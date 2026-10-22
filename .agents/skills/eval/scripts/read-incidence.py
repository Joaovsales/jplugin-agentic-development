#!/usr/bin/env python3
"""read-incidence.py — how often does the parent agent pull whole large files
into its own context? The read-shunt baseline (specs/read-shunt-baseline.md).

    read-incidence.py [--root DIR] [--bytes N] [--lines N] [--json] [--paths]

Walks a transcript root (default ~/.claude/projects) through
`read_transcript.py` and prints one row per main-loop session plus an
aggregate: reads, whole-file large reads, the bytes those reads delivered and
their share of every tool-result byte in the parent loop, bare shell reads and
their bytes, the largest single result, re-reads of a path already read in the
session, the parent's final context size, compactions, and the sub-agents'
reads in their own column — never the parent's (D5). A read is large at
`--bytes` (32768) or `--lines` (800) (D3).

The aggregate ends with the go rule of D11 applied: the gate is worth building
when whole-file large reads are at least 10% of the parent's tool-result bytes
in the median session, or at least 25% in a quarter of sessions.

Paths are basenames unless `--paths`; file contents never appear. Exit 2 with
the path when the root holds no transcripts or a block cannot be read.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import MISSING, asdict, dataclass, field, fields
from typing import Callable, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import read_transcript as rt  # noqa: E402

GO_MEDIAN_SHARE = 0.10
GO_QUARTER_SHARE = 0.25


Cell = Callable[..., str]    # (row, full_paths) -> the cell's text


def _metric(label: Optional[str], *, summable: bool = True, default: object = 0,
            derived: Optional[Tuple[str, str, Cell]] = None, fmt: Optional[Cell] = None):
    """A Row field and everything the report knows about it: its column label
    (`None` for a field that is no column), whether the aggregate sums it, a
    derived column that follows it, and how its cell reads (`str` when unset)."""
    return field(default=default, metadata={"label": label, "summable": summable, "derived": derived, "fmt": fmt})


@dataclass
class Row:
    session: str = _metric("Session", summable=False, default=MISSING)
    reads: int = _metric("Reads")
    whole_large: int = _metric("Whole-file large")
    whole_large_bytes: int = _metric("Bytes", derived=("share", "Share", lambda row, _: f"{row.share:.1%}"))
    result_bytes: int = _metric(None)
    truncated: int = _metric("Truncated")
    shell_reads: int = _metric("Shell reads")
    shell_bytes: int = _metric("Shell bytes")
    largest: int = _metric("Largest result", summable=False, fmt=lambda row, full_paths: (
        f"{row.largest} ({_display_path(row.largest_path, full_paths)})" if row.largest else "0"))
    largest_path: str = _metric(None, summable=False, default="")
    rereads: int = _metric("Re-reads")
    final_context: Optional[int] = _metric("Final context", summable=False, default=None,
                                           fmt=lambda row, _: "-" if row.final_context is None else str(row.final_context))
    compactions: int = _metric("Compactions")
    subagent_reads: int = _metric("Sub-agent reads")
    subagent_large: int = _metric("Sub-agent large")
    excluded: int = _metric("Excluded")
    malformed: int = _metric("Malformed")

    @property
    def share(self) -> float:
        return self.whole_large_bytes / self.result_bytes if self.result_bytes else 0.0


def _columns() -> List[Tuple[str, str, Cell]]:
    columns: List[Tuple[str, str, Cell]] = []
    for f in fields(Row):
        if f.metadata["label"]:
            columns.append((f.name, f.metadata["label"],
                            f.metadata["fmt"] or (lambda row, _, name=f.name: str(getattr(row, name)))))
        if f.metadata["derived"]:
            columns.append(f.metadata["derived"])
    return columns


COLUMNS = _columns()
SUMMED = [f.name for f in fields(Row) if f.metadata["summable"]]


def measure_session(session: rt.Session, th: rt.Thresholds) -> Row:
    reads = rt.parse_session(session.path, session.subagent_paths)
    parent = reads.parent
    row = Row(f"{session.project}/{parent.session_id}" if session.project else parent.session_id)
    row.result_bytes = parent.own_result_bytes()
    row.final_context = parent.final_context
    row.compactions = parent.compactions
    row.malformed = reads.malformed
    row.largest, row.largest_path = parent.largest_own_result()
    seen: set = set()
    for call in parent.own_calls():
        if isinstance(call, rt.Read):
            _count_read(row, call, seen, th)
        elif isinstance(call, rt.ShellRead):
            row.shell_reads += len(call.paths)
            row.shell_bytes += call.bytes
            row.rereads += sum(1 for p in call.paths if p in seen)
            seen.update(call.paths)
    for read in reads.counted_sidechain_reads:
        _count_subagent_read(row, read, th)
    return row


def _count_read(row: Row, read: rt.Read, seen: set, th: rt.Thresholds) -> None:
    if read.is_excluded:
        row.excluded += 1
        return
    row.reads += 1
    if read.norm_path in seen:
        row.rereads += 1
    seen.add(read.norm_path)
    if read.truncated:
        row.truncated += 1
    if read.is_whole_large(th):
        row.whole_large += 1
        row.whole_large_bytes += read.bytes


def _count_subagent_read(row: Row, read: rt.Read, th: rt.Thresholds) -> None:
    row.subagent_reads += 1
    if read.is_whole_large(th):
        row.subagent_large += 1


@dataclass
class Aggregate:
    total: Row
    sessions: int
    median_share: float
    quarter_share: float
    verdict: str


def aggregate(rows: List[Row]) -> Aggregate:
    total = Row("all sessions")
    for r in rows:
        for key in SUMMED:
            setattr(total, key, getattr(total, key) + getattr(r, key))
        if r.largest > total.largest:
            total.largest, total.largest_path = r.largest, r.largest_path
    shares = sorted(r.share for r in rows)
    n = len(shares)
    median = shares[n // 2] if n % 2 else (shares[n // 2 - 1] + shares[n // 2]) / 2
    quarter = shares[n - math.ceil(n / 4)]
    gate = median >= GO_MEDIAN_SHARE or quarter >= GO_QUARTER_SHARE
    return Aggregate(total, n, median, quarter, "gate" if gate else "not worth gating")


def _display_path(path: str, full: bool) -> str:
    if full or not path:
        return path
    return path.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]


def render_markdown(rows: List[Row], agg: Aggregate, args: argparse.Namespace) -> str:
    full_paths = args.paths
    headers = [label for _, label, _ in COLUMNS]

    def cells(row: Row) -> List[str]:
        return [fmt(row, full_paths) for _, _, fmt in COLUMNS]
    lines = [f"# Read incidence over `{args.root}` (bytes >= {args.bytes}, lines >= {args.lines})", "",
             "## Per session", "", rt.markdown_table(headers, [cells(r) for r in rows]),
             "", "## Aggregate", "", rt.markdown_table(headers, [cells(agg.total)]), "",
             f"Sessions: {agg.sessions} · median share {agg.median_share:.1%} · "
              f"quarter share {agg.quarter_share:.1%}",
              f"Verdict: {agg.verdict} — gate when the median share is at least {GO_MEDIAN_SHARE:.0%} "
              f"or a quarter of sessions reach {GO_QUARTER_SHARE:.0%}"]
    return "\n".join(lines)


def render_json(rows: List[Row], agg: Aggregate, args: argparse.Namespace) -> str:
    def row_dict(r: Row) -> Dict[str, object]:
        d = asdict(r)
        d["share"] = r.share
        d["largest_path"] = _display_path(r.largest_path, args.paths)
        return d
    out = {
        "root": args.root, "bytes": args.bytes, "lines": args.lines,
        "sessions": [row_dict(r) for r in rows],
        "aggregate": {**row_dict(agg.total), "sessions": agg.sessions,
                      "median_share": agg.median_share, "quarter_share": agg.quarter_share,
                      "go_median_share": GO_MEDIAN_SHARE, "go_quarter_share": GO_QUARTER_SHARE,
                      "verdict": agg.verdict},
    }
    return json.dumps(out, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    parser.add_argument("--bytes", type=int, default=rt.DEFAULT_BYTES)
    parser.add_argument("--lines", type=int, default=rt.DEFAULT_LINES)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--paths", action="store_true", help="full paths instead of basenames")
    args = parser.parse_args()
    th = rt.Thresholds(args.bytes, args.lines)
    rows = [measure_session(s, th) for s in rt.iter_sessions(args.root)]
    agg = aggregate(rows)
    render = render_json if args.json else render_markdown
    sys.stdout.buffer.write((render(rows, agg, args) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(rt.run(main))
