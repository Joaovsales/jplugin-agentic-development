#!/usr/bin/env python3
"""Adapt the shared text SessionStart hook to Codex hook JSON."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    hook = Path(__file__).with_name("jplugin-agentic-development-session-start.sh")
    # The shell hook's double-invocation guard is a Claude Code workaround: that
    # harness registers the hook twice (globally and per-project), so the second
    # firing has to exit silently. Codex registers it exactly once, so here the
    # guard can only ever suppress the one banner there is. It reliably does on
    # Windows: the guard keys on $PPID, and bash spawned from a native Windows
    # process reports PPID 1, so every invocation collides on a single sentinel
    # and every run inside its 5-minute window emits nothing at all.
    # Resolve bash by PATH order. A bare "bash" goes through CreateProcess on
    # Windows, which searches System32 before PATH and finds the WSL launcher
    # there when WSL is installed; that bash then fails to open a Windows path
    # and the adapter emits nothing. shutil.which walks PATH the way a shell
    # does and lands on Git's bash.
    result = subprocess.run(
        [shutil.which("bash") or "bash", str(hook)],
        input=sys.stdin.buffer.read(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "CCW_SESSION_GUARD": "0"},
        check=False,
    )
    if result.stderr:
        sys.stderr.buffer.write(result.stderr)
    output = result.stdout.decode("utf-8", errors="replace").strip()
    if output:
        payload = {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": output,
            }
        }
        # Written as UTF-8 bytes rather than print()ed. The banner carries box
        # rules, arrows and em-dashes, while Python encodes stdout with the
        # platform default — cp1252 on Windows, where print() raises
        # UnicodeEncodeError and Codex receives no JSON at all.
        sys.stdout.buffer.write(
            (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
        )
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
