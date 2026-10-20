# Tidy tools check

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: plan.specs-diagram-skill-md.tidy-tools-check
kind: feature
depends-on: plan.specs-diagram-skill-md.provenance
spec: specs/diagram-skill.md
evidence: design: specs/diagram-skill.md § Build Order, slice 6
<!-- task-registry:end -->

- status: open
- updated: 2026-10-19

## Summary

Slice 6/7: The tenth `/tidy` check comparing the installed commit with the registry baseline

## Acceptance Criteria

- [ ] AC13: `/tidy` § The checks has a `tools` row describing the `$ARCHIFY_HOME` commit vs registry baseline comparison, its inconclusive case and its Tier 1 remedy; `tests/test-skill-references.sh` and `tests/test-doc-conventions.sh` still pass.
