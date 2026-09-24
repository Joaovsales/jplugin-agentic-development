#!/usr/bin/env python3
"""routine_run.py — launch a routine so it cannot start in a state that stops it.

On 2026-09-11 an `improve` run was recorded as completed while its output ended
at an interactive Codex startup screen: `MCP startup incomplete (failed: linear)`,
no selection, no result. The session had inherited an MCP server no routine step
uses, and it had been launched interactively, so it waited for a human who was
never coming. Both conditions came from the hand-written launch command, so this
launcher writes the command itself:

    routine_run.py run --routine <name> --harness <claude|codex> --log-dir <dir>
                       [--mcp-config <file>] [--timeout S]

* **Always non-interactive**, stdin closed: `claude -p`, `codex exec`.
* **Zero MCP servers by default.** A routine gets an integration only by naming
  it in `--mcp-config`; every other server is off.
* **The prompt is the repo's file** `references/routine-prompts/<name>.md`, so a
  copy pasted into a scheduler cannot drift.

Completion is stated, not inferred. The prompt tells the agent to print
`ROUTINE-ENVELOPE start {...}` first and `ROUTINE-ENVELOPE finish {...}` or
`ROUTINE-ENVELOPE failure {...}` last, each at the start of its own line. A run
succeeds when the exit code is 0, a start and a finish were printed and no
failure was. A run that printed no envelope line at all never began -- nothing
was claimed or branched -- so it is retried exactly once. Success is silent;
failure persists the output under `<log-dir>/<routine>-<UTC stamp>-<suffix>/`, prints one
`ROUTINE FAILED` block to stderr and exits 1. A usage error exits 2.

Standard library only, so it runs wherever `/wrap-up-session` does.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

PROMPTS = pathlib.Path(__file__).resolve().parent.parent / "references" / "routine-prompts"
ENVELOPE = "ROUTINE-ENVELOPE"
KINDS = ("start", "finish", "failure")
HARNESSES = ("claude", "codex")
#: The finish outcomes each routine may report -- the one table the prompts
#: restate (tests/test-routine-run.sh pins every prompt to its row). Membership
#: is also what makes a routine name valid.
#: An escalation is not an outcome: `fix` escalates by stopping non-zero, and
#: that stop prints a `failure` line, so the run has one completion signal.
ROUTINE_OUTCOMES: Dict[str, tuple] = {
    "fix": ("pr_opened", "no_candidate"),
    "improve": ("pr_opened", "no_candidate"),
    "plan": ("pr_opened", "no_candidate"),
    "janitor": ("pr_opened",),
    "architect": ("pr_opened",),
    "tidy": ("pr_opened",),
}
NEVER_STARTED = "never started"
#: Four hours: longer than any routine takes, short enough that a stalled
#: session is reported the same night instead of holding the scheduler slot.
DEFAULT_TIMEOUT_S = 4 * 60 * 60
#: Test seam: a JSON array that replaces the harness executable (argv[0]).
HARNESS_BIN_ENV = "ROUTINE_RUN_HARNESS_BIN"
QUOTE_LIMIT = 200
USAGE_ERROR = 2
RUN_FAILED = 1


class UsageError(Exception):
    """A launch that must not start: exit 2, before any harness runs."""


@dataclass
class Attempt:
    stdout: str = ""
    stderr: str = ""
    exit_code: Optional[int] = None
    error: Optional[str] = None


@dataclass
class Verdict:
    """Why an attempt failed, and whether re-running it is safe."""

    reason: str
    #: True only for a run that printed no envelope line: nothing was claimed or branched.
    retryable: bool = False


@dataclass
class RunResult:
    """Every attempt of one run with its verdict, in launch order; the last decides."""

    routine: str
    harness: str
    attempts: List[Tuple[Attempt, Optional[Verdict]]]

    @property
    def succeeded(self) -> bool:
        return self.attempts[-1][1] is None

    def to_json(self) -> dict:
        last, verdict = self.attempts[-1]
        return {"routine": self.routine, "harness": self.harness, "reason": verdict.reason,
                "exit_code": last.exit_code, "attempts": len(self.attempts),
                "attempt_reasons": [v.reason for _, v in self.attempts]}

    def render(self, run_dir: pathlib.Path) -> str:
        data = self.to_json()
        rows = [f"  {label}: {data[key]}" for label, key in
                (("routine", "routine"), ("reason", "reason"), ("exit code", "exit_code"), ("attempts", "attempts"))]
        return "\n".join(["ROUTINE FAILED", *rows, f"  log dir: {run_dir}"])


@dataclass
class Envelope:
    seen: bool = False
    by_kind: Dict[str, List[dict]] = field(default_factory=lambda: {kind: [] for kind in KINDS})
    malformed: Optional[str] = None


def build_command(harness: str, prompt: str, mcp_config: Optional[str] = None) -> List[str]:
    """The non-interactive argv for `harness`, with only the named MCP servers.

    For `codex` this reads `$CODEX_HOME/config.toml` (default `~/.codex/`) to
    learn which servers exist, so each one not named can be switched off.
    """
    if mcp_config is not None and not pathlib.Path(mcp_config).is_file():
        raise UsageError(f"--mcp-config file not found: {mcp_config}")
    allowed = _allowed_servers(mcp_config)
    if harness == "claude":
        # Plain `-p` prints only the final message; the start line is printed at
        # the top of the session, so every assistant message has to be streamed.
        argv = ["claude", "-p", prompt, "--strict-mcp-config", "--output-format", "stream-json", "--verbose"]
        return argv + (["--mcp-config", mcp_config] if mcp_config else [])
    if harness == "codex":
        return ["codex", "exec", *_codex_disable_flags(allowed), prompt]
    raise UsageError(f"unknown harness {harness!r} ({', '.join(HARNESSES)})")


def _allowed_servers(mcp_config: Optional[str]) -> set:
    if mcp_config is None:
        return set()
    try:
        servers = json.loads(pathlib.Path(mcp_config).read_text(encoding="utf-8"))["mcpServers"]
    except (ValueError, KeyError, TypeError) as exc:
        raise UsageError(f"--mcp-config {mcp_config} has no readable mcpServers object: {exc}") from exc
    return set(servers)


def _codex_disable_flags(allowed: set) -> List[str]:
    """`-c mcp_servers.<name>.enabled=false` for each configured server not allowed."""
    config = pathlib.Path(os.environ.get("CODEX_HOME") or pathlib.Path.home() / ".codex") / "config.toml"
    try:
        configured = list(tomllib.loads(config.read_text(encoding="utf-8")).get("mcp_servers", {}))
    except FileNotFoundError:
        configured = []
    except tomllib.TOMLDecodeError as exc:
        raise UsageError(f"{config} is not valid TOML: {exc}") from exc
    unknown = sorted(allowed - set(configured))
    if unknown:
        raise UsageError(f"--mcp-config names servers {config} does not configure: {', '.join(unknown)}")
    return [arg for name in configured if name not in allowed for arg in ("-c", f"mcp_servers.{name}.enabled=false")]


def read_prompt(routine: str) -> str:
    path = PROMPTS / f"{routine}.md"
    if routine not in ROUTINE_OUTCOMES or not path.is_file():
        raise UsageError(f"unknown routine {routine!r}: no prompt at {path}")
    return path.read_text(encoding="utf-8")


def transcript_lines(attempt: Attempt) -> List[str]:
    """Every line the agent could have printed, stream-json events unwrapped."""
    lines: List[str] = []
    for line in attempt.stdout.splitlines():
        lines.extend(_event_lines(line))
    return lines + attempt.stderr.splitlines()


def _event_lines(line: str) -> List[str]:
    """A raw line as itself; a stream-json event as its assistant text, else nothing.

    Tool results are dropped on purpose: a `cat` of a prompt file is not the
    agent saying it started.
    """
    try:
        event = json.loads(line)
    except ValueError:
        return [line]
    if not isinstance(event, dict):
        return [line]
    if event.get("type") != "assistant":
        return []
    blocks = (event.get("message") or {}).get("content") or []
    texts = [b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "text"]
    return [piece for text in texts for piece in str(text).splitlines()]


def read_envelope(lines: Sequence[str], routine: str) -> Envelope:
    """Only a line that *starts* with the marker counts; an echo mid-line never does."""
    envelope = Envelope()
    for line in lines:
        if not line.startswith(ENVELOPE):
            continue
        envelope.seen = True
        try:
            kind, payload = _parse_envelope_line(line, routine)
        except ValueError as exc:
            envelope.malformed = envelope.malformed or f"{exc}: {_quote(line)}"
            continue
        envelope.by_kind[kind].append(payload)
    return envelope


def _parse_envelope_line(line: str, routine: str):
    parts = line.split(" ", 2)
    if len(parts) != 3 or parts[0] != ENVELOPE or parts[1] not in KINDS:
        raise ValueError(f"not `{ENVELOPE} {'|'.join(KINDS)} {{json}}`")
    payload = json.loads(parts[2])  # JSONDecodeError is a ValueError
    if not isinstance(payload, dict) or payload.get("routine") != routine:
        raise ValueError(f"not an envelope for routine {routine!r}")
    outcomes = ROUTINE_OUTCOMES[routine]
    if parts[1] == "finish" and payload.get("outcome") not in outcomes:
        raise ValueError(f"finish outcome is not one of {', '.join(outcomes)}")
    if parts[1] == "failure" and not isinstance(payload.get("reason"), str):
        raise ValueError("failure carries no reason")
    return parts[1], payload


def judge(attempt: Attempt, routine: str) -> Optional[Verdict]:
    """None for success, else the first check that did not hold."""
    if attempt.error:
        return Verdict(attempt.error)
    if not (attempt.stdout.strip() or attempt.stderr.strip()):
        return Verdict("empty output")
    lines = transcript_lines(attempt)
    envelope = read_envelope(lines, routine)
    if not envelope.seen:
        last = next((line for line in reversed(lines) if line.strip()), "")
        return Verdict(f"{NEVER_STARTED} - last output: {_quote(last)}", retryable=True)
    if envelope.by_kind["failure"]:
        return Verdict(f"reported failure: {envelope.by_kind['failure'][0]['reason']}")
    if envelope.malformed:
        return Verdict(f"malformed envelope: {envelope.malformed}")
    if not envelope.by_kind["start"]:
        return Verdict("malformed envelope: finish without start")
    if not envelope.by_kind["finish"]:
        return Verdict("exited without a result")
    return None if attempt.exit_code == 0 else Verdict(f"non-zero exit {attempt.exit_code}")


def launch(argv: Sequence[str], timeout: int) -> Attempt:
    """One harness run: stdin closed, output captured as bytes and decoded safely."""
    exe = shutil.which(argv[0])
    if exe is None:
        return Attempt(error=f"harness could not start: {argv[0]} not found")
    try:
        done = subprocess.run([exe, *argv[1:]], stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        return Attempt(_decode(exc.stdout), _decode(exc.stderr), error=f"timeout after {timeout}s")
    except OSError as exc:
        return Attempt(error=f"harness could not start: {exc}")
    return Attempt(_decode(done.stdout), _decode(done.stderr), done.returncode)


def run_with_retry(argv: Sequence[str], routine: str, timeout: int) -> List[Tuple[Attempt, Optional[Verdict]]]:
    """Every `(attempt, verdict)` launched, retrying once only a run that never began.

    The last verdict decides the run: None means it succeeded.
    """
    history: List[tuple] = []
    for _ in range(2):
        attempt = launch(argv, timeout)
        verdict = judge(attempt, routine)
        history.append((attempt, verdict))
        if verdict is None or not verdict.retryable:
            break
    return history


def with_harness_override(argv: List[str]) -> List[str]:
    """`argv` with its executable replaced by the test seam's JSON array, if set."""
    override = os.environ.get(HARNESS_BIN_ENV)
    if not override:
        return argv
    try:
        executable = json.loads(override)
    except ValueError as exc:
        raise UsageError(f"{HARNESS_BIN_ENV} is not JSON: {exc}") from exc
    if not (isinstance(executable, list) and executable and all(isinstance(a, str) for a in executable)):
        raise UsageError(f"{HARNESS_BIN_ENV} must be a non-empty JSON array of strings")
    return [*executable, *argv[1:]]


def report_failure(log_dir: str, report: RunResult) -> None:
    """The last attempt's streams at the top, each earlier one as `attempt-<n>.*`.

    The directory is `<routine>-<UTC stamp>-<unique suffix>`, so two failures in
    the same second each keep their record.
    """
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    pathlib.Path(log_dir).mkdir(parents=True, exist_ok=True)
    run_dir = pathlib.Path(tempfile.mkdtemp(prefix=f"{report.routine}-{stamp}-", dir=log_dir))
    *earlier, (last, _) = report.attempts
    for number, (attempt, _) in enumerate(earlier, start=1):
        _write_streams(run_dir, f"attempt-{number}.", attempt)
    _write_streams(run_dir, "", last)
    (run_dir / "verdict.json").write_text(json.dumps(report.to_json(), indent=2) + "\n", encoding="utf-8")
    print(report.render(run_dir), file=sys.stderr)


def _write_streams(run_dir: pathlib.Path, prefix: str, attempt: Attempt) -> None:
    (run_dir / f"{prefix}stdout.txt").write_text(attempt.stdout, encoding="utf-8")
    (run_dir / f"{prefix}stderr.txt").write_text(attempt.stderr, encoding="utf-8")


def _decode(data: Optional[bytes]) -> str:
    return (data or b"").decode("utf-8", errors="replace")


def _quote(line: str) -> str:
    return line if len(line) <= QUOTE_LIMIT else line[:QUOTE_LIMIT] + "..."


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run", help="launch one routine unattended and judge its envelope")
    run.add_argument("--routine", required=True)
    run.add_argument("--harness", required=True, choices=HARNESSES)
    run.add_argument("--log-dir", required=True)
    run.add_argument("--mcp-config", help="the only MCP servers the routine may load")
    run.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S, help="seconds per attempt")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    sys.stderr.reconfigure(errors="replace")  # a quoted line must never crash the report
    args = build_parser().parse_args(argv)
    try:
        command = with_harness_override(build_command(args.harness, read_prompt(args.routine), args.mcp_config))
    except UsageError as exc:
        print(f"routine_run: {exc}", file=sys.stderr)
        return USAGE_ERROR
    result = RunResult(args.routine, args.harness, run_with_retry(command, args.routine, args.timeout))
    if result.succeeded:
        return 0
    report_failure(args.log_dir, result)
    return RUN_FAILED


if __name__ == "__main__":
    sys.exit(main())
