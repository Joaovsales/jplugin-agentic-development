---
title: Subagents for research
date: 2026-09-01
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
