#!/usr/bin/env python3
"""workflow-incidence.py — the `workflow` producer's engine: rank agent-workflow
waste and unreliability over completed sessions, bounded by a cursor.

    workflow-incidence.py scan    [--root DIR] [--cursor FILE] [--report FILE]
                                  [--max-sessions 50] [--token-budget N]
                                  [--max-seconds 1200] [--settle-minutes 60]
                                  [--fixed-context N] [--full-suite TEXT ...]
    workflow-incidence.py advance [--root DIR] [--cursor FILE] [--report FILE]
    workflow-incidence.py pending [--root DIR] [--cursor FILE] [--settle-minutes 60]

It is not a transcript collector. Every session is read through
`read_transcript.py` (the one reader of the on-disk JSONL) and measured with
`read-incidence.py`'s `measure_session`, so the parser, the read classifier
and the per-session read-incidence row are the ones the read-shunt baseline
already trusts. This file only ranks what they return
(specs/claude-mem-retention.md § Proposed routine: workflow producer).

Seven candidate kinds, each counted per context — a parent's own calls and
each sub-agent's calls are separate contexts and never summed together:

  repeated-denied-call    one identical call answered with an error twice or more
  expired-retrieval-loop  one identical retrieval call (`*retrieve*`) issued twice or more
  duplicated-read         the same Read (path, offset, limit) again with no write to the path between
  forgotten-handover      an Agent dispatch after a `> Handover:` was written, whose prompt names no handover
  repeated-full-suite     the full suite run more than FULL_SUITE_ALLOWANCE times in one context
  observer-capture        a session filed under a claude-mem observer project
  excessive-fixed-context the first turn's context at or above --fixed-context tokens

A candidate is not a finding. Each pattern reports how many distinct sessions
carry it; the lens (`.agents/skills/sweep/references/lens-workflow.md`) decides
what may be filed.

**The cursor never moves past unread input.** `scan` reads settled sessions
after the cursor in (mtime, path) order and stops at the first bound it would
cross — the first session of a run is always read, so one oversized session
cannot wedge the cursor. It writes a report and leaves the cursor alone;
`advance` moves the cursor to the last session that report examined, and only
when the cursor has not moved since the scan. Sessions beyond a bound are
reported as unexamined with a count; a session the parser cannot read is a
named coverage gap, never a zero. Open (unsettled) sessions are not read.

Output carries no file content: anchors are `<transcript>:<line>` relative to
the root, with the home directory written `~`, a per-file sha256 digest, and a
subject scrubbed by the registry's redactor and truncated. Exit 2 with a
message on any unreadable input; `pending` exits 1 when nothing is pending.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import time
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import read_transcript as rt  # noqa: E402

sys.path.insert(0, os.path.join(HERE, "..", "..", "task-registry", "scripts"))
from registry.redaction import Redactor  # noqa: E402


def _load_incidence():
    spec = importlib.util.spec_from_file_location("read_incidence", os.path.join(HERE, "read-incidence.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module    # dataclasses resolve their module through sys.modules
    spec.loader.exec_module(module)
    return module


incidence = _load_incidence()

CURSOR_VERSION = 1
DEFAULT_MAX_SESSIONS = 50
DEFAULT_MAX_SECONDS = 1200
DEFAULT_TOKEN_BUDGET = 25_000_000
DEFAULT_SETTLE_MINUTES = 60
DEFAULT_FIXED_CONTEXT = 40_000
#: AGENTS.md § Workflow step 4: the full suite runs twice a session — the build
#: baseline and the wrap-up run. A third run in one context is the candidate.
FULL_SUITE_ALLOWANCE = 2
DEFAULT_FULL_SUITE = ("tests/run.sh",)
#: A cached-suite call reuses a green run of the same tree, so it is not a rerun.
CACHED_SUITE = "cached-suite.sh"
OBSERVER_PROJECT = "observer-sessions"
HANDOVER_MARK = "> Handover:"
WRITE_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
BYTES_PER_TOKEN = 4
ESTIMATOR = f"transcript bytes / {BYTES_PER_TOKEN} (an estimate of source size, not billed usage)"
SUBJECT_LIMIT = 120

HOME = os.path.expanduser("~")
_REDACT = Redactor([])


class CursorError(rt.TranscriptError):
    """The cursor or report cannot be used as given. `rt.run` maps it to exit 2."""


# --- display -----------------------------------------------------------------

def _encoded_home() -> str:
    """How Claude Code spells the home directory inside a project directory name."""
    return HOME.replace("\\", "/").replace("/", "-").replace(".", "-")


def display(text: str) -> str:
    """`text` with the home directory written `~` — no absolute home path leaves this tool."""
    text = text.replace(HOME, "~")
    enc = _encoded_home()
    return text.replace(enc + "-", "~-").replace(enc, "~")


def subject(use: rt.ToolUse) -> str:
    raw = " ".join(use.subject.split())
    if len(raw) > SUBJECT_LIMIT:
        raw = raw[:SUBJECT_LIMIT] + "…"
    return display(_REDACT.scrub(raw))


# --- sessions and the cursor -------------------------------------------------

@dataclass(frozen=True)
class Pending:
    session: rt.Session
    rel: str
    mtime_ns: int
    size: int

    @property
    def key(self) -> Tuple[int, str]:
        return (self.mtime_ns, self.rel)


def _stat(paths: Sequence[str]) -> Tuple[int, int]:
    stats = [os.stat(p) for p in paths]
    return max(s.st_mtime_ns for s in stats), sum(s.st_size for s in stats)


def list_after(root: str, through: Optional[Tuple[int, str]]) -> List[Pending]:
    """Every session after the cursor in (mtime, path) order; a session's mtime is its newest file's."""
    found = []
    for s in rt.iter_sessions(root):
        mtime, size = _stat([s.path, *s.subagent_paths])
        p = Pending(s, os.path.relpath(s.path, root).replace("\\", "/"), mtime, size)
        if through is None or p.key > through:
            found.append(p)
    return sorted(found, key=lambda p: p.key)


def split_settled(pending: List[Pending], settle_minutes: float, now_ns: int) -> Tuple[List[Pending], List[Pending]]:
    """(settled prefix, open rest): an mtime-ordered list's settled sessions are always a prefix."""
    boundary = now_ns - int(settle_minutes * 60 * 1e9)
    settled = [p for p in pending if p.mtime_ns <= boundary]
    return settled, pending[len(settled):]


def default_cursor(root: str) -> str:
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
    tag = hashlib.sha256(os.path.realpath(root).encode("utf-8")).hexdigest()[:8]
    return os.path.join(state, "jplugin", f"workflow-{tag}.json")


def read_cursor(path: str) -> Optional[dict]:
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except ValueError:
        raise CursorError(f"{display(path)}: cursor is not JSON — move it aside to rescan from the start")
    through = data.get("through") if isinstance(data, dict) else None
    if data.get("version") != CURSOR_VERSION or not isinstance(through, dict):
        raise CursorError(f"{display(path)}: cursor has no version-{CURSOR_VERSION} `through`")
    return data


def cursor_key(cursor: Optional[dict]) -> Optional[Tuple[int, str]]:
    return None if cursor is None else (int(cursor["through"]["mtime_ns"]), str(cursor["through"]["path"]))


def file_digest(paths: Sequence[str]) -> str:
    h = hashlib.sha256()
    for path in paths:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()[:16]


# --- candidates --------------------------------------------------------------

@dataclass
class Occurrence:
    kind: str
    signature: str
    session: str
    frame: str            # parent | subagent — never summed across
    anchor: str           # <transcript relative to root>:<line>, or @<timestamp> for a session-level event
    digest: str
    detail: str


@dataclass
class Context:
    """One context's calls: the parent's own, or one sub-agent's."""

    frame: str
    rel: str
    uses: List[rt.ToolUse]
    results: Dict[str, rt.ToolResult]
    first_context: Optional[int]
    first_timestamp: Optional[str]


def contexts_of(parsed: rt.SessionReads, root: str) -> List[Context]:
    parent = parsed.parent
    rel = lambda t: display(os.path.relpath(t.path, root).replace("\\", "/"))  # noqa: E731
    own = [u for u in parent.tool_uses if not u.sidechain]
    inline = [u for u in parent.tool_uses if u.sidechain]
    out = [Context("parent", rel(parent), own, parent.results, parent.first_context, parent.first_timestamp)]
    if inline:
        out.append(Context("subagent", rel(parent), inline, parent.results, None, None))
    for agent in parsed.agents:
        out.append(Context("subagent", rel(agent), agent.tool_uses, agent.results,
                           agent.first_context, agent.first_timestamp))
    return out


def _call_key(use: rt.ToolUse) -> str:
    return json.dumps([use.name, use.input], sort_keys=True, default=str)


def _erred(ctx: Context, use: rt.ToolUse) -> bool:
    result = ctx.results.get(use.id)
    return result is not None and result.is_error


def repeated_denied(ctx: Context) -> List[Tuple[rt.ToolUse, str]]:
    seen: Dict[str, int] = defaultdict(int)
    hits = []
    for use in ctx.uses:
        if not _erred(ctx, use):
            continue
        key = _call_key(use)
        seen[key] += 1
        if seen[key] == 2:
            hits.append((use, f"{use.name} answered with an error again: {subject(use)}"))
    return hits


def retrieval_loops(ctx: Context) -> List[Tuple[rt.ToolUse, str]]:
    seen: Dict[str, int] = defaultdict(int)
    errors: Dict[str, int] = defaultdict(int)
    hits = []
    for use in ctx.uses:
        if "retrieve" not in use.name.lower():
            continue
        key = _call_key(use)
        seen[key] += 1
        errors[key] += _erred(ctx, use)
        if seen[key] == 2:
            hits.append((use, f"{use.name} reissued with identical input ({errors[key]} errored so far)"))
    return hits


def _written_path(use: rt.ToolUse) -> Optional[str]:
    path = use.input.get("file_path") or use.input.get("notebook_path")
    return rt.normalize_path(str(path)) if use.name in WRITE_TOOLS and path else None


def duplicated_reads(ctx: Context) -> List[Tuple[rt.ToolUse, str]]:
    seen = set()
    hits = []
    for use in ctx.uses:
        written = _written_path(use)
        if written is not None:
            seen = {k for k in seen if k[0] != written}
            continue
        if use.name != "Read" or _erred(ctx, use) or not use.input.get("file_path"):
            continue
        key = (rt.normalize_path(str(use.input["file_path"])), use.input.get("offset"), use.input.get("limit"))
        if key in seen:
            hits.append((use, f"Read of {os.path.basename(key[0])} repeated with no write between"))
        seen.add(key)
    return hits


def _text_of(use: rt.ToolUse) -> str:
    return json.dumps(use.input, default=str)


def forgotten_handovers(ctx: Context) -> List[Tuple[rt.ToolUse, str]]:
    handover_written = False
    hits = []
    for use in ctx.uses:
        if use.name in WRITE_TOOLS and HANDOVER_MARK in _text_of(use):
            handover_written = True
        elif use.name == "Agent" and handover_written and "handover" not in _text_of(use).lower():
            hits.append((use, "Agent dispatched after a handover was written; its prompt names no handover"))
    return hits


def full_suite_reruns(ctx: Context, patterns: Sequence[str]) -> List[Tuple[rt.ToolUse, str]]:
    runs = 0
    hits = []
    for use in ctx.uses:
        command = str(use.input.get("command", "")) if use.name == "Bash" else ""
        if not command or CACHED_SUITE in command or not any(p in command for p in patterns):
            continue
        runs += 1
        if runs > FULL_SUITE_ALLOWANCE:
            hits.append((use, f"full suite run {runs} in one context (allowance {FULL_SUITE_ALLOWANCE})"))
    return hits


def detect(ctx: Context, session: str, digest: str, args: argparse.Namespace) -> List[Occurrence]:
    occ: List[Occurrence] = []
    per_use = (
        ("repeated-denied-call", repeated_denied(ctx)),
        ("expired-retrieval-loop", retrieval_loops(ctx)),
        ("duplicated-read", duplicated_reads(ctx)),
        ("forgotten-handover", forgotten_handovers(ctx)),
        ("repeated-full-suite", full_suite_reruns(ctx, args.full_suite)),
    )
    for kind, hits in per_use:
        for use, detail in hits:
            occ.append(Occurrence(kind, use.name, session, ctx.frame, f"{ctx.rel}:{use.line_no}", digest, detail))
    if ctx.first_context is not None and ctx.first_context >= args.fixed_context:
        occ.append(Occurrence("excessive-fixed-context", ctx.frame, session, ctx.frame,
                              f"{ctx.rel}@{ctx.first_timestamp}", digest,
                              f"first turn context {ctx.first_context} tokens (threshold {args.fixed_context})"))
    return occ


# --- the scan ----------------------------------------------------------------

@dataclass
class Report:
    root: str
    cursor_from: Optional[dict]
    cursor_to: Optional[dict]
    bounds: Dict[str, object]
    estimator: str
    examined: List[Dict[str, object]] = field(default_factory=list)
    gaps: List[Dict[str, str]] = field(default_factory=list)
    unexamined: int = 0
    unexamined_first: Optional[str] = None
    stopped_by: str = "none"
    open_skipped: int = 0
    source_digest: str = ""
    patterns: List[Dict[str, object]] = field(default_factory=list)


def _bound_hit(report: Report, p: Pending, est_tokens: int, started: float, args: argparse.Namespace) -> Optional[str]:
    if not report.examined and not report.gaps:
        return None    # the first session is always read, so one oversized session cannot wedge the cursor
    if len(report.examined) + len(report.gaps) >= args.max_sessions:
        return "max-sessions"
    if est_tokens + p.size // BYTES_PER_TOKEN > args.token_budget:
        return "token-budget"
    if time.monotonic() - started > args.max_seconds:
        return "max-seconds"
    return None


def examine(p: Pending, root: str, args: argparse.Namespace, th: rt.Thresholds) -> Tuple[Dict[str, object], List[Occurrence]]:
    files = [p.session.path, *p.session.subagent_paths]
    digest = file_digest(files)
    parsed = rt.parse_session(p.session.path, p.session.subagent_paths)
    name = display(f"{p.session.project}/{parsed.parent.session_id}" if p.session.project else parsed.parent.session_id)
    row = asdict(incidence.measure_session(p.session, th))
    row["session"] = name
    row["largest_path"] = os.path.basename(row["largest_path"].replace("\\", "/"))
    occ = [o for ctx in contexts_of(parsed, root) for o in detect(ctx, name, digest, args)]
    if OBSERVER_PROJECT in p.session.project:
        occ.append(Occurrence("observer-capture", display(p.session.project), name, "parent",
                              f"{display(p.rel)}:1", digest, "session filed under a claude-mem observer project"))
    examined = {"session": name, "path": display(p.rel), "digest": digest, "subagents": len(parsed.agents),
                "parent_tokens": parsed.parent.total_tokens,
                "subagent_tokens": sum(a.total_tokens for a in parsed.agents), "read_incidence": row}
    return examined, occ


def rank(occurrences: List[Occurrence]) -> List[Dict[str, object]]:
    groups: Dict[Tuple[str, str], List[Occurrence]] = defaultdict(list)
    for o in occurrences:
        groups[(o.kind, o.signature)].append(o)
    patterns = []
    for (kind, signature), occ in groups.items():
        sessions = {o.session for o in occ}
        patterns.append({
            "kind": kind, "signature": signature, "distinct_sessions": len(sessions),
            "meets_repeat_bar": len(sessions) >= 2,
            "parent": sum(o.frame == "parent" for o in occ),
            "subagent": sum(o.frame == "subagent" for o in occ),
            "occurrences": [asdict(o) for o in occ],
        })
    return sorted(patterns, key=lambda p: (-p["distinct_sessions"], -len(p["occurrences"]), p["kind"], p["signature"]))


def scan(args: argparse.Namespace) -> Report:
    cursor = read_cursor(args.cursor)
    pending, open_ = split_settled(list_after(args.root, cursor_key(cursor)), args.settle_minutes, time.time_ns())
    report = Report(display(args.root), cursor, None,
                    {"max_sessions": args.max_sessions, "token_budget": args.token_budget,
                     "max_seconds": args.max_seconds, "settle_minutes": args.settle_minutes},
                    ESTIMATOR, open_skipped=len(open_))
    th = rt.Thresholds()
    started, est_tokens, last = time.monotonic(), 0, None
    occurrences: List[Occurrence] = []
    for i, p in enumerate(pending):
        stop = _bound_hit(report, p, est_tokens, started, args)
        if stop:
            report.stopped_by, report.unexamined = stop, len(pending) - i
            report.unexamined_first = display(p.rel)
            break
        try:
            examined, occ = examine(p, args.root, args, th)
            report.examined.append(examined)
            occurrences.extend(occ)
        except rt.TranscriptError as exc:
            report.gaps.append({"path": display(p.rel), "reason": display(str(exc))})
        est_tokens += p.size // BYTES_PER_TOKEN
        last = p
    if last is not None:
        report.cursor_to = {"version": CURSOR_VERSION, "through": {"mtime_ns": last.mtime_ns, "path": last.rel}}
    joined = "".join(e["digest"] for e in report.examined).encode("utf-8")
    report.source_digest = hashlib.sha256(joined).hexdigest()[:16] if report.examined else ""
    report.patterns = rank(occurrences)
    return report


# --- rendering and commands --------------------------------------------------

def render(report: Report, report_path: str) -> str:
    lines = [f"# Workflow incidence over `{report.root}`", "",
             f"Examined {len(report.examined)} session(s); coverage gaps {len(report.gaps)}; "
             f"unexamined {report.unexamined} (stopped by {report.stopped_by}); "
             f"open sessions skipped {report.open_skipped}.",
             f"Source digest: {report.source_digest or 'none'} · estimator: {report.estimator}",
             f"Report: {display(report_path)} — the cursor has NOT moved; run `advance` after the record is written.",
             "", "## Patterns (ranked by distinct sessions)", ""]
    rows = [[p["kind"], p["signature"], str(p["distinct_sessions"]), "yes" if p["meets_repeat_bar"] else "no",
             str(p["parent"]), str(p["subagent"]), p["occurrences"][0]["anchor"]] for p in report.patterns]
    lines.append(rt.markdown_table(["Kind", "Signature", "Sessions", "Repeat bar", "Parent", "Sub-agent", "First anchor"],
                                   rows) if rows else "none")
    lines += ["", "## Coverage gaps", ""]
    lines += [f"- {g['path']}: {g['reason']}" for g in report.gaps] or ["none"]
    if report.unexamined:
        lines += ["", f"Unexamined from `{report.unexamined_first}` on: {report.unexamined} session(s), "
                      f"left after the cursor for the next run."]
    return "\n".join(lines)


def _write_json(path: str, data: object) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp, path)


def cmd_scan(args: argparse.Namespace) -> int:
    report = scan(args)
    _write_json(args.report, asdict(report))
    print(render(report, args.report))
    return 0


def cmd_advance(args: argparse.Namespace) -> int:
    if not os.path.exists(args.report):
        raise CursorError(f"{display(args.report)}: no scan report — run `scan` first")
    with open(args.report, encoding="utf-8") as fh:
        report = json.load(fh)
    current = read_cursor(args.cursor)
    if cursor_key(current) != cursor_key(report.get("cursor_from")):
        raise CursorError("the cursor moved since this report was scanned — rescan, never advance a stale report")
    target = report.get("cursor_to")
    if target is None:
        print("advance: the report examined nothing; the cursor stays where it is")
        return 0
    target = {**target, "source_digest": report.get("source_digest", ""),
              "examined": len(report.get("examined", [])), "gaps": report.get("gaps", []),
              "advanced_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    _write_json(args.cursor, target)
    print(f"advance: cursor through {display(target['through']['path'])}; "
          f"{report.get('unexamined', 0)} session(s) remain after it")
    return 0


def cmd_pending(args: argparse.Namespace) -> int:
    settled, _ = split_settled(list_after(args.root, cursor_key(read_cursor(args.cursor))),
                               args.settle_minutes, time.time_ns())
    print(f"pending: {len(settled)} settled session(s) after the cursor")
    return 0 if settled else 1


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("scan", "advance", "pending"):
        p = sub.add_parser(name)
        p.add_argument("--root", default=os.path.join(HOME, ".claude", "projects"))
        p.add_argument("--cursor")
        p.add_argument("--settle-minutes", type=float, default=DEFAULT_SETTLE_MINUTES)
        if name != "pending":
            p.add_argument("--report")
        if name == "scan":
            p.add_argument("--max-sessions", type=int, default=DEFAULT_MAX_SESSIONS)
            p.add_argument("--token-budget", type=int, default=DEFAULT_TOKEN_BUDGET)
            p.add_argument("--max-seconds", type=float, default=DEFAULT_MAX_SECONDS)
            p.add_argument("--fixed-context", type=int, default=DEFAULT_FIXED_CONTEXT)
            p.add_argument("--full-suite", action="append")
    args = parser.parse_args(argv)
    if not os.path.isdir(args.root):
        raise CursorError(f"{display(args.root)}: transcript root is not a directory")
    args.cursor = args.cursor or default_cursor(args.root)
    if hasattr(args, "report"):
        args.report = args.report or os.path.splitext(args.cursor)[0] + ".report.json"
    if getattr(args, "full_suite", None) is None and args.command == "scan":
        args.full_suite = list(DEFAULT_FULL_SUITE)
    return {"scan": cmd_scan, "advance": cmd_advance, "pending": cmd_pending}[args.command](args)


if __name__ == "__main__":
    sys.exit(rt.run(main))
