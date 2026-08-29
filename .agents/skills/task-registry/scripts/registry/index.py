"""The local task index — `tasks/todo.md` as a map, not a database.

A row carries six things and nothing else: status box, title, stable ID, provider
link, one-line summary, optional dependency marker. Acceptance criteria, issue
bodies, and discussion live in the external task or the linked spec. That bound is
the whole reason the index stays loadable at the top of every session.

Backwards compatibility is load-bearing: a plain `[ ] do the thing` row from before
this capability existed must parse, be reported, and never be silently rewritten.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

from .model import ExternalRef, Task, TaskModelError
from .providers import provider_for_url, reference_label

#: Status box characters. `[ ]` and `[x]` are the pre-existing convention; the
#: rest extend it without breaking a reader that only knows those two.
BOX_TO_STATUS = {
    " ": "open",
    "": "open",
    "~": "in_progress",
    ">": "in_progress",
    "!": "blocked",
    "x": "done",
    "X": "done",
    "-": "cancelled",
}
STATUS_TO_BOX = {
    "open": " ",
    "in_progress": "~",
    "blocked": "!",
    "done": "x",
    "cancelled": "-",
}

ROW_RE = re.compile(r"^(?P<indent>[ \t]*)(?P<bullet>[-*]\s+)?\[(?P<box>.?)\](?P<rest>.*)$")
TASK_ID_RE = re.compile(r"<!--\s*task-id:\s*(?P<id>[^\s>]+?)\s*-->")
LINK_RE = re.compile(
    r"\((?P<label>\[[^\]]+\])\((?P<url>[^)\s]+)\)\)"  # the ([#42](url)) shape we render
    r"|\[(?P<bare>[^\]]+)\]\((?P<bare_url>[^)\s]+)\)"  # a bare [#42](url) a human typed
)
DEPS_RE = re.compile(
    r"[(\[]\s*(?:blocked-by|depends-on|deps)\s*:\s*(?P<ids>[^)\]]+)[)\]]", re.IGNORECASE
)
SUMMARY_SPLIT = re.compile(r"\s+[—–]\s+")
#: A reference id ends up as a positional argument to `gh` and as a path segment
#: in a Jira URL. Anything outside this set is a malformed row, reported like any
#: other (AC-19) rather than forwarded to a subprocess or an HTTP client.
REF_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")


@dataclass(frozen=True)
class Problem:
    """A row that could not be read. Reported, never dropped."""

    path: str
    line: int
    message: str
    raw: str = ""

    def render(self) -> str:
        return f"{self.path}:{self.line} — {self.message}"


@dataclass(frozen=True)
class IndexRow:
    task: Task
    line: int  # 1-based, matching what an editor and a Problem report
    raw: str
    legacy: bool  # no stable ID present in the source row
    indent: str = ""  # leading whitespace, so a rewrite preserves nesting


class TaskIndex:
    """Parsed view of one index file, able to rewrite only the rows it owns."""

    def __init__(self, path: str, text: str, relative_path: Optional[str] = None) -> None:
        self.path = path
        self.relative_path = relative_path or path
        self._lines = text.splitlines()
        self._trailing_newline = text.endswith("\n") if text else True
        self.rows: List[IndexRow] = []
        self.problems: List[Problem] = []
        self._parse()

    # ---------------------------------------------------------------- parsing

    def _parse(self) -> None:
        for number, line in enumerate(self._lines, start=1):
            match = ROW_RE.match(line)
            if not match:
                continue
            try:
                row = self._parse_row(match, number, line)
            except TaskModelError as exc:
                self.problems.append(Problem(self.relative_path, number, str(exc), line))
                continue
            if row is not None:
                self.rows.append(row)

    def _parse_row(self, match: "re.Match[str]", number: int, line: str) -> Optional[IndexRow]:
        box = match.group("box")
        if box not in BOX_TO_STATUS:
            self.problems.append(
                Problem(
                    self.relative_path,
                    number,
                    f"unknown status box '[{box}]' (expected one of: "
                    f"{', '.join(repr(k) for k in STATUS_TO_BOX.values())})",
                    line,
                )
            )
            return None

        rest = match.group("rest")
        task_id, rest = _extract_id(rest)
        depends_on, rest = _extract_dependencies(rest)
        external, rest = _extract_link(rest)
        title, summary = _split_title_summary(rest)

        if not title:
            self.problems.append(
                Problem(self.relative_path, number, "row has a status box but no title", line)
            )
            return None

        task = Task(
            id=task_id or "",
            title=title,
            status=BOX_TO_STATUS[box],
            depends_on=depends_on,
            external=external,
            summary=summary,
            source_path=f"{self.relative_path}:{number}",
        )
        return IndexRow(
            task=task,
            line=number,
            raw=line,
            legacy=not task_id,
            indent=match.group("indent") or "",
        )

    # ---------------------------------------------------------------- writing

    def replace_row(self, line: int, new_text: str) -> None:
        self._lines[line - 1] = new_text

    def row_text(self, line: int) -> str:
        """The current text of a line, including edits made this run."""
        return self._lines[line - 1]

    def append_row(self, task: Task) -> None:
        self._lines.append(render_row(task))

    def render(self) -> str:
        text = "\n".join(self._lines)
        return text + "\n" if self._trailing_newline and text else text

    def save(self) -> None:
        write_text(self.path, self.render())

    def by_id(self, task_id: str) -> Optional[IndexRow]:
        for row in self.rows:
            if row.task.id and row.task.id == task_id:
                return row
        return None


def _extract_id(rest: str) -> Tuple[Optional[str], str]:
    match = TASK_ID_RE.search(rest)
    if not match:
        return None, rest
    return match.group("id"), (rest[: match.start()] + rest[match.end() :])


def _extract_dependencies(rest: str) -> Tuple[Tuple[str, ...], str]:
    match = DEPS_RE.search(rest)
    if not match:
        return (), rest
    ids = tuple(part.strip() for part in match.group("ids").split(",") if part.strip())
    return ids, (rest[: match.start()] + rest[match.end() :])


def _extract_link(rest: str) -> Tuple[Optional[ExternalRef], str]:
    match = LINK_RE.search(rest)
    if not match:
        return None, rest
    label = match.group("label") or match.group("bare") or ""
    url = match.group("url") or match.group("bare_url") or ""
    ref_id = label.strip("[]").lstrip("#").strip()
    if not REF_ID_RE.match(ref_id):
        raise TaskModelError(
            f"reference id {ref_id!r} contains characters this registry will not "
            "pass to a tracker (allowed: letters, digits, '.', '_', '/', '-')"
        )
    ref = ExternalRef(provider=provider_for_url(url), id=ref_id, url=url)
    return ref, (rest[: match.start()] + rest[match.end() :])


def _split_title_summary(rest: str) -> Tuple[str, str]:
    cleaned = re.sub(r"\s{2,}", " ", rest).strip()
    parts = SUMMARY_SPLIT.split(cleaned, maxsplit=1)
    # Only whitespace is stripped: ROW_RE already consumed the bullet, so
    # stripping dashes here would silently rewrite a legitimate title such as
    # "-fno-strict-aliasing crashes the build".
    title = parts[0].strip()
    summary = parts[1].strip() if len(parts) > 1 else ""
    return title, summary


def render_row(task: Task, indent: str = "") -> str:
    """Render the canonical compact row. This is the only row shape we emit."""
    box = STATUS_TO_BOX.get(task.status, " ")
    parts = [f"{indent}- [{box}] {task.title.strip()}"]
    if task.id:
        parts.append(f"<!-- task-id: {task.id} -->")
    if task.summary:
        parts.append(f"— {_one_line(task.summary)}")
    if task.external is not None:
        label = reference_label(task.external)
        parts.append(f"([{label}]({task.external.url}))" if task.external.url else f"({label})")
    if task.depends_on:
        parts.append(f"(blocked-by: {', '.join(task.depends_on)})")
    return " ".join(parts)


def _one_line(text: str, limit: int = 120) -> str:
    collapsed = re.sub(r"\s+", " ", text).strip()
    return collapsed if len(collapsed) <= limit else collapsed[: limit - 1].rstrip() + "…"


def load_index(path: str, relative_path: Optional[str] = None) -> TaskIndex:
    if not os.path.isfile(path):
        return TaskIndex(path, "", relative_path)
    with open(path, "r", encoding="utf-8-sig") as handle:
        return TaskIndex(path, handle.read(), relative_path)


def write_text(path: str, text: str) -> None:
    """Write UTF-8, creating parents. Explicit encoding at every IO boundary."""
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8-sig") as handle:
        return handle.read()


def collect_problems(indexes: Sequence[TaskIndex]) -> List[Problem]:
    problems: List[Problem] = []
    for index in indexes:
        problems.extend(index.problems)
    return problems
