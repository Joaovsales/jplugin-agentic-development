"""Migration for repositories that predate the registry.

Input is whatever the repository already has: a `tasks/todo.md` of plan blocks and
checkboxes, an optional `tasks/backlog.md`, and specs in `specs/`, `specs/pending/`,
`specs/completed/`. Output is a *proposal*: classifications, minted IDs, grouping,
and an audit trail. Dry-run is the default and `--apply` only ever writes locally.

Three rules the classifier exists to keep:

* One external task per *deliverable*, never one per historical checkbox. A closed
  plan block with 9 ticked rows is history, not backlog.
* Operational verification work is first-class (`operational`), not noise to drop.
* Nothing unresolved is deleted. `stale` and `superseded` are labels a human then
  acts on; this tool only ever adds them to a report.
"""

from __future__ import annotations

import datetime
import os
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .index import TaskIndex, load_index, write_text
from .model import TERMINAL_STATUSES, slugify_id
from .reconcile import _scan_specs

AUDIT_PATH = "tasks/task-registry-migration.md"
PLAN_HEADING_RE = re.compile(r"^##+\s+(?P<title>.+?)\s*$")
#: The heading that marks a plan block as finished. "Session Summary" is this
#: harness's convention, not a universal one, so a project that closes its plans
#: differently sets `closed_plan_marker` instead of going unclassified.
DEFAULT_CLOSED_PLAN_MARKER = "Session Summary"
SPEC_REFERENCE_RE = re.compile(r"(?P<path>specs?/[A-Za-z0-9._/-]+\.md)")

#: Keyword classification is a heuristic and is reported as one. It never
#: overrides an explicit kind already present in a row's metadata.
KIND_KEYWORDS = (
    ("operational", ("verify", "verification", "deploy", "deployment", "e2e", "smoke",
                     "monitor", "runbook", "rollout", "incident", "health check")),
    ("bug", ("bug", "fix ", "fixes", "regression", "broken", "crash", "hotfix")),
    ("decision", ("decide", "decision", "adr", "choose", "trade-off", "tradeoff")),
    ("research", ("research", "spike", "investigate", "explore", "prototype", "evaluate")),
    ("epic", ("epic", "milestone", "phase")),
)


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
            "task-registry migrate — " + ("APPLIED" if self.applied else "DRY RUN (nothing written)"),
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
                "recommendation for the human running `publish`, not something this "
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


def plan_migration(config) -> MigrationPlan:
    index = load_index(config.path(config.index_path), config.index_path)
    plan = MigrationPlan(root=config.root, index_path=config.index_path)
    plan.problems += [problem.render() for problem in index.problems]

    marker = _closed_marker_re(config)
    groups = _group_lines(index, marker)
    block_starts = _block_starts(index)
    closed_groups = _closed_groups(index, marker)
    if not closed_groups and index.rows:
        plan.notes.append(
            f"no '{_marker_text(config)}' heading found, so no plan block could be read as "
            "closed — every open row is classified active; set `closed_plan_marker` in the "
            "task-tracking configuration if this project closes plans differently"
        )
    superseded_specs = {
        spec.path for spec in _scan_specs(config) if spec.state == "superseded"
    }
    # Seeded with the ids already in the index: minting `recipe.morph` a second
    # time would hand two different rows the same identity, which is the one
    # thing an identity must never do.
    minted: Dict[str, int] = {row.task.id: 1 for row in index.rows if row.task.id}

    for row in index.rows:
        group = groups.get(row.line, "ungrouped")
        spec_path = _spec_for(index, row.line, block_starts.get(row.line, 1))
        classification = _classify(row.task.status, group in closed_groups, spec_path, superseded_specs)
        kind = _kind_for(row.task.title, group)
        task_id = row.task.id or _mint(group, row.task.title, minted)
        plan.entries.append(
            MigrationEntry(
                line=row.line,
                title=row.task.title,
                status=row.task.status,
                classification=classification,
                kind=kind,
                task_id=task_id,
                group=group,
                spec_path=spec_path,
                existing_id=bool(row.task.id),
            )
        )

    _resolve_dependencies(index, plan)
    _add_backlog_notes(config, plan)
    plan.notes.append(
        "kind is inferred from row wording and the plan heading — review before publishing"
    )
    plan.notes.append(
        "completed rows are recorded as history and are never published as external tasks"
    )
    return plan


def apply_migration(config, plan: MigrationPlan) -> List[str]:
    """Write stable IDs into the index and leave an audit trail. Local writes only."""
    index = load_index(config.path(config.index_path), config.index_path)
    actions: List[str] = []
    written = 0
    for entry in plan.entries:
        # Everything still unresolved gets an identity — active, stale, and
        # superseded alike. Identity is not publication: `publish` is a separate,
        # human-run, gated step, whereas a row left without an id is a row no
        # command can name, and `reconcile` would report it as missing forever.
        if entry.existing_id or entry.classification == "completed":
            continue
        row = next((candidate for candidate in index.rows if candidate.line == entry.line), None)
        if row is None:  # pragma: no cover - index re-read is identical
            continue
        index.replace_row(row.line, _insert_id(row.raw, entry.task_id))
        written += 1
    rewritten = _rewrite_dependencies(index, plan)
    if written or rewritten:
        index.save()
    actions.append(f"minted {written} stable task id(s) in {config.index_path}")
    if rewritten:
        actions.append(f"rewrote {rewritten} dependency reference(s) to minted ids")
    if plan.unresolved_dependencies:
        actions.append(
            f"{len(plan.unresolved_dependencies)} dependency reference(s) could not be "
            "resolved and were left as written — see the audit trail"
        )
    audit = _render_audit(plan)
    write_text(config.path(AUDIT_PATH), audit)
    actions.append(f"audit trail written to {AUDIT_PATH}")
    plan.applied = True
    return actions


# --------------------------------------------------------------------- helpers


def _insert_id(raw: str, task_id: str) -> str:
    """Add the identity comment after the title, leaving the rest of the row alone.

    Deliberately surgical: migration is not an excuse to reformat a human's index.
    """
    if "<!-- task-id:" in raw:
        return raw
    marker = f" <!-- task-id: {task_id} -->"
    for separator in (" — ", " – ", " -> "):
        if separator in raw:
            head, tail = raw.split(separator, 1)
            return f"{head}{marker}{separator}{tail}"
    return raw.rstrip() + marker


def _marker_text(config) -> str:
    return getattr(config, "closed_plan_marker", "") or DEFAULT_CLOSED_PLAN_MARKER


def _closed_marker_re(config) -> "re.Pattern[str]":
    return re.compile(r"^##+\s+" + re.escape(_marker_text(config)), re.IGNORECASE)


def _heading_slug(title: str) -> str:
    return slugify_id(
        re.sub(r"^(plan|task \d+)\s*[:—-]?\s*", "", title, flags=re.IGNORECASE)
    )


def _rewrite_dependencies(index: TaskIndex, plan: MigrationPlan) -> int:
    """Replace resolved `blocked-by:` wording with the minted id, in place."""
    if not plan.dependency_rewrites:
        return 0
    rewritten = 0
    for row in index.rows:
        raw = index.row_text(row.line)
        updated = raw
        for old, new in plan.dependency_rewrites.items():
            updated = re.sub(
                r"(?<=[:,\s])" + re.escape(old) + r"(?=\s*[,)\]])", new, updated
            )
        if updated != raw:
            index.replace_row(row.line, updated)
            rewritten += 1
    return rewritten


def _group_lines(index: TaskIndex, marker: "re.Pattern[str]") -> Dict[int, str]:
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


def _block_starts(index: TaskIndex) -> Dict[int, int]:
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


def _closed_groups(index: TaskIndex, marker: "re.Pattern[str]") -> set:
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


def _spec_for(index: TaskIndex, line: int, block_start: int) -> Optional[str]:
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


def _resolve_dependencies(index: TaskIndex, plan: MigrationPlan) -> None:
    """Point every `blocked-by:` at a minted id, and name the ones that cannot be.

    Before migration a dependency can only name a row by its wording, because no
    row has an id yet. Minting ids without rewriting those references leaves the
    index full of dependencies that resolve to nothing — and `frontier` would then
    read an unresolvable blocker as no blocker at all.
    """
    by_slug: Dict[str, str] = {}
    for entry in plan.entries:
        by_slug.setdefault(slugify_id(entry.title), entry.task_id)
    known = {entry.task_id for entry in plan.entries}
    for row in index.rows:
        for dependency in row.task.depends_on:
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


def _add_backlog_notes(config, plan: MigrationPlan) -> None:
    backlog = config.path(config.backlog_path)
    if not os.path.isfile(backlog):
        return
    backlog_index = load_index(backlog, config.backlog_path)
    open_items = [row for row in backlog_index.rows if row.task.status not in TERMINAL_STATUSES]
    plan.notes.append(
        f"{config.backlog_path}: {len(open_items)} open item(s) left in place — the backlog "
        "stays the ordered queue; publish from it deliberately, not automatically"
    )


def _render_audit(plan: MigrationPlan) -> str:
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "# Task Registry Migration Audit",
        "",
        f"> Generated {stamp} by `/task-registry migrate --apply`.",
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
