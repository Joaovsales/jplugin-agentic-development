# Collapse the seven-region syncable-path enumeration into script-owned data

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.syncable-paths-single-source
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: tests/test-syncable-paths.sh:8-19 names seven hand-maintained regions across three files (the § Syncable Paths doc block, two `git diff` argument lists, their two compat-copy twins, and the session-start.sh drift check); .agents/skills/sync/scripts/sync-retire.py:parse_syncable_roots became an eighth *consumer* of the block rather than an eighth copy, but the other six copies are unchanged, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

The syncable-path list is retyped in seven regions across three files. `tests/test-syncable-paths.sh` pins them equal, which catches drift but does not remove it — the drift it was written for (a missing `.agents/agents` in the drift check) had already shipped. Deterministic retirement made the list machine-read for the first time; the remaining six regions could read the same source instead of restating it.

## Acceptance Criteria

- [ ] The `## Syncable Paths` doc block, or a data file it renders from, is the only place the path list is written
- [ ] The two `git diff` argument lists in SKILL.md and their compat-copy twins are generated or read from that source rather than retyped
- [ ] `.claude/hooks/session-start.sh` reads the same source for its drift check
- [ ] `tests/test-syncable-paths.sh` still fails when any consumer disagrees with the source
- [ ] Canonical and compatibility skill trees stay byte-identical

## Notes

Deferred from the deterministic-retirement build: collapsing the other six regions
would have widened that change well beyond its routed radius.
