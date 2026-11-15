#!/usr/bin/env python3
"""Normalize native Codex searches for the shared, context-only graph hint."""

from __future__ import annotations

import json
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict) or payload.get("tool_name") != "Bash":
            return 0
        tool_input = payload.get("tool_input")
        if not isinstance(tool_input, dict) or not isinstance(tool_input.get("command"), str):
            return 0
        words = shlex.split(tool_input["command"])
        if not words:
            return 0
        command = Path(words[0]).name
        if command in ("rg", "grep"):
            tool = "Glob" if command == "rg" and "--files" in words[1:] else "Grep"
        elif command == "find":
            tool = "Glob"
        else:
            return 0
        hook = Path(__file__).with_name("jplugin-agentic-development-code-graph-hint.sh")
        result = subprocess.run(
            [shutil.which("bash") or "bash", str(hook)],
            input=json.dumps({"tool_name": tool}),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return 0
        output = json.loads(result.stdout)
        context = output.get("hookSpecificOutput", {}).get("additionalContext")
        if isinstance(context, str) and context:
            sys.stdout.buffer.write((json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "additionalContext": context,
            }}, ensure_ascii=False) + "\n").encode("utf-8"))
    except (OSError, ValueError, TypeError, AttributeError, subprocess.SubprocessError):
        return 0  # Optional context must never prevent the native search.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
