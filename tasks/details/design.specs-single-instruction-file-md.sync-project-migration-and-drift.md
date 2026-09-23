# Sync project migration and drift

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: design.specs-single-instruction-file-md.sync-project-migration-and-drift
kind: feature
spec: specs/single-instruction-file.md
evidence: design: specs/single-instruction-file.md § Build order, slice 4
<!-- task-registry:end -->

- status: open
- updated: 2026-09-22

## Summary

Slice 4/6: sync-managed-block.py --migrate moves everything but the five generic sections below the end marker and deletes .claude/project.md; /sync Step 6.6 runs it inside the approved run; drift compares block hashes. After: Plugin hooks, slim banner, hook retirement.

## Acceptance Criteria

- [ ] --migrate moves the pointer, the targets table and a team section in order, leaves the five generic sections, exits 2 on a doubled targets table with project.md intact, and re-runs as nothing to move
- [ ] a template commit touching only text below the end marker produces no drift line
