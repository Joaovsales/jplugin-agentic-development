#!/usr/bin/env python3
"""Grade code-navigation runs from shared session transcripts and the frozen rule.

Layout: <results>/<arm>/<case>/run-<n>/{transcript.jsonl,outcome.json,metadata.json}.
Metadata records kind (localization/control), seed, status (completed/errored),
and cost_usd. Retries belong outside run-* directories; each planned run has one
final record. Errored runs remain visible but never make incomplete evidence go.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import math
from pathlib import Path
import shlex
from statistics import mean, median
import sys

import read_transcript as rt

METRICS = ("graph_calls", "lsp_calls", "grep_calls", "glob_calls", "read_calls",
           "total_tokens", "wall_seconds", "outcome")
RULE_NAMES = {1: "correctness", 2: "cost", 3: "control overhead", 4: "adoption",
              5: "latency", 6: "graceful degradation"}
EPSILON = 1e-9


def number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) \
            or not math.isfinite(value) or value < 0:
        raise rt.TranscriptError(f"{label}: expected a finite nonnegative number")
    return value


def metadata(path):
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise rt.TranscriptError(f"{path}: unreadable metadata: {exc}") from exc
    if not isinstance(record, dict) or record.get("kind") not in ("localization", "control") \
            or record.get("status") not in ("completed", "errored") \
            or isinstance(record.get("seed"), bool) or not isinstance(record.get("seed"), int):
        raise rt.TranscriptError(f"{path}: invalid kind, status or integer seed")
    number(record.get("cost_usd"), f"{path}: cost_usd")
    return record


def graph_command(command):
    """Recognise executable positions, excluding prose such as `echo graphify`."""
    if not isinstance(command, str):
        return False
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        words = list(lexer)
    except ValueError:
        return False
    executable = True
    wrapper = None
    skip_next = False
    wrappers = {"timeout", "env", "command", "nice", "nohup"}
    for word in words:
        if word and all(c in ";&|()\n" for c in word):
            executable = True
            wrapper = None
            skip_next = False
        elif executable:
            if skip_next:
                skip_next = False
                continue
            if word in ("if", "then", "elif", "else", "while", "until", "do"):
                continue
            name = word.rsplit("/", 1)[-1]
            if name == "graphify":
                return True
            if wrapper == "command" and word in ("-v", "-V"):
                executable = False
                continue
            if (wrapper == "env" and word in ("-u", "--unset")) or \
                    (wrapper == "timeout" and word in ("-s", "--signal", "-k", "--kill-after")):
                skip_next = True
                continue
            if name in wrappers:
                wrapper = name
                continue
            if "=" in word or word.startswith("-") \
                    or (word and word[0].isdigit()):
                continue
            executable = False
    return False


def grade_run(arm, case, run):
    info = metadata(run / "metadata.json")
    row = dict(arm=arm, case=case, run=run.name, **info)
    if info["status"] == "errored":
        return row
    transcript = run / rt.TRANSCRIPT_FILE
    try:
        session = rt.parse_session(str(transcript), rt.subagent_transcripts(str(run)))
        outcome = rt.read_outcome(str(run))
    except (OSError, ValueError) as exc:
        raise rt.TranscriptError(f"{run}: unreadable run evidence: {exc}") from exc
    if session.malformed:
        raise rt.TranscriptError(f"{transcript}: {session.malformed} malformed transcript record(s)")
    if outcome is None or not 0 <= number(outcome, f"{run}: outcome") <= 1:
        raise rt.TranscriptError(f"{run}: outcome must be recorded in [0,1]")
    parent = session.parent
    subtokens, _ = session.subagent_totals()
    if subtokens is None or parent.total_tokens <= 0:
        raise rt.TranscriptError(f"{run}: missing parent or sub-agent token evidence")
    try:
        first = datetime.fromisoformat(parent.first_timestamp.replace("Z", "+00:00"))
        last = datetime.fromisoformat(parent.last_timestamp.replace("Z", "+00:00"))
        seconds = (last - first).total_seconds()
    except (AttributeError, ValueError, TypeError) as exc:
        raise rt.TranscriptError(f"{run}: missing or invalid wall-time evidence") from exc
    number(seconds, f"{run}: wall_seconds")
    # Separate sub-agent files own their calls. Exclude duplicated inline turns
    # from the parent when those files are present; otherwise count inline uses.
    uses = [u for u in parent.tool_uses if not session.agents or not u.sidechain]
    uses += [u for agent in session.agents for u in agent.own_tool_uses()]
    row.update(graph_calls=sum(u.name == "Bash" and graph_command(u.input.get("command")) for u in uses),
               lsp_calls=sum(u.name.startswith("mcp__serena__") for u in uses),
               grep_calls=sum(u.name == "Grep" for u in uses),
               glob_calls=sum(u.name == "Glob" for u in uses),
               read_calls=sum(u.name == "Read" for u in uses),
               total_tokens=parent.total_tokens + subtokens, wall_seconds=seconds, outcome=outcome)
    return row


def read_runs(root, arms):
    rows = []
    for arm in arms:
        directory = root / arm
        if not directory.is_dir():
            raise rt.TranscriptError(f"{directory}: missing arm")
        for case in sorted(p for p in directory.iterdir() if p.is_dir()):
            for run in sorted(p for p in case.glob("run-*") if p.is_dir()):
                rows.append(grade_run(arm, case.name, run))
    if not rows:
        raise rt.EmptyRoot(str(root))
    # Pair both the case ids and each planned replicate's seed and case kind.
    maps = [{(r["case"], r["run"]): (r["seed"], r["kind"])
             for r in rows if r["arm"] == arm} for arm in arms]
    if any(mapping != maps[0] for mapping in maps[1:]):
        raise rt.TranscriptError("arms have unpaired cases, runs, seeds or kinds")
    for case in {r["case"] for r in rows}:
        if len({r["kind"] for r in rows if r["case"] == case}) != 1:
            raise rt.TranscriptError(f"{case}: inconsistent case kind")
    return rows


def paired_means(rows, arms):
    result = []
    for case in sorted({r["case"] for r in rows}):
        for arm in arms:
            completed = [r for r in rows if r["arm"] == arm and r["case"] == case
                         and r["status"] == "completed"]
            row = {"arm": arm, "case": case, "runs": len(completed)}
            row.update({key: mean(r[key] for r in completed) if completed else None for key in METRICS})
            result.append(row)
    return result


def verdict(rows, arms):
    cases = {r["case"] for r in rows}
    complete = all(len(planned := [r for r in rows if r["arm"] == arm and r["case"] == case]) == 3
                   and all(r["status"] == "completed" for r in planned)
                   for arm in arms for case in cases)
    complete = complete and {r["kind"] for r in rows} == {"localization", "control"}
    if not complete:
        return False, {}, ["incomplete"]
    groups = {(arm, kind): [r for r in rows if r["arm"] == arm and r["kind"] == kind]
              for arm in arms for kind in ("localization", "control")}
    a, b, d = (groups[(arm, "localization")] for arm in arms)
    ac, bc = (groups[(arm, "control")] for arm in arms[:2])

    def avg(group):
        return mean(r["outcome"] for r in group)

    def med(group, metric="total_tokens"):
        return median(r[metric] for r in group)

    def accuracy(group):
        return avg(group) + EPSILON >= avg(a) and all(
            sum(r["outcome"] for r in a if r["case"] == case)
            - sum(r["outcome"] for r in group if r["case"] == case) <= 1 + EPSILON
            for case in {r["case"] for r in a})

    rules = {
        1: accuracy(b),
        2: med(b) <= 0.85 * med(a) + EPSILON or
           (avg(b) + EPSILON >= avg(a) + 0.10 and med(b) <= 1.10 * med(a) + EPSILON),
        3: avg(bc) + EPSILON >= avg(ac) and med(bc) <= 1.15 * med(ac) + EPSILON,
        4: mean(bool(r["graph_calls"] or r["lsp_calls"]) for r in b) + EPSILON >= 0.60,
        5: med([r for r in rows if r["arm"] == arms[1]], "wall_seconds") <=
           1.30 * med([r for r in rows if r["arm"] == arms[0]], "wall_seconds") + EPSILON,
        6: accuracy(d) and med(d) <= 1.15 * med(a) + EPSILON,
    }
    return True, rules, [n for n, passed in rules.items() if not passed]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results_dir", type=Path)
    parser.add_argument("--control", default="A")
    parser.add_argument("--arm", choices=("B", "C"), required=True)
    parser.add_argument("--degraded", default="D")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    arms = (args.control, args.arm, args.degraded)
    if len(set(arms)) != 3:
        parser.error("control, treatment and degraded arm must differ")
    rows = read_runs(args.results_dir, arms)
    paired = paired_means(rows, arms)
    complete, rules, failed = verdict(rows, arms)
    result = {"runs": rows, "paired_means": paired, "complete": complete,
              "rules": rules, "failed_rules": failed, "verdict": "no-go" if failed else "go",
              "errored_runs": {arm: sum(r["arm"] == arm and r["status"] == "errored" for r in rows) for arm in arms},
              "total_spend_usd": sum(r["cost_usd"] for r in rows)}
    if args.json:
        print(json.dumps(result, indent=2, allow_nan=False))
        return
    headers = ("Arm", "Case", "Run", "Status", *METRICS, "cost_usd")
    keys = ("arm", "case", "run", "status", *METRICS, "cost_usd")
    print(rt.markdown_table(headers, [[str(row.get(k, "-")) for k in keys] for row in rows]))
    print("\n## Paired per-case means\n")
    print(rt.markdown_table(("Arm", "Case", "Runs", *METRICS),
                           [[str(row[k]) for k in ("arm", "case", "runs", *METRICS)] for row in paired]))
    print(f"\nErrored runs: {json.dumps(result['errored_runs'])}")
    print(f"Total spend: ${result['total_spend_usd']:.4f}")
    reason = "; ".join(f"rule {n} ({RULE_NAMES[n]})" if isinstance(n, int) else "incomplete evidence (N=3 required)" for n in failed)
    print(f"Verdict: {result['verdict']}" + (f" — {reason}" if reason else ""))


if __name__ == "__main__":
    sys.exit(rt.run(main))
