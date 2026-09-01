---
title: Spec before code
date: 2026-09-01
problem_type: architecture-decision
module: CLAUDE.md, .agents/skills/plan
tags: [spec-first, planning, scope-control, acceptance-criteria]
applies_when: Starting a non-trivial feature or changing behavior with multiple acceptance criteria
date_source: git-log
migrated_from: tasks/memory.md
---

## Spec before code

The workflow requires a formal spec before source edits and a TDD plan before code
(`CLAUDE.md:31-44`). This makes behavior, edge cases, and acceptance criteria the
contract reviewed during implementation rather than an explanation written after it.
