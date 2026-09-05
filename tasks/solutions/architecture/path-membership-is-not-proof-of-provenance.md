---
title: Path membership is not proof of provenance
date: 2026-09-05
problem_type: architecture-decision
module: .agents/skills/sync/scripts/sync-retire.py
tags: [provenance, data-loss, git, determinism, sync]
applies_when: deleting a file because some other repository once had that path
---

## The rule

"The template once had a file at this path" and "this file is the template's"
are different claims. A tool that deletes without asking needs the second, and
only content can supply it. Compare the bytes.

## What happened

Bootstrap retirement computed
`retire = (project − template) ∩ (paths the template ever carried)` and reported
each result as `was template content, retired upstream`. The set operation is on
paths; the report line, the spec, and the acceptance criterion all claimed a fact
about the *file*. Three cases break on that gap:

- a synced file the project **edited** afterwards — deleted, edit gone
- a file the project **wrote itself** at a colliding path — `.claude/hooks/` is a
  syncable root and `pre-commit.sh` is a name both a template and a project reach
  for — deleted, never recoverable because it was never upstream
- a tracked file with **uncommitted** modifications — deleted, and
  `git checkout --` restores only the committed version, silently losing the edit

The fix compares the working-tree hash against every blob the template ever held
at that path (`git log --raw --no-abbrev` carries both pre- and post-image blobs,
so one walk yields the whole content history). A mismatch demotes the path to a
candidate for a human.

## Why hash the working tree, not the index

Hashing the index would still delete the third case: the indexed blob matches the
template's, so the arithmetic says "pristine" while the file on disk carries work
nobody can recover. The working tree is the thing being deleted, so it is the
thing to measure.

## The generalisable trap

Determinism was the goal, and determinism was achieved — but determinism
guarantees the *same* answer, not a *correct* one. A cheap checkable proxy
(path membership) was substituted for the expensive question (is this the
template's file?), and then the proxy was described in prose as though it were
the answer. Whenever a design replaces a judgement with a record, check that the
record actually records what the prose claims.

Related: [[current-state-cannot-distinguish-removed-from-never-present]],
[[a-repository-level-flag-does-not-describe-one-revision]].
