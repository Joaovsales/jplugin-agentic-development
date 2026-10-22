#!/usr/bin/env python3
"""arrange-plugin-eval-results.py — turn what `claude plugin eval` leaves into
the directory `grade-read-shunt.py` reads.

    arrange-plugin-eval-results.py <keep-temp> <aggregate-result.json> --arm NAME --out DIR [--side with|without]

The runner's results directory holds `aggregate-result.json` and `report.html`
only. A run's session transcript survives only when the suite ran with
`--keep-temp`, under `<TEMP>/claude-eval-<id>/config/projects/<cwd>/<session>.jsonl`
(sub-agents beside it under `<session>/subagents/`); the aggregate names each
run's `out/trace.jsonl` in that home as `tracePath`. `<keep-temp>` is the
directory holding the `claude-eval-<id>` homes, or one home itself — the home
every run's `tracePath` names, so an aggregate of several runs needs the parent.

For every run of every case on the chosen side of the ablation (default
`with`, the plugin build) this writes

    <out>/<arm>/<case>/run-<n>/transcript.jsonl
                              subagents/agent-*.jsonl   when the session had any
                              outcome.json              {"score": …} or {"pass": …}

from the run's own record: its `score`, else its `passed`. Every run is
checked before anything is written, so a missing temp home exits 2 with its
name and leaves `<out>` untouched, as does a run directory that already
exists.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import sys
from dataclasses import dataclass
from typing import List, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import read_transcript as rt  # noqa: E402


@dataclass
class ArrangedRun:
    case: str
    number: int
    transcript: str
    score: object
    passed: object


def _runs(aggregate_path: str, side: str) -> List[Tuple[str, List[dict]]]:
    with open(aggregate_path, encoding="utf-8") as fh:
        try:
            data = json.load(fh)
        except ValueError:
            raise rt.TranscriptError(f"{aggregate_path}:1: aggregate is not JSON")
    try:
        return [(case["name"], case["arms"][side]) for case in data["cases"]]
    except (KeyError, TypeError):
        raise rt.TranscriptError(f"{aggregate_path}:1: no cases[].arms.{side}[] — runner format changed")


def _home(keep_temp: str, trace_path: str) -> str:
    parts = trace_path.replace("\\", "/").split("/")
    if len(parts) < 3 or parts[-2] != "out":
        raise rt.TranscriptError(f"tracePath {trace_path!r} is not <temp home>/out/trace.jsonl")
    home_id = parts[-3]
    if os.path.basename(os.path.normpath(keep_temp)) == home_id:
        return keep_temp
    return os.path.join(keep_temp, home_id)


def _session(home: str) -> str:
    found = sorted(glob.glob(os.path.join(home, "config", "projects", "*", "*.jsonl")))
    if not found:
        raise rt.TranscriptError(f"{home}: no session transcript under config/projects — "
                                 "was the suite run with --keep-temp?")
    if len(found) > 1:
        raise rt.TranscriptError(f"{home}: {len(found)} session transcripts under config/projects, expected one")
    return found[0]


def plan(keep_temp: str, aggregate_path: str, side: str) -> List[ArrangedRun]:
    arranged: List[ArrangedRun] = []
    for case, runs in _runs(aggregate_path, side):
        if not case or "/" in case or "\\" in case or case in (".", ".."):
            raise rt.TranscriptError(f"{aggregate_path}: case name {case!r} is not a directory name")
        for number, run in enumerate(runs, 1):
            where = f"{aggregate_path}: {case} run-{number}"
            trace = run.get("tracePath")
            if not isinstance(trace, str):
                raise rt.TranscriptError(f"{where}: run has no tracePath")
            home = _home(keep_temp, trace)
            if not os.path.isdir(home):
                raise rt.TranscriptError(f"{where}: temp home {home} is gone — "
                                         "was the suite run with --keep-temp?")
            try:
                rt.outcome_record(score=run.get("score"), passed=run.get("passed"))
            except rt.TranscriptError as exc:
                raise rt.TranscriptError(f"{where}: {exc}")
            arranged.append(ArrangedRun(case, number, _session(home), run.get("score"), run.get("passed")))
    if not arranged:
        raise rt.EmptyRoot(aggregate_path)
    return arranged


def write(arranged: List[ArrangedRun], arm: str, out: str) -> None:
    for run in arranged:
        dest = os.path.join(out, arm, run.case, f"run-{run.number}")
        if os.path.exists(dest):
            raise rt.TranscriptError(f"{dest}: run directory exists — refusing to mix two runs")
    for run in arranged:
        dest = os.path.join(out, arm, run.case, f"run-{run.number}")
        os.makedirs(dest)
        shutil.copyfile(run.transcript, os.path.join(dest, rt.TRANSCRIPT_FILE))
        agents = os.path.join(os.path.splitext(run.transcript)[0], rt.SUBAGENTS_DIR)
        if os.path.isdir(agents):
            shutil.copytree(agents, os.path.join(dest, rt.SUBAGENTS_DIR))
        rt.write_outcome(dest, score=run.score, passed=run.passed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("keep_temp")
    parser.add_argument("aggregate")
    parser.add_argument("--arm", required=True, help="name of the arm these runs belong to")
    parser.add_argument("--out", required=True, help="results directory to write")
    parser.add_argument("--side", choices=("with", "without"), default="with")
    args = parser.parse_args()
    write(plan(args.keep_temp, args.aggregate, args.side), args.arm, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(rt.run(main))
