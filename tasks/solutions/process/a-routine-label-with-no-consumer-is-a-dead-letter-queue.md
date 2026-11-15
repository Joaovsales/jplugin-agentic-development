---
title: A label a routine files under, with no routine that consumes it, is a dead-letter queue
date: 2026-11-12
problem_type: process
module: .agents/skills/make-it-simpler, routines
tags: [routines, simplify, design-decision, observability]
applies_when: a scheduled routine ends in a silent exit most days, or its output piles up as open issues instead of pull requests
---

## The rule

For every label an unattended routine can file under, name the routine (or the
person) that consumes it. A label with no consumer is a dead-letter queue: each
find is filed once, never acted on, and the routine's next run sees "already
filed" and exits silently.

## What happened (this session's observation)

The daily `simplify` routine ran every day but mostly exited silently.

- Its main signal, `duplicate-rule`, almost always spans the rule's home plus
  copies in other skills. That breaks the unattended one-area cap, so each
  confirmed find was filed `design-decision`.
- No scheduled routine consumes `design-decision`, and the `plan` lane is not
  scheduled.
- Five finds piled up (#358, #368, #372, #375, #387) while the routine looked
  healthy.

#390 fixed the cause, not the queue:

- A one-rule deduplication into a one-line § citation now counts as one area,
  under `.agents/skills/make-it-simpler/references/safe-moves.md`
  § *Cross-area deduplication*.
- The routine now ships those finds itself instead of filing them as
  decisions.

## Consequence of ignoring it

Silence on success (AGENTS.md § *Observability Discipline*) hides the
starvation. The routine's run list stays green, so only an owner review of its
open issues reveals that nothing ships.

See also [[registry-upsert-never-removes-a-label]]: re-kinding a piled-up
decision to task also needs its label removed.
