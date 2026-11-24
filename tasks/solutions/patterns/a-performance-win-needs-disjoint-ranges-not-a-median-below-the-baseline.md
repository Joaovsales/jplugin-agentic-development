---
title: A performance win needs disjoint ranges, not a median below the baseline
date: 2026-11-24
problem_type: pattern
module: .agents/skills/perf/scripts/measure.py (compare), /perf Debug mode
tags: [performance, measurement, noise, benchmarking]
applies_when: judging whether a change made a measured path faster or slower from two batches of runs of the same command
---

## The rule

Call a change `improved` only when every after run is faster than every
baseline run (after max < baseline min); `regressed` is the mirror; anything
else is `within-noise`. For two batches of an unchanged command, disjoint
ranges happen by chance once in C(2N, N): 1 in 252 at N = 5, 1 in 184756 at
N = 10.

## Why the obvious rule fails

The first draft of `measure.py compare` called a change improved when the after
*median* was below the baseline *minimum*. In the #484 end-to-end run, the same
unchanged command measured twice back to back (N = 10) read `improved`
(baseline min 154.9 ms, after median 152.4 ms), and a comment-only edit read
`regressed`. The two batches ran a few seconds apart, and the machine's load
drifted between them. That drift moves a whole batch, so a median compared
against the other batch's range crosses it easily. Every run in the batch
crossing it is far less likely.

## How to apply

- Keep N ≥ 5 per batch, use the same command and the same N on both sides
  (`measure.py compare` refuses otherwise).
- A non-`within-noise` verdict on a change that cannot move the number means
  the machine drifted: measure both again, back to back.
- A modest real improvement can read `within-noise` under this rule. Raise N
  or quiet the machine; do not loosen the rule.

See `specs/perf-audit-and-debug.md` Decision 5 and `tasks/e2e-log.md`
(#484 walkthrough).
