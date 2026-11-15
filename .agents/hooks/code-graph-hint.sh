#!/usr/bin/env bash
# Optional file-freshness context; never execute graphify or deny a tool call.
command -v graphify >/dev/null 2>&1 || exit 0
command -v timeout >/dev/null 2>&1 || exit 0
PYTHON_BIN="$(command -v python3 || command -v python || true)"
[ -n "$PYTHON_BIN" ] || exit 0

timeout 1 "$PYTHON_BIN" -c '
import json
import os
from pathlib import Path
import re
import subprocess
import sys

def context():
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict) or payload.get("tool_name") not in ("Grep", "Glob"):
        return None
    graph = Path("graphify-out/graph.json")
    with graph.open(encoding="utf-8") as source:
        json.load(source)
    graph_time = graph.stat().st_mtime_ns
    head = subprocess.check_output(["git", "log", "-1", "--format=%ct"], stderr=subprocess.DEVNULL)
    if graph_time < int(head) * 1_000_000_000:
        return None
    changed = subprocess.check_output(["git", "diff", "--name-only", "-z", "HEAD"], stderr=subprocess.DEVNULL)
    extensions = re.compile(r"\.(py|js|jsx|ts|tsx|go|rs|java|kt|c|h|cc|cpp|hpp|cs|rb|php|swift|scala)$", re.IGNORECASE)
    for name in os.fsdecode(changed).split("\0"):
        path = Path(name)
        if name and extensions.search(name) and (not path.exists() or path.stat().st_mtime_ns > graph_time):
            return None
    reference = ".agents/references/code-navigation.md"
    package = Path(sys.argv[1]).resolve().parents[1] / "references/code-navigation.md"
    if not Path(reference).is_file() and package.is_file():
        reference += " (package reference: " + str(package) + ")"
    return "Fresh code-graph files are present; see " + reference + "; use Grep if navigation is unavailable."

try:
    hint = context()
except (OSError, ValueError, subprocess.SubprocessError):
    hint = None
if hint:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": hint}}, separators=(",", ":")))
' "${BASH_SOURCE[0]}" 2>/dev/null || true
exit 0
