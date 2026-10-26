---
title: Subagents for research
date: 2026-10-21
problem_type: architecture-decision
module: .agents/skills/build, .agents/agents
tags: [subagents, delegation, context, research]
applies_when: Independent read-heavy investigation can proceed without sharing write ownership
date_source: git-log
migrated_from: tasks/memory.md
---

## Subagents for research

Delegate one bounded question per sub-agent and keep coordinated writes in the main
context. `/build` requires focused prompts, explicit ownership, and partial-result
budgets before dispatch (`.agents/skills/build/SKILL.md:105-115`). This preserves
context without turning delegation into an unowned parallel edit.

## Source maps do not replace component understanding

Ported from PR #128 (`origin/worktree-bulk-read-gate`), superseded by
`specs/read-shunt-baseline.md` on 2026-10-21. Its review exposed an edit-only
reading rule that could omit callers and contracts outside the changed lines.
The bulk-read handoff it drafted therefore required the implementing agent to
inspect those dependencies before editing and permitted successive bounded
reads of an entire relevant component; its scout reported anchors, inspected
scope, and unknowns. A summary is navigation, not proof of correctness.

Measure coding behavior separately from retrieval cost. A compact answer to an
inventory question does not demonstrate that a builder can safely change a
component. PR #128's paired runs are preserved under
`tasks/eval-results/read-shunt/prior-128/` (`protocol.md`, `results.md`,
`prompts.json`, `blind-grades.json`): the routed arm cost more and took longer
in every round, and in round 3 a 1,406-character map replaced a 13,869-character
source while quality fell and its exception labels were invented. Behavioral
results, inspected dependencies, map fidelity and total model usage are
reported as separate columns there; none is a substitute for the other, and
`specs/read-shunt.md` § Eval design carries that separation into the read-shunt
grader's metrics.
