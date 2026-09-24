# Spec — routine launcher: a routine cannot start in a state that stops it

> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/127
> Related: #123 (PR-to-issue closure verification — separate gap, out of scope).

## Problem

On 2026-09-11 the private-knowledge-base `improve` run was recorded as completed.
Its captured output stopped at the Codex **TUI** startup screen, whose last line
was `MCP startup incomplete (failed: linear)`: no selection, no result.

Two things made that possible, and neither belongs to the routine:

1. **The session inherited the operator's global integrations.** No routine step
   uses an MCP server: the tracker is reached through `task-registry` over `gh`,
   and everything else is shell and git. `linear` was loaded only because it was
   enabled globally on that machine.
2. **The session was launched interactively.** A TUI waits for a human, and an
   unattended scheduler has none. An optional MCP failure does not normally stop
   a session, so the interactive launch, not `linear`, is the likely reason the
   routine never began. The `linear` line was just the last output before the stall.

The fix removes both conditions at the source. Detection stays as the last line
of defense, not the mechanism.

## Behavior

### 1. The launcher owns the invocation (removes both conditions)

`.agents/skills/wrap-up-session/scripts/routine_run.py run --routine <name>
--harness <claude|codex> --log-dir <dir> [--mcp-config <file>] [--timeout S]`
builds the harness command itself. The operator no longer hand-writes it, so the
mistake above cannot be made:

| Harness | Command built |
|---|---|
| `claude` | `claude -p <prompt> --strict-mcp-config --output-format stream-json --verbose [--mcp-config <file>]` — plain `-p` prints only the final message, so the start line would never reach the launcher; only assistant text counts |
| `codex` | `codex exec <prompt>` plus `-c mcp_servers.<name>.enabled=false` for every server in the user's `~/.codex/config.toml` (or `$CODEX_HOME`) that `--mcp-config` does not list |

- **Always non-interactive**, stdin closed. A TUI cannot be reached.
- **Zero MCP servers by default.** A routine gets an integration only by naming
  it; an unrelated server is never loaded, so its startup failure cannot happen.
- The prompt is the routine's file in `references/routine-prompts/<name>.md`,
  read by the launcher. A copy pasted into a scheduler cannot drift from the repo.

### 2. The prompts say integrations are optional

Every routine prompt states: *no step needs an MCP server; if a tool or
integration is unavailable, continue — the tracker is `task-registry`, the rest
is shell.* A session launched some other way still proceeds.

### 3. A run that never began is retried once

If the session exits without printing its start line (see §4), nothing was
claimed or branched, so re-running is safe. The launcher retries **once**. It
never retries after the start line: the claim and branch steps already guard a
second run (idempotent claim; "branch exists" is loud).

### 4. Completion is stated, not inferred (the backstop)

The prompt tells the agent to print, each on its own line:
`ROUTINE-ENVELOPE start {"routine": "<name>"}` first, and last either
`ROUTINE-ENVELOPE finish {"routine": "<name>", "outcome": "pr_opened|no_candidate|escalated"}`
or `ROUTINE-ENVELOPE failure {"routine": "<name>", "reason": "…"}`.

A run succeeds when the exit code is 0, a `start` and a `finish` were printed, and
no `failure` was printed. Otherwise it fails, with the reason for the first check
that did not hold: timeout · empty output · never started (no envelope line at
all; quoting the last output line, such as an MCP failure) · reported failure ·
malformed envelope (bad JSON, another routine's name, an unknown outcome, a
`finish` with no `start`) · exited without a result · non-zero exit.

Success is silent, exit 0. Failure writes
`<log-dir>/<routine>-<UTC stamp>/{stdout.txt,stderr.txt,verdict.json}`, prints a
single `ROUTINE FAILED` block (routine, reason, exit code, attempts, log dir) to
stderr, and exits 1. A usage error exits 2.

## Edge Cases

- An MCP startup warning followed by a complete envelope is success. Warnings never decide the verdict.
- The `--mcp-config` list names a server that is not configured: loud usage error (exit 2) before launch.
- No `~/.codex/config.toml`: no `-c` overrides needed; not an error.
- The harness binary is missing: fails with `harness could not start`. Not retried, because it is not transient.
- An envelope line counts only at the start of a line, so a prompt echoed mid-line never counts.
- Non-UTF-8 output is decoded with `errors="replace"` and never crashes the launcher.

## Decisions

- `user`: resilience first. Remove the conditions, and keep loud detection only as a backstop.
- `assumed`: the launcher builds the command (`--harness`) instead of passing through argv. Passthrough would keep the hand-written, interactive launch possible.
- `assumed`: Codex per-server `enabled=false` via `-c`. **Unverified here** (Codex is not installed on the build host). It is tested against the built argv, and the first real run on the Orca host is the proof.
- `assumed`: one retry, only before the start line.
- `assumed` (build): Claude runs with `--output-format stream-json --verbose`. Plain `-p` prints only the final message, so the start line printed first could never be observed; AC1's prefix `claude -p <prompt> --strict-mcp-config` is unchanged.
- `assumed` (build): malformed envelope is judged before "exited without a result", so a garbled `finish` names itself instead of reading as a missing one; "never started" means no envelope-marked line at all, which keeps a malformed run from being retried.

## Acceptance Criteria

- [ ] AC1: `--harness claude` builds `claude -p <prompt file contents> --strict-mcp-config`, with `--mcp-config` only when given. The argv never enters interactive mode.
- [ ] AC2: `--harness codex` builds `codex exec …` with `enabled=false` for each configured server not allowed (fixture config lists `linear` and `github`; allowing `github` disables only `linear`).
- [ ] AC3: A fake harness whose first attempt prints only `MCP startup incomplete (failed: linear)` and whose second attempt completes the envelope: the run succeeds silently, with 2 attempts.
- [ ] AC4: A harness that never starts on both attempts fails. The reason names the startup line and `linear`, and stdout, stderr and `verdict.json` are persisted.
- [ ] AC5: `start` without `finish`, `failure`, a non-zero exit (even with `finish`), empty output, and a malformed envelope each fail with their reason and are not retried.
- [ ] AC6: A complete envelope preceded by an MCP warning succeeds on the first attempt, prints nothing, and writes no log dir.
- [ ] AC7: Every routine prompt carries the envelope lines and the integrations-are-optional rule. `routines.md` and the prompts README document the launcher as *the* way to schedule a routine.

## Implementation Paths

- `.agents/skills/wrap-up-session/scripts/routine_run.py`
- `.agents/skills/wrap-up-session/references/routines.md`
- `.agents/skills/wrap-up-session/references/routine-prompts/*.md`
- `tests/test-routine-run.sh`
- `tests/fixtures/routine-run/**`
