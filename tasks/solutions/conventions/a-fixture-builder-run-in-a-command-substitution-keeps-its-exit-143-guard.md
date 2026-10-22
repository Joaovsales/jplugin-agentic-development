---
title: A fixture builder run in a command substitution keeps its `|| exit 143` guard
date: 2026-10-22
problem_type: convention
module: tests/lib.sh § setup primitives (_abort, fixture_dir, fixture_repo); test-file builders called as `$(…)` or `<(…)`
tags: [testing, bash, subshell, fixtures, false-green, aposd]
applies_when: writing or reviewing a test-file helper that calls fixture_dir or fixture_repo inside `$(…)`, `<(…)`, `( … )` or a background job, or reading a design finding that calls the guard dead code
---

## The claim

`tests/lib.sh`'s setup primitives stop the file by signalling its shell: `_abort`
prints the reason and, when it is not running in the file's own process, sends
`TERM` to `$$` and exits 143 (`tests/lib.sh:312-317`); the file's `TERM` trap
cleans up and exits 143 (`tests/lib.sh:310`). The header states the intent: the
stop reaches the file's shell even from inside a command substitution
(`tests/lib.sh:302-303`).

What the signal does **not** do is stop the subshell that called the primitive.
Bash delivers a trap to the main shell only when the command it is running
returns, and a command substitution is that command: the `$(…)` subshell keeps
executing until it exits on its own. The library's own `fixture_repo` therefore
guards its inner call — `d="$(fixture_dir)" || exit 143` (`tests/lib.sh:331`) —
because without it `git init` would run against an empty path, which is the
current directory: the 2026-09 "empty fixture dir commits the real tree"
incident (`git -C ""` falls back to cwd) is exactly that failure.

Every test-file builder invoked as `X="$(builder)"` or `< <(builder)` is in the
same position. The 2026-10-22 design review of the test-suite migration read
the five copies of `repo="$(fixture_repo)" || exit 143` in
`tests/test-upstream-drift.sh`, `test-quality-receipt.sh`, `test-session-stop.sh`,
`test-bootstrap-worktree.sh` and `test-publish-evidence.sh` as dead code
carrying a magic number, reasoning that the builders run in the file's shell.
All five are called inside `$(…)` or `<(…)` (`SCOPED_REPO="$(upstream_repo)"`,
`REPO1="$(feature_repo)"`, `REPO="$(repo_with_origin)"`, `MAIN="$(main_repo)"`,
`read … < <(evidence_fixture)`), so the guard is what stops the rest of the
builder from running against `""`. The finding was refuted and dropped.

## The rule

- A builder that calls `fixture_dir`/`fixture_repo` and is itself called in a
  command substitution keeps `|| exit 143` on that line; the exit code matches
  the library's so the file's trailer and the runner read one stop code.
- A builder that runs in the file's own shell (assigned without `$(…)`, e.g.
  writing its paths into globals) needs no guard — the trap fires as soon as the
  primitive returns.
- Before accepting a "dead guard" finding on a bash helper, check **how the
  helper is invoked**, not where it is defined: `grep -n 'builder' file` and look
  for `$(` or `<(` around every call.

## The consequence of ignoring it

Deleting the guard turns an abort into a silent run of the builder's remaining
commands against the current directory: `git init`, `git add -A`, `git commit`
in the repository under test. The file then fails late and misleadingly, or
passes and leaves a stray commit.

Related: [command-substitution-forks-a-subshell-so-ppid-varies-per-call](../patterns/command-substitution-forks-a-subshell-so-ppid-varies-per-call.md)
(the same `$(…)`-forks-a-subshell mechanism, seen from the process-identity side).
