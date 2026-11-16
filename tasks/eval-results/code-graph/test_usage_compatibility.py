#!/usr/bin/env python3
"""Isolated compatibility recovery checks; no production state or model calls."""
from contextlib import contextmanager
import importlib.util
import json
import os
import stat
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


migration = module("usage_compatibility", "prepare-usage-compatibility.py")
runner = module("commerce_runner", "run-code-graph.py")


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        def git(*args):
            return subprocess.run(["git", "-C", str(root), "-c", "core.hooksPath=/dev/null",
                "-c", "user.name=Offline", "-c", "user.email=offline@localhost", *args],
                capture_output=True, text=True, check=True).stdout.strip()
        git("init", "-q")
        protocol = root / "protocol.md"; protocol.write_text("Frozen protocol\n")
        git("add", "protocol.md"); git("commit", "-qm", "Register offline protocol")
        commit = git("rev-parse", "HEAD"); protocol_hash = migration.digest(protocol.read_bytes())
        for name in migration.OPS:
            (root / name).write_text("current " + name)
        active = {name: migration.digest((root / name).read_bytes()) for name in migration.OPS}
        previous = {**active, "run-code-graph.py": "1" * 64, "admission_gateway.py": "2" * 64}
        slot = {"id": "A/invoice-rounding/1", "arm": "A", "case": "invoice-rounding", "repetition": 1}
        original = {"model": runner.MODEL, "N": 3, "protocol_sha256": protocol_hash,
                    "operational_sha256": previous, "sources": {"A": runner.BASE},
                    "results_directory": "retained", "slots": [slot]}
        old_path = root / "run-manifest.json"; old_path.write_bytes(migration.encoded(original))
        new_path = root / "run-manifest-usage-compat-1.json"
        new_path.write_bytes(migration.encoded({**original, "operational_sha256": active}))
        old_hash = migration.digest(old_path.read_bytes())
        attempt = {**slot, "generation": 0, "attempt": 1, "attempt_id": migration.ATTEMPT_ID,
                   "status": "errored", "protocol_commit": commit, "costUsd": .14927200000000002,
                   "budgetAccountedUsd": "1.660241"}
        state = {"attempts": [attempt], "selected": {}, "accounted_usd": "1.660241", "pending": None,
                 "manifest_sha256": old_hash, "arm_generations": {}, "halt_reason": migration.HALT}
        (root / "execution-state.json").write_bytes(migration.encoded(state))
        proof = root / "offline-proof.json"; proof.write_text('{"paid_calls":0}\n')
        with patch.object(migration, "HERE", root), patch.object(migration, "REPO", root), \
             patch.object(migration, "PROTOCOL_COMMIT", commit), patch.object(migration, "PROTOCOL_HASH", protocol_hash), \
             patch.object(migration, "OLD_MANIFEST_HASH", old_hash), patch.object(migration, "OLD_ATTEMPT_HASH", migration.attempt_digest(attempt)), \
             patch.object(migration, "NEW_MANIFEST_HASH", migration.digest(new_path.read_bytes()), create=True):
            yield root, old_path, new_path, proof, state, git


class CompatibilityChecks(unittest.TestCase):
    def test_default_preparation_changes_no_state_or_original_inputs(self):
        with fixture() as (root, old, new, proof, state, git):
            paths = [old, root / "protocol.md", root / "execution-state.json"]
            before = {path: path.read_bytes() for path in paths}
            receipt = migration.migrate(old, new, [proof])
            self.assertFalse(receipt["state_applied"])
            self.assertEqual(before, {path: path.read_bytes() for path in paths})
            self.assertFalse((root / "execution-state-before-usage-compat-1.json").exists())

    def test_non_operational_difference_including_numeric_type_is_refused(self):
        for key, value in [("model", "other"), ("N", 3.0), ("results_directory", "different")]:
            with self.subTest(key=key), fixture() as (root, old, new, proof, state, git):
                data = json.loads(new.read_text()); data[key] = value; new.write_bytes(migration.encoded(data))
                with patch.object(migration, "NEW_MANIFEST_HASH", migration.digest(new.read_bytes())), \
                     self.assertRaisesRegex(ValueError, "only existing operational"):
                    migration.migrate(old, new, [proof])

    def test_reviewed_candidate_hash_refuses_even_value_identical_json(self):
        with fixture() as (root, old, new, proof, state, git):
            new.write_bytes(new.read_bytes() + b" ")
            with self.assertRaisesRegex(ValueError, "reviewed compatibility manifest hash"):
                migration.migrate(old, new, [proof])

    def test_snapshot_and_intent_directory_entries_are_durable_before_state_replace(self):
        with fixture() as (root, old, new, proof, state, git):
            events = []
            real_sync, real_replace = os.fsync, Path.replace
            def sync(fd):
                if stat.S_ISDIR(os.fstat(fd).st_mode):
                    events.append(("directory_sync", ""))
                else:
                    events.append(("file_sync", Path(os.readlink(f"/proc/self/fd/{fd}")).name))
                return real_sync(fd)
            def replace(path, target):
                events.append(("state_replace", ""))
                return real_replace(path, target)
            with patch.object(migration.os, "fsync", side_effect=sync), patch.object(Path, "replace", new=replace):
                migration.migrate(old, new, [proof], apply=True)
            rename = events.index(("state_replace", ""))
            prior_syncs = [index for index, event in enumerate(events[:rename]) if event[0] == "directory_sync"]
            self.assertTrue(prior_syncs, "Snapshot and audit directory entries were not flushed before replacement")
            prior_sync = max(prior_syncs)
            intent_name = next(root.glob("usage-compatibility-migration-applied.*")).name
            self.assertLess(events.index(("file_sync", "execution-state-before-usage-compat-1.json")), prior_sync)
            self.assertLess(events.index(("file_sync", intent_name)), prior_sync)
            self.assertTrue(any(event[0] == "directory_sync" for event in events[rename + 1:]))

    def test_wrong_original_or_protocol_bytes_or_commit_identity_is_refused(self):
        for kind in ["manifest", "protocol", "identity"]:
            with self.subTest(kind=kind), fixture() as (root, old, new, proof, state, git):
                if kind == "manifest":
                    old.write_bytes(old.read_bytes() + b" ")
                else:
                    (root / "protocol.md").write_text("Changed\n")
                    if kind == "identity":
                        git("add", "protocol.md"); git("commit", "-qm", "Change")
                        (root / "protocol.md").write_text("Frozen protocol\n")
                        git("add", "protocol.md"); git("commit", "-qm", "Restore")
                with self.assertRaisesRegex(ValueError, "manifest hash|protocol bytes|commit identity"):
                    migration.migrate(old, new, [proof])

    def test_altered_attempt_cost_pending_or_generation_is_refused(self):
        for kind in ["cost", "attempt", "pending", "generation"]:
            with self.subTest(kind=kind), fixture() as (root, old, new, proof, state, git):
                if kind == "cost": state["accounted_usd"] = "0"
                if kind == "attempt": state["attempts"][0]["costUsd"] = 0
                if kind == "pending": state["pending"] = {"reserved_usd": "4"}
                if kind == "generation": state["arm_generations"] = {"A": 1}
                (root / "execution-state.json").write_bytes(migration.encoded(state))
                with self.assertRaises(ValueError):
                    migration.migrate(old, new, [proof])

    def test_changed_relay_or_source_hash_is_refused(self):
        with fixture() as (root, old, new, proof, state, git):
            (root / "sandbox-relay.py").write_text("unexpected relay change")
            with self.assertRaisesRegex(ValueError, "operational source"):
                migration.migrate(old, new, [proof])

    def test_apply_preserves_attempt_costs_and_binds_history_without_retroactive_edit(self):
        with fixture() as (root, old, new, proof, state, git):
            before_bytes = (root / "execution-state.json").read_bytes()
            receipt = migration.migrate(old, new, [proof], apply=True)
            after = json.loads((root / "execution-state.json").read_text())
            for key in ["attempts", "selected", "arm_generations", "accounted_usd", "pending"]:
                self.assertEqual(migration.canonical(after[key]), migration.canonical(state[key]))
            self.assertNotIn("manifest_sha256", after["attempts"][0])
            history = after["compatibility_history"][0]
            self.assertEqual(history["prior_attempt_provenance"]["manifest_sha256"], state["manifest_sha256"])
            self.assertEqual(history["prior_halt_reason"], state["halt_reason"])
            self.assertEqual((root / "execution-state-before-usage-compat-1.json").read_bytes(), before_bytes)
            self.assertEqual(receipt["after_state_sha256"], migration.digest((root / "execution-state.json").read_bytes()))
            applied_bytes = (root / "execution-state.json").read_bytes()
            with self.assertRaisesRegex(ValueError, "already applied"):
                migration.migrate(old, new, [proof], apply=True)
            self.assertEqual((root / "execution-state.json").read_bytes(), applied_bytes)

    def test_future_retry_is_attempt_two_with_active_manifest_in_receipt_state_and_ledger(self):
        with fixture() as (root, old, new, proof, state, git):
            migration.migrate(old, new, [proof], apply=True)
            home = root / "person"; (home / ".claude").mkdir(parents=True)
            (home / ".claude/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"accessToken": "fake", "scopes": []}}))
            def completed(run_root, *args):
                (run_root / "out").mkdir(parents=True)
                return {"status": "completed", "kind": "localization", "seed": 101, "costUsd": .1,
                        "costSource": "native_cli", "budgetAccountedUsd": ".25", "admissionBlocked": False}
            with patch.object(runner, "HERE", root), patch.object(runner, "REPO", root), \
                 patch.object(runner, "validate_manifest"), patch.object(runner.Path, "home", return_value=home), \
                 patch.object(runner, "record_ledger") as ledger, patch.object(runner, "run_slot", side_effect=completed) as paid, \
                 patch.object(runner, "select_run", side_effect=RuntimeError("stop after retry receipt")), patch("builtins.print"):
                with self.assertRaisesRegex(RuntimeError, "stop after retry receipt"):
                    runner.execute(new)
            after = json.loads((root / "execution-state.json").read_text())
            original, retry = after["attempts"]
            self.assertEqual(migration.canonical(original), migration.canonical(state["attempts"][0]))
            self.assertEqual(retry["attempt_id"], "A/invoice-rounding/1/0/2")
            self.assertEqual(retry["manifest_sha256"], migration.digest(new.read_bytes()))
            self.assertEqual(json.loads((Path(retry["artifact_root"]) / "out/run-receipt.json").read_text())["manifest_sha256"], retry["manifest_sha256"])
            self.assertEqual(ledger.call_args.args[1]["manifest_sha256"], retry["manifest_sha256"])
            self.assertEqual(after["accounted_usd"], "1.910241")
            self.assertEqual(paid.call_count, 1)


if __name__ == "__main__":
    unittest.main()
