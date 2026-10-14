# Reconcile specs/compound-engineering-adoption.md with current learning-store, review and guard behavior

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: spec-reconciliation.specs-compound-engineering-adoption-md
kind: research
spec: specs/compound-engineering-adoption.md
evidence: selected-by: project-template/tasks/solutions/README.md (M, committed)
evidence: inspected: specs/compound-engineering-adoption.md § Behavior M3 overlap paragraph, § Guards, § Acceptance Criteria Tier 1, § Files Likely Involved; existence of every listed path
evidence: missing: a re-trace of M1, M2 and M4-M7 against the current tree, out of scope for #168 (the owner chose to defer)
evidence: revision: claude/jplugin-issue-168-880fce @ 5178b2a
<!-- task-registry:end -->

- status: open
- updated: 2026-10-14

## Summary

The legacy spec was updated for per-track overlap scoring (#168), which triggers its migration (implementation_paths, Implementation Paths, factual tense, AC bullets). Its M1-M7 sections have drifted: Files Likely Involved names the retired .claude/skills/** tree and the removed auto-improve skill, and acceptance criteria refer to both skill trees. Migrating accurately needs every mechanism re-traced against the current tree.

## Acceptance Criteria

- [ ] Determine the current behavior
- [ ] Update specs/compound-engineering-adoption.md and its implementation_paths to match
- [ ] Add deterministic coverage where the gap came from a missing test
