---
title: cached-suite keys on the verbatim command, so parallelism comes from the environment
date: 2026-10-16
problem_type: tooling
module: .agents/skills/build/scripts/cached-suite.sh; tests/run.sh § --jobs / TEST_JOBS
tags: [cached-suite, tests, baseline, test-jobs, windows, gitignore]
applies_when: starting the /build baseline or the /wrap-up-session pre-push suite on this Windows machine, or writing its log somewhere under tasks/
---

## cached-suite keys on the verbatim command, so parallelism comes from the environment

**Claim**: `cached-suite.sh` reuses a green run only when the working-tree hash
*and the command* match (`.agents/skills/build/scripts/cached-suite.sh:10-20`),
and `AGENTS.md` asks every skill to spell the `Full suite:` line verbatim. The
runner itself defaults to one file at a time (`tests/run.sh:37`,
`jobs="${TEST_JOBS:-1}"`). On 2026-10-16 the serial baseline took 4680 s wall for
73 files while two slice agents and a WSL copy shared the CPU; the same
affected set of 40 files ran in 50 s under WSL with `TEST_JOBS=6`.

**Rule**:
- Export `TEST_JOBS=6` (12 cores here) before `cached-suite.sh -- bash tests/run.sh`
  instead of adding `--jobs` to the command, so the cache key `/wrap-up-session`
  looks up is unchanged and the run is still reusable.
- Write the suite log to a path the ignore rules cover (`tasks/<name>-<sha>.log`
  matches `tasks/*.log` in `.gitignore`). A log under `tasks/.logs/` is untracked,
  grows while the suite runs, and moves the tree hash the cache recorded, so the
  green run can never be reused — this session restarted its baseline for that
  reason.
- On Windows the baseline is red by design-stack and gh-mock files regardless;
  diff the failing *file names* (`=== tests/... ===` blocks) against the baseline
  log, never the counts, and prove the design-stack files under WSL.

**Consequence of ignoring it**: a 78-minute baseline that the pre-push run
cannot reuse, so the session pays it twice.

Related: [baseline-must-precede-tree-edits](../process/baseline-must-precede-tree-edits.md),
[windows-suite-takes-20-to-38-minutes-because-every-process-spawn-costs-over-a-second](../performance/windows-suite-takes-20-to-38-minutes-because-every-process-spawn-costs-over-a-second.md),
[a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux](../process/a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md).
