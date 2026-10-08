"""The parsed visual plan: every known section read, validated and cross-checked.

`analyse` is the one place a spec's typed content is read. It raises
`SpecError` on the first malformed known section or diagram, so the page
renderer only ever sees a plan that parsed completely.
"""

import hashlib
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from plan_diagrams import parse_diagram
from plan_md import Block, Document, Section, parse_document, plain
from plan_sections import (
    BuildOrder, Criterion, Decision, Question, Risks,
    parse_build_order, parse_criteria, parse_decisions, parse_questions, parse_risks,
)


@dataclass
class Plan:
    doc: Document
    spec_path: str
    out_path: str
    sha256: str
    summary: List[Block] = field(default_factory=list)
    decisions: List[Decision] = field(default_factory=list)
    criteria: List[Criterion] = field(default_factory=list)
    build: Optional[BuildOrder] = None
    risks: Optional[Risks] = None
    questions: List[Question] = field(default_factory=list)
    diagrams: Dict[int, object] = field(default_factory=dict)  # fence line -> Flow | Sequence

    @property
    def short_sha(self) -> str:
        return self.sha256[:12]


@dataclass
class Blocker:
    kind: str  # open decision | blocking question | uncovered criterion | unmitigated high-impact risk
    id: str
    title: str


def anchor(item_id: str) -> str:
    """The element id of a card: `D2` -> `d2`, `AC1.1` -> `ac1-1`."""
    return re.sub(r"[^a-z0-9]+", "-", item_id.lower()).strip("-")


def coverage(plan: Plan) -> Optional[Dict[str, List[int]]]:
    """AC id -> the slices whose ACs column names it; None when the spec is unsliced."""
    if plan.build is None:
        return None
    out: Dict[str, List[int]] = {c.id: [] for c in plan.criteria}
    for s in plan.build.slices:
        for ac in s.acs:
            for c in plan.criteria:
                if c.id == ac or c.id.split(".")[0] == ac:
                    out[c.id].append(s.number)
    return out


def is_blocking_risk(risk) -> bool:
    return risk.impact == "H" and not plain(risk.mitigation)


def blockers(plan: Plan) -> List[Blocker]:
    """Open decisions, blocking questions, uncovered ACs, unmitigated high-impact risks."""
    out = [Blocker("open decision", d.id, d.title) for d in plan.decisions if d.status == "open"]
    out += [Blocker("blocking question", q.id, q.text) for q in plan.questions if q.blocks]
    covered = coverage(plan)
    if covered is not None:
        out += [Blocker("uncovered criterion", c.id, c.text) for c in plan.criteria if not covered[c.id]]
    risks = plan.risks.items if plan.risks else []
    out += [Blocker("unmitigated high-impact risk", r.id, r.text) for r in risks if is_blocking_risk(r)]
    return out


def not_ready_ids(plan: Plan) -> List[str]:
    """Open decisions, then questions that block a slice: while any exists the
    build prompt is not executable (`/slice readiness` and the page agree)."""
    return [d.id for d in plan.decisions if d.status == "open"] + [q.id for q in plan.questions if q.blocks]


def read_plan(spec_path: str, out_path: str = "") -> Plan:
    """Parse and analyse a spec file; raises SpecError on a malformed known section."""
    with open(spec_path, encoding="utf-8") as fh:
        text = fh.read()
    return analyse(parse_document(text), text, spec_path, out_path)


def section_key(title: str) -> str:
    """Normalised section title used to recognise known sections."""
    return re.sub(r"\s+", " ", plain(title).lower()).strip()


def find(doc: Document, *keys: str) -> Optional[Section]:
    for section in doc.sections:
        if section_key(section.title) in keys:
            return section
    return None


def spec_sha256(text: str) -> str:
    """SHA-256 of the spec text as read (line endings normalised to LF), so a CRLF
    checkout and an LF checkout of one spec share a hash."""
    return hashlib.sha256(text.replace("\r\n", "\n").encode("utf-8")).hexdigest()


def analyse(doc: Document, text: str, spec_path: str, out_path: str) -> Plan:
    plan = Plan(doc, spec_path, out_path, spec_sha256(text))
    _read_typed(plan)
    plan.summary = _summary(doc)
    _read_diagrams(plan)
    return plan


def _read_typed(plan: Plan) -> None:
    doc = plan.doc
    build = find(doc, "build order")
    plan.build = parse_build_order(build) if build and build.blocks else None  # empty: not sliced yet
    numbers = {s.number for s in plan.build.slices} if plan.build else None
    readers = (
        ("decisions", lambda s: setattr(plan, "decisions", parse_decisions(s))),
        ("acceptance criteria", lambda s: setattr(plan, "criteria", parse_criteria(s))),
        ("risks", lambda s: setattr(plan, "risks", parse_risks(s))),
        ("open questions", lambda s: setattr(plan, "questions", parse_questions(s, numbers))),
    )
    for key, read in readers:
        section = find(doc, key)
        if section:
            read(section)


def _summary(doc: Document) -> List[Block]:
    """`## Summary`, else the first paragraph of Problem or Behavior, else the preamble's."""
    section = find(doc, "summary")
    if section:
        return section.blocks
    for key in ("problem", "behavior", "behaviour", "overview"):
        section = find(doc, key)
        para = section and next((b for b in section.blocks if b.kind == "para"), None)
        if para:
            return [para]
    para = next((b for b in doc.preamble if b.kind == "para"), None)
    return [para] if para else []


def _code_blocks(blocks: List[Block]):
    for block in blocks:
        if block.kind == "code":
            yield block


def _read_diagrams(plan: Plan) -> None:
    for section in [None] + plan.doc.sections:
        blocks = plan.doc.preamble if section is None else section.blocks
        for block in _code_blocks(blocks):
            diagram = parse_diagram(block.lang, block.text, block.line)
            if diagram is not None:
                plan.diagrams[block.line] = diagram
