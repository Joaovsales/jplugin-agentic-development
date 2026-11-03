---
title: A second path inside a skill loses to the default path unless the routing comes first and the script's output names it
date: 2026-10-21
problem_type: pattern
module: .agents/skills/build/SKILL.md Phase 1 — any skill with a mode that switches to a different loop
tags: [skill-authoring, routing, build, eval, design-mode]
applies_when: adding a mode, variant or special-case loop to a skill whose default path is long and well rehearsed
---

## What happened

The design-mode loop in `/build` (since reverted, spec `specs/aposd-first-build.md`
D23) was described in one paragraph among the Phase 1 dispatch rules. `slice.py
ready` printed `mode=design` in every run, yet in the first eval round the
orchestrator ran the design loop correctly in only one of four runs: two
dispatched a normal implementer and were caught later by the freeze check, one
never called `slice.py` at all. The eval report is `tasks/eval-aposd-first-build.md`.

The fix that worked (4 of 4 in round 2) had two parts: the routing rule became
the first sentence of Phase 1 ("Route every slice before its first dispatch",
now `.agents/skills/build/SKILL.md:168`), and the script's own `ready` output
named the loop file on a design slice, so the cue arrived at the moment of
dispatch rather than in prose read earlier.

## The rule

- Put the branch point at the top of the section the agent acts from, before the
  default steps it would otherwise follow.
- Make the tool output that triggers the branch say where to go, not just print a
  label the agent must map back to prose.
- Measure routing separately from outcome: a correct final result can hide a
  wasted implementation that a later gate threw away.

## Consequence of ignoring it

Each additional path costs upkeep in a skill held to a line budget, and a path
the agent does not reliably take gives the cost without the benefit. Here the
routing fix worked but the loop still cost 3.09× for no measured gain, and it was
reverted — see [pre-registered keep-or-revert rule](../process/a-pre-registered-keep-or-revert-rule-settles-a-costly-feature.md).
