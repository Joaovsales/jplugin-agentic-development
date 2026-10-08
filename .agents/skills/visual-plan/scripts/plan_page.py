"""Assemble a parsed `Plan` into one self-contained HTML page."""

import re
from pathlib import Path
from typing import Callable, Dict, List

from plan_md import Section, esc, inline, plain, render_blocks
from plan_model import Plan, section_key

THEME_CSS = Path(__file__).resolve().parents[4] / "design" / "plan-theme" / "plan.css"


def theme_css() -> str:
    """The jplugin plan theme, inlined into every page; a missing theme is an error."""
    if not THEME_CSS.is_file():
        raise FileNotFoundError("plan theme not found at %s" % THEME_CSS)
    return THEME_CSS.read_text(encoding="utf-8")


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{css}</style>
</head>
<body>
<header class="masthead"><h1>{title_html}</h1></header>
<main id="main">
{main}
</main>
</body>
</html>
"""


class Slugs:
    """Unique, stable element ids derived from titles."""

    def __init__(self):
        self.used = set()

    def __call__(self, text: str) -> str:
        base = re.sub(r"[^a-z0-9]+", "-", plain(text).lower()).strip("-") or "section"
        slug, n = base, 2
        while slug in self.used:
            slug, n = "%s-%d" % (base, n), n + 1
        self.used.add(slug)
        return slug


def section_wrap(sid: str, title: str, inner: str, kind: str = "generic", open_: bool = True) -> str:
    return (
        '<section class="sec sec-%s" id="%s" data-kind="%s">'
        '<details class="sec-body"%s><summary><h2>%s</h2></summary>%s</details></section>'
        % (kind, esc(sid), kind, " open" if open_ else "", inline(title), inner)
    )


def render_lead(plan: Plan) -> str:
    if not plan.summary:
        return ""
    return '<section class="lead" id="summary-lead" aria-label="Summary">%s</section>' % render_blocks(plan.summary)


def render_decisions(plan: Plan, section: Section) -> str:
    cards = []
    for d in plan.decisions:
        cards.append(
            '<article class="card card-decision" id="%s"><header><span class="card-id">%s</span> '
            '<span class="chip chip-%s">%s</span> <h3>%s</h3></header><p class="chosen">%s</p></article>'
            % (esc(d.id.lower()), esc(d.id), d.status, d.status, inline(d.title), inline(d.chosen))
        )
    return "".join(cards)


def render_criteria(plan: Plan, section: Section) -> str:
    rows = "".join(
        '<li class="ac" id="%s"><span class="card-id">%s</span> %s</li>'
        % (esc(c.id.lower()), esc(c.id), inline(c.text))
        for c in plan.criteria
    )
    return '<ol class="ac-list">%s</ol>' % rows


TYPED: Dict[str, Callable[[Plan, Section], str]] = {
    "decisions": render_decisions,
    "acceptance criteria": render_criteria,
}


def render_section(plan: Plan, section: Section, slugs: Slugs) -> str:
    key = section_key(section.title)
    renderer = TYPED.get(key)
    inner = renderer(plan, section) if renderer else render_blocks(section.blocks)
    kind = re.sub(r"[^a-z]+", "-", key) if renderer else "generic"
    return section_wrap(slugs(section.title), section.title, inner, kind)


def render_page(plan: Plan) -> str:
    slugs = Slugs()
    parts: List[str] = [render_blocks(plan.doc.preamble), render_lead(plan)]
    parts += [render_section(plan, s, slugs) for s in plan.doc.sections]
    title = plain(plan.doc.title)
    return PAGE.format(title=esc(title), title_html=inline(plan.doc.title), css=theme_css(), main="\n".join(parts))
