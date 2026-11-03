# Installer

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: plan.specs-diagram-skill-md.installer
kind: feature
spec: specs/diagram-skill.md
evidence: design: specs/diagram-skill.md § Build Order, slice 3
<!-- task-registry:end -->

- status: open
- updated: 2026-10-19

## Summary

Slice 3/7: `install.sh` clones the pinned tag when Node ≥ 18 is present, reports present or a NOTE otherwise

## Acceptance Criteria

- [ ] AC6: `install.sh` on a machine with `node` ≥ 18 and an isolated `HOME` clones Archify into `$ARCHIFY_HOME` at commit `208acba8…` and reports "installed"; a second run reports "present" without network; without `node` it prints a NOTE containing the install command and exits 0 (`tests/test-install-sh.sh`).
