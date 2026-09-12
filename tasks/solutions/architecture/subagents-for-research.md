---
title: Subagents for research
date: 2026-09-12
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

PR #128 review exposed an edit-only reading rule that could omit callers and
contracts outside the changed lines. The bulk-read handoff now requires the
implementing agent to inspect those dependencies before editing and permits
successive bounded reads of an entire relevant component (`CLAUDE.md:427-444`,
`.agents/skills/build/SKILL.md:143`). The scout reports anchors, inspected scope,
and unknowns (`.agents/agents/bulk-reader.md:11-19`); a summary is navigation,
not proof of correctness.

Measure coding behavior separately from retrieval cost. A compact answer to an
inventory question does not demonstrate that a builder can safely change a
component. The coding protocol and its measured limits live in
`tasks/eval-results/bulk-read-context/protocol.md`.

The PR #128 coding runs passed their held-out behavior checks even when scout
maps misdescribed local text preservation. The measured report
(`tasks/eval-results/bulk-read-context/README.md`, observed tradeoffs section)
therefore separates behavioral results, inspected dependencies, map fidelity,
and total model usage. None is a substitute for the other.
