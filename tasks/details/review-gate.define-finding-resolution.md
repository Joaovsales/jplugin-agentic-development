# Define finding resolution per owner, and remove the owner carve-out from every gate

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: review-gate.define-finding-resolution
kind: decision
spec: specs/review-context-contract.md
evidence: wrap-up-session/SKILL.md:446 and :530 — Apply Gate carries an owner:human MUST-FIX to the report; Commit Gate STOPS on the same finding, auto-push/SKILL.md:130-131 and yolo/SKILL.md:167-168 use "unresolved" with no definition in scope, grep for a definition of resolved/unresolved across .agents/ and CLAUDE.md returns 0 hits, inspected: CLAUDE.md Finding Model, wrap-up-session 5.1 + Step 7, quality-gate Apply Gate, the four reviewer personas, revision: Joaovsales/wrap-u @ 907ac6d
<!-- task-registry:end -->

- status: open
- updated: 2026-09-03

## Summary

The word "unresolved" is load-bearing in four commit gates and defined nowhere, so each gate re-derives it and two derivations disagree.

## Acceptance Criteria

- [ ] CLAUDE.md Finding Model defines resolution per owner: agent = fixed or refuted with evidence; human = decision put to a human and answered; release = recorded as a durable task carrying an ID
- [ ] Step 7 and the 5.1 owner bullet lose the owner:human carve-out — every gate asks only whether a MUST-FIX is unresolved
- [ ] The four gate rows in wrap-up-session, auto-push, yolo, and quality-gate reference the single definition rather than restating it
- [ ] Filing a task does NOT resolve an owner:human finding — only owner:release defers that way
- [ ] tests/test-review-context.sh pins the definition and the absence of the carve-out; .claude/ mirrors stay byte-identical
