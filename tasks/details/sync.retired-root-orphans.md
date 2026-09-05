# A syncable root retired upstream leaves permanent orphans

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.retired-root-orphans
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `.agents/skills/sync/scripts/sync-retire.py` computes its scan set as exactly the roots the current template declares (`compute_plan` calls `parse_syncable_roots` on the template's doc block), so a directory removed from the block is never scanned again; pinned as intended behaviour by `tests/test-sync-retirement.sh` — "a path under a root the doc block does not declare is never scanned". Raised in code review of the deterministic-retirement change, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

Deterministic retirement removes files *within* the declared roots. If a whole root is retired upstream — the directory leaves the `## Syncable Paths` block — the project's entire copy of it survives forever, because nothing scans a root the template no longer declares. This is a silent hole in the "a file retired upstream is removed without a human classifying it" criterion, at the granularity of a whole directory.

It is not fixable by scanning more: the previous root list is not available to the script, and widening the scan to undeclared directories is exactly the attack the root-shape constraint was added to prevent.

## Acceptance Criteria

- [ ] A root present in the project but absent from the template's doc block is detected and reported
- [ ] The report distinguishes it from ordinary per-file retirement, since deleting a whole root is a larger act
- [ ] Nothing is deleted for this case without an explicit human confirmation
- [ ] The mechanism cannot be used to widen the scan to a directory that was never a syncable root
- [ ] `specs/sync-deterministic-retirement.md` § Edge Cases is updated from "needs a one-off manual deletion" to whatever is implemented

## Notes

Deferred from the deterministic-retirement build and documented in the spec's Edge
Cases in the meantime. Related: [[sync.syncable-paths-single-source]].
