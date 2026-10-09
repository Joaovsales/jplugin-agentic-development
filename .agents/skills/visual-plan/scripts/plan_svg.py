"""Deterministic inline SVG for the slice DAG and the flow / sequence DSLs.

No layout engine and no library: nodes sit in dependency layers (longest path
from a source), left to right, and every label is HTML-escaped. Styling comes
from the plan theme's `svg .node`, `.edge`, `.msg`, `.frame` ... rules, so the
diagrams follow light, dark and print themes.
"""

from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

from plan_diagrams import Flow, Sequence as SeqDiagram
from plan_md import esc
from plan_model import slice_anchor

PAD = 20
GAP_X = 64
GAP_Y = 22
FONT_W = 7.4  # px per character at 13 px, a conservative sans average


def clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def text_w(text: str, scale: float = 1.0) -> float:
    return len(text) * FONT_W * scale


def layers(nodes: Sequence, edges: Iterable[Tuple]) -> Dict:
    """Longest path from a source; an edge closing a cycle is ignored."""
    preds: Dict = {n: [] for n in nodes}
    for a, b in edges:
        if a != b:
            preds[b].append(a)
    memo: Dict = {}
    onstack: Set = set()

    def depth(n) -> int:
        if n in memo:
            return memo[n]
        onstack.add(n)
        d = max([depth(p) + 1 for p in preds[n] if p not in onstack] or [0])
        onstack.discard(n)
        memo[n] = d
        return d

    return {n: depth(n) for n in nodes}


def grid(nodes: Sequence, layer: Dict, w: float, h: float, gap: float = GAP_X) -> Dict:
    """node -> (x, y) top-left, columns by layer, rows by first appearance."""
    rows: Dict[int, int] = {}
    pos = {}
    for n in nodes:
        col = layer[n]
        row = rows.get(col, 0)
        rows[col] = row + 1
        pos[n] = (PAD + col * (w + gap), PAD + 18 + row * (h + GAP_Y))
    return pos


def svg_open(prefix: str, width: float, height: float, title: str, desc: str, role: str = "img") -> str:
    return (
        '<svg viewBox="0 0 %d %d" width="%d" height="%d" role="%s" aria-labelledby="%s-t %s-d">'
        '<title id="%s-t">%s</title><desc id="%s-d">%s</desc>'
        '<defs><marker id="%s-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="arrow"/></marker></defs>'
        % (width, height, width, height, role, prefix, prefix, prefix, esc(title), prefix, esc(desc), prefix)
    )


def curve(x1: float, y1: float, x2: float, y2: float) -> str:
    if x2 > x1:
        bend = max(24.0, (x2 - x1) / 2)
        return "M%.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f" % (x1, y1, x1 + bend, y1, x2 - bend, y2, x2, y2)
    drop = max(y1, y2) + 46
    return "M%.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f" % (x1, y1, x1, drop, x2, drop, x2, y2)


def edge_label(x: float, y: float, text: str) -> str:
    if not text:
        return ""
    shown = clip(text, 34)
    w = text_w(shown, 0.86) + 10
    return '<rect class="label-bg" x="%.1f" y="%.1f" width="%.1f" height="16" rx="3"/><text class="edge-label" x="%.1f" y="%.1f" text-anchor="middle">%s</text>' % (
        x - w / 2, y - 12, w, x, y, esc(shown))


# ------------------------------------------------------------------ DAG ---

DAG_W, DAG_H = 190, 52


def dag_svg(prefix: str, slices: Sequence, blocked: Set[int]) -> str:
    nums = [s.number for s in slices]
    edges = [(b, s.number) for s in slices for b in s.blocked_by]
    layer = layers(nums, edges)
    pos = grid(nums, layer, DAG_W, DAG_H)
    width = max(x for x, _ in pos.values()) + DAG_W + PAD
    height = max(y for _, y in pos.values()) + DAG_H + PAD + 30
    paths = "".join(
        '<path class="edge" d="%s" marker-end="url(#%s-arrow)"/>'
        % (curve(pos[a][0] + DAG_W, pos[a][1] + DAG_H / 2, pos[b][0], pos[b][1] + DAG_H / 2), prefix)
        for a, b in edges)
    nodes = "".join(_dag_node(s, pos[s.number], layer[s.number], s.number in blocked) for s in slices)
    return svg_open(prefix, width, height, "Slice dependency graph", _dag_desc(slices, blocked), "group") + paths + nodes + "</svg>"


def _dag_node(s, xy: Tuple[float, float], layer: int, is_blocked: bool) -> str:
    x, y = xy
    name = "Slice %d: %s" % (s.number, s.name)
    status = '<text class="node-sub" x="%.1f" y="%.1f" text-anchor="end">blocked</text>' % (
        x + DAG_W - 10, y + 19) if is_blocked else ""
    return (
        '<a href="#%s" aria-label="%s" class="%s" data-layer="%d"><title>%s</title>'
        '<rect x="%.1f" y="%.1f" width="%d" height="%d" rx="6"/>'
        '<text class="node-sub" x="%.1f" y="%.1f">S%d</text>%s'
        '<text x="%.1f" y="%.1f">%s</text></a>'
        % (slice_anchor(s.number), esc(name), "node node-blocked" if is_blocked else "node", layer, esc(name),
           x, y, DAG_W, DAG_H, x + 10, y + 19, s.number, status, x + 10, y + 39, esc(clip(s.name, 24)))
    )


def _dag_desc(slices: Sequence, blocked: Set[int]) -> str:
    parts = []
    for s in slices:
        if s.blocked_by:
            parts.append("Slice %d (%s) is blocked by %s." % (
                s.number, s.name, ", ".join("slice %d" % b for b in s.blocked_by)))
        else:
            parts.append("Slice %d (%s) has no blocker." % (s.number, s.name))
        if s.number in blocked:
            parts.append("Slice %d waits on an open question." % s.number)
    return " ".join(parts)


# ----------------------------------------------------------------- flow ---

def flow_svg(prefix: str, flow: Flow, title: str) -> str:
    w = min(220, max(120, max(text_w(clip(n, 26)) for n in flow.nodes) + 28))
    h = 52
    layer = layers(flow.nodes, [(a, b) for a, b, _, _ in flow.edges])
    labels = [text_w(clip(label, 34), 0.86) + 34 for _, _, label, _ in flow.edges]
    pos = grid(flow.nodes, layer, w, h, min(260, max([GAP_X] + labels)))
    back = any(layer[b] <= layer[a] for a, b, _, _ in flow.edges)
    width = max(x for x, _ in pos.values()) + w + PAD
    height = max(y for _, y in pos.values()) + h + PAD + (60 if back else 0)
    lanes = "".join(_lane(name, members, pos, w, h) for name, members in flow.groups)
    edges = "".join(_flow_edge(prefix, e, pos, w, h) for e in flow.edges)
    nodes = "".join(_flow_node(n, pos[n], w, h, flow.marks.get(n)) for n in flow.nodes)
    return svg_open(prefix, width, height, title, flow_desc(flow)) + lanes + edges + nodes + "</svg>"


def _lane(name: str, members: List[str], pos: Dict, w: float, h: float) -> str:
    xs = [pos[m][0] for m in members]
    ys = [pos[m][1] for m in members]
    x0, y0 = min(xs) - 10, min(ys) - 22
    return '<rect class="lane" x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="8"/><text class="lane-label" x="%.1f" y="%.1f">%s</text>' % (
        x0, y0, max(xs) - min(xs) + w + 20, max(ys) - min(ys) + h + 32, x0 + 8, y0 + 14, esc(name))


def _flow_edge(prefix: str, edge, pos: Dict, w: float, h: float) -> str:
    a, b, label, dashed = edge
    (ax, ay), (bx, by) = pos[a], pos[b]
    if bx > ax:
        x1, y1, x2, y2 = ax + w, ay + h / 2, bx, by + h / 2
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2 - 4
    else:
        x1, y1, x2, y2 = ax + w / 2, ay + h, bx + w / 2, by + h
        mx, my = (x1 + x2) / 2, max(y1, y2) + 36
    cls = "edge edge-dashed" if dashed else "edge"
    return '<path class="%s" d="%s" marker-end="url(#%s-arrow)"/>%s' % (
        cls, curve(x1, y1, x2, y2), prefix, edge_label(mx, my, label))


def _flow_node(name: str, xy, w: float, h: float, mark: Optional[str]) -> str:
    x, y = xy
    cls = "node node-%s" % mark if mark else "node"
    sub = '<text class="node-sub" x="%.1f" y="%.1f">(%s)</text>' % (x + 10, y + h - 10, mark) if mark else ""
    ty = y + (22 if mark else h / 2 + 5)
    return '<g class="%s"><title>%s</title><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="6"/><text x="%.1f" y="%.1f">%s</text>%s</g>' % (
        cls, esc(name), x, y, w, h, x + 10, ty, esc(clip(name, 26)), sub)


def flow_desc(flow: Flow) -> str:
    parts = ["%s to %s%s" % (a, b, ": " + label if label else "") for a, b, label, _ in flow.edges]
    marks = ["%s is %s" % (n, m) for n, m in flow.marks.items()]
    groups = ["%s groups %s" % (g, ", ".join(ms)) for g, ms in flow.groups]
    return "; ".join(parts + marks + groups) + "."


# ------------------------------------------------------------- sequence ---

ACTOR_H, ROW = 34, 40


def sequence_svg(prefix: str, seq: SeqDiagram, title: str) -> str:
    longest = max([text_w(clip(s.label, 40), 0.92) for s in seq.steps if s.kind == "msg"] + [0])
    col = max(150, min(320, longest + 30), max(text_w(p) + 30 for p in seq.participants))
    xs = {p: PAD + col / 2 + i * col for i, p in enumerate(seq.participants)}
    width = PAD * 2 + col * len(seq.participants)
    body, bottom = _sequence_body(prefix, seq, xs, width)
    height = bottom + PAD
    actors = "".join(_actor(p, xs[p], height) for p in seq.participants)
    return svg_open(prefix, width, height, title, sequence_desc(seq)) + actors + body + "</svg>"


def _actor(name: str, x: float, height: float) -> str:
    w = max(110, text_w(clip(name, 24)) + 24)
    return (
        '<line class="lifeline" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>'
        '<g class="actor"><rect x="%.1f" y="%d" width="%.1f" height="%d" rx="5"/><text x="%.1f" y="%d" text-anchor="middle">%s</text></g>'
        % (x, PAD + ACTOR_H, x, height - PAD, x - w / 2, PAD, w, ACTOR_H, x, PAD + 22, esc(clip(name, 24)))
    )


def _sequence_body(prefix: str, seq: SeqDiagram, xs: Dict, width: float) -> Tuple[str, float]:
    out: List[str] = []
    y = PAD + ACTOR_H + 30
    frames: List[Tuple[float, List[Tuple[float, str]]]] = []  # (top, [(y, label)])
    for step in seq.steps:
        if step.kind == "msg":
            out.append(_message(prefix, step, xs, y))
            y += ROW + (14 if step.a == step.b else 0)
        elif step.kind == "alt":
            frames.append((y, [(y, "alt [%s]" % step.label if step.label else "alt")]))
            y += 30
        elif step.kind == "else":
            frames[-1][1].append((y, "[%s]" % step.label if step.label else "[else]"))
            y += 26
        else:
            top, labels = frames.pop()
            out.insert(0, _frame(top, y, labels, width, len(frames)))
            y += 16
    return "".join(out), y


def _frame(top: float, bottom: float, labels: List[Tuple[float, str]], width: float, depth: int) -> str:
    x0, x1 = PAD / 2 + depth * 8, width - PAD / 2 - depth * 8
    head_y, head = labels[0]
    tab_w = text_w(head, 0.86) + 16
    out = ['<rect class="frame" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>' % (x0, top - 8, x1 - x0, bottom - top),
           '<path class="frame-tab" d="M%.1f,%.1f h%.1f v14 l-6,6 h-%.1f z"/>' % (x0, top - 8, tab_w, tab_w - 6),
           '<text class="frame-label" x="%.1f" y="%.1f">%s</text>' % (x0 + 6, top + 6, esc(head))]
    for y, text in labels[1:]:
        out.append('<line class="frame-divider" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>' % (x0, y - 6, x1, y - 6))
        out.append('<text class="frame-label" x="%.1f" y="%.1f">%s</text>' % (x0 + 6, y + 10, esc(text)))
    return "".join(out)


def _message(prefix: str, step, xs: Dict, y: float) -> str:
    xa, xb = xs[step.a], xs[step.b]
    cls = "msg msg-reply" if step.reply else "msg"
    label = esc(clip(step.label, 44))
    if step.a == step.b:
        return '<path class="%s" d="M%.1f,%.1f h44 v18 h-44" marker-end="url(#%s-arrow)"/><text class="msg-label" x="%.1f" y="%.1f">%s</text>' % (
            cls, xa, y, prefix, xa + 50, y + 13, label)
    return '<line class="%s" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" marker-end="url(#%s-arrow)"/><text class="msg-label" x="%.1f" y="%.1f" text-anchor="middle">%s</text>' % (
        cls, xa, y, xb, y, prefix, (xa + xb) / 2, y - 7, label)


def sequence_desc(seq: SeqDiagram) -> str:
    parts, n = [], 0
    for step in seq.steps:
        if step.kind == "msg":
            n += 1
            verb = "replies to" if step.reply else "calls"
            parts.append("%d. %s %s %s: %s" % (n, step.a, verb, step.b, step.label))
        elif step.kind in ("alt", "else"):
            parts.append("%s %s:" % ("When" if step.kind == "alt" else "Otherwise, when", step.label or "else"))
        else:
            parts.append("End of alternatives.")
    return " ".join(parts)
