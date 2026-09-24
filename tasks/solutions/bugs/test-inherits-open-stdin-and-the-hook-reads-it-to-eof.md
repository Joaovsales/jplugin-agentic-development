---
title: A test that inherits an open stdin hangs when the hook it runs reads stdin to EOF
date: 2026-09-21
problem_type: test-failure
module: tests/test-pre-push-gate.sh
tags: [bash, hooks, stdin, tests, hang]
symptoms: "`bash tests/test-pre-push-gate.sh < <(sleep 1000)` printed the `Hook: no network or tracker command invoked` assertion and then produced nothing — no failure, no timeout, the process simply never exited"
root_cause: "The session-start hook reads stdin to EOF whenever stdin is not a terminal (`if [ ! -t 0 ]; then HOOK_INPUT=$(cat 2>/dev/null || true)` at .claude/hooks/session-start.sh:41-42). The two Banner-block invocations ran the hook with the suite's own stdin inherited, so a launcher that holds stdin open — a background process runner, a pipe that never closes — made `cat` block forever"
resolution: "Add `</dev/null` to both invocations (tests/test-pre-push-gate.sh:218 and :224), matching the sibling quote-safety call at :262. Every other test invocation of the hook already pipes stdin from `printf`, which closes it. The hook itself is unchanged"
---

## Symptoms

The suite ran to the `Hook: no network or tracker command invoked` assertion and
stopped. No assertion failed, no error printed, and the process stayed alive
indefinitely. Under a terminal (`-t 0` true) or with `</dev/null` on the launch the
same file completes with 51 assertions passed, so the hang was invisible during
ordinary interactive development.

## Root cause

`.claude/hooks/session-start.sh:41-42` decides whether it was launched by the
harness by testing `[ ! -t 0 ]`, and if stdin is not a terminal it drains it with
`cat` to capture the hook event JSON. That is correct for the harness, which
writes one JSON object and closes the pipe. It is wrong for any caller that leaves
stdin open without writing to it: `cat` waits for EOF that never comes.

The two Banner-block test calls at `tests/test-pre-push-gate.sh:218` and `:224`
were the only invocations in `tests/*.sh` that inherited stdin. The sibling call at
`:262` already carried `</dev/null`, and every call in `tests/test-session-start.sh`
feeds the hook from a `printf ... |` pipe, which closes on its own.

## Resolution

Both calls now read:

```bash
BAN_OUT="$( cd "$D" && CCW_SESSION_GUARD=0 bash ./session-start.sh </dev/null 2>/dev/null )"
```

Verified both launch modes complete with 51 assertions passed:
`bash tests/test-pre-push-gate.sh </dev/null` and
`bash tests/test-pre-push-gate.sh < <(sleep 30)`.

## Prevention

Any test that executes a hook directly must decide stdin explicitly — either pipe
the event JSON it wants the hook to see, or `</dev/null` when the event is
irrelevant. Inheriting stdin is never neutral for a program that branches on
`[ -t 0 ]`: it behaves one way at a keyboard and another under a runner. The failure
mode is a silent hang rather than a red assertion, so it will not show up in a
normal run; reproduce with `< <(sleep N)` before trusting a hook test.

Related: [[grep-zero-matches-aborts-hooks-under-set-e-pipefail]] — the same hook,
a different way that "works at my terminal" concealed a defect in the non-tty path.

## Merged from test-suite-hangs-when-stdin-is-an-open-pipe (2026-09-07)

An earlier occurrence of this same hang — before the two Banner-block call sites
above regressed — was worked around at the suite level: run the whole suite as
`bash tests/run.sh </dev/null` (the fix above instead closes stdin at each call
site inside `tests/test-pre-push-gate.sh`, so the suite no longer needs the
wrapper). If a suite run shows no progress for minutes with no failure printed,
check `ps` for a `cat` process under `session-start.sh` before assuming a slow
test.

That session also noted a related PTY observation while generating
verify-task-registry: util-linux `script` consumes subsequent recipe lines when
the parent Bash program itself came from stdin. Redirecting the noninteractive
CLI driver's stdin with `</dev/null` kept those lines with the parent shell
(`.agents/skills/verify-task-registry/SKILL.md:65`; walkthrough in
`tasks/e2e-log.md`). Same principle — a program that branches on stdin state
needs stdin owned explicitly — different failure mode (consumed script input
rather than a blocking hook).
