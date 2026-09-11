---
title: A baseline run overlapping tree edits measures a mixture, not a baseline
date: 2026-08-14
problem_type: process
module: tests/run.sh, /yolo and /auto-improve pre-flight
tags: [testing, baseline, background-jobs, yolo]
applies_when: launching the full suite as a background job to establish a green baseline, then starting work before it returns
---

## The rule

Take the baseline **before** the first edit, and wait for it. A suite launched in
the background and left running while you write files does not measure the tree you
meant — `tests/run.sh` globs `tests/test-*.sh` at the moment it reaches that loop,
so a test file created mid-run is discovered and executed.

## What happened

2026-08-14, `feat/review-context-contract`. The baseline was started in a fresh
worktree, then the session immediately began TDD work — including writing a new,
deliberately red `tests/test-review-context.sh`. The run reported
`RESULT: 1/16 test files FAILED` against a 15-file tree.

Two distinct wrong conclusions were both available from that output:

1. **"My new test is the failure."** Plausible: it was red for most of the run, and
   16 files where master has 15 is exactly the signature of a picked-up new file.
2. **"Master is broken."** Also plausible, and in fact true — but for a *different*
   file (`tests/test-codex-install.sh`, see
   `../bugs/codex-session-start-hook-emits-nothing.md`).

Only `awk`-ing the per-file markers out of the captured log distinguished them. Had
the new test still been red when the run reached it, both files would have failed
and the pre-existing breakage would have been easy to write off as self-inflicted.

## How to apply

- Establish the baseline on an unmodified tree; treat the wait as part of pre-flight,
  not as dead time to fill with edits.
- Capture per-file results, not just the exit code:
  `awk '/^=== tests/{f=$2} /assertions FAILED/{print f}'` over the run log names the
  culprit in one line. An exit code cannot.
- When a baseline is red, prove *whose* red it is before deciding anything — a
  detached worktree at the base commit (`git worktree add --detach <path> origin/master`)
  answers it in one run and costs nothing.

Related: `../bugs/codex-session-start-hook-emits-nothing.md` — the real failure this
nearly masked.

Related: proving a red file pre-existing from inside a worktree — [worktree-sessions-refuse-compound-bash-and-sub-agents-read-the-shared-checkout](../tooling/worktree-sessions-refuse-compound-bash-and-sub-agents-read-the-shared-checkout.md).
