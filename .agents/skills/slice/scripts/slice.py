#!/usr/bin/env python3
"""slice.py — validate, list, and check the slices in a spec's § Build Order.

`/slice` breaks a spec into session-sized slices and writes two artifacts: the
`## Build Order` table in the spec, and a `## Plan:` block in `tasks/todo.md`
with one `### Slice n/N` heading per row. This script answers the three
mechanical questions a human should never have to hold in their head:

  * **validate** — does the Build Order actually describe a buildable plan?
    Every surface inside `implementation_paths`, no cycle in `Blocked by`, no
    pair of slices that overlap without an ordering between them, and no
    § Interfaces entry without a `Path:`. Once the `## Plan:` block exists, it
    links its feature once and every open `TDD:` row's `tests/...` file is
    inside its slice's surface too.
  * **ready** — which slices can be dispatched right now, given which plan-block
    headers are already `[x]`, and in which `mode=` (design when a § Interfaces
    `Path:` falls inside the slice's surface, else tdd)?
  * **check** — after a slice closes, did its diff actually stay inside the
    surface it declared? Exit 1 on surface drift. With `--index` the freeze is
    checked too; every freeze problem prints one line and exits 3:

      - `frozen-edited: <path>` — a contract test (a non-`tasks/` path changed
        in `S..F`) or a file added after `F` in a contract test's own
        directory (that exact directory, never a subdirectory; a root-level
        test protects only itself) changed after `F` with no `> Test amended:`.
      - `amended-unknown: <path>` — a `> Test amended:` line names a file that
        is no contract test.
      - `duplicate freeze line` — two `> Frozen:` lines under one slice.
      - `missing freeze commit` — a design-mode slice with no `> Frozen:` line.

    A slice with a recorded `> Frozen:` line is checked whatever mode it
    derives now. A plan block with `### Slice` headings but none for the slice
    exits 2. Without `--index` the freeze is not read, and a design-mode slice
    says so on stderr.
  * **readiness** — may a build prompt be printed at all? Not while a decision
    is `open` or an open question blocks a slice (specs/readable-visual-plans.md).

The glob matcher (`match_path`, `patterns_intersect`, `pattern_covered_by`) and
the `implementation_paths` frontmatter reader live in `registry/globs.py`,
shared with `wrap-up-session/scripts/spec-reconcile.py` rather than duplicated.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from functools import cached_property
from itertools import combinations
from typing import Dict, List, Optional, Sequence, Tuple

# `registry` lives under the task-registry skill, not this one. Resolved
# relative to this file so the script works from any cwd.
_TASK_REGISTRY_SCRIPTS = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "task-registry", "scripts")
)
if _TASK_REGISTRY_SCRIPTS not in sys.path:
    sys.path.insert(0, _TASK_REGISTRY_SCRIPTS)

from registry.globs import (  # noqa: E402  (path must be set up first)
    SpecPathError,
    match_path,
    pattern_covered_by,
    patterns_intersect,
    read_implementation_paths,
    validate_pattern,
)
from registry.index import IndexRow, IndexUnreadable, load_index_strict, read_text  # noqa: E402

BUILD_ORDER_HEADING = "## Build Order"
PLAN_HEADING_RE = re.compile(r"^##\s*Plan:\s*(?P<name>.+?)\s*$")
SPEC_LINE_RE = re.compile(r"^>\s*Spec:\s*(?P<path>\S+)\s*$")
SLICE_HEADING_RE = re.compile(r"^###\s*Slice\s+(?P<number>\d+)/(?P<total>\d+)\s+—\s+(?P<name>.+?)\s*$")
# Only an open row whose test file is a `tests/...` path before ` § ` is
# checked against its slice's surface: `<test name> -> <impl>` rows carry no
# path, and a `[x]` row's test is already written, so its mismatch blocks no agent.
OPEN_TDD_ROW_RE = re.compile(r"^\s*(?:-\s*)?\[ \]\s*TDD:\s*(?P<path>tests/\S+)\s+§\s")
H2_RE = re.compile(r"^##\s")
# A plan block's feature link: the `> Issue:` line, or the one `- [ ]` row above the first slice heading.
ISSUE_LINE_RE = re.compile(r"^>\s*Issue:\s*\S")
FEATURE_ROW_RE = re.compile(r"^\s*-\s*\[.\]\s")
FROZEN_LINE_RE = re.compile(r"^>\s*Frozen:\s*(?P<s>[0-9A-Za-z]+)\.\.(?P<f>[0-9A-Za-z]+)(?:\s|$)")
AMENDED_LINE_RE = re.compile(r"^>\s*Test amended:\s*(?P<path>\S+)")
INTERFACES_HEADING = "## Interfaces"
INTERFACE_ENTRY_RE = re.compile(r"^###\s+(?P<title>.+?)\s*$", re.MULTILINE)
INTERFACE_PATH_RE = re.compile(r"^\s*-\s*\*\*Path:\*\*\s*(?P<path>.*?)\s*$", re.MULTILINE)


class SliceError(Exception):
    """A spec's § Build Order, or a plan block, does not read as this format expects.

    Always names the spec or the index file: the whole point of failing loudly
    is that the author fixes the source, not that this script guesses past it.
    """


class MissingBuildOrder(SliceError):
    """The spec has no `## Build Order` section at all — a legacy, one-slice plan."""


@dataclass(frozen=True)
class SliceRow:
    """One row of § Build Order."""

    number: int
    name: str
    surface: Tuple[str, ...]
    blocked_by: Tuple[int, ...]


_FENCE_RE = re.compile(r"^\s*(?P<fence>`{3,}|~{3,})")


def _closes_fence(fence: str, line: str) -> bool:
    """A fence closes on a run of the same character at least as long, alone on its line."""
    match = _FENCE_RE.match(line)
    if not match:
        return False
    run = match.group("fence")
    return run[0] == fence[0] and len(run) >= len(fence) and not line.strip()[len(run):].strip()


def _without_fences(text: str) -> str:
    """Blank every line inside a code fence, keeping line numbers intact.

    A spec shows the grammar it asks for inside a fenced example, so the first
    `## Build Order` in the file may be the illustration rather than the
    section; the real plan-slices spec is exactly that shape. Headings and
    table rows are only read from prose.
    """
    out: List[str] = []
    fence = ""
    for line in text.splitlines():
        match = _FENCE_RE.match(line)
        if fence and _closes_fence(fence, line):
            fence = ""
        elif not fence and match:
            fence = match.group("fence")
        else:
            out.append("" if fence else line)
            continue
        out.append("")
    return "\n".join(out)


# ------------------------------------------------------------- Build Order


def _section_body(text: str, heading: str) -> Optional[str]:
    match = re.search(
        rf"^{re.escape(heading)}\s*$(?P<body>.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL
    )
    return match.group("body") if match else None


def _table_rows(body: str) -> List[List[str]]:
    """Every table row's cells, header first. Separator rows (`|---|---|`) are dropped."""
    rows: List[List[str]] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if all(re.fullmatch(r":?-+:?", cell) for cell in cells):
            continue  # the markdown header-separator row
        rows.append(cells)
    return rows


def _split_surface(cell: str, spec_path: str) -> Tuple[str, ...]:
    """Surface globs go through the shared validator: an unsupported token
    would otherwise reach `check` and `ready` as a literal that matches nothing."""
    if cell in ("", "—", "-"):
        return ()
    parts = [part.strip().strip("`").strip() for part in cell.split(",")]
    return tuple(validate_pattern(part, spec_path) for part in parts if part)


def _split_blocked_by(cell: str, spec_path: str) -> Tuple[int, ...]:
    if cell in ("", "—", "-"):
        return ()
    numbers: List[int] = []
    for part in cell.split(","):
        part = part.strip()
        if not part:
            continue
        if not part.isdigit():
            raise SliceError(
                f"{spec_path}: Build Order `Blocked by` cell has a non-numeric entry: {part!r}"
            )
        numbers.append(int(part))
    return tuple(numbers)


def parse_build_order(spec_text: str, spec_path: str) -> List[SliceRow]:
    """Parse the `# | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size` table."""
    body = _section_body(_without_fences(spec_text), BUILD_ORDER_HEADING)
    if body is None:
        raise MissingBuildOrder(f"{spec_path}: no {BUILD_ORDER_HEADING!r} section found")
    rows = _table_rows(body)
    if len(rows) < 2:
        raise SliceError(f"{spec_path}: Build Order table not found")
    header = [cell.lower() for cell in rows[0]]

    def column(name: str) -> int:
        try:
            return header.index(name)
        except ValueError:
            raise SliceError(f"{spec_path}: Build Order table missing column {name!r}")

    idx_number, idx_name = column("#"), column("slice")
    idx_surface, idx_blocked = column("surface"), column("blocked by")

    slices: List[SliceRow] = []
    for cells in rows[1:]:
        if len(cells) < len(header):
            raise SliceError(
                f"{spec_path}: Build Order row has {len(cells)} cells, header has {len(header)}: {cells!r}"
            )
        number_text = cells[idx_number]
        if not number_text.isdigit():
            raise SliceError(f"{spec_path}: Build Order `#` cell is not a number: {number_text!r}")
        slices.append(
            SliceRow(
                number=int(number_text),
                name=cells[idx_name],
                surface=_split_surface(cells[idx_surface], spec_path),
                blocked_by=_split_blocked_by(cells[idx_blocked], spec_path),
            )
        )
    _refuse_unknown_blockers(slices, spec_path)
    return slices


def _refuse_unknown_blockers(slices: Sequence[SliceRow], spec_path: str) -> None:
    """Every `Blocked by` number names a row of the same table.

    Refused here, once, so the ordering helpers and `ready` can index the table
    unconditionally: a typo (`9` for `1`) is an error the author sees, not a
    slice that validates clean and is never ready.
    """
    numbers = {row.number for row in slices}
    for row in slices:
        for dep in row.blocked_by:
            if dep not in numbers:
                raise SliceError(
                    f"{spec_path}: slice {row.number} ({row.name}) is blocked by {dep}, which names no slice"
                )


def resolve_slices(spec_path: str, implicit_name: str) -> Dict[int, SliceRow]:
    """The spec's slices by number — or one implicit slice when it has no Build Order.

    A plan written before § Build Order existed is one slice whose surface is
    the spec's whole `implementation_paths`; `ready` and `check` both read that
    definition from here so a legacy plan still builds and still checks.
    """
    try:
        rows = parse_build_order(read_text(spec_path), spec_path)
    except MissingBuildOrder:
        surface = tuple(read_implementation_paths(spec_path))
        return {1: SliceRow(number=1, name=implicit_name, surface=surface, blocked_by=())}
    return {row.number: row for row in rows}


# --------------------------------------------------------- ordering helpers


def _reachable(slices: Dict[int, SliceRow], start: int) -> set:
    """Every slice `start` transitively depends on, via `Blocked by`."""
    seen: set = set()
    stack = [start]
    while stack:
        current = stack.pop()
        for dep in slices[current].blocked_by:
            if dep not in seen:
                seen.add(dep)
                stack.append(dep)
    return seen


def _ordered(slices: Dict[int, SliceRow], a: int, b: int) -> bool:
    """Whether `a` and `b` have a blocking relationship, in either direction."""
    return b in _reachable(slices, a) or a in _reachable(slices, b)


def _surfaces_intersect(a: Sequence[str], b: Sequence[str]) -> bool:
    return any(patterns_intersect(p, q) for p in a for q in b)


def find_cycle(slices: Dict[int, SliceRow]) -> Optional[List[int]]:
    """A `Blocked by` cycle as a list of slice numbers, or None."""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {number: WHITE for number in slices}
    path: List[int] = []

    def visit(number: int) -> Optional[List[int]]:
        color[number] = GRAY
        path.append(number)
        for dep in slices[number].blocked_by:
            if color[dep] == GRAY:
                start = path.index(dep)
                return path[start:] + [dep]
            if color[dep] == WHITE:
                found = visit(dep)
                if found:
                    return found
        path.pop()
        color[number] = BLACK
        return None

    for number in slices:
        if color[number] == WHITE:
            found = visit(number)
            if found:
                return found
    return None


# ------------------------------------------------------------- Interfaces


def parse_interfaces(spec_text: str) -> List[Tuple[str, Optional[str]]]:
    """(title, Path or None) per `### ` entry of the spec's optional `## Interfaces` section."""
    body = _section_body(_without_fences(spec_text), INTERFACES_HEADING)
    if body is None:
        return []
    entries = list(INTERFACE_ENTRY_RE.finditer(body))
    parsed: List[Tuple[str, Optional[str]]] = []
    for position, entry in enumerate(entries):
        end = entries[position + 1].start() if position + 1 < len(entries) else len(body)
        path = INTERFACE_PATH_RE.search(body, entry.end(), end)
        value = path.group("path").strip("`").strip() if path else ""
        parsed.append((entry.group("title"), value or None))
    return parsed


def _interfaces_problems(spec_text: str) -> List[str]:
    return [
        f"§ Interfaces entry {title} has no `Path:`"
        for title, path in parse_interfaces(spec_text)
        if path is None
    ]


def _interface_paths(spec_text: str) -> List[str]:
    return [path for _title, path in parse_interfaces(spec_text) if path]


# --------------------------------------------------------------- validate


def _surface_problems(rows: Sequence[SliceRow], implementation_paths: Sequence[str]) -> List[str]:
    return [
        f"slice {row.number} ({row.name}): surface `{pattern}` is outside implementation_paths"
        for row in rows
        for pattern in row.surface
        if not pattern_covered_by(pattern, implementation_paths)
    ]


def _ordering_problems(slices: Dict[int, SliceRow]) -> List[str]:
    cycle = find_cycle(slices)
    if cycle:
        # Ordering is undefined while a cycle exists, so the intersection check
        # only runs once the graph is confirmed acyclic.
        return ["cycle: " + " -> ".join(str(number) for number in cycle)]
    return [
        f"slices {a} and {b} have intersecting surfaces with no blocker between them"
        for a, b in combinations(sorted(slices), 2)
        if _surfaces_intersect(slices[a].surface, slices[b].surface) and not _ordered(slices, a, b)
    ]


def cmd_validate(args: argparse.Namespace) -> int:
    """Exit 0 for a buildable plan, 1 for plan problems, 2 when the spec cannot be read."""
    spec_path = args.spec
    try:
        implementation_paths = read_implementation_paths(spec_path)
        spec_text = read_text(spec_path)
        rows = parse_build_order(spec_text, spec_path)
    except (SpecPathError, SliceError, OSError) as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2

    slices = {row.number: row for row in rows}
    problems = (
        _interfaces_problems(spec_text)
        + _surface_problems(rows, implementation_paths)
        + _ordering_problems(slices)
        + _plan_block_problems(args.index, spec_path, slices)
    )
    for problem in problems:
        print(f"slice: {problem}", file=sys.stderr)
    return 1 if problems else 0


# -------------------------------------------------------------- readiness

# The visual plan renderer owns the spec parser; the readiness gate reads the
# spec through it so `/slice` and the page's disabled copy name the same ids.
_VISUAL_PLAN_SCRIPTS = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "visual-plan", "scripts")
)


def _use_visual_plan_parser() -> None:
    sys.dont_write_bytecode = True  # importing the renderer must leave no __pycache__ in its skill
    if _VISUAL_PLAN_SCRIPTS not in sys.path:
        sys.path.insert(0, _VISUAL_PLAN_SCRIPTS)


def cmd_readiness(args: argparse.Namespace) -> int:
    """Exit 0 silently when a build prompt may be printed, 1 with `not ready: <ids>`, 2 when unreadable."""
    _use_visual_plan_parser()
    from plan_md import SpecError  # noqa: E402  (path set up above)
    from plan_model import not_ready_ids, read_plan  # noqa: E402

    try:
        ids = not_ready_ids(read_plan(args.spec))
    except SpecError as exc:
        print(f"slice: {args.spec}:{exc.line}: {exc.reason}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2
    if ids:
        print("not ready: " + ", ".join(ids))
        return 1
    return 0


# ------------------------------------------------------------------ ready


def _normalize_spec_path(path: str) -> str:
    normalized = os.path.normpath(path).replace(os.sep, "/")
    return normalized[2:] if normalized.startswith("./") else normalized


def _find_plan_block(todo_text: str, spec_path: str) -> Optional[Tuple[int, int, str]]:
    """1-based (start_line, end_line, plan_name) of the `## Plan:` block naming `spec_path`."""
    lines = todo_text.splitlines()
    target = _normalize_spec_path(spec_path)
    starts = [index for index, line in enumerate(lines) if PLAN_HEADING_RE.match(line)]
    for position, start in enumerate(starts):
        end = starts[position + 1] if position + 1 < len(starts) else len(lines)
        for offset in range(start, end):
            match = SPEC_LINE_RE.match(lines[offset])
            if match and _normalize_spec_path(match.group("path")) == target:
                name = PLAN_HEADING_RE.match(lines[start]).group("name")
                return start + 1, end, name
    return None


def _slice_headings(lines: Sequence[str], start_line: int, end_line: int) -> List[Tuple[int, int, str]]:
    """(1-based line, slice number, name) for every `### Slice` heading in range."""
    headings = []
    for line_number in range(start_line, end_line + 1):
        match = SLICE_HEADING_RE.match(lines[line_number - 1])
        if match:
            headings.append((line_number, int(match.group("number")), match.group("name")))
    return headings


@dataclass(frozen=True)
class PlanBlock:
    """One `## Plan:` block of the index: where it is, its rows, and what they mean.

    Callers ask it for a slice's mode and lines; none re-derive either from
    the heading list.
    """

    prose: List[str]  # the index with every fenced line blanked
    start_line: int
    end_line: int
    name: str
    headings: List[Tuple[int, int, str]]
    index_path: str

    @cached_property
    def rows(self) -> List[IndexRow]:
        """The index's rows, parsed on first use: `validate` never needs them and must not refuse over them."""
        return load_index_strict(self.index_path, self.index_path).rows

    @property
    def legacy(self) -> bool:
        """Legacy when any slice header row carries a `task-id` marker."""
        for heading_line, _number, _name, boundary in _heading_spans(self.headings, self.end_line):
            row = _row_after(self.rows, heading_line, boundary, self.prose)
            if row is not None and "task-id:" in self.prose[row.line - 1]:
                return True
        return False

    def mode(self, row: SliceRow, interface_paths: Sequence[str]) -> str:
        """`design` when a § Interfaces `Path:` falls inside the slice's Surface and the block is new."""
        if self.legacy:
            return "tdd"
        hit = any(match_path(pattern, path) for pattern in row.surface for path in interface_paths)
        return "design" if hit else "tdd"

    def slice_lines(self, number: int) -> Optional[List[str]]:
        """The lines under slice `number`'s heading, or None when it has no heading."""
        for heading_line, heading_number, _title, boundary in _heading_spans(self.headings, self.end_line):
            if heading_number == number:
                return self.prose[heading_line:boundary]
        return None


def _find_loaded_block(index_path: str, spec_path: str) -> Optional[PlanBlock]:
    """The `## Plan:` block of `index_path` naming `spec_path`, or None when the file or block is absent."""
    if not os.path.isfile(index_path):
        return None
    todo_text = _without_fences(read_text(index_path))
    block = _find_plan_block(todo_text, spec_path)
    if block is None:
        return None
    start_line, end_line, name = block
    prose = todo_text.splitlines()
    return PlanBlock(prose, start_line, end_line, name, _slice_headings(prose, start_line, end_line), index_path)


def _load_plan_block(index_path: str, spec_path: str) -> PlanBlock:
    """The `## Plan:` block of `index_path` naming `spec_path`, or SliceError."""
    if not os.path.isfile(index_path):
        raise SliceError(f"no such index file: {index_path}")
    block = _find_loaded_block(index_path, spec_path)
    if block is None:
        raise SliceError(f"{index_path} has no `## Plan:` block naming {spec_path!r}")
    return block


def _heading_spans(
    headings: Sequence[Tuple[int, int, str]], end_line: int
) -> List[Tuple[int, int, str, int]]:
    """Each heading with the last 1-based line it owns: up to the next heading, else the block's end."""
    boundaries = [heading[0] - 1 for heading in headings[1:]] + [end_line]
    return [(line, number, name, boundary) for (line, number, name), boundary in zip(headings, boundaries)]


def _tdd_surface_problems(
    prose: Sequence[str], headings: Sequence[Tuple[int, int, str]], end_line: int, slices: Dict[int, SliceRow]
) -> List[str]:
    """Every open `TDD:` row's test file must be matched by its slice's surface.

    The agent a slice dispatches may edit only that surface, so a row naming a
    test outside it is a slice that cannot write its own test. Found live on
    specs/design-stack-hyperframes.md slice 4, whose surface named only skill
    text while its row targeted `tests/test-design-stack-video.sh`. The last
    heading's span ends at the next `##` heading: the block runs on to the
    next `## Plan:`, and the session summaries between carry rows of their own.
    """
    problems = []
    for heading_line, number, _name, boundary in _heading_spans(headings, end_line):
        if number not in slices:
            continue
        for line_number in range(heading_line + 1, boundary + 1):
            line = prose[line_number - 1]
            if H2_RE.match(line):
                break
            match = OPEN_TDD_ROW_RE.match(line)
            if match and not any(match_path(pattern, match.group("path")) for pattern in slices[number].surface):
                problems.append(
                    f"slice {number} ({slices[number].name}): TDD row names {match.group('path')}, "
                    "which no surface pattern matches"
                )
    return problems


def _feature_link_problems(
    index_path: str, prose: Sequence[str], start_line: int, headings: Sequence[Tuple[int, int, str]]
) -> List[str]:
    """A block links its feature once: one `> Issue:` line or one feature row, never two.

    The feature link sits between the `## Plan:` heading and the first
    `### Slice` heading; a slice's own header row is not one. The refusal names
    the second link, the line a human deletes. A flat legacy plan has no
    headings, so its rows are tasks, not links.
    """
    if not headings:
        return []
    links = [
        line_number
        for line_number in range(start_line + 1, headings[0][0])
        if ISSUE_LINE_RE.match(prose[line_number - 1]) or FEATURE_ROW_RE.match(prose[line_number - 1])
    ]
    return [
        f"{index_path}:{line_number}: two feature links in one plan block (one `> Issue:` line or one feature row)"
        for line_number in links[1:2]
    ]


def _plan_block_problems(index_path: str, spec_path: str, slices: Dict[int, SliceRow]) -> List[str]:
    """`validate`'s view of the plan block: feature-link and TDD-row problems when the index already holds one.

    Propose step 1 validates before the block is written, so a missing index
    or block is nothing to report here; `ready` requires the block and refuses.
    """
    block = _find_loaded_block(index_path, spec_path)
    if block is None:
        return []
    return _feature_link_problems(index_path, block.prose, block.start_line, block.headings) + _tdd_surface_problems(
        block.prose, block.headings, block.end_line, slices
    )


def _row_after(
    rows: Sequence[IndexRow], line_number: int, boundary: int, prose: Sequence[str]
) -> Optional[IndexRow]:
    """The earliest prose row strictly after `line_number` and no later than `boundary`.

    `prose` is the index text with every fenced line blanked, so a `- [ ]`
    example inside a fence is never mistaken for the heading's row.
    """
    candidates = [
        row for row in rows if line_number < row.line <= boundary and prose[row.line - 1].strip()
    ]
    return min(candidates, key=lambda row: row.line) if candidates else None


def _block_has_open_row(rows: Sequence[IndexRow], start_line: int, end_line: int) -> bool:
    return any(start_line <= row.line <= end_line and row.task.status == "open" for row in rows)


def _print_ready(number: int, name: str, surface: Sequence[str], mode: str = "tdd") -> None:
    print(f"ready: {number} {name} mode={mode}")
    print(f"  surface: {', '.join(surface)}")


def _done_by_slice(
    rows: Sequence[IndexRow], headings: Sequence[Tuple[int, int, str]], end_line: int, prose: Sequence[str]
) -> Dict[int, bool]:
    """Whether each `### Slice` heading's header row is `[x]`, keyed by slice number."""
    done: Dict[int, bool] = {}
    for heading_line, number, _name, boundary in _heading_spans(headings, end_line):
        row = _row_after(rows, heading_line, boundary, prose)
        if row is None:
            raise SliceError(f"no task row found under `### Slice {number}` heading")
        done[number] = row.task.status == "done"
    return done


def _refuse_plan_drift(
    slices: Dict[int, SliceRow], done: Dict[int, bool], spec_path: str, index_path: str
) -> None:
    """Every Build Order row has a `### Slice` heading and every heading names a row.

    A row with no heading would never be ready and never be named; a heading
    with no row would be ignored. Both mean the plan block drifted from the
    table after `/slice` wrote them, and silence here is a slice that waits
    forever on a blocker nothing can close.
    """
    table_only = sorted(set(slices) - set(done))
    plan_only = sorted(set(done) - set(slices))
    if table_only or plan_only:
        raise SliceError(
            f"{index_path} drifted from {spec_path} § Build Order: slices {table_only} have no "
            f"`### Slice` heading; headings {plan_only} name no Build Order row"
        )


def _ready_numbers(slices: Dict[int, SliceRow], done: Dict[int, bool]) -> List[int]:
    """Open slices whose every blocker is done, in table order."""
    return [
        number
        for number in sorted(slices)
        if number in done
        and not done[number]
        and all(done.get(dep, False) for dep in slices[number].blocked_by)
    ]


def _print_ready_set(
    slices: Dict[int, SliceRow], ready_numbers: Sequence[int], interface_paths: Sequence[str], block: PlanBlock
) -> None:
    for number in ready_numbers:
        row = slices[number]
        _print_ready(number, row.name, row.surface, block.mode(row, interface_paths))
    for a, b in combinations(ready_numbers, 2):
        if _surfaces_intersect(slices[a].surface, slices[b].surface) and not _ordered(slices, a, b):
            print(f"intersects: {a} \u2194 {b} (no blocker; serialize in table order)")


def _implicit_slice_ready(args: argparse.Namespace, block: PlanBlock) -> int:
    """Edge Case: a flat legacy plan predates `### Slice` headings.

    It is one implicit slice whose surface is the spec's whole implementation_paths.
    """
    if not _block_has_open_row(block.rows, block.start_line, block.end_line):
        return 0
    _print_ready(1, block.name, read_implementation_paths(args.spec))
    return 0


def cmd_ready(args: argparse.Namespace) -> int:
    """Exit 0 with the ready set on stdout; 2 when the index, block or spec cannot be read."""
    try:
        block = _load_plan_block(args.index, args.spec)
        if not block.headings:
            return _implicit_slice_ready(args, block)
        spec_text = read_text(args.spec)
        slices = {row.number: row for row in parse_build_order(spec_text, args.spec)}
        done = _done_by_slice(block.rows, block.headings, block.end_line, block.prose)
        _refuse_plan_drift(slices, done, args.spec, args.index)
        problems = _tdd_surface_problems(block.prose, block.headings, block.end_line, slices)
        if problems:
            raise SliceError("; ".join(problems))
    except (SpecPathError, SliceError, IndexUnreadable, OSError) as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2
    _print_ready_set(slices, _ready_numbers(slices, done), _interface_paths(spec_text), block)
    return 0


# ------------------------------------------------------------------ check


def _git_changed_paths(repo: str, base: str) -> List[str]:
    return _git_paths(repo, f"{base}..HEAD")


def _git_paths(repo: str, *diff_args: str, renames: bool = True) -> List[str]:
    """Paths `git diff` names. `renames=False` lists a rename as delete plus add: the freeze check needs the old path."""
    rename_flag = () if renames else ("--no-renames",)
    result = subprocess.run(
        ("git", "-C", repo, "diff", "--name-only", *rename_flag, *diff_args),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise SliceError(f"git diff --name-only {' '.join(diff_args)} failed: {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


def _slice_plan(index_path: str, spec_path: str, row: SliceRow) -> Optional[Tuple[List[str], str]]:
    """(the lines under the slice's heading, its mode), or None for a flat plan with no headings."""
    block = _load_plan_block(index_path, spec_path)
    if not block.headings:
        return None
    lines = block.slice_lines(row.number)
    if lines is None:
        raise SliceError(f"{index_path} has no `### Slice {row.number}` heading under its `## Plan:` block")
    return lines, block.mode(row, _interface_paths(read_text(spec_path)))


def _freeze_problems(args: argparse.Namespace, repo: str, row: SliceRow) -> List[str]:
    """`frozen-edited:`, `amended-unknown:`, `duplicate freeze line` and `missing freeze commit`.

    The freeze lives in the plan block, never in `/build`'s context, so it
    survives compaction. A recorded freeze is always checked, whatever mode the
    slice derives now; a design-mode slice with none is missing it. Contract
    tests are what `S..F` changed outside `tasks/`.
    """
    plan = _slice_plan(args.index, args.spec, row)
    if plan is None:
        return []
    lines, mode = plan
    frozen_lines = [m for m in map(FROZEN_LINE_RE.match, lines) if m]
    if not frozen_lines:
        return ["missing freeze commit"] if mode == "design" else []
    frozen = frozen_lines[0]
    problems = ["duplicate freeze line"] if len(frozen_lines) > 1 else []
    def paths(*diff_args: str) -> List[str]:
        return _git_paths(repo, *diff_args, renames=False)

    contract = [p for p in paths(f"{frozen.group('s')}..{frozen.group('f')}") if not p.startswith("tasks/")]
    after = paths(f"{frozen.group('f')}..HEAD")
    added = paths("--diff-filter=A", f"{frozen.group('f')}..HEAD")
    # AC10: a new file in a contract test's own directory, not a subdirectory.
    # A root-level contract test protects only itself: "" would freeze every new root file.
    directories = {os.path.dirname(path) for path in contract} - {""}
    new_beside = [p for p in added if not p.startswith("tasks/") and os.path.dirname(p) in directories]
    amended = [m.group("path") for m in map(AMENDED_LINE_RE.match, lines) if m]
    known = set(contract) | set(new_beside)
    edited = [p for p in after if p in known and p not in amended]
    unknown = [p for p in amended if p not in known]
    return problems + [f"frozen-edited: {p}" for p in edited] + [f"amended-unknown: {p}" for p in unknown]


def _warn_freeze_unchecked(args: argparse.Namespace, repo: str, row: SliceRow) -> None:
    """Say so on stderr when a design-mode slice runs `check` without `--index`.

    Best effort: the mode is read from the repo's own `tasks/todo.md`; a missing
    file, block or heading means there is nothing to say, never a failure.
    """
    index_path = os.path.join(repo, "tasks", "todo.md")
    if not os.path.isfile(index_path):
        return
    try:
        plan = _slice_plan(index_path, args.spec, row)
    except (SliceError, IndexUnreadable, OSError, ValueError):
        return
    if plan is not None and plan[1] == "design":
        print("freeze: not checked (no --index)", file=sys.stderr)


def cmd_check(args: argparse.Namespace) -> int:
    """Exit 0 when the diff stayed inside the slice's surface, 1 when it did not, 3 on a freeze problem, 2 on bad input."""
    implicit_name = os.path.splitext(os.path.basename(args.spec))[0]
    try:
        slices = resolve_slices(args.spec, implicit_name)
    except (SpecPathError, SliceError, OSError) as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2
    row = slices.get(args.slice)
    if row is None:
        print(f"slice: no slice {args.slice} in {args.spec}", file=sys.stderr)
        return 2

    try:
        changed = _git_changed_paths(args.repo or ".", args.base)
    except SliceError as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2

    undeclared = [path for path in changed if not any(match_path(pattern, path) for pattern in row.surface)]
    untouched = [pattern for pattern in row.surface if not any(match_path(pattern, path) for path in changed)]

    freeze: List[str] = []
    if args.index:
        try:
            freeze = _freeze_problems(args, args.repo or ".", row)
        except (SliceError, IndexUnreadable, OSError) as exc:
            print(f"slice: {exc}", file=sys.stderr)
            return 2
    else:
        _warn_freeze_unchecked(args, args.repo or ".", row)

    exit_code = 0
    if undeclared:
        print("undeclared: " + ", ".join(undeclared))
        exit_code = 1
    if untouched:
        print("untouched: " + ", ".join(untouched))
        exit_code = 1
    for problem in freeze:
        print(problem)
    return 3 if freeze else exit_code


# --------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="slice", description="Validate, list, and check the slices in a spec's § Build Order."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    validate_parser = sub.add_parser("validate", help="Refuse a Build Order that cannot be built as written.")
    validate_parser.add_argument("--spec", required=True, help="path to the spec")
    validate_parser.add_argument(
        "--index", default="tasks/todo.md",
        help="path to tasks/todo.md; its `## Plan:` block's feature link and TDD rows are checked when it already exists",
    )

    ready_parser = sub.add_parser("ready", help="List the slices ready to dispatch right now.")
    ready_parser.add_argument("--index", required=True, help="path to tasks/todo.md")
    ready_parser.add_argument("--spec", required=True, help="path to the spec")

    readiness_parser = sub.add_parser(
        "readiness", help="Refuse a build prompt while a decision is open or a question blocks a slice.")
    readiness_parser.add_argument("--spec", required=True, help="path to the spec")

    check_parser = sub.add_parser("check", help="Check a closed slice's diff against its declared surface.")
    check_parser.add_argument("--spec", required=True, help="path to the spec")
    check_parser.add_argument("--slice", required=True, type=int, help="slice number")
    check_parser.add_argument("--base", required=True, help="base revision to diff against")
    check_parser.add_argument("--repo", default=None, help="repository to diff (default: cwd)")
    check_parser.add_argument(
        "--index", default=None,
        help="path to tasks/todo.md; a design-mode slice's `> Frozen:` and `> Test amended:` lines are checked",
    )

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "validate":
        return cmd_validate(args)
    if args.command == "ready":
        return cmd_ready(args)
    if args.command == "readiness":
        return cmd_readiness(args)
    return cmd_check(args)


if __name__ == "__main__":
    # `ready` prints a non-ASCII separator; a Windows console defaults to
    # cp1252 and would die on it whenever PYTHONUTF8 is not exported.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    sys.exit(main())
