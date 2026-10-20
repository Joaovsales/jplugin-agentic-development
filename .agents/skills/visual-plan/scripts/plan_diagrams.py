"""Strict parsers for the `flow` and `sequence` diagram fences.

Both DSLs are a Mermaid-flavoured subset. An unsupported line fails with its
spec line number; nothing falls back to an empty or partial diagram.

flow:      `A -> B : label` (or `-->` dashed), `group <Name>: a, b`,
           `A (new)` / `A (changed)` markers on any node mention,
           `caption: <text>`, `%%` comments.
sequence:  `A -> B : msg` calls (`->>` too), `A --> B : msg` replies (`-->>`),
           `participant <name>`, `alt <cond>` / `else <cond>` / `end`,
           `caption: <text>`, `%%` comments.
"""

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from plan_md import SpecError

_MARK = re.compile(r"^(?P<name>.*?)\s*\((?P<mark>new|changed)\)\s*$", re.I)
_FLOW_EDGE = re.compile(r"^(?P<a>[^:]+?)\s+(?P<arrow>-->|->)\s+(?P<b>[^:]+?)\s*(?::\s*(?P<label>.*\S))?\s*$")
_GROUP = re.compile(r"^group\s+(?P<name>[^:]+?)\s*:\s*(?P<members>.+)$", re.I)
_CAPTION = re.compile(r"^caption\s*:\s*(?P<text>.+)$", re.I)
_SEQ_MSG = re.compile(r"^(?P<a>[^:]+?)\s*(?P<arrow>-->>|-->|->>|->)\s*(?P<b>[^:]+?)\s*:\s*(?P<label>.*\S)\s*$")
_PARTICIPANT = re.compile(r"^participant\s+(?P<name>.+)$", re.I)
_ALT = re.compile(r"^(?P<kw>alt|else)\b\s*(?P<cond>.*)$", re.I)


@dataclass
class Flow:
    nodes: List[str] = field(default_factory=list)
    marks: Dict[str, str] = field(default_factory=dict)
    edges: List[Tuple[str, str, str, bool]] = field(default_factory=list)  # a, b, label, dashed
    groups: List[Tuple[str, List[str]]] = field(default_factory=list)
    caption: str = ""


@dataclass
class Step:
    kind: str  # msg | alt | else | end
    a: str = ""
    b: str = ""
    label: str = ""
    reply: bool = False


@dataclass
class Sequence:
    participants: List[str] = field(default_factory=list)
    steps: List[Step] = field(default_factory=list)
    caption: str = ""


def _lines(body: str, first_line: int):
    """(spec line, stripped text) for each meaningful DSL line."""
    for offset, raw in enumerate(body.splitlines(), start=1):
        text = raw.strip()
        if text and not text.startswith("%%"):
            yield first_line + offset, text


def _node(flow: Flow, raw: str) -> str:
    m = _MARK.match(raw.strip())
    name = (m.group("name") if m else raw).strip()
    if not name:
        raise ValueError("empty node name")
    if m:
        flow.marks[name] = m.group("mark").lower()
    if name not in flow.nodes:
        flow.nodes.append(name)
    return name


def parse_flow(body: str, fence_line: int) -> Flow:
    flow = Flow()
    for no, text in _lines(body, fence_line):
        try:
            supported = _flow_line(flow, text)
        except ValueError as err:  # _node: a marker with no name
            raise SpecError(no, "%s: %r" % (err, text)) from None
        if not supported:
            raise SpecError(no, "unsupported flow line: %r" % text)
    if not flow.edges and not flow.nodes:
        raise SpecError(fence_line, "empty flow diagram")
    return flow


def _flow_line(flow: Flow, text: str) -> bool:
    for pattern, apply in ((_CAPTION, _flow_caption), (_GROUP, _flow_group), (_FLOW_EDGE, _flow_edge)):
        m = pattern.match(text)
        if m:
            apply(flow, m)
            return True
    if re.search(r"[<>=|{}\[\]:]", text):
        return False
    _node(flow, text)
    return True


def _flow_caption(flow: Flow, m: "re.Match") -> None:
    flow.caption = m.group("text").strip()


def _flow_group(flow: Flow, m: "re.Match") -> None:
    members = [_node(flow, part) for part in m.group("members").split(",") if part.strip()]
    flow.groups.append((m.group("name").strip(), members))


def _flow_edge(flow: Flow, m: "re.Match") -> None:
    a, b = _node(flow, m.group("a")), _node(flow, m.group("b"))
    flow.edges.append((a, b, (m.group("label") or "").strip(), m.group("arrow") == "-->"))


def parse_sequence(body: str, fence_line: int) -> Sequence:
    seq, depth = Sequence(), 0
    for no, text in _lines(body, fence_line):
        depth = _sequence_line(seq, text, no, depth)
    if depth:
        raise SpecError(fence_line, "alt without end")
    if not any(s.kind == "msg" for s in seq.steps):
        raise SpecError(fence_line, "empty sequence diagram")
    return seq


def _sequence_line(seq: Sequence, text: str, no: int, depth: int) -> int:
    m = _CAPTION.match(text)
    if m:
        seq.caption = m.group("text").strip()
        return depth
    m = _PARTICIPANT.match(text)
    if m:
        _participant(seq, m.group("name"))
        return depth
    if text.lower() == "end":
        if not depth:
            raise SpecError(no, "end without alt")
        seq.steps.append(Step("end"))
        return depth - 1
    m = _ALT.match(text)
    if m:
        return _alt(seq, m, no, depth)
    m = _SEQ_MSG.match(text)
    if not m:
        raise SpecError(no, "unsupported sequence line: %r" % text)
    a, b = _participant(seq, m.group("a")), _participant(seq, m.group("b"))
    seq.steps.append(Step("msg", a, b, m.group("label"), m.group("arrow").startswith("--")))
    return depth


def _alt(seq: Sequence, m: "re.Match", no: int, depth: int) -> int:
    kind = m.group("kw").lower()
    if kind == "else" and not depth:
        raise SpecError(no, "else without alt")
    seq.steps.append(Step(kind, label=m.group("cond").strip()))
    return depth + 1 if kind == "alt" else depth


def _participant(seq: Sequence, raw: str) -> str:
    name = raw.strip()
    if name not in seq.participants:
        seq.participants.append(name)
    return name


def parse_diagram(lang: str, body: str, fence_line: int) -> Optional[object]:
    if lang == "flow":
        return parse_flow(body, fence_line)
    if lang == "sequence":
        return parse_sequence(body, fence_line)
    return None
