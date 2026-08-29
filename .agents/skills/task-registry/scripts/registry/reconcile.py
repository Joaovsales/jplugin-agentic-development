"""Reconciliation, frontier, and progressive disclosure.

The registry's contract with the reader is that a run costs a bounded number of
lines. `reconcile` prints counts and one line per divergence; the body of any
task is one `show <task-id>` away and never arrives unasked. That is the whole
reason `tasks/todo.md` can stay small enough to load every session.

Direction of writes is fixed and narrow:

* `pull`     external -> local. Local writes only.
* `publish`  local -> external. Gated on `--apply`.
* `reconcile` reports both directions; `--apply` performs only the local half.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

from .index import IndexRow, Problem, TaskIndex, load_index, render_row
from .model import TERMINAL_STATUSES, Task
from .providers.base import ProviderError, ProviderStatus, ProviderUnavailable, TrackerProvider

SUPERSEDED_RE = re.compile(r"^>\s*Superseded by:\s*(?P<by>.+)$", re.MULTILINE | re.IGNORECASE)
MAX_LINES_PER_CATEGORY = 20


@dataclass(frozen=True)
class Finding:
    """One divergence. `category` is what the summary counts by."""

    category: str
    task_id: str
    message: str
    detail: str = ""

    def render(self) -> str:
        who = self.task_id or "(no id)"
        return f"  {who}: {self.message}"


@dataclass
class Report:
    command: str
    provider: str
    provider_status: Optional[ProviderStatus] = None
    selection_reason: str = ""
    findings: List[Finding] = field(default_factory=list)
    problems: List[Problem] = field(default_factory=list)
    limitations: List[str] = field(default_factory=list)
    failures: List[str] = field(default_factory=list)
    actions: List[str] = field(default_factory=list)
    applied: bool = False

    def add(self, category: str, task_id: str, message: str, detail: str = "") -> None:
        self.findings.append(Finding(category, task_id, message, detail))

    @property
    def exit_code(self) -> int:
        return 1 if self.failures or self.problems else 0

    def counts(self) -> Dict[str, int]:
        tally: Dict[str, int] = {}
        for finding in self.findings:
            tally[finding.category] = tally.get(finding.category, 0) + 1
        return tally

    def render(self, verbose: bool = False) -> str:
        """Summary first. Always."""
        lines = [f"task-registry {self.command} — provider: {self.provider}"]
        if self.selection_reason:
            lines.append(f"  selected because: {self.selection_reason}")
        if self.provider_status is not None and not self.provider_status.available:
            lines.append(f"  provider unavailable: {self.provider_status.detail}")
        lines.append(
            "  mode: applied" if self.applied else "  mode: dry-run (no changes written)"
        )
        tally = self.counts()
        if tally:
            lines.append("")
            lines.append("Summary:")
            for category in sorted(tally):
                lines.append(f"  {category}: {tally[category]}")
        else:
            lines.append("")
            lines.append("Summary: nothing to reconcile — local index and provider agree")
        lines += self._detail_lines(verbose)
        if self.actions:
            lines.append("")
            lines.append("Actions:")
            lines += [f"  {action}" for action in self.actions]
        if self.limitations:
            lines.append("")
            lines.append("Provider limitations (not silently absorbed):")
            lines += [f"  - {item}" for item in self.limitations]
        if self.problems:
            lines.append("")
            lines.append("Malformed input (reported, nothing dropped):")
            lines += [f"  - {problem.render()}" for problem in self.problems]
        if self.failures:
            lines.append("")
            lines.append("Failures:")
            lines += [f"  - {failure}" for failure in self.failures]
        if self.findings:
            lines.append("")
            lines.append("Run `task-registry show <task-id>` for the full detail of any task.")
        return "\n".join(lines)

    def _detail_lines(self, verbose: bool) -> List[str]:
        lines: List[str] = []
        by_category: Dict[str, List[Finding]] = {}
        for finding in self.findings:
            by_category.setdefault(finding.category, []).append(finding)
        for category in sorted(by_category):
            entries = by_category[category]
            lines.append("")
            lines.append(f"{category}:")
            shown = entries if verbose else entries[:MAX_LINES_PER_CATEGORY]
            lines += [entry.render() for entry in shown]
            if len(entries) > len(shown):
                lines.append(f"  … {len(entries) - len(shown)} more (pass --verbose)")
        return lines


class Registry:
    """Orchestrates the local index, the specs, and one provider."""

    def __init__(self, config, provider: TrackerProvider, selection_reason: str = "") -> None:
        self.config = config
        self.provider = provider
        self.selection_reason = selection_reason

    # ------------------------------------------------------------------ loading
    def local_index(self) -> TaskIndex:
        return load_index(self.config.path(self.config.index_path), self.config.index_path)

    def external_tasks(self, report: Report) -> List[Task]:
        """Read the provider, degrading loudly rather than failing the whole run."""
        status = self.provider.discover()
        report.provider_status = status
        if not status.available:
            if self.config.offline_reads == "fail":
                report.failures.append(f"provider unreachable: {status.detail}")
            else:
                report.limitations.append(
                    f"reads degraded to local-only: {status.detail}"
                )
            return []
        try:
            return self.provider.list_tasks()
        except (ProviderError, ProviderUnavailable) as exc:
            report.failures.append(str(exc))
            return []

    # -------------------------------------------------------------- reconcile
    def reconcile(self, apply: bool = False) -> Report:
        report = Report("reconcile", self.provider.name, selection_reason=self.selection_reason)
        index = self.local_index()
        report.problems.extend(index.problems)
        external = self.external_tasks(report)

        self._report_identity_gaps(index, report)
        self._report_link_gaps(index, external, report)
        self._report_duplicates(index, external, report)
        self._report_specs(index, external, report)
        self._collect_limitations(report)

        if apply:
            report.applied = True
            self._apply_local_updates(index, external, report)
        return report

    def _report_identity_gaps(self, index: TaskIndex, report: Report) -> None:
        for row in index.rows:
            if row.legacy and row.task.status not in TERMINAL_STATUSES:
                report.add(
                    "missing-id",
                    "",
                    f"{self.config.index_path}:{row.line} '{_short(row.task.title)}' has no "
                    "stable task-id — run `task-registry migrate --apply` to mint one",
                )

    def _report_link_gaps(
        self, index: TaskIndex, external: Sequence[Task], report: Report
    ) -> None:
        by_id = {task.id: task for task in external if task.id}
        by_ref = {task.external.id: task for task in external if task.external}
        for row in index.rows:
            task = row.task
            if task.status in TERMINAL_STATUSES:
                continue
            match = self._match_external(task, by_id, by_ref)
            if match is None and task.external is None:
                report.add(
                    "unlinked-local",
                    task.id,
                    f"'{_short(task.title)}' exists only locally — "
                    "`task-registry publish --apply` would create it",
                )
            elif match is None and task.external is not None:
                report.add(
                    "orphaned-link",
                    task.id,
                    f"links to {task.external.display()} which the provider does not return "
                    "— left untouched for a human to resolve",
                )
            elif match.status != task.status:
                report.add(
                    "status-drift",
                    task.id or match.id,
                    f"local '{task.status}' vs provider '{match.status}' "
                    f"({match.external.display() if match.external else 'n/a'})",
                )
        local_ids = {row.task.id for row in index.rows if row.task.id}
        local_refs = {
            row.task.external.id for row in index.rows if row.task.external is not None
        }
        for task in external:
            if task.status in TERMINAL_STATUSES:
                continue
            if task.id and task.id in local_ids:
                continue
            if task.external is not None and task.external.id in local_refs:
                continue
            report.add(
                "unlinked-external",
                task.id,
                f"'{_short(task.title)}' ({task.external.display() if task.external else '?'}) "
                "has no row in the local index — `task-registry pull --apply` adds one",
            )

    @staticmethod
    def _match_external(
        task: Task, by_id: Dict[str, Task], by_ref: Dict[str, Task]
    ) -> Optional[Task]:
        """Identity is the stable ID or a recorded reference. Never the title."""
        if task.id and task.id in by_id:
            return by_id[task.id]
        if task.external is not None and task.external.id in by_ref:
            return by_ref[task.external.id]
        return None

    def _report_duplicates(
        self, index: TaskIndex, external: Sequence[Task], report: Report
    ) -> None:
        seen: Dict[str, int] = {}
        for row in index.rows:
            if not row.task.id:
                continue
            seen[row.task.id] = seen.get(row.task.id, 0) + 1
        for task_id, count in seen.items():
            if count > 1:
                report.add("duplicate-id", task_id, f"appears on {count} rows of the local index")
        external_ids: Dict[str, List[str]] = {}
        for task in external:
            if task.id:
                external_ids.setdefault(task.id, []).append(
                    task.external.display() if task.external else "?"
                )
        for task_id, refs in external_ids.items():
            if len(refs) > 1:
                report.add(
                    "duplicate-id", task_id, f"claimed by {len(refs)} provider tasks: {', '.join(refs)}"
                )
        self._report_title_collisions(index, external, report)

    @staticmethod
    def _report_title_collisions(
        index: TaskIndex, external: Sequence[Task], report: Report
    ) -> None:
        """Advisory only. Two tasks may legitimately share a title."""
        titles: Dict[str, List[str]] = {}
        for task in [row.task for row in index.rows] + list(external):
            if task.status in TERMINAL_STATUSES:
                continue
            titles.setdefault(task.title.strip().lower(), []).append(task.id or "(no id)")
        for title, ids in titles.items():
            if len(ids) > 1 and len(set(ids)) > 1:
                report.add(
                    "possible-duplicate",
                    "",
                    f"'{_short(title)}' is used by {', '.join(sorted(set(ids)))} — advisory "
                    "only: a matching title is not identity, confirm before merging",
                )

    def _report_specs(self, index: TaskIndex, external: Sequence[Task], report: Report) -> None:
        index_text = _safe_read(self.config.path(self.config.index_path))
        linked = {task.spec_path for task in external if task.spec_path}
        for spec in _scan_specs(self.config):
            referenced = spec.path in index_text or spec.path in linked
            if spec.state == "superseded":
                report.add(
                    "superseded-spec", "", f"{spec.path} declares: superseded by {spec.superseded_by}"
                )
            elif spec.state == "completed" and referenced:
                report.add(
                    "completed-spec",
                    "",
                    f"{spec.path} is filed as completed but is still referenced by an open row",
                )
            elif spec.state == "pending" and not referenced:
                report.add(
                    "stale-spec",
                    "",
                    f"{spec.path} is pending with no task referencing it — "
                    "classify it, do not delete it",
                )

    def _collect_limitations(self, report: Report) -> None:
        for item in getattr(self.provider, "limitations", []):
            if item not in report.limitations:
                report.limitations.append(item)
        capabilities = self.provider.capabilities
        if not capabilities.native_dependencies:
            report.limitations.append(
                f"{self.provider.name}: no native dependency links — dependencies are preserved "
                "in task metadata and reported as inferred"
            )
        if not capabilities.native_hierarchy:
            report.limitations.append(
                f"{self.provider.name}: no native parent/child link — hierarchy is preserved "
                "in task metadata and reported as inferred"
            )

    def _apply_local_updates(
        self, index: TaskIndex, external: Sequence[Task], report: Report
    ) -> None:
        """The local half of reconciliation: statuses and links, nothing else."""
        by_id = {task.id: task for task in external if task.id}
        by_ref = {task.external.id: task for task in external if task.external}
        changed = 0
        for row in index.rows:
            match = self._match_external(row.task, by_id, by_ref)
            if match is None:
                continue
            updated = row.task.with_(
                status=self._reconciled_status(row.task, match, report),
                external=match.external,
                summary=row.task.summary or match.summary,
                id=row.task.id or match.id,
            )
            rendered = render_row(updated, row.indent)
            if rendered != row.raw:
                index.replace_row(row.line, rendered)
                changed += 1
        if changed:
            index.save()
        report.actions.append(f"updated {changed} local row(s) from provider state")

    def _reconciled_status(self, local: Task, match: Task, report: Report) -> str:
        """Provider state wins, except where the provider cannot hold the answer.

        GitHub only knows open and closed. Overwriting a local `in_progress` or
        `blocked` with the `open` that state maps to would erase the one fact the
        provider was never able to store — so the local value is kept and the
        divergence is reported instead of resolved.
        """
        richer = ("in_progress", "blocked")
        if local.status not in richer or match.status in TERMINAL_STATUSES:
            return match.status
        if match.status in richer or local.status in self.config.status_sources:
            return match.status
        report.add(
            "status-kept-local",
            local.id,
            f"kept local '{local.status}' — {self.provider.name} reports "
            f"'{match.status}' and has no way to express '{local.status}'",
        )
        return local.status

    # ---------------------------------------------------------------- publish
    def publish(self, apply: bool = False) -> Report:
        report = Report("publish", self.provider.name, selection_reason=self.selection_reason)
        report.applied = apply
        index = self.local_index()
        report.problems.extend(index.problems)
        external = self.external_tasks(report)
        if apply and report.provider_status is not None and not report.provider_status.available:
            # Degrading a *read* to local-only is a service. Degrading a write is
            # data loss with a success message, so this stops instead.
            report.failures.append(
                f"refusing to publish: {self.provider.name} is unreachable — "
                f"{report.provider_status.detail}"
            )
            return report
        if self.provider.result_truncated:
            report.failures.append(
                f"refusing to publish: {self.provider.name} returned a truncated task list, "
                "so an unseen task could be created a second time"
            )
            return report
        by_id = {task.id: task for task in external if task.id}
        by_ref = {task.external.id: task for task in external if task.external}
        published_rows: Dict[str, Task] = {}

        created = 0
        for row in index.rows:
            task = row.task
            if task.status in TERMINAL_STATUSES:
                continue
            if not task.id:
                # Publishing an ID-less row would create a task nothing can be
                # matched back to, so it is skipped — but skipping in silence is
                # how work goes missing, so it is reported like any divergence.
                report.add(
                    "skipped-no-id",
                    "",
                    f"{self.config.index_path}:{row.line} '{_short(task.title)}' has no "
                    "stable task-id — not published; run `task-registry migrate --apply` first",
                )
                continue
            if self._match_external(task, by_id, by_ref) is not None:
                continue
            if not apply:
                report.add("would-create", task.id, f"create provider task for '{_short(task.title)}'")
                continue
            try:
                published = self.provider.create_task(task)
            except (ProviderError, ProviderUnavailable) as exc:
                report.failures.append(f"{task.id}: {exc}")
                continue
            index.replace_row(row.line, render_row(published, row.indent))
            published_rows[task.id] = published
            created += 1
            report.add("created", task.id, f"-> {published.external.display()}")
        if created:
            index.save()
            report.actions.append(f"created {created} provider task(s) and linked them locally")
        self._link_dependencies(index, published_rows, external, apply, report)
        self._collect_limitations(report)
        return report

    def _link_dependencies(
        self,
        index: TaskIndex,
        published: Dict[str, Task],
        external: Sequence[Task],
        apply: bool,
        report: Report,
    ) -> None:
        # `index.rows` is a snapshot taken before this run created anything, so a
        # task published a moment ago still reads as unlinked there. The freshly
        # published records are layered over it, otherwise a first publish links
        # nothing and reports nothing.
        rows = {row.task.id: row.task for row in index.rows if row.task.id}
        rows.update(published)
        recorded = {task.id: set(task.depends_on) for task in external if task.id}
        for task in rows.values():
            for dependency_id in task.depends_on:
                target = rows.get(dependency_id)
                if target is None:
                    report.add(
                        "unknown-dependency",
                        task.id,
                        f"declares blocked-by {dependency_id}, which is not in the index",
                    )
                    continue
                if not apply or task.external is None or target.external is None:
                    continue
                if dependency_id in recorded.get(task.id, ()):
                    continue  # already recorded provider-side; re-linking is noise
                try:
                    result = self.provider.add_dependency(task, target)
                except (ProviderError, ProviderUnavailable) as exc:
                    report.failures.append(f"{task.id} -> {dependency_id}: {exc}")
                    continue
                report.add("dependency", task.id, result.render())

    # ------------------------------------------------------------------- pull
    def pull(self, apply: bool = False) -> Report:
        report = Report("pull", self.provider.name, selection_reason=self.selection_reason)
        report.applied = apply
        index = self.local_index()
        report.problems.extend(index.problems)
        external = self.external_tasks(report)
        local_ids = {row.task.id for row in index.rows if row.task.id}
        local_refs = {row.task.external.id for row in index.rows if row.task.external}

        added = 0
        for task in external:
            if task.status in TERMINAL_STATUSES:
                continue
            if task.id in local_ids or (task.external and task.external.id in local_refs):
                continue
            if not apply:
                report.add("would-add-row", task.id, f"add index row for '{_short(task.title)}'")
                continue
            index.append_row(task)
            added += 1
            report.add("added-row", task.id, f"'{_short(task.title)}'")
        if apply:
            self._apply_local_updates(index, external, report)
            if added:
                index.save()
                report.actions.append(f"added {added} row(s) to {self.config.index_path}")
        self._collect_limitations(report)
        return report

    # --------------------------------------------------------------- frontier
    def frontier(self) -> Report:
        report = Report("frontier", self.provider.name, selection_reason=self.selection_reason)
        index = self.local_index()
        report.problems.extend(index.problems)
        tasks = _merge(index.rows, self.external_tasks(report))
        status_by_id = {task.id: task.status for task in tasks if task.id}
        known_ids = set(status_by_id)

        ordered, cycles = _dependency_order(tasks)
        for members in cycles:
            report.failures.append(
                "dependency cycle — no task in it can ever become ready: "
                + " -> ".join(members + members[:1])
            )
        for task in ordered:
            if task.status in TERMINAL_STATUSES:
                continue
            missing = [d for d in task.depends_on if d not in known_ids]
            if missing:
                # A dependency naming nothing is not a satisfied dependency. It is
                # a dangling reference, and reading it as "ready" would let the
                # frontier hand out work whose real blocker is invisible.
                report.add(
                    "unknown-dependency",
                    task.id,
                    f"waits on {', '.join(missing)}, which no task in this registry "
                    "defines — resolve the reference before treating it as ready",
                )
            blockers = [
                dependency
                for dependency in task.depends_on
                if status_by_id.get(dependency, "open") not in TERMINAL_STATUSES
            ]
            if blockers:
                report.add(
                    "blocked", task.id, f"'{_short(task.title)}' waits on {', '.join(blockers)}"
                )
            else:
                report.add(
                    "ready",
                    task.id,
                    f"[{task.priority or 'unset'}] '{_short(task.title)}'"
                    + (f" ({task.external.display()})" if task.external else ""),
                )
        return report

    # ------------------------------------------------------- progressive detail
    def show(self, task_id: str) -> Tuple[str, int]:
        """The only command that prints a full task. Detail on demand, never before."""
        report = Report("show", self.provider.name, selection_reason=self.selection_reason)
        index = self.local_index()
        row = index.by_id(task_id)
        external = None
        if row is not None and row.task.external is not None:
            try:
                external = self.provider.get_task(row.task.external)
            except (ProviderError, ProviderUnavailable) as exc:
                report.failures.append(str(exc))
        if external is None:
            for task in self.external_tasks(report):
                if task.id == task_id:
                    external = task
                    break
        if row is None and external is None:
            return (f"task-registry show: no task with id '{task_id}' locally or in the provider", 1)
        return ("\n".join(_render_detail(task_id, row, external, report)), report.exit_code)


def _render_detail(task_id: str, row: Optional[IndexRow], external: Optional[Task], report: Report):
    lines = [f"task: {task_id}"]
    task = external or (row.task if row else None)
    if task is None:  # pragma: no cover - guarded by the caller
        return lines
    lines.append(f"  title:    {task.title}")
    lines.append(f"  kind:     {task.kind}")
    lines.append(f"  status:   {task.status}")
    lines.append(f"  priority: {task.priority or 'unset'}")
    if task.labels:
        lines.append(f"  labels:   {', '.join(task.labels)}")
    if task.area:
        lines.append(f"  area:     {task.area}")
    if task.parent:
        lines.append(f"  parent:   {task.parent}")
    if task.depends_on:
        lines.append(f"  blocked-by: {', '.join(task.depends_on)}")
    if task.spec_path:
        lines.append(f"  spec:     {task.spec_path}")
    if task.external is not None:
        lines.append(f"  external: {task.external.display()} {task.external.url}".rstrip())
    if row is not None:
        lines.append(f"  index row: {row.task.source_path}")
    if task.summary:
        lines.append(f"  summary:  {task.summary}")
    if task.acceptance_criteria:
        lines.append("  acceptance criteria:")
        lines += [f"    - {item}" for item in task.acceptance_criteria]
    if task.evidence:
        lines.append(f"  evidence: {', '.join(task.evidence)}")
    if report.failures:
        lines.append("  failures:")
        lines += [f"    - {failure}" for failure in report.failures]
    return lines


# --------------------------------------------------------------------- helpers


@dataclass(frozen=True)
class SpecFile:
    path: str
    state: str
    superseded_by: str = ""


def _scan_specs(config) -> List[SpecFile]:
    """Classify every spec by the directory it sits in and its own marker."""
    specs: List[SpecFile] = []
    root = config.path(config.spec_dir)
    if not os.path.isdir(root):
        return specs
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if not filename.endswith(".md") or filename == "README.md":
                continue
            absolute = os.path.join(directory, filename)
            relative = os.path.relpath(absolute, config.root).replace(os.sep, "/")
            text = _safe_read(absolute)
            match = SUPERSEDED_RE.search(text)
            if match:
                specs.append(SpecFile(relative, "superseded", match.group("by").strip()))
                continue
            parent = os.path.basename(directory).lower()
            state = parent if parent in ("pending", "completed") else "active"
            specs.append(SpecFile(relative, state))
    return specs


def _merge(rows: Sequence[IndexRow], external: Sequence[Task]) -> List[Task]:
    """One task per identity, provider state winning on status, local on ordering."""
    merged: Dict[str, Task] = {}
    order: List[str] = []
    for row in rows:
        key = row.task.id or f"row:{row.line}"
        merged[key] = row.task
        order.append(key)
    for task in external:
        key = task.id or (f"ref:{task.external.id}" if task.external else task.title)
        if key in merged:
            local = merged[key]
            merged[key] = task.with_(depends_on=local.depends_on or task.depends_on)
        else:
            merged[key] = task
            order.append(key)
    return [merged[key] for key in order]


_PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2, None: 3}


def _by_priority(task: Task) -> Tuple[int, str]:
    return (_PRIORITY_ORDER.get(task.priority, 3), task.id)


def _dependency_order(tasks: Sequence[Task]) -> Tuple[List[Task], List[List[str]]]:
    """Dependencies first, priority breaking ties; plus any cycles found.

    Sorting the frontier by priority alone put a high-priority task above the
    medium-priority one it waits on, which reads as a work order that cannot be
    followed. Kahn's algorithm gives the order that can; whatever it cannot place
    is, by definition, in a cycle, and a cycle is reported rather than ordered
    arbitrarily — nothing in it will ever unblock on its own.
    """
    by_id = {task.id: task for task in tasks if task.id}
    pending = {
        task.id: {d for d in task.depends_on if d in by_id and d != task.id}
        for task in by_id.values()
    }
    ordered: List[Task] = []
    while pending:
        ready = sorted(
            (by_id[task_id] for task_id, deps in pending.items() if not deps), key=_by_priority
        )
        if not ready:
            break
        for task in ready:
            ordered.append(task)
            del pending[task.id]
        placed = {task.id for task in ready}
        for deps in pending.values():
            deps -= placed
    cycles = _cycles(pending) if pending else []
    ordered += sorted((by_id[task_id] for task_id in pending), key=_by_priority)
    ordered += sorted((task for task in tasks if not task.id), key=_by_priority)
    return ordered, cycles


def _cycles(pending: Dict[str, set]) -> List[List[str]]:
    """Name each cycle once, so the report points at the tasks a human must edit."""
    found: List[List[str]] = []
    seen: set = set()
    for start in sorted(pending):
        if start in seen:
            continue
        path: List[str] = []
        node = start
        while node in pending and node not in path:
            path.append(node)
            node = sorted(pending[node])[0]
        if node in path:
            cycle = path[path.index(node) :]
            seen.update(cycle)
            found.append(cycle)
    return found


def _short(text: str, limit: int = 70) -> str:
    collapsed = re.sub(r"\s+", " ", text or "").strip()
    return collapsed if len(collapsed) <= limit else collapsed[: limit - 1] + "…"


def _safe_read(path: str) -> str:
    if not os.path.isfile(path):
        return ""
    with open(path, "r", encoding="utf-8-sig", errors="replace") as handle:
        return handle.read()
