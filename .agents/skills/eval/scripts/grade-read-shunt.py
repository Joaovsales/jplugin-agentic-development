#!/usr/bin/env python3
"""grade-read-shunt.py — per-run read metrics and paired per-task means over an
eval results directory, from transcripts and never from what the candidate said
(specs/read-shunt-baseline.md § Behavior › Eval harness; /eval Mode C).

    grade-read-shunt.py <results-dir> [--bytes N] [--lines N] [--json]

The results directory is runner-neutral: one directory per arm, per task, per
run, each holding the run's main-loop transcript and what sat beside it —

    <results>/<arm>/<task>/<run>/
        transcript.jsonl         the parent transcript
        subagents/agent-*.jsonl  sub-agent transcripts, when any
        shunt.jsonl              the gate's decision log, when a gate ran
        outcome.json             {"score": 0..1} or {"pass": true|false}

`claude plugin eval` does not leave that layout: its results directory holds
only `aggregate-result.json` and `report.html`, and a run's session transcript
survives only under `--keep-temp`. `arrange-plugin-eval-results.py` builds the
layout from the kept temp homes and the aggregate; the arm is the plugin build
the run carried, the task is the case.

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
from dataclasses import MISSING, dataclass, field, fields
from datetime import datetime
from typing import Dict, List, Optional, Set, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import read_transcript as rt  # noqa: E402

GREP_CONTEXT_FLOOR = 50


def _column(label: str, numeric: bool = True, hook: bool = False, default: object = MISSING):
    """A RunRow field and its table column: header, whether the paired means
    average it, and whether it only appears when a shunt log exists."""
    return field(default=default, metadata={"label": label, "numeric": numeric, "hook": hook})


@dataclass
class RunRow:
    arm: str = _column("Arm", numeric=False)
    task: str = _column("Task", numeric=False)
    run: str = _column("Run", numeric=False)
    whole_large: int = _column("Parent whole-file large", default=0)
    routing_around: int = _column("Routing-around", default=0)
    parent_bytes: int = _column("Bytes into parent", default=0)
    largest: int = _column("Largest result", default=0)
    final_context: Optional[int] = _column("Final context", default=None)
    compactions: int = _column("Compactions", default=0)
    subagent_tokens: Optional[int] = _column("Sub-agent tokens", default=None)
    subagent_tool_uses: int = _column("Sub-agent tool uses", default=0)
    wall_seconds: Optional[float] = _column("Wall s", default=None)
    reread_rate: Optional[float] = _column("Re-read rate", default=None)
    outcome: Optional[float] = _column("Outcome", default=None)
    hook_decisions: Optional[str] = _column("Hook decisions", numeric=False, hook=True, default=None)
    repeated_denies: Optional[int] = _column("Repeated denies", hook=True, default=None)


def _columns(hook: bool) -> List[Tuple[str, str, bool]]:
    return [(f.name, f.metadata["label"], f.metadata["numeric"]) for f in fields(RunRow)
            if f.metadata["hook"] == hook]


# (field, header, numeric). Hook columns are appended only when a shunt log exists.
COLUMNS = _columns(hook=False)
HOOK_COLUMNS = _columns(hook=True)


@dataclass
class RunDir:
    arm: str
    task: str
    run: str
    path: str
    transcript: str
    subagents: List[str] = field(default_factory=list)


def discover(results: str) -> List[RunDir]:
    """<results>/<arm>/<task>/<run>/ holding a transcript.jsonl."""
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
                transcript = os.path.join(run_dir, rt.TRANSCRIPT_FILE)
                if not os.path.isfile(transcript):
                    continue
                runs.append(RunDir(arm, task, run, run_dir, transcript, rt.subagent_transcripts(run_dir)))
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


def _seconds_between(first: Optional[str], last: Optional[str]) -> Optional[float]:
    if not first or not last:
        return None
    try:
        a = datetime.fromisoformat(first.replace("Z", "+00:00"))
        b = datetime.fromisoformat(last.replace("Z", "+00:00"))
    except ValueError:
        return None
    return round((b - a).total_seconds(), 1)


def _is_routing_grep(grep: rt.GrepCall) -> bool:
    context = grep.context_lines
    return (context is not None and context >= GREP_CONTEXT_FLOOR) or grep.head_limit == 0


def grade_run(run: RunDir, th: rt.Thresholds) -> RunRow:
    parent = rt.parse_transcript(run.transcript, is_subagent=False)
    row = RunRow(run.arm, run.task, run.run)
    row.parent_bytes = parent.tool_result_bytes()
    row.final_context = parent.final_context
    row.compactions = parent.compactions
    row.wall_seconds = _seconds_between(parent.first_timestamp, parent.last_timestamp)
    agents = [rt.parse_transcript(p, is_subagent=True) for p in run.subagents]
    sidechain_reads = [*parent.sidechain_reads(), *(r for a in agents for r in a.sidechain_reads())]
    large_paths: Set[str] = {r.norm_path for r in sidechain_reads if r.is_large(th)}
    named: Set[str] = set()
    rereads = 0
    tokens: Optional[int] = None
    for use in parent.parent_tool_uses():
        result = parent.results.get(use.id)
        if result is not None and result.bytes > row.largest:
            row.largest = result.bytes
    for call in parent.parent_calls():
        if isinstance(call, rt.Read):
            if call.is_excluded:
                continue
            if call.is_large(th):
                large_paths.add(call.norm_path)
            if call.is_whole_large(th):
                row.whole_large += 1
            rereads += _was_named(call.norm_path, named)
        elif isinstance(call, rt.ShellRead):
            if call.bytes >= th.bytes or any(n in large_paths for n in call.paths):
                row.routing_around += 1
            rereads += sum(_was_named(n, named) for n in call.paths)
        elif isinstance(call, rt.GrepCall):
            if _is_routing_grep(call) and (call.target in large_paths
                                           or (call.bytes is not None and call.bytes >= th.bytes)):
                row.routing_around += 1
        elif isinstance(call, rt.AgentCall):
            named |= _paths_in(call.named_text)
            if call.total_tokens is not None:
                tokens = (tokens or 0) + call.total_tokens
    named |= {r.norm_path for r in sidechain_reads if not r.is_excluded}
    counted = [c.tool_use_count for c in parent.agent_calls() if c.tool_use_count is not None]
    row.subagent_tokens = tokens
    row.subagent_tool_uses = sum(counted) if counted else sum(len(a.tool_uses) for a in agents)
    row.reread_rate = round(rereads / len(named), 3) if named else None
    row.outcome = rt.read_outcome(run.path)
    _hook_columns(row, run.path)
    return row


def _was_named(norm: str, named: Set[str]) -> bool:
    """A named token is this path, or shares its basename — a prompt that says
    `big_module.py` names the parent's full-path read of it."""
    base = norm.rsplit("/", 1)[-1]
    return norm in named or any(n.rsplit("/", 1)[-1] == base for n in named)


def _hook_columns(row: RunRow, run_dir: str) -> None:
    path = os.path.join(run_dir, rt.SHUNT_LOG)
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
    th = rt.Thresholds(args.bytes, args.lines)
    rows = [grade_run(r, th) for r in discover(args.results)]
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
