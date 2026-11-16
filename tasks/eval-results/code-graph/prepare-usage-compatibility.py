#!/usr/bin/env python3
"""Prepare a guarded usage-decoder recovery. Real application is a separate approval."""
import argparse
import copy
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PROTOCOL_COMMIT = "f1f4df8715029e380c8b4e382a4547152f4082df"
PROTOCOL_HASH = "eceb8b458bf7b0464d0b523de8e87eec61f621151818aa29c1b4881932798dfd"
OLD_MANIFEST_HASH = "6e27abd6299168923124f2bcbaadec6f46df56ee0856070deb39400763894c1e"
NEW_MANIFEST_HASH = "f91ff5d287569ab8c6cb8594d6c55f01ce9c2bbeaa3c39e39f557af01150c23a"
OLD_ATTEMPT_HASH = "517d2cee0a851b170b8ba60483a17cddea039c053d08ad9fe68134d4a9c19c63"
ATTEMPT_ID = "A/invoice-rounding/1/0/1"
HALT = "admission assumptions failed; review the retained audit before resuming"
MIGRATION = "native-usage-compatibility-1"
OPS = {"run-code-graph.py", "admission_gateway.py", "sandbox-relay.py"}


def digest(content):
    return hashlib.sha256(content).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2) + "\n").encode()


def attempt_digest(attempt):
    return digest(json.dumps(attempt, sort_keys=True, separators=(",", ":")).encode())


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def parsed(content):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON field")
            result[key] = value
        return result
    return json.loads(content, object_pairs_hook=unique)


def git(*args):
    return subprocess.run(["git", *args], cwd=REPO, capture_output=True, check=True).stdout


def frozen_inputs(old_path, new_path):
    original = old_path.read_bytes()
    if digest(original) != OLD_MANIFEST_HASH:
        raise ValueError("original manifest hash changed")
    candidate = new_path.read_bytes()
    if digest(candidate) != NEW_MANIFEST_HASH:
        raise ValueError("reviewed compatibility manifest hash changed")
    old, new = parsed(original), parsed(candidate)
    old_without_ops, new_without_ops = copy.deepcopy(old), copy.deepcopy(new)
    prior, active = old_without_ops.pop("operational_sha256"), new_without_ops.pop("operational_sha256")
    if canonical(old_without_ops) != canonical(new_without_ops) or set(prior) != OPS or set(active) != OPS:
        raise ValueError("compatibility manifest may change only existing operational hashes")
    changed = {key for key in OPS if prior[key] != active[key]}
    if changed != {"run-code-graph.py", "admission_gateway.py"}:
        raise ValueError("only the reviewed gateway and controller may change; relay stays fixed")
    for name, expected in active.items():
        if digest((HERE / name).read_bytes()) != expected:
            raise ValueError("active operational source does not match manifest: " + name)
    protocol = HERE / "protocol.md"
    content = protocol.read_bytes()
    if digest(content) != PROTOCOL_HASH or old.get("protocol_sha256") != PROTOCOL_HASH:
        raise ValueError("frozen protocol bytes changed")
    relative = str(protocol.relative_to(REPO))
    if git("log", "-1", "--format=%H", "--", relative).decode().strip() != PROTOCOL_COMMIT:
        raise ValueError("frozen protocol commit identity changed")
    if git("show", PROTOCOL_COMMIT + ":" + relative) != content:
        raise ValueError("protocol working tree differs from its frozen commit")
    return digest(candidate), active


def unchanged_attempt(state):
    expected_keys = {"attempts", "selected", "accounted_usd", "pending", "manifest_sha256", "arm_generations", "halt_reason"}
    if set(state) != expected_keys or state.get("manifest_sha256") != OLD_MANIFEST_HASH:
        raise ValueError("state is not the original stopped batch")
    if state["pending"] is not None or state["selected"] != {} or state["arm_generations"] != {}:
        raise ValueError("pending, selected or retry-generation state changed")
    if state["accounted_usd"] != "1.660241" or state["halt_reason"] != HALT:
        raise ValueError("accounted cost or diagnosed halt changed")
    attempts = state["attempts"]
    if len(attempts) != 1 or attempt_digest(attempts[0]) != OLD_ATTEMPT_HASH:
        raise ValueError("original attempt changed")
    attempt = attempts[0]
    if (attempt.get("attempt_id") != ATTEMPT_ID or attempt.get("status") != "errored"
            or attempt.get("protocol_commit") != PROTOCOL_COMMIT or attempt.get("attempt") != 1):
        raise ValueError("original attempt identity, status or retry count changed")


def fresh_file(path, content):
    with path.open("xb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def migrate(old_path, new_path, proof_paths, apply=False):
    new_hash, active = frozen_inputs(old_path, new_path)
    state_path = HERE / "execution-state.json"
    before = state_path.read_bytes()
    state = parsed(before)
    if state.get("manifest_sha256") == new_hash:
        raise ValueError("compatibility migration already applied; refusing any reset")
    unchanged_attempt(state)
    if not proof_paths:
        raise ValueError("reviewed offline proof files are required")
    proofs = {}
    for path in proof_paths:
        relative = path.resolve().relative_to(HERE.resolve())
        proofs[str(relative)] = digest(path.read_bytes())
    snapshot = HERE / "execution-state-before-usage-compat-1.json"
    receipt_path = HERE / "usage-compatibility-migration-applied.jsonl"
    history = {"id": MIGRATION, "recorded_utc": datetime.now(timezone.utc).isoformat(),
               "old_manifest_sha256": OLD_MANIFEST_HASH, "new_manifest_sha256": new_hash,
               "protocol_commit": PROTOCOL_COMMIT, "protocol_sha256": PROTOCOL_HASH,
               "prior_state_sha256": digest(before), "snapshot": snapshot.name,
               "prior_halt_reason": state["halt_reason"], "proof_sha256": proofs,
               "active_operational_sha256": active,
               "prior_attempt_provenance": {"attempt_id": ATTEMPT_ID, "manifest_sha256": OLD_MANIFEST_HASH,
                                            "attempt_sha256": OLD_ATTEMPT_HASH},
               "reason": "Pinned native usage-counter normalization compatibility; exact paid trigger not asserted."}
    after = copy.deepcopy(state)
    after["manifest_sha256"] = new_hash
    after["compatibility_history"] = [history]
    del after["halt_reason"]
    after_bytes = encoded(after)
    receipt = {"mode": "apply" if apply else "dry-run", "state_applied": False,
               "history": history, "after_state_sha256": digest(after_bytes),
               "preserved": ["attempts", "selected", "arm_generations", "accounted_usd", "pending"],
               "next_planned_attempt": "A/invoice-rounding/1/0/2"}
    if not apply:
        return receipt
    if snapshot.exists() or receipt_path.exists():
        raise ValueError("migration snapshot or receipt already exists; reconcile before applying")
    if state_path.read_bytes() != before:
        raise ValueError("controller state changed during verification")
    if frozen_inputs(old_path, new_path) != (new_hash, active):
        raise ValueError("compatibility manifest changed during verification")
    fresh_file(snapshot, before)
    fresh_file(receipt_path, json.dumps({"event": "apply_intent", **receipt}).encode() + b"\n")
    temporary = HERE / "execution-state.usage-compat-1.new"
    fresh_file(temporary, after_bytes)
    directory = os.open(HERE, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
        temporary.replace(state_path)
        os.fsync(directory)
    finally:
        os.close(directory)
    receipt["state_applied"] = True
    with receipt_path.open("ab") as stream:
        stream.write(json.dumps({"event": "applied", "after_state_sha256": digest(after_bytes)}).encode() + b"\n")
        stream.flush()
        os.fsync(stream.fileno())
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=HERE / "run-manifest-usage-compat-1.json")
    parser.add_argument("--proof", type=Path, action="append", required=True)
    parser.add_argument("--apply", action="store_true", help="Apply only after the orchestrator explicitly approves recovery")
    args = parser.parse_args()
    if args.apply:
        with (HERE / "runner.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            receipt = migrate(HERE / "run-manifest.json", args.manifest, args.proof, apply=True)
    else:
        receipt = migrate(HERE / "run-manifest.json", args.manifest, args.proof)
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
