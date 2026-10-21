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
from dataclasses import asdict, dataclass, field
from typing import Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import read_transcript as rt  # noqa: E402

GO_MEDIAN_SHARE = 0.10
GO_QUARTER_SHARE = 0.25

COLUMNS = [
    ("session", "Session"), ("reads", "Reads"), ("whole_large", "Whole-file large"),
    ("whole_large_bytes", "Bytes"), ("share", "Share"), ("truncated", "Truncated"),
    ("shell_reads", "Shell reads"), ("shell_bytes", "Shell bytes"), ("largest", "Largest result"),
    ("rereads", "Re-reads"), ("final_context", "Final context"), ("compactions", "Compactions"),
    ("subagent_reads", "Sub-agent reads"), ("subagent_large", "Sub-agent large"),
    ("excluded", "Excluded"), ("malformed", "Malformed"),
]


@dataclass
class Row:
    session: str
    reads: int = 0
    whole_large: int = 0
    whole_large_bytes: int = 0
    result_bytes: int = 0
    truncated: int = 0
    shell_reads: int = 0
    shell_bytes: int = 0
    largest: int = 0
    largest_path: str = ""
    rereads: int = 0
    final_context: Optional[int] = None
    compactions: int = 0
    subagent_reads: int = 0
    subagent_large: int = 0
    excluded: int = 0
    malformed: int = 0

    @property
    def share(self) -> float:
        return self.whole_large_bytes / self.result_bytes if self.result_bytes else 0.0


def measure_session(session: rt.Session, bytes_t: int, lines_t: int) -> Row:
    parent = rt.parse_transcript(session.path)
    row = Row(f"{session.project}/{parent.session_id}" if session.project else parent.session_id)
    row.result_bytes = parent.tool_result_bytes()
    row.final_context = parent.final_context
    row.compactions = parent.compactions
    row.malformed = parent.malformed
    seen: set = set()
    reads_by_id = {r.tool_use.id: r for r in parent.reads()}
    for use in parent.tool_uses:
        result = parent.results.get(use.id)
        if use.name == "Read":
            _count_read(row, reads_by_id[use.id], seen, bytes_t, lines_t)
        elif use.name == "Bash" and not use.sidechain and result is not None:
            files = rt.bare_shell_reads(str(use.input.get("command", "")))
            if files:
                row.shell_reads += len(files)
                row.shell_bytes += result.bytes
                row.rereads += sum(1 for f in files if rt.normalize_path(f) in seen)
                seen.update(rt.normalize_path(f) for f in files)
        if result is not None and result.bytes > row.largest and not use.sidechain:
            row.largest = result.bytes
            row.largest_path = str(use.input.get("file_path") or use.input.get("command") or use.name)
    for path in session.subagent_paths:
        agent = rt.parse_transcript(path, is_subagent=True)
        row.malformed += agent.malformed
        for read in agent.reads():
            _count_subagent_read(row, read, bytes_t, lines_t)
    return row


def _count_read(row: Row, read: rt.Read, seen: set, bytes_t: int, lines_t: int) -> None:
    if read.tool_use.sidechain:
        _count_subagent_read(row, read, bytes_t, lines_t)
        return
    if read.kind == "excluded":
        row.excluded += 1
        return
    row.reads += 1
    if read.norm_path in seen:
        row.rereads += 1
    seen.add(read.norm_path)
    if read.truncated:
        row.truncated += 1
    if read.kind == "whole" and read.is_large(bytes_t, lines_t):
        row.whole_large += 1
        row.whole_large_bytes += read.bytes


def _count_subagent_read(row: Row, read: rt.Read, bytes_t: int, lines_t: int) -> None:
    if read.kind == "excluded":
        return
    row.subagent_reads += 1
    if read.kind == "whole" and read.is_large(bytes_t, lines_t):
        row.subagent_large += 1


def aggregate(rows: List[Row]) -> Dict[str, object]:
    total = Row("all sessions")
    for r in rows:
        for key in ("reads", "whole_large", "whole_large_bytes", "result_bytes", "truncated", "shell_reads",
                    "shell_bytes", "rereads", "compactions", "subagent_reads", "subagent_large",
                    "excluded", "malformed"):
            setattr(total, key, getattr(total, key) + getattr(r, key))
        if r.largest > total.largest:
            total.largest, total.largest_path = r.largest, r.largest_path
    shares = sorted(r.share for r in rows)
    n = len(shares)
    median = shares[n // 2] if n % 2 else (shares[n // 2 - 1] + shares[n // 2]) / 2
    quarter = shares[n - math.ceil(n / 4)]
    gate = median >= GO_MEDIAN_SHARE or quarter >= GO_QUARTER_SHARE
    return {
        "sessions": n, "total": total, "median_share": median, "quarter_share": quarter,
        "verdict": "gate" if gate else "not worth gating",
    }


def _display_path(path: str, full: bool) -> str:
    if full or not path:
        return path
    return path.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]


def _cell(row: Row, key: str, full_paths: bool) -> str:
    if key == "share":
        return f"{row.share:.1%}"
    if key == "largest":
        return f"{row.largest} ({_display_path(row.largest_path, full_paths)})" if row.largest else "0"
    if key == "final_context":
        return "-" if row.final_context is None else str(row.final_context)
    return str(getattr(row, key))


def render_markdown(rows: List[Row], agg: Dict[str, object], full_paths: bool, args: argparse.Namespace) -> str:
    header = "| " + " | ".join(label for _, label in COLUMNS) + " |"
    rule = "|" + "|".join("---" for _ in COLUMNS) + "|"
    lines = [f"# Read incidence over `{args.root}` (bytes >= {args.bytes}, lines >= {args.lines})", "",
             "## Per session", "", header, rule]
    lines += ["| " + " | ".join(_cell(r, key, full_paths) for key, _ in COLUMNS) + " |" for r in rows]
    total: Row = agg["total"]  # type: ignore[assignment]
    lines += ["", "## Aggregate", "", header, rule,
              "| " + " | ".join(_cell(total, key, full_paths) for key, _ in COLUMNS) + " |", "",
              f"Sessions: {agg['sessions']} · median share {agg['median_share']:.1%} · "
              f"quarter share {agg['quarter_share']:.1%}",
              f"Verdict: {agg['verdict']} — gate when the median share is at least {GO_MEDIAN_SHARE:.0%} "
              f"or a quarter of sessions reach {GO_QUARTER_SHARE:.0%}"]
    return "\n".join(lines)


def render_json(rows: List[Row], agg: Dict[str, object], full_paths: bool, args: argparse.Namespace) -> str:
    def row_dict(r: Row) -> Dict[str, object]:
        d = asdict(r)
        d["share"] = r.share
        d["largest_path"] = _display_path(r.largest_path, full_paths)
        return d
    out = {
        "root": args.root, "bytes": args.bytes, "lines": args.lines,
        "sessions": [row_dict(r) for r in rows],
        "aggregate": {**row_dict(agg["total"]), "sessions": agg["sessions"],  # type: ignore[arg-type]
                      "median_share": agg["median_share"], "quarter_share": agg["quarter_share"],
                      "go_median_share": GO_MEDIAN_SHARE, "go_quarter_share": GO_QUARTER_SHARE,
                      "verdict": agg["verdict"]},
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
    rows = [measure_session(s, args.bytes, args.lines) for s in rt.iter_sessions(args.root)]
    agg = aggregate(rows)
    render = render_json if args.json else render_markdown
    sys.stdout.buffer.write((render(rows, agg, args.paths, args) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(rt.run(main))
