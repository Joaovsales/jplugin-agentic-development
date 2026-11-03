# Single AGENTS.md and its delivery

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: design.specs-single-instruction-file-md.single-agents-md-and-its-delivery
kind: feature
spec: specs/single-instruction-file.md
evidence: design: specs/single-instruction-file.md § Build order, slice 2
<!-- task-registry:end -->

- status: open
- updated: 2026-09-22

## Summary

Slice 2/6: the managed block in AGENTS.md, CLAUDE.md reduced to @AGENTS.md, .claude/project.md merged and deleted, sync-managed-block.py (replace/append/pointer), /sync Step 5 and the CI mirror writing the block, install.sh step 1 removed, budget test. After: References move.

## Acceptance Criteria

- [ ] tests/test-instruction-budget.sh passes: block ≤ 200 lines, file ≤ 16 KiB, CLAUDE.md byte-equal to @AGENTS.md, fixed heading set in order, no @ line, ≤ 1 H1, no POINTER_RE match, [AMBIGUITY] format and TODO(shortcut): present
- [ ] .claude/project.md is absent and every reader is repointed to AGENTS.md with the legacy notice
- [ ] a fixture project synced from this branch ends with a block in AGENTS.md and the pointer CLAUDE.md in the same run
- [ ] install.sh writes no ~/.claude/CLAUDE.md; the /eval triggerability report shows no regression and is linked from the PR body
