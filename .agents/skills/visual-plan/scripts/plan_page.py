"""Assemble a parsed `Plan` into one self-contained HTML page."""

import os
import re
from pathlib import Path
from typing import Callable, Dict, List, Tuple

import plan_cards as cards
import plan_reference as reference
from plan_build import render_build_order
from plan_figures import diagram_hook
from plan_md import Section, esc, inline, plain, render_blocks
from plan_model import Plan, section_key

HERE = Path(__file__).resolve().parent
THEME_CSS = HERE.parents[3] / "design" / "plan-theme" / "plan.css"
PAGE_JS = HERE / "plan_page.js"

# ids the page itself owns; a section slug never takes one of them
RESERVED = ("main", "summary-lead", "blockers", "blockers-h", "build-prompt", "review")

# reference content starts collapsed; approval content (everything else) starts open
COLLAPSED = ("constraints", "component contracts", "data models", "references")
LEAD_ONLY = ("summary",)


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
<header class="masthead">{masthead}</header>
<div class="shell">{toc}<main id="main">
{main}
</main>
</div>
<script>{script}</script>
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


def section_wrap(sid: str, title: str, inner: str, kind: str, open_: bool) -> str:
    marks = " has-blockers" if "is-blocker" in inner else ""
    return (
        '<section class="sec sec-%s%s" id="%s" data-kind="%s">'
        '<details class="sec-body"%s><summary><h2>%s</h2></summary>%s</details></section>'
        % (kind, marks, esc(sid), kind, " open" if open_ else "", inline(title), inner)
    )


TYPED: Dict[str, Callable[[Plan, Section, Callable], str]] = {
    "decisions": lambda plan, section, hook: cards.render_decisions(plan),
    "acceptance criteria": lambda plan, section, hook: cards.render_criteria(plan),
    "build order": lambda plan, section, hook: render_build_order(plan, hook),
    "risks": lambda plan, section, hook: cards.render_risks(plan),
    "open questions": lambda plan, section, hook: cards.render_questions(plan),
    "constraints": lambda plan, section, hook: reference.render_constraints(section, hook),
    "component contracts": lambda plan, section, hook: reference.render_contracts(section, hook),
    "data models": lambda plan, section, hook: reference.render_models(section, hook),
    "references": lambda plan, section, hook: reference.render_references(section, hook),
}


def render_section(plan: Plan, section: Section, sid: str, hook: Callable) -> str:
    key = section_key(section.title)
    renderer = TYPED.get(key)
    inner = renderer(plan, section, hook) if renderer else render_blocks(section.blocks, hook)
    kind = re.sub(r"[^a-z]+", "-", key) if renderer else "generic"
    return section_wrap(sid, section.title, inner, kind, key not in COLLAPSED)


def body_sections(plan: Plan) -> List[Tuple[Section, str]]:
    """(section, element id) in source order, without the sections the lead absorbs."""
    slugs = Slugs()
    pairs = [(s, slugs(s.title)) for s in plan.doc.sections]
    return [(s, sid) for s, sid in pairs if section_key(s.title) not in LEAD_ONLY]


def render_controls() -> str:
    return (
        '<div class="controls" role="toolbar" aria-label="Disclosure">'
        '<button type="button" class="btn" data-action="expand">Expand all</button>'
        '<button type="button" class="btn" data-action="collapse">Collapse all</button>'
        '<button type="button" class="btn" data-action="blockers" aria-pressed="false">Show only blockers</button>'
        "</div>"
    )


def render_toc(plan: Plan, sections: List[Tuple[Section, str]]) -> str:
    entries = []
    if plan.summary:
        entries.append(("summary-lead", "Summary"))
    entries.append(("blockers", "Blockers"))
    entries += [(sid, s.title) for s, sid in sections]
    if plan.build:
        entries.append(("build-prompt", "Build prompt"))
    items = "".join('<li><a href="#%s">%s</a></li>' % (esc(sid), inline(title)) for sid, title in entries)
    return ('<nav class="toc" aria-label="Contents"><details class="toc-menu" open><summary>Contents</summary>'
            "<ol>%s</ol></details></nav>" % items)


def source_href(plan: Plan) -> str:
    """The spec, relative to the directory the page is written into."""
    out_dir = os.path.dirname(os.path.abspath(plan.out_path))
    return os.path.relpath(os.path.abspath(plan.spec_path), out_dir).replace(os.sep, "/")


def render_masthead(plan: Plan) -> str:
    shown = plan.spec_path.replace(os.sep, "/")
    prompt = '<a href="#build-prompt">Build prompt ↓</a>' if plan.build else "Not sliced yet"
    return (
        '<p class="folio"><span>Visual plan</span><span>%s</span></p><h1>%s</h1>'
        '<p class="source">Source: <a href="%s">%s</a> · sha256 <code>%s</code></p>'
        % (prompt, inline(plan.doc.title), esc(source_href(plan)), esc(shown), plan.short_sha)
    )


def render_main(plan: Plan, sections: List[Tuple[Section, str]]) -> str:
    hook = diagram_hook(plan)
    by_key = {section_key(s.title): sid for s, sid in sections}
    parts: List[str] = [
        render_blocks(plan.doc.preamble, hook),
        cards.render_lead(plan.summary, render_blocks(plan.summary, hook)),
        cards.render_strip(plan, by_key), cards.render_blockers(plan), render_controls(),
    ]
    parts += [render_section(plan, s, sid, hook) for s, sid in sections]
    return "\n".join(p for p in parts if p)


def render_page(plan: Plan) -> str:
    sections = body_sections(plan)
    return PAGE.format(
        title=esc(plain(plan.doc.title)), masthead=render_masthead(plan),
        css=theme_css(), toc=render_toc(plan, sections), main=render_main(plan, sections),
        script=PAGE_JS.read_text(encoding="utf-8"),
    )
