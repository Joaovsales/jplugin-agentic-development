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

One JSON object per line. An `assistant` record carries `message.content`
(a list of blocks; a `tool_use` block has `id`, `name`, `input`) and
`message.usage`; a `user` record carries `tool_result` blocks and, beside the
message, `toolUseResult` — the tool's structured result. A `Read` of a text
file puts `{"type": "text", "file": {filePath, content, numLines, startLine,
totalLines[, truncatedByTokenCap]}}` there; an image, PDF, notebook or an
unchanged file has another `type`; an error is a bare string. A sub-agent's
lines carry `isSidechain: true` and `agentId`; older transcripts put such
lines inline in the parent's file. A `system` record with `subtype:
compact_boundary` marks a compaction.

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
from typing import Callable, Dict, List, Optional

DEFAULT_BYTES = 32768
DEFAULT_LINES = 800
SUBAGENTS_DIR = "subagents"

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


@dataclass
class ToolResult:
    tool_use_id: str
    bytes: int                 # text bytes of the tool_result block
    result: object             # the record's `toolUseResult`, or None
    is_error: bool
    line_no: int


@dataclass
class Read:
    """One `Read` tool use, classified from its input and its result."""

    tool_use: ToolUse
    path: str
    kind: str                  # whole | ranged | excluded
    truncated: bool
    bytes: int                 # UTF-8 bytes of the file content delivered
    total_lines: int

    @property
    def norm_path(self) -> str:
        return normalize_path(self.path)

    def is_large(self, bytes_threshold: int = DEFAULT_BYTES, lines_threshold: int = DEFAULT_LINES) -> bool:
        if self.kind == "excluded":
            return False
        return self.bytes >= bytes_threshold or self.total_lines >= lines_threshold


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

    def tool_uses_named(self, name: str) -> List[ToolUse]:
        return [t for t in self.tool_uses if t.name == name]

    def reads(self) -> List[Read]:
        return [classify_read(t, self.results.get(t.id), self.path) for t in self.tool_uses_named("Read")]

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
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(dirpath, root)
            project = rel.replace("\\", "/").split("/")[0] if rel != "." else ""
            agents_dir = os.path.join(dirpath, name[: -len(".jsonl")], SUBAGENTS_DIR)
            agents = []
            if os.path.isdir(agents_dir):
                agents = sorted(
                    os.path.join(agents_dir, a) for a in os.listdir(agents_dir) if a.endswith(".jsonl")
                )
            sessions.append(Session(path, project, agents))
    if not sessions:
        raise EmptyRoot(root)
    return sessions


def _block_bytes(content: object) -> int:
    if isinstance(content, str):
        return len(content.encode("utf-8"))
    if isinstance(content, list):
        return sum(len(part.get("text", "").encode("utf-8")) for part in content
                   if isinstance(part, dict) and part.get("type") == "text")
    return 0


def _context_size(usage: object) -> Optional[int]:
    if not isinstance(usage, dict):
        return None
    total = 0
    for key in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
        value = usage.get(key, 0)
        total += value if isinstance(value, int) else 0
    return total


def parse_transcript(path: str, is_subagent: Optional[bool] = None) -> Transcript:
    """Stream one JSONL transcript into its metadata."""
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
        t.results[tid] = ToolResult(tid, _block_bytes(block.get("content")), structured,
                                    block.get("is_error") is True, line_no)


def classify_read(tool_use: ToolUse, result: Optional[ToolResult], path: str) -> Read:
    """Whole-file, ranged or excluded, from the input plus `toolUseResult.file`."""
    file_path = tool_use.input.get("file_path")
    if not isinstance(file_path, str):
        raise TranscriptDrift(path, tool_use.line_no, "Read input has no file_path")
    excluded = Read(tool_use, file_path, "excluded", False, 0, 0)
    if result is None or result.is_error or isinstance(result.result, str):
        return excluded            # unanswered, or an error message: nothing entered the context
    structured = result.result
    if not isinstance(structured, dict):
        raise TranscriptDrift(path, result.line_no, "Read result is not an object or a string")
    kind = structured.get("type")
    if kind in EXCLUDED_RESULT_TYPES:
        return excluded
    file_block = structured.get("file")
    if kind != "text" or not isinstance(file_block, dict) \
            or any(k not in file_block for k in _TEXT_FILE_KEYS) \
            or not isinstance(file_block["content"], str):
        raise TranscriptDrift(path, result.line_no, f"Read result of type {kind!r} has no readable file block")
    ranged = "offset" in tool_use.input or "limit" in tool_use.input
    num_lines, total_lines = int(file_block["numLines"]), int(file_block["totalLines"])
    truncated = not ranged and (num_lines < total_lines or file_block.get("truncatedByTokenCap") is True)
    return Read(tool_use, file_path, "ranged" if ranged else "whole", truncated,
                len(file_block["content"].encode("utf-8")), total_lines)


SHELL_READERS = frozenset({"cat", "head", "tail", "less", "more"})
_SEGMENT_SPLITTERS = (";", "&&", "||", "\n")
_NOT_BARE = ("|", ">", "<", "$(", "`")
_COUNT_OPTIONS = frozenset({"-n", "-c", "-b", "-s"})


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
        while rest and rest[0].startswith("-"):
            opt = rest.pop(0)
            if opt in _COUNT_OPTIONS and rest:
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
