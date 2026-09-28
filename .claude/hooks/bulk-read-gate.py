#!/usr/bin/env python3
"""PostToolUse adapter for scripts/context-read.py (Claude Code and Codex)."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time


def cli_path() -> Path:
    local = Path(__file__).with_name("context-read.py")
    return local if local.is_file() else Path(__file__).resolve().parents[2] / "scripts/context-read.py"


def fallback(event: dict, category: str) -> None:
    path = os.environ.get("BULK_READ_TELEMETRY") or str(Path.home() / ".cache/coding-agent-workflow/bulk-read-fallback.jsonl")
    record = {"time": int(time.time()), "category": category,
              "harness": event.get("harness", "unknown"),
              "call_id": event.get("tool_use_id", "unknown"), "usage": "unknown"}
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError as exc:
        print(f"bulk-read-gate: telemetry write failed: {exc}", file=sys.stderr)


def replacement_output(original: object, summary: str) -> object:
    if isinstance(original, dict):
        file_result = original.get("file")
        if isinstance(file_result, dict) and isinstance(file_result.get("content"), str):
            return {**original, "file": {**file_result, "content": summary}}
        for key in ("stdout", "output", "content"):
            if isinstance(original.get(key), str):
                return {**original, key: summary}
    return summary


def route_event(event: dict) -> dict | None:
    event["harness"] = event.get("harness") or os.environ.get("BULK_READ_HARNESS", "claude")
    cli = Path(os.environ.get("BULK_READ_CLI") or cli_path())
    if not cli.is_file():
        fallback(event, "cli_missing")
        return None
    try:
        result = subprocess.run([sys.executable, str(cli), "--route"],
                                input=json.dumps(event), text=True, capture_output=True,
                                timeout=90, env=os.environ.copy())
        if result.returncode:
            raise ValueError("router exited nonzero")
        return json.loads(result.stdout)["replacement"]
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
        fallback(event, "router_failed")
        return None


def protocol_output(event: dict, summary: dict) -> dict:
    text = json.dumps(summary, ensure_ascii=False, separators=(",", ":"))
    if event["harness"] == "codex":
        return {"decision": "block", "reason": text}
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse",
            "updatedToolOutput": replacement_output(event.get("tool_response"), text)}}


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError) as exc:
        fallback({}, "invalid_hook_event")
        print(f"bulk-read-gate: invalid hook JSON: {exc}", file=sys.stderr)
        return 0
    if not isinstance(event, dict):
        fallback({}, "invalid_hook_event")
        return 0
    if os.environ.get("BULK_READ_GATE", "").lower() == "off" or os.environ.get("BULK_READ_CHILD") == "1":
        return 0
    summary = route_event(event)
    if summary is not None:
        print(json.dumps(protocol_output(event, summary), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
