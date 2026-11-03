# Provenance

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: plan.specs-diagram-skill-md.provenance
kind: feature
depends-on: plan.specs-diagram-skill-md.skill-core
spec: specs/diagram-skill.md
evidence: design: specs/diagram-skill.md § Build Order, slice 4
<!-- task-registry:end -->

- status: open
- updated: 2026-10-19

## Summary

Slice 4/7: `kind: installed` in the upstreams registry and its validator, the notices section, README § Sources and the `.archify/` ignore rule

## Acceptance Criteria

- [ ] AC7: `.github/upstreams.json` carries the Archify entry with `kind: "installed"`, `ref: "refs/tags/v3.2.0"` and the tag's commit as `baseline`; `scripts/check-upstream-drift.py --validate` passes; the same entry with a `paths` list fails validation naming `paths` (`tests/test-upstream-drift.sh`).
- [ ] AC8: `.gitignore` ignores `.archify/`; `THIRD_PARTY_NOTICES.md` has an Archify section with the MIT text; README § Sources names Archify.
