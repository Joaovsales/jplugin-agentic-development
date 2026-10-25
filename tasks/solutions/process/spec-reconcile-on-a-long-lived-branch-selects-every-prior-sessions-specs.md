---
title: Spec-reconcile on a long-lived branch selects every prior session's specs, so filter by the staged and unstaged reasons
date: 2026-10-25
problem_type: process
module: .agents/skills/wrap-up-session/references/spec-reconcile.md § Discover candidates; scripts/spec-reconcile.py discover
tags: [wrap-up-session, spec-reconciliation, long-lived-branch, candidate-scoping, reasons]
applies_when: running /wrap-up-session on a branch that is many commits ahead of the base, where the discover step returns more candidate specs than the session could plausibly have touched
---

**Status**: current as of 2026-10-25

## Situation

`spec-reconcile.py discover --base <base-branch>` captures one change set built
from committed `<base>...HEAD` **plus** staged **plus** unstaged
(`references/spec-reconcile.md` § *Discover candidates*). On a short-lived feature
branch whose only commits are this session's, that set *is* the session — which is
the case the procedure was written for.

On a long-lived branch it is not. A run on `Joaovsales/jev-routing`, 184 commits
ahead of `master` with no pull request open, returned 22 candidate specs and a
reasons list running to hundreds of paths, essentially all of it prior sessions'
work. Every candidate was technically correct and none of them belonged to the
session being wrapped up.

## The rule

Scope the outcomes to the session, using the `reasons` entries the script already
supplies. A path reason is suffixed `(M, committed)`, `(A, committed)`,
`(M, unstaged)`, `(M, staged)` and so on, so the session's own files are the ones
carrying a `staged` or `unstaged` marker:

```
[c for c in candidates if any('staged' in r or 'unstaged' in r for r in c['reasons'])]
```

Assign `updated` / `unchanged` / `deferred` to those, and leave the
committed-only candidates alone — a prior session already had its turn at them.

**A `(M, committed)` reason is not automatically stale**, though: a spec whose
implementation paths this session's change *shares* with earlier commits still
matters. Read the diff rather than the marker.

## Consequence

The filter is a scoping aid, not a substitute for judgement, because
**discovery only finds specs that carry path metadata**. The spec semantically
closest to this session's change — `specs/model-tier-ceiling-gaps.md`, which owns
the Ceiling tier and `critic`'s floor — has no `implementation_paths` frontmatter
and so was never a candidate at all, while two specs that merely name
`.agents/references/model-routing.md` were. Grep the store for the *concepts* the
session changed (here: `ceiling`, `agentOverrides`, `inherit`) and reconcile those
by hand; a spec without path metadata is invisible to discovery by construction,
and giving it metadata is the durable fix.
