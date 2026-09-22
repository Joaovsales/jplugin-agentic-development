#!/usr/bin/env python3
"""slice.py — validate, list, and check the slices in a spec's § Build Order.

`/slice` breaks a spec into session-sized slices and writes two artifacts: the
`## Build Order` table in the spec, and a `## Plan:` block in `tasks/todo.md`
with one `### Slice n/N` heading per row. This script answers the three
mechanical questions a human should never have to hold in their head:

  * **validate** — does the Build Order actually describe a buildable plan?
    Every surface inside `implementation_paths`, no cycle in `Blocked by`, and
    no pair of slices that overlap without an ordering between them.
  * **ready** — which slices can be dispatched right now, given which plan-block
    headers are already `[x]`?
  * **check** — after a slice closes, did its diff actually stay inside the
    surface it declared?

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
)
from registry.index import IndexRow, load_index  # noqa: E402

BUILD_ORDER_HEADING = "## Build Order"
PLAN_HEADING_RE = re.compile(r"^##\s*Plan:\s*(?P<name>.+?)\s*$")
SPEC_LINE_RE = re.compile(r"^>\s*Spec:\s*(?P<path>\S+)\s*$")
SLICE_HEADING_RE = re.compile(r"^###\s*Slice\s+(?P<number>\d+)/(?P<total>\d+)\s+—\s+(?P<name>.+?)\s*$")
H2_RE = re.compile(r"^##\s")


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


def _read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


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


def _split_surface(cell: str) -> Tuple[str, ...]:
    if cell in ("", "—", "-"):
        return ()
    parts = [part.strip().strip("`").strip() for part in cell.split(",")]
    return tuple(part for part in parts if part)


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
        number_text = cells[idx_number]
        if not number_text.isdigit():
            raise SliceError(f"{spec_path}: Build Order `#` cell is not a number: {number_text!r}")
        slices.append(
            SliceRow(
                number=int(number_text),
                name=cells[idx_name],
                surface=_split_surface(cells[idx_surface]),
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
        rows = parse_build_order(_read(spec_path), spec_path)
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
        rows = parse_build_order(_read(spec_path), spec_path)
    except (SpecPathError, SliceError, OSError) as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2

    slices = {row.number: row for row in rows}
    problems = _surface_problems(rows, implementation_paths) + _ordering_problems(slices)
    for problem in problems:
        print(f"slice: {problem}", file=sys.stderr)
    return 1 if problems else 0


# ------------------------------------------------------------------ ready


def _normalize_spec_path(path: str) -> str:
    return os.path.normpath(path).replace(os.sep, "/").lstrip("./")


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


def _print_ready(number: int, name: str, surface: Sequence[str]) -> None:
    print(f"ready: {number} {name}")
    print(f"  surface: {', '.join(surface)}")


def _done_by_slice(
    rows: Sequence[IndexRow], headings: Sequence[Tuple[int, int, str]], end_line: int, prose: Sequence[str]
) -> Dict[int, bool]:
    """Whether each `### Slice` heading's header row is `[x]`, keyed by slice number."""
    boundaries = [heading[0] - 1 for heading in headings[1:]] + [end_line]
    done: Dict[int, bool] = {}
    for (heading_line, number, _name), boundary in zip(headings, boundaries):
        row = _row_after(rows, heading_line, boundary, prose)
        if row is None:
            raise SliceError(f"no task row found under `### Slice {number}` heading")
        done[number] = row.task.status == "done"
    return done


def _ready_numbers(slices: Dict[int, SliceRow], done: Dict[int, bool]) -> List[int]:
    """Open slices whose every blocker is done, in table order."""
    return [
        number
        for number in sorted(slices)
        if number in done
        and not done[number]
        and all(done.get(dep, False) for dep in slices[number].blocked_by)
    ]


def _print_ready_set(slices: Dict[int, SliceRow], ready_numbers: Sequence[int]) -> None:
    for number in ready_numbers:
        _print_ready(number, slices[number].name, slices[number].surface)
    for a, b in combinations(ready_numbers, 2):
        if _surfaces_intersect(slices[a].surface, slices[b].surface) and not _ordered(slices, a, b):
            print(f"intersects: {a} \u2194 {b} (no blocker; serialize in table order)")


def _implicit_slice_ready(args: argparse.Namespace, index, start_line: int, end_line: int, plan_name: str) -> int:
    """Edge Case: a flat legacy plan predates `### Slice` headings.

    It is one implicit slice whose surface is the spec's whole implementation_paths.
    """
    if not _block_has_open_row(index.rows, start_line, end_line):
        return 0
    _print_ready(1, plan_name, read_implementation_paths(args.spec))
    return 0


def cmd_ready(args: argparse.Namespace) -> int:
    """Exit 0 with the ready set on stdout; 2 when the index, block or spec cannot be read."""
    if not os.path.isfile(args.index):
        print(f"slice: no such index file: {args.index}", file=sys.stderr)
        return 2
    todo_text = _without_fences(_read(args.index))
    block = _find_plan_block(todo_text, args.spec)
    if block is None:
        print(f"slice: {args.index} has no `## Plan:` block naming {args.spec!r}", file=sys.stderr)
        return 2
    start_line, end_line, plan_name = block
    prose = todo_text.splitlines()
    headings = _slice_headings(prose, start_line, end_line)
    index = load_index(args.index)
    try:
        if not headings:
            return _implicit_slice_ready(args, index, start_line, end_line, plan_name)
        slices = {row.number: row for row in parse_build_order(_read(args.spec), args.spec)}
        done = _done_by_slice(index.rows, headings, end_line, prose)
    except (SpecPathError, SliceError, OSError) as exc:
        print(f"slice: {exc}", file=sys.stderr)
        return 2
    _print_ready_set(slices, _ready_numbers(slices, done))
    return 0


# ------------------------------------------------------------------ check


def _git_changed_paths(repo: str, base: str) -> List[str]:
    result = subprocess.run(
        ("git", "-C", repo, "diff", "--name-only", f"{base}..HEAD"),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise SliceError(f"git diff --name-only {base}..HEAD failed: {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


def cmd_check(args: argparse.Namespace) -> int:
    """Exit 0 when the diff stayed inside the slice's surface, 1 when it did not, 2 on bad input."""
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

    exit_code = 0
    if undeclared:
        print("undeclared: " + ", ".join(undeclared))
        exit_code = 1
    if untouched:
        print("untouched: " + ", ".join(untouched))
        exit_code = 1
    return exit_code


# --------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="slice", description="Validate, list, and check the slices in a spec's § Build Order."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    validate_parser = sub.add_parser("validate", help="Refuse a Build Order that cannot be built as written.")
    validate_parser.add_argument("--spec", required=True, help="path to the spec")

    ready_parser = sub.add_parser("ready", help="List the slices ready to dispatch right now.")
    ready_parser.add_argument("--index", required=True, help="path to tasks/todo.md")
    ready_parser.add_argument("--spec", required=True, help="path to the spec")

    check_parser = sub.add_parser("check", help="Check a closed slice's diff against its declared surface.")
    check_parser.add_argument("--spec", required=True, help="path to the spec")
    check_parser.add_argument("--slice", required=True, type=int, help="slice number")
    check_parser.add_argument("--base", required=True, help="base revision to diff against")
    check_parser.add_argument("--repo", default=None, help="repository to diff (default: cwd)")

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "validate":
        return cmd_validate(args)
    if args.command == "ready":
        return cmd_ready(args)
    return cmd_check(args)


if __name__ == "__main__":
    # `ready` prints a non-ASCII separator; a Windows console defaults to
    # cp1252 and would die on it whenever PYTHONUTF8 is not exported.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    sys.exit(main())
