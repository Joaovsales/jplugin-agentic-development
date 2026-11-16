#!/usr/bin/env python3
"""Offline checks for grading, secret isolation and durable budget admission."""
from decimal import Decimal
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).with_name("run-code-graph.py")
spec = importlib.util.spec_from_file_location("commerce_runner", SOURCE)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerChecks(unittest.TestCase):
    def protocol_repository(self, root):
        def git(*args):
            return subprocess.run(["git", "-C", str(root), "-c", "core.hooksPath=/dev/null",
                "-c", "user.name=Offline probe", "-c", "user.email=offline@localhost", *args],
                env={**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"},
                capture_output=True, text=True, check=True).stdout.strip()
        git("init", "-q")
        (root / "anchor.txt").write_text("Temporary offline repository\n")
        git("add", "anchor.txt")
        git("commit", "-qm", "Initialize offline repository")
        return git

    def test_missing_protocol_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.protocol_repository(root)
            with patch.object(runner, "HERE", root), patch.object(runner, "REPO", root):
                with self.assertRaises(FileNotFoundError):
                    runner.protocol_commit({"protocol_sha256": "0" * 64})

    def test_untracked_and_staged_but_uncommitted_protocol_are_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); git = self.protocol_repository(root)
            protocol = root / "protocol.md"; protocol.write_text("Frozen protocol\n")
            manifest = {"protocol_sha256": hashlib.sha256(protocol.read_bytes()).hexdigest()}
            with patch.object(runner, "HERE", root), patch.object(runner, "REPO", root):
                for staged in [False, True]:
                    if staged:
                        git("add", "protocol.md")
                    with self.subTest(staged=staged), self.assertRaisesRegex(ValueError, "not committed"):
                        runner.protocol_commit(manifest)

    def test_committed_protocol_returns_real_commit_and_rejects_wrong_hash_or_dirty_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); git = self.protocol_repository(root)
            protocol = root / "protocol.md"; protocol.write_text("Frozen protocol\n")
            manifest = {"protocol_sha256": hashlib.sha256(protocol.read_bytes()).hexdigest()}
            git("add", "protocol.md"); git("commit", "-qm", "Register protocol")
            registered = git("rev-parse", "HEAD")
            with patch.object(runner, "HERE", root), patch.object(runner, "REPO", root):
                self.assertEqual(runner.protocol_commit(manifest), registered)
                with self.assertRaisesRegex(ValueError, "hash mismatch"):
                    runner.protocol_commit({"protocol_sha256": "0" * 64})
                protocol.write_text("Dirty revised protocol\n")
                manifest["protocol_sha256"] = hashlib.sha256(protocol.read_bytes()).hexdigest()
                with self.assertRaisesRegex(ValueError, "not committed"):
                    runner.protocol_commit(manifest)

    def test_protocol_change_between_paid_attempts_stops_next_launch_and_preserves_spend(self):
        for mutation in ["dirty", "commit_then_restore"]:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as folder:
                root = Path(folder); git = self.protocol_repository(root)
                protocol = root / "protocol.md"; original = b"Frozen protocol\n"; protocol.write_bytes(original)
                git("add", "protocol.md"); git("commit", "-qm", "Register protocol")
                registered = git("rev-parse", "HEAD")
                home = root / "person"; (home / ".claude").mkdir(parents=True)
                (home / ".claude/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"accessToken": "fake", "scopes": []}}))
                planned = [{"id": f"A/invoice-rounding/{n}", "arm": "A", "case": "invoice-rounding", "repetition": n} for n in [1, 2]]
                manifest = root / "manifest.json"
                manifest.write_text(json.dumps({"protocol_sha256": hashlib.sha256(original).hexdigest(),
                    "results_directory": "retained", "sources": {"A": runner.BASE}, "slots": planned}))
                calls = []
                def completed(run_root, *args):
                    calls.append(run_root); (run_root / "out").mkdir(parents=True)
                    protocol.write_text("Changed after the first attempt\n")
                    if mutation == "commit_then_restore":
                        git("add", "protocol.md"); git("commit", "-qm", "Change protocol")
                        protocol.write_bytes(original)
                        git("add", "protocol.md"); git("commit", "-qm", "Restore protocol bytes")
                    return {"status": "completed", "kind": "localization", "seed": 101, "costUsd": .1,
                            "costSource": "native_cli", "budgetAccountedUsd": ".25", "admissionBlocked": False}
                with patch.object(runner, "HERE", root), patch.object(runner, "REPO", root), \
                     patch.object(runner, "validate_manifest"), patch.object(runner.Path, "home", return_value=home), \
                     patch.object(runner, "record_ledger"), patch.object(runner, "run_slot", side_effect=completed), \
                     patch.object(runner, "select_run"), patch("builtins.print"):
                    for _ in range(2):
                        with self.assertRaisesRegex(ValueError, "hash mismatch|commit changed"):
                            runner.execute(manifest)
                state = json.loads((root / "execution-state.json").read_text())
                self.assertEqual(len(calls), 1)
                self.assertEqual(state["accounted_usd"], "0.25")
                self.assertIsNone(state["pending"])
                self.assertEqual(state["attempts"][0]["protocol_commit"], registered)

    def test_only_explicit_environment_reaches_candidate(self):
        secrets = {key: "private" for key in ["GH_TOKEN", "GITHUB_TOKEN", "SSH_AUTH_SOCK", "BASH_ENV",
                   "PYTHONPATH", "PYTHONSTARTUP", "AWS_SESSION_TOKEN", "ANTHROPIC_API_KEY", "GIT_CONFIG"]}
        with patch.dict(os.environ, secrets):
            env = runner.clean_env(Path("/neutral"))
        self.assertFalse(set(secrets) & set(env))
        self.assertEqual(env["PATH"], "/neutral/tools:/usr/local/bin:/usr/bin:/bin")
        self.assertEqual(env["NO_PROXY"], "127.0.0.1,localhost")

    def test_control_fixture_is_local_committed_and_has_no_graph_runtime(self):
        with tempfile.TemporaryDirectory(prefix="hr-", dir=Path.home()) as folder:
            root = Path(folder) / "round"
            env, info = runner.prepare(root, "A", "invoice-rounding", runner.BASE)
            self.assertEqual(info["seed"], 101)
            self.assertFalse(any(key.startswith("CODE_GRAPH_") for key in env))
            self.assertTrue((root / "home/app/.git").is_dir())
            self.assertFalse((root / "home/app/graphify-out").exists())
            self.assertEqual((root / "home/app/.ignore").read_text(), "graphify-out/\n")
            settings = json.loads((root / "config/settings.json").read_text())
            self.assertTrue(settings["sandbox"]["enabled"])
            self.assertFalse(settings["sandbox"]["allowUnsandboxedCommands"])
            self.assertIn("//tmp", settings["sandbox"]["filesystem"]["denyRead"])
            self.assertIn("Read(//tmp/**)", settings["permissions"]["deny"])

    def test_file_grade_uses_file_even_when_answer_has_expected_word(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); app = root / "home/app"; app.mkdir(parents=True)
            target = app / "README.md"
            target.write_text("Store each receipt")
            score, _ = runner.grade("readme-copy", root, "README.md")
            self.assertEqual(score, 1)
            target.write_text("Store each reciept")
            score, _ = runner.grade("readme-copy", root, "README.md receipt")
            self.assertEqual(score, .5)

    def test_yaml_file_grade_does_not_grade_the_reported_port(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); target = root / "home/app/config/runtime.yaml"; target.parent.mkdir(parents=True)
            target.write_text("gateway:\n  port: 4210\n")
            score, _ = runner.grade("profile-port", root, "config/runtime.yaml now uses 4211")
            self.assertEqual(score, .5)
            target.write_text("gateway:\n  port: 4211\n")
            score, _ = runner.grade("profile-port", root, "config/runtime.yaml")
            self.assertEqual(score, 1)

    def test_reservation_survives_a_crash_and_blocks_an_unknown_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            state = {"accounted_usd": "316", "pending": None}
            runner.reserve_attempt(path, state, {"id": "A/invoice-rounding/1"})
            recovered = json.loads(path.read_text())
            self.assertEqual(recovered["pending"]["reserved_usd"], "4")
            with self.assertRaisesRegex(ValueError, "unresolved"):
                runner.reserve_attempt(path, recovered, {"id": "A/invoice-rounding/1"})
            self.assertEqual(json.loads(path.read_text()), recovered)

    def test_reservation_refuses_before_the_total_ceiling(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            state = {"accounted_usd": "316.01", "pending": None}
            with self.assertRaisesRegex(ValueError, "total ceiling"):
                runner.reserve_attempt(path, state, {"id": "next"})
            self.assertFalse(path.exists())
            self.assertIsNone(state["pending"])

    def test_manifest_refuses_model_and_N_changes(self):
        planned = runner.slots()
        self.assertEqual(len(planned), 90)
        self.assertEqual(len({slot["id"] for slot in planned}), 90)
        for changed in [{"model": "other", "N": 3}, {"model": runner.MODEL, "N": 4}]:
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, "model, N"):
                runner.validate_manifest({**changed, "slots": planned})
        with self.assertRaisesRegex(ValueError, "model, N"):
            runner.validate_manifest({"model": runner.MODEL, "N": 3, "slots": planned[:-1]})

    def test_missing_nominal_cost_uses_accounted_upper_and_marks_error(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            class Gateway:
                url = "http://127.0.0.1/offline"
                budget = SimpleNamespace(spent=Decimal(".75"), held={}, blocked=False)
                def __init__(self, **kwargs):
                    return
                def serve_forever(self):
                    return
                def shutdown(self):
                    return
                def server_close(self):
                    return
            def prepare(*args):
                (root / "out").mkdir()
                return {}, {"kind": "localization", "seed": 101}
            output = json.dumps({"type": "result", "subtype": "success", "result": "billing/amounts.py settle_amount"}) + "\n"
            with patch.object(runner, "prepare", side_effect=prepare), \
                 patch.object(runner, "load", return_value=SimpleNamespace(Gateway=Gateway)), \
                 patch.object(runner.subprocess, "run", return_value=SimpleNamespace(stdout=output, stderr="", returncode=0)) as invoked:
                record = runner.run_slot(root, "B", "invoice-rounding", "source", "fake-only", [])
            self.assertEqual(record["costUsd"], .75)
            self.assertEqual(record["costSource"], "accounted_upper_unknown_nominal")
            self.assertEqual(record["status"], "errored")
            self.assertNotIn("CLAUDE_CODE_OAUTH_TOKEN", invoked.call_args.kwargs["env"])
            self.assertEqual(len(invoked.call_args.kwargs["pass_fds"]), 1)

    def test_selected_artifact_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); selected = root / "A/invoice-rounding/run-1"; selected.mkdir(parents=True)
            (selected / "metadata.json").write_text('{"attempt_id":"previous"}')
            run = {"kind": "localization", "seed": 101, "status": "completed", "costUsd": .2,
                   "costSource": "native_cli", "attempt_id": "replacement"}
            with self.assertRaisesRegex(ValueError, "collision"):
                runner.select_run(run, {"arm": "A", "case": "invoice-rounding", "repetition": 1}, root)
            self.assertEqual(json.loads((selected / "metadata.json").read_text()), {"attempt_id": "previous"})

    def test_spend_is_durable_before_arranging_and_restart_does_not_pay_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); home = root / "person"; (home / ".claude").mkdir(parents=True)
            (home / ".claude/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"accessToken": "fake", "scopes": []}}))
            slot = {"id": "A/invoice-rounding/1", "arm": "A", "case": "invoice-rounding", "repetition": 1}
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"results_directory": "retained", "sources": {"A": runner.BASE}, "slots": [slot]}))
            calls = []
            def completed(run_root, *args):
                calls.append(run_root); (run_root / "out").mkdir(parents=True)
                return {"status": "completed", "kind": "localization", "seed": 101, "costUsd": .1,
                        "costSource": "native_cli", "budgetAccountedUsd": ".25", "admissionBlocked": False}
            with patch.object(runner, "HERE", root), patch.object(runner, "validate_manifest"), \
                 patch.object(runner, "protocol_commit", return_value="committed"), \
                 patch.object(runner.Path, "home", return_value=home), patch.object(runner, "record_ledger"), \
                 patch.object(runner, "run_slot", side_effect=completed), \
                 patch.object(runner, "select_run", side_effect=RuntimeError("arranger failed")):
                for _ in range(2):
                    with self.assertRaisesRegex(RuntimeError, "arranger failed"):
                        runner.execute(manifest)
            state = json.loads((root / "execution-state.json").read_text())
            self.assertEqual(len(calls), 1)
            self.assertEqual(state["accounted_usd"], "0.25")
            self.assertIsNone(state["pending"])
            self.assertEqual(len(state["attempts"]), 1)

    def test_one_error_retry_then_arm_replacement_preserves_N_and_spend(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); home = root / "person"; (home / ".claude").mkdir(parents=True)
            (home / ".claude/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"accessToken": "fake", "scopes": []}}))
            planned = runner.slots()
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"results_directory": "retained", "sources": {arm: runner.BASE for arm in ["A", "B", "D"]}, "slots": planned}))
            failing = {slot["id"] for slot in planned[:4]}
            def completed(run_root, arm, case, *args):
                (run_root / "out").mkdir(parents=True)
                pending = json.loads((root / "execution-state.json").read_text())["pending"]
                bad = pending["generation"] == 0 and pending["id"] in failing
                return {"status": "errored" if bad else "completed", "kind": pending["kind"], "seed": pending["seed"],
                        "costUsd": .01, "costSource": "native_cli", "budgetAccountedUsd": ".01", "admissionBlocked": False}
            def select(record, slot, results):
                (results / slot["arm"] / slot["case"] / ("run-" + str(slot["repetition"]))).mkdir(parents=True)
            with patch.object(runner, "HERE", root), patch.object(runner, "validate_manifest"), \
                 patch.object(runner, "protocol_commit", return_value="committed"), \
                 patch.object(runner.Path, "home", return_value=home), patch.object(runner, "record_ledger"), \
                 patch.object(runner, "run_slot", side_effect=completed), patch.object(runner, "select_run", side_effect=select), \
                 patch("builtins.print"):
                runner.execute(manifest)
            state = json.loads((root / "execution-state.json").read_text())
            self.assertEqual(len(state["selected"]), 90)
            self.assertEqual(state["arm_generations"]["A"], 1)
            self.assertEqual(len(state["attempts"]), 124)
            self.assertEqual(Decimal(state["accounted_usd"]), Decimal("1.24"))
            self.assertTrue((root / "retained/attempts/arm-A-generation-0").is_dir())

    def test_larger_nominal_charge_is_debited_and_stops_the_next_paid_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); home = root / "person"; (home / ".claude").mkdir(parents=True)
            (home / ".claude/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"accessToken": "fake", "scopes": []}}))
            slot = {"id": "A/invoice-rounding/1", "arm": "A", "case": "invoice-rounding", "repetition": 1}
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"results_directory": "retained", "sources": {"A": runner.BASE}, "slots": [slot]}))
            def charged(run_root, *args):
                (run_root / "out").mkdir(parents=True)
                return {"status": "completed", "kind": "localization", "seed": 101, "costUsd": 2.,
                        "costSource": "native_cli", "budgetAccountedUsd": ".25", "admissionBlocked": False}
            with patch.object(runner, "HERE", root), patch.object(runner, "validate_manifest"), \
                 patch.object(runner, "protocol_commit", return_value="committed"), \
                 patch.object(runner.Path, "home", return_value=home), patch.object(runner, "record_ledger"), \
                 patch.object(runner, "run_slot", side_effect=charged) as invoked, patch("builtins.print"):
                for _ in range(2):
                    with self.assertRaisesRegex(ValueError, "admission assumptions failed"):
                        runner.execute(manifest)
            state = json.loads((root / "execution-state.json").read_text())
            self.assertEqual(invoked.call_count, 1)
            self.assertEqual(Decimal(state["accounted_usd"]), Decimal(2))
            self.assertTrue(state["attempts"][0]["billingBreach"])


if __name__ == "__main__":
    unittest.main()
