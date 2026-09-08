---
title: A skill may not name a path /sync does not deliver
date: 2026-09-07
problem_type: architecture-decision
module: .agents/skills/task-registry/SKILL.md, tests/test-syncable-paths.sh, scripts/migrate-task-registry.py
tags: [sync, syncable-roots, distribution, template-repo, dangling-reference]
applies_when: a skill document points at repository tooling that lives outside .agents/skills, .claude, or another syncable root
---

## The rule

A skill document may only name paths **inside a syncable root**. `/sync` copies
`.agents/skills/`, `.claude/`, and the other roots in its list — it does **not**
copy `scripts/`. A `SKILL.md` naming `scripts/foo.py` resolves fine in the
template repository and dangles in every project that consumes it.

When a skill genuinely needs to point at repository tooling, write the path
against a template clone:

```
python3 <template-clone>/scripts/migrate-task-registry.py --repo .
```

The `<template-clone>` prefix is load-bearing twice over: it tells the downstream
reader the file is not in their project, and it keeps the token out of
`tests/test-syncable-paths.sh`'s scanner, whose regex only matches a bare
`scripts/…` at a word boundary.

## What happened

Cut 1 of `specs/workflow-routing.md` retired `task-registry migrate` and replaced
it with a one-shot at `scripts/migrate-task-registry.py`, following the
`scripts/migrate-learning-store.py` precedent. Three skill documents were updated
to name the new path, and `tests/test-syncable-paths.sh` failed all three:

```
FAIL Distribution: .agents/skills/task-registry/SKILL.md names
     scripts/migrate-task-registry.py -> outside every syncable path
```

The guard was right and the instinct was wrong. A downstream project that ran
`/sync` would have received a `SKILL.md` instructing it to run a file `/sync`
never sends — the same shape as issue #82, where a `Task tracking instructions:`
pointer named a file the template could not deliver.

`.agents/skills/sync/SKILL.md` had already solved this for the learning-store
migration and was the model:

```
> `python3 <template-clone>/scripts/migrate-learning-store.py --repo .`
```

## Why the script still belongs outside the skill

Moving it *into* `.agents/skills/task-registry/scripts/` would satisfy the guard
and cost more than it saves: `/sync` overwrites skills wholesale, so a one-shot
every project runs once would be carried in the skill forever, and it would count
against the size reduction the cut exists to deliver. The prefix is the cheaper
correction — the file's home is right, only the reference was wrong.

## How to apply

- Before adding a path to any skill document, ask which root it sits under. If
  none, write it as `<template-clone>/<path>` and say in prose that it lives in
  the template repository.
- The same applies to **runtime messages** emitted by skill code, not just to
  Markdown. `reconcile.py`'s `missing-id` remedy is read inside a downstream
  project, so it names "the template repo's `scripts/…`" rather than a bare path
  that would resolve to nothing there.
- `tests/test-syncable-paths.sh` only scans `*.md` under the skill trees. A
  dangling path in a `.py` string is not caught mechanically — that one is on the
  author.

Related: [[to-extend-a-sync-managed-skill-s-output-without-editing-it-w]],
[[task-tracking-pointer-to-a-missing-file-was-indistinguishable-from-no-pointer]],
[[layered-config-claude-md-template-claude-project-md-project]]
