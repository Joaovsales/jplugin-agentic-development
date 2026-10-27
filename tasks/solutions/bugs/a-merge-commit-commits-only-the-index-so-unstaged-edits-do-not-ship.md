---
title: A merge commit commits only the index, so edits made to resolve it silently do not ship
date: 2026-10-25
problem_type: bug
module: git workflow — any merge commit resolved during /wrap-up-session § Conflict repair
tags: [git, merge, index, staging, wrap-up-session, conflict-repair, false-record]
symptoms: the merge commit `a0bd6ad` announced the removal of `fallbackModels` from `PI_SETUP.md` and `.agents/skills/build/SKILL.md`, and `git show --stat a0bd6ad` listed only four files — none of them those two. `git status` afterwards showed both files still modified. The quality receipt minted just before the commit reported `valid`, because it hashes the working tree and the working tree did have the edits
root_cause: `git commit` during a merge records the index, not the working tree, so an unstaged edit is simply not part of the commit. The conflict here was in `tasks/todo.md` alone, and only that path was `git add`-ed to mark it resolved; the two other files were edited in the same turn, before the commit, but never staged. Ordinary commits in the same session used `git add -A` and were unaffected — a merge cannot use it, because staging every path would commit files git never conflicted, and the mistake is exactly that the one commit which cannot use the safe form is the one that needs the check
resolution: fixed — 2026-10-25. `e37efca` adds both files unchanged from what receipt 2d8dc9d5 reviewed, so the receipt still validates: its diff was taken against the merge base and already included the unstaged edits. The commit message states the defect rather than hiding it
---

**Status**: fixed — 2026-10-25
**Regression test**: none — this is a git-usage defect in a session procedure, not a property of the tree. `git status --short` after any commit is the check that catches it, and `git show --stat <merge-sha>` confirms what a merge actually carried

## Prevention

After a merge commit, run `git status --short`. Anything still listed is content the
commit's message may already claim. `git show --stat <sha>` is the second half: it
reads the commit's real contents, so a message describing work the commit does not
contain is visible in one command.

The wider rule: **a commit message is a claim about the index, and the index is not
the working tree.** Every "and then I fixed X" paragraph written before `git add -A`
is a hypothesis until `git status` is empty.

Related: `a-stale-local-base-branch-inflates-every-range-the-harness-derives.md`
is the same session's other bookkeeping defect — both are cases where the recorded
account and the artifact diverged, and only a direct read of the artifact caught it.
