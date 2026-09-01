---
title: Memory.md + lessons.md
date: 2026-09-01
problem_type: architecture-decision
module: tasks/solutions, tasks/history.md
tags: [learning-store, migration, superseded, history]
applies_when: Reviewing why the retired monolithic memory and lessons files were replaced
date_source: git-log
migrated_from: tasks/memory.md
---

> **Superseded (2026-08-13)**: the two-tier memory.md/lessons.md store this
> decision describes was retired by M3 — the typed learning store
> (`tasks/solutions/`, one document per learning) replaced both files. Kept
> verbatim below as the historical record of the decision it reverses.

The current store schema explicitly identifies the typed store as the replacement
and assigns one learning per document (`tasks/solutions/README.md:1-15`).

## Memory.md + lessons.md

**Rationale**: Two-tier learning: tactical (lessons.md) vs strategic (memory.md)
