---
title: Dispatch disjoint slices in scratchpad copies and verify the merge centrally
date: 2026-10-19
problem_type: process
module: .agents/skills/build, mods/session-viz
tags: [build, parallel-dispatch, slices, sub-agents, verification]
applies_when: "/build's ready set holds two or more disjoint slices of one package and the harness's `isolation: \"worktree\"` would branch the agents from the wrong base"
---

## The pattern

`slice.py ready` listed four disjoint slices of `mods/session-viz` (one `.tsx`
and one `.test.ts` each). `/build` § *Parallel Dispatch Assessment* says to pass
`isolation: "worktree"` to each agent, but on this harness an agent worktree is
cut from `master`, not from the session branch, so the agents would not have
seen slice 1's shell. What worked instead, with the same isolation guarantee:

1. Copy the committed package once per slice into the session scratchpad
   (`<scratchpad>/slices/s<n>/<package>`), each with its own `tsconfig-s<n>.json`
   pointing at that copy.
2. One shared brief file (paths, the exact commands, the engine rules learned so
   far, the test idioms, a tool budget with a "stop and return partial" hatch,
   and a fixed receipt format) plus a per-slice prompt carrying only that slice's
   TDD rows, ACs, decisions and the blocker's handover verbatim. The agents never
   run the repository suite — a shared lock and the orchestrator own that.
3. The agents write only their two files in their copy. The orchestrator merges
   the eight files into one tree, runs `claude plugin validate`, `claude plugin test`
   and `tsc` once, fixes the cross-slice collisions the copies could not see,
   then commits one slice at a time and runs `slice.py check --slice n --base <parent>`
   against each slice's own parent commit (a check against the plan's base lists
   every later slice's files as `undeclared`).

Each agent returned green in its copy; the merged tree had exactly one collision
(two matcher-less `agent.spawn` hooks, see
[declare-atoms-per-file-and-match-every-shared-event-hook-in-a-claude-code-mod](../tooling/declare-atoms-per-file-and-match-every-shared-event-hook-in-a-claude-code-mod.md)),
found by the central validate in one run. Two agents independently reported the
same engine rule as an `[AMBIGUITY]`, which is the signal that it belongs in the
shared brief for the next session.

## The rule

Isolate the edits, centralise the verification: a per-slice copy that only the
slice's files change is as safe as a worktree and starts from the right tree;
every cross-file property (hook registrations, shared constants, a contract
field one slice writes and another reads) is checked once on the merge, never
by the agents. Give every agent a return template — `FILES / VALIDATE / TEST /
TSC / AMBIGUITY / SURFACE / NOT FINISHED / NOTES` — so the merge step reads
eight lines per slice instead of a transcript.

## Consequence of ignoring it

Agents branched from the wrong base reimplement what the blocker slice already
landed (this repository's history has one such case, the `/build` off a stale
`master` that re-did #53), and agents told to run the suite themselves multiply
a 30-minute Windows suite by the number of slices and fight over the shared
`cached-suite` lock.
