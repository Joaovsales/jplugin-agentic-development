# The bootstrap candidate protects a generated skill file-by-file

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.candidate-emits-per-file-patterns
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `lines.extend(_as_pattern(path) for path in plan.candidates)` in `write_candidate` (`.agents/skills/sync/scripts/sync-retire.py`) — verified output is `.agents/skills/verify-myapp/SKILL.md`, not `.agents/skills/verify-myapp/**`, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

The candidate emits one exact pattern per project-only *file*. A project-local skill is therefore protected file-by-file, so any file added to it afterwards is a fresh retire candidate. The candidate generator is the one place that could reduce this by emitting a `**` rule per project-only *directory*.

Nothing is deleted silently, so this is not a correctness defect — but the bootstrap output is the weakest form of the record the whole feature exists to produce, and it interacts directly with the `/create-verification-skill` exposure already documented in Step 6.4.

`owner: human` because widening a generated allowlist rule is a deliberate trade: a `**` per directory protects more than the operator inspected.

## Acceptance Criteria

- [ ] The candidate expresses a project-only directory as one reviewable rule
- [ ] Widening is visible to the human reviewing the candidate, never implicit
- [ ] A path that cannot be expressed is still commented rather than widened
- [ ] `tests/test-sync-retirement.sh` covers directory-level candidate emission

## Notes

Found in adversarial review (Pass 4), reported as advisory. Related: [[sync.retire-blast-radius-cap]].
