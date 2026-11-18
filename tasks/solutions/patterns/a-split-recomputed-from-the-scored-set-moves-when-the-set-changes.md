---
title: A split recomputed from the scored set moves when the set changes
date: 2026-11-18
problem_type: pattern
module: .agents/skills/eval/scripts/variant-holdout.py
tags: [eval, holdout, determinism, quality-gate]
applies_when: a split, sample or partition is recomputed from content so it resists tampering, and the content set can change between the split and the scoring
---

## Context

`variant-holdout.py verdict` recomputes the tuning/holdout split from the
prompts in `scores.jsonl` (SHA-256 order, first `n // 2` held out), so the
split cannot be edited after the scores are seen (#443).

## Learning

The rule is deterministic over the *set*, not over each prompt. The `n // 2`
boundary moves when the set changes: six prompts split, two prompts with high
hashes added after tuning, and the old rank-3 tuning prompt lands in the
holdout — a tuned-on prompt scored as unseen. Dropping prompts never leaks,
adding them can. Probe: `split(base)` vs `split(base + extra)`, intersect the
first's tuning with the second's holdout.

## How to apply

When a "fixed by the content" split is meant to resist tampering, check it
under set growth, not only reordering. Either fix membership per item (hash
threshold, refuse an empty side) or bind the verdict to the split-time set.
`/eval` § Mode B step 5 now tells the author to score exactly the prompts
`split` was given; enforcement is left open.
