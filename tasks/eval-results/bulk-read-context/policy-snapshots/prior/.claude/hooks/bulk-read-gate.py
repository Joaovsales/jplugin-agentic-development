#!/usr/bin/env python3
"""PreToolUse gate: deny whole-file reads over BULK_READ_MIN_LINES lines.

Spec: specs/bulk-read-gate.md. Shared byte-identical by Claude Code
(.claude/settings.json, through the bulk-read-gate.sh interpreter shim) and
Codex (scripts/install-codex.sh); Pi mirrors it in pi/extensions/bulk-read-gate.ts.

Reads one hook event as JSON on stdin ({"tool_name", "tool_input"}). When the
call would put more than the threshold's worth of one file's lines into the
calling model's context, it denies the call and names the two alternatives:
dispatch `bulk-reader` with a question, or read only the range an edit needs.
It never rewrites the call and never reads content into the model — it counts
newlines and exits.

Admission is by input shape, not tool name: `Read` is gated by `file_path`, and
any other tool whose input carries a string or argv `command` is treated as a
shell. That is deliberate — Claude Code scopes the hook with a tool matcher, but
Codex registers it for every tool and names its shell tool differently, so the
shell contract has to live in the input. The TypeScript mirror gates by Pi's
fixed tool names instead, because Pi has exactly two.

Exit codes: 0 allow (silent) or deny (decision JSON on stdout); 1 internal
error with one structured line on stderr — never a silent allow.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import NoReturn, Optional

DEFAULT_THRESHOLD = 350
BINARY_PROBE_BYTES = 8192
# Command lists: each list's final pipe stage prints into the tool result, so
# every one is gated. `|` alone hands a stage's stdout to the next stage.
LIST_SEPARATORS = {"||", "&&", ";", "&", "\n"}
# `2>&1`, `> out`, `>> log`, `&> all`, `< in` — with or without the operand glued on.
REDIRECT = re.compile(r"^(?P<fd>\d*)(?P<op>&>>|&>|>>|>|<<|<)(?P<target>.*)$")
SED_RANGE = re.compile(r"^(\d+),(\d+|\$)p$")
HEAD_COUNT = re.compile(r"^(?:-n|--lines=|-)(\d+)$")
POWERSHELL_LIMITERS = {"-totalcount", "-head", "-first", "-tail", "-last"}

# (first line, last line or None for end of file), 1-based and inclusive.
Window = tuple[int, Optional[int]]
WHOLE: Window = (1, None)


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"bulk-read-gate: {message}\n")
    sys.exit(1)


def positive_int(value: object) -> Optional[int]:
    try:
        number = int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def threshold() -> int:
    raw = os.environ.get("BULK_READ_MIN_LINES", "").strip()
    if not raw:
        return DEFAULT_THRESHOLD
    value = positive_int(raw)
    if value is None:
        fail(f"BULK_READ_MIN_LINES must be a positive integer, got {raw!r}")
    return value


def count_lines(path: str) -> int:
    """Line count of a regular text file; 0 when the gate has no opinion.

    Missing paths, directories, and binary files (NUL in the first 8 KB) are
    the tool's problem, not the gate's, and zero lines never exceeds a
    threshold. A path that exists but cannot be opened exits 1 instead: on
    Claude Code and Codex that is a loud, non-blocking hook error (the tool
    still runs, stderr is shown), on Pi the mirror blocks. Either way the
    breakage is visible; a silent allow is the one outcome ruled out.
    """
    expanded = os.path.expanduser(path)
    if not os.path.isfile(expanded):
        return 0
    try:
        with open(expanded, "rb") as stream:
            head = stream.read(BINARY_PROBE_BYTES)
            if b"\0" in head:
                return 0
            lines = head.count(b"\n")
            last = head[-1:]
            while chunk := stream.read(1 << 20):
                lines += chunk.count(b"\n")
                last = chunk[-1:]
    except OSError as exc:
        fail(f"cannot open {path}: {exc}")
    return lines + (1 if last and last != b"\n" else 0)


def deny_reason(path: str, lines: int, limit: int) -> str:
    return (
        f"{path} has {lines} lines; the bulk-read gate denies reads over {limit} lines "
        f"(BULK_READ_MIN_LINES). Either dispatch the `bulk-reader` agent with a question "
        f"about this file, or read only the range you need for an edit "
        f"(Read with offset/limit of at most {limit} lines, or `sed -n 'A,Bp'`)."
    )


def delivered_lines(lines: int, window: Window) -> int:
    """How many of an N-line file's lines printing `window` puts into context."""
    start, end = window
    return max(min(end or lines, lines) - start + 1, 0)


def gate_path(path: str, window: Window, limit: int) -> Optional[str]:
    lines = count_lines(path)
    return deny_reason(path, lines, limit) if delivered_lines(lines, window) > limit else None


def gate_read(tool_input: dict, limit: int) -> Optional[str]:
    path = tool_input.get("file_path")
    if not isinstance(path, str) or not path:
        return None
    offset = positive_int(tool_input.get("offset")) or 1
    requested = positive_int(tool_input.get("limit"))
    return gate_path(path, (offset, offset + requested - 1 if requested else None), limit)


def tokenize(command: str) -> list[str]:
    """Quote-aware split. Quotes stay on the token (see unquote); backslashes are
    literal so Windows paths survive; `|`, `||`, `&&`, `;`, `&` and newline are
    their own tokens. The `&` of `2>&1` or `&>` belongs to the redirection."""
    tokens: list[str] = []
    current = ""
    quote: Optional[str] = None
    index = 0
    while index < len(command):
        char = command[index]
        if quote:
            current += char
            quote = None if char == quote else quote
        elif char in "\"'":
            quote, current = char, current + char
        elif char == "\n" or (char in "|&;" and not redirect_glue(current, command, index)):
            tokens, current = flush(tokens, current), ""
            pair = command[index : index + 2]
            tokens.append(pair if pair in {"||", "&&"} else char)
            index += 1 if pair in {"||", "&&"} else 0
        elif char.isspace():
            tokens, current = flush(tokens, current), ""
        else:
            current += char
        index += 1
    return flush(tokens, current)


def redirect_glue(current: str, command: str, index: int) -> bool:
    """`&` inside `2>&1` or `&>` is part of a redirection, not a list separator."""
    return command[index] == "&" and (current.endswith(">") or command[index + 1 : index + 2] == ">")


def flush(tokens: list[str], current: str) -> list[str]:
    return tokens + [current] if current else tokens


def split_command(command: object) -> list[str]:
    if isinstance(command, list):
        return [str(token) for token in command]
    return tokenize(command) if isinstance(command, str) else []


def final_stages(tokens: list[str]) -> list[list[str]]:
    """The last pipe stage of every command list — each prints into the tool result."""
    stages: list[list[str]] = []
    stage: list[str] = []
    for token in tokens:
        if token in LIST_SEPARATORS:
            stages, stage = stages + [stage], []
        elif token == "|":
            stage = []
        else:
            stage = stage + [token]
    return stages + [stage]


def strip_redirects(args: list[str]) -> tuple[list[str], bool]:
    """Drop redirections and their operands. Returns (arguments, stdout silenced).

    `< path` makes the path an argument (cat < big prints big); `N>&M` is a
    descriptor copy and `<<WORD` an inline heredoc, neither of which changes
    what is printed; `>`/`>>`/`&>` to a file take the stage's stdout out of the
    tool result, so nothing reaches the model.
    """
    kept: list[str] = []
    inputs: list[str] = []
    silenced = False
    index = 0
    while index < len(args):
        match = REDIRECT.match(args[index])
        if not match:
            kept.append(args[index])
        else:
            target = match.group("target")
            if not target and index + 1 < len(args):
                index += 1
                target = args[index]
            if target.startswith("&") or match.group("op") == "<<":
                pass
            elif match.group("op") == "<":
                inputs.append(target)
            elif match.group("fd") in {"", "1"} or match.group("op").startswith("&"):
                silenced = True
        index += 1
    return kept + inputs, silenced


def unquote(token: str) -> str:
    if len(token) >= 2 and token[0] == token[-1] and token[0] in "\"'":
        return token[1:-1]
    return token


def positional(args: list[str]) -> list[str]:
    return [unquote(arg) for arg in args if not arg.startswith("-")]


def shell_read(stage: list[str]) -> tuple[list[str], Window]:
    """Paths a stage prints into the tool result, and the line window it prints."""
    if not stage:
        return [], WHOLE
    args, silenced = strip_redirects(stage[1:])
    if silenced:
        return [], WHOLE
    name = os.path.basename(unquote(stage[0])).lower()
    if name in {"cat", "type"}:
        return positional(args), WHOLE
    if name in {"get-content", "gc"}:
        if any(arg.lower() in POWERSHELL_LIMITERS for arg in args):
            return [], WHOLE
        return powershell_paths(args), WHOLE
    if name == "head":
        return head_read(args)
    if name == "sed":
        return sed_read(args)
    return [], WHOLE


def powershell_paths(args: list[str]) -> list[str]:
    paths: list[str] = []
    skip = False
    for index, arg in enumerate(args):
        if skip:
            skip = False
            continue
        if arg.lower() in {"-path", "-literalpath"}:
            if index + 1 < len(args):
                paths.append(unquote(args[index + 1]))
            skip = True
        elif not arg.startswith("-"):
            paths.append(unquote(arg))
    return paths


def head_read(args: list[str]) -> tuple[list[str], Window]:
    """`head [-n N] path` prints lines 1..N (10 by default)."""
    count: Optional[int] = 10
    paths: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        match = HEAD_COUNT.match(arg)
        if arg in {"-n", "--lines"} and index + 1 < len(args):
            index += 1
            count = positive_int(args[index])
        elif match:
            count = positive_int(match.group(1))
        elif arg.startswith("-"):
            return [], WHOLE  # -c bytes and friends are not line reads
        else:
            paths.append(unquote(arg))
        index += 1
    return (paths, (1, count)) if count else ([], WHOLE)


def sed_read(args: list[str]) -> tuple[list[str], Window]:
    """`sed -n 'A,Bp' path` prints lines A..B; `$` means end of file."""
    script: Optional[str] = None
    paths: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in {"-e", "--expression"} and index + 1 < len(args):
            index += 1
            script = unquote(args[index])
        elif not arg.startswith("-"):
            if script is None:
                script = unquote(arg)
            else:
                paths.append(unquote(arg))
        index += 1
    match = SED_RANGE.match(script or "")
    if not match:
        return [], WHOLE
    end = None if match.group(2) == "$" else int(match.group(2))
    return paths, (int(match.group(1)), end)


def gate_shell(tool_input: dict, limit: int) -> Optional[str]:
    for stage in final_stages(split_command(tool_input.get("command"))):
        paths, window = shell_read(stage)
        for path in paths:
            reason = gate_path(path, window, limit)
            if reason is not None:
                return reason
    return None


def read_event() -> dict:
    raw = sys.stdin.read()
    try:
        event = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"stdin is not valid hook JSON ({exc})")
    if not isinstance(event, dict):
        fail("stdin JSON must be an object with tool_name and tool_input")
    return event


def decide(event: dict, limit: int) -> Optional[str]:
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        fail(f"tool_input must be an object, got {type(tool_input).__name__}")
    if event.get("tool_name") == "Read":
        return gate_read(tool_input, limit)
    if "command" in tool_input:
        return gate_shell(tool_input, limit)
    return None


def main() -> int:
    if os.environ.get("BULK_READ_GATE", "").strip().lower() == "off":
        return 0
    limit = threshold()
    reason = decide(read_event(), limit)
    if reason is not None:
        payload = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
        sys.stdout.write(json.dumps(payload) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
