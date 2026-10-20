---
title: kill -0 counts a zombie as alive under a slow-reaping PID 1
date: 2026-10-19
problem_type: test-failure
module: tests/test-upstream-drift.sh § process tree; scripts/check-upstream-drift.py kill_process_tree
tags: [flaky-test, zombie, process-group, container, pid-1]
symptoms: "`process tree: the helper is dead once the checker returns` failed in roughly half of the suite runs in a cloud container, passed alone, and passed on the developer machine"
root_cause: "The checker kills the hanging helper's process group with SIGKILL and the helper dies at once, but its parent (git) is dead too, so the orphan is reparented to PID 1. This container's PID 1 (`process_api --firecracker-init`) reaps orphans slowly, and a zombie still answers `kill -0` for well over the test's one-second wait."
resolution: "`helper_running` in tests/test-upstream-drift.sh reads the process state as well: `kill -0` must succeed and `ps -o stat=` must not start with `Z`. A zombie is dead; only a running state counts. Fixed 2026-10-19 on the diagram-skill branch (PR #290)."
---

## What was observed

`tests/test-upstream-drift.sh` starts a `git-remote-hanging` helper that writes
its pid and sleeps thirty seconds, runs the checker with a 0.1 s deadline, and
then asserts the helper is gone within one second. In the build session's cloud
container the assertion failed in three of six suite runs and passed in every
single-file run; the baseline before any edit already carried the failure.

## Why

A probe reproduced it outside the test: a session-leader child spawning a
grandchild, `killpg(SIGKILL)` after a short timeout, then `/proc/<pid>/stat`
read every 50 ms — the grandchild sat in state `Z` for the whole 450 ms window,
as root and as `nobody`. `kill -0` on a zombie returns 0 (the pid still exists
in the process table), so the test's liveness loop never saw it die. PID 1 here
is `process_api --firecracker-init`, which does not reap orphans promptly; a
desktop init does, which is why the test is green elsewhere.

## The fix

`tests/test-upstream-drift.sh:166` — `helper_running` returns false when
`kill -0` fails *or* `ps -o stat= -p <pid>` starts with `Z`. When `ps` prints
nothing (no `ps`, or a platform without the column) the state read is empty,
which is not `Z`, so the check degrades to the old `kill -0` behaviour rather
than passing vacuously. The test's meaning is unchanged: a helper that outlives
the kill is still running and still fails.

## Prevention rule

A liveness assertion after a kill must distinguish *exited but unreaped* from
*running*. In a container, assume PID 1 may reap late: read the process state,
or wait on the pid from the process that owns it instead of polling `kill -0`.
