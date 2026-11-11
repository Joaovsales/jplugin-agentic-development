---
title: A routine clone can carry a stale local master that skews every merge-base
date: 2026-10-23
problem_type: tooling
module: .agents/skills/quality-gate/scripts/receipt.py, .agents/skills/wrap-up-session/scripts/spec-reconcile.py
tags: [routines, cloud-clone, merge-base, quality-receipt, git]
applies_when: a routine or cloud session computes a merge-base (receipt fingerprint, spec-reconcile discover, affected tests) and the scope lists files this branch never touched
---

## The rule

Before the first `receipt.py fingerprint`, confirm the local base branch and
`origin/<base>` name the commit `HEAD` was cut from:
`git rev-parse --short master origin/master HEAD~<n>`. When they disagree, run
`git fetch origin master` and, when local `master` is an ancestor of
`origin/master`, `git branch -f master origin/master` (never on the checked-out
branch). Then recompute the fingerprint.

## What happened

The 2026-10-23 `simplify` run (#357) started in a fresh clone whose checkout was
`e7c14eb`, but `refs/heads/master` and `refs/remotes/origin/master` still pointed
at `2da4eab`. The first `receipt.py fingerprint` used `2da4eab` as the
merge-base, so the gate's scope listed 35 files from two already-merged PRs, and
`spec-reconcile.py discover --base master` proposed 29 specs. The one-heading
change touched 2 files. Fetching and fast-forwarding both refs brought the
scope back to the 2 files and 2 spec candidates.
