# Bound the retirement blast radius before --apply deletes

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.retire-blast-radius-cap
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `main` in `.agents/skills/sync/scripts/sync-retire.py` prints the plan and calls `apply_requested_writes` in the same non-interactive run, with no cap on the size of the retirement set and no second confirmation; raised as an advisory owner:human finding in security review of the deterministic-retirement change, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

The report satisfies "reported before deletion" literally, but nothing acts on the report: any upstream defect that inflates the retirement set destroys the whole set before a human can react. The root-shape constraint closed the known way to inflate it; a cap bounds the unknown ones.

Raised as `owner: human` because choosing a default threshold is a policy call, not an implementation detail.

## Acceptance Criteria

- [ ] `--apply` aborts, deleting nothing, when the retirement set exceeds a threshold
- [ ] The abort prints the full set and the explicit flag that overrides it
- [ ] The default threshold is justified against real sync sizes, not guessed
- [ ] Bootstrap is unaffected — it already deletes nothing
- [ ] `tests/test-sync-retirement.sh` covers the abort, the override, and a set just under the threshold

## Notes

Deferred from the deterministic-retirement build. Related: [[sync.retired-root-orphans]].
