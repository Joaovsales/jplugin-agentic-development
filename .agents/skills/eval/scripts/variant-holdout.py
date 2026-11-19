#!/usr/bin/env python3
"""Hold variant-lift prompts out of tuning, and promote only on a holdout win.

  variant-holdout.py split <prompts.json> [--manifest <manifest.json>] [--json]
  variant-holdout.py verdict <manifest.json> <scores.jsonl> --expect <fingerprint> [--json]

prompts.json is a JSON array of prompt strings. scores.jsonl carries one graded
run per line: {"prompt": str, "arm": "unchanged"|"previous"|"candidate",
"score": number, "cost_usd": number (optional)}.

The split is a function of the prompt set: distinct prompts (whitespace
collapsed) sorted by SHA-256, the first half held out. Because the cut depends
on the whole set, adding or dropping a prompt moves it, so `split --manifest`
records the split-time set and prints its fingerprint. The orchestrator retains
that fingerprint outside the tuning loop before tuning starts; `verdict` requires
it via --expect. It refuses a replaced manifest, membership the rule does not
reproduce, and a scored prompt set that differs in either direction. Fewer than
four distinct prompts refuse. The verdict is promote only when the candidate's
holdout mean beats both baselines; a run without cost_usd makes its arm's cost unknown,
never zero.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import mean
import sys

import read_transcript as rt

ARMS = ("unchanged", "previous", "candidate")
BASELINES = ARMS[:2]
MIN_PROMPTS = 4
# A candidate a float ulp above a baseline ties it; the holdout must be beaten, not matched.
EPSILON = 1e-9


def normalise(prompt):
    return " ".join(prompt.split())


def split(prompts):
    distinct = sorted({normalise(p) for p in prompts},
                      key=lambda p: hashlib.sha256(p.encode("utf-8")).hexdigest())
    if len(distinct) < MIN_PROMPTS:
        raise rt.TranscriptError(
            f"{len(distinct)} distinct prompt(s); a holdout needs at least {MIN_PROMPTS} distinct prompts")
    cut = len(distinct) // 2
    return {"tuning": distinct[cut:], "holdout": distinct[:cut]}


def read_prompts(path):
    try:
        prompts = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise rt.TranscriptError(f"{path}: unreadable prompts: {exc}") from exc
    if not isinstance(prompts, list) or not all(isinstance(p, str) and p.strip() for p in prompts):
        raise rt.TranscriptError(f"{path}: expected a JSON array of non-empty strings")
    return prompts


def write_manifest(path, sets):
    try:
        with path.open("x", encoding="utf-8") as fh:
            fh.write(json.dumps(sets, indent=2) + "\n")
    except FileExistsError as exc:
        raise rt.TranscriptError(f"{path}: manifest already exists; a split is pinned once, before tuning") from exc
    except OSError as exc:
        raise rt.TranscriptError(f"{path}: cannot write manifest: {exc}") from exc


def manifest_fingerprint(sets):
    canonical = json.dumps(sets, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def read_manifest(path):
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise rt.TranscriptError(f"{path}: unreadable manifest: {exc}") from exc
    if not isinstance(manifest, dict) or not all(
            isinstance(manifest.get(name), list) and all(isinstance(p, str) and p.strip() for p in manifest[name])
            for name in ("tuning", "holdout")):
        raise rt.TranscriptError(f"{path}: expected a manifest with tuning and holdout arrays of non-empty strings")
    sets = split(manifest["tuning"] + manifest["holdout"])
    if any({normalise(p) for p in manifest[name]} != set(sets[name]) or len(manifest[name]) != len(sets[name])
           for name in sets):
        raise rt.TranscriptError(f"{path}: manifest membership does not match the split rule; re-run split, never edit it")
    return sets


def finite(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def read_scores(path):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise rt.TranscriptError(f"{path}: unreadable scores: {exc}") from exc
    records = []
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        where = f"{path}:{number}"
        try:
            record = json.loads(line)
        except ValueError as exc:
            raise rt.TranscriptError(f"{where}: not JSON: {exc}") from exc
        if not isinstance(record, dict):
            raise rt.TranscriptError(f"{where}: expected a JSON object")
        prompt, arm, cost = record.get("prompt"), record.get("arm"), record.get("cost_usd")
        if not isinstance(prompt, str) or not prompt.strip():
            raise rt.TranscriptError(f"{where}: prompt must be a non-empty string")
        if arm not in ARMS:
            raise rt.TranscriptError(f"{where}: unknown arm {arm!r}; expected one of {', '.join(ARMS)}")
        if not finite(record.get("score")):
            raise rt.TranscriptError(f"{where}: score must be a finite number")
        if cost is not None and not (finite(cost) and cost >= 0):
            raise rt.TranscriptError(f"{where}: cost_usd must be a finite nonnegative number")
        records.append({"prompt": normalise(prompt), "arm": arm,
                        "score": record["score"], "cost_usd": cost})
    return records


def judge(sets, records):
    pinned = sets["tuning"] + sets["holdout"]
    added = sorted({r["prompt"] for r in records} - set(pinned))
    if added:
        raise rt.TranscriptError(f"prompt {added[0]!r} is not in the manifest; a prompt added after the split moves it")
    runs = {}
    for r in records:
        runs.setdefault((r["prompt"], r["arm"]), []).append(r["score"])
    for prompt in pinned:
        if not any((prompt, arm) in runs for arm in ARMS):
            raise rt.TranscriptError(f"manifest prompt {prompt!r} has no scored runs; a prompt dropped after the split moves it")
        for arm in ARMS:
            if (prompt, arm) not in runs:
                raise rt.TranscriptError(f"prompt {prompt!r} has no {arm} run")
    # Average each prompt's runs first, so a prompt run twice weighs the same as one run once.
    means = {name: {arm: mean(mean(runs[p, arm]) for p in prompts) for arm in ARMS}
             for name, prompts in sets.items()}
    costs = {arm: "unknown" if any(r["cost_usd"] is None for r in records if r["arm"] == arm)
             else sum(r["cost_usd"] for r in records if r["arm"] == arm) for arm in ARMS}
    holdout = means["holdout"]
    lost = [b for b in BASELINES if not holdout["candidate"] > holdout[b] + EPSILON]
    return {"split": sets, "means": means, "cost_usd": costs,
            "verdict": "reject" if lost else "promote", "not_beaten": lost}


def verdict_line(result):
    holdout = result["means"]["holdout"]
    cand = f"holdout candidate {holdout['candidate']:.4f}"
    if result["verdict"] == "promote":
        return (f"Verdict: promote — {cand} beats unchanged {holdout['unchanged']:.4f}"
                f" and previous {holdout['previous']:.4f}")
    lost = " and ".join(f"{b} {holdout[b]:.4f}" for b in result["not_beaten"])
    return f"Verdict: reject — {cand} does not beat {lost}"


def money(cost):
    return cost if cost == "unknown" else f"{cost:.4f}"


def print_split(sets):
    for name in ("tuning", "holdout"):
        print(f"{name}:")
        for prompt in sets[name]:
            print(f"  {prompt}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    split_cmd = sub.add_parser("split")
    split_cmd.add_argument("path", type=Path, metavar="prompts.json")
    split_cmd.add_argument("--manifest", type=Path, metavar="manifest.json")
    verdict_cmd = sub.add_parser("verdict")
    verdict_cmd.add_argument("manifest", type=Path, metavar="manifest.json")
    verdict_cmd.add_argument("path", type=Path, metavar="scores.jsonl")
    verdict_cmd.add_argument("--expect", required=True, metavar="fingerprint")
    for command in (split_cmd, verdict_cmd):
        command.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.command == "split":
        sets = split(read_prompts(args.path))
        if args.manifest:
            write_manifest(args.manifest, sets)
        if args.json:
            print(json.dumps({**sets, "fingerprint": manifest_fingerprint(sets)}, indent=2))
        else:
            print(f"split: fingerprint {manifest_fingerprint(sets)}")
            print_split(sets)
        return
    sets = read_manifest(args.manifest)
    if manifest_fingerprint(sets) != args.expect:
        raise rt.TranscriptError("manifest fingerprint mismatch; use the fingerprint recorded before tuning")
    result = judge(sets, read_scores(args.path))
    if args.json:
        print(json.dumps(result, indent=2, allow_nan=False))
        return
    sets = result["split"]
    print(f"Split: {len(sets['tuning']) + len(sets['holdout'])} distinct prompts — "
          f"{len(sets['tuning'])} tuning, {len(sets['holdout'])} holdout "
          "(SHA-256 order; never tune on the holdout)")
    print_split(sets)
    print()
    print(rt.markdown_table(("Arm", "Tuning mean", "Holdout mean", "Cost USD"),
                            [[arm, f"{result['means']['tuning'][arm]:.4f}",
                              f"{result['means']['holdout'][arm]:.4f}", money(result["cost_usd"][arm])]
                             for arm in ARMS]))
    print()
    print(verdict_line(result))


if __name__ == "__main__":
    sys.exit(rt.run(main))
