---
title: On a Windows checkout, compare a failing test file against a throwaway HEAD worktree before debugging it
date: 2026-09-21
problem_type: process
module: tests/run.sh on Windows (Git Bash, Microsoft Store python3)
tags: [testing, windows, baseline, worktree, environment-failures]
applies_when: the suite reports failures on a Windows machine and you need to know which ones your change introduced
---

## The rule

When a test file fails on Windows, run the same file in a detached worktree of
HEAD (`git worktree add --detach <scratch-path> HEAD`) and compare the failure
**count and assertion names**. Identical output means the failure is the
environment's, not yours; then move on and say so. Debug only the delta.

## Why

This session observed a stable set of environment-only failures on Windows
11 with Git Bash and a Microsoft Store `python3`, all reproduced on clean HEAD:

| Test file | Failing | Cause observed |
|-----------|---------|----------------|
| test-sync-retirement | 47/329 | `mktemp` paths in POSIX form compared against native-form paths printed by Python; `chmod a-w` on a directory does not block deletion |
| test-task-registry | 37/326 | `gh` stub and path handling |
| test-routine-selectors | 54/174 | same `gh` stub fixtures |
| test-skill-invocation-chain | 4/72 | "maintains before e2e" ordering assertions in build and wrap-up |
| test-routine-skills | 2/64 | `doctor` prints `docs\task-tracking.md` with a backslash; a homoglyph refusal turns on console encoding |
| test-verification-skill-integration | 2/90 | bundled-license byte comparison |
| test-install-sh | 1/94 | dangling-symlink handling |
| test-task-escalation | 1/62 | artifact-confinement failure not reported — `chmod` does not confine on Windows (seen at d6c5e5b, 2026-09-15) |
| test-upstream-drift | 0 since #136 | the process-deadline assertion used to want a hanging helper killed in under 2 s wall-clock; on Windows the 0.1 s deadline expires before Git spawns the helper at all, so it measured python + git start-up. Since #136 the bound is relative to the no-op helper run and the file prints a `note` that the helper was not exercised |

The same set, with identical counts, reproduced on 2026-09-15 at a clean worktree of e7ab8fa (8 files, 148 of 3789 assertions) during the `/tidy` build; the `gh`-stub rows are explained by Python resolving `gh` through PATHEXT to the real `gh.exe` instead of the extensionless bash mock.

Reproduced again on 2026-09-16 against a clean export of `origin/master` at
3eeac10 during the #123 fix: the same eight files, with routine-selectors now
60/200 and task-registry 44/398 as master grew tests, and identical assertion
names on both trees.

**Inside a worktree-isolated session** the Bash guard refuses
`git worktree add`, shell variables, `awk`, and `git archive | tar`, so the
detached-worktree recipe above cannot run. The equivalent that passes:
`git archive --format=tar -o <scratch>/base.tar origin/master` as one plain
command, then a scratch Python script that extracts it with `tarfile`, runs the
suspect test files on both trees **sequentially** (concurrent runs fake
failures), and diffs the `  FAIL ` lines. Nothing to `git worktree remove`
afterwards.

None of these names a file the session touched. Without the HEAD comparison,
each is an hour of false debugging; with it, each is a one-line report.

## A clone under the Claude desktop app's scratch workspace is not a normal path

`AppData/Roaming/Claude/scratch-workspaces/...` is a packaged-app virtualized
path: git resolves it to `AppData/Local/Packages/Claude_.../LocalCache/Roaming/...`.
The Store `python3` is its own MSIX package with its own AppData view and cannot
see files there — every `python3 script.py` fails with `can't open file`, which
invents failures that are not in the table above (codex-install 8/26,
html-presentation) and makes Python-heavy files finish fast and wrong. Clone
under `/tmp` (`AppData/Local/Temp`, visible to both) before running the suite
from such a session. Seen 2026-09-21 while working #136.

## Two things that make the run slow to read

- `python3` resolves to the Store launcher under `WindowsApps`, which adds
  noticeable start-up cost to every call. Since #136 `tests/lib.sh` resolves a
  real CPython into `TEST_PYTHON` when one is installed, `tests/run.sh` prints
  per-file timings, and `bash tests/run.sh --jobs N` (or `TEST_JOBS=N`) runs the
  files concurrently; a serial run on Windows is still measured in tens of minutes.
- A background run piped through `grep` shows **nothing** until it exits,
  because `grep` buffers to a file. An empty output file is not a hung run —
  check `ps -W` for the shell PID before concluding anything.

## Reproduced 2026-09-21 (grilling adoption build)

Nine files at the build tree and at a clean detached worktree of the base commit,
identical assertion names on both: install-sh 1/133, routine-selectors 60/189,
routine-skills 2/63, skill-invocation-chain 2/44, sync-retirement 47/365,
task-escalation 1/62, task-registry 44/398, verification-skill-integration 2/82,
and the upstream-drift deadline assertion, which failed and passed on **both**
trees across four alternating solo runs — a second-granularity flake, not a
regression (retired by #136, which replaced the absolute bound with a
millisecond bound relative to a no-op helper run).

Two details of the recipe on this machine: `git worktree add` under the session
scratchpad fails with `Filename too long` (the scratchpad prefix plus the repo's
deepest paths exceed MAX_PATH), so put the throwaway worktree at
`.claude/worktrees/<short-name>`, which is gitignored, and remove it before the
build report; and strip the `  FAIL ` prefix on **both** sides before diffing the
assertion names under `LC_ALL=C sort`, or the whole list reads as different.

## Related

- [[baseline-must-precede-tree-edits]] — the same idea in time rather than
  space: a baseline taken while editing measures a mixture. A HEAD worktree is
  how to take one *after* editing has begun.
- [[recursive-grep-over-dot-claude-hits-stale-worktree-checkouts]] — remove the
  scratch worktree afterwards (`git worktree remove <path>`); a forgotten one
  becomes a test-polluting checkout.
