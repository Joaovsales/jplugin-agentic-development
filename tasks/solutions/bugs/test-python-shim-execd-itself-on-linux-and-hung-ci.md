---
title: A sandbox python3 shim that exec'd $TEST_PYTHON by name found itself on PATH and hung CI until the 15-minute cap
date: 2026-09-23
problem_type: bug
module: tests/test-install-sh.sh § run_install; tests/lib.sh § TEST_PYTHON
tags: [tests, ci, linux, shim, exec-loop, TEST_PYTHON, path]
symptoms: PR #177's first CI run was "cancelled" after 15 minutes with no failing assertion; the log stopped after the stale-copies "answered N" case of test-install-sh.sh and went silent for 15 minutes; Windows ran the same file green in ~15 minutes
root_cause: run_install wrote `exec "$TEST_PYTHON" "$@"` into the sandbox's bin/python3. On Linux tests/lib.sh resolves TEST_PYTHON to the bare name `python3`, and the sandbox PATH puts bin/ first, so the shim exec'd itself forever (no fork, so no process-count growth — a silent CPU spin). On Windows TEST_PYTHON is an absolute python.exe path, so the shim never saw itself
resolution: Fixed 2026-09-23 (89acf9c) — the shim execs `$(command -v "$TEST_PYTHON")`. Full Linux suite green in 69 s afterwards
---

**Status**: fixed
**Regression test**: the whole of `tests/test-install-sh.sh` Case 9 — it cannot pass on Linux with the recursive shim; the repro was WSL Ubuntu on a fresh clone

## What to check next time a CI job is "cancelled"

1. Read the workflow file first: `timeout-minutes` is a cancel, not a failure. GitHub shows it as "Cancelled after Nm" with no red assertion.
2. Find the last line the job printed and the file header above it — the hang is in the *next* case.
3. Reproduce under WSL from a fresh clone (`/var/tmp`, not `/tmp`; copy Windows-edited test files through `sed 's/\r$//'` because the working tree is CRLF).
4. When a shim wraps an interpreter, write the resolved path, never the name: `"$(command -v "$TEST_PYTHON")"`. Any name that the sandbox PATH can re-resolve is a loop waiting for the one platform where the name is bare.

Related: [[loaded-windows-runs-fake-refusal-failures]] — a second Linux-only finding rode along: `tests/test-sync-retirement.sh`'s "seven real syncable roots" pin was already wrong on this branch (nine roots) but invisible on Windows because that file's encoding failures put it in the baseline set. A baseline built on the branch itself hides the branch's own regressions; the first Linux run is the first honest look.
