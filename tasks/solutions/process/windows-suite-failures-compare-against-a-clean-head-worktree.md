---
title: On a Windows checkout, compare a failing test file against a throwaway HEAD worktree before debugging it
date: 2026-09-11
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
| test-upstream-drift | 0–1 | timing flake in the process-deadline assertion |

None of these names a file the session touched. Without the HEAD comparison,
each is an hour of false debugging; with it, each is a one-line report.

## Two things that make the run slow to read

- `python3` resolves to the Store launcher under `WindowsApps`, which adds
  noticeable start-up cost to every call; a full suite takes over twenty minutes.
- A background run piped through `grep` shows **nothing** until it exits,
  because `grep` buffers to a file. An empty output file is not a hung run —
  check `ps -W` for the shell PID before concluding anything.

## Related

- [[baseline-must-precede-tree-edits]] — the same idea in time rather than
  space: a baseline taken while editing measures a mixture. A HEAD worktree is
  how to take one *after* editing has begun.
- [[recursive-grep-over-dot-claude-hits-stale-worktree-checkouts]] — remove the
  scratch worktree afterwards (`git worktree remove <path>`); a forgotten one
  becomes a test-polluting checkout.
