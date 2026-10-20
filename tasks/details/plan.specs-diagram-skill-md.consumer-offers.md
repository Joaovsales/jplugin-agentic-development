# Consumer offers

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: plan.specs-diagram-skill-md.consumer-offers
kind: feature
depends-on: plan.specs-diagram-skill-md.evidence-and-conventions
spec: specs/diagram-skill.md
evidence: design: specs/diagram-skill.md § Build Order, slice 5
<!-- task-registry:end -->

- status: open
- updated: 2026-10-19

## Summary

Slice 5/7: One-line diagram offers in `/how` and `/plan`, the architecture diagram as a `/system-design-planning` deliverable, Mermaid/ASCII instruction removed

## Acceptance Criteria

- [ ] AC10: `/how`'s SKILL.md ends its output contract with the one-line diagram offer, and `references/explainer-prompt.md` no longer instructs Mermaid or ASCII diagrams (`tests/test-diagram-skill.sh` greps both).
- [ ] AC11: `/plan` § 4 Present carries the one-line diagram offer for multi-component features (`tests/test-diagram-skill.sh` greps it).
- [ ] AC12: `/system-design-planning` names the architecture diagram beside the spec as a deliverable and the no-tool behaviour: install command printed, session continues (`tests/test-diagram-skill.sh` greps both).
