"""Diagram figures: an SVG, its caption, and its DSL source in a disclosure."""

from typing import Callable, Optional, Set

import plan_svg
from plan_cards import icon, label
from plan_diagrams import Flow
from plan_md import Block, esc
from plan_model import Plan

DEFAULT_CAPTION = {"flow": "Flow diagram", "sequence": "Sequence diagram"}


def figure(kind: str, fig_id: str, svg: str, caption: str, source: str = "") -> str:
    src = ('<details class="diagram-source"><summary>Diagram source</summary><pre><code>%s</code></pre></details>'
           % esc(source)) if source else ""
    return (
        '<figure class="diagram card-diagram %s" id="%s"><div class="card-head">%s%s<span class="chip">%s</span></div>'
        '<div class="diagram-scroll" tabindex="0" role="region" aria-label="%s">%s</div>'
        "<figcaption>%s</figcaption>%s</figure>"
        % (kind, fig_id, icon("diagram"), label("diagram"), kind, esc(caption), svg, esc(caption), src)
    )


def dsl_figure(block: Block, diagram) -> str:
    kind = "flow" if isinstance(diagram, Flow) else "sequence"
    caption = diagram.caption or DEFAULT_CAPTION[kind]
    prefix = "dg%d" % block.line
    if kind == "flow":
        svg = plan_svg.flow_svg(prefix, diagram, caption)
    else:
        svg = plan_svg.sequence_svg(prefix, diagram, caption)
    return figure(kind, "diagram-%d" % block.line, svg, caption, block.text)


def dag_figure(plan: Plan, blocked: Set[int]) -> str:
    svg = plan_svg.dag_svg("dag", plan.build.slices, blocked)
    caption = "Slices in dependency order: a slice starts when every slice it is blocked by is done."
    return figure("dag", "slice-graph", svg, caption)


def diagram_hook(plan: Plan) -> Callable[[Block], Optional[str]]:
    """A render_blocks hook that turns parsed flow / sequence fences into figures."""
    def hook(block: Block) -> Optional[str]:
        if block.kind == "code" and block.line in plan.diagrams:
            return dsl_figure(block, plan.diagrams[block.line])
        return None
    return hook
