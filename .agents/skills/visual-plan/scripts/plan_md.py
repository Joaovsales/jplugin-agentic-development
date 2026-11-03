"""Stdlib-only markdown subset for visual plans.

Parses the subset specs are written in — headings, paragraphs, block quotes,
ordered and unordered (nested) lists, tables, fenced code, inline code, bold,
italic and links — into line-numbered blocks, and renders blocks and inline
text to escaped HTML. Every block keeps the 1-based spec line it starts on, so
a section parser can fail with `<spec>:<line>: <reason>`.
"""

import html
import re
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Tuple


class SpecError(Exception):
    """A spec that cannot be rendered as written: carries the spec line."""

    def __init__(self, line: int, reason: str):
        super().__init__(reason)
        self.line = line
        self.reason = reason


@dataclass
class ListItem:
    text: str
    line: int
    children: List["Block"] = field(default_factory=list)


@dataclass
class Block:
    kind: str  # heading | para | quote | list | table | code | hr
    line: int
    text: str = ""
    level: int = 0
    lang: str = ""
    ordered: bool = False
    items: List[ListItem] = field(default_factory=list)
    rows: List[List[str]] = field(default_factory=list)
    row_lines: List[int] = field(default_factory=list)


@dataclass
class Section:
    title: str
    line: int
    blocks: List[Block]


@dataclass
class Document:
    title: str
    preamble: List[Block]
    sections: List[Section]


_FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([^`\s]*)")
_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
_LIST = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")
_HR = re.compile(r"^\s*([-*_])(\s*\1){2,}\s*$")


def strip_frontmatter(lines: List[str]) -> int:
    """Index of the first line after a leading `---` YAML block (0 when none)."""
    if not lines or lines[0].strip() != "---":
        return 0
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return i + 1
    raise SpecError(1, "unclosed frontmatter block")


def split_cells(row: str) -> List[str]:
    """Split one table row on `|`, honouring `\\|` and backtick code spans."""
    text = row.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|") and not text.endswith("\\|"):
        text = text[:-1]
    cells, cur, in_code = [], [], False
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text) and text[i + 1] == "|":
            cur.append("|")
            i += 2
            continue
        if ch == "`":
            in_code = not in_code
        if ch == "|" and not in_code:
            cells.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    cells.append("".join(cur).strip())
    return cells


class _Reader:
    """Line cursor over the spec body; `no` is the 1-based spec line."""

    def __init__(self, lines: List[str], offset: int):
        self.lines = lines
        self.i = offset

    def done(self) -> bool:
        return self.i >= len(self.lines)

    def peek(self) -> str:
        return self.lines[self.i]

    @property
    def no(self) -> int:
        return self.i + 1


def _read_fence(r: _Reader) -> Block:
    m = _FENCE.match(r.peek())
    start, marker, lang = r.no, m.group(2), m.group(3)
    r.i += 1
    body = []
    while not r.done():
        line = r.peek()
        stripped = line.strip()
        if stripped.startswith(marker[0] * len(marker)) and set(stripped) == {marker[0]}:
            r.i += 1
            return Block("code", start, text="\n".join(body), lang=lang.lower())
        body.append(line)
        r.i += 1
    raise SpecError(start, "unclosed code fence")


def _read_table(r: _Reader) -> Block:
    block = Block("table", r.no)
    while not r.done() and r.peek().strip().startswith("|"):
        if not _TABLE_SEP.match(r.peek()):
            block.rows.append(split_cells(r.peek()))
            block.row_lines.append(r.no)
        r.i += 1
    return block


def _is_table_start(r: _Reader) -> bool:
    if not r.peek().strip().startswith("|") or r.i + 1 >= len(r.lines):
        return False
    return bool(_TABLE_SEP.match(r.lines[r.i + 1]))


def _read_list(r: _Reader) -> Block:
    """Collect list lines (with continuations) and build the nesting tree."""
    entries: List[Tuple[int, bool, str, int]] = []
    while not r.done():
        line = r.peek()
        m = _LIST.match(line)
        if m:
            entries.append((len(m.group(1).expandtabs(4)), m.group(2)[0].isdigit(), m.group(3), r.no))
        elif line.strip() and line[:1].isspace() and entries:
            ind, ordered, text, no = entries[-1]
            entries[-1] = (ind, ordered, text + " " + line.strip(), no)
        elif not line.strip() and _list_continues(r):
            pass
        else:
            break
        r.i += 1
    return _nest(entries)


def _list_continues(r: _Reader) -> bool:
    for j in range(r.i + 1, len(r.lines)):
        nxt = r.lines[j]
        if nxt.strip():
            return bool(_LIST.match(nxt)) and nxt[:1].isspace()
    return False


def _nest(entries: List[Tuple[int, bool, str, int]]) -> Block:
    root = Block("list", entries[0][3], ordered=entries[0][1])
    stack: List[Tuple[int, Block]] = [(entries[0][0], root)]
    for indent, ordered, text, no in entries:
        while len(stack) > 1 and indent < stack[-1][0]:
            stack.pop()
        if indent > stack[-1][0] and stack[-1][1].items:
            child = Block("list", no, ordered=ordered)
            stack[-1][1].items[-1].children.append(child)
            stack.append((indent, child))
        stack[-1][1].items.append(ListItem(text, no))
    return root


def _read_quote(r: _Reader) -> Block:
    block, parts = Block("quote", r.no), []
    while not r.done() and r.peek().lstrip().startswith(">"):
        parts.append(r.peek().lstrip()[1:].strip())
        r.i += 1
    block.text = "\n".join(parts)
    return block


def _read_para(r: _Reader) -> Block:
    block, parts = Block("para", r.no), []
    while not r.done() and r.peek().strip() and not _starts_block(r):
        parts.append(r.peek().strip())
        r.i += 1
    block.text = " ".join(parts)
    return block


def _starts_block(r: _Reader) -> bool:
    line = r.peek()
    return bool(
        _FENCE.match(line) or _HEADING.match(line) or _LIST.match(line)
        or line.lstrip().startswith(">") or _is_table_start(r) or _HR.match(line)
    )


def _read_block(r: _Reader) -> Optional[Block]:
    line = r.peek()
    if not line.strip():
        r.i += 1
        return None
    if _FENCE.match(line):
        return _read_fence(r)
    m = _HEADING.match(line)
    if m:
        r.i += 1
        return Block("heading", r.no - 1, text=m.group(2), level=len(m.group(1)))
    if _is_table_start(r):
        return _read_table(r)
    if _HR.match(line):
        r.i += 1
        return Block("hr", r.no - 1)
    if _LIST.match(line):
        return _read_list(r)
    if line.lstrip().startswith(">"):
        return _read_quote(r)
    return _read_para(r)


def parse_blocks(text: str) -> List[Block]:
    lines = text.splitlines()
    r = _Reader(lines, strip_frontmatter(lines))
    blocks = []
    while not r.done():
        block = _read_block(r)
        if block is not None:
            blocks.append(block)
    return blocks


def parse_document(text: str) -> Document:
    """Split blocks into the `#` title, the preamble and the `##` sections."""
    title, preamble, sections = "", [], []
    for block in parse_blocks(text):
        if block.kind == "heading" and block.level == 1 and not title and not sections:
            title = block.text
        elif block.kind == "heading" and block.level == 2:
            sections.append(Section(block.text, block.line, []))
        elif sections:
            sections[-1].blocks.append(block)
        else:
            preamble.append(block)
    return Document(title or "Untitled spec", preamble, sections)


# ---------------------------------------------------------------- inline ---

_INLINE = re.compile(
    r"(?P<code>`+)(?P<codebody>.+?)(?P=code)"
    r"|\[(?P<ltext>[^\]]+)\]\((?P<href>[^)\s]+)\)"
    r"|\*\*(?P<bold>.+?)\*\*"
    r"|(?<![\w*])\*(?P<em>[^\s*](?:.*?[^\s*])?)\*(?![\w*])"
    r"|(?<![\w])_(?P<em2>[^\s_](?:.*?[^\s_])?)_(?![\w])"
)
_SAFE_HREF = re.compile(r"^(https?:|mailto:|#|\.{0,2}/|[\w.-]+(/|\.|#|$))", re.I)


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def inline(text: str) -> str:
    """Render inline markdown to escaped HTML."""
    out, pos = [], 0
    for m in _INLINE.finditer(text):
        out.append(esc(text[pos:m.start()]))
        out.append(_inline_token(m))
        pos = m.end()
    out.append(esc(text[pos:]))
    return "".join(out)


def _inline_token(m: "re.Match") -> str:
    if m.group("code"):
        return "<code>%s</code>" % esc(m.group("codebody").strip())
    if m.group("ltext") is not None:
        href = m.group("href")
        if not _SAFE_HREF.match(href) or href.lower().startswith("javascript:"):
            return esc(m.group(0))
        return '<a href="%s">%s</a>' % (esc(href), inline(m.group("ltext")))
    if m.group("bold") is not None:
        return "<strong>%s</strong>" % inline(m.group("bold"))
    return "<em>%s</em>" % inline(m.group("em") or m.group("em2"))


def plain(text: str) -> str:
    """Inline markdown stripped to plain text (for labels and slugs); code keeps its characters."""
    return _INLINE.sub(_plain_token, text).strip()


def _plain_token(m: "re.Match") -> str:
    if m.group("code"):
        return m.group("codebody").strip()
    return plain(m.group("ltext") or m.group("bold") or m.group("em") or m.group("em2") or "")


# ---------------------------------------------------------------- blocks ---

_BOX = re.compile(r"[┌┐└┘│─├┤┬┴┼═║╔╗╚╝▶▼◀▲]|\+-{2,}|-{2,}>|<-{2,}|\|\s.*\s\|")


# (icon, label) of the text-diagram component; plan_cards.COMPONENTS reads it from here
TEXT_DIAGRAM = ("≡", "Text diagram")


def looks_like_diagram(body: str) -> bool:
    """A `text` fence is a diagram when several lines carry box or arrow art."""
    hits = sum(1 for line in body.splitlines() if _BOX.search(line))
    return hits >= 2


def render_table(block: Block) -> str:
    head, body = block.rows[0], block.rows[1:]
    ths = "".join('<th scope="col">%s</th>' % inline(c) for c in head)
    trs = "".join(
        "<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in row) for row in body
    )
    return (
        '<div class="table-scroll" tabindex="0" role="region" aria-label="%s">'
        "<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>"
        % (esc("Table: " + ", ".join(plain(c) for c in head[:3])), ths, trs)
    )


def render_list(block: Block) -> str:
    tag = "ol" if block.ordered else "ul"
    items = "".join(
        "<li>%s%s</li>" % (inline(item.text), "".join(render_list(c) for c in item.children))
        for item in block.items
    )
    return "<%s>%s</%s>" % (tag, items, tag)


def render_code(block: Block) -> str:
    code = "<pre><code>%s</code></pre>" % esc(block.text)
    if block.lang in ("text", "") and looks_like_diagram(block.text):
        return ('<details class="text-diagram card-text-diagram"><summary><span class="card-icon" aria-hidden="true">%s</span>'
                '<span class="card-label">%s</span></summary>%s</details>' % (TEXT_DIAGRAM[0], TEXT_DIAGRAM[1], code))
    return code


def render_block(block: Block) -> str:
    if block.kind == "heading":
        level = min(max(block.level, 3), 6)
        return "<h%d>%s</h%d>" % (level, inline(block.text), level)
    if block.kind == "para":
        return "<p>%s</p>" % inline(block.text)
    if block.kind == "quote":
        return "<blockquote>%s</blockquote>" % "<br>".join(inline(t) for t in block.text.split("\n"))
    if block.kind == "list":
        return render_list(block)
    if block.kind == "table":
        return render_table(block)
    if block.kind == "code":
        return render_code(block)
    return "<hr>"


def render_blocks(blocks: List[Block], hook: Optional[Callable[[Block], Optional[str]]] = None) -> str:
    """Render blocks; `hook` may claim a block (a diagram fence) by returning HTML."""
    out = []
    for block in blocks:
        claimed = hook(block) if hook else None
        out.append(claimed if claimed is not None else render_block(block))
    return "\n".join(out)
