---
title: A cached-suite refusal is its lock line, not any cached-suite prefix
date: 2026-11-18
problem_type: tooling
module: .agents/skills/build/scripts/cached-suite.sh; .agents/skills/build/scripts/slice_outcome.py
tags: [cached-suite, refusal, exit-status, three-outcomes]
applies_when: a script or skill must tell "the suite was refused, nothing ran" from "the suite ran and exited non-zero" when calling cached-suite.sh
---

## A cached-suite refusal is its lock line, not any cached-suite prefix

**Claim**: `cached-suite.sh` exits 3 with
`cached-suite: a suite is already running (pid <n>, since <time>)` when another
suite holds the lock (`.agents/skills/build/scripts/cached-suite.sh:103-104`),
but it also prints other `cached-suite:` notes on runs that *did* happen, for
example `cached-suite: not a git repository, running uncached`
(`cached-suite.sh:40`). The wrapped command's own exit status passes through, so
a real test run that exits 3 after such a note is a failure, not a refusal.

**Rule**: match the lock-refusal text, not the bare `cached-suite:` prefix.
`slice_outcome.py` does this with
`REFUSAL_PREFIX = "cached-suite: a suite is already running"`, so only a held
lock reads as `verification_result=Unknown`; anything else that exits 3 is
`False` (`tests/test-slice-outcome.sh` § *verification comes only from a run*,
the `uncached.sh` case). The #441 quality gate caught the looser match.

**Operationally**: the lock is shared across every worktree of the repository.
An Orca worker that meets exit 3 with this line waits and retries; it never
counts the refusal as a test result or a fix attempt.
