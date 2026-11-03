---
title: A stale local base branch inflates every range the harness derives
date: 2026-10-27
problem_type: bug
module: .agents/git-hooks/pre-push § resolve_base; .agents/skills/wrap-up-session/SKILL.md § No-change exit; spec-reconcile.py --base
tags: [git, base-branch, stale-ref, origin, pre-push, wrap-up-session, spec-reconcile, range]
symptoms: a 10-commit branch was reported as 184 commits ahead of `master`; `spec-reconcile.py discover --base master` returned 22 candidate specs, all belonging to earlier sessions; the pre-push gate recorded 76 uncovered commits in tasks/wrap-up-debt.md; the affected-test set selected the whole 91-file suite instead of the ~49 files the real diff covers. `git log --oneline master..HEAD` printed 202 while `git log --oneline origin/master..HEAD` printed 10
root_cause: Both resolvers preferred a **local** branch ref. `.agents/git-hooks/pre-push` `resolve_base()` looped `for _b in master main develop` over `refs/heads/$_b`, and `wrap-up-session/SKILL.md` § No-change exit defined `<base-branch>` as the first local branch found, falling back to `origin/HEAD` only when none existed. The local `master` on this machine was 192 commits behind `origin/master` (an ancestor, so stale rather than divergent), and nothing fetches or checks. Every range the harness derives from `<base-branch>` — the no-change check, the changed-file list, the spec-reconcile candidate set, the pre-push coverage range and the affected-test selection — grows by however far the local branch lags. `.agents/skills/quality-gate/scripts/receipt.py` was already correct (`DEFAULT_BASE_CANDIDATES` lists `origin/main`, `origin/master`, `origin/develop` before the local names), so the three resolvers disagreed with each other
resolution: fixed — 2026-10-27. `resolve_base()` in pre-push tries `refs/remotes/origin/<base>` before `refs/heads/<base>`, and the wrap-up skill's `<base-branch>` definition matches it. The hook still performs no network I/O, so a remote-tracking ref left stale under-reports coverage rather than over-reporting debt — the safe direction for a gate that only warns — and the skill now says to `git fetch` before resolving. A regression test in `tests/test-pre-push-gate.sh` builds a repo whose local `master` sits at the base while `origin/master` already carries the pushed commit, and asserts the gate stays silent and writes no ledger row; it fails against the old resolver
---

**Status**: fixed — 2026-10-27
**Regression test**: `tests/test-pre-push-gate.sh` — `Stale local base: no debt for a commit already on origin/master` and `Stale local base: gate silent`

## Prevention

**Resolve a base against the remote-tracking ref, never a local branch.** "What is
already on the target branch" is a fact about the remote; a local branch is a cache
of it that nothing keeps fresh, and the failure is silent in the direction that
matters — the ranges just get bigger, and every extra commit is reported as
uncovered, unreconciled or affected.

Three things make this class of bug hard to see:

- **The output stays plausible.** 202 commits and 22 specs are not absurd numbers.
  Nothing errors, nothing is empty, and each individual row looks like a real
  finding. The tell is a range wider than the work: if the candidate count or the
  commit count is much larger than the session's own diff, suspect the base first.
- **The resolvers can disagree.** `receipt.py` was remote-first while `pre-push` and
  the skill were local-first, so the same session got a correct receipt fingerprint
  and an incorrect debt range from the same tree. Grep for every resolver before
  trusting one.
- **A stale base is an ancestor, not a divergence.** `git merge-base --is-ancestor
  master origin/master` answers "is this just behind?" in one command, and it is the
  first thing to run when a range looks too wide. `git fetch` before any measurement.

Related: `a-merge-commit-commits-only-the-index-so-unstaged-edits-do-not-ship.md` is
the same session's other defect — both are cases where a number the harness reported
was wrong and only a direct check of the underlying ref or artifact caught it. The
`process/` document this replaces diagnosed a "long-lived branch" and prescribed
filtering the candidate set by staging state; that treated the symptom. The branch
was never long-lived — the base was 192 commits stale.
