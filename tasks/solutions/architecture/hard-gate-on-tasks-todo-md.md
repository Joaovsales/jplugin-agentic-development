---
title: Materialize workflow gates in `tasks/todo.md`
date: 2026-09-01
problem_type: architecture-decision
module: .agents/skills/route/playbooks, tasks/todo.md
tags: [workflow-gates, playbooks, task-register, temporal-ordering]
applies_when: A workflow guard must run in a particular order and omission would otherwise be silent
migrated_from: tasks/memory.md
---

## Materialize workflow gates in `tasks/todo.md`

Workflow prose is not an execution invariant. Put each required operation in the
materialized lane so following the visible task register necessarily encounters it.
The route playbooks place the runtime radius tripwire immediately after `/build`
(`.agents/skills/route/playbooks/autonomous.md:3-5`), and materialization writes the
selected playbook beside the decision before returning
(`.agents/skills/route/scripts/route_issue.py:368-378`).

This extends the original planning hard gate: ordering constraints such as
"record before edit" or "check scope before push" belong in `tasks/todo.md`, with
skipped operations retained and explained, rather than only in descriptive prose.
