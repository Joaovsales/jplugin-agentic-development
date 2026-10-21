#!/usr/bin/env python3
"""grade-read-shunt.py — per-run read metrics and paired per-task means over an
eval results directory, from transcripts and never from what the candidate said
(specs/read-shunt-baseline.md § Behavior › Eval harness; /eval Mode C).

    grade-read-shunt.py <results-dir> [--bytes N] [--lines N] [--json]

The results directory is runner-neutral: one directory per arm, per task, per
run, each holding the run's main-loop transcript and what sat beside it —

    <results>/<arm>/<task>/<run>/
        *.jsonl                  the parent transcript (the first one, sorted)
        subagents/agent-*.jsonl  sub-agent transcripts, when any
        shunt.jsonl              the gate's decision log, when a gate ran
        outcome.json             {"score": 0..1} or {"pass": true|false}

`claude plugin eval` and the Workflow-based /eval Mode B both leave those
files; the arm is the plugin build the run carried, the task is the case.

One row per run: parent whole-file large reads; routing-around attempts (a
bare shell read of a large result, or a `Grep` with `-C` >= 50 or
`head_limit: 0` on a large file — D14); hook decisions and repeated identical
denied inputs when `shunt.jsonl` is present; bytes delivered into the parent;
the largest single result; the parent's final context; compactions; sub-agent
tokens and tool uses; wall time; re-read rate (parent reads of a path an
earlier `Agent` prompt or sub-agent result named); and the outcome the runner
recorded. Then per-task means per arm as paired rows, when more than one arm
is present. Exit 2 on a transcript the shared parser cannot read.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field, fields
from datetime import datetime
from typing import Dict, List, Optional, Set

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import read_transcript as rt  # noqa: E402

GREP_CONTEXT_FLOOR = 50
SHUNT_LOG = "shunt.jsonl"
OUTCOME_FILE = "outcome.json"

# (field, header, numeric). Hook columns are appended only when a shunt log exists.
COLUMNS = [
    ("arm", "Arm", False), ("task", "Task", False), ("run", "Run", False),
    ("whole_large", "Parent whole-file large", True), ("routing_around", "Routing-around", True),
    ("parent_bytes", "Bytes into parent", True), ("largest", "Largest result", True),
    ("final_context", "Final context", True), ("compactions", "Compactions", True),
    ("subagent_tokens", "Sub-agent tokens", True), ("subagent_tool_uses", "Sub-agent tool uses", True),
    ("wall_seconds", "Wall s", True), ("reread_rate", "Re-read rate", True), ("outcome", "Outcome", True),
]
HOOK_COLUMNS = [("hook_decisions", "Hook decisions", False), ("repeated_denies", "Repeated denies", True)]


@dataclass
class RunRow:
    arm: str
    task: str
    run: str
    whole_large: int = 0
    routing_around: int = 0
    parent_bytes: int = 0
    largest: int = 0
    final_context: Optional[int] = None
    compactions: int = 0
    subagent_tokens: Optional[int] = None
    subagent_tool_uses: int = 0
    wall_seconds: Optional[float] = None
    reread_rate: Optional[float] = None
    outcome: Optional[float] = None
    hook_decisions: Optional[str] = None
    repeated_denies: Optional[int] = None


@dataclass
class RunDir:
    arm: str
    task: str
    run: str
    path: str
    transcript: str
    subagents: List[str] = field(default_factory=list)


def discover(results: str) -> List[RunDir]:
    """<results>/<arm>/<task>/<run>/ with at least one *.jsonl at the run level."""
    runs: List[RunDir] = []
    if not os.path.isdir(results):
        raise rt.EmptyRoot(results)
    for arm in sorted(os.listdir(results)):
        arm_dir = os.path.join(results, arm)
        if not os.path.isdir(arm_dir):
            continue
        for task in sorted(os.listdir(arm_dir)):
            task_dir = os.path.join(arm_dir, task)
            if not os.path.isdir(task_dir):
                continue
            for run in sorted(os.listdir(task_dir)):
                run_dir = os.path.join(task_dir, run)
                if not os.path.isdir(run_dir):
                    continue
                transcripts = sorted(f for f in os.listdir(run_dir) if f.endswith(".jsonl") and f != SHUNT_LOG)
                if not transcripts:
                    continue
                agents_dir = os.path.join(run_dir, rt.SUBAGENTS_DIR)
                agents = sorted(os.path.join(agents_dir, a) for a in os.listdir(agents_dir)
                                if a.endswith(".jsonl")) if os.path.isdir(agents_dir) else []
                runs.append(RunDir(arm, task, run, run_dir, os.path.join(run_dir, transcripts[0]), agents))
    if not runs:
        raise rt.EmptyRoot(results)
    return runs


_PATH_TOKEN = re.compile(r"""[A-Za-z]:[\\/][^\s"'`<>|]+|/[^\s"'`<>|]+|[\w.\\/-]+\.[A-Za-z0-9]{1,8}""")
_LINE_SUFFIX = re.compile(r":\d+(?:-\d+)?$")


def _paths_in(text: str) -> Set[str]:
    """Path-like tokens of a prompt or a result, normalised, a `:line` or
    `:from-to` suffix dropped so `big.py:120-160` and `big.py` are one file."""
    return {rt.normalize_path(_LINE_SUFFIX.sub("", token.rstrip(".,;:)")))
            for token in _PATH_TOKEN.findall(text)}


def _agent_text(use: rt.ToolUse, result: Optional[rt.ToolResult]) -> str:
    parts = [str(use.input.get("prompt", ""))]
    if result is not None and isinstance(result.result, dict):
        content = result.result.get("content")
        if isinstance(content, list):
            parts += [str(p.get("text", "")) for p in content if isinstance(p, dict)]
        elif isinstance(content, str):
            parts.append(content)
    return "\n".join(parts)


def _seconds_between(first: Optional[str], last: Optional[str]) -> Optional[float]:
    if not first or not last:
        return None
    try:
        a = datetime.fromisoformat(first.replace("Z", "+00:00"))
        b = datetime.fromisoformat(last.replace("Z", "+00:00"))
    except ValueError:
        return None
    return round((b - a).total_seconds(), 1)


def _is_routing_grep(use: rt.ToolUse) -> bool:
    context = use.input.get("-C")
    return (isinstance(context, int) and context >= GREP_CONTEXT_FLOOR) or use.input.get("head_limit") == 0


def grade_run(run: RunDir, bytes_t: int, lines_t: int) -> RunRow:
    parent = rt.parse_transcript(run.transcript, is_subagent=False)
    row = RunRow(run.arm, run.task, run.run)
    row.parent_bytes = parent.tool_result_bytes()
    row.final_context = parent.final_context
    row.compactions = parent.compactions
    row.wall_seconds = _seconds_between(parent.first_timestamp, parent.last_timestamp)
    agents = [rt.parse_transcript(p, is_subagent=True) for p in run.subagents]
    large_paths: Set[str] = {r.norm_path for a in agents for r in a.reads() if r.is_large(bytes_t, lines_t)}
    named: Set[str] = set()
    rereads = 0
    tokens: Optional[int] = None
    tool_uses = 0
    reads = {r.tool_use.id: r for r in parent.reads()}
    for use in parent.tool_uses:
        result = parent.results.get(use.id)
        if use.sidechain:
            continue
        if result is not None and result.bytes > row.largest:
            row.largest = result.bytes
        if use.name == "Read":
            read = reads[use.id]
            if read.kind == "excluded":
                continue
            if read.is_large(bytes_t, lines_t):
                large_paths.add(read.norm_path)
                if read.kind == "whole":
                    row.whole_large += 1
            rereads += _was_named(read.norm_path, named)
        elif use.name == "Bash":
            files = rt.bare_shell_reads(str(use.input.get("command", "")))
            if files and result is not None:
                norms = [rt.normalize_path(f) for f in files]
                if result.bytes >= bytes_t or any(n in large_paths for n in norms):
                    row.routing_around += 1
                rereads += sum(_was_named(n, named) for n in norms)
        elif use.name == "Grep":
            target = rt.normalize_path(str(use.input.get("path", "")))
            if _is_routing_grep(use) and (target in large_paths or (result is not None and result.bytes >= bytes_t)):
                row.routing_around += 1
        elif use.name == "Agent":
            named |= _paths_in(_agent_text(use, result))
            if result is not None and isinstance(result.result, dict):
                if isinstance(result.result.get("totalTokens"), int):
                    tokens = (tokens or 0) + result.result["totalTokens"]
                if isinstance(result.result.get("totalToolUseCount"), int):
                    tool_uses += result.result["totalToolUseCount"]
    for agent in agents:
        named |= {r.norm_path for r in agent.reads() if r.kind != "excluded"}
        if not tool_uses:
            tool_uses += len(agent.tool_uses)
    row.subagent_tokens = tokens
    row.subagent_tool_uses = tool_uses
    files_named = {n for n in named if "/" in n or "." in n}
    row.reread_rate = round(rereads / len(files_named), 3) if files_named else None
    row.outcome = _outcome(run.path)
    _hook_columns(row, run.path)
    return row


def _was_named(norm: str, named: Set[str]) -> bool:
    """A named token is this path, or shares its basename — a prompt that says
    `big_module.py` names the parent's full-path read of it."""
    base = norm.rsplit("/", 1)[-1]
    return norm in named or any(n.rsplit("/", 1)[-1] == base for n in named)


def _outcome(run_dir: str) -> Optional[float]:
    path = os.path.join(run_dir, OUTCOME_FILE)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        try:
            data = json.load(fh)
        except ValueError:
            raise rt.TranscriptError(f"{path}:1: outcome.json is not JSON")
    if isinstance(data, dict):
        if isinstance(data.get("score"), (int, float)):
            return float(data["score"])
        if isinstance(data.get("pass"), bool):
            return 1.0 if data["pass"] else 0.0
    raise rt.TranscriptError(f"{path}:1: outcome.json has neither score nor pass")


def _hook_columns(row: RunRow, run_dir: str) -> None:
    path = os.path.join(run_dir, SHUNT_LOG)
    if not os.path.exists(path):
        return
    decisions: Dict[str, int] = {}
    denied: Dict[str, int] = {}
    with open(path, encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                raise rt.TranscriptError(f"{path}:{line_no}: shunt log line is not JSON")
            decision = entry.get("decision") if isinstance(entry, dict) else None
            if not isinstance(decision, str):
                raise rt.TranscriptError(f"{path}:{line_no}: shunt log entry has no decision")
            decisions[decision] = decisions.get(decision, 0) + 1
            if decision == "deny":
                key = json.dumps([entry.get("tool"), entry.get("input")], sort_keys=True)
                denied[key] = denied.get(key, 0) + 1
    row.hook_decisions = " ".join(f"{k}:{v}" for k, v in sorted(decisions.items())) or "none"
    row.repeated_denies = sum(v - 1 for v in denied.values() if v > 1)


def paired_means(rows: List[RunRow], numeric: List[str]) -> List[Dict[str, object]]:
    arms = sorted({r.arm for r in rows})
    if len(arms) < 2:
        return []
    means: List[Dict[str, object]] = []
    for task in sorted({r.task for r in rows}):
        for arm in arms:
            group = [r for r in rows if r.task == task and r.arm == arm]
            if not group:
                continue
            entry: Dict[str, object] = {"arm": arm, "task": task, "runs": len(group)}
            for key in numeric:
                values = [getattr(r, key) for r in group if getattr(r, key) is not None]
                entry[key] = round(sum(values) / len(values), 3) if values else None
            means.append(entry)
    return means


def _fmt(value: object) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def render_markdown(rows: List[RunRow], means: List[Dict[str, object]], columns: list) -> str:
    header = "| " + " | ".join(h for _, h, _ in columns) + " |"
    rule = "|" + "|".join("---" for _ in columns) + "|"
    out = ["## Runs", "", header, rule]
    out += ["| " + " | ".join(_fmt(getattr(r, k)) for k, _, _ in columns) + " |" for r in rows]
    if means:
        numeric = [(k, h) for k, h, n in columns if n]
        out += ["", "## Paired per-task means", "",
                "| Arm | Task | Runs | " + " | ".join(h for _, h in numeric) + " |",
                "|---|---|---|" + "|".join("---" for _ in numeric) + "|"]
        out += ["| " + " | ".join([str(m["arm"]), str(m["task"]), str(m["runs"])]
                                   + [_fmt(m.get(k)) for k, _ in numeric]) + " |" for m in means]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("results")
    parser.add_argument("--bytes", type=int, default=rt.DEFAULT_BYTES)
    parser.add_argument("--lines", type=int, default=rt.DEFAULT_LINES)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    rows = [grade_run(r, args.bytes, args.lines) for r in discover(args.results)]
    columns = COLUMNS + (HOOK_COLUMNS if any(r.repeated_denies is not None for r in rows) else [])
    numeric = [k for k, _, n in columns if n]
    means = paired_means(rows, numeric)
    if args.json:
        payload = {"results": args.results, "bytes": args.bytes, "lines": args.lines,
                   "runs": [{f.name: getattr(r, f.name) for f in fields(RunRow)} for r in rows],
                   "paired_means": means}
        text = json.dumps(payload, indent=2)
    else:
        text = render_markdown(rows, means, columns)
    sys.stdout.buffer.write((text + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(rt.run(main))
