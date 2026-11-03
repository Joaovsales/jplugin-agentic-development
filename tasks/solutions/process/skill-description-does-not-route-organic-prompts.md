---
title: A skill's description does not make organic prompts load it — discoverability rides on the entry point CLAUDE.md and the banner name
date: 2026-09-16
problem_type: process
module: .agents/skills/*/SKILL.md description frontmatter, /eval mode A, .claude/hooks/session-start.sh
tags: [eval, triggerability, skill-description, discoverability, go]
applies_when: shipping a new skill and deciding what an /eval Mode A miss means, or planning how a skill will actually get invoked when nobody types its slash command
---

## The observation

The `/go` triggerability eval (2026-09-16, `tasks/e2e-log.md` § "Triggerability
eval — /go Mode A") ran four organic prompts on the confusable boundaries,
N = 2, with the `go` skill committed and present in every candidate's
available-skills block. Result: **0/8 fired, 8 NONE** — and no candidate loaded
*any* skill, not `go`, not `/debug`, not `/plan`. Every candidate did the work
by hand, and most did it correctly.

The spec's AC7 treats a miss as a cue defect in the lane table, but the cues
are consulted only after the skill loads. With zero loads of any skill there
was no signal a cue or description rewrite could act on, so the lane table was
left unchanged and the result recorded as data.

## What this session concluded

- **Description-based routing is not the invocation mechanism** for a blind
  builder-tier agent given a task-shaped prompt. This matches the 2026-08-28
  audit that `tests/test-skill-invocation-chain.sh:6` cites in its header: skills
  get invoked when a host names them, not when a description matches.
- **Discoverability therefore has to be placed where the agent reads before
  acting:** the entry-point sentence in `CLAUDE.md` § *Workflow* and the first
  row and closing line of the session banner (`.claude/hooks/session-start.sh`).
  `/go` shipped both; the eval measured the skill without them, because
  candidates were blind sub-agents that do not receive the banner.
- **An /eval Mode A zero is not a ship blocker on its own** when every
  code-changing path the skill opens still passes through another skill's
  human gate — the spec said so, and the eval confirmed the failure mode is
  "not invoked", never "invoked and misrouted" (0 MISROUTED).

## How to apply

When a new interactive skill is planned, budget for its invocation surface
(CLAUDE.md sentence, banner row, README row) as part of the deliverable, not as
documentation. When an /eval Mode A run returns all-NONE, first check whether
*any* skill loaded; if none did, the miss is upstream of the description and a
description rewrite is not the fix. Record the run either way — a zero is the
baseline the next eval compares against.

Related: [record a formal E2E gap when no project verification surface exists](issue-lane-routing-e2e-gap.md) — the earlier Mode A/B eval on issue-lane routing.
