---
title: TDD enforcement
date: 2026-09-01
problem_type: architecture-decision
module: CLAUDE.md, .agents/skills/tdd
tags: [tdd, regression-tests, behavior-first, red-green-refactor]
applies_when: Implementing or correcting behavior that can be expressed as an executable test
date_source: git-log
migrated_from: tasks/memory.md
---

## TDD enforcement

Write the failing test before production code, then implement minimally and refactor.
The core workflow records that sequence for every build task (`CLAUDE.md:36-45`),
while `/tdd` treats tests written after implementation as coverage rather than TDD
(`.agents/skills/tdd/SKILL.md:77-102`).
