#!/usr/bin/env python3
"""Noise-controlled measurement for /perf (specs/perf-audit-and-debug.md).

A number is a measurement only when it is several runs of one repeatable
command, summarised as min, median, max and spread. Everything here refuses
less, so a single-run figure never reaches an audit report or a PR body.

    measure.py run --runs N [--warmup W] [--timeout S] -- <command ...>
    measure.py summarize --unit <unit> --command '<what produced them>' <sample ...>
    measure.py compare <baseline.json> <after.json> [--expected X] [--format json|markdown]

Exit 0 on success, 1 when the measured command fails, 2 on a refused input.
"""

from __future__ import annotations

import argparse
import json
import shlex
import statistics
import subprocess
import sys
import time
from typing import List, Sequence

MIN_RUNS = 5
DEFAULT_RUNS = 10

IMPROVED = "improved"
WITHIN_NOISE = "within-noise"
REGRESSED = "regressed"


class Refused(Exception):
    """An input that is not a measurement. Exit 2."""


class CommandFailed(Exception):
    """The measured command exited non-zero. Exit 1."""


def summary(command: str, unit: str, samples: Sequence[float], warmup: int = 0) -> dict:
    """The one summary shape every subcommand emits and every reader accepts."""
    if len(samples) < MIN_RUNS:
        raise Refused(
            f"{len(samples)} run(s) is not a measurement: take at least {MIN_RUNS} "
            "runs of the same command and report min, median and spread"
        )
    samples = [round(s, 3) for s in samples]
    low, high, mid = min(samples), max(samples), round(statistics.median(samples), 3)
    spread = round(high - low, 3)
    return {
        "command": command,
        "unit": unit,
        "runs": len(samples),
        "warmup": warmup,
        "samples": samples,
        "min": low,
        "median": mid,
        "max": high,
        "spread": spread,
        "spread_pct": round(spread / mid * 100, 1) if mid else 0.0,
    }


def check_summary(data: dict, label: str = "measurement") -> None:
    """Refuse a summary that is not N >= MIN_RUNS samples agreeing with its own numbers."""
    samples = data.get("samples")
    if not isinstance(samples, list) or not all(isinstance(s, (int, float)) for s in samples):
        raise Refused(f"{label}: no numeric `samples` list — not a measurement")
    if data.get("runs") != len(samples):
        raise Refused(f"{label}: runs={data.get('runs')} but {len(samples)} samples")
    expected = summary(str(data.get("command", "")), str(data.get("unit", "")), samples)
    for key in ("min", "median", "max", "spread"):
        if key not in data or abs(float(data[key]) - expected[key]) > 1e-3:
            raise Refused(
                f"{label}: {key}={data.get(key)} does not match its samples "
                f"({expected[key]}) — numbers are computed, never typed"
            )
    if not data.get("command"):
        raise Refused(f"{label}: no `command` — a number without its command is not repeatable")


def run_command(argv: List[str], runs: int, warmup: int, timeout: float) -> dict:
    if not argv:
        raise Refused("no command given after `--`")
    if runs < MIN_RUNS:
        raise Refused(
            f"--runs {runs} is not a measurement: use at least {MIN_RUNS} runs"
        )
    samples: List[float] = []
    for index in range(warmup + runs):
        start = time.perf_counter_ns()
        try:
            done = subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=timeout)
        except FileNotFoundError:
            raise Refused(f"command not found: {argv[0]}") from None
        except subprocess.TimeoutExpired:
            raise CommandFailed(f"run {index + 1 - warmup} timed out after {timeout} s") from None
        elapsed_ms = (time.perf_counter_ns() - start) / 1e6
        if done.returncode != 0:
            label = f"warmup {index + 1}" if index < warmup else f"run {index + 1 - warmup}"
            tail = done.stderr.decode("utf-8", "replace").strip().splitlines()[-1:] or [""]
            raise CommandFailed(
                f"{label} exited {done.returncode}: a failing run's time is not a measurement. {tail[0]}".rstrip()
            )
        if index >= warmup:
            samples.append(elapsed_ms)
    return summary(shlex.join(argv), "ms", samples, warmup)


def verdict(baseline: dict, after: dict) -> str:
    """`improved` only when every after run beats every baseline run; the mirror is `regressed`.

    Disjoint ranges are the noise rule: for two batches of one unchanged
    command they happen by chance once in C(2N, N) — 1 in 252 at N = 5, 1 in
    184756 at N = 10 — while a median compared against the other batch's range
    is fooled by ordinary drift between batches.
    """
    if after["max"] < baseline["min"]:
        return IMPROVED
    if after["min"] > baseline["max"]:
        return REGRESSED
    return WITHIN_NOISE


def compare(baseline: dict, after: dict, expected) -> dict:
    check_summary(baseline, "baseline")
    check_summary(after, "after")
    for key, words in (("command", "same command"), ("unit", "same unit"), ("runs", "same number of runs")):
        if baseline.get(key) != after.get(key):
            raise Refused(
                f"baseline and after differ in {key} ({baseline.get(key)!r} vs {after.get(key)!r}): "
                f"compare the {words} or the numbers are not comparable"
            )
    return {"verdict": verdict(baseline, after), "expected": expected, "baseline": baseline, "after": after}


def _cell(data: dict) -> str:
    return f"{data['median']:g} {data['unit']} (min {data['min']:g}, spread {data['spread']:g}, n={data['runs']})"


def markdown(result: dict) -> str:
    base, after = result["baseline"], result["after"]
    expected = "—" if result["expected"] is None else f"{result['expected']:g} {base['unit']}"
    note = {
        IMPROVED: "every after run is faster than every baseline run",
        WITHIN_NOISE: "inside the baseline's noise band — not an improvement",
        REGRESSED: "every after run is slower than every baseline run",
    }[result["verdict"]]
    return "\n".join([
        f"Command: `{base['command']}`",
        "",
        "| Baseline | Expected | After | Verdict |",
        "|---|---|---|---|",
        f"| {_cell(base)} | {expected} | {_cell(after)} | {result['verdict']} — {note} |",
        "",
    ])


def _load(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        raise Refused(f"{path}: {error}") from None


def _number(text: str) -> float:
    try:
        return float(text)
    except ValueError:
        raise Refused(f"sample {text!r} is not a number") from None


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="measure.py", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_run = sub.add_parser("run", help="time a command N times")
    p_run.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    p_run.add_argument("--warmup", type=int, default=1)
    p_run.add_argument("--timeout", type=float, default=600.0)
    p_run.add_argument("argv", nargs=argparse.REMAINDER)
    p_sum = sub.add_parser("summarize", help="summarise samples another tool produced")
    p_sum.add_argument("--unit", required=True)
    p_sum.add_argument("--command", required=True)
    p_sum.add_argument("samples", nargs="*")
    p_cmp = sub.add_parser("compare", help="baseline vs after, with the noise-band verdict")
    p_cmp.add_argument("baseline")
    p_cmp.add_argument("after")
    p_cmp.add_argument("--expected", type=float)
    p_cmp.add_argument("--format", choices=("json", "markdown"), default="json")
    return parser


def main(argv=None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.cmd == "run":
            command = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
            print(json.dumps(run_command(command, args.runs, args.warmup, args.timeout), indent=2))
        elif args.cmd == "summarize":
            samples = [_number(s) for s in args.samples]
            print(json.dumps(summary(args.command, args.unit, samples), indent=2))
        else:
            result = compare(_load(args.baseline), _load(args.after), args.expected)
            print(markdown(result) if args.format == "markdown" else json.dumps(result, indent=2))
    except Refused as error:
        print(f"measure.py: refused: {error}", file=sys.stderr)
        return 2
    except CommandFailed as error:
        print(f"measure.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
