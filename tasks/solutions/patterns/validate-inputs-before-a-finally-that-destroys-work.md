---
title: Validate every input before entering a try whose finally destroys work
date: 2026-11-19
problem_type: pattern
module: .agents/skills/build/scripts/candidates.py
tags: [cleanup, finally, worktrees, validation, candidates]
---

## Context

`candidates.py rank` removes every candidate worktree in a `finally`, so a
cancelled or failed run never leaves worktrees behind (specs/parallel-candidates.md
AC3). The first version resolved the slice's Surface from `--spec` *inside*
that `try`: a mistyped spec path raised, the `finally` ran, and N Builders'
uncommitted work was deleted for a typo.

## Rule

When a `finally` (or an exit handler) deletes state that other agents produced,
everything that can fail for a *usage* reason — paths, ids, argument formats,
the lookup of the spec or slice — runs before the `try`. Inside it, order the
steps so the one that saves the work runs first: `rank` applies the winner's
diff before it writes the ledger record, and records in a nested `finally`,
so neither a ledger failure nor an apply failure costs both.

## Check

A test that makes the call fail for a usage reason must assert the worktrees
still exist afterwards (`tests/test-candidates.sh` § refusals: "a refused rank
call keeps the candidates' work").
