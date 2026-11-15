---
title: A registry upsert never removes a label, so re-kinding an issue needs a manual label removal
date: 2026-11-12
problem_type: tooling
module: .agents/skills/task-registry/scripts/registry/providers/base.py, .agents/skills/task-registry/scripts/registry/config.py
tags: [task-registry, github-labels, routines, kind-precedence]
applies_when: changing a published issue's kind through `task-registry.py upsert --kind`, especially away from `decision`, so a routine can select it
---

## The rule

`upsert --kind task` on an issue labelled `design-decision` rewrites the body
but leaves the label in place. Until the label is removed by hand
(`gh issue edit <n> --remove-label design-decision`), the issue still reads as a
decision and no task routine selects it.

## Why

- `preserve_labels` is a union that "never drops an existing label"
  (`.agents/skills/task-registry/scripts/registry/providers/base.py:267`), and
  the GitHub provider computes the desired label set through it
  (`.agents/skills/task-registry/scripts/registry/providers/github.py:466`).
  This is deliberate: the project owns the label vocabulary.
- Selection reads labels by precedence, and `design-decision` ranks above
  `simplify` (`DEFAULT_KIND_PRECEDENCE`,
  `.agents/skills/task-registry/scripts/registry/config.py:106`). One leftover
  label therefore outranks the kind you just wrote.

## What happened

This session re-kinded #372 and #387 from decision to task, so the `simplify`
routine could ship them under the cross-area deduplication rule (#390). The
upsert reported `updated`, but both issues kept `design-decision` until it was
removed with `gh`.

## Consequence of ignoring it

The issue looks updated, since its body says `kind: task`, but the routine
never picks it up. That is the same silent starvation the re-kinding was meant
to fix.
