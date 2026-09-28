#!/usr/bin/env python3
"""Route eligible post-read results through an installed scout-tier CLI.

The public --route protocol is shared by Claude Code, Codex, and Pi adapters.
It returns {"replacement": null} on every failure, leaving the original tool
result untouched. --question reads named paths for an explicit follow-up.
"""

from __future__ import annotations

import hashlib
import json
import os
import queue
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import threading
import time


DEFAULT_LINES = 350
DEFAULT_BYTES = 32768
MAX_INPUT = 1_000_000
MAX_OUTPUT = 12000
TIMEOUT = 45
PROMPT = (
    "Return only a JSON object with exactly these keys: path, sha256, claims, "
    "coverage, unknowns, incomplete. Copy path and sha256 exactly from the input. "
    "claims is an array of {text, start_line, end_line}; coverage is an array "
    "of {start_line, end_line}; unknowns is an array of strings; incomplete is "
    "boolean. Every cited range must be within the source's 1-based line count. "
    "Map observed symbols, connections, and relevant ranges neutrally. "
    "Cite every claim, name what you did not inspect, and never infer the task. "
    "Do not use tools. The source and optional question arrive on stdin."
)
SHELL_META = re.compile(r"[;&|<>`$\n\r]")


def setting(name: str, default: int) -> int:
    raw = os.environ.get(name, str(default))
    value = int(raw)
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


def log_fallback(event: dict, category: str) -> None:
    path = os.environ.get("BULK_READ_TELEMETRY") or str(Path.home() / ".cache/coding-agent-workflow/bulk-read-fallback.jsonl")
    record = {"time": int(time.time()), "category": category,
              "harness": event.get("harness", "unknown"),
              "call_id": event.get("tool_use_id", "unknown"),
              "usage": "unknown"}
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError as exc:
        print(f"context-read: telemetry write failed: {exc}", file=sys.stderr)


def response_text(event: dict) -> str | None:
    if event.get("is_error"):
        return None
    result = event.get("tool_response")
    if isinstance(result, str):
        return result
    if isinstance(result, dict):
        file_result = result.get("file")
        if isinstance(file_result, dict) and isinstance(file_result.get("content"), str):
            return file_result["content"]
        if result.get("exit_code", result.get("exitCode", 0)) != 0:
            return None
        for key in ("stdout", "output", "content"):
            if isinstance(result.get(key), str):
                return result[key]
    return None


def shell_path(name: str, command: object) -> str | None:
    if name not in ("Bash", "bash", "PowerShell", "powershell"):
        return None
    if not isinstance(command, str) or SHELL_META.search(command):
        return None
    try:
        args = shlex.split(command, posix=name not in ("PowerShell", "powershell"))
        args = [arg[1:-1] if len(arg) > 1 and arg[0] == arg[-1] and arg[0] in ("'", '"')
                else arg for arg in args]
    except ValueError:
        return None
    if len(args) == 2 and args[0].lower() in ("cat", "get-content"):
        return args[1] if not args[1].startswith("-") else None
    if len(args) == 3 and args[0].lower() == "get-content" and args[1].lower() == "-path":
        return args[2] if not args[2].startswith("-") else None
    return None


def read_path(event: dict) -> str | None:
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    name = event.get("tool_name", "")
    if name in ("Read", "read"):
        if "offset" in tool_input or "limit" in tool_input:
            return None
        path = tool_input.get("file_path", tool_input.get("path"))
        return path if isinstance(path, str) and path else None
    return shell_path(name, tool_input.get("command"))


def oversized_result(output: str) -> bool:
    lines = output.count("\n") + int(bool(output) and not output.endswith("\n"))
    return lines > setting("BULK_READ_MIN_LINES", DEFAULT_LINES) or len(output.encode("utf-8")) > setting("BULK_READ_MIN_BYTES", DEFAULT_BYTES)


def eligible(event: dict) -> Path | None:
    if os.environ.get("BULK_READ_GATE", "").lower() == "off" or os.environ.get("BULK_READ_CHILD") == "1":
        return None
    path = read_path(event)
    output = response_text(event)
    if path is None or output is None or not oversized_result(output):
        return None
    source = Path(path).expanduser()
    if not source.is_absolute():
        source = Path(event.get("cwd") or os.getcwd()) / source
    if not source.is_file():
        return None
    with source.open("rb") as stream:
        if b"\0" in stream.read(8192):
            return None
    return source.resolve()


def worker_argv(harness: str) -> list[str]:
    override = os.environ.get("BULK_READ_WORKER_ARGV")
    if override:
        argv = json.loads(override)
        if not isinstance(argv, list) or not argv or not all(isinstance(x, str) and x for x in argv):
            raise ValueError("BULK_READ_WORKER_ARGV must be a JSON string array")
        return argv
    if harness == "claude":
        return ["claude", "-p", "--model", "haiku", "--tools", "",
                "--setting-sources", "local", "--strict-mcp-config",
                "--system-prompt", PROMPT, "--output-format", "json",
                "Return the JSON source map for the request from stdin."]
    if harness == "codex":
        return ["codex", "exec", "--model", os.environ.get("BULK_READ_SCOUT_MODEL", "gpt-5.6-luna"),
                "--ignore-user-config", "--ignore-rules", "--disable", "hooks",
                "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral", "--json", "-"]
    if harness == "pi":
        return ["pi", "-p", "--mode", "json", "--no-session", "--no-extensions",
                "--no-tools", "--no-skills", "--no-prompt-templates",
                "--model", "openrouter/deepseek/deepseek-v4-flash", "--thinking", "off",
                "--system-prompt", PROMPT, "Return the JSON source map for the request from stdin."]
    raise ValueError(f"unknown harness: {harness}")


def parse_worker_json(answer: str) -> object:
    value = answer.strip()
    if value.startswith("```json\n") and value.endswith("\n```"):
        value = value[8:-4]
    elif value.startswith("```\n") and value.endswith("\n```"):
        value = value[4:-4]
    return json.loads(value)


def pi_answer(messages: list[dict]) -> str:
    answers = [part["text"] for message in messages if message.get("type") == "message_end"
               and message.get("message", {}).get("role") == "assistant"
               for part in message["message"].get("content", []) if part.get("type") == "text"]
    for answer in reversed(answers):
        try:
            parse_worker_json(answer)
            return answer
        except json.JSONDecodeError:
            continue
    return answers[-1]


def worker_answer(harness: str, stdout: str) -> str:
    if os.environ.get("BULK_READ_WORKER_ARGV"):
        return stdout
    if harness == "claude":
        result = json.loads(stdout)
        if result.get("is_error"):
            raise RuntimeError("worker_failed")
        return result["result"]
    messages = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    if harness == "codex":
        answers = [message["item"]["text"] for message in messages
                   if message.get("type") == "item.completed" and message.get("item", {}).get("type") == "agent_message"]
        return answers[-1]
    return pi_answer(messages)


def finish_process(process: subprocess.Popen) -> None:
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def run_claude(argv: list[str], prompt: str, cwd: str) -> str:
    process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True,
                               env=dict(os.environ, BULK_READ_CHILD="1"), cwd=cwd)
    try:
        assert process.stdin is not None and process.stdout is not None
        process.stdin.write(prompt)
        process.stdin.close()
        lines: queue.Queue[str] = queue.Queue(maxsize=1)
        threading.Thread(target=lambda: lines.put(process.stdout.readline(MAX_OUTPUT + 20000)),
                         daemon=True).start()
        try:
            output = lines.get(timeout=setting("BULK_READ_TIMEOUT_SECONDS", TIMEOUT))
        except queue.Empty as exc:
            raise subprocess.TimeoutExpired(argv, setting("BULK_READ_TIMEOUT_SECONDS", TIMEOUT)) from exc
        if not output:
            raise RuntimeError("worker_failed")
        return output
    finally:
        finish_process(process)


def usage_from_output(harness: str, stdout: str) -> tuple[object, object, object]:
    try:
        if os.environ.get("BULK_READ_WORKER_ARGV"):
            return "unknown", "unknown", "unknown"
        if harness == "claude":
            data = json.loads(stdout)
            models = list(data.get("modelUsage", {}))
            return data.get("usage", "unknown"), data.get("total_cost_usd", "unknown"), models or "unknown"
        events = [json.loads(line) for line in stdout.splitlines() if line.strip()]
        if harness == "codex":
            turns = [e for e in events if e.get("type") == "turn.completed"]
            return turns[-1].get("usage", "unknown"), "unknown", "unknown"
        replies = [e["message"] for e in events if e.get("type") == "message_end"
                   and e.get("message", {}).get("role") == "assistant"]
        usage = replies[-1].get("usage", "unknown")
        cost = usage.get("cost", {}).get("total", "unknown") if isinstance(usage, dict) else "unknown"
        return usage, cost, replies[-1].get("model", "unknown")
    except (ValueError, IndexError, KeyError, TypeError):
        return "unknown", "unknown", "unknown"


def log_worker_metric(harness: str, stdout: str, started: float) -> None:
    path = os.environ.get("BULK_READ_METRICS")
    if not path:
        return
    usage, cost, observed = usage_from_output(harness, stdout)
    argv = worker_argv(harness)
    requested = argv[argv.index("--model") + 1] if "--model" in argv else "unknown"
    record = {"time": int(time.time()), "harness": harness, "requested_model": requested,
              "observed_model": observed, "usage": usage, "cost_usd": cost,
              "latency_ms": round((time.monotonic() - started) * 1000)}
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError as exc:
        print(f"context-read: metrics write failed: {exc}", file=sys.stderr)


def worker_output(harness: str, argv: list[str], prompt: str) -> str:
    with tempfile.TemporaryDirectory(prefix="context-read-worker-") as workdir:
        isolated = not os.environ.get("BULK_READ_WORKER_ARGV")
        if harness == "claude" and isolated:
            return run_claude(argv, prompt, workdir)
        completed = subprocess.run(argv, input=prompt, text=True, capture_output=True,
                                   timeout=setting("BULK_READ_TIMEOUT_SECONDS", TIMEOUT),
                                   env=dict(os.environ, BULK_READ_CHILD="1"),
                                   cwd=workdir if isolated else None)
        if completed.returncode:
            raise RuntimeError("worker_failed")
        return completed.stdout


def call_worker(request: dict, harness: str) -> dict:
    argv = worker_argv(harness)
    prompt = json.dumps(request, ensure_ascii=False)
    if harness == "codex" and not os.environ.get("BULK_READ_WORKER_ARGV"):
        prompt = PROMPT + "\n" + prompt
    started = time.monotonic()
    stdout = worker_output(harness, argv, prompt)
    log_worker_metric(harness, stdout, started)
    answer = worker_answer(harness, stdout)
    if not answer or len(answer.encode("utf-8")) > setting("BULK_READ_MAX_OUTPUT_BYTES", MAX_OUTPUT):
        raise RuntimeError("oversized_or_empty_output")
    return parse_worker_json(answer)


def valid_ranges(items: object, total: int, claims: bool) -> bool:
    if not isinstance(items, list):
        return False
    for item in items:
        if not isinstance(item, dict):
            return False
        if claims and (not isinstance(item.get("text"), str) or not item["text"].strip()):
            return False
        start, end = item.get("start_line"), item.get("end_line")
        if type(start) is not int or type(end) is not int or not (1 <= start <= end <= total):
            return False
    return True


def validate_map(answer: object, request: dict) -> dict:
    if not isinstance(answer, dict):
        raise RuntimeError("invalid_map")
    expected = {"path", "sha256", "claims", "coverage", "unknowns", "incomplete"}
    if set(answer) != expected or answer["path"] != request["path"] or answer["sha256"] != request["sha256"]:
        raise RuntimeError("invalid_map")
    if isinstance(answer["coverage"], dict):
        answer = {**answer, "coverage": [answer["coverage"]]}
    total = request["content"].count("\n") + int(bool(request["content"]) and not request["content"].endswith("\n"))
    if not valid_ranges(answer["claims"], total, True) or not valid_ranges(answer["coverage"], total, False):
        raise RuntimeError("invalid_map")
    if not isinstance(answer["unknowns"], list) or not all(isinstance(x, str) for x in answer["unknowns"]):
        raise RuntimeError("invalid_map")
    if type(answer["incomplete"]) is not bool:
        raise RuntimeError("invalid_map")
    return answer


def map_source(path: Path, harness: str, question: str | None = None) -> dict:
    source_bytes = path.read_bytes()
    if len(source_bytes) > setting("BULK_READ_MAX_INPUT_BYTES", MAX_INPUT):
        raise RuntimeError("oversized_input")
    content = source_bytes.decode("utf-8")
    digest = hashlib.sha256(source_bytes).hexdigest()
    request = {"path": str(path), "content": content, "sha256": digest, "question": question}
    answer = validate_map(call_worker(request, harness), request)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError("changed_source")
    return answer


def original_matches(path: Path, event: dict) -> bool:
    if event.get("tool_name") not in ("Read", "read", "Bash", "bash", "PowerShell", "powershell"):
        return True
    original = response_text(event)
    return original is None or path.read_bytes().decode("utf-8") == original


def route(event: dict) -> dict:
    try:
        path = eligible(event)
        if path is None:
            return {"replacement": None}
        if not original_matches(path, event):
            raise RuntimeError("changed_source")
        return {"replacement": map_source(path, event.get("harness", "unknown"))}
    except subprocess.TimeoutExpired:
        category = "timeout"
    except FileNotFoundError:
        category = "missing_worker"
    except (OSError, UnicodeError):
        category = "source_unavailable"
    except (ValueError, KeyError, IndexError, json.JSONDecodeError):
        category = "invalid_configuration_or_response"
    except RuntimeError as exc:
        category = str(exc)
    log_fallback(event, category)
    return {"replacement": None}


def main() -> int:
    if sys.argv[1:] == ["--route"]:
        try:
            event = json.load(sys.stdin)
            print(json.dumps(route(event), ensure_ascii=False))
            return 0
        except (json.JSONDecodeError, TypeError) as exc:
            print(f"context-read: invalid route event: {exc}", file=sys.stderr)
            return 2
    if len(sys.argv) >= 4 and sys.argv[1] == "--question":
        question, *paths = sys.argv[2:]
        harness = os.environ.get("BULK_READ_HARNESS", "claude")
        try:
            print(json.dumps([map_source(Path(path).resolve(), harness, question) for path in paths]))
            return 0
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
            print(f"context-read: {exc}", file=sys.stderr)
            return 1
    print("usage: context-read.py --route | --question QUESTION PATH...", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
