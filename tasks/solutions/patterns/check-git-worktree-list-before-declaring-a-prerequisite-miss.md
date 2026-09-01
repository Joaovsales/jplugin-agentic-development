---
title: Check `git worktree list` before declaring a prerequisite missing
date: 2026-08-11
problem_type: pattern
module: git-worktrees
tags: [git, worktree, prerequisite-discovery]
applies_when: Multi-tier specs where an earlier tier may already be built.
date_source: git-log
migrated_from: tasks/memory.md
---

## Check `git worktree list` before declaring a prerequisite missing

**Pattern**: A tier's work can be complete on an unmerged branch inside a worktree, so the files are absent from the branch you are standing on. `ls tests/` on `master` said Tier 1 was unbuilt; `git worktree list` + `git branch` showed it finished on `feat/compound-engineering-tier-1`. Check both before concluding anything is missing, and branch the next tier from the real base so the work stacks instead of duplicating.

**Evidence**: Tier 2 build opened by wrongly reporting Tier 1 as not landed.
