"""Typed cards for a visual plan: one colour, icon, label and border per type.

The class names are the plan theme's component vocabulary (design/plan-theme);
the theme CSS styles them. Every card carries a text label and an aria-hidden icon, so
no type is told apart by colour alone.
"""

import re
from typing import Dict, List, Optional

from plan_md import TEXT_DIAGRAM, Block, esc, inline, plain, render_blocks
from plan_model import Plan, anchor, blockers, coverage, is_blocking_risk
from plan_review import review_controls

# component type -> (icon glyph, text label); the registry AC3 checks.
COMPONENTS: Dict[str, tuple] = {
    "lead": ("¶", "Summary"),
    "strip": ("#", "At a glance"),
    "blockers": ("!", "Blockers"),
    "question": ("?", "Question"),
    "decision": ("◆", "Decision"),
    "criterion": ("✓", "Criterion"),
    "risk": ("▲", "Risk"),
    "constraint": ("⊟", "Constraint"),
    "contract": ("{ }", "Contract"),
    "model": ("⊞", "Data model"),
    "slice": ("▤", "Slice"),
    "diagram": ("◇", "Diagram"),
    "text-diagram": TEXT_DIAGRAM,
    "prompt": ("▶", "Build prompt"),
    "reference": ("↗", "Reference"),
}


def icon(kind: str) -> str:
    return '<span class="card-icon" aria-hidden="true">%s</span>' % esc(COMPONENTS[kind][0])


def label(kind: str) -> str:
    return '<span class="card-label">%s</span>' % esc(COMPONENTS[kind][1])


def head(kind: str, item_id: str = "", chips: str = "", title_html: str = "") -> str:
    parts = [icon(kind), label(kind)]
    if item_id:
        parts.append('<span class="card-id">%s</span>' % esc(item_id))
    parts.append(chips)
    if title_html:
        parts.append("<h3>%s</h3>" % title_html)
    return '<div class="card-head">%s</div>' % "".join(parts)


def chip(state: str, text: str = "") -> str:
    return '<span class="chip chip-%s">%s</span>' % (state, esc(text or state))


def classes(*names: str) -> str:
    return " ".join(n for n in names if n)


# ------------------------------------------------------------- decisions ---

def _decision_body(d) -> str:
    rows = [("Options", d.options), ("Why", d.rationale), ("Source", d.source)]
    dl = "".join("<dt>%s</dt><dd>%s</dd>" % (k, inline(v)) for k, v in rows if plain(v))
    wrong = '<p class="callout-wrong"><strong>Wrong when:</strong> %s</p>' % inline(d.wrong_when) if plain(d.wrong_when) else ""
    if not dl and not wrong:
        return ""
    summary = "Options, rationale and reversal" if wrong else "Options and rationale"
    return '<details class="card-more"><summary>%s</summary>%s%s</details>' % (
        summary, "<dl>%s</dl>" % dl if dl else "", wrong)


def _chosen(d) -> str:
    word = d.chosen_label or "Decision"
    text = plain(d.chosen)
    if d.status == "open" and (not text or text.lower() == "open"):
        return '<p class="chosen is-undecided">Not decided yet</p>'
    if not text:
        return ""
    return '<p class="chosen"><span class="visually-hidden">%s: </span>%s</p>' % (word, inline(d.chosen))


def decision_card(d) -> str:
    is_open = d.status == "open"
    return '<article class="%s" id="%s">%s%s%s%s</article>' % (
        classes("card card-decision", "is-open is-blocker" if is_open else ""), anchor(d.id),
        head("decision", d.id, chip(d.status, d.status_text), inline(d.title)), _chosen(d), _decision_body(d),
        review_controls(d.id, pick_from=d.options if is_open else None))


def render_decisions(plan: Plan) -> str:
    return '<div class="cards">%s</div>' % "".join(decision_card(d) for d in plan.decisions)


# -------------------------------------------------------------- criteria ---

def _covered_by(slices: List[int]) -> str:
    links = ", ".join('<a href="#slice-%d">slice %d</a>' % (n, n) for n in slices)
    return '<p class="meta">covered by %s</p>' % links


def criterion_card(c, slices: Optional[List[int]]) -> str:
    uncovered = slices is not None and not slices
    chips = chip("uncovered") if uncovered else ""
    meta = _covered_by(slices) if slices else ""
    return '<li class="%s" id="%s">%s<p>%s</p>%s%s</li>' % (
        classes("card card-criterion", "is-uncovered is-blocker" if uncovered else ""), anchor(c.id),
        head("criterion", c.id, chips), inline(c.text), meta, review_controls(c.id))


def render_criteria(plan: Plan) -> str:
    covered = coverage(plan)
    note = "" if covered is not None else (
        '<p class="meta">This spec has not been sliced: no Build Order names its criteria yet.</p>')
    items = "".join(criterion_card(c, covered[c.id] if covered else None) for c in plan.criteria)
    return '%s<ol class="ac-list cards">%s</ol>' % (note, items)


# ----------------------------------------------------------------- risks ---

RANK = {"H": 0, "M": 1, "L": 2}


def _slice_links(cell: str) -> str:
    """`1, 2` -> slice links; anything else stays as written."""
    nums = re.findall(r"\d+", plain(cell))
    if not nums or re.sub(r"[\d,\s]", "", plain(cell)):
        return inline(cell)
    return ", ".join('<a href="#slice-%s">slice %s</a>' % (n, n) for n in nums)


def risk_card(r) -> str:
    blocking = is_blocking_risk(r)
    levels = '<span class="lvl lvl-%s">Likelihood %s</span><span class="lvl lvl-%s">Impact %s</span>' % (
        r.likelihood, r.likelihood, r.impact, r.impact)
    mitigation = inline(r.mitigation) if plain(r.mitigation) else "<em>No mitigation yet</em>"
    rows = "<dt>Mitigation</dt><dd>%s</dd>" % mitigation
    if plain(r.slice):
        rows += "<dt>Slice</dt><dd>%s</dd>" % _slice_links(r.slice)
    return '<article class="%s" id="%s">%s<dl class="risk-body">%s</dl>%s</article>' % (
        classes("card card-risk", "is-blocker" if blocking else ""), anchor(r.id),
        head("risk", r.id, levels, inline(r.text)), rows, review_controls(r.id))


def render_risks(plan: Plan) -> str:
    if plan.risks is None or plan.risks.none_why is not None:
        why = plan.risks.none_why if plan.risks else ""
        return '<p class="risks-none">None identified — %s</p>' % inline(why)
    ordered = sorted(plan.risks.items, key=lambda r: (RANK[r.impact], RANK[r.likelihood]))
    return '<div class="cards">%s</div>' % "".join(risk_card(r) for r in ordered)


# -------------------------------------------------------- open questions ---

def question_card(q) -> str:
    blocks = ("Blocks %s" % ", ".join('<a href="#slice-%d">slice %d</a>' % (n, n) for n in q.blocks)
              if q.blocks else "Blocks nothing")
    tags = '<p class="meta"><span class="tag">%s</span>%s</p>' % (
        blocks, '<span class="tag">Needed from %s</span>' % inline(q.needed_from) if plain(q.needed_from) else "")
    return '<article class="%s" id="%s">%s%s%s</article>' % (
        classes("card card-question", "is-blocker" if q.blocks else ""), anchor(q.id),
        head("question", q.id, chip("open", "blocking") if q.blocks else "", inline(q.text)), tags,
        review_controls(q.id, answer=True))


def render_questions(plan: Plan) -> str:
    return '<div class="cards">%s</div>' % "".join(question_card(q) for q in plan.questions)


# --------------------------------------------- lead, strip and blockers ---

def render_lead(blocks: List[Block], body_html: str = "") -> str:
    if not blocks:
        return ""
    return '<section class="lead card-lead" id="summary-lead" aria-label="Summary"><span class="lead-label">%s %s</span>%s</section>' % (
        icon("lead"), label("lead"), body_html or render_blocks(blocks))


def _stat(href: str, n: int, text: str, alert: bool = False) -> str:
    return '<a class="%s" href="#%s"><span class="stat-n">%d</span><span class="stat-l">%s</span></a>' % (
        "stat stat-alert" if alert else "stat", href, n, text)


def render_strip(plan: Plan, slugs: Dict[str, str]) -> str:
    open_items = sum(d.status == "open" for d in plan.decisions) + len(plan.questions)
    stats = [
        ("build order", len(plan.build.slices) if plan.build else 0, "slices"),
        ("acceptance criteria", len(plan.criteria), "criteria"),
        ("decisions", len(plan.decisions), "decisions"),
        ("risks", len(plan.risks.items) if plan.risks else 0, "risks"),
        ("open questions" if "open questions" in slugs else "decisions", open_items, "open items"),
    ]
    links = [_stat(slugs[key], n, text) for key, n, text in stats if key in slugs]
    links.append(_stat("blockers", len(blockers(plan)), "blockers", alert=bool(blockers(plan))))
    return '<nav class="strip card-strip" aria-label="At a glance"><span class="strip-label">%s%s</span>%s</nav>' % (
        icon("strip"), label("strip"), "".join(links))


def render_blockers(plan: Plan) -> str:
    items = blockers(plan)
    if items:
        body = "<ul>%s</ul>" % "".join(
            '<li><a href="#%s"><strong>%s</strong> — %s: %s</a></li>'
            % (anchor(b.id), esc(b.id), esc(b.kind), inline(b.title)) for b in items)
    else:
        body = '<p class="none">No blockers: no open decision, blocking question, uncovered criterion or unmitigated high-impact risk.</p>'
    return '<section class="blockers card-blockers" id="blockers" aria-labelledby="blockers-h"><h2 id="blockers-h">%s%s <span class="sec-count">%d</span></h2>%s</section>' % (
        icon("blockers"), label("blockers"), len(items), body)
