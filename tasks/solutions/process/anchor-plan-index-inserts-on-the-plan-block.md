---
title: Anchor a tasks/todo.md insert on its `## Plan:` block, not on a slice heading
date: 2026-10-19
problem_type: process
module: tasks/todo.md, .agents/skills/build, .agents/skills/slice
tags: [todo-index, handover, slice-headings, plan-block, parser]
applies_when: writing a `> Handover:` blockquote, marking rows or inserting anything under a `### Slice n/N` heading in `tasks/todo.md`
---

## What happened

The slice 1 handover of `## Plan: session-viz-mod` was inserted "before the first
`### Slice 2/5` heading" — and the first such heading in `tasks/todo.md` belongs to
`## Plan: visual-e2e-evidence`, an older block hundreds of lines above. The index
is every plan ever built here, so slice headings repeat per block. Nothing noticed
until the new plan parser (`mods/session-viz/hooks/plan.tsx`, `parsePlan`) was
run over the real file and read `session-viz-mod · slice 0/5` with no handover on a
slice whose handover had been committed. Fixed by moving the three lines
(commit "docs(todo): slices 2-5 done with handovers; move the slice 1 handover
into its own plan block").

## The rule

Locate the `## Plan: <feature>` line first, then search for the slice heading
only between it and the next line starting `## `; insert after the slice's last
row (before the trailing blank line). After any edit to the index, re-run a
reader that understands the grammar — `python3 .agents/skills/slice/scripts/slice.py ready --index tasks/todo.md --spec <spec>`
or the session-viz parser — and check that the slice numbers and handover marks it
reports are the ones just written.

## Consequence of ignoring it

The next slice's delegation prompt carries no handover (the build prompt reads
the blockquote under the heading), `slice.py ready` keeps the slice open, and a
reader of the older plan finds a handover about a different feature under its
slice 1.
