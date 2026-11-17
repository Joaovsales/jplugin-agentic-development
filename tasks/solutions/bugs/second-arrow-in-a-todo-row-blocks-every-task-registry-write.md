---
title: a second `->` in any tasks/todo.md row blocks every task-registry write
date: 2026-11-15
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/index.py
tags: [task-registry, todo-index, legacy-row, arrow-delimiter, upsert, malformed-index]
symptoms: Every `task-registry upsert` (dry run included) refused with "refusing to act on a malformed index — fix these rows first: tasks/todo.md:2800 — cannot publish legacy row: multiple '->' delimiters are ambiguous"; the row was an already-ticked `[x] TDD:` row from a merged plan block (#372), unrelated to the tasks being filed
root_cause: A legacy `TDD: <test> -> <implementation>` row is split on its single `->` (registry/index.py:299-302). Prose inside the row that also used an arrow ("overlaps go 5 -> 0") made two arrows, which index.py:307-308 reports as a parse problem; the strict loader that every writing command goes through refuses the whole index on any problem (index.py:390-394), by design, so one closed row deadlocked all writes
resolution: Reworded the prose arrow in that row ("go from 5 to 0") so the row carries exactly one `->`; `upsert` then ran clean. Prevention — inside a `TDD:` row write transitions in words or with `→`, never a second ASCII `->`
---

# A second `->` in any tasks/todo.md row blocks every task-registry write

The 2026-11-15 session tried to file three bug issues (#413–#415) and every
`upsert` refused before reaching GitHub, naming `tasks/todo.md:2800`.

## Why one closed row stops everything

- `ARROW_SPLIT` finds every `->` in a row; a legacy `TDD:` row is accepted only
  with exactly one (`.agents/skills/task-registry/scripts/registry/index.py:299`).
- Two or more arrows on a non-canonical row is a problem, not a guess
  (`index.py:307-308`).
- Writers load through the strict loader, which refuses on any problem anywhere
  in the index (`index.py:390-394`). The docstring explains why: a row that
  failed to parse would be re-appended with a duplicate id on the next write.

The refusal is correct; the trap is that the row's *status* does not matter — a
ticked `[x]` row in a long-merged plan block is enough.

## Fix and prevention

Reword the offending prose so the row has one `->`. When writing plan-block
`TDD:` rows (`/slice`, `/build` handovers), express counts and transitions in
words or with the Unicode `→`; reserve the ASCII `->` for the test→implementation
separator.

Related: #412 (an HTML comment marker in a title deadlocks the next upsert — the
same "one bad row blocks all writes" shape).

Related: [inspection-and-action-need-two-loaders-not-one](../patterns/inspection-and-action-need-two-loaders-not-one.md) — why the strict loader refuses instead of skipping the bad row.
