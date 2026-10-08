"""Assemble a parsed `Plan` into one self-contained HTML page."""

import re
from pathlib import Path
from typing import Callable, Dict, List

import plan_cards as cards
from plan_build import render_build_order
from plan_figures import diagram_hook
from plan_md import Section, esc, inline, plain, render_blocks
from plan_model import Plan, section_key

THEME_CSS = Path(__file__).resolve().parents[4] / "design" / "plan-theme" / "plan.css"

# ids the page itself owns; a section slug never takes one of them
RESERVED = ("main", "summary-lead", "blockers", "blockers-h", "build-prompt", "review")


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
<meta name="color-scheme" content="light dark">
<title>{title}</title>
<style>{css}</style>
</head>
<body class="plan">
<a class="skip" href="#main">Skip to content</a>
<header class="masthead"><h1>{title_html}</h1></header>
<div class="shell">
<main id="main">
{main}
</main>
</div>
</body>
</html>
"""


class Slugs:
    """Unique, stable element ids derived from titles."""

    def __init__(self, reserved=RESERVED):
        self.used = set(reserved)

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


TYPED: Dict[str, Callable[[Plan, Section, Callable], str]] = {
    "decisions": lambda plan, section, hook: cards.render_decisions(plan),
    "acceptance criteria": lambda plan, section, hook: cards.render_criteria(plan),
    "build order": lambda plan, section, hook: render_build_order(plan, hook),
}
LEAD_ONLY = ("summary",)


def render_section(plan: Plan, section: Section, sid: str, hook: Callable) -> str:
    key = section_key(section.title)
    renderer = TYPED.get(key)
    inner = renderer(plan, section, hook) if renderer else render_blocks(section.blocks, hook)
    kind = re.sub(r"[^a-z]+", "-", key) if renderer else "generic"
    return section_wrap(sid, section.title, inner, kind)


def section_slugs(plan: Plan) -> Dict[int, str]:
    """Section start line -> element id, assigned once in source order."""
    slugs = Slugs()
    return {s.line: slugs(s.title) for s in plan.doc.sections}


def render_main(plan: Plan) -> str:
    ids = section_slugs(plan)
    hook = diagram_hook(plan)
    by_key = {section_key(s.title): ids[s.line] for s in plan.doc.sections}
    parts: List[str] = [
        render_blocks(plan.doc.preamble, hook),
        cards.render_lead(plan.summary, render_blocks(plan.summary, hook)),
        cards.render_strip(plan, by_key), cards.render_blockers(plan),
    ]
    parts += [render_section(plan, s, ids[s.line], hook) for s in plan.doc.sections
              if section_key(s.title) not in LEAD_ONLY]
    return "\n".join(p for p in parts if p)


def render_page(plan: Plan) -> str:
    title = plain(plan.doc.title)
    return PAGE.format(title=esc(title), title_html=inline(plan.doc.title), css=theme_css(),
                       main=render_main(plan))
