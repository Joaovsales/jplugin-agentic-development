"""Typed parsers for the spec sections a visual plan understands.

Each parser takes a `plan_md.Section` and returns plain records, or raises
`SpecError` naming the spec line of the offending row. A known section that is
malformed fails loudly; nothing here guesses past a broken row.
"""

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

from plan_md import Block, Section, SpecError, plain

LEVELS = ("H", "M", "L")


@dataclass
class Decision:
    id: str
    title: str
    chosen: str
    status: str  # settled | open
    line: int
    options: str = ""
    rationale: str = ""
    wrong_when: str = ""
    source: str = ""
    chosen_label: str = ""  # the column the chosen option came from
    status_text: str = ""  # the Status cell as written, e.g. `settled (operator pick)`


@dataclass
class Criterion:
    id: str
    text: str
    line: int


@dataclass
class Slice:
    number: int
    name: str
    line: int
    cells: Dict[str, str]
    blocked_by: Tuple[int, ...]
    acs: Tuple[str, ...]


@dataclass
class BuildOrder:
    slices: List[Slice]
    prompt: Optional[str]
    intro: List[Block] = field(default_factory=list)


@dataclass
class Risk:
    id: str
    text: str
    likelihood: str
    impact: str
    mitigation: str
    slice: str
    line: int


@dataclass
class Risks:
    items: List[Risk]
    none_why: Optional[str] = None


@dataclass
class Question:
    id: str
    text: str
    blocks: Tuple[int, ...]
    needed_from: str
    line: int


# ----------------------------------------------------------- table rows ---

def _tables(section: Section) -> List[Block]:
    return [b for b in section.blocks if b.kind == "table"]


def _one_table(section: Section) -> Block:
    tables = _tables(section)
    if not tables:
        raise SpecError(section.line, "%s has no table" % section.title)
    return tables[0]


def _records(section: Section, table: Block) -> List[Tuple[int, Dict[str, str]]]:
    """Header-keyed rows; a row whose cell count differs from the header fails."""
    header = [plain(c).lower() for c in table.rows[0]]
    out = []
    for row, no in zip(table.rows[1:], table.row_lines[1:]):
        if len(row) != len(header):
            raise SpecError(no, "%s row has %d cells, the header has %d" % (section.title, len(row), len(header)))
        out.append((no, dict(zip(header, row))))
    return out


def _pick(row: Dict[str, str], *names: str) -> str:
    for name in names:
        if name in row:
            return row[name]
    return ""


def _unique(items: Sequence, what: str = "ID") -> None:
    seen = set()
    for item in items:
        if item.id in seen:
            raise SpecError(item.line, "duplicate %s %s" % (what, item.id))
        seen.add(item.id)


def _norm_id(raw: str, prefix: str, n: int) -> str:
    raw = plain(raw)
    if not raw:
        return "%s%d" % (prefix, n)
    return prefix + raw if raw.isdigit() else raw


# ------------------------------------------------------------ decisions ---

def parse_decisions(section: Section) -> List[Decision]:
    table = _one_table(section)
    header = [plain(c).lower() for c in table.rows[0]]
    sdp = "recommended" in header
    title_col = "decision" if sdp or "question" not in header else "question"
    chosen_col = "recommended" if sdp else ("decision" if title_col == "question" else "")
    out = []
    for n, (no, row) in enumerate(_records(section, table), start=1):
        out.append(_decision(row, no, n, title_col, chosen_col))
    _unique(out)
    return out


def _decision(row: Dict[str, str], no: int, n: int, title_col: str, chosen_col: str) -> Decision:
    source = _pick(row, "source")
    raw = plain(_pick(row, "status")).lower() or ("open" if plain(source).lower() == "open" else "settled")
    status = raw.split(" ", 1)[0].strip("(,;")  # `settled (operator pick)` is settled
    if status not in ("settled", "open"):
        raise SpecError(no, "Decisions status must be settled or open, got %r" % status)
    title = row.get(title_col) or next(iter(row.values()), "")
    return Decision(
        id=_norm_id(_pick(row, "id", "#"), "D", n), title=title,
        chosen=row.get(chosen_col, "") if chosen_col else "", status=status, line=no,
        options=_pick(row, "options"), rationale=_pick(row, "why", "rationale", "reason"),
        wrong_when=_pick(row, "wrong when"), source=source, chosen_label=chosen_col.capitalize(),
        status_text=plain(_pick(row, "status")),
    )


# --------------------------------------------------- acceptance criteria ---

_AC = re.compile(r"^\s*(?:\[[ xX]\]\s*)?(?:\*\*)?(AC[\s-]?\d+(?:\.\d+)*)(?:\*\*)?\s*[:.)—-]\s*(.+)$")
_AC_BAD = re.compile(r"^\s*AC\b[^:]*:", re.I)


def parse_criteria(section: Section) -> List[Criterion]:
    items = [item for b in section.blocks if b.kind == "list" for item in b.items]
    if not items:
        raise SpecError(section.line, "Acceptance Criteria has no list items")
    out = []
    for n, item in enumerate(items, start=1):
        m = _AC.match(item.text)
        if m:
            out.append(Criterion(re.sub(r"[\s-]", "", m.group(1)).upper(), m.group(2).strip(), item.line))
        elif _AC_BAD.match(item.text):
            raise SpecError(item.line, "Acceptance Criteria prefix must be AC<number>:")
        else:
            out.append(Criterion("AC%d" % n, re.sub(r"^\[[ xX]\]\s*", "", item.text), item.line))
    _unique(out)
    return out


# ----------------------------------------------------------- build order ---

def _numbers(cell: str, no: int, what: str) -> Tuple[int, ...]:
    text = plain(cell)
    if text in ("", "-", "—", "none"):
        return ()
    out = []
    for part in re.split(r"[,\s]+", text):
        part = re.sub(r"^(slice|s|ac)", "", part.strip(), flags=re.I)
        span = re.match(r"^(\d+)[–-](\d+)$", part)
        if span:
            out.extend(range(int(span.group(1)), int(span.group(2)) + 1))
            continue
        if not part:
            continue
        if not part.isdigit():
            raise SpecError(no, "%s must list numbers, got %r" % (what, cell))
        out.append(int(part))
    return tuple(out)


def _blocked_by(cell: str, no: int) -> Tuple[int, ...]:
    """Bare slice numbers, comma-separated: the grammar `slice.py validate` accepts."""
    text = plain(cell)
    if text in ("", "-", "—"):
        return ()
    parts = [p.strip() for p in text.split(",") if p.strip()]
    if not all(p.isdigit() for p in parts):
        raise SpecError(no, "Build Order Blocked by must list slice numbers, got %r" % cell)
    return tuple(int(p) for p in parts)


def parse_build_order(section: Section) -> BuildOrder:
    table = _one_table(section)
    slices = []
    for no, row in _records(section, table):
        num = plain(_pick(row, "#", "slice #", "n"))
        if not num.isdigit():
            raise SpecError(no, "Build Order slice number must be an integer, got %r" % num)
        slices.append(Slice(
            int(num), _pick(row, "slice", "name"), no, row,
            _blocked_by(_pick(row, "blocked by"), no),
            tuple("AC%d" % n for n in _numbers(_pick(row, "acs"), no, "Build Order ACs")),
        ))
    _check_slices(slices)
    intro = [b for b in section.blocks if b is not table and b.kind != "code" and not _is_prompt_label(b)]
    return BuildOrder(slices, _prompt(section), intro)


def _is_prompt_label(block) -> bool:
    return block.kind == "para" and plain(block.text).lower().startswith("build prompt")


def _prompt(section: Section) -> Optional[str]:
    """The fenced block after a `Build prompt:` paragraph, verbatim."""
    seen_label = False
    for block in section.blocks:
        if _is_prompt_label(block):
            seen_label = True
        elif block.kind == "code" and seen_label:
            return block.text
    return None


def _check_slices(slices: List[Slice]) -> None:
    by_num: Dict[int, Slice] = {}
    for s in slices:
        if s.number in by_num:
            raise SpecError(s.line, "duplicate slice %d" % s.number)
        by_num[s.number] = s
    for s in slices:
        for b in s.blocked_by:
            if b not in by_num:
                raise SpecError(s.line, "slice %d is blocked by slice %d, which the Build Order lacks" % (s.number, b))
    cycle = _cycle(by_num)
    if cycle:
        raise SpecError(by_num[cycle[0]].line, "Build Order cycle: %s" % " -> ".join(map(str, cycle)))


def _cycle(by_num: Dict[int, Slice]) -> Optional[List[int]]:
    state: Dict[int, int] = {}

    def visit(n: int, path: List[int]) -> Optional[List[int]]:
        state[n] = 1
        for b in by_num[n].blocked_by:
            if state.get(b) == 1:
                return path[path.index(b):] + [b] if b in path else [n, b]
            if not state.get(b):
                found = visit(b, path + [b])
                if found:
                    return found
        state[n] = 2
        return None

    for n in sorted(by_num):
        if not state.get(n):
            found = visit(n, [n])
            if found:
                return found
    return None


# ----------------------------------------------------------------- risks ---

_NONE = re.compile(r"^none identified\s*[—:-]+\s*(.+)$", re.I)


def parse_risks(section: Section) -> Risks:
    for block in section.blocks:
        if block.kind == "para" and _NONE.match(plain(block.text)):
            return Risks([], _NONE.match(plain(block.text)).group(1))
    table = _one_table(section)
    out = []
    for n, (no, row) in enumerate(_records(section, table), start=1):
        lik, imp = _level(row, "likelihood", no), _level(row, "impact", no)
        out.append(Risk(_norm_id(_pick(row, "id"), "R", n), _pick(row, "risk"), lik, imp,
                        _pick(row, "mitigation"), _pick(row, "slice"), no))
    _unique(out)
    return Risks(out)


def _level(row: Dict[str, str], col: str, no: int) -> str:
    raw = plain(row.get(col, ""))
    value = raw[:1].upper() if raw.lower() in ("high", "medium", "low") else raw.upper()
    if value not in LEVELS:
        raise SpecError(no, "Risks %s must be H/M/L, got %r" % (col, raw))
    return value


# -------------------------------------------------------- open questions ---

def parse_questions(section: Section, slice_numbers: Optional[set]) -> List[Question]:
    table = _one_table(section)
    out = []
    for n, (no, row) in enumerate(_records(section, table), start=1):
        blocks = _numbers(_pick(row, "blocks"), no, "Open questions Blocks")
        for b in blocks:
            if slice_numbers is None or b not in slice_numbers:
                raise SpecError(no, "Open questions Blocks names slice %d, which the Build Order lacks" % b)
        out.append(Question(_norm_id(_pick(row, "id"), "Q", n), _pick(row, "question"), blocks,
                            _pick(row, "needed from"), no))
    _unique(out)
    return out
