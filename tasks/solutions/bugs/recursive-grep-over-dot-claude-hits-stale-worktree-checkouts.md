---
title: A recursive grep over .claude/ reads every stale worktree checkout parked under .claude/worktrees/
date: 2026-09-11
problem_type: test-failure
module: tests/test-tdd-retirement.sh
tags: [bash, grep, worktrees, tests, retired-files, windows]
symptoms: "tests/test-tdd-retirement.sh failed `Retire: no 'or at minimum' commit escape hatch anywhere` although no tracked file under .agents/ or .claude/ carried the phrase; the hits were 58 copies of the retired tdd/SKILL.md inside .claude/worktrees/<name>/ — 29 leftover worktrees from earlier sessions, plus a live session's checkout whose spec merely quoted the phrase"
root_cause: "the assertion runs `grep -rn ... .agents .claude ...` (tests/test-tdd-retirement.sh:40-41). Claude Code parks git worktrees under .claude/worktrees/, which .git/info/exclude hides from git but not from a recursive grep, so every other checkout on the machine is searched as if it were this tree"
resolution: "add `--exclude-dir=worktrees` to that grep and say why in the comment above it (tests/test-tdd-retirement.sh:39-40); remove the idle worktrees with `git worktree remove --force` after preserving any uncommitted work as a WIP commit on its own branch"
---

**Status**: fixed — 2026-09-11

## What happened

The full suite reported one failure in `tests/test-tdd-retirement.sh`. The
phrase it forbids had been retired from the tree weeks earlier. Every hit came
from `.claude/worktrees/*/…/tdd/SKILL.md`: old checkouts left by finished
sessions and workflow sub-agents, all still holding the file at the revision
they were created from.

## Why the grep saw them

`.claude/worktrees/` is listed in `.git/info/exclude`, so `git status` and
`git ls-files` never show it. `grep -r` has no idea what git excludes. Any
assertion of the form "this text appears nowhere under `.claude`" is therefore
really "nowhere under `.claude`, in this tree or any other checkout on this
machine" — and the other checkouts are frozen at older commits by design.

The same trap applies to any recursive scan rooted at `.claude/` or at the
repository root: retired-needle sweeps, parity walks, license checks. Prefer
`git ls-files` or `git grep` when the question is about *this* tree; when a
plain `grep -r` is the right tool, exclude `worktrees`.

## Cleanup done alongside

31 of 32 worktrees were idle since mid-August and were removed. The one live
worktree (locked by a running session, `.git/worktrees/<name>/locked` names its
PID) was kept — a lock reason of `claude session … (pid N)` with a live PID is
another session's working copy, not debris. One idle worktree held real
uncommitted spec edits; they were committed as a WIP commit on its own branch
before removal so nothing was lost.

## Related

- [[grep-end-of-options-before-exclude-dir-drops-the-exclusions]] — the other
  way an `--exclude-dir` fails to exclude: `--` placed before it.
- [[check-git-worktree-list-before-declaring-a-prerequisite-miss]] —
  `git worktree list` is also the fastest way to see what is parked here.
