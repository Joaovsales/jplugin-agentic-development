"""Public CLI regressions, invoked by test-run-ledger.sh."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve()
SKILL = Path(sys.argv.pop(1)).resolve()

# Pause after the real read, and expose an actual contended OS-lock attempt.
WORKER = r'''
import importlib.util, os, pathlib, sys, time
spec = importlib.util.spec_from_file_location("ledger", sys.argv[1])
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)
mode, marker, release = sys.argv[2:5]
marker, release = pathlib.Path(marker), pathlib.Path(release)
if mode == "timeout":
    ledger.LOCK_TIMEOUT = .15
if mode == "pause":
    original = ledger.load_record
    def load(path):
        record = original(path)
        marker.touch()
        deadline = time.monotonic() + 10
        while not release.exists():
            if time.monotonic() >= deadline:
                raise RuntimeError("test read barrier timed out")
            time.sleep(.01)
        return record
    ledger.load_record = load
else:
    if os.name == "nt":
        import msvcrt
        module, name = msvcrt, "locking"
    else:
        import fcntl
        module, name = fcntl, "flock"
    original = getattr(module, name)
    def lock(*args):
        try:
            return original(*args)
        except BlockingIOError:
            marker.touch()
            raise
        except OSError as exc:
            if exc.errno in (11, 13, 35, 36):
                marker.touch()
            raise
    setattr(module, name, lock)
sys.exit(ledger.main(sys.argv[5:]))
'''


class LedgerRegressions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.box = Path(self.temp.name)
        self.ledger = self.box / "tasks/runs"
        self.cli("record", "--branch", "review", "--base", "aaaaaaaaaaaa", "--run-id", "R")
        self.path = self.ledger / "R.json"

    def cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args, "--ledger", str(self.ledger)],
                              capture_output=True, text=True, timeout=15)

    def caller(self, block):
        target = self.box / ".agents/skills/build/scripts"
        target.mkdir(parents=True, exist_ok=True)
        for source in SCRIPT.parent.glob("*.py"):
            shutil.copyfile(source, target / source.name)
        prefix = 'git() { printf "%s\\n" review; }; python3() { "$LEDGER_PY" "$@"; };\n'
        return subprocess.run(["bash", "-c", prefix + block], cwd=self.box,
                              env={**os.environ, "LEDGER_PY": sys.executable},
                              capture_output=True, text=True, timeout=15)

    def wait_for(self, condition):
        deadline = time.monotonic() + 10
        while not condition():
            if time.monotonic() >= deadline:
                self.fail("process barrier timed out")
            time.sleep(.01)

    def race(self, first_args, second_result):
        read, blocked, release = [self.box / name for name in ("read", "blocked", "release")]
        common = ["--ledger", str(self.ledger)]
        first = subprocess.Popen([sys.executable, "-c", WORKER, str(SCRIPT), "pause",
                                  str(read), str(release), *first_args, *common],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        second = None
        try:
            self.wait_for(lambda: read.exists() or first.poll() is not None)
            self.assertTrue(read.exists(), first.communicate() if first.poll() is not None else "")
            second = subprocess.Popen([sys.executable, "-c", WORKER, str(SCRIPT), "contend",
                                       str(blocked), str(release), "decide", "--run-id", "R",
                                       "--result", second_result, *common],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.wait_for(lambda: blocked.exists() or second.poll() is not None)
            contended = blocked.exists()
            release.touch()
            first_output = first.communicate(timeout=15)
            second_output = second.communicate(timeout=15)
            self.assertTrue(contended, "second writer completed while the first held a stale read")
            self.assertEqual(first.returncode, 0, first_output)
            return second.returncode, second_output
        finally:
            release.touch()
            for process in (first, second):
                if process is not None and process.poll() is None:
                    process.kill()
                    process.communicate()

    def test_record_vs_decide_preserves_merged(self):
        code, output = self.race(["record", "--branch", "review", "--base", "aaaaaaaaaaaa",
                                  "--run-id", "R", "--cost", "2"], "merged")
        self.assertEqual(code, 0, output)
        record = json.loads(self.path.read_text())
        self.assertEqual((record["human_result"], record["decisions"], record["cost_usd"]),
                         ("merged", ["merged"], 2))

    def test_decide_vs_decide_refuses_overwriting_merged(self):
        code, output = self.race(["decide", "--run-id", "R", "--result", "merged"], "closed")
        self.assertEqual(code, 1, output)
        self.assertIn("already merged", output[1])
        record = json.loads(self.path.read_text())
        self.assertEqual((record["human_result"], record["decisions"]), ("merged", ["merged"]))

    def test_lock_timeout_and_crashed_writer_recovery(self):
        read, blocked, release = [self.box / name for name in ("read", "blocked", "release")]
        first = subprocess.Popen([sys.executable, "-c", WORKER, str(SCRIPT), "pause",
                                  str(read), str(release), "decide", "--run-id", "R", "--result",
                                  "merged", "--ledger", str(self.ledger)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.wait_for(lambda: read.exists() or first.poll() is not None)
            self.assertTrue(read.exists())
            result = subprocess.run([sys.executable, "-c", WORKER, str(SCRIPT), "timeout",
                                     str(blocked), str(release), "decide", "--run-id", "R",
                                     "--result", "closed", "--ledger", str(self.ledger)],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("timed out waiting for run lock", result.stderr)
            self.assertIn(str(self.path.with_suffix(".lock")), result.stderr)
        finally:
            first.kill()
            first.communicate()
        recovered = self.cli("decide", "--run-id", "R", "--result", "merged")
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertEqual(self.cli("stats").returncode, 0)

    def test_invalid_payloads_refused_by_readers_and_writers(self):
        original = json.loads(self.path.read_text())
        cases = [("human_result", "mergd"), ("human_result", []),
                 ("decisions", None), ("decisions", ["mergd"]),
                 ("decisions", ["merged"]), ("decisions", ["merged", "closed"]),
                 ("cost_usd", "oops"), ("cost_usd", -5), ("cost_usd", float("inf")),
                 ("cost_usd", float("nan")), ("cost_usd", True),
                 ("tokens", -1), ("tokens", 1.5), ("tokens", "12"), ("tokens", False),
                 ("branch", []), ("recorded_at", 42), ("parent_run_id", [])]
        cases += [(key, None) for key in ("human_result", "decisions", "cost_usd", "tokens")]
        for index, (field, value) in enumerate(cases):
            bad = {**original, field: value}
            if index >= len(cases) - 4:
                del bad[field]
            if value == ["merged", "closed"]:
                bad["human_result"] = "closed"
            for command in (("stats",), ("last", "--branch", "review"),
                            ("decide", "--run-id", "R", "--result", "merged"),
                            ("record", "--branch", "review", "--base", "aaaaaaaaaaaa", "--run-id", "R")):
                with self.subTest(field=field, value=value, command=command):
                    self.path.write_text(json.dumps(bad))
                    result = self.cli(*command)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn(str(self.path), result.stderr)
                    self.assertNotIn("Traceback", result.stderr)

    def test_last_no_run_diagnostic_is_distinct_from_invalid_record(self):
        absent = self.cli("last", "--branch", "absent")
        self.assertEqual(absent.returncode, 1)
        self.assertEqual(absent.stderr.strip(), f"last: no run on branch absent in {self.ledger}")
        self.path.write_text("not json")
        broken = self.cli("last", "--branch", "review")
        self.assertEqual(broken.returncode, 1)
        self.assertIn(str(self.path), broken.stderr)
        self.assertNotIn("last: no run on branch", broken.stderr)
        self.ledger.rename(self.box / "backup")
        self.ledger.write_text("not a directory")
        broken = self.cli("last", "--branch", "review")
        self.assertEqual(broken.returncode, 1)
        self.assertIn(str(self.ledger), broken.stderr)
        self.assertNotIn("last: no run on branch", broken.stderr)

    def test_receive_review_executes_documented_no_run_and_failure_paths(self):
        text = SKILL.read_text(encoding="utf-8")
        block = text.split("### Record the rework run", 1)[1].split("```bash\n", 1)[1].split("```", 1)[0]
        for state in ("absent", "broken", "valid", "final"):
            with self.subTest(state=state):
                if state == "absent":
                    self.path.unlink()
                elif state == "broken":
                    self.path.write_text("not json")
                else:
                    self.path.unlink()
                    self.cli("record", "--branch", "review", "--base", "aaaaaaaaaaaa", "--run-id", "R")
                    if state == "final":
                        self.cli("decide", "--run-id", "R", "--result", "merged")
                result = self.caller(block + '\nprintf "CONTINUED:%s\\n" "$parent"')
                self.assertEqual(result.returncode, 1 if state in ("broken", "final") else 0,
                                 result.stdout + result.stderr)
                if state in ("broken", "final"):
                    self.assertNotIn("CONTINUED", result.stdout)
                    self.assertTrue(result.stderr)
                else:
                    self.assertIn("CONTINUED:" + ("R" if state == "valid" else ""), result.stdout)

    def test_receive_review_record_failure_stops(self):
        text = SKILL.read_text(encoding="utf-8").split("### Record the rework run", 1)[1]
        block = text.split("```bash\n")[2].split("```", 1)[0].replace("<start>", "aaaaaaaaaaaa")
        bad = self.ledger / "review-aaaaaaaaaaaa.json"
        bad.write_text("not json")
        result = self.caller('parent=R\n' + block + '\nprintf "CONTINUED\\n"')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(bad.name, result.stderr)
        self.assertNotIn("CONTINUED", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
