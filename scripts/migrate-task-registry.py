#!/usr/bin/env python3
"""One-shot migration for a `tasks/todo.md` that predates the task registry.

Replaces the `task-registry migrate` subcommand, retired with the Jira adapter in
Cut 1 of `specs/workflow-routing.md`. It lives here, outside the skill, for the
same reason `scripts/migrate-learning-store.py` does: a conversion every project
runs once should not be carried in the skill forever, and `.agents/skills/` is a
syncable root that `/sync` overwrites wholesale.

**Self-contained on purpose.** It imports nothing from the skill. Cut 2 deletes
`registry/index.py` and `registry/reconcile.py`, which the retired module read
its index and specs through, so a one-shot that imported them would break one
phase after it shipped. The row parser below is a deliberately narrower vendored
copy: this tool needs a line, a status box, an id, a title, and `blocked-by:`,
and none of the link, kind, or reference handling the live index does.

Input is whatever the repository already has: a `tasks/todo.md` of plan blocks
and checkboxes, an optional `tasks/backlog.md`, and specs under `specs/`,
`specs/pending/`, `specs/completed/`. Output is a *proposal*: classifications,
minted IDs, grouping, and an audit trail. Dry-run is the default; `--apply` only
ever writes locally.

Three rules the classifier exists to keep:

* One external task per *deliverable*, never one per historical checkbox. A
  closed plan block with 9 ticked rows is history, not backlog.
* Operational verification work is first-class (`operational`), not noise to drop.
* Nothing unresolved is deleted. `stale` and `superseded` are labels a human then
  acts on; this tool only ever adds them to a report.

Usage:

    python3 scripts/migrate-task-registry.py                 # dry run, this repo
    python3 scripts/migrate-task-registry.py --apply         # mint ids + audit
    python3 scripts/migrate-task-registry.py --repo ../other --index docs/plan.md

Paths default to the registry's own defaults, so a project that never changed
them passes no flags. Unlike the retired subcommand this reads no configuration
file: a one-shot with explicit inputs has no config-load failure mode to define
away, and the values it needs are five strings.
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

AUDIT_PATH = "tasks/task-registry-migration.md"
TERMINAL_STATUSES: Tuple[str, ...] = ("done", "cancelled")

#: Status box characters, matching the live index's vocabulary.
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

ROW_RE = re.compile(r"^(?P<indent>[ \t]*)(?P<bullet>[-*]\s+)?\[(?P<box>.?)\](?P<rest>.*)$")
TASK_ID_RE = re.compile(r"<!--\s*task-id:\s*(?P<id>[^\s>]+?)\s*-->")
DEPS_RE = re.compile(
    r"[(\[]\s*(?:blocked-by|depends-on|deps)\s*:\s*(?P<ids>[^)\]]+)[)\]]", re.IGNORECASE
)
LINK_RE = re.compile(
    r"\((?P<label>\[[^\]]+\])\((?P<url>[^)\s]+)\)\)"
    r"|\[(?P<bare>[^\]]+)\]\((?P<bare_url>[^)\s]+)\)"
)
SUMMARY_SPLIT = re.compile(r"\s+[—–]\s+")
ARROW_SPLIT = re.compile(r"(?<!-)->")
PLAN_HEADING_RE = re.compile(r"^##+\s+(?P<title>.+?)\s*$")
SPEC_REFERENCE_RE = re.compile(r"(?P<path>specs?/[A-Za-z0-9._/-]+\.md)")
SUPERSEDED_RE = re.compile(r"^>?\s*superseded\s+by[:\s]+(?P<by>.+?)\s*$", re.IGNORECASE | re.MULTILINE)

#: The heading that marks a plan block as finished. "Session Summary" is this
#: harness's convention, not a universal one, so a project that closes its plans
#: differently passes `--closed-plan-marker`.
DEFAULT_CLOSED_PLAN_MARKER = "Session Summary"

#: Keyword classification is a heuristic and is reported as one. It never
#: overrides an explicit id already present in a row.
KIND_KEYWORDS = (
    ("operational", ("verify", "verification", "deploy", "deployment", "e2e", "smoke",
                     "monitor", "runbook", "rollout", "incident", "health check")),
    ("bug", ("bug", "fix ", "fixes", "regression", "broken", "crash", "hotfix")),
    ("decision", ("decide", "decision", "adr", "choose", "trade-off", "tradeoff")),
    ("research", ("research", "spike", "investigate", "explore", "prototype", "evaluate")),
    ("epic", ("epic", "milestone", "phase")),
)


def slugify_id(*parts: str) -> str:
    """Mint a stable ID from human text. Dotted segments read as a hierarchy hint."""
    cleaned = []
    for part in parts:
        if not part:
            continue
        text = re.sub(r"[^a-zA-Z0-9]+", "-", part.strip().lower()).strip("-")
        if text:
            cleaned.append(text)
    return ".".join(cleaned) or "task"


# ------------------------------------------------------------------ index model


@dataclass(frozen=True)
class Row:
    line: int          # 1-based, matching what an editor shows
    raw: str
    title: str
    status: str
    task_id: str       # "" when the row has no stable identity yet
    depends_on: Tuple[str, ...] = ()


class Index:
    """The subset of the live `TaskIndex` this migration needs.

    Rewrites are line-addressed and surgical: migration is not an excuse to
    reformat a human's index, so untouched lines are written back byte-for-byte.
    """

    def __init__(self, path: str, text: str, relative_path: str) -> None:
        self.path = path
        self.relative_path = relative_path
        self._lines = text.splitlines()
        self._trailing_newline = text.endswith("\n")
        self.rows: List[Row] = []
        self.problems: List[str] = []
        self._parse()

    def _parse(self) -> None:
        for number, line in enumerate(self._lines, start=1):
            match = ROW_RE.match(line)
            if not match:
                continue
            box = match.group("box")
            if box not in BOX_TO_STATUS:
                self.problems.append(
                    f"{self.relative_path}:{number} — unknown status box '[{box}]'"
                )
                continue
            rest = match.group("rest")
            task_id, rest = _extract_id(rest)
            depends_on, rest = _extract_dependencies(rest)
            rest = LINK_RE.sub("", rest)
            title = _title_of(rest)
            if not title:
                self.problems.append(
                    f"{self.relative_path}:{number} — row has a status box but no title"
                )
                continue
            self.rows.append(
                Row(
                    line=number,
                    raw=line,
                    title=title,
                    status=BOX_TO_STATUS[box],
                    task_id=task_id,
                    depends_on=depends_on,
                )
            )

    def line_text(self, line: int) -> str:
        return self._lines[line - 1]

    def replace_line(self, line: int, new_text: str) -> None:
        self._lines[line - 1] = new_text

    def render(self) -> str:
        text = "\n".join(self._lines)
        return text + "\n" if self._trailing_newline else text

    def save(self) -> None:
        write_text(self.path, self.render())


def _extract_id(rest: str) -> Tuple[str, str]:
    match = TASK_ID_RE.search(rest)
    if not match:
        return "", rest
    return match.group("id"), rest[: match.start()] + rest[match.end():]


def _extract_dependencies(rest: str) -> Tuple[Tuple[str, ...], str]:
    match = DEPS_RE.search(rest)
    if not match:
        return (), rest
    # Comma-separated, never whitespace-separated: before migration a dependency
    # names a row by its *wording*, and "Colour LUT pass" is one blocker, not three.
    ids = tuple(part.strip() for part in match.group("ids").split(",") if part.strip())
    return ids, rest[: match.start()] + rest[match.end():]


def _title_of(rest: str) -> str:
    """The row's title: everything before the em-dash summary or the `->` detail."""
    cleaned = re.sub(r"\s{2,}", " ", rest).strip()
    cleaned = re.sub(r"^[-*]\s+", "", cleaned)
    head = SUMMARY_SPLIT.split(cleaned, 1)[0]
    head = ARROW_SPLIT.split(head, 1)[0]
    return head.strip().strip("`").strip()


def load_index(path: str, relative_path: str) -> Index:
    with open(path, "r", encoding="utf-8") as handle:
        return Index(path, handle.read(), relative_path)


def write_text(path: str, text: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def scan_superseded_specs(root: str, spec_dir: str) -> set:
    """Specs that declare themselves superseded. Their rows are not live backlog."""
    superseded = set()
    spec_root = os.path.join(root, spec_dir)
    if not os.path.isdir(spec_root):
        return superseded
    for directory, _, filenames in os.walk(spec_root):
        for filename in sorted(filenames):
            if not filename.endswith(".md") or filename == "README.md":
                continue
            absolute = os.path.join(directory, filename)
            relative = os.path.relpath(absolute, root).replace(os.sep, "/")
            try:
                with open(absolute, "r", encoding="utf-8") as handle:
                    text = handle.read()
            except OSError as exc:
                print(f"warning: cannot read {relative}: {exc}", file=sys.stderr)
                continue
            if SUPERSEDED_RE.search(text):
                superseded.add(relative)
    return superseded


# ------------------------------------------------------------------- the plan


@dataclass(frozen=True)
class MigrationEntry:
    line: int
    title: str
    status: str
    classification: str  # active | completed | stale | superseded
    kind: str
    task_id: str
    group: str
    spec_path: Optional[str] = None
    existing_id: bool = False

    def render(self) -> str:
        marker = " (id already present)" if self.existing_id else ""
        spec = f" spec={self.spec_path}" if self.spec_path else ""
        return (
            f"  line {self.line:>4}  {self.classification:<10} {self.kind:<11} "
            f"{self.task_id}{marker}{spec}  — {_short(self.title)}"
        )


@dataclass
class MigrationPlan:
    root: str
    index_path: str
    entries: List[MigrationEntry] = field(default_factory=list)
    problems: List[str] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)
    #: `blocked-by:` text that names a row by wording -> the id minted for it.
    dependency_rewrites: Dict[str, str] = field(default_factory=dict)
    unresolved_dependencies: List[str] = field(default_factory=list)
    applied: bool = False

    def by_classification(self, name: str) -> List[MigrationEntry]:
        return [entry for entry in self.entries if entry.classification == name]

    def proposed_groups(self) -> Dict[str, List[MigrationEntry]]:
        """Active work only, grouped by its plan block — the unit of an external task."""
        groups: Dict[str, List[MigrationEntry]] = {}
        for entry in self.entries:
            if entry.classification in ("active", "stale"):
                groups.setdefault(entry.group, []).append(entry)
        return groups

    def render(self) -> str:
        groups = self.proposed_groups()
        lines = [
            "migrate-task-registry — "
            + ("APPLIED" if self.applied else "DRY RUN (nothing written)"),
            "",
            "Summary:",
            f"  rows scanned:        {len(self.entries)}",
            f"  active:              {len(self.by_classification('active'))}",
            f"  stale (open in a closed plan): {len(self.by_classification('stale'))}",
            f"  completed (history, no external task): {len(self.by_classification('completed'))}",
            f"  superseded:          {len(self.by_classification('superseded'))}",
            f"  proposed external tasks: {len(groups)} group(s) covering "
            f"{sum(len(v) for v in groups.values())} row(s)",
        ]
        if groups:
            lines += [
                "",
                "Proposed grouping (one external task per group, not per checkbox) — a "
                "recommendation for the human who publishes, not something this "
                "command applies:",
            ]
            for group, entries in sorted(groups.items()):
                lines.append(f"  {group}: {len(entries)} row(s)")
                lines += [f"    - {entry.task_id}  {_short(entry.title, 60)}" for entry in entries]
        for classification in ("active", "stale", "superseded", "completed"):
            selected = self.by_classification(classification)
            if not selected:
                continue
            lines += ["", f"{classification}:"]
            lines += [entry.render() for entry in selected[:40]]
            if len(selected) > 40:
                lines.append(f"  … {len(selected) - 40} more")
        if self.dependency_rewrites:
            lines += ["", "Dependency references to rewrite:"]
            lines += [
                f"  {old} -> {new}" for old, new in sorted(self.dependency_rewrites.items())
            ]
        if self.unresolved_dependencies:
            lines += ["", "Unresolved dependencies (reported, nothing dropped):"]
            lines += [f"  - {item}" for item in self.unresolved_dependencies]
        if self.notes:
            lines += ["", "Notes:"] + [f"  - {note}" for note in self.notes]
        if self.problems:
            lines += ["", "Malformed input (reported, nothing dropped):"]
            lines += [f"  - {problem}" for problem in self.problems]
        lines += [
            "",
            "Nothing here is deleted. Unresolved rows keep their text; classification is a "
            "label for a human to act on.",
        ]
        return "\n".join(lines)


@dataclass(frozen=True)
class Paths:
    root: str
    index_path: str
    backlog_path: str
    spec_dir: str
    closed_plan_marker: str

    def path(self, relative: str) -> str:
        return os.path.join(self.root, relative)


def plan_migration(paths: Paths) -> MigrationPlan:
    index = load_index(paths.path(paths.index_path), paths.index_path)
    plan = MigrationPlan(root=paths.root, index_path=paths.index_path)
    plan.problems += list(index.problems)

    marker = _closed_marker_re(paths.closed_plan_marker)
    groups = _group_lines(index, marker)
    block_starts = _block_starts(index)
    closed_groups = _closed_groups(index, marker)
    if not closed_groups and index.rows:
        plan.notes.append(
            f"no '{paths.closed_plan_marker}' heading found, so no plan block could be read "
            "as closed — every open row is classified active; pass --closed-plan-marker if "
            "this project closes plans differently"
        )
    superseded_specs = scan_superseded_specs(paths.root, paths.spec_dir)
    # Seeded with the ids already in the index: minting `recipe.morph` a second
    # time would hand two different rows the same identity, which is the one
    # thing an identity must never do.
    minted: Dict[str, int] = {row.task_id: 1 for row in index.rows if row.task_id}

    for row in index.rows:
        group = groups.get(row.line, "ungrouped")
        spec_path = _spec_for(index, row.line, block_starts.get(row.line, 1))
        classification = _classify(row.status, group in closed_groups, spec_path, superseded_specs)
        plan.entries.append(
            MigrationEntry(
                line=row.line,
                title=row.title,
                status=row.status,
                classification=classification,
                kind=_kind_for(row.title, group),
                task_id=row.task_id or _mint(group, row.title, minted),
                group=group,
                spec_path=spec_path,
                existing_id=bool(row.task_id),
            )
        )

    _resolve_dependencies(index, plan)
    _add_backlog_notes(paths, plan)
    plan.notes.append(
        "kind is inferred from row wording and the plan heading — review before publishing"
    )
    plan.notes.append(
        "completed rows are recorded as history and are never published as external tasks"
    )
    return plan


def apply_migration(paths: Paths, plan: MigrationPlan) -> List[str]:
    """Write stable IDs into the index and leave an audit trail. Local writes only."""
    index = load_index(paths.path(paths.index_path), paths.index_path)
    actions: List[str] = []
    written = 0
    for entry in plan.entries:
        # Everything still unresolved gets an identity — active, stale, and
        # superseded alike. Identity is not publication: a row left without an id
        # is a row no command can name.
        if entry.existing_id or entry.classification == "completed":
            continue
        row = next((candidate for candidate in index.rows if candidate.line == entry.line), None)
        if row is None:  # pragma: no cover - index re-read is identical
            continue
        index.replace_line(row.line, _insert_id(row.raw, entry.task_id))
        written += 1
    rewritten = _rewrite_dependencies(index, plan)
    if written or rewritten:
        index.save()
    actions.append(f"minted {written} stable task id(s) in {paths.index_path}")
    if rewritten:
        actions.append(f"rewrote {rewritten} dependency reference(s) to minted ids")
    if plan.unresolved_dependencies:
        actions.append(
            f"{len(plan.unresolved_dependencies)} dependency reference(s) could not be "
            "resolved and were left as written — see the audit trail"
        )
    write_text(paths.path(AUDIT_PATH), _render_audit(plan))
    actions.append(f"audit trail written to {AUDIT_PATH}")
    plan.applied = True
    return actions


# --------------------------------------------------------------------- helpers


def _insert_id(raw: str, task_id: str) -> str:
    """Add the identity comment after the title, leaving the rest of the row alone."""
    if "<!-- task-id:" in raw:
        return raw
    marker = f" <!-- task-id: {task_id} -->"
    for separator in (" — ", " – ", " -> "):
        if separator in raw:
            head, tail = raw.split(separator, 1)
            return f"{head}{marker}{separator}{tail}"
    return raw.rstrip() + marker


def _closed_marker_re(marker_text: str) -> "re.Pattern[str]":
    return re.compile(r"^##+\s+" + re.escape(marker_text), re.IGNORECASE)


def _heading_slug(title: str) -> str:
    return slugify_id(
        re.sub(r"^(plan|task \d+)\s*[:—-]?\s*", "", title, flags=re.IGNORECASE)
    )


def _rewrite_dependencies(index: Index, plan: MigrationPlan) -> int:
    """Replace resolved `blocked-by:` wording with the minted id, in place."""
    if not plan.dependency_rewrites:
        return 0
    rewritten = 0
    for row in index.rows:
        raw = index.line_text(row.line)
        updated = raw
        for old, new in plan.dependency_rewrites.items():
            updated = re.sub(
                r"(?<=[:,\s])" + re.escape(old) + r"(?=\s*[,)\]])", new, updated
            )
        if updated != raw:
            index.replace_line(row.line, updated)
            rewritten += 1
    return rewritten


def _group_lines(index: Index, marker: "re.Pattern[str]") -> Dict[int, str]:
    """Map every row line to the heading block that contains it."""
    mapping: Dict[int, str] = {}
    current = "ungrouped"
    row_lines = {row.line for row in index.rows}
    for number, line in enumerate(index.render().splitlines(), start=1):
        match = PLAN_HEADING_RE.match(line)
        if match and not marker.match(line):
            current = _heading_slug(match.group("title"))
        if number in row_lines:
            mapping[number] = current
    return mapping


def _block_starts(index: Index) -> Dict[int, int]:
    """Line number of the heading each row sits under. Bounds every lookback."""
    starts: Dict[int, int] = {}
    current = 1
    row_lines = {row.line for row in index.rows}
    for number, line in enumerate(index.render().splitlines(), start=1):
        if PLAN_HEADING_RE.match(line):
            current = number
        if number in row_lines:
            starts[number] = current
    return starts


def _closed_groups(index: Index, marker: "re.Pattern[str]") -> set:
    """Groups followed by the closed-plan marker — their open rows are stale."""
    closed = set()
    current = "ungrouped"
    for line in index.render().splitlines():
        match = PLAN_HEADING_RE.match(line)
        if not match:
            continue
        if marker.match(line):
            closed.add(current)
            continue
        current = _heading_slug(match.group("title"))
    return closed


def _spec_for(index: Index, line: int, block_start: int) -> Optional[str]:
    """The nearest spec path above this row, never crossing into another plan.

    A fixed-size lookback walked straight past the heading above it and attached
    the previous plan's spec to this plan's first rows.
    """
    lines = index.render().splitlines()
    for candidate in range(min(line, len(lines)) - 1, block_start - 2, -1):
        match = SPEC_REFERENCE_RE.search(lines[candidate])
        if match:
            return match.group("path")
    return None


def _resolve_dependencies(index: Index, plan: MigrationPlan) -> None:
    """Point every `blocked-by:` at a minted id, and name the ones that cannot be.

    Before migration a dependency can only name a row by its wording, because no
    row has an id yet. Minting ids without rewriting those references leaves the
    index full of dependencies that resolve to nothing.
    """
    by_slug: Dict[str, str] = {}
    for entry in plan.entries:
        by_slug.setdefault(slugify_id(entry.title), entry.task_id)
    known = {entry.task_id for entry in plan.entries}
    for row in index.rows:
        for dependency in row.depends_on:
            if dependency in known:
                continue
            resolved = by_slug.get(slugify_id(dependency))
            if resolved:
                plan.dependency_rewrites[dependency] = resolved
            else:
                plan.unresolved_dependencies.append(
                    f"{plan.index_path}:{row.line} declares blocked-by {dependency!r}, "
                    "which names no row in this index — left as written for a human"
                )


def _classify(status: str, in_closed_group: bool, spec_path: Optional[str], superseded: set) -> str:
    if spec_path and spec_path in superseded:
        return "superseded"
    if status in TERMINAL_STATUSES:
        return "completed"
    return "stale" if in_closed_group else "active"


def _kind_for(title: str, group: str) -> str:
    haystack = f"{title} {group}".lower()
    for kind, keywords in KIND_KEYWORDS:
        if any(keyword in haystack for keyword in keywords):
            return kind
    return "feature"


def _mint(group: str, title: str, minted: Dict[str, int]) -> str:
    base = slugify_id(group, title)[:80]
    minted[base] = minted.get(base, 0) + 1
    return base if minted[base] == 1 else f"{base}-{minted[base]}"


def _add_backlog_notes(paths: Paths, plan: MigrationPlan) -> None:
    backlog = paths.path(paths.backlog_path)
    if not os.path.isfile(backlog):
        return
    backlog_index = load_index(backlog, paths.backlog_path)
    open_items = [row for row in backlog_index.rows if row.status not in TERMINAL_STATUSES]
    plan.notes.append(
        f"{paths.backlog_path}: {len(open_items)} open item(s) left in place — the backlog "
        "stays the ordered queue; publish from it deliberately, not automatically"
    )


def _render_audit(plan: MigrationPlan) -> str:
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "# Task Registry Migration Audit",
        "",
        f"> Generated {stamp} by `scripts/migrate-task-registry.py --apply`.",
        "> Every row scanned is listed. Nothing was deleted; IDs were added to every",
        "> unresolved row, and completed rows were recorded as history.",
        "",
        "| line | classification | kind | task id | spec | title |",
        "|------|----------------|------|---------|------|-------|",
    ]
    for entry in plan.entries:
        lines.append(
            f"| {entry.line} | {entry.classification} | {entry.kind} | `{entry.task_id}` | "
            f"{entry.spec_path or ''} | {_escape(entry.title)} |"
        )
    lines += ["", "## Proposed grouping", ""]
    for group, entries in sorted(plan.proposed_groups().items()):
        lines.append(f"- **{group}** — {len(entries)} row(s): " + ", ".join(
            f"`{entry.task_id}`" for entry in entries
        ))
    if plan.unresolved_dependencies:
        lines += ["", "## Unresolved dependencies", ""]
        lines += [f"- {item}" for item in plan.unresolved_dependencies]
    if plan.notes:
        lines += ["", "## Notes", ""] + [f"- {note}" for note in plan.notes]
    return "\n".join(lines) + "\n"


def _escape(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").replace("|", "\\|")).strip()


def _short(text: str, limit: int = 70) -> str:
    collapsed = re.sub(r"\s+", " ", text or "").strip()
    return collapsed if len(collapsed) <= limit else collapsed[: limit - 1] + "…"


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="migrate-task-registry.py",
        description="One-shot migration of a pre-registry tasks/todo.md: mint stable "
                    "task ids, classify rows, and write an audit trail.",
    )
    parser.add_argument("--repo", default=".", help="project root (default: .)")
    parser.add_argument("--index", default="tasks/todo.md", help="the task index to migrate")
    parser.add_argument("--backlog", default="tasks/backlog.md", help="ordered backlog, if any")
    parser.add_argument("--spec-dir", default="specs", help="where specs live")
    parser.add_argument(
        "--closed-plan-marker", default=DEFAULT_CLOSED_PLAN_MARKER,
        help="heading that marks a plan block as finished",
    )
    parser.add_argument(
        "--apply", action="store_true",
        help="write the minted ids and the audit trail (default: dry run)",
    )
    args = parser.parse_args(argv)

    paths = Paths(
        root=os.path.abspath(args.repo),
        index_path=args.index,
        backlog_path=args.backlog,
        spec_dir=args.spec_dir,
        closed_plan_marker=args.closed_plan_marker,
    )
    index_file = paths.path(paths.index_path)
    if not os.path.isfile(index_file):
        print(f"migrate-task-registry: no index at {paths.index_path} "
              f"(looked in {paths.root})", file=sys.stderr)
        return 1

    plan = plan_migration(paths)
    if args.apply:
        for action in apply_migration(paths, plan):
            print(action)
        print()
    print(plan.render())
    # Applying does not make malformed rows readable: the same rows are still
    # unparsed afterwards, so both branches report the same failure. A row this
    # tool could not read is a row it could not mint an id for, and exiting 0
    # would report a partial migration as a complete one.
    return 1 if plan.problems else 0


if __name__ == "__main__":
    sys.exit(main())
