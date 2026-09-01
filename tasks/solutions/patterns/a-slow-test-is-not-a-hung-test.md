---
title: A slow test is not a hung test
date: 2026-08-11
problem_type: pattern
module: test-harness
tags: [tests, timeout, diagnostics]
applies_when: Diagnosing a test suite that exceeds a tool timeout.
date_source: git-log
migrated_from: tasks/memory.md
---

## A slow test is not a hung test

**Pattern**: Time each file (`for f in tests/test-*.sh; do ... done`) before diagnosing a hang. `test-install-sh.sh` runs `install.sh` five times for real and takes ~108s on this filesystem; the whole suite needs ~4.5 min, so the 2-minute default Bash timeout truncates it and reads as a hang. Pass an explicit timeout for `tests/run.sh`.

**Evidence**: Tier 2 build — first full-suite run reported a hang that was ordinary slowness.
