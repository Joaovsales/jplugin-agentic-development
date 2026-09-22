"""Idempotent create-or-update for one task, addressed by its stable ID.

`publish` mints provider tasks for rows that already exist in the index. Nothing
could put a row *there* without a human typing it, so a skill that discovers
durable work at runtime — documentation debt, an unresolved behavioral question —
had no way to record it except by hand-writing Markdown in the index's format.
Two consequences, both bad: the format gets copied into skills that then drift
from it, and "record this once" turns into "append every time it runs".

So this module owns the operation `publish` cannot express: *given an ID, make
exactly one task exist with this content*. Running it twice updates; running it
against a closed task reopens, because the same question recurring is the same
question.

Provider-neutral by construction. Where the canonical body lands is
:func:`resolve_destination`'s decision, and it never widens the write policy the
project already set.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import List, Optional, Tuple

from .index import load_index_strict, render_row
from .model import Task, is_valid_id, slugify_id
from .providers.base import ProviderError, ProviderUnavailable, preserve_labels
from .routines import is_escalated

#: Where a task's canonical body lives once this command has run.
EXTERNAL = "external"
LOCAL = "local"
LOCAL_PENDING = "local-pending"

TERMINAL = ("done", "cancelled")


class UpsertDisposition(str, Enum):
    """Stable machine outcomes returned to escalation callers."""

    PREVIEW = "preview"
    EXTERNAL = EXTERNAL
    LOCAL = LOCAL
    LOCAL_PENDING = LOCAL_PENDING
    EXISTING_HELD = "existing-held"
    EXISTING_TERMINAL = "existing-terminal"
    FAILED = "failed"
    UNKNOWN = "unknown"

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class UpsertResult:
    """Machine-readable persistence outcome with compatible legacy rendering."""

    disposition: UpsertDisposition
    task: Optional[Task] = None
    readback: Optional[Task] = None
    detail: str = ""
    lines: Tuple[str, ...] = ()
    code: int = 0

    def reference_summary(self) -> str:
        """Render the confirmed destination without exposing outcome branching."""
        if self.task is None:
            return "unconfirmed"
        if self.disposition is UpsertDisposition.LOCAL_PENDING:
            return f"{self.task.id} (publication pending)"
        return self.task.external.display() if self.task.external else self.task.id


def resolve_destination(provider_name: str, gate, reachable: bool) -> str:
    """Decide where the canonical body belongs. Pure, so it is testable alone.

    Three rules, in order:

    * A project with no tracker has nothing to publish *to*; the local record is
      simply canonical, not a degraded copy of something better.
    * An external provider is written only when the project's existing write
      policy already permits it. This command never relaxes that policy — an
      unattended wrap-up must not be the thing that decides an approval gate
      does not apply tonight.
    * Otherwise the work is kept locally and the pending publication is
      reported. Failing instead would discard documentation debt to protect a
      tracker, which is the wrong thing to protect.

    Reads the **policy** only — `gate.approved or not gate.require_approval` —
    and deliberately not `gate.open`, which also folds in the dry-run flag.
    Destination is a property of the project's configuration, not of whether
    this particular invocation intends to write; conflating them would make the
    preview describe a different run than the one `--apply` performs, and the
    preview is the artifact a human reads before authorizing the write.
    """
    if provider_name == LOCAL:
        return LOCAL
    if not reachable:
        return LOCAL_PENDING
    permitted = gate.approved or not gate.require_approval
    return EXTERNAL if permitted else LOCAL_PENDING


def derive_id(namespace: str, path: str, title: str = "") -> str:
    """Mint the stable ID for a task *about* a repository path.

    `title` is folded in only when given: a sweep files several findings against
    one file and needs the short title to tell them apart, while a spec
    reconciliation task is one-per-spec and keeps the two-part ID it always had.

    Idempotence depends entirely on two runs producing the same ID, and a rule
    that lives only in prose is a rule each caller re-derives by hand. Both
    `spec-reconciliation.feature-c` and `spec-reconciliation.specs-feature-c-md`
    satisfy `is_valid_id`, so a caller who normalizes differently mints a second
    task instead of updating the first — silently, and only on the second run.

    Exposing the derivation makes the mismatch unrepresentable rather than
    merely discouraged.
    """
    return slugify_id(namespace, path, title)


def _local_provider(config, gate):
    """A local writer, regardless of which provider the project selected."""
    from .providers.local import LocalMarkdownProvider

    return LocalMarkdownProvider(config, gate)


def _existing(provider, task_id: str, reference=None) -> Optional[Task]:
    """The task this ID already names, or None if it does not exist yet.

    A provider that *fails to answer* is not the same as one answering "no", so
    the error propagates. Reading a listing failure as absence is precisely how
    a re-run creates the duplicate this command exists to prevent.
    """
    if reference is not None and reference.provider == provider.name:
        return provider.get_task(reference)
    return next((t for t in provider.list_tasks() if t.id == task_id), None)


#: Fields this command owns: the caller recomputes them from scratch each run,
#: so the incoming value replaces whatever is on disk.
#: Everything else belongs to whoever is *working* the task. Overwriting those
#: with a fresh `Task`'s defaults is not an update, it is state loss — a task a
#: human moved to `in_progress` would silently return to `open` on every wrap-up,
#: and an `external` address dropped here makes the next `update_task` fail
#: because the record no longer knows where it lives.
#: `evidence` is neither: it accretes, see `_accreted`.
CARRIED_FROM_EXISTING = ("created_at", "external", "priority", "depends_on", "parent", "area")


def _merge(existing: Optional[Task], incoming: Task) -> Tuple[Task, str]:
    """Fold new content into whatever this ID already holds.

    A closed task reopening is reported separately from an ordinary update: it
    is the signal that a question everyone believed settled came back, and a
    reader who sees only "updated" would not go looking for why.
    """
    if existing is None:
        return incoming, "created"
    carried = {name: getattr(existing, name) for name in CARRIED_FROM_EXISTING}
    carried["evidence"] = _accreted(existing.evidence, incoming.evidence)
    carried["labels"] = tuple(preserve_labels(existing.labels, incoming.labels))
    if existing.status in TERMINAL:
        return incoming.with_(status="open", **carried), "reopened"
    return incoming.with_(status=existing.status, **carried), "updated"


def _accreted(existing: tuple, incoming: tuple) -> tuple:
    """Evidence accretes across runs: each sighting is a witness, not a
    replacement. Order is kept and an entry seen before is not repeated."""
    seen = list(existing)
    seen += [entry for entry in incoming if entry not in seen]
    return tuple(seen)


def _merge_blocker(existing: Optional[Task], incoming: Task) -> Tuple[Task, str]:
    """Merge fresh evidence while freezing an existing blocker's identity/routing."""
    merged, action = _merge(existing, incoming)
    if existing is None:
        return merged, action
    return merged.with_(
        title=existing.title,
        source_path=existing.source_path,
        kind=existing.kind,
    ), action


def _persist(target, task: Task, existing: Optional[Task]) -> Task:
    """Write the task and return the record the provider actually wrote.

    The return value is load-bearing, not decoration: providers enrich the task
    with an :class:`ExternalRef` naming where the body landed, and that ref is
    what `render_row` turns into the index's link. Rendering the row from the
    *input* task instead silently produces a row that indexes nothing.
    """
    if existing is None:
        return target.create_task(task)
    return target.update_task(task)


def _published_ref(config, task_id: str):
    """The external address the index already records for this ID, if any.

    When the provider is unreachable or its approval gate is shut, the canonical
    body falls back to the local store — which has never heard of a task that was
    published to GitHub on an earlier run. Left alone, the merge carries
    `external=None` and :func:`_sync_index` rewrites the row *without* its link:
    the issue still exists upstream, but nothing in the repository points at it
    any more, and the next reachable run mints a second one.

    The index is the only place that remembers, so it is where we look.
    """
    row = load_index_strict(config.path(config.index_path), config.index_path).by_id(task_id)
    return None if row is None else row.task.external


def _seeded_from_row(index, existing: Optional[Task], task: Task) -> Task:
    """A row filed ahead of its task is the only record of its status and blockers.

    `/slice --file` seeds the compact row -- `[x]` for a slice already built,
    `(blocked-by: ...)` for its ordering -- before the task it names exists
    anywhere else. `_existing` reads the provider, so without this the task
    would be created `open` with no `depends_on`, and the very first refresh
    would rewrite the seeded row from that record: a finished slice back to
    `[ ]`, its marker gone. Seeding the incoming task from the row, once, before
    the merge, lets `_sync_index` stay a pure render of the task.
    """
    row = index.by_id(task.id) if existing is None else None
    if row is None:
        return task
    return task.with_(status=row.task.status, depends_on=_accreted(row.task.depends_on, task.depends_on))


def _sync_index(config, task: Task) -> str:
    """Add or refresh the one compact row that points at this task."""
    index = load_index_strict(config.path(config.index_path), config.index_path)
    row = index.by_id(task.id)
    if row is None:
        index.append_row(task)
        outcome = "row added"
    else:
        index.replace_row(row.line, render_row(task, row.indent))
        outcome = "row refreshed"
    index.save()
    return outcome


def upsert_task_result(registry, task: Task, apply: bool) -> UpsertResult:
    """Persist for escalation callers, preserving human-owned existing tasks."""
    return _upsert_task_result(registry, task, apply, preserve_existing=True)


def upsert_task(
    registry, task: Task, apply: bool, parent_ref: Optional[str] = None
) -> Tuple[List[str], int]:
    """Compatible human-oriented wrapper, including legacy reopen behavior."""
    result = _upsert_task_result(registry, task, apply, preserve_existing=False, parent_ref=parent_ref)
    return list(result.lines), result.code


def _preview_parent_line(provider, parent_ref: str) -> str:
    """Decided from capabilities alone -- a dry run must not touch the provider."""
    how = "native" if provider.capabilities.native_hierarchy else "parent: metadata"
    return f"upsert: would link parent {parent_ref} ({how} on {provider.name})"


def _link_parent_line(registry, target, written: Task, status, provider, parent_ref: str) -> Tuple[str, bool]:
    """Apply-time parent link. Returns the report line and whether it is a hard failure.

    An unreachable provider is not a hard failure: the body is already canonical
    locally, and the pending link is reported the same way a pending publication
    is -- never retried silently. Any other failure (bad reference, wrong
    provider, a write the target refuses) is the command's own job to report,
    so it is translated into a line here rather than left to propagate as a
    traceback.
    """
    if not status.available:
        return f"upsert: parent link pending — {provider.name} is unreachable", False
    from .escalation import EscalationError, _authoritative_parent  # lazy: avoids the import cycle

    try:
        parent = _authoritative_parent(registry, parent_ref)
        link = target.link_parent(written, parent)
    except (EscalationError, ProviderError, ProviderUnavailable) as exc:
        return f"upsert: parent {parent_ref} — {exc}", True
    parent_display = parent.external.display() if parent.external else parent.id
    how = "linked natively" if link.native else f"stored as metadata — {link.detail}"
    return f"upsert: parent {parent_display} {how}", False


def _upsert_task_result(
    registry, task: Task, apply: bool, preserve_existing: bool, parent_ref: Optional[str] = None
) -> UpsertResult:
    if not is_valid_id(task.id):
        line = f"upsert: {task.id!r} is not a valid task id"
        return UpsertResult(UpsertDisposition.FAILED, detail=line, lines=(line,), code=2)

    config, provider = registry.config, registry.provider
    gate = provider.gate
    # Before the provider is touched at all. AC-19 requires the refusal to precede
    # *any* provider write, and the two index reads below are both incidental: one
    # is skipped on the external path, the other runs after `_persist`. Loading
    # here is what makes the guarantee unconditional -- and makes the dry run
    # refuse identically, so the preview describes the run `--apply` performs.
    index = load_index_strict(config.path(config.index_path), config.index_path)
    try:
        status = provider.discover()
        destination = resolve_destination(provider.name, gate, status.available)
        target = provider if destination == EXTERNAL else _local_provider(config, gate)
        published = _published_ref(config, task.id)
        lookup = published if destination == EXTERNAL else None
        existing = _existing(target, task.id, lookup)
    except (ProviderError, ProviderUnavailable) as exc:
        line = f"upsert: cannot establish whether {task.id} already exists: {exc}"
        return UpsertResult(UpsertDisposition.FAILED, detail=str(exc), lines=(line,), code=1)
    task = _seeded_from_row(index, existing, task)

    preserved = _preserved_result(existing, config) if preserve_existing else None
    if preserved is not None:
        return preserved
    merge = _merge_blocker if preserve_existing else _merge
    merged, action = merge(existing, task)
    if published is not None and published.provider == provider.name:
        merged = merged.with_(external=published)

    if not apply:
        # The applied line reports what happened ("created"); the preview reports
        # what would happen, and reads as a typo in the past tense.
        intent = {"created": "create", "updated": "update", "reopened": "reopen"}[action]
        line = f"upsert: would {intent} {merged.id} ({destination}); index row would be synced"
        preview_lines = (line, _preview_parent_line(provider, parent_ref)) if parent_ref else (line,)
        return UpsertResult(UpsertDisposition.PREVIEW, task=merged, detail=line, lines=preview_lines)

    if preserve_existing:
        try:
            existing = _existing(target, task.id, lookup)
        except (ProviderError, ProviderUnavailable) as exc:
            line = f"upsert: cannot refresh {task.id} before persistence: {exc}"
            return UpsertResult(UpsertDisposition.FAILED, detail=str(exc), lines=(line,), code=1)
        preserved = _preserved_result(existing, config)
        if preserved is not None:
            return preserved
        merged, action = _merge_blocker(existing, task)
        if published is not None and published.provider == provider.name:
            merged = merged.with_(external=published)

    try:
        written = _persist(target, merged, existing)
    except (ProviderError, ProviderUnavailable) as exc:
        # The record is the whole point of the command, so failing to write it is
        # a failure of the command — never a warning attached to a success.
        return _persist_failure(merged, destination, existing, exc)
    except Exception as exc:
        if not preserve_existing:
            raise
        return _persist_failure(merged, destination, existing, exc)

    if preserve_existing:
        return _structured_success(config, target, destination, action, written)

    lines = [f"upsert: {action} {written.id} ({destination}); {_sync_index(config, written)}"]
    if destination == LOCAL_PENDING:
        lines.append(
            f"upsert: external publication pending — {provider.name} "
            f"{'is unreachable' if not status.available else 'requires approval'}; "
            "the local record is canonical until it is published"
        )
    code = 0
    if parent_ref:
        parent_line, parent_failed = _link_parent_line(registry, target, written, status, provider, parent_ref)
        lines.append(parent_line)
        code = 1 if parent_failed else code
    return UpsertResult(UpsertDisposition(destination), task=written, readback=written, lines=tuple(lines), code=code)


def _preserved_result(existing: Optional[Task], config) -> Optional[UpsertResult]:
    if existing is None:
        return None
    if existing.status in TERMINAL:
        disposition = UpsertDisposition.EXISTING_TERMINAL
    elif is_escalated(existing.labels, config):
        disposition = UpsertDisposition.EXISTING_HELD
    else:
        return None
    detail = f"upsert: preserved {existing.id} ({disposition}); human review required"
    return UpsertResult(disposition, task=existing, readback=existing, detail=detail, lines=(detail,))


def _persist_failure(task, destination, existing, exc: Exception) -> UpsertResult:
    unknown = destination == EXTERNAL and existing is None
    disposition = UpsertDisposition.UNKNOWN if unknown else UpsertDisposition.FAILED
    line = f"upsert: could not persist {task.id}: {exc}"
    return UpsertResult(disposition, task=task, detail=str(exc), lines=(line,), code=1)


def _structured_success(config, target, destination, action, written) -> UpsertResult:
    try:
        readback = _existing(target, written.id, written.external)
    except (ProviderError, ProviderUnavailable) as exc:
        line = f"upsert: {action} {written.id} ({destination}); authoritative readback failed: {exc}"
        return UpsertResult(UpsertDisposition(destination), task=written, detail=str(exc), lines=(line,), code=1)
    if readback is None:
        detail = "authoritative readback did not find the persisted task"
        line = f"upsert: {action} {written.id} ({destination}); {detail}"
        return UpsertResult(UpsertDisposition(destination), task=written, detail=detail, lines=(line,), code=1)
    authoritative = readback
    if destination == LOCAL_PENDING and written.external is not None:
        authoritative = readback.with_(external=written.external)
    preserved = _preserved_result(readback, config)
    disposition = preserved.disposition if preserved else UpsertDisposition(destination)
    try:
        index_outcome = _sync_index(config, authoritative)
    except Exception as exc:
        line = f"upsert: {action} {written.id} ({destination}); index sync failed: {exc}"
        return UpsertResult(disposition, task=written, readback=authoritative, detail=str(exc), lines=(line,), code=1)
    lines = [f"upsert: {action} {written.id} ({destination}); {index_outcome}"]
    if destination == LOCAL_PENDING:
        lines.append("upsert: external publication pending; the local record is canonical")
    return UpsertResult(disposition, task=written, readback=authoritative, lines=tuple(lines))
