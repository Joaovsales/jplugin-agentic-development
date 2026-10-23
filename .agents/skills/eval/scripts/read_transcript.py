#!/usr/bin/env python3
"""read_transcript.py — the one reader of Claude Code's on-disk session JSONL.

`read-incidence.py` (the baseline over a transcript root) and
`grade-read-shunt.py` (per-run metrics over an eval results directory) both
measure what the parent agent pulled into its context. Everything either of
them knows about the JSONL shape lives here, so a format change is pinned in
one place (specs/read-shunt-baseline.md § Decisions, row 12).

Shape, as observed on Claude Code 2.1.306 and pinned by
tests/fixtures/transcripts/:

  <root>/<project>/<session>.jsonl                      the main loop
  <root>/<project>/<session>/subagents/agent-<id>.jsonl  one per sub-agent

A `shunt.jsonl` gate log beside a transcript is not a session; `iter_sessions`
skips it by the name `SHUNT_LOG`. The log's shape — one `{decision, tool,
input}` object per line — is read here too (`read_shunt_log`, `ShuntDecision`),
and `find_shunt_log` locates the one the gate's hook writes under the project
it ran in, `tasks/.shunt/<session>.jsonl` (specs/read-shunt.md § Tier 0), so a
kept eval home's log can be arranged beside its transcript.

One JSON object per line. An `assistant` record carries `message.content`
(a list of blocks; a `tool_use` block has `id`, `name`, `input`) and
`message.usage`; a `user` record carries `tool_result` blocks and, beside the
message, `toolUseResult` — the tool's structured result. A `Read` of a text
file puts `{"type": "text", "file": {filePath, content, numLines, startLine,
totalLines[, truncatedByTokenCap]}}` there; an image, PDF, notebook or an
unchanged file has another `type`; an error is a bare string; older
transcripts have no `toolUseResult` at all and the block's numbered text is
the only record. A sub-agent's
lines carry `isSidechain: true` and `agentId`; older transcripts put such
lines inline in the parent's file. A `system` record with `subtype:
compact_boundary` marks a compaction. A `Bash` use carries `input.command`, a
`Grep` use `input.path`, `-C` and `head_limit`; an `Agent` use carries
`input.prompt` and its `toolUseResult` is `{status, content, totalTokens,
totalToolUseCount, ...}` once completed — an async launch has `status:
async_launched` and no counters.

The results layout the eval CLIs share (`TRANSCRIPT_FILE`, `OUTCOME_FILE`,
`subagent_transcripts`, `write_outcome`, `read_outcome`) lives here too, so the
writer and the reader of a results directory cannot name or validate it apart.

Everything streams: one line is parsed at a time, a tool use is classified
the moment its result arrives (a result logged before its use is held until the
use arrives), and only the classification and the result's size are kept — a Read's file content is
dropped with its line — so an 800 MB root is a few minutes, not a few
gigabytes, and a session costs its line count, not its read volume.

A block this module cannot read raises `TranscriptDrift` with the file and
line; a root with no transcripts raises `EmptyRoot`. Both are
`TranscriptError`, which `run()` turns into exit 2 with the message on
stderr — never a silent zero, because a zero here reads as "the parent never
bulk-reads" and decides whether a gate is built.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
import re
from typing import Callable, Dict, List, Optional, Sequence, Set, Tuple, Union

DEFAULT_BYTES = 32768
DEFAULT_LINES = 800
SUBAGENTS_DIR = "subagents"
# The gate's decision log, written beside a transcript; it is JSONL but not a session.
SHUNT_LOG = "shunt.jsonl"
# Where the gate's hook writes a session's log, under the project it ran in
# (specs/read-shunt.md § Tier 0): <project>/tasks/.shunt/<session>.jsonl.
SHUNT_SOURCE_DIR = os.path.join("tasks", ".shunt")
# The runner-neutral results layout `arrange-plugin-eval-results.py` writes and
# `grade-read-shunt.py` reads: <results>/<arm>/<task>/<run>/{TRANSCRIPT_FILE,
# SUBAGENTS_DIR/agent-*.jsonl, SHUNT_LOG, OUTCOME_FILE}.
TRANSCRIPT_FILE = "transcript.jsonl"
OUTCOME_FILE = "outcome.json"

# `toolUseResult.type` values that are not text and therefore not a read into
# the parent's context. Anything else that is not `text` is drift, not a new
# kind of nothing.
EXCLUDED_RESULT_TYPES = frozenset({"image", "pdf", "notebook", "file_unchanged", "directory"})
_TEXT_FILE_KEYS = ("content", "numLines", "startLine", "totalLines")
# The tool uses `_classify` keeps a call for; any other use is only counted.
CLASSIFIED_TOOLS = ("Read", "Bash", "Grep", "Agent")


class TranscriptError(Exception):
    """A measurement that cannot be made. `run()` maps it to exit 2."""

    exit_code = 2


class EmptyRoot(TranscriptError):
    def __init__(self, root: str) -> None:
        super().__init__(f"no session transcripts under {root}")
        self.root = root


class TranscriptDrift(TranscriptError):
    def __init__(self, path: str, line_no: int, what: str) -> None:
        super().__init__(f"{path}:{line_no}: {what} — transcript format changed")
        self.path = path
        self.line_no = line_no


@dataclass
class ToolUse:
    id: str
    name: str
    input: dict
    line_no: int
    timestamp: Optional[str]
    sidechain: bool

    @property
    def subject(self) -> str:
        """What the call was about: its file, else its command, else its tool name."""
        return str(self.input.get("file_path") or self.input.get("command") or self.name)


@dataclass
class ToolResult:
    """What a transcript keeps of a tool_result block: its size and whether it erred."""

    tool_use_id: str
    bytes: int                 # text bytes of the tool_result block — what entered the context
    is_error: bool
    line_no: int


@dataclass
class RawResult:
    """One tool_result block with the record's `toolUseResult`, alive only while
    the use it answers is classified; `kept()` is what the transcript retains."""

    tool_use_id: str
    text: str                  # the block's text
    structured: object         # the record's `toolUseResult`, or None
    is_error: bool
    line_no: int
    bytes: int = field(init=False)

    def __post_init__(self) -> None:
        self.bytes = len(self.text.encode("utf-8"))

    def kept(self) -> ToolResult:
        return ToolResult(self.tool_use_id, self.bytes, self.is_error, self.line_no)


@dataclass(frozen=True)
class ShuntDecision:
    """One line of the gate's log: what it decided about one tool input."""

    decision: str              # the hook's word — allow, annotate, deny — counted as written
    tool: Optional[str]
    input: object
    line_no: int

    @property
    def denied(self) -> bool:
        return self.decision == "deny"

    @property
    def input_key(self) -> str:
        """One spelling for (tool, input), so two denials of the same call compare equal."""
        return json.dumps([self.tool, self.input], sort_keys=True)


@dataclass(frozen=True)
class Thresholds:
    """When a read is large: at `bytes` or `lines` (specs/read-shunt-baseline.md D3)."""

    bytes: int = DEFAULT_BYTES
    lines: int = DEFAULT_LINES


@dataclass
class Read:
    """One `Read` tool use, classified from its input and its result."""

    tool_use: ToolUse
    path: str
    kind: str                  # whole | ranged | excluded
    truncated: bool
    bytes: int                 # UTF-8 bytes of the tool_result block the parent received
    total_lines: int

    @property
    def norm_path(self) -> str:
        return normalize_path(self.path)

    @property
    def is_whole(self) -> bool:
        return self.kind == "whole"

    @property
    def is_excluded(self) -> bool:
        return self.kind == "excluded"

    def is_large(self, th: Thresholds = Thresholds()) -> bool:
        if self.is_excluded:
            return False
        return self.bytes >= th.bytes or self.total_lines >= th.lines

    def is_whole_large(self, th: Thresholds = Thresholds()) -> bool:
        return self.is_whole and self.is_large(th)


@dataclass
class ShellRead:
    """A parent `Bash` use that printed whole files into the context (`bare_shell_reads`)."""

    tool_use: ToolUse
    paths: Tuple[str, ...]     # normalized, one per file
    bytes: int                 # UTF-8 bytes of the result block, shared by the command's files


@dataclass
class GrepCall:
    """A parent `Grep` use: where it looked, how much context it asked for, what came back."""

    tool_use: ToolUse
    target: str                # normalized `path` input, "" when it searched the working directory
    context_lines: Optional[int]   # `-C`
    head_limit: Optional[int]
    bytes: Optional[int]       # result block bytes; None when the call went unanswered


@dataclass
class AgentCall:
    """A parent `Agent` use: the text that named paths and the sub-agent's own counters."""

    tool_use: ToolUse
    named_text: str            # the prompt, then the result's text
    total_tokens: Optional[int]
    tool_use_count: Optional[int]
    agent_id: Optional[str]    # `toolUseResult.agentId`; `subagent_session_id` names its file


Call = Union[Read, ShellRead, GrepCall, AgentCall]


@dataclass
class Transcript:
    path: str
    session_id: str
    is_subagent: bool
    tool_uses: List[ToolUse] = field(default_factory=list)
    results: Dict[str, ToolResult] = field(default_factory=dict)
    malformed: int = 0
    compactions: int = 0
    final_context: Optional[int] = None
    first_timestamp: Optional[str] = None
    last_timestamp: Optional[str] = None
    total_tokens: int = 0      # the usage of this file's own turns summed, one count per API message
    _uses_by_id: Dict[str, ToolUse] = field(default_factory=dict, init=False, repr=False)
    _pending: Dict[str, RawResult] = field(default_factory=dict, init=False, repr=False)
    _calls: Dict[str, Call] = field(default_factory=dict, init=False, repr=False)
    _message_ids: Set[str] = field(default_factory=set, init=False, repr=False)
    _reads: Tuple[Read, ...] = field(default=(), init=False, repr=False)
    _shell_reads: Tuple[ShellRead, ...] = field(default=(), init=False, repr=False)
    _grep_calls: Tuple[GrepCall, ...] = field(default=(), init=False, repr=False)
    _agent_calls: Tuple[AgentCall, ...] = field(default=(), init=False, repr=False)
    _own_calls: Tuple[Call, ...] = field(default=(), init=False, repr=False)
    _largest_own_result: Tuple[int, str] = field(default=(0, ""), init=False, repr=False)

    def _tool_uses_named(self, name: str) -> List[ToolUse]:
        return [t for t in self.tool_uses if t.name == name]

    # Two frames of reference. The *file frame* (`own_*`) asks what this file's
    # own context did: a parent file's uses minus an inline sidechain's, all of
    # a `subagents/` file's. The *session frame* (`ToolUse.sidechain`,
    # `subagent_*`) asks which context of the session made a call: a
    # sub-agent's, inline or in its own file. On a `subagents/` file the two
    # coincide; `SessionReads.counted_subagent_reads` is the session frame across files.

    def own_tool_uses(self) -> List[ToolUse]:
        """File frame: the tool uses of this file's own context."""
        return [t for t in self.tool_uses if self._is_own(t)]

    def _is_own(self, use: ToolUse) -> bool:
        return self.is_subagent or not use.sidechain

    def reads(self) -> Tuple[Read, ...]:
        """Every Read in the file, whichever context made it, in call order."""
        return self._reads

    def own_reads(self) -> List[Read]:
        """File frame: the Reads of this file's own context."""
        return [r for r in self._reads if self._is_own(r.tool_use)]

    def subagent_reads(self) -> List[Read]:
        """Session frame: the Reads a sub-agent made — inline in a parent file, or all of a `subagents/` file's."""
        return [r for r in self._reads if r.tool_use.sidechain]

    def counted_subagent_reads(self) -> List[Read]:
        """The sub-agent reads whose file text entered a context — every one but the excluded."""
        return [r for r in self.subagent_reads() if not r.is_excluded]

    def own_calls(self) -> Tuple[Call, ...]:
        """This file's own Read, shell-read, Grep and Agent calls in call order."""
        return self._own_calls

    def shell_reads(self) -> Tuple[ShellRead, ...]:
        """The parent's `Bash` uses that printed whole files, in call order."""
        return self._shell_reads

    def grep_calls(self) -> Tuple[GrepCall, ...]:
        return self._grep_calls

    def agent_calls(self) -> Tuple[AgentCall, ...]:
        return self._agent_calls

    def own_result_bytes(self) -> int:
        """The bytes the results of this file's own tool uses put into its context."""
        return sum(self.results[u.id].bytes for u in self.own_tool_uses() if u.id in self.results)

    def largest_own_result(self) -> Tuple[int, str]:
        """(bytes, subject) of the biggest result an own tool use received; (0, "") when none."""
        return self._largest_own_result


@dataclass
class Session:
    path: str
    project: str
    subagent_paths: List[str]


@dataclass
class SessionReads:
    """A session assembled from its main-loop transcript and its sub-agent files."""

    parent: Transcript
    agents: List[Transcript]
    counted_subagent_reads: List[Read]     # session frame: the parent's inline ones and every agent's, excluded dropped
    malformed: int                 # unreadable lines, summed over every file

    def subagent_totals(self) -> Tuple[Optional[int], Optional[int]]:
        """(tokens, tool uses) of the session's sub-agents, summed per Agent call:
        the call's own counters when it carries both, else the transcript its
        `agentId` names (`total_tokens`, own tool uses), else unknown. A column
        is None when any call is unknown; no Agent call is a true (0, 0)."""
        by_session = {a.session_id: a for a in self.agents}
        tokens: Optional[int] = 0
        uses: Optional[int] = 0
        for call in self.parent.agent_calls():
            if call.total_tokens is not None and call.tool_use_count is not None:
                call_tokens, call_uses = call.total_tokens, call.tool_use_count
            else:
                agent = by_session.get(subagent_session_id(call.agent_id)) if call.agent_id else None
                if agent is None:
                    return None, None
                call_tokens, call_uses = agent.total_tokens, len(agent.own_tool_uses())
            tokens, uses = tokens + call_tokens, uses + call_uses
        return tokens, uses


def normalize_path(path: str) -> str:
    """One spelling for a path the model may have written either way on Windows."""
    p = path.replace("\\", "/")
    while "//" in p:
        p = p.replace("//", "/")
    return p.rstrip("/").casefold()


def iter_sessions(root: str) -> List[Session]:
    """Every main-loop transcript under `root`, each with its sub-agent files."""
    sessions: List[Session] = []
    for dirpath, dirnames, filenames in os.walk(root):
        if SUBAGENTS_DIR in dirnames:
            dirnames.remove(SUBAGENTS_DIR)
        dirnames.sort()    # os.walk descends in listing order, which Linux leaves unsorted
        for name in sorted(filenames):
            if not name.endswith(".jsonl") or name == SHUNT_LOG:
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(dirpath, root)
            project = rel.replace("\\", "/").split("/")[0] if rel != "." else ""
            sessions.append(Session(path, project, _agent_files(session_subagents_dir(path))))
    if not sessions:
        raise EmptyRoot(root)
    return sessions


def session_id(transcript_path: str) -> str:
    """A session's id is its transcript's name without `.jsonl`."""
    return os.path.splitext(os.path.basename(transcript_path))[0]


def subagent_session_id(agent_id: str) -> str:
    """The session id of a sub-agent's file: `agent-<id>` (its `agent-<id>.jsonl` under `subagents/`)."""
    return f"agent-{agent_id}"


def session_subagents_dir(transcript_path: str) -> str:
    """Where Claude Code keeps a session's sub-agent files: beside its transcript,
    under the transcript's name without `.jsonl`."""
    return os.path.join(os.path.splitext(transcript_path)[0], SUBAGENTS_DIR)


def subagent_transcripts(session_dir: str) -> List[str]:
    """The sub-agent transcripts under `<session_dir>/subagents/`, sorted."""
    return _agent_files(os.path.join(session_dir, SUBAGENTS_DIR))


def _agent_files(agents_dir: str) -> List[str]:
    if not os.path.isdir(agents_dir):
        return []
    return sorted(os.path.join(agents_dir, a) for a in os.listdir(agents_dir) if a.endswith(".jsonl"))


def read_shunt_log(path: str) -> List[ShuntDecision]:
    """Every decision in a gate log; a line that is not JSON or has no decision is drift."""
    decisions: List[ShuntDecision] = []
    with open(path, encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                raise TranscriptError(f"{path}:{line_no}: shunt log line is not JSON")
            decision = entry.get("decision") if isinstance(entry, dict) else None
            if not isinstance(decision, str):
                raise TranscriptError(f"{path}:{line_no}: shunt log entry has no decision")
            tool = entry.get("tool")
            decisions.append(ShuntDecision(decision, tool if isinstance(tool, str) else None,
                                           entry.get("input"), line_no))
    return decisions


def find_shunt_log(home: str, session: str) -> Optional[str]:
    """The log the gate's hook wrote for `session` somewhere under `home` —
    `<project>/tasks/.shunt/<session>.jsonl`, the project being wherever the
    session ran. None when no gate ran; two candidates are drift."""
    parent_name, leaf_name = os.path.normpath(SHUNT_SOURCE_DIR).split(os.sep)
    name = f"{session}.jsonl"
    found: List[str] = []
    for dirpath, dirnames, filenames in os.walk(home):
        dirnames[:] = sorted(d for d in dirnames if d not in (".git", "node_modules"))
        head, leaf = os.path.split(dirpath)
        if leaf == leaf_name and os.path.basename(head) == parent_name and name in filenames:
            found.append(os.path.join(dirpath, name))
    if len(found) > 1:
        raise TranscriptError(f"{home}: {len(found)} shunt logs for session {session}: " + ", ".join(found))
    return found[0] if found else None


def _is_score(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def outcome_record(*, score: object = None, passed: object = None) -> Dict[str, object]:
    """The `outcome.json` payload for a runner's `score`, else its `passed`.

    A bool is not a score: `{"score": true}` is refused here and by `read_outcome`."""
    if _is_score(score):
        return {"score": score}
    if isinstance(passed, bool):
        return {"pass": passed}
    raise TranscriptError("run has neither score nor passed")


def write_outcome(run_dir: str, record: Dict[str, object]) -> None:
    """Write a record `outcome_record` made."""
    with open(os.path.join(run_dir, OUTCOME_FILE), "w", encoding="utf-8") as fh:
        json.dump(record, fh)


def read_outcome(run_dir: str) -> Optional[float]:
    """The run's outcome as 0..1, None when the runner recorded none."""
    path = os.path.join(run_dir, OUTCOME_FILE)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        try:
            data = json.load(fh)
        except ValueError:
            raise TranscriptError(f"{path}:1: {OUTCOME_FILE} is not JSON")
    if isinstance(data, dict):
        if _is_score(data.get("score")):
            return float(data["score"])
        if isinstance(data.get("pass"), bool):
            return 1.0 if data["pass"] else 0.0
    raise TranscriptError(f"{path}:1: {OUTCOME_FILE} has neither score nor pass")


def _block_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(part.get("text", "") for part in content
                       if isinstance(part, dict) and part.get("type") == "text")
    return ""


_NUMBERED_LINE = re.compile(r"^\s*(\d+)\t")
# The harness prefixes some Read results (memory files, stale-file notes) with one
# or more <system-reminder> blocks before the numbered text.
_LEADING_REMINDERS = re.compile(r"^(?:\s*<system-reminder>.*?</system-reminder>)+\s*", re.DOTALL)


# What a null-result Read block says when no file text entered the context.
_NON_FILE_NOTES = ("Wasted call", "PDF file read:")


def _is_non_file_note(text: str) -> bool:
    """True when a block without metadata carries a note instead of file text:
    an empty file or an offset past its end (a bare reminder), an unchanged
    file ("Wasted call"), a PDF summary line, or nothing at all (an image)."""
    rest = _LEADING_REMINDERS.sub("", text, count=1).strip()
    return rest == "" or rest.startswith(_NON_FILE_NOTES)


def _numbered_lines(text: str) -> Optional[Tuple[int, int]]:
    """(first line number, line count) when `text` is the Read tool's `cat -n` output."""
    lines = _LEADING_REMINDERS.sub("", text, count=1).split("\n")
    first = _NUMBERED_LINE.match(lines[0]) if lines and lines[0] else None
    if first is None or not all(_NUMBERED_LINE.match(l) for l in lines if l):
        return None
    return int(first.group(1)), sum(1 for l in lines if l)


def _context_size(usage: object) -> Optional[int]:
    if not isinstance(usage, dict):
        return None
    total = 0
    for key in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
        value = usage.get(key, 0)
        total += value if isinstance(value, int) else 0
    return total


def parse_transcript(path: str, is_subagent: Optional[bool] = None) -> Transcript:
    """Stream one JSONL transcript into its metadata, its Reads, shell reads,
    Greps and Agent calls classified.

    A Read block or a completed Agent result the module cannot read raises
    `TranscriptDrift` here, so a returned `Transcript` is a readable one."""
    if is_subagent is None:
        is_subagent = SUBAGENTS_DIR in path.replace("\\", "/").split("/")
    t = Transcript(path, session_id(path), is_subagent)
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line_no, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                t.malformed += 1
                continue
            if not isinstance(rec, dict):
                t.malformed += 1
                continue
            _absorb(t, rec, line_no)
    t._pending.clear()    # a result whose use never came is in `t.results` and nowhere else
    for use in t.tool_uses:
        if use.name in CLASSIFIED_TOOLS and use.id not in t.results:
            _classify(t, use, None)    # unanswered: the session ended, or the harness never replied
    t._reads = tuple(t._calls[u.id] for u in t._tool_uses_named("Read"))
    own = t.own_tool_uses()
    t._own_calls = tuple(t._calls[u.id] for u in own if u.id in t._calls)
    t._shell_reads = tuple(c for c in t._own_calls if isinstance(c, ShellRead))
    t._grep_calls = tuple(c for c in t._own_calls if isinstance(c, GrepCall))
    t._agent_calls = tuple(c for c in t._own_calls if isinstance(c, AgentCall))
    for use in own:
        result = t.results.get(use.id)
        if result is not None and result.bytes > t._largest_own_result[0]:
            t._largest_own_result = (result.bytes, use.subject)
    return t


def parse_session(parent_path: str, subagent_paths: List[str]) -> SessionReads:
    """A main-loop transcript and its sub-agent files, parsed and assembled once."""
    parent = parse_transcript(parent_path, is_subagent=False)
    agents = [parse_transcript(p, is_subagent=True) for p in subagent_paths]
    counted = [r for t in (parent, *agents) for r in t.counted_subagent_reads()]
    return SessionReads(parent, agents, counted, parent.malformed + sum(a.malformed for a in agents))


def _classify(t: Transcript, use: ToolUse, raw: Optional[RawResult]) -> None:
    """Classify one tool use from its input and (when answered) its result, and keep the call.

    Every Read is kept, whichever context made it; a Bash, Grep or Agent use
    only when it is this file's own. A Bash that printed no file whole is no call."""
    if use.name not in CLASSIFIED_TOOLS:
        return
    if use.name == "Read":
        t._calls[use.id] = classify_read(use, raw, t.path)
    elif not t._is_own(use):
        return
    elif use.name == "Bash":
        shell = classify_shell_read(use, raw)
        if shell is not None:
            t._calls[use.id] = shell
    elif use.name == "Grep":
        t._calls[use.id] = classify_grep(use, raw)
    elif use.name == "Agent":
        t._calls[use.id] = classify_agent(use, raw, t.path)


def _absorb(t: Transcript, rec: dict, line_no: int) -> None:
    ts = rec.get("timestamp")
    if isinstance(ts, str):
        t.first_timestamp = t.first_timestamp or ts
        t.last_timestamp = ts    # every line, sidechain included: wall time
    kind = rec.get("type")
    if kind not in ("assistant", "user", "system"):
        return    # an api-request-blob copies the request, uuid-less and with no isSidechain
    sidechain = t.is_subagent or rec.get("isSidechain") is True
    inline_sidechain = sidechain and not t.is_subagent
    if kind == "system":
        if rec.get("subtype") == "compact_boundary" and not inline_sidechain:
            t.compactions += 1
        return
    message = rec.get("message")
    if not isinstance(message, dict):
        return
    content = message.get("content")
    if kind == "assistant" and not inline_sidechain:
        usage = message.get("usage")
        size = _context_size(usage)
        if size is not None:
            t.final_context = size
        # One API message is logged as several assistant records, one per content
        # block, each carrying the whole message's usage: count a message id once.
        message_id = message.get("id")
        if message_id not in t._message_ids:    # an id-less record counts on its own
            if isinstance(message_id, str):
                t._message_ids.add(message_id)
            t.total_tokens += _turn_tokens(usage)
    if not isinstance(content, list):
        return
    results = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"]
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "tool_use" and str(block.get("id")) not in t._uses_by_id:
            # a resumed session re-logs a record: first wins, use and result
            use = ToolUse(str(block.get("id")), str(block.get("name")),
                          block.get("input") if isinstance(block.get("input"), dict) else {},
                          line_no, ts if isinstance(ts, str) else None, sidechain)
            t._uses_by_id[use.id] = use
            t.tool_uses.append(use)
            held = t._pending.pop(use.id, None)
            if held is not None:
                _classify(t, use, held)    # its result was logged first
    # `toolUseResult` sits beside the message, one per record, so it belongs to a
    # record with one result block; several blocks never carry one (a record
    # that did would be drift), and their Reads fall back to the block text.
    structured = rec.get("toolUseResult")
    if len(results) > 1 and structured is not None:
        raise TranscriptDrift(t.path, line_no, "several tool_result blocks share one toolUseResult")
    for block in results:
        tid = str(block.get("tool_use_id"))
        if tid in t.results:
            continue
        raw = RawResult(tid, _block_text(block.get("content")), structured, block.get("is_error") is True, line_no)
        t.results[tid] = raw.kept()
        use = t._uses_by_id.get(tid)
        if use is not None:
            _classify(t, use, raw)    # the block text and toolUseResult go out of scope with this line
        else:
            t._pending[tid] = raw     # held until its use arrives


def _turn_tokens(usage: object) -> int:
    """Every token an API message was billed: its input, cache writes and reads, and output."""
    if not isinstance(usage, dict):
        return 0
    return sum(v for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
               for v in [usage.get(k, 0)] if isinstance(v, int))


def classify_read(tool_use: ToolUse, result: Optional[RawResult], path: str) -> Read:
    """Whole-file, ranged or excluded, from the input plus `toolUseResult.file`."""
    file_path = tool_use.input.get("file_path")
    if result is None or result.is_error or isinstance(result.structured, str):
        # Unanswered, or an error message — nothing entered the context. A call
        # the harness could not parse (`__unparsedToolInput`) has no file_path.
        return Read(tool_use, file_path if isinstance(file_path, str) else "", "excluded", False, 0, 0)
    if not isinstance(file_path, str):
        raise TranscriptDrift(path, tool_use.line_no, "Read input has no file_path")
    excluded = Read(tool_use, file_path, "excluded", False, 0, 0)
    ranged = "offset" in tool_use.input or "limit" in tool_use.input
    kind = "ranged" if ranged else "whole"
    structured = result.structured
    if structured is None:
        # Older transcripts carry no `toolUseResult` beside a Read; the block
        # text is the tool's `cat -n` output, so the lines are counted from it
        # and the total is unknown — a whole-file read is taken at its line count.
        numbered = _numbered_lines(result.text)
        if numbered is None:
            if _is_non_file_note(result.text):
                return excluded    # unchanged, empty, PDF or image: no file text entered
            raise TranscriptDrift(path, result.line_no, "Read result has no metadata and its text is not numbered lines")
        return Read(tool_use, file_path, kind, False, result.bytes, numbered[1])
    if not isinstance(structured, dict):
        raise TranscriptDrift(path, result.line_no, "Read result is not an object, a string or null")
    result_type = structured.get("type")
    if result_type in EXCLUDED_RESULT_TYPES:
        return excluded
    file_block = structured.get("file")
    if result_type != "text" or not isinstance(file_block, dict) \
            or any(k not in file_block for k in _TEXT_FILE_KEYS) \
            or not isinstance(file_block["content"], str):
        raise TranscriptDrift(path, result.line_no, f"Read result of type {result_type!r} has no readable file block")
    num_lines, total_lines = int(file_block["numLines"]), int(file_block["totalLines"])
    truncated = not ranged and (num_lines < total_lines or file_block.get("truncatedByTokenCap") is True)
    return Read(tool_use, file_path, kind, truncated, result.bytes, total_lines)


def classify_grep(tool_use: ToolUse, result: Optional[RawResult]) -> GrepCall:
    context, head_limit = tool_use.input.get("-C"), tool_use.input.get("head_limit")
    return GrepCall(tool_use, normalize_path(str(tool_use.input.get("path", ""))),
                    context if isinstance(context, int) else None,
                    head_limit if isinstance(head_limit, int) else None,
                    result.bytes if result is not None else None)


def classify_agent(tool_use: ToolUse, result: Optional[RawResult], path: str) -> AgentCall:
    """The text an Agent call named paths in, and the counters its result carries.

    An async launch has an object result with no counters; a `completed` result
    without them is drift, and an unanswered or errored call is not."""
    parts = [str(tool_use.input.get("prompt", ""))]
    tokens: Optional[int] = None
    tool_uses: Optional[int] = None
    agent_id: Optional[str] = None
    structured = result.structured if result is not None else None
    if isinstance(structured, dict):
        content = structured.get("content")
        if isinstance(content, list):
            parts += [str(p.get("text", "")) for p in content if isinstance(p, dict)]
        elif isinstance(content, str):
            parts.append(content)
        counters = (structured.get("totalTokens"), structured.get("totalToolUseCount"))
        tokens, tool_uses = (c if isinstance(c, int) else None for c in counters)
        if isinstance(structured.get("agentId"), str):
            agent_id = structured["agentId"]
        if structured.get("status") == "completed" and None in (tokens, tool_uses):
            raise TranscriptDrift(path, result.line_no,
                                  "completed Agent result has no totalTokens and totalToolUseCount")
    return AgentCall(tool_use, "\n".join(parts), tokens, tool_uses, agent_id)


def classify_shell_read(tool_use: ToolUse, result: Optional[RawResult]) -> Optional[ShellRead]:
    """The files a `Bash` use printed whole, or None when it printed none or never answered."""
    files = bare_shell_reads(str(tool_use.input.get("command", "")))
    if not files or result is None:
        return None
    return ShellRead(tool_use, tuple(normalize_path(f) for f in files), result.bytes)


SHELL_READERS = frozenset({"cat", "head", "tail", "less", "more"})
_SEGMENT_SPLITTERS = (";", "&&", "||", "\n")
_NOT_BARE = ("|", ">", "<", "$(", "`")
# Per command, the short options that take the next word as their argument;
# every other option is a bare flag (`cat -n f` numbers lines, it takes no count).
_ARG_OPTIONS = {"head": frozenset({"-n", "-c"}), "tail": frozenset({"-n", "-c"})}


def _split_segments(command: str) -> List[str]:
    """Split on `;`, `&&`, `||` and newlines outside quotes; `|` stays inside its segment."""
    segments, buf, quote, i = [], [], None, 0
    while i < len(command):
        ch = command[i]
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        for sep in _SEGMENT_SPLITTERS:
            if command.startswith(sep, i):
                segments.append("".join(buf))
                buf = []
                i += len(sep)
                break
        else:
            buf.append(ch)
            i += 1
    segments.append("".join(buf))
    return [s.strip() for s in segments if s.strip()]


def _words(segment: str) -> List[str]:
    """Whitespace split that honours quotes and keeps backslashes literal (Windows paths)."""
    words, buf, quote = [], [], None
    for ch in segment:
        if quote:
            if ch == quote:
                quote = None
            else:
                buf.append(ch)
        elif ch in ("'", '"'):
            quote = ch
        elif ch.isspace():
            if buf:
                words.append("".join(buf))
                buf = []
        else:
            buf.append(ch)
    if buf:
        words.append("".join(buf))
    return words


def _is_print_range(script: str) -> bool:
    body = script[:-1] if script.endswith("p") else ""
    return bool(body) and all(c.isdigit() or c in ",$" for c in body)


def bare_shell_reads(command: str) -> List[str]:
    """The files a Bash command prints whole into the context, one entry per file.

    `cat f`, `head f`, `tail f`, `less f`, `more f` and `sed -n '1,$p' f` count;
    every file of a chained command (`cat a; cat b`) counts. A segment that is
    piped, redirected, substituted or fed a heredoc delivers nothing to the
    context and is skipped (specs/read-shunt-baseline.md § Behavior, AC3).
    """
    files: List[str] = []
    for segment in _split_segments(command):
        if any(marker in segment for marker in _NOT_BARE):
            continue
        words = _words(segment)
        if not words:
            continue
        name = os.path.basename(words[0])
        if name == "sed":
            rest = [w for w in words[1:] if w != "-n"]
            if rest and _is_print_range(rest[0]):
                files.extend(rest[1:])
            continue
        if name not in SHELL_READERS:
            continue
        rest = words[1:]
        arg_options = _ARG_OPTIONS.get(name, frozenset())
        while rest and rest[0].startswith("-"):
            opt = rest.pop(0)
            if opt in arg_options and rest:
                rest.pop(0)
        files.extend(rest)
    return files


def markdown_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> str:
    """A header line, its rule line and one line per row."""
    def line(cells: Sequence[str]) -> str:
        return "| " + " | ".join(cells) + " |"
    rule = "|" + "|".join("---" for _ in headers) + "|"
    return "\n".join([line(headers), rule, *(line(row) for row in rows)])


def run(main: Callable[[], object]) -> int:
    """Run a CLI body; a TranscriptError is reported on stderr, prefixed with the CLI's name, and becomes exit 2."""
    try:
        code = main()
    except TranscriptError as exc:
        name = os.path.basename(sys.argv[0])
        print(f"{name[:-3] if name.endswith('.py') else name}: {exc}", file=sys.stderr)
        return exc.exit_code
    return code if isinstance(code, int) else 0
