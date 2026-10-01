---
title: tests/run.sh hangs at test-pre-push-gate when stdin is an open pipe
date: 2026-09-30
problem_type: test-failure
module: tests/test-pre-push-gate.sh
tags: [tests, hooks, stdin, bash, session-start]
symptoms: "`bash tests/run.sh` launched from an agent shell printed nothing after tests/test-pre-push-gate.sh and never exited; `ps` showed a `cat` child under a copied session-start.sh. Two such hung runs were found in the same session"
root_cause: "tests/test-pre-push-gate.sh copies .claude/hooks/session-start.sh into a temp repo and runs it (tests/test-pre-push-gate.sh:217-218). The hook reads its JSON payload with `HOOK_INPUT=$(cat 2>/dev/null || true)` (.claude/hooks/session-start.sh:42), which blocks until stdin reaches EOF. An agent shell leaves stdin as an open pipe, so EOF never comes"
resolution: "Initially run the suite with `</dev/null`; the later test fix redirected both hook invocations themselves, so the suite no longer depends on its launcher's stdin"
---

**Status**: superseded by the test-level fix on 2026-09-21; see [the follow-up](test-inherits-open-stdin-and-the-hook-reads-it-to-eof.md).

## Symptoms

The full suite ran green up to `tests/test-pre-push-gate.sh`, then produced no
further output and did not exit. Nothing on stderr, no failing assertion. `ps`
showed the tree `run.sh → test-pre-push-gate.sh → session-start.sh → cat`.

## Root cause

The session-start hook is designed to be fed by the harness: Claude Code writes
a JSON object on stdin and the hook slurps it
(`.claude/hooks/session-start.sh:42`). Under a terminal, stdin is a tty and
`cat` returns at the first EOF the shell sends; under most CI runners stdin is
`/dev/null`. Under an agent's Bash tool stdin is a pipe held open by the
harness, so `cat` waits forever.

The pre-push-gate test runs the real hook to check that the banner surfaces the
shortcut ledger (`tests/test-pre-push-gate.sh:217-218`), so it inherits the
hook's stdin contract.

## Initial workaround and later fix

The initial workaround closed stdin at the suite boundary:

```bash
bash tests/run.sh </dev/null
```

The two test invocations now each use `</dev/null`
(`tests/test-pre-push-gate.sh:218`, `:224`), so launching the suite with an open
stdin no longer hangs here. The [follow-up](test-inherits-open-stdin-and-the-hook-reads-it-to-eof.md)
records the reproducer and the test-level correction. The underlying lesson is
to close stdin at the call site that executes a hook when its payload is irrelevant.

## Prevention

If a suite run shows no progress for minutes with no failure printed, check
`ps` for a `cat` under `session-start.sh` before assuming a slow test. Any new
test that copies and runs a hook should pipe an explicit payload or `</dev/null`
into it rather than relying on the caller's stdin.

## Related PTY recipe observation — 2026-09-08

While generating verify-task-registry, this session observed util-linux `script`
consume subsequent recipe lines when the parent Bash program itself came from
stdin. Redirecting the noninteractive CLI driver's stdin with `</dev/null>` kept
those lines with the parent shell. The persisted recipe uses that boundary in
`.agents/skills/verify-task-registry/SKILL.md:65`; the successful walkthrough is in
`tasks/e2e-log.md`. Both cases require explicit ownership of stdin, though the
failure symptoms differ (blocking hook versus consumed script input).
