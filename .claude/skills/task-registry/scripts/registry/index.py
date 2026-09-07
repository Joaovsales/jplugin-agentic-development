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
TASK_KIND_RE = re.compile(r"<!--\s*task-kind:\s*(?P<kind>[^\s>]+?)\s*-->")
COMMENT_MARKER_RE = re.compile(r"<!--|-->")
LINK_RE = re.compile(
    r"\((?P<label>\[[^\]]+\])\((?P<url>[^)\s]+)\)\)"  # the ([#42](url)) shape we render
    r"|\[(?P<bare>[^\]]+)\]\((?P<bare_url>[^)\s]+)\)"  # a bare [#42](url) a human typed
)
DEPS_RE = re.compile(
    r"[(\[]\s*(?:blocked-by|depends-on|deps)\s*:\s*(?P<ids>[^)\]]+)[)\]]", re.IGNORECASE
)
SUMMARY_SPLIT = re.compile(r"\s+[—–]\s+")
LEGACY_TDD_RE = re.compile(
    r"^TDD:\s*`(?P<title>[^`]+)`\s*->\s*(?P<summary>.+)$", re.IGNORECASE
)
ARROW_SPLIT = re.compile(r"(?<!-)->")
TRAILING_CONJUNCTION = re.compile(r"(?:^|\s+)(?:and|or|then)$", re.IGNORECASE)
MAX_LOGICAL_ROW_CHARS = 60_000
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
    end_line: int  # inclusive physical span owned by this logical row
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
        self._replacements: dict[int, str] = {}
        self.rows: List[IndexRow] = []
        self.problems: List[Problem] = []
        self._parse()

    # ---------------------------------------------------------------- parsing

    def _parse(self) -> None:
        for number, line in enumerate(self._lines, start=1):
            match = ROW_RE.match(line)
            if not match:
                continue
            detail, end_line = _continuation_lines(
                self._lines, number - 1, len(match.group("indent") or "")
            )
            try:
                row = self._parse_row(match, number, end_line, line, detail)
            except TaskModelError as exc:
                self.problems.append(Problem(self.relative_path, number, str(exc), line))
                continue
            if row is not None:
                self.rows.append(row)

    def _parse_row(
        self,
        match: "re.Match[str]",
        number: int,
        end_line: int,
        line: str,
        detail: Sequence[str],
    ) -> Optional[IndexRow]:
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
        if _has_unbalanced_comment((rest, *detail)):
            self.problems.append(
                Problem(
                    self.relative_path,
                    number,
                    "unbalanced HTML comment in logical task row",
                    line,
                )
            )
            return None
        if len(rest) + sum(len(item) + 1 for item in detail) > MAX_LOGICAL_ROW_CHARS:
            self.problems.append(
                Problem(
                    self.relative_path,
                    number,
                    f"logical task row exceeds the {MAX_LOGICAL_ROW_CHARS}-character publish limit",
                    line,
                )
            )
            return None
        task_id, rest = _extract_id(rest)
        task_kind, rest = _extract_kind(rest)
        depends_on, rest = _extract_dependencies(rest)
        external, rest = _extract_link(rest)
        title, summary, publish_error = _split_title_summary(rest)
        summary = " ".join(part for part in (summary, *detail) if part)

        if publish_error:
            self.problems.append(Problem(self.relative_path, number, publish_error, line))
            return None

        if not title:
            self.problems.append(
                Problem(self.relative_path, number, "row has a status box but no title", line)
            )
            return None

        task = Task(
            id=task_id or "",
            title=title,
            kind=task_kind or "task",
            status=BOX_TO_STATUS[box],
            depends_on=depends_on,
            external=external,
            summary=summary,
            source_path=f"{self.relative_path}:{number}",
        )
        return IndexRow(
            task=task,
            line=number,
            end_line=end_line,
            raw=line,
            legacy=not task_id,
            indent=match.group("indent") or "",
        )

    # ---------------------------------------------------------------- writing

    def replace_row(self, line: int, new_text: str) -> None:
        self._replacements[line] = new_text

    def replace_line(self, line: int, new_text: str) -> None:
        self._lines[line - 1] = new_text

    def row_text(self, line: int) -> str:
        """The current text of a line, including edits made this run."""
        return self._replacements.get(line, self._lines[line - 1])

    def append_row(self, task: Task) -> None:
        self._lines.append(render_row(task))

    def render(self) -> str:
        row_ends = {row.line: row.end_line for row in self.rows}
        rendered = []
        line = 1
        while line <= len(self._lines):
            rendered.append(self._replacements.get(line, self._lines[line - 1]))
            line = row_ends.get(line, line) + 1 if line in self._replacements else line + 1
        text = "\n".join(rendered)
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


def _extract_kind(rest: str) -> Tuple[Optional[str], str]:
    match = TASK_KIND_RE.search(rest)
    if not match:
        return None, rest
    return match.group("kind"), (rest[: match.start()] + rest[match.end() :])


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


def _continuation_lines(
    lines: Sequence[str], row_index: int, indent: int
) -> Tuple[List[str], int]:
    detail = []
    end_line = row_index + 1
    for candidate_index in range(row_index + 1, len(lines)):
        line = lines[candidate_index]
        leading = len(line) - len(line.lstrip(" \t"))
        if not line.strip():
            continue
        if ROW_RE.match(line) or leading <= indent:
            break
        detail.append(line.strip())
        end_line = candidate_index + 1
    return detail, end_line


def _has_unbalanced_comment(parts: Sequence[str]) -> bool:
    opened = False
    for marker in COMMENT_MARKER_RE.findall("\n".join(parts)):
        if marker == "<!--":
            if opened:
                return True
            opened = True
        elif not opened:
            return True
        else:
            opened = False
    return opened


def _split_title_summary(rest: str) -> Tuple[str, str, Optional[str]]:
    cleaned = re.sub(r"\s{2,}", " ", rest).strip()
    arrows = list(ARROW_SPLIT.finditer(cleaned))
    tdd = LEGACY_TDD_RE.match(cleaned)
    if tdd and len(arrows) == 1:
        title = tdd.group("title").strip()
        summary = tdd.group("summary").strip()
        return title, summary, _legacy_publish_error(cleaned, title, summary)
    canonical = _canonical_summary(cleaned, arrows)
    if canonical is not None:
        return canonical[0], canonical[1], None
    if len(arrows) > 1:
        return cleaned, "", "cannot publish legacy row: multiple '->' delimiters are ambiguous"
    if arrows:
        return _split_legacy_arrow(cleaned, arrows[0])
    return cleaned, "", None


def _canonical_summary(
    cleaned: str, arrows: Sequence["re.Match[str]"]
) -> Optional[Tuple[str, str]]:
    separator = SUMMARY_SPLIT.search(cleaned)
    if separator is None or (arrows and arrows[0].start() < separator.start()):
        return None
    return cleaned[: separator.start()].strip(), cleaned[separator.end() :].strip()


def _split_legacy_arrow(
    cleaned: str, arrow: "re.Match[str]"
) -> Tuple[str, str, Optional[str]]:
    title = TRAILING_CONJUNCTION.sub("", cleaned[: arrow.start()].strip()).strip()
    summary = cleaned[arrow.end() :].strip()
    return title or cleaned, summary, _legacy_publish_error(cleaned, title, summary)


def _legacy_publish_error(cleaned: str, title: str, summary: str) -> Optional[str]:
    if cleaned.lower().startswith("tdd:") and (not title or not summary or "``" in title):
        return "cannot publish legacy TDD row: expected a quoted test name and detail after '->'"
    if not title or not summary:
        return "cannot publish legacy row: expected a clean title and detail around '->'"
    return None


def render_row(task: Task, indent: str = "", include_kind: bool = False) -> str:
    """Render the canonical compact row. This is the only row shape we emit."""
    box = STATUS_TO_BOX.get(task.status, " ")
    parts = [f"{indent}- [{box}] {task.title.strip()}"]
    if task.id:
        parts.append(f"<!-- task-id: {task.id} -->")
    if include_kind:
        parts.append(f"<!-- task-kind: {task.kind} -->")
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
