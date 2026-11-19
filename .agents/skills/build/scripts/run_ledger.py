#!/usr/bin/env python3
"""run_ledger.py — one durable record per build or rework run (specs/run-ledger.md).

    run_ledger.py record --branch B --base SHA [--run-id ID] [--spec PATH] [--pr N]
                         [--parent RUN_ID] [--model TIER=NAME]...
                         [--slice "<id> attempts=<n> <outcome line>"]...
                         [--tokens N|unknown] [--cost USD|unknown] [--ledger DIR]
    run_ledger.py decide --run-id ID --result merged|changes_requested|closed [--ledger DIR]
    run_ledger.py last   --branch B [--ledger DIR]
    run_ledger.py stats  [--ledger DIR]

Each run is `<ledger>/<run-id>.json` (default ledger `tasks/runs`). The default
run id is `<branch slug>-<base SHA[:12]>`, so recording the same run again
lands on the same file. `record` has no option that sets the human result:
only `decide` does, and `merged` and `closed` are final. Missing tokens or cost
are stored as "unknown", never 0. `stats` derives every total from the records.

Exit status: 0 done; 1 refused (a final decision, an unknown run, a malformed
record, no run on the branch); 2 usage.
Only `last: no run on branch <branch> in <ledger>` means an absent run;
other exit-1 diagnostics are ledger errors.
"""

from __future__ import annotations

import argparse
import errno
import json
import math
import os
import re
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Sequence

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slice_outcome import FALSE, TRUE, UNKNOWN, derive  # noqa: E402

SCHEMA = "run-ledger/1"
DEFAULT_LEDGER = "tasks/runs"
UNKNOWN_VALUE = "unknown"
RESULTS = ("merged", "changes_requested", "closed")
FINAL = ("merged", "closed")
OUTCOME_VALUES = (TRUE, FALSE, UNKNOWN)
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SHA_RE = re.compile(r"^[0-9a-fA-F]{7,64}$")
LOCK_TIMEOUT = 10


class Refused(Exception):
    """An expected refusal: printed as one line, exit 1."""


# --------------------------------------------------------------------------
# Argument parsing

def _run_id(value: str) -> str:
    if not RUN_ID_RE.match(value):
        raise argparse.ArgumentTypeError(f"run id {value!r} must match {RUN_ID_RE.pattern}")
    return value


def _sha(value: str) -> str:
    if not SHA_RE.match(value):
        raise argparse.ArgumentTypeError(f"--base {value!r} is not a commit SHA")
    return value


# Public argparse types for scripts that write into the ledger (candidates.py).
run_id_arg, sha_arg = _run_id, _sha


def _positive_int(value: str) -> int:
    if not value.isdigit() or int(value) < 1:
        raise argparse.ArgumentTypeError(f"--pr {value!r} is not a positive integer")
    return int(value)


def _tokens(value: str):
    if value == UNKNOWN_VALUE:
        return value
    if not value.isdigit():
        raise argparse.ArgumentTypeError(f"--tokens {value!r} is not a non-negative integer or 'unknown'")
    return int(value)


def _cost(value: str):
    if value == UNKNOWN_VALUE:
        return value
    try:
        cost = float(value)
    except ValueError:
        cost = -1.0
    if not cost >= 0 or cost == float("inf"):
        raise argparse.ArgumentTypeError(f"--cost {value!r} is not a non-negative number or 'unknown'")
    return cost


def _model(value: str) -> List[str]:
    tier, sep, name = value.partition("=")
    if not sep or not tier.strip() or not name.strip():
        raise argparse.ArgumentTypeError(f"--model {value!r} is not TIER=NAME")
    return [tier.strip(), name.strip()]


def _slice(value: str) -> Dict[str, object]:
    """`<id> attempts=<n> agent_result=… verification_result=… slice_result=… <LABEL>`."""
    parts = value.split()
    if len(parts) != 6:
        raise argparse.ArgumentTypeError(
            f"--slice {value!r} is not '<id> attempts=<n> <outcome line>'")
    sid, label = parts[0], parts[5]
    fields = dict(p.partition("=")[::2] for p in parts[1:5])
    keys = ("attempts", "agent_result", "verification_result", "slice_result")
    if sorted(fields) != sorted(keys):
        raise argparse.ArgumentTypeError(f"--slice {value!r} needs {', '.join(keys)}")
    attempts = fields["attempts"]
    if not attempts.isdigit() or int(attempts) < 1:
        raise argparse.ArgumentTypeError(f"--slice {value!r}: attempts must be at least 1")
    for key in keys[1:]:
        if fields[key] not in OUTCOME_VALUES:
            raise argparse.ArgumentTypeError(f"--slice {value!r}: {key} must be one of {', '.join(OUTCOME_VALUES)}")
    expected = derive(fields["agent_result"], fields["verification_result"])
    if (fields["slice_result"], label) != expected:
        raise argparse.ArgumentTypeError(
            f"--slice {value!r}: slice_result={fields['slice_result']} {label} does not follow from "
            f"agent_result and verification_result (slice_outcome.derive gives {' '.join(expected)})")
    return {"id": sid, "attempts": int(attempts), "agent_result": fields["agent_result"],
            "verification_result": fields["verification_result"],
            "slice_result": fields["slice_result"], "label": label}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="run_ledger.py", allow_abbrev=False,
                                     description="Record build runs and derive their totals.")
    sub = parser.add_subparsers(dest="command", required=True)

    rec = sub.add_parser("record", allow_abbrev=False, help="record or update one run")
    rec.add_argument("--branch", required=True)
    rec.add_argument("--base", required=True, type=_sha)
    rec.add_argument("--run-id", type=_run_id)
    rec.add_argument("--spec")
    rec.add_argument("--pr", type=_positive_int)
    rec.add_argument("--parent", type=_run_id)
    rec.add_argument("--model", type=_model, action="append")
    rec.add_argument("--slice", type=_slice, action="append")
    rec.add_argument("--tokens", type=_tokens)
    rec.add_argument("--cost", type=_cost)

    dec = sub.add_parser("decide", allow_abbrev=False, help="record the human result of a run's PR")
    dec.add_argument("--run-id", required=True, type=_run_id)
    dec.add_argument("--result", required=True, choices=RESULTS)

    last = sub.add_parser("last", allow_abbrev=False, help="print the newest run id on a branch")
    last.add_argument("--branch", required=True)

    sub.add_parser("stats", allow_abbrev=False, help="print the derived totals")
    for p in sub.choices.values():
        p.add_argument("--ledger", type=Path, default=Path(DEFAULT_LEDGER))
    return parser


# --------------------------------------------------------------------------
# Storage

def _slug(branch: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", branch).strip("-.") or "run"


def load_record(path: Path) -> Dict[str, object]:
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise Refused(f"run-ledger: {path}: unreadable record — {exc}") from exc
    if not isinstance(record, dict) or record.get("schema") != SCHEMA:
        raise Refused(f"run-ledger: {path}: schema is not {SCHEMA}")
    if record.get("run_id") != path.stem:
        raise Refused(f"run-ledger: {path}: run_id {record.get('run_id')!r} does not match the file name")
    for field in ("branch", "recorded_at"):
        if not isinstance(record.get(field), str):
            raise Refused(f"run-ledger: {path}: invalid {field} — expected a string")
    parent = record.get("parent_run_id")
    if ("parent_run_id" not in record or
            (parent is not None and (not isinstance(parent, str) or not RUN_ID_RE.fullmatch(parent)))):
        raise Refused(f"run-ledger: {path}: invalid parent_run_id")
    current = record.get("human_result")
    decisions = record.get("decisions")
    if ("human_result" not in record or current not in (None, *RESULTS)
            or not isinstance(decisions, list) or any(d not in RESULTS for d in decisions)
            or (decisions[-1] if decisions else None) != current
            or any(d in FINAL for d in decisions[:-1])
            or any(a == b for a, b in zip(decisions, decisions[1:]))):
        raise Refused(f"run-ledger: {path}: invalid human_result or decisions history")
    for field in ("tokens", "cost_usd"):
        value = record.get(field)
        numeric = type(value) is int or (field == "cost_usd" and type(value) is float)
        if value != UNKNOWN_VALUE and not (numeric and value >= 0 and
                                          (type(value) is int or math.isfinite(value))):
            raise Refused(f"run-ledger: {path}: invalid {field} — expected a finite non-negative "
                          f"{'integer' if field == 'tokens' else 'number'} or 'unknown'")
    if not isinstance(record.get("candidates", {}), dict):
        raise Refused(f"run-ledger: {path}: invalid candidates — expected an object keyed by slice")
    return record


@contextmanager
def run_lock(path: Path):
    """Lock the entire transaction; kernel locks release even when a writer dies.

    Unix uses flock, Windows uses a one-byte msvcrt lock. Keep the lock file:
    unlinking it lets waiters and new arrivals lock different inodes.
    """
    lock_path = path.with_suffix(".lock")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+b") as handle:
            if os.name == "nt":
                import msvcrt
                def acquire():
                    # Windows permits byte-range locks beyond EOF, including empty files.
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                def acquire():
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            deadline = time.monotonic() + LOCK_TIMEOUT
            while True:
                try:
                    acquire()
                    break
                except OSError as exc:
                    if exc.errno not in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                        raise
                    if time.monotonic() >= deadline:
                        raise Refused(f"run-ledger: {lock_path}: timed out waiting for run lock") from exc
                    time.sleep(.05)
            try:
                yield
            finally:
                if os.name == "nt":
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    except OSError as exc:
        raise Refused(f"run-ledger: {lock_path}: storage error — {exc}") from exc


def write_record(ledger: Path, record: Dict[str, object]) -> None:
    ledger.mkdir(parents=True, exist_ok=True)
    text = json.dumps(record, indent=2, sort_keys=True) + "\n"
    fd, tmp = tempfile.mkstemp(dir=ledger, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp, ledger / f"{record['run_id']}.json")
    except BaseException:
        os.unlink(tmp)
        raise


def load_ledger(ledger: Path) -> List[Dict[str, object]]:
    if not ledger.exists():
        return []
    if not ledger.is_dir():
        raise Refused(f"run-ledger: {ledger}: not a ledger directory")
    # A run id never starts with ".", so a dot-file is a write's leftover temp, not a record.
    return [load_record(path) for path in sorted(ledger.glob("*.json")) if not path.name.startswith(".")]


# --------------------------------------------------------------------------
# Commands

def default_run_id(branch: str, base: str) -> str:
    return f"{_slug(branch)}-{base[:12]}"


def _stored_or_new(path: Path, run_id: str) -> Dict[str, object]:
    """The stored record, validated by load_record, or a new one. Call under run_lock."""
    return load_record(path) if path.exists() else {
        "schema": SCHEMA, "run_id": run_id, "spec": None, "pr": None, "parent_run_id": None,
        "models": {}, "slices": [], "tokens": UNKNOWN_VALUE, "cost_usd": UNKNOWN_VALUE,
        "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "human_result": None, "decisions": [],
    }


def add_candidates(ledger: Path, branch: str, base: str, run_id: Optional[str],
                   slice_id: str, entries: List[Dict[str, object]]) -> str:
    """Write one slice's ranked candidates (candidates.py rank) into the run record.

    Same transaction as `record`: one run lock around read, merge and write.
    `candidates` is not a `record` option, so a later `record` keeps it."""
    run_id = run_id or default_run_id(branch, base)
    if not RUN_ID_RE.fullmatch(run_id) or not SHA_RE.fullmatch(base):
        raise Refused(f"run-ledger: refused candidates for run {run_id!r} at base {base!r}")
    path = ledger / f"{run_id}.json"
    with run_lock(path):
        stored = _stored_or_new(path, run_id)
        record = {"branch": branch, "base_sha": base, **stored,
                  "candidates": {**stored.get("candidates", {}), slice_id: entries}}
        write_record(ledger, record)
    return run_id


def cmd_record(args: argparse.Namespace) -> int:
    run_id = args.run_id or default_run_id(args.branch, args.base)
    if args.parent == run_id:
        print(f"run_ledger.py record: error: run {run_id} cannot be its own parent", file=sys.stderr)
        return 2
    path = args.ledger / f"{run_id}.json"
    given = {
        "branch": args.branch, "base_sha": args.base, "spec": args.spec, "pr": args.pr,
        "parent_run_id": args.parent,
        "models": dict(args.model) if args.model else None,
        "slices": args.slice, "tokens": args.tokens, "cost_usd": args.cost,
    }
    # An option left out keeps the stored value; the human fields are not options.
    with run_lock(path):
        stored = _stored_or_new(path, run_id)
        record = {**stored, **{k: v for k, v in given.items() if v is not None}}
        write_record(args.ledger, record)
    print(f"record: recorded {run_id}")
    return 0


def cmd_decide(args: argparse.Namespace) -> int:
    path = args.ledger / f"{args.run_id}.json"
    with run_lock(path):
        if not path.exists():
            raise Refused(f"decide: no run {args.run_id} in {args.ledger}")
        record = load_record(path)
        current = record["human_result"]
        if current == args.result:
            print(f"decide: unchanged {args.run_id} {current}")
            return 0
        if current in FINAL:
            raise Refused(f"decide: refused {args.run_id} — already {current}, "
                          "a final human decision is never overwritten")
        record = {**record, "human_result": args.result,
                  "decisions": [*record["decisions"], args.result]}
        write_record(args.ledger, record)
    print(f"decide: recorded {args.run_id} {args.result}")
    return 0


def cmd_last(args: argparse.Namespace) -> int:
    runs = [r for r in load_ledger(args.ledger) if r.get("branch") == args.branch]
    if not runs:
        raise Refused(f"last: no run on branch {args.branch} in {args.ledger}")
    print(max(runs, key=lambda r: (r.get("recorded_at", ""), r["run_id"]))["run_id"])
    return 0


def _root(run_id: str, by_id: Dict[str, Dict[str, object]]) -> str:
    seen = [run_id]
    while True:
        parent = by_id[seen[-1]].get("parent_run_id")
        if parent is None or parent not in by_id:
            return seen[-1]
        if parent in seen:
            raise Refused(f"run-ledger: parent cycle through {', '.join(sorted(seen))}")
        seen.append(parent)


def _chains(records: List[Dict[str, object]]) -> List[List[Dict[str, object]]]:
    by_id = {r["run_id"]: r for r in records}
    chains: Dict[str, List[Dict[str, object]]] = {}
    for run_id in sorted(by_id):
        chains.setdefault(_root(run_id, by_id), []).append(by_id[run_id])
    return list(chains.values())


def _outcome(chain: List[Dict[str, object]]) -> str:
    results = {r.get("human_result") for r in chain}
    return "merged" if "merged" in results else "closed" if "closed" in results else "open"


def _per_pr(merged: List[List[Dict[str, object]]], field: str, label: str, fmt: str) -> str:
    if not merged:
        return "unknown — no merged PRs"
    missing = sum(1 for chain in merged if any(r.get(field) == UNKNOWN_VALUE for r in chain))
    if missing:
        return f"unknown — {label} missing on {missing} of {len(merged)} merged PRs"
    total = sum(r[field] for chain in merged for r in chain)
    return fmt.format(total / len(merged))


def cmd_stats(args: argparse.Namespace) -> int:
    records = load_ledger(args.ledger)
    chains = _chains(records)
    merged = [c for c in chains if _outcome(c) == "merged"]
    closed = [c for c in chains if _outcome(c) == "closed"]
    decided = len(merged) + len(closed)
    first = sum(1 for c in merged if len(c) == 1 and c[0].get("decisions") == ["merged"])
    rate = f"{first}/{decided} ({round(100 * first / decided)}%)" if decided else "unknown — no decided PRs"
    attempts = (f"{sum(len(c) for c in merged) / len(merged):.2f}" if merged
                else "unknown — no merged PRs")
    print(f"run-ledger: runs={len(records)} prs={len(chains)} merged={len(merged)} "
          f"closed={len(closed)} open={len(chains) - decided}")
    print(f"run-ledger: first_pass_rate={rate}")
    print(f"run-ledger: attempts_per_merged_pr={attempts}")
    print(f"run-ledger: cost_per_merged_pr={_per_pr(merged, 'cost_usd', 'cost', '{:.2f}')}")
    print(f"run-ledger: tokens_per_merged_pr={_per_pr(merged, 'tokens', 'tokens', '{:.0f}')}")
    return 0


COMMANDS = {"record": cmd_record, "decide": cmd_decide, "last": cmd_last, "stats": cmd_stats}


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return COMMANDS[args.command](args)
    except Refused as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
