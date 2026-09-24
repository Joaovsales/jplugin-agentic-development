"""A stand-in harness for tests/test-routine-run.sh.

Plays one scripted attempt per invocation. FAKE_HARNESS_PLAN names a JSON list
of attempts — {"stdout", "stderr", "stdout_hex", "exit", "sleep"} — and
FAKE_HARNESS_STATE a directory where the attempt counter and the last argv and
stdin are recorded, so a test can assert how often and how it was launched.
"""

import json
import os
import pathlib
import sys
import time

state = pathlib.Path(os.environ["FAKE_HARNESS_STATE"])
plan = json.loads(pathlib.Path(os.environ["FAKE_HARNESS_PLAN"]).read_text(encoding="utf-8"))
counter = state / "attempts"
attempt = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(attempt + 1))
(state / "argv.json").write_text(
    json.dumps({"argv": sys.argv[1:], "stdin": sys.stdin.read()}), encoding="utf-8"
)

step = plan[min(attempt, len(plan) - 1)]
time.sleep(step.get("sleep", 0))
sys.stdout.buffer.write(bytes.fromhex(step.get("stdout_hex", "")))
sys.stdout.buffer.write(step.get("stdout", "").encode("utf-8"))
sys.stderr.buffer.write(step.get("stderr", "").encode("utf-8"))
sys.exit(step.get("exit", 0))
