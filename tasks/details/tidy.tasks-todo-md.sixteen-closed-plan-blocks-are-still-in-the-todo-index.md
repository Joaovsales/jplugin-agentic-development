# Sixteen closed plan blocks are still in the todo index

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: tidy.tasks-todo-md.sixteen-closed-plan-blocks-are-still-in-the-todo-index
kind: task
source: tasks/todo.md
evidence: [NITPICK | confidence: 100 | autofix_class: manual | owner: agent] tasks/todo.md:148 — first of 16 closed plan blocks below the second-newest session summary (line 31)
evidence: ## Plan: M4 — Accreting Concept Glossary (Tier 3.3) (tasks/todo.md:148)
evidence: discovered: tidy 2026-09-16 @ 80e265c
proposed-fix: Move each fully-checked plan block into tasks/history.md under its own session heading, leaving the open rows and the two newest session summaries in the index.
<!-- task-registry:end -->

- status: open
- labels: documentation, next
- updated: 2026-09-16

## Summary

tasks/todo.md is specified as an index but carries 16 fully-checked plan blocks older than the last two session summaries, inflating it to 837 lines and burying the 15 genuinely open rows.

## Proposed fix

- Move each fully-checked plan block into tasks/history.md under its own session heading, leaving the open rows and the two newest session summaries in the index.

## Acceptance Criteria

- [ ] tasks/todo.md contains no fully-checked plan block older than the last two Session Summary headings.
