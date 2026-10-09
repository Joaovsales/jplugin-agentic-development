"""Reference components, collapsed by default: constraints, contracts, data models, references."""

import re
from typing import Callable, List, Optional, Tuple

from plan_cards import chip, head
from plan_md import Block, Section, esc, inline, plain, render_blocks

_MARKER = re.compile(r"\s*\((?P<mark>new|changed)\b[^)]*\)\s*", re.I)


def _subsections(section: Section) -> Tuple[List[Block], List[Tuple[Block, List[Block]]]]:
    """Blocks before the first `###`, then (heading, blocks) per `###` subsection."""
    lead: List[Block] = []
    groups: List[Tuple[Block, List[Block]]] = []
    for block in section.blocks:
        if block.kind == "heading" and block.level == 3:
            groups.append((block, []))
        elif groups:
            groups[-1][1].append(block)
        else:
            lead.append(block)
    return lead, groups


def _title_and_mark(text: str) -> Tuple[str, Optional[str]]:
    m = _MARKER.search(text)
    if not m:
        return text, None
    return (text[:m.start()] + " " + text[m.end():]).strip(), m.group("mark").lower()


def _copyable(blocks: List[Block], prefix: str, hook: Callable) -> str:
    """Render blocks; each code block gets an id and a copy button."""
    out = []
    for n, block in enumerate(blocks, start=1):
        if block.kind == "code" and hook(block) is None:
            cid = "%s-code-%d" % (prefix, n)
            out.append('<pre><code id="%s">%s</code></pre><button type="button" class="copy" data-copy-from="%s">Copy</button>'
                       % (cid, esc(block.text), cid))
        else:
            out.append(render_blocks([block], hook))
    return "".join(out)


def _grouped(section: Section, kind: str, hook: Callable, copy: bool) -> str:
    lead, groups = _subsections(section)
    cards = []
    for heading, blocks in groups:
        title, mark = _title_and_mark(heading.text)
        aid = "%s-%s" % (kind, re.sub(r"[^a-z0-9]+", "-", plain(title).lower()).strip("-"))
        body = _copyable(blocks, aid, hook) if copy else render_blocks(blocks, hook)
        cards.append('<article class="card card-%s" id="%s">%s<div class="card-body">%s</div></article>' % (
            kind, aid, head(kind, "", chip(mark) if mark else "", inline(title)), body))
    body = _copyable(lead, kind, hook) if copy else render_blocks(lead, hook)
    return body + ('<div class="cards">%s</div>' % "".join(cards) if cards else "")


def render_contracts(section: Section, hook: Callable) -> str:
    return _grouped(section, "contract", hook, copy=True)


def render_models(section: Section, hook: Callable) -> str:
    return _grouped(section, "model", hook, copy=False)


def render_constraints(section: Section, hook: Callable) -> str:
    tables = [b for b in section.blocks if b.kind == "table"]
    if not tables:
        return render_blocks(section.blocks, hook)
    table = tables[0]
    header = table.rows[0]
    cards = []
    names = [plain(h).lower() for h in header]
    source = names.index("source") if "source" in names else -1
    for raw in table.rows[1:]:
        # tolerant, not a strict section: short rows pad, extra cells keep a blank label
        cells = raw + [""] * (len(header) - len(raw))
        labels = header + [""] * (len(cells) - len(header))
        inferred = source >= 0 and "inferred" in plain(cells[source]).lower()
        rows = "".join("<dt>%s</dt><dd>%s</dd>" % (inline(h), inline(c)) for h, c in zip(labels[1:], cells[1:]))
        cards.append('<article class="card card-constraint">%s<dl class="constraint-body">%s</dl></article>' % (
            head("constraint", "", chip("verify") if inferred else "", inline(cells[0])), rows))
    rest = [b for b in section.blocks if b is not table]
    return render_blocks(rest, hook) + '<div class="cards">%s</div>' % "".join(cards)


def render_references(section: Section, hook: Callable) -> str:
    out = []
    for block in section.blocks:
        if block.kind != "list":
            out.append(render_blocks([block], hook))
            continue
        items = "".join('<li class="card card-reference">%s<span>%s</span></li>' % (
            head("reference"), inline(item.text)) for item in block.items)
        out.append('<ul class="cards refs">%s</ul>' % items)
    return "".join(out)
