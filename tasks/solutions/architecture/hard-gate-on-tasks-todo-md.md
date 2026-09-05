---
title: Materialize workflow gates in `tasks/todo.md`
date: 2026-09-05
problem_type: architecture-decision
module: .agents/skills/wrap-up-session/references/routines.md, .agents/skills/auto-improve, tasks/todo.md
tags: [workflow-gates, task-register, gate-ledger, temporal-ordering]
applies_when: A workflow guard must run in a particular order and omission would otherwise be silent
migrated_from: tasks/memory.md
---

## Materialize workflow gates in `tasks/todo.md`

Workflow prose is not an execution invariant. Put each required operation in a
step list the running session must walk, so following the visible task register
necessarily encounters it.

This learning outlived the machinery that first demonstrated it. The routing
engine that carried the original citation was deleted wholesale — 923 lines of
policy plus 728 of tests — and the materialized rows were deliberately kept, as
the one part worth salvaging. They now live as a convention rather than an
engine: each routine names an ordered, mandatory step list
(`.agents/skills/wrap-up-session/references/routines.md` § *Step ledger*), and
`/auto-improve` Phase 3 writes this run's steps before it starts any of them.

Two properties do the work, and both were lost when the rows were only prose:

- **Two sinks, not one.** The list goes into `tasks/todo.md` *and* the PR body.
  The index is what a running session reads; the body is what a reviewer reads,
  and a gate that never ran is invisible in exactly the second one.
- **A skipped row is retained, never deleted**, carrying `skip: <reason>`. A
  deleted row reads as a workflow that never had that gate.

The failure this closes is not bad code reaching review — human PR review catches
that. It is an **absent gate**, which leaves no trace in the diff a human reads.
Pipeline #93 shipped green with `/quality-gate` and the pre-push reviewers never
having run: not by decision, by omission.

Generalizes to any ordering constraint — "record before edit", "check scope
before push" — which belongs in the task register with skipped operations
retained and explained, rather than only in descriptive prose.
