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
skips it by the name `SHUNT_LOG`.

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

Everything streams: one line is parsed at a time and only metadata is kept,
so an 800 MB root is a few minutes, not a few gigabytes.

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
from typing import Callable, Dict, List, Optional, Tuple

DEFAULT_BYTES = 32768
DEFAULT_LINES = 800
SUBAGENTS_DIR = "subagents"
# The gate's decision log, written beside a transcript; it is JSONL but not a session.
SHUNT_LOG = "shunt.jsonl"
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
    tool_use_id: str
    bytes: int                 # text bytes of the tool_result block — what entered the context
    result: object             # the record's `toolUseResult`, or None
    is_error: bool
    line_no: int
    numbered: Optional[Tuple[int, int]] = None   # (first line number, line count) of `cat -n` text
    non_file: bool = False     # a note in place of file text: unchanged, empty, PDF, image


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
    _reads: List[Read] = field(default_factory=list, init=False, repr=False)
    _shell_reads: List[ShellRead] = field(default_factory=list, init=False, repr=False)
    _grep_calls: List[GrepCall] = field(default_factory=list, init=False, repr=False)
    _agent_calls: List[AgentCall] = field(default_factory=list, init=False, repr=False)

    def tool_uses_named(self, name: str) -> List[ToolUse]:
        return [t for t in self.tool_uses if t.name == name]

    def parent_tool_uses(self) -> List[ToolUse]:
        """The tool uses of the parent loop: every one that is not a sub-agent's sidechain."""
        return [t for t in self.tool_uses if not t.sidechain]

    def reads(self) -> List[Read]:
        return self._reads

    def shell_reads(self) -> List[ShellRead]:
        """The parent's `Bash` uses that printed whole files, in call order."""
        return self._shell_reads

    def grep_calls(self) -> List[GrepCall]:
        return self._grep_calls

    def agent_calls(self) -> List[AgentCall]:
        return self._agent_calls

    def counted_reads(self) -> List[Read]:
        """The reads whose file text entered the context — every read but the excluded."""
        return [r for r in self._reads if not r.is_excluded]

    def tool_result_bytes(self) -> int:
        return sum(r.bytes for r in self.results.values())


@dataclass
class Session:
    path: str
    project: str
    subagent_paths: List[str]


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
        for name in sorted(filenames):
            if not name.endswith(".jsonl") or name == SHUNT_LOG:
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(dirpath, root)
            project = rel.replace("\\", "/").split("/")[0] if rel != "." else ""
            agents = subagent_transcripts(os.path.join(dirpath, name[: -len(".jsonl")]))
            sessions.append(Session(path, project, agents))
    if not sessions:
        raise EmptyRoot(root)
    return sessions


def subagent_transcripts(session_dir: str) -> List[str]:
    """The sub-agent transcripts under `<session_dir>/subagents/`, sorted."""
    agents_dir = os.path.join(session_dir, SUBAGENTS_DIR)
    if not os.path.isdir(agents_dir):
        return []
    return sorted(os.path.join(agents_dir, a) for a in os.listdir(agents_dir) if a.endswith(".jsonl"))


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


def write_outcome(run_dir: str, *, score: object = None, passed: object = None) -> None:
    with open(os.path.join(run_dir, OUTCOME_FILE), "w", encoding="utf-8") as fh:
        json.dump(outcome_record(score=score, passed=passed), fh)


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
    t = Transcript(path, os.path.splitext(os.path.basename(path))[0], is_subagent)
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
    t._reads = [classify_read(u, t.results.get(u.id), path) for u in t.tool_uses_named("Read")]
    parent = t.parent_tool_uses()
    t._shell_reads = [s for s in (classify_shell_read(u, t.results.get(u.id))
                                  for u in parent if u.name == "Bash") if s is not None]
    t._grep_calls = [classify_grep(u, t.results.get(u.id)) for u in parent if u.name == "Grep"]
    t._agent_calls = [classify_agent(u, t.results.get(u.id), path) for u in parent if u.name == "Agent"]
    return t


def _absorb(t: Transcript, rec: dict, line_no: int) -> None:
    ts = rec.get("timestamp")
    if isinstance(ts, str):
        t.first_timestamp = t.first_timestamp or ts
        t.last_timestamp = ts
    kind = rec.get("type")
    if kind == "system":
        if rec.get("subtype") == "compact_boundary":
            t.compactions += 1
        return
    message = rec.get("message")
    if not isinstance(message, dict):
        return
    content = message.get("content")
    sidechain = t.is_subagent or rec.get("isSidechain") is True
    if kind == "assistant":
        size = _context_size(message.get("usage"))
        if size is not None:
            t.final_context = size
    if not isinstance(content, list):
        return
    results = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"]
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "tool_use":
            t.tool_uses.append(ToolUse(str(block.get("id")), str(block.get("name")),
                                       block.get("input") if isinstance(block.get("input"), dict) else {},
                                       line_no, ts if isinstance(ts, str) else None, sidechain))
    # `toolUseResult` sits beside the message, one per record; with several
    # result blocks on one line it cannot be attributed and is left out.
    structured = rec.get("toolUseResult") if len(results) == 1 else None
    for block in results:
        tid = str(block.get("tool_use_id"))
        text = _block_text(block.get("content"))
        t.results[tid] = ToolResult(tid, len(text.encode("utf-8")), structured,
                                    block.get("is_error") is True, line_no, _numbered_lines(text),
                                    _is_non_file_note(text))


def classify_read(tool_use: ToolUse, result: Optional[ToolResult], path: str) -> Read:
    """Whole-file, ranged or excluded, from the input plus `toolUseResult.file`."""
    file_path = tool_use.input.get("file_path")
    if result is None or result.is_error or isinstance(result.result, str):
        # Unanswered, or an error message — nothing entered the context. A call
        # the harness could not parse (`__unparsedToolInput`) has no file_path.
        return Read(tool_use, file_path if isinstance(file_path, str) else "", "excluded", False, 0, 0)
    if not isinstance(file_path, str):
        raise TranscriptDrift(path, tool_use.line_no, "Read input has no file_path")
    excluded = Read(tool_use, file_path, "excluded", False, 0, 0)
    ranged = "offset" in tool_use.input or "limit" in tool_use.input
    kind = "ranged" if ranged else "whole"
    structured = result.result
    if structured is None:
        # Older transcripts carry no `toolUseResult` beside a Read; the block
        # text is the tool's `cat -n` output, so the lines are counted from it
        # and the total is unknown — a whole-file read is taken at its line count.
        if result.numbered is None:
            if result.non_file:
                return excluded    # unchanged, empty, PDF or image: no file text entered
            raise TranscriptDrift(path, result.line_no, "Read result has no metadata and its text is not numbered lines")
        return Read(tool_use, file_path, kind, False, result.bytes, result.numbered[1])
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


def classify_grep(tool_use: ToolUse, result: Optional[ToolResult]) -> GrepCall:
    context, head_limit = tool_use.input.get("-C"), tool_use.input.get("head_limit")
    return GrepCall(tool_use, normalize_path(str(tool_use.input.get("path", ""))),
                    context if isinstance(context, int) else None,
                    head_limit if isinstance(head_limit, int) else None,
                    result.bytes if result is not None else None)


def classify_agent(tool_use: ToolUse, result: Optional[ToolResult], path: str) -> AgentCall:
    """The text an Agent call named paths in, and the counters its result carries.

    An async launch has an object result with no counters; a `completed` result
    without them is drift, and an unanswered or errored call is not."""
    parts = [str(tool_use.input.get("prompt", ""))]
    tokens: Optional[int] = None
    tool_uses: Optional[int] = None
    structured = result.result if result is not None else None
    if isinstance(structured, dict):
        content = structured.get("content")
        if isinstance(content, list):
            parts += [str(p.get("text", "")) for p in content if isinstance(p, dict)]
        elif isinstance(content, str):
            parts.append(content)
        counters = (structured.get("totalTokens"), structured.get("totalToolUseCount"))
        tokens, tool_uses = (c if isinstance(c, int) else None for c in counters)
        if structured.get("status") == "completed" and None in (tokens, tool_uses):
            raise TranscriptDrift(path, result.line_no,
                                  "completed Agent result has no totalTokens and totalToolUseCount")
    return AgentCall(tool_use, "\n".join(parts), tokens, tool_uses)


def classify_shell_read(tool_use: ToolUse, result: Optional[ToolResult]) -> Optional[ShellRead]:
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


def run(main: Callable[[], object]) -> int:
    """Run a CLI body; a TranscriptError is reported on stderr and becomes exit 2."""
    try:
        code = main()
    except TranscriptError as exc:
        print(f"read-transcript: {exc}", file=sys.stderr)
        return exc.exit_code
    return code if isinstance(code, int) else 0
