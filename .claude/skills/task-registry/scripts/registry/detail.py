"""Progressive disclosure: resolve one task reference, render one task.

The registry's contract with the reader is that a run costs a bounded number of
lines. The body of any task is one `show <task-id>` away and never arrives
unasked -- that is the whole reason `tasks/todo.md` can stay small enough to
load every session.

This module owns the *read* half of that contract: it resolves a reference
against the local index and the provider, combines the two into one normalized
record, and renders it. Nothing here writes.

`Registry` is the exception to that framing and the reason this file is not
purely a reader. It is the three-field application context -- config, provider,
selection reason -- that every command threads through, including the writing
ones (`upsert`, `claim`). It lives here because `show` is its only method and
`reconcile.py`, its previous home, is gone. Splitting the context out from the
capability is the honest next move; it is deliberately not this cut, which is a
deletion rather than a rearrangement.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Sequence, Tuple

from .index import IndexRow, TaskIndex, load_index
from .model import Task
from .providers.base import ProviderError, ProviderStatus, ProviderUnavailable, TrackerProvider


@dataclass
class Report:
    """What a resolution learned besides the task itself.

    `show` needs none of the finding/summary machinery the sync commands used
    this class for -- only the degradations that must not be swallowed. Both
    fields reach the reader: `_render_detail` prints `limitations` under
    `degraded:` and `failures` under `failures:`, so an answer assembled without
    the provider never reads as a complete one.
    """

    provider: str
    provider_status: Optional[ProviderStatus] = None
    limitations: List[str] = field(default_factory=list)
    failures: List[str] = field(default_factory=list)

    @property
    def exit_code(self) -> int:
        return 1 if self.failures else 0


class TaskLookupError(ValueError):
    """A requested task reference did not resolve to one normalized record."""


class Registry:
    """Holds the configuration and provider one resolution reads through."""

    def __init__(self, config, provider: TrackerProvider, selection_reason: str = "") -> None:
        self.config = config
        self.provider = provider
        self.selection_reason = selection_reason

    def local_index(self) -> TaskIndex:
        """Permissive on purpose: reading is how a malformed index gets diagnosed.

        The strict variant belongs to the commands that *act* on the index, where
        a row missing from `by_id` turns an update into an append. `show` writes
        nothing, so refusing here would deny the one answer available while the
        file is broken -- and deny it for every task, over one bad row. The rows
        that failed to parse are surfaced as limitations instead; see `show`.
        """
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

    def resolve_task(self, task_ref: str) -> Task:
        """Return one provider-neutral record without a caller rebuilding it."""
        report = Report(self.provider.name)
        return self._resolve_task(task_ref, report)

    def _resolve_task(self, task_ref: str, report: Report) -> Task:
        index = self.local_index()
        row = index.by_id(task_ref)
        external_tasks = self.external_tasks(report)
        report.limitations.extend(self.provider.limitations)
        external = _matching_task(external_tasks, task_ref, row)
        if external is None and (report.provider_status is None or report.provider_status.available):
            external = self._resolve_direct(task_ref, report)
        task = _combine_task(row, external)
        if task is None:
            raise TaskLookupError(f"no task with reference {task_ref!r} locally or in the provider")
        return task

    def _resolve_direct(self, task_ref: str, report: Report) -> Optional[Task]:
        reference = self.provider.resolve_reference(task_ref)
        if reference is None:
            return None
        try:
            return self.provider.get_task(reference)
        except (ProviderError, ProviderUnavailable) as exc:
            report.failures.append(str(exc))
            return None

    def show(self, task_id: str) -> Tuple[str, int]:
        """The only command that prints a full task. Detail on demand, never before."""
        report = Report(self.provider.name)
        index = self.local_index()
        report.limitations += [
            f"unreadable index row -- {problem.render()}" for problem in index.problems
        ]
        try:
            task = self._resolve_task(task_id, report)
        except TaskLookupError:
            return (f"task-registry show: no task with reference '{task_id}' locally or in the provider", 1)
        row = index.by_id(task.id) or index.by_id(task_id)
        return ("\n".join(_render_detail(task.id, row, task, report)), report.exit_code)


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
    if report.limitations:
        lines.append("  degraded:")
        lines += [f"    - {item}" for item in report.limitations]
    if report.failures:
        lines.append("  failures:")
        lines += [f"    - {failure}" for failure in report.failures]
    return lines


# --------------------------------------------------------------------- helpers
def _matching_task(tasks: Sequence[Task], task_ref: str, row: Optional[IndexRow]) -> Optional[Task]:
    wanted_ref = row.task.external if row is not None else None
    for task in tasks:
        if task.id == task_ref:
            return task
        if task.external and task.external.id == task_ref.lstrip("#"):
            return task
        if task.external and wanted_ref and task.external == wanted_ref:
            return task
    return None


def _combine_task(row: Optional[IndexRow], external: Optional[Task]) -> Optional[Task]:
    if external is None:
        return row.task if row is not None else None
    if row is None:
        return external
    extra = dict(external.extra)
    extra.pop("registry_identity", None)
    return external.with_(
        id=row.task.id,
        depends_on=row.task.depends_on or external.depends_on,
        extra=extra,
    )
