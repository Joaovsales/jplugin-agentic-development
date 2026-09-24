#!/usr/bin/env bash
# tests/test-routine-run.sh — the routine launcher: a routine cannot start in a
# state that stops it, and a run that did not finish is never recorded as done.
#
# specs/routine-run-envelope.md AC1–AC7. The 2026-09-11 `improve` run stalled at
# an interactive Codex TUI whose last line was an MCP failure for a server no
# routine step uses, and was recorded as completed. The launcher builds the
# harness command itself (non-interactive, zero MCP servers by default), retries
# once a run that never printed its start line, and judges the run by the
# envelope the prompt tells the agent to print — never by the exit code alone.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

# A failing Python half is counted, not fatal, so the AC7 checks below still report.
"$TEST_PYTHON" - <<'PY' || { _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1)); }
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = pathlib.Path(os.environ["ROOT"])
SCRIPT = ROOT / ".agents/skills/wrap-up-session/scripts/routine_run.py"
PROMPTS = ROOT / ".agents/skills/wrap-up-session/references/routine-prompts"
FIXTURES = ROOT / "tests/fixtures/routine-run"
FAKE = FIXTURES / "fake_harness.py"
MCP_LINE = "MCP startup incomplete (failed: linear)\n"

spec = importlib.util.spec_from_file_location("routine_run", SCRIPT)
routine_run = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = routine_run
spec.loader.exec_module(routine_run)


def envelope(kind, **fields):
    return f"ROUTINE-ENVELOPE {kind} {json.dumps({'routine': 'improve', **fields})}\n"


START = envelope("start")
FINISH = envelope("finish", outcome="pr_opened")


class Run:
    """One launcher invocation against the fake harness, in its own temp dir."""

    def __init__(self, plan, *extra, harness="codex", routine="improve", env=None):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.logs = self.tmp / "logs"
        (self.tmp / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
        run_env = {
            **os.environ,
            "FAKE_HARNESS_PLAN": str(self.tmp / "plan.json"),
            "FAKE_HARNESS_STATE": str(self.tmp),
            "ROUTINE_RUN_HARNESS_BIN": json.dumps([sys.executable, str(FAKE)]),
            "CODEX_HOME": str(self.tmp / "no-codex-home"),
            **(env or {}),
        }
        argv = [sys.executable, str(SCRIPT), "run", "--routine", routine,
                "--harness", harness, "--log-dir", str(self.logs), *extra]
        done = subprocess.run(argv, env=run_env, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=120)
        self.code, self.stdout, self.stderr = done.returncode, done.stdout, done.stderr

    @property
    def attempts(self):
        counter = self.tmp / "attempts"
        return int(counter.read_text()) if counter.exists() else 0

    @property
    def launched(self):
        return json.loads((self.tmp / "argv.json").read_text(encoding="utf-8"))

    def run_dirs(self):
        return sorted(self.logs.iterdir()) if self.logs.exists() else []

    def verdict(self):
        (run_dir,) = self.run_dirs()
        return json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))


class ClaudeArgvTests(unittest.TestCase):
    """AC1 — non-interactive, and no MCP server unless one is named."""

    def test_default_argv_is_print_mode_with_strict_empty_mcp(self):
        argv = routine_run.build_command("claude", "PROMPT", None)
        self.assertEqual(argv[:4], ["claude", "-p", "PROMPT", "--strict-mcp-config"])
        self.assertNotIn("--mcp-config", argv)

    def test_default_argv_streams_every_message(self):
        # Plain `-p` prints only the final message, so a start line printed at
        # the top of the session would never reach the launcher.
        argv = routine_run.build_command("claude", "PROMPT", None)
        self.assertIn("stream-json", argv)
        self.assertIn("--verbose", argv)

    def test_named_mcp_config_is_passed_through(self):
        allow = str(FIXTURES / "allow-github.json")
        argv = routine_run.build_command("claude", "PROMPT", allow)
        self.assertEqual(argv[argv.index("--mcp-config") + 1], allow)
        self.assertIn("--strict-mcp-config", argv)

    def test_the_prompt_is_the_routine_file_and_stdin_is_closed(self):
        run = Run([{"stdout": START + FINISH}], harness="claude")
        self.assertEqual(run.code, 0, run.stderr)
        prompt = (PROMPTS / "improve.md").read_text(encoding="utf-8")
        self.assertEqual(run.launched["argv"][:3], ["-p", prompt, "--strict-mcp-config"])
        self.assertEqual(run.launched["stdin"], "")

    def test_unknown_routine_is_a_usage_error(self):
        run = Run([{"stdout": START + FINISH}], routine="imporve")
        self.assertEqual(run.code, 2)
        self.assertIn("imporve", run.stderr)
        self.assertEqual(run.attempts, 0)

    def test_unknown_harness_is_a_usage_error(self):
        run = Run([{"stdout": START + FINISH}], harness="gemini")
        self.assertEqual(run.code, 2)
        self.assertEqual(run.attempts, 0)

    def test_malformed_mcp_config_is_a_usage_error_for_claude_too(self):
        bad = pathlib.Path(tempfile.mkdtemp()) / "bad.json"
        bad.write_text("not json", encoding="utf-8")
        run = Run([{"stdout": START + FINISH}], "--mcp-config", str(bad), harness="claude")
        self.assertEqual(run.code, 2)
        self.assertEqual(run.attempts, 0)

    def test_missing_mcp_config_file_is_a_usage_error(self):
        run = Run([{"stdout": START + FINISH}], "--mcp-config", "no-such.json", harness="claude")
        self.assertEqual(run.code, 2)
        self.assertIn("no-such.json", run.stderr)
        self.assertEqual(run.attempts, 0)


class CodexArgvTests(unittest.TestCase):
    """AC2 — every configured server the allow list does not name is disabled."""

    def setUp(self):
        self._saved = os.environ.get("CODEX_HOME")

    def tearDown(self):
        if self._saved is None:
            os.environ.pop("CODEX_HOME", None)
        else:
            os.environ["CODEX_HOME"] = self._saved

    def overrides(self, argv):
        return [argv[i + 1] for i, arg in enumerate(argv) if arg == "-c"]

    def test_allowing_github_disables_only_linear(self):
        os.environ["CODEX_HOME"] = str(FIXTURES / "codex-home")
        argv = routine_run.build_command("codex", "PROMPT", str(FIXTURES / "allow-github.json"))
        self.assertEqual(argv[:2], ["codex", "exec"])
        self.assertIn("PROMPT", argv)
        self.assertEqual(self.overrides(argv), ["mcp_servers.linear.enabled=false"])

    def test_no_allow_list_disables_every_configured_server(self):
        os.environ["CODEX_HOME"] = str(FIXTURES / "codex-home")
        argv = routine_run.build_command("codex", "PROMPT", None)
        self.assertEqual(sorted(self.overrides(argv)),
                         ["mcp_servers.github.enabled=false", "mcp_servers.linear.enabled=false"])

    def test_missing_config_needs_no_overrides(self):
        os.environ["CODEX_HOME"] = tempfile.mkdtemp()
        argv = routine_run.build_command("codex", "PROMPT", None)
        self.assertEqual(argv, ["codex", "exec", "PROMPT"])

    def test_allowing_an_unconfigured_server_is_a_usage_error_before_launch(self):
        run = Run([{"stdout": START + FINISH}],
                  "--mcp-config", str(FIXTURES / "allow-unconfigured.json"),
                  env={"CODEX_HOME": str(FIXTURES / "codex-home")})
        self.assertEqual(run.code, 2)
        self.assertIn("jira", run.stderr)
        self.assertEqual(run.attempts, 0)


class RetryTests(unittest.TestCase):
    """AC3, AC4 — a run that never printed its start line is retried once."""

    def test_ac3_second_attempt_completes_silently(self):
        run = Run([{"stderr": MCP_LINE}, {"stderr": MCP_LINE, "stdout": START + FINISH}])
        self.assertEqual((run.code, run.stdout, run.stderr), (0, "", ""))
        self.assertEqual(run.attempts, 2)
        self.assertEqual(run.run_dirs(), [])

    def test_ac4_never_started_twice_fails_loudly_with_the_startup_line(self):
        run = Run([{"stderr": MCP_LINE}])
        self.assertEqual(run.code, 1)
        self.assertEqual(run.attempts, 2)
        self.assertIn("ROUTINE FAILED", run.stderr)
        self.assertIn("never started", run.stderr)
        self.assertIn("linear", run.stderr)
        (run_dir,) = run.run_dirs()
        self.assertTrue(run_dir.name.startswith("improve-"), run_dir.name)
        for name in ("stdout.txt", "stderr.txt", "verdict.json"):
            self.assertTrue((run_dir / name).is_file(), name)
        self.assertIn("linear", (run_dir / "stderr.txt").read_text(encoding="utf-8"))
        verdict = run.verdict()
        self.assertEqual(verdict["attempts"], 2)
        self.assertIn("never started", verdict["reason"])
        self.assertIn(str(run_dir), run.stderr)

    def test_a_retried_failure_keeps_the_first_attempts_evidence(self):
        second = "MCP startup incomplete (failed: github)\n"
        run = Run([{"stderr": MCP_LINE}, {"stderr": second}])
        (run_dir,) = run.run_dirs()
        self.assertIn("github", (run_dir / "stderr.txt").read_text(encoding="utf-8"))
        self.assertIn("linear", (run_dir / "attempt-1.stderr.txt").read_text(encoding="utf-8"))
        self.assertTrue((run_dir / "attempt-1.stdout.txt").is_file())
        reasons = run.verdict()["attempt_reasons"]
        self.assertEqual(len(reasons), 2)
        self.assertIn("linear", reasons[0])
        self.assertIn("github", reasons[1])

    def test_retry_follows_the_envelope_not_the_reason_wording(self):
        # A harness error whose text happens to begin with the never-started
        # wording must not be retried: retry is a property of the verdict.
        verdict = routine_run.judge(routine_run.Attempt(error="never started by the scheduler"), "improve")
        self.assertFalse(verdict.retryable)
        verdict = routine_run.judge(routine_run.Attempt(stderr=MCP_LINE, exit_code=0), "improve")
        self.assertTrue(verdict.retryable)

    def test_an_envelope_mid_line_never_counts(self):
        run = Run([{"stdout": "echo: " + START + "> " + FINISH}])
        self.assertEqual(run.code, 1)
        self.assertEqual(run.attempts, 2)
        self.assertIn("never started", run.verdict()["reason"])


class VerdictTests(unittest.TestCase):
    """AC5 — every other failure names its reason and is not retried."""

    def assert_fails(self, plan, reason, *extra):
        run = Run(plan, *extra)
        self.assertEqual(run.code, 1, run.stderr)
        self.assertEqual(run.attempts, 1)
        self.assertIn(reason, run.verdict()["reason"])
        self.assertIn(reason, run.stderr)
        return run

    def test_start_without_finish(self):
        self.assert_fails([{"stdout": START}], "exited without a result")

    def test_reported_failure_quotes_the_agent_reason(self):
        run = self.assert_fails([{"stdout": START + envelope("failure", reason="doctor red")}],
                                "reported failure")
        self.assertIn("doctor red", run.verdict()["reason"])

    def test_non_zero_exit_fails_even_with_finish(self):
        run = self.assert_fails([{"stdout": START + FINISH, "exit": 3}], "non-zero exit")
        self.assertEqual(run.verdict()["exit_code"], 3)

    def test_empty_output(self):
        self.assert_fails([{}], "empty output")

    def test_malformed_json(self):
        self.assert_fails([{"stdout": START + "ROUTINE-ENVELOPE finish {oops\n"}],
                          "malformed envelope")

    def test_another_routines_envelope_is_malformed(self):
        other = START.replace("improve", "fix") + FINISH.replace("improve", "fix")
        self.assert_fails([{"stdout": other}], "malformed envelope")

    def test_unknown_outcome_is_malformed(self):
        self.assert_fails([{"stdout": START + envelope("finish", outcome="done")}],
                          "malformed envelope")

    def test_an_outcome_another_routine_owns_is_malformed(self):
        # `no_candidate` is a consumer's outcome; a producer that prints it did not follow its prompt.
        lines = ('ROUTINE-ENVELOPE start {"routine": "janitor"}\n'
                 'ROUTINE-ENVELOPE finish {"routine": "janitor", "outcome": "no_candidate"}\n')
        run = Run([{"stdout": lines}], routine="janitor")
        self.assertEqual(run.code, 1, run.stderr)
        self.assertEqual(run.attempts, 1)
        self.assertIn("malformed envelope", run.verdict()["reason"])

    def test_finish_without_start_is_malformed(self):
        self.assert_fails([{"stdout": FINISH}], "malformed envelope")

    def test_timeout(self):
        self.assert_fails([{"sleep": 30, "stdout": START + FINISH}], "timeout", "--timeout", "2")

    def test_missing_harness_binary_is_not_retried(self):
        run = Run([{}], env={"ROUTINE_RUN_HARNESS_BIN": json.dumps([str(FIXTURES / "no-such-harness")])})
        self.assertEqual(run.code, 1)
        self.assertIn("harness could not start", run.stderr)
        self.assertEqual(run.verdict()["attempts"], 1)


class SilentSuccessTests(unittest.TestCase):
    """AC6 — warnings never decide the verdict; success prints nothing."""

    def test_ac6_mcp_warning_then_full_envelope(self):
        run = Run([{"stderr": MCP_LINE, "stdout": START + "working\n" + FINISH}])
        self.assertEqual((run.code, run.stdout, run.stderr), (0, "", ""))
        self.assertEqual(run.attempts, 1)
        self.assertEqual(run.run_dirs(), [])

    def test_non_utf8_output_does_not_crash(self):
        run = Run([{"stdout_hex": "fffe0a", "stdout": START + FINISH}])
        self.assertEqual((run.code, run.stderr), (0, ""))

    def test_claude_stream_json_counts_only_assistant_text(self):
        def event(kind, block):
            return json.dumps({"type": kind, "message": {"content": [block]}}) + "\n"

        head = json.dumps({"type": "system", "subtype": "init"}) + "\n"
        said_start = event("assistant", {"type": "text", "text": "Starting.\n" + START})
        tool_echo = event("user", {"type": "tool_result", "content": FINISH})
        said_finish = event("assistant", {"type": "text", "text": FINISH})
        done = Run([{"stdout": head + said_start + said_finish}], harness="claude")
        self.assertEqual((done.code, done.stderr), (0, ""))
        echoed = Run([{"stdout": head + said_start + tool_echo}], harness="claude")
        self.assertEqual(echoed.code, 1)
        self.assertIn("exited without a result", echoed.verdict()["reason"])


class ReportTests(unittest.TestCase):
    def test_two_failures_in_the_same_second_keep_both_records(self):
        logs = pathlib.Path(tempfile.mkdtemp())
        attempt = routine_run.Attempt(stderr=MCP_LINE, exit_code=0)
        verdict = routine_run.judge(attempt, "improve")
        result = routine_run.RunResult("improve", "codex", [(attempt, verdict)])
        saved_stderr, sys.stderr = sys.stderr, open(os.devnull, "w")
        try:
            routine_run.report_failure(str(logs), result)
            routine_run.report_failure(str(logs), result)
        finally:
            sys.stderr.close()
            sys.stderr = saved_stderr
        dirs = sorted(logs.iterdir())
        self.assertEqual(len(dirs), 2)
        self.assertTrue(all(d.name.startswith("improve-") for d in dirs))


class PromptAgreementTests(unittest.TestCase):
    """The prompts restate the launcher's outcome table; a drift fails here, not at 03:00."""

    def test_every_prompt_has_an_outcome_row_and_every_row_a_prompt(self):
        prompts = {p.stem for p in PROMPTS.glob("*.md") if p.stem != "README"}
        self.assertEqual(prompts, set(routine_run.ROUTINE_OUTCOMES))

    def test_an_escalation_is_a_failure_line_not_a_finish_outcome(self):
        # fix escalates by stopping non-zero; a `finish` beside a non-zero exit would
        # give the run two completion signals that disagree.
        self.assertNotIn("escalated", routine_run.ROUTINE_OUTCOMES["fix"])
        self.assertNotIn("escalated", (PROMPTS / "fix.md").read_text(encoding="utf-8"))

    def test_each_prompts_finish_line_lists_exactly_its_outcomes(self):
        for name, outcomes in routine_run.ROUTINE_OUTCOMES.items():
            with self.subTest(routine=name):
                text = (PROMPTS / f"{name}.md").read_text(encoding="utf-8")
                match = re.search(
                    r'ROUTINE-ENVELOPE finish \{"routine": "' + name + r'", "outcome": "<?([a-z_|]+)>?"\}', text)
                self.assertIsNotNone(match, f"{name}.md has no finish line")
                self.assertEqual(tuple(match.group(1).split("|")), outcomes)


runner = unittest.TextTestRunner(verbosity=0, stream=sys.stderr)
result = runner.run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
count = result.testsRun
if not result.wasSuccessful():
    print(f"  -> {len(result.failures) + len(result.errors)}/{count} assertions FAILED")
    sys.exit(1)
print(f"  -> {count} assertions passed")
PY

# ============================================================================
# AC7 — the prompts carry the envelope and the integrations-optional rule, and
# the launcher is documented as the way to schedule a routine
# ============================================================================
WRAP=.agents/skills/wrap-up-session/references
cd "$ROOT"
for name in janitor architect tidy fix improve plan; do
  p="$WRAP/routine-prompts/$name.md"
  for kind in start finish failure; do
    assert_file_contains "$p" "\`ROUTINE-ENVELOPE $kind {\"routine\": \"$name\"" \
      "AC7: $name.md tells the agent to print its $kind line"
  done
  assert_prose_contains "$p" "No step needs an MCP server" \
    "AC7: $name.md says integrations are optional"
  assert_file_not_matches "$p" '^ROUTINE-ENVELOPE' \
    "AC7: $name.md never starts a line with the envelope, so an echoed prompt cannot count"
done
assert_file_matches "$WRAP/routines.md" '^## Launching a routine' \
  "AC7: routines.md has a Launching a routine section"
assert_file_contains "$WRAP/routines.md" "routine_run.py run --routine" \
  "AC7: routines.md names the launcher"
assert_file_contains "$WRAP/routine-prompts/README.md" "routine_run.py run --routine" \
  "AC7: the prompts README names the launcher"
assert_file_not_matches "$WRAP/routine-prompts/README.md" 'copy it into the scheduler' \
  "AC7: the prompts README no longer says to paste the prompt into a scheduler"

finish
