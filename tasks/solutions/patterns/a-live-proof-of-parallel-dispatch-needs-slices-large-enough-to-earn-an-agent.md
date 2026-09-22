---
title: A live proof of parallel dispatch needs slices large enough to earn an agent
date: 2026-09-22
problem_type: pattern
module: /build Parallel Dispatch Assessment; e2e fixtures for the plan → slice → build flow
tags: [e2e, fixture-design, parallel-dispatch, sub-agents, slices]
applies_when: designing a fixture feature or a live walkthrough whose acceptance criterion is that two independent slices dispatch in parallel, or that a handover is consumed by a separately dispatched agent
---

## The pattern

`/build` § Parallel Dispatch Assessment is an *assessment*: the orchestrator decides
whether independent work earns a sub-agent, and a one-to-three-file stdlib slice does
not. The 2026-09-22 walkthrough for `specs/plan-slices-and-handover.md` AC 15 built a
four-slice greeting toolkit whose two ready slices were `greet.py` + its test and
`farewell.py` + its test. `slice.py ready` named both with disjoint surfaces, so the
pre-condition held, and the session then wrote all four slices inline in sequence.
Its five `Agent` calls were all reviewers. Its own report said why: "dispatch overhead
exceeded the work."

The consequence is that two of the criterion's sub-claims could not be observed at all:

- **parallel dispatch of two disjoint slices** — nothing was dispatched;
- **a handover read by a blocked slice** — the same context wrote the handovers and
  then built the blocked slice, so there was no delegation prompt for a handover to
  cross and no fresh reader whose only source was the blockquote.

The handover *content* was correct and sufficient, and the surface reports fired on
every slice. What the fixture could not produce was the dispatch boundary.

## How to apply

- Size each ready slice above the orchestrator's dispatch threshold: several files,
  more than one system, real test setup — enough that an agent is cheaper than doing
  it inline. Two such slices in the ready set is the minimum.
- Make the blocked slice's correctness depend on a fact only the handover carries (a
  signature the spec does not state, a sha, a decision recorded during the build), so
  "read the handover" is observable as a correct import or call rather than inferred.
- Grade dispatch from the transcript's `Agent` tool-use blocks and their prompts, never
  from the session's narration; a prompt that quotes the `> Handover:` line is the
  evidence.
- Record a run that could not dispatch as *not observed*, not as failed and not as
  passed. The tool under test behaved as designed; the fixture asked the wrong question.

## Related

- `tasks/e2e-log.md`, section "plan-slices-and-handover — 2026-09-22": the run this
  came from, with the transcript timestamps.
- `../tooling/print-mode-skill-probes-on-windows-git-bash.md`: the same run also
  showed the harness loading user-scope skill copies over the project-local ones.
