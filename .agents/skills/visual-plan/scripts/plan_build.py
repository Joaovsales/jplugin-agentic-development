"""The Build Order section: the slice DAG, one card per slice, the build prompt."""

from typing import Set

from plan_cards import classes, chip, head
from plan_figures import dag_figure
from plan_md import esc, inline, plain, render_blocks
from plan_model import Plan, anchor, not_ready_ids
from plan_sections import Slice

# Build Order column -> the label it carries in a slice card body
SLICE_FIELDS = (("delivers", "Delivers"), ("surface", "Surface"), ("verify", "Verify"), ("size", "Size"))


def blocked_slices(plan: Plan) -> Set[int]:
    """Slices an open question's `Blocks` names."""
    return {n for q in plan.questions for n in q.blocks}


def _links(numbers) -> str:
    return ", ".join('<a href="#slice-%d">slice %d</a>' % (n, n) for n in numbers) or "none"


def _ac_links(acs) -> str:
    return ", ".join('<a href="#%s">%s</a>' % (anchor(a), a) for a in acs) or "none"


def slice_card(s: Slice, is_blocked: bool) -> str:
    rows = ["<dt>%s</dt><dd>%s</dd>" % (lbl, inline(s.cells[col])) for col, lbl in SLICE_FIELDS
            if plain(s.cells.get(col, ""))]
    rows.insert(1, "<dt>Blocked by</dt><dd>%s</dd>" % _links(s.blocked_by))
    rows.insert(2, "<dt>Criteria</dt><dd>%s</dd>" % _ac_links(s.acs))
    chips = chip("blocked", "blocked by a question") if is_blocked else ""
    goal = plain(s.cells.get("delivers", ""))
    return '<article class="%s" id="slice-%d">%s<p>%s</p><details class="card-more"><summary>Slice details</summary><dl>%s</dl></details></article>' % (
        classes("card card-slice", "is-blocked is-blocker" if is_blocked else ""), s.number,
        head("slice", "S%d" % s.number, chips, inline(s.name)), inline(goal), "".join(rows))


def _not_ready_body(plan: Plan, ids) -> str:
    """Blockers named and linked; the superseded prompt kept out of sight, copy disabled."""
    links = ", ".join('<a href="#%s">%s</a>' % (anchor(i), esc(i)) for i in ids)
    stale = ""
    if plan.build.prompt is not None:
        stale = ('<details class="prompt-stale"><summary>Prompt text (not executable until these clear)</summary>'
                 '<pre><code id="build-prompt-text">%s</code></pre></details>'
                 '<button type="button" class="copy" data-copy-from="build-prompt-text" disabled>Copy build prompt</button>'
                 % esc(plan.build.prompt))
    return ('<p class="not-ready-msg">Not ready: %s</p><p class="meta">Settle these decisions and questions, '
            'then re-run <code>/slice</code> for a prompt that is safe to build from.</p>%s' % (links, stale))


def prompt_panel(plan: Plan) -> str:
    """The canonical build prompt, verbatim, with a copy button over its exact text."""
    ids = not_ready_ids(plan)
    if ids:
        body = _not_ready_body(plan, ids)
    elif plan.build.prompt is None:
        body = '<p class="meta">§ Build Order carries no build prompt yet: re-run <code>/slice</code>.</p>'
    else:
        body = ('<pre><code id="build-prompt-text">%s</code></pre>'
                '<button type="button" class="copy" data-copy-from="build-prompt-text">Copy build prompt</button>'
                % esc(plan.build.prompt))
    return '<section class="%s" id="build-prompt" aria-label="Build prompt">%s%s</section>' % (
        classes("card card-prompt", "not-ready is-blocker" if ids else ""), head("prompt"), body)


def render_build_order(plan: Plan, hook) -> str:
    blocked = blocked_slices(plan)
    intro = [b for b in plan.build.intro if not plain(b.text).lower().startswith("build prompt")]
    cards = "".join(slice_card(s, s.number in blocked) for s in plan.build.slices)
    return "%s%s<div class=\"cards slice-cards\">%s</div>%s" % (
        render_blocks(intro, hook), dag_figure(plan, blocked), cards, prompt_panel(plan))

