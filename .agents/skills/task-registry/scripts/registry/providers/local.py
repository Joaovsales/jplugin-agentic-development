"""Local Markdown provider — the offline default.

Canonical task detail lives in one file per task under the configured detail
directory; `tasks/todo.md` stays a compact index that links to them. Nothing here
touches the network, so this provider is what a repository with no tracker, no
credentials, or no connectivity still gets: stable IDs, parent links, dependency
links, comments, and long-form detail that never has to be pasted into the index.
"""

from __future__ import annotations

import datetime
import os
import re
import tempfile
from typing import List, Optional

from ..model import ExternalRef, Task, parse_metadata_block, render_metadata_block
from .base import Capabilities, LinkResult, ProviderError, ProviderStatus, TrackerProvider

FIELD_RE = re.compile(r"^-\s*(?P<key>status|priority|labels|area|updated|created)\s*:\s*(?P<value>.*)$")
SECTION_RE = re.compile(r"^##\s+(?P<name>.+?)\s*$")


class LocalMarkdownProvider(TrackerProvider):
    name = "local"
    capabilities = Capabilities(
        native_hierarchy=True,
        native_dependencies=True,
        comments=True,
        labels=True,
        offline=True,
        atomic_updates=True,
    )

    def __init__(self, config, gate=None) -> None:
        super().__init__(config, gate)
        self.detail_dir = config.path(config.local_detail_dir)

    # ---------------------------------------------------------------- discovery
    def discover(self) -> ProviderStatus:
        return ProviderStatus(True, f"local Markdown store at {self.config.local_detail_dir}/")

    # -------------------------------------------------------------------- reads
    def list_tasks(self) -> List[Task]:
        if not os.path.isdir(self.detail_dir):
            return []
        tasks: List[Task] = []
        for name in sorted(os.listdir(self.detail_dir)):
            if not name.endswith(".md") or name == "README.md":
                continue
            tasks.append(self._read(os.path.join(self.detail_dir, name)))
        return tasks

    def get_task(self, ref: ExternalRef) -> Task:
        path = self._path_for(ref.id)
        if not os.path.isfile(path):
            raise ProviderError(f"local: no task file for {ref.id} at {self._relative(path)}")
        return self._read(path)

    def resolve_reference(self, raw: str) -> Optional[ExternalRef]:
        if not raw:
            return None
        candidate = raw.strip()
        if candidate.endswith(".md"):
            candidate = os.path.basename(candidate)[:-3]
        path = self._path_for(candidate)
        if os.path.isfile(path):
            return ExternalRef("local", candidate, self._relative(path))
        return None

    # ------------------------------------------------------------------- writes
    def create_task(self, task: Task) -> Task:
        self.gate.authorize(f"create local task {task.id}", self.name)
        path = self._path_for(task.id)
        if os.path.isfile(path):
            return self.update_task(task)
        self._write(path, self._render(task))
        return task.with_(external=ExternalRef("local", task.id, self._relative(path)))

    def update_task(self, task: Task) -> Task:
        self.gate.authorize(f"update local task {task.id}", self.name)
        path = self._path_for(task.id)
        existing = _read_text(path) if os.path.isfile(path) else ""
        self._write(path, self._render(task, existing))
        return task.with_(external=ExternalRef("local", task.id, self._relative(path)))

    def close_task(self, task: Task, resolution: str = "done") -> Task:
        return self.update_task(task.with_(status=resolution))

    def comment(self, task: Task, body: str) -> None:
        self.gate.authorize(f"comment on local task {task.id}", self.name)
        path = self._path_for(task.id)
        if not os.path.isfile(path):
            raise ProviderError(f"local: cannot comment, no task file for {task.id}")
        stamp = datetime.date.today().isoformat()
        text = _read_text(path).rstrip("\n")
        if "## Comments" not in text:
            text += "\n\n## Comments\n"
        text += f"\n- {stamp} — {body.strip()}\n"
        self._write(path, text)

    def link_parent(self, child: Task, parent: Task) -> LinkResult:
        self.update_task(child.with_(parent=parent.id))
        return LinkResult("parent", child.id, parent.id, native=True)

    def add_dependency(self, task: Task, depends_on: Task) -> LinkResult:
        merged = tuple(dict.fromkeys(tuple(task.depends_on) + (depends_on.id,)))
        self.update_task(task.with_(depends_on=merged))
        return LinkResult("dependency", task.id, depends_on.id, native=True)

    # ------------------------------------------------------------------ helpers
    def _path_for(self, task_id: str) -> str:
        safe = re.sub(r"[^A-Za-z0-9._-]", "-", task_id)
        return os.path.join(self.detail_dir, f"{safe}.md")

    def _relative(self, path: str) -> str:
        return os.path.relpath(path, self.config.root).replace(os.sep, "/")

    def _render(self, task: Task, existing: str = "") -> str:
        """Rebuild the managed regions; keep every section a human added."""
        preserved = _sections_beyond_managed(existing)
        head = [f"# {task.title}", "", render_metadata_block(task), ""]
        head.append(f"- status: {task.status}")
        if task.priority:
            head.append(f"- priority: {task.priority}")
        if task.labels:
            head.append(f"- labels: {', '.join(task.labels)}")
        if task.area:
            head.append(f"- area: {task.area}")
        head.append(f"- updated: {datetime.date.today().isoformat()}")
        head.append("")
        if task.summary:
            head += ["## Summary", "", task.summary.strip(), ""]
        if task.acceptance_criteria:
            head.append("## Acceptance Criteria")
            head.append("")
            head += [f"- [ ] {item}" for item in task.acceptance_criteria]
            head.append("")
        if preserved:
            head.append(preserved.strip())
            head.append("")
        return "\n".join(head)

    def _read(self, path: str) -> Task:
        text = _read_text(path)
        meta = parse_metadata_block(text)
        fields = {}
        for line in text.splitlines():
            match = FIELD_RE.match(line.strip())
            if match:
                fields[match.group("key")] = match.group("value").strip()
        title_match = re.search(r"^#\s+(?P<title>.+?)\s*$", text, re.MULTILINE)
        task_id = meta.get("task-id") or os.path.basename(path)[:-3]
        labels = tuple(
            part.strip() for part in fields.get("labels", "").split(",") if part.strip()
        )
        return Task(
            id=task_id,
            title=title_match.group("title") if title_match else task_id,
            kind=meta.get("kind", "task"),
            status=fields.get("status", "open"),
            priority=fields.get("priority") or None,
            labels=labels,
            area=fields.get("area") or None,
            parent=meta.get("parent"),
            depends_on=meta.get("depends-on", ()),
            spec_path=meta.get("spec"),
            source_path=meta.get("source"),
            evidence=meta.get("evidence", ()),
            summary=_section_body(text, "Summary"),
            acceptance_criteria=_criteria(text),
            updated_at=fields.get("updated"),
            external=ExternalRef("local", task_id, self._relative(path)),
        )

    def _write(self, path: str, text: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        handle = tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="\n", dir=os.path.dirname(path), delete=False
        )
        try:
            handle.write(text if text.endswith("\n") else text + "\n")
            handle.close()
            os.replace(handle.name, path)  # atomic on every supported platform
        except BaseException:
            handle.close()
            if os.path.exists(handle.name):
                os.unlink(handle.name)
            raise


def _read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8-sig") as handle:
        return handle.read()


MANAGED_SECTIONS = {"summary", "acceptance criteria"}


def _sections_beyond_managed(text: str) -> str:
    """Everything under an `##` heading this provider does not own."""
    if not text:
        return ""
    kept: List[str] = []
    keeping = False
    for line in text.splitlines():
        match = SECTION_RE.match(line)
        if match:
            keeping = match.group("name").strip().lower() not in MANAGED_SECTIONS
        if keeping:
            kept.append(line)
    return "\n".join(kept)


def _section_body(text: str, name: str) -> str:
    lines = text.splitlines()
    body: List[str] = []
    collecting = False
    for line in lines:
        match = SECTION_RE.match(line)
        if match:
            collecting = match.group("name").strip().lower() == name.lower()
            continue
        if collecting:
            body.append(line)
    return "\n".join(body).strip()


def _criteria(text: str) -> tuple:
    body = _section_body(text, "Acceptance Criteria")
    return tuple(
        re.sub(r"^-\s*\[.\]\s*", "", line).strip()
        for line in body.splitlines()
        if line.strip().startswith("- [")
    )
