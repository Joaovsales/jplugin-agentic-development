#!/usr/bin/env python3
"""workflow-incidence.py — the `workflow` producer's engine: rank agent-workflow
waste and unreliability over this repository's completed sessions, bounded by a cursor.

    workflow-incidence.py scan    [--repo DIR] [--root DIR] [--cursor FILE] [--report FILE]
                                  [--max-sessions 50] [--token-budget N] [--max-session-tokens N]
                                  [--max-seconds 1200] [--settle-minutes 60]
                                  [--fixed-context N] [--full-suite TEXT ...]
    workflow-incidence.py advance [--repo DIR] [--root DIR] [--cursor FILE] [--report FILE]
    workflow-incidence.py pending [--repo DIR] [--root DIR] [--cursor FILE] [--settle-minutes 60]

The template ships this engine; each user runs it on their own machine over
their own sessions, and the routine files what it proves into the project's
tracker for later analysis. So two things are fixed here rather than left to
the agent running it:

* **Scope — this repository's sessions only.** A session is in scope when the
  working directory it ran in belongs to the repository at `--repo`: inside one
  of its live worktrees, a live directory whose git common directory is the
  repository's, or — for a worktree since deleted — under a directory that
  holds only this repository's worktrees. Every other session (another project,
  claude-mem's observer, a working directory that cannot be attributed) is
  counted and never read.
* **Evidence — nothing that names the machine.** Anchors are
  `<session-id>[/<agent-id>]:<line>`, never a project directory; a subject has
  the session's working directory written `.`, the home directory `~`, and
  credentials scrubbed by the registry's redactor. The owner reopens an anchor
  locally with `find ~/.claude/projects -name '<session-id>.jsonl'`.

It is not a transcript collector. Every session is read through
`read_transcript.py` (the one reader of the on-disk JSONL) and measured with
`read-incidence.py`'s `measure_session`; this file only ranks what they return
(specs/claude-mem-retention.md § Proposed routine: workflow producer).

Six candidate kinds, each counted per context — a parent's own calls and each
sub-agent's calls are separate contexts and never summed together:

  repeated-denied-call    one identical call answered with an error twice or more
  expired-retrieval-loop  one identical retrieval call (`*retrieve*`) issued twice or more
  duplicated-read         the same Read (path, offset, limit) again with no write to the path between
  forgotten-handover      an Agent dispatch after a `> Handover:` was written, whose prompt names no handover
  repeated-full-suite     the project's declared full suite run more than FULL_SUITE_ALLOWANCE times in one context
  excessive-fixed-context the first turn's context at or above --fixed-context tokens

The full suite is the project's own `Full suite: <command>` line in AGENTS.md or
CLAUDE.md (`--full-suite` overrides it); with neither, that detector is off and
the report says so. A run narrowed to named files, or text that merely mentions
the command, is not a full-suite run.

A candidate is not a finding; the lens
(`.agents/skills/sweep/references/lens-workflow.md`) decides what may be filed.

**The cursor never moves past unread input.** `scan` reads settled in-scope
sessions after the cursor in (mtime, path) order and stops at the first bound
it would cross — the first session of a run is always read. One session is
charged at most `--max-session-tokens` against the budget, so an outsized
session is still read but cannot spend a run on its own. `scan` writes a report
and leaves the cursor alone; `advance` moves it to the last session that report
examined, only when the cursor has not moved since. The cursor belongs to one
(root, repository) scope and refuses another. Sessions beyond a bound are
reported as unexamined; a session the parser cannot read is a coverage gap,
never a zero; an open session is not read. Exit 2 with a message on unreadable
input; `pending` exits 1 when nothing is pending.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
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

CURSOR_VERSION = 2
DEFAULT_MAX_SESSIONS = 50
DEFAULT_MAX_SECONDS = 1200
DEFAULT_TOKEN_BUDGET = 25_000_000
DEFAULT_MAX_SESSION_TOKENS = 1_000_000
DEFAULT_SETTLE_MINUTES = 60
DEFAULT_FIXED_CONTEXT = 40_000
#: AGENTS.md § Workflow step 4: the full suite runs twice a session — the build
#: baseline and the wrap-up run. A third run in one context is the candidate.
FULL_SUITE_ALLOWANCE = 2
FULL_SUITE_FILES = ("AGENTS.md", "CLAUDE.md")
FULL_SUITE_LINE = re.compile(r"^Full suite:\s*(.+?)\s*$", re.MULTILINE)
HANDOVER_MARK = "> Handover:"
WRITE_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
BYTES_PER_TOKEN = 4
ESTIMATOR = f"transcript bytes / {BYTES_PER_TOKEN} (an estimate of source size, not billed usage)"
SUBJECT_LIMIT = 120

HOME = os.path.expanduser("~")
_REDACT = Redactor([])


class CursorError(rt.TranscriptError):
    """The cursor, report or repository cannot be used as given. `rt.run` maps it to exit 2."""


# --- display -----------------------------------------------------------------

def _encoded_home() -> str:
    """How Claude Code spells the home directory inside a project directory name."""
    return HOME.replace("\\", "/").replace("/", "-").replace(".", "-")


def display(text: str) -> str:
    """`text` with the home directory written `~` — no absolute home path leaves this tool."""
    text = text.replace(HOME, "~")
    enc = _encoded_home()
    return text.replace(enc + "-", "~-").replace(enc, "~")


def subject(use: rt.ToolUse, cwd: Optional[str]) -> str:
    raw = " ".join(use.subject.split())
    if cwd:
        raw = raw.replace(cwd.rstrip("/\\"), ".")
    if len(raw) > SUBJECT_LIMIT:
        raw = raw[:SUBJECT_LIMIT] + "…"
    return display(_REDACT.scrub(raw))


# --- scope: which sessions belong to this repository -------------------------

def _norm(path: str) -> str:
    return os.path.normcase(os.path.realpath(path))


def _under(path: str, root: str) -> bool:
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def _git(directory: str, *args: str) -> Optional[str]:
    try:
        done = subprocess.run(["git", "-C", directory, *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def _common_dir(directory: str) -> Optional[str]:
    out = _git(directory, "rev-parse", "--git-common-dir")
    return None if not out else _norm(os.path.join(directory, out))


class ProjectScope:
    """Decides whether a session's working directory belongs to one repository.

    `owns` answers True, False, or None when the directory is gone and nothing
    still standing attributes it — a deleted worktree outside any directory that
    holds only this repository's worktrees."""

    def __init__(self, repo: str) -> None:
        common = _common_dir(repo)
        if common is None:
            raise CursorError(f"{display(os.path.abspath(repo))}: not inside a git repository")
        self.common = common
        listing = _git(repo, "worktree", "list", "--porcelain") or ""
        self.worktrees = [_norm(line[len("worktree "):]) for line in listing.splitlines()
                          if line.startswith("worktree ")]
        self.parents = self._dedicated_parents()
        self.tag = hashlib.sha256(common.encode("utf-8")).hexdigest()[:8]
        self._live: Dict[str, bool] = {}

    def _dedicated_parents(self) -> List[str]:
        """Directories that hold a linked worktree of ours and no other repository's checkout."""
        main = self.worktrees[0] if self.worktrees else ""
        home = _norm(HOME)
        found = []
        for parent in {os.path.dirname(w) for w in self.worktrees[1:]}:
            if parent in (home, os.path.dirname(parent)) or _under(main, parent) or not os.path.isdir(parent):
                continue
            children = [os.path.join(parent, c) for c in os.listdir(parent)]
            checkouts = [c for c in children if os.path.exists(os.path.join(c, ".git"))]
            if all(self._is_ours(c) for c in checkouts):
                found.append(parent)
        return found

    def _is_ours(self, checkout: str) -> bool:
        """A checkout sharing our git directory — or a worktree whose registration
        was pruned but whose `.git` file still points into our git directory."""
        if _common_dir(checkout) == self.common:
            return True
        marker = os.path.join(checkout, ".git")
        if not os.path.isfile(marker):
            return False
        with open(marker, encoding="utf-8", errors="replace") as fh:
            line = fh.readline().strip()
        return line.startswith("gitdir:") and _under(_norm(line[len("gitdir:"):].strip()), self.common)

    def owns(self, cwd: Optional[str]) -> Optional[bool]:
        if not cwd:
            return None
        path = _norm(cwd)
        if any(_under(path, w) for w in self.worktrees):
            return True
        if os.path.isdir(path):
            if path not in self._live:
                self._live[path] = _common_dir(path) == self.common
            return self._live[path]
        return True if any(_under(path, p) for p in self.parents) else None


# --- sessions and the cursor -------------------------------------------------

@dataclass(frozen=True)
class Pending:
    session: rt.Session
    rel: str
    mtime_ns: int
    size: int
    cwd: Optional[str]

    @property
    def tiebreak(self) -> str:
        """Orders sessions of one mtime without the cursor storing a project directory."""
        return hashlib.sha256(self.rel.encode("utf-8")).hexdigest()[:16]

    @property
    def key(self) -> Tuple[int, str]:
        return (self.mtime_ns, self.tiebreak)

    @property
    def sid(self) -> str:
        return rt.session_id(self.session.path)


@dataclass
class Listing:
    pending: List[Pending]     # in scope, after the cursor, oldest first
    out_of_scope: int          # another project's, or claude-mem observer sessions
    unattributable: int        # no working directory, or one that no longer exists and nothing attributes


def _stat(paths: Sequence[str]) -> Tuple[int, int]:
    stats = [os.stat(p) for p in paths]
    return max(s.st_mtime_ns for s in stats), sum(s.st_size for s in stats)


def list_after(root: str, through: Optional[Tuple[int, str]], scope: ProjectScope) -> Listing:
    """This repository's sessions after the cursor in (mtime, path) order; a session's mtime is its newest file's."""
    listing = Listing([], 0, 0)
    for s in rt.iter_sessions(root):
        mtime, size = _stat([s.path, *s.subagent_paths])
        p = Pending(s, os.path.relpath(s.path, root).replace("\\", "/"), mtime, size, None)
        if through is not None and p.key <= through:
            continue
        cwd = rt.session_cwd(s.path)
        owned = scope.owns(cwd)
        if owned is None:
            listing.unattributable += 1
        elif not owned:
            listing.out_of_scope += 1
        else:
            listing.pending.append(Pending(s, p.rel, mtime, size, cwd))
    listing.pending.sort(key=lambda p: p.key)
    return listing


def split_settled(pending: List[Pending], settle_minutes: float, now_ns: int) -> Tuple[List[Pending], List[Pending]]:
    """(settled prefix, open rest): an mtime-ordered list's settled sessions are always a prefix."""
    boundary = now_ns - int(settle_minutes * 60 * 1e9)
    settled = [p for p in pending if p.mtime_ns <= boundary]
    return settled, pending[len(settled):]


def scope_tag(root: str, scope: ProjectScope) -> str:
    return hashlib.sha256(f"{os.path.realpath(root)}\n{scope.common}".encode("utf-8")).hexdigest()[:8]


def default_cursor(root: str, scope: ProjectScope) -> str:
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
    return os.path.join(state, "jplugin", f"workflow-{scope_tag(root, scope)}.json")


def read_cursor(path: str, tag: str) -> Optional[dict]:
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except ValueError:
        raise CursorError(f"{display(path)}: cursor is not JSON — move it aside to rescan from the start")
    through = data.get("through") if isinstance(data, dict) else None
    if not isinstance(through, dict) or data.get("version") != CURSOR_VERSION:
        raise CursorError(f"{display(path)}: cursor has no version-{CURSOR_VERSION} `through` — "
                          "move it aside to rescan from the start")
    if data.get("scope") != tag:
        raise CursorError(f"{display(path)}: cursor belongs to another transcript root or repository")
    return data


def cursor_key(cursor: Optional[dict]) -> Optional[Tuple[int, str]]:
    return None if cursor is None else (int(cursor["through"]["mtime_ns"]), str(cursor["through"]["tiebreak"]))


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
    anchor: str           # <session-id>[/<agent-id>]:<line>, or …@<timestamp> for a session-level event
    digest: str
    detail: str


@dataclass
class Context:
    """One context's calls: the parent's own, or one sub-agent's."""

    frame: str
    label: str
    uses: List[rt.ToolUse]
    results: Dict[str, rt.ToolResult]
    first_context: Optional[int]
    first_timestamp: Optional[str]
    cwd: Optional[str]


def contexts_of(parsed: rt.SessionReads, cwd: Optional[str]) -> List[Context]:
    parent = parsed.parent
    sid = parent.session_id
    own = [u for u in parent.tool_uses if not u.sidechain]
    inline = [u for u in parent.tool_uses if u.sidechain]
    out = [Context("parent", sid, own, parent.results, parent.first_context, parent.first_timestamp, cwd)]
    if inline:
        out.append(Context("subagent", sid, inline, parent.results, None, None, cwd))
    for agent in parsed.agents:
        out.append(Context("subagent", f"{sid}/{agent.session_id}", agent.tool_uses, agent.results,
                           agent.first_context, agent.first_timestamp, cwd))
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
            hits.append((use, f"{use.name} answered with an error again: {subject(use, ctx.cwd)}"))
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


def declared_full_suite(repo: str) -> List[str]:
    """The project's `Full suite: <command>` line(s) from AGENTS.md or CLAUDE.md at the repository top."""
    top = _git(repo, "rev-parse", "--show-toplevel") or repo
    for name in FULL_SUITE_FILES:
        path = os.path.join(top, name)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                found = FULL_SUITE_LINE.findall(fh.read())
            if found:
                return found
    return []


def full_suite_reruns(ctx: Context, commands: Sequence[str]) -> List[Tuple[rt.ToolUse, str]]:
    runs = 0
    hits = []
    for use in ctx.uses:
        command = str(use.input.get("command", "")) if use.name == "Bash" else ""
        if not command or not any(rt.runs_command(command, c) for c in commands):
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
            occ.append(Occurrence(kind, use.name, session, ctx.frame, f"{ctx.label}:{use.line_no}", digest, detail))
    if ctx.first_context is not None and ctx.first_context >= args.fixed_context:
        occ.append(Occurrence("excessive-fixed-context", ctx.frame, session, ctx.frame,
                              f"{ctx.label}@{ctx.first_timestamp}", digest,
                              f"first turn context {ctx.first_context} tokens (threshold {args.fixed_context})"))
    return occ


# --- the scan ----------------------------------------------------------------

@dataclass
class Report:
    root: str
    scope: str
    cursor_from: Optional[dict]
    cursor_to: Optional[dict]
    bounds: Dict[str, object]
    estimator: str
    examined: List[Dict[str, object]] = field(default_factory=list)
    gaps: List[Dict[str, str]] = field(default_factory=list)
    oversized: List[str] = field(default_factory=list)
    unexamined: int = 0
    unexamined_first: Optional[str] = None
    stopped_by: str = "none"
    open_skipped: int = 0
    out_of_scope: int = 0
    unattributable: int = 0
    full_suite: List[str] = field(default_factory=list)
    source_digest: str = ""
    patterns: List[Dict[str, object]] = field(default_factory=list)


def _charge(p: Pending, args: argparse.Namespace) -> int:
    """What one session costs against the token budget: its estimate, at most --max-session-tokens."""
    return min(p.size // BYTES_PER_TOKEN, args.max_session_tokens)


def _bound_hit(report: Report, p: Pending, spent: int, started: float, args: argparse.Namespace) -> Optional[str]:
    if not report.examined and not report.gaps:
        return None    # the first session is always read, so one session cannot wedge the cursor
    if len(report.examined) + len(report.gaps) >= args.max_sessions:
        return "max-sessions"
    if spent + _charge(p, args) > args.token_budget:
        return "token-budget"
    if time.monotonic() - started > args.max_seconds:
        return "max-seconds"
    return None


def examine(p: Pending, args: argparse.Namespace, th: rt.Thresholds) -> Tuple[Dict[str, object], List[Occurrence]]:
    digest = file_digest([p.session.path, *p.session.subagent_paths])
    parsed = rt.parse_session(p.session.path, p.session.subagent_paths)
    row = asdict(incidence.measure_session(p.session, th))
    row["session"] = p.sid
    row["largest_path"] = os.path.basename(row["largest_path"].replace("\\", "/"))
    occ = [o for ctx in contexts_of(parsed, p.cwd) for o in detect(ctx, p.sid, digest, args)]
    examined = {"session": p.sid, "digest": digest, "subagents": len(parsed.agents),
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
    cursor = read_cursor(args.cursor, args.tag)
    listing = list_after(args.root, cursor_key(cursor), args.scope)
    pending, open_ = split_settled(listing.pending, args.settle_minutes, time.time_ns())
    report = Report(display(args.root), args.tag, cursor, None,
                    {"max_sessions": args.max_sessions, "token_budget": args.token_budget,
                     "max_session_tokens": args.max_session_tokens, "max_seconds": args.max_seconds,
                     "settle_minutes": args.settle_minutes},
                    ESTIMATOR, open_skipped=len(open_), out_of_scope=listing.out_of_scope,
                    unattributable=listing.unattributable, full_suite=list(args.full_suite))
    th = rt.Thresholds()
    started, spent, last = time.monotonic(), 0, None
    occurrences: List[Occurrence] = []
    for i, p in enumerate(pending):
        stop = _bound_hit(report, p, spent, started, args)
        if stop:
            report.stopped_by, report.unexamined, report.unexamined_first = stop, len(pending) - i, p.sid
            break
        try:
            examined, occ = examine(p, args, th)
            report.examined.append(examined)
            occurrences.extend(occ)
        except rt.TranscriptError as exc:
            reason = str(exc).replace(os.path.dirname(p.session.path), "<project>")
            report.gaps.append({"session": p.sid, "reason": display(reason)})
        if p.size // BYTES_PER_TOKEN > args.max_session_tokens:
            report.oversized.append(p.sid)
        spent += _charge(p, args)
        last = p
    if last is not None:
        report.cursor_to = {"version": CURSOR_VERSION, "scope": args.tag,
                            "through": {"mtime_ns": last.mtime_ns, "tiebreak": last.tiebreak, "session": last.sid}}
    joined = "".join(e["digest"] for e in report.examined).encode("utf-8")
    report.source_digest = hashlib.sha256(joined).hexdigest()[:16] if report.examined else ""
    report.patterns = rank(occurrences)
    return report


# --- rendering and commands --------------------------------------------------

def render(report: Report, report_path: str) -> str:
    lines = [f"# Workflow incidence over `{report.root}` — this repository's sessions", "",
             f"Examined {len(report.examined)} session(s); coverage gaps {len(report.gaps)}; "
             f"unexamined {report.unexamined} (stopped by {report.stopped_by}); "
             f"open sessions skipped {report.open_skipped}.",
             f"Out of scope {report.out_of_scope} (other projects, observer sessions); "
             f"unattributable {report.unattributable} (no working directory, or one since deleted); "
             f"oversized, charged at the cap {len(report.oversized)}.",
             "Full suite: " + (" | ".join(f"`{c}`" for c in report.full_suite) if report.full_suite else
                               "detector off — no `Full suite:` line in AGENTS.md or CLAUDE.md"),
             f"Source digest: {report.source_digest or 'none'} · estimator: {report.estimator}",
             f"Report: {display(report_path)} — the cursor has NOT moved; run `advance` after the record is written.",
             "", "## Patterns (ranked by distinct sessions)", ""]
    rows = [[p["kind"], p["signature"], str(p["distinct_sessions"]), "yes" if p["meets_repeat_bar"] else "no",
             str(p["parent"]), str(p["subagent"]), p["occurrences"][0]["anchor"]] for p in report.patterns]
    lines.append(rt.markdown_table(["Kind", "Signature", "Sessions", "Repeat bar", "Parent", "Sub-agent", "First anchor"],
                                   rows) if rows else "none")
    lines += ["", "## Coverage gaps", ""]
    lines += [f"- {g['session']}: {g['reason']}" for g in report.gaps] or ["none"]
    if report.unexamined:
        lines += ["", f"Unexamined from session `{report.unexamined_first}` on: {report.unexamined} session(s), "
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
    if report.get("scope") != args.tag:
        raise CursorError("the report was scanned for another transcript root or repository — rescan")
    current = read_cursor(args.cursor, args.tag)
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
    print(f"advance: cursor through session {target['through']['session']}; "
          f"{report.get('unexamined', 0)} session(s) remain after it")
    return 0


def cmd_pending(args: argparse.Namespace) -> int:
    listing = list_after(args.root, cursor_key(read_cursor(args.cursor, args.tag)), args.scope)
    settled, _ = split_settled(listing.pending, args.settle_minutes, time.time_ns())
    print(f"pending: {len(settled)} settled session(s) of this repository after the cursor")
    return 0 if settled else 1


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("scan", "advance", "pending"):
        p = sub.add_parser(name)
        p.add_argument("--repo", default=".", help="the repository whose sessions are in scope")
        p.add_argument("--root", default=os.path.join(HOME, ".claude", "projects"))
        p.add_argument("--cursor")
        p.add_argument("--settle-minutes", type=float, default=DEFAULT_SETTLE_MINUTES)
        if name != "pending":
            p.add_argument("--report")
        if name == "scan":
            p.add_argument("--max-sessions", type=int, default=DEFAULT_MAX_SESSIONS)
            p.add_argument("--token-budget", type=int, default=DEFAULT_TOKEN_BUDGET)
            p.add_argument("--max-session-tokens", type=int, default=DEFAULT_MAX_SESSION_TOKENS)
            p.add_argument("--max-seconds", type=float, default=DEFAULT_MAX_SECONDS)
            p.add_argument("--fixed-context", type=int, default=DEFAULT_FIXED_CONTEXT)
            p.add_argument("--full-suite", action="append")
    args = parser.parse_args(argv)
    if not os.path.isdir(args.root):
        raise CursorError(f"{display(args.root)}: transcript root is not a directory")
    args.scope = ProjectScope(args.repo)
    args.tag = scope_tag(args.root, args.scope)
    args.cursor = args.cursor or default_cursor(args.root, args.scope)
    if hasattr(args, "report"):
        args.report = args.report or os.path.splitext(args.cursor)[0] + ".report.json"
    if args.command == "scan" and args.full_suite is None:
        args.full_suite = declared_full_suite(args.repo)
    return {"scan": cmd_scan, "advance": cmd_advance, "pending": cmd_pending}[args.command](args)


if __name__ == "__main__":
    sys.exit(rt.run(main))
