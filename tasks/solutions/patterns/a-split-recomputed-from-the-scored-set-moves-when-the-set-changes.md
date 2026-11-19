---
title: A split recomputed from the scored set moves when the set changes
date: 2026-11-18
problem_type: pattern
module: .agents/skills/eval/scripts/variant-holdout.py
tags: [eval, holdout, determinism, quality-gate]
applies_when: a split, sample or partition is recomputed from content so it resists tampering, and the content set can change between the split and the scoring
---

## Context

The first version of `variant-holdout.py verdict` (#443) recomputed the
tuning/holdout split from the prompts in `scores.jsonl` (SHA-256 order, first
`n // 2` held out). That stopped an author from relabelling a prompt, but not
from changing the split after the scores were seen: changing the *set* of
scored prompts changes the split.

## Learning

The rule is deterministic over the *set*, not over each prompt, and the
`n // 2` boundary moves when the set changes in either direction. The PR #449
review reproduced a promote from each side of a tuning-only win (candidate 1.0
on tuning prompts, 0.0 on holdout, baselines 0.2):

- **Growth** — four high-hash prompts added after tuning moved the original
  tuning prompts into the recomputed holdout: candidate holdout 0.5, promote.
- **Deletion** — eight prompts split, then the four original holdout prompts
  dropped: the four tuning prompts re-split among themselves, so two tuned-on
  prompts became the holdout: candidate holdout 1.0, promote.

A warning in the skill text stopped neither. Probe either direction by
intersecting `split(original)["tuning"]` with `split(changed)["holdout"]`.

## How to apply

When a "fixed by the content" split has to resist tampering, test it under set
growth *and* shrinkage, not only reordering. Pin the split-time set and
require the scored set to equal it: `variant-holdout.py split --manifest`
writes the membership before tuning, and `verdict <manifest> <scores>`
re-applies the rule to validate the manifest, then refuses any added or
missing prompt before computing a mean.
