---
title: Windows suite takes 20 to 38 minutes because every process spawn costs over a second
date: 2026-09-21
problem_type: performance
module: tests/run.sh, tests/lib.sh, tests/test-sync-retirement.sh, tests/test-upstream-drift.sh
tags: [tests, windows, process-spawn, python3, parallel-runner]
symptoms: "`bash tests/run.sh` takes over 20 minutes idle and 38+ minutes under load on a Windows 11 checkout (51 minutes measured here); the same suite finishes in a few minutes on Linux CI. Issue #136."
root_cause: "The suite assumes processes are free. On Windows every spawn costs 100-500 ms and a Python launcher 0.7-1.5 s; the fixture helpers in test-sync-retirement.sh spent three or four processes per fixture file (a dirname subshell, a mkdir, two cats per capture, two git config calls per repo), and tests/run.sh ran 42 independent files strictly serially. The Store python3 launcher was only 5 % of the slowest file; the upstream-drift wall-clock assertion failed because its 0.1 s deadline expires before Git spawns the helper on Windows, so it measured spawn latency alone."
resolution: "tests/run.sh prints per-file elapsed seconds, runs every file with stdin closed and takes --jobs N / TEST_JOBS=N to run files concurrently; tests/lib.sh resolves TEST_PYTHON once (real CPython ahead of the Store launcher) and every test invokes it; the sync-retirement fixture helpers use builtins and one mkdir per fixture (1275 s -> 695 s, identical 365 assertion results); the upstream-drift bound is relative to a no-op helper run plus a PID liveness check."
---

**Status**: fixed — 2026-09-21
**Regression test**: tests/test-run-sh.sh (runner contract and TEST_PYTHON resolution); tests/test-upstream-drift.sh "process tree" assertions; tests/test-sync-retirement.sh unchanged 365 assertions as the equivalence check

## Investigation

Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/136

### Measurements on this machine (Windows 11, Git Bash 5.2, 12 cores, idle)

| Operation | Wall-clock (net of ~190 ms measurement overhead) |
|---|---|
| `python3 -c pass` (Store launcher, `WindowsApps/python3`) | ~650 ms |
| `py -3 -c pass` (py launcher, resolves to the same Store build) | ~700 ms |
| `Programs/Python/Python312/python.exe -c pass` (real CPython) | ~270 ms |
| `bash -c true` | ~190 ms |
| one `$(...)` substitution | ~95 ms |

Evidence level 2 (primary measurement). The issue's numbers (2.15 s / 1.34 s)
were taken on a loaded machine with the same tooling; the ratios match.

### Confound found and removed

A clone under the Claude desktop app's scratch workspace
(`AppData/Roaming/Claude/...`) is a *packaged-app virtualized path*: git
resolves it to `AppData/Local/Packages/Claude_.../LocalCache/Roaming/...`.
The Store `python3` is its own MSIX package with its own AppData view, so it
reports `can't open file` for every script in that clone while bash sees them
fine. Any Python-driven test then fails fast, which *under*-measures the
Python-heavy files and invents failures (codex-install 8/26,
html-presentation) that are not in the Windows environment-failure table.
`AppData/Local/Temp` is visible to both, so the baseline was re-run from a
clone under `/tmp`. See [[windows-suite-failures-compare-against-a-clean-head-worktree]]
for the known environment-only failure set.

### Attribution (Level 1: timestamped xtrace of test-sync-retirement.sh, 1035 s traced)

| Command | Share | Calls | Per call |
|---|---|---|---|
| git | 26 % | 567 | 469 ms |
| mkdir | 25 % | 1160 | 220 ms |
| python3 | 20 % | 124 | 1703 ms (launcher + the script's own git subprocesses) |
| dirname | 11 % | 867 | 127 ms |
| `$(...)` fork | 8 % | 865 | 92 ms |
| cat | 4 % | 230 | 165 ms |

Per-section wall times were uniform (15–100 s): no hang, no retry, no timeout
path — the shape of the fixture helper was the whole story. The three
candidates and the disconfirming checks are in the pattern document
[[a-bash-suite-on-windows-is-process-bound-so-attribute-time-by-spawn-before-optimizing]].

### upstream-drift (Level 1)

Standalone probe with millisecond timing: a helper that exits at once took
2134 ms, the "hanging" helper 2544 ms, and the hanging helper's pid file was
never written — the 0.1 s deadline expired before Git spawned it. The old
`under 2 s` bound therefore measured python + git start-up and nothing else.

## Fix

| Change | Where | Effect on this machine |
|---|---|---|
| per-file `--- file: N s ---`, `TOTAL`/`SLOWEST` summary, stdin closed | tests/run.sh | slow files visible; the stdin-pipe hang closed at the runner |
| `--jobs N` / `TEST_JOBS=N`, whole-block output, same RESULT | tests/run.sh | see the suite row below |
| `TEST_PYTHON` resolved once; 64 call sites use it | tests/lib.sh, tests/test-*.sh | 0.4 s per call when a real CPython is installed |
| fixture helpers: `${1%/*}`, `[ -d ] \|\| mkdir`, one mkdir per builder, identity via .git/config, `$(<out)` capture, one sha256sum pass | tests/test-sync-retirement.sh | 1275 s -> 695 s; 47/365 failing and 318 passing names identical |
| deadline bound relative to the no-op helper run + pid liveness + printed `note` | tests/test-upstream-drift.sh | 1/64 -> 0/64 on Windows; on Linux the pid check is the real pin |
| `shutil.which("bash")` instead of a bare `bash` | codex/hooks/session_start.py | codex-install 24/24 under a plain CPython, where a bare `bash` reached WSL |

### Suite timings (idle Windows 11, 12 cores, Git Bash 5.2)

| Run | Wall |
|---|---|
| baseline, serial, clean HEAD 0de3f8a | 3051 s |
| after, `--jobs 4` | 1404 s |
| after, `--jobs 8` | 936 s |
| after, serial (estimate from per-file times) | ~2470 s |

Failing-file set after: the eight known environment-only files (install-sh
1/133, routine-selectors 60/189, routine-skills 2/63, skill-invocation-chain
2/42, sync-retirement 47/365, task-escalation 1/62, task-registry 44/398,
verification-skill-integration 2/82) with identical assertion names; upstream-drift
left the table (0/64). Under concurrency each file runs 1.5–3× slower than
alone (sum of per-file seconds 3045 serial vs 5610 at eight jobs), so the
machine's spawn throughput, not the critical path, is the ceiling: the
acceptance target of ten minutes is **not** met here (15.6 min at eight
jobs) and needs the same process-thinning applied to install-sh, solutions-schema,
session-start, routine-selectors and task-registry.

Two comparison traps met on the way: a LF-normalized clone made
verification-skill-integration's two license-byte failures disappear (they are
CRLF artefacts, back in a CRLF checkout), and the real CPython surfaced a
latent Windows bug in `codex/hooks/session_start.py` — a bare `bash` in
`subprocess.run` reaches WSL's bash via System32 before PATH; fixed with
`shutil.which("bash")`.

The issue's machine measured spawns 2–3× slower than this one (python3 2.15 s
vs 0.85 s, `bash -c true` 1.34 s vs 0.38 s), so its wall time scales
accordingly; the parallel runner and the fixture rewrite are the two levers
that reach it. A serial `bash tests/run.sh` on Windows remains tens of minutes:
set `TEST_JOBS` in the shell profile so every skill that runs the suite picks
it up.

## Follow-ups not taken here

- `scripts/check-upstream-drift.py` cannot kill a remote helper's process tree
  on Windows (`process.kill()` reaches git.exe only); CI is Linux, so the
  checker is unaffected there, and the test now says when the path was not
  exercised.
- The skills that run `bash tests/run.sh` (`/wrap-up-session`, `/build`,
  `/tidy`) do not pass `--jobs`; `TEST_JOBS` covers them without a skill edit.
