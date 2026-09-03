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

from typing import List, Optional, Tuple

from .index import load_index, render_row
from .model import Task, is_valid_id, slugify_id
from .providers.base import ProviderError, ProviderUnavailable

#: Where a task's canonical body lives once this command has run.
EXTERNAL = "external"
LOCAL = "local"
LOCAL_PENDING = "local-pending"

TERMINAL = ("done", "cancelled")


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


def derive_id(namespace: str, path: str) -> str:
    """Mint the stable ID for a task *about* a repository path.

    Idempotence depends entirely on two runs producing the same ID, and a rule
    that lives only in prose is a rule each caller re-derives by hand. Both
    `spec-reconciliation.feature-c` and `spec-reconciliation.specs-feature-c-md`
    satisfy `is_valid_id`, so a caller who normalizes differently mints a second
    task instead of updating the first — silently, and only on the second run.

    Exposing the derivation makes the mismatch unrepresentable rather than
    merely discouraged.
    """
    return slugify_id(namespace, path)


def _local_provider(config, gate):
    """A local writer, regardless of which provider the project selected."""
    from .providers.local import LocalMarkdownProvider

    return LocalMarkdownProvider(config, gate)


def _existing(provider, task_id: str) -> Optional[Task]:
    """The task this ID already names, or None if it does not exist yet.

    A provider that *fails to answer* is not the same as one answering "no", so
    the error propagates. Reading a listing failure as absence is precisely how
    a re-run creates the duplicate this command exists to prevent.
    """
    return next((t for t in provider.list_tasks() if t.id == task_id), None)


#: Fields this command owns: the caller recomputes them from scratch each run,
#: so the incoming value replaces whatever is on disk.
#: Everything else belongs to whoever is *working* the task. Overwriting those
#: with a fresh `Task`'s defaults is not an update, it is state loss — a task a
#: human moved to `in_progress` would silently return to `open` on every wrap-up,
#: and an `external` address dropped here makes the next `update_task` fail
#: because the record no longer knows where it lives.
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
    if existing.status in TERMINAL:
        return incoming.with_(status="open", **carried), "reopened"
    return incoming.with_(status=existing.status, **carried), "updated"


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
    row = load_index(config.path(config.index_path), config.index_path).by_id(task_id)
    return None if row is None else row.task.external


def _sync_index(config, task: Task) -> str:
    """Add or refresh the one compact row that points at this task."""
    index = load_index(config.path(config.index_path), config.index_path)
    row = index.by_id(task.id)
    if row is None:
        index.append_row(task)
        outcome = "row added"
    else:
        index.replace_row(row.line, render_row(task, row.indent))
        outcome = "row refreshed"
    index.save()
    return outcome


def upsert_task(registry, task: Task, apply: bool) -> Tuple[List[str], int]:
    """Make exactly one task exist with this content. Returns (lines, exit code)."""
    if not is_valid_id(task.id):
        return ([f"upsert: {task.id!r} is not a valid task id"], 2)

    config, provider = registry.config, registry.provider
    gate = provider.gate
    try:
        status = provider.discover()
        destination = resolve_destination(provider.name, gate, status.available)
        target = provider if destination == EXTERNAL else _local_provider(config, gate)
        existing = _existing(target, task.id)
    except (ProviderError, ProviderUnavailable) as exc:
        return ([f"upsert: cannot establish whether {task.id} already exists: {exc}"], 1)
    merged, action = _merge(existing, task)
    if destination != EXTERNAL and merged.external is None:
        merged = merged.with_(external=_published_ref(config, task.id))

    if not apply:
        # The applied line reports what happened ("created"); the preview reports
        # what would happen, and reads as a typo in the past tense.
        intent = {"created": "create", "updated": "update", "reopened": "reopen"}[action]
        return ([f"upsert: would {intent} {merged.id} ({destination}); index row would be synced"], 0)

    try:
        written = _persist(target, merged, existing)
    except (ProviderError, ProviderUnavailable) as exc:
        # The record is the whole point of the command, so failing to write it is
        # a failure of the command — never a warning attached to a success.
        return ([f"upsert: could not persist {merged.id}: {exc}"], 1)

    lines = [f"upsert: {action} {written.id} ({destination}); {_sync_index(config, written)}"]
    if destination == LOCAL_PENDING:
        lines.append(
            f"upsert: external publication pending — {provider.name} "
            f"{'is unreachable' if not status.available else 'requires approval'}; "
            "the local record is canonical until it is published"
        )
    return (lines, 0)
