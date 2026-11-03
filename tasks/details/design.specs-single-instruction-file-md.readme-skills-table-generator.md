# README skills table generator

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: design.specs-single-instruction-file-md.readme-skills-table-generator
kind: feature
spec: specs/single-instruction-file.md
evidence: design: specs/single-instruction-file.md § Build order, slice 6
<!-- task-registry:end -->

- status: open
- updated: 2026-09-22

## Summary

Slice 6/6: scripts/render-skills-table.py renders the README skills table from SKILL.md frontmatter between markers; --check drift test; /tidy inventory runs it as its Tier 0 fix. After: install.sh stops copying.

## Acceptance Criteria

- [ ] render-skills-table.py --check exits 0 on HEAD, 1 with a diff on a removed row, 2 naming the directory on a skill without description
- [ ] tests/test-skills-table.sh runs the check; /tidy inventory names the generator with the <template-clone> prefix
