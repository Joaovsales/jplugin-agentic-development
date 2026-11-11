---
title: pre-push gates inherit the pushing repo's GIT_DIR and let test fixtures write to it
date: 2026-11-04
problem_type: bug
module: .agents/git-hooks/pre-push
tags: [git-hooks, pre-push, worktrees, test-isolation, GIT_DIR, incident]
symptoms: In a downstream project whose pre-push gate ran its unit tests, a push from a linked worktree failed fixture tests that pass standalone ("cannot lock ref", "branch already exists"), and afterwards origin/main pointed at a fixture commit, a junk remote branch existed, and the clone's .git/config had core.bare=true and user.name=Test.
root_cause: Git exports an absolute GIT_DIR to hooks run from a linked worktree (none from the main checkout). The hook ran `npm run <gate>` with that environment, so any gate that spawns git — a test suite building fixture repos with the inherited env — operated on the pushing repository and its origin.
resolution: Each gate runs in a subshell that unsets `git rev-parse --local-env-vars` (git's own list — GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_COMMON_DIR, ...). The hook's own git calls are unaffected; they run outside the subshell.
date_source: session
---

**Status**: fixed — 2026-11-04
**Regression test**: `tests/test-pre-push-gate.sh` § *exit-branches* — "Pushing repo's git env".

Evidence (level 1, controlled reproduction, in pix-receipt-extractor-application
#611): a sandbox clone with a linked worktree pushing to a throwaway origin, the
gate running four fixture test files. The unfixed hook reproduced the incident
(19 failed, core.bare=true, user.name=Test, junk branches); the fixed hook left
the clone untouched.

Projects whose gates run tests should also scrub these variables in their test
setup: vitest/jest/pytest started by `git rebase --exec` or a stale installed
hook inherit GIT_DIR the same way.
