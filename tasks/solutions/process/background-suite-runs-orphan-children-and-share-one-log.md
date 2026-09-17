---
title: Give every background suite run a unique log path and never stop-and-relaunch it
date: 2026-09-17
problem_type: process
module: tests/run.sh, routine sweeps that run the suite in the background
tags: [tests, background-tasks, routines, windows, evidence]
applies_when: A routine or session launches `bash tests/run.sh` as a background task and may need to restart it
---

Stopping a background task stops the **wrapper shell**, not the `tests/run.sh`
child it spawned. The child keeps running, and it keeps the log file open.

## What this looked like

The 2026-09-17 `tidy` routine launched the suite, stopped it to add a missing
`</dev/null`, and relaunched it to the same log path. Both runs were then live.
Because each was started with `>`, the log's line count *fell* — 71019 on one
poll, 325 on the next — as the two truncated and appended over each other. The
file was unreadable, so the suite's result could not be established at all, and
the check had to be re-run from scratch.

`ps -ef` showed two `bash tests/run.sh` processes, started 13 minutes apart, both
parented to shells that had already been stopped
(`tasks/sweeps/2026-09-17-tidy.md` § *Coverage gaps* records the timings).

## The two rules

1. **Unique log path per run.** `suite-<stamp>-<attempt>.log`, never a fixed
   name. Two writers on one path destroy the evidence rather than duplicating
   it — a shared append would merely interleave, but `>` truncation makes the
   file shrink, which is indistinguishable from nothing having happened.
2. **Do not stop and relaunch.** Let the run finish, or accept that its child
   survives and wait for it to drain. Killing the process tree is not always
   available: under Claude Code's auto mode, `Stop-Process` on a test run is
   refused as interference with a workload, so draining was the only option
   (≈20 minutes here).

Get the invocation right the first time instead. On this repository that means
`bash tests/run.sh </dev/null` — see
[../bugs/test-suite-hangs-when-stdin-is-an-open-pipe.md](../bugs/test-suite-hangs-when-stdin-is-an-open-pipe.md),
which is the reason the relaunch was wanted in the first place.

## Why it matters beyond one wasted run

A routine's suite result gates its behaviour. `/tidy` Law 3 withholds every Tier 0
repair on a red suite, so a suite whose result cannot be read is not a neutral
inconvenience — it is an unreadable gate, and the honest outcome is
`inconclusive`, never `clean`.

Concurrency makes it worse rather than better: a second Claude session was
independently running `tests/test-sync-retirement.sh` during the same window, and
one file (`tests/test-upstream-drift.sh`) failed in-suite under that load while
passing 64/64 solo. Any failure measured on a loaded host must be re-run solo
before it is called a regression — see
[windows-suite-failures-compare-against-a-clean-head-worktree.md](windows-suite-failures-compare-against-a-clean-head-worktree.md).
