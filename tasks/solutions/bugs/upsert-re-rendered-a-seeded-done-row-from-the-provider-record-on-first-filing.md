---
title: upsert re-rendered a seeded done row from the provider record on first filing
date: 2026-09-22
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/upsert.py — _sync_index, _upsert_task_result
tags: [task-registry, upsert, slice, seeded-row, index]
symptoms: "Filing the seven #106 slices after slices 1 to 3 were already built re-opened their `[x]` header rows to `[ ]`; the filing commit had to re-mark them done by hand"
root_cause: "`_existing` reads the provider, so a row `/slice` seeded ahead of its task had no record; the task was created `open` and `_sync_index` re-rendered the seeded row from that record, dropping its status (and, before the slice-3 fix, its `(blocked-by:)` marker)"
resolution: "`_seeded_from_row(index, existing, task)` seeds the incoming task's status and `depends_on` from the pre-filed index row once, before the merge, when the provider has no record; `_sync_index` is a pure `render_row` again. Pinned by the seeded `[x]` block in tests/test-task-registry.sh"
---

## What happened

`/slice --file` seeds the compact row in `tasks/todo.md` before the task exists in
any provider — that is the whole point of filing from the plan block. When the
#106 build filed its slices after three of them were already `[x]`, `upsert`
found no provider record (`_existing` reads the provider, never the row), created
each task `open`, and refreshed the row from the new record. Three finished slices
came back as `[ ]`. The first fix, in slice 3, carried only the `(blocked-by:)`
marker forward and did it inside `_sync_index`, which made the renderer read the
row it was about to overwrite.

## Root cause

Two records described one task and the code trusted the wrong one. A row filed
ahead of its task is the *only* record of that task's status and blockers until
the provider learns them; treating the provider as authoritative on the first
run threw that record away.

## Resolution

`_seeded_from_row` (found by the quality gate's dispatched APOSD review, applied
in the #106 quality-gate commit) runs once in `_upsert_task_result`, after
`_existing` and before `_merge`: when the provider has no record and the index
has a row, the task takes the row's status and, if it declares none of its own,
the row's `depends_on`. `_sync_index` renders the task and nothing else.

## Prevention

- Two stores for one fact need one rule for which wins on which run. Write it
  down where the merge happens, not in the renderer.
- A test that files a `[x]` row and asserts the box survives the first `--apply`
  (`upsert seeded [x]` in `tests/test-task-registry.sh`) is the pin; a test that
  only checks the `(blocked-by:)` marker would have passed the slice-3 version.

## Related

- `../patterns/reader-and-writer-must-share-one-span-locator.md`
- `specs/plan-slices-and-handover.md` § `/slice --file`: the seeded-row contract.
