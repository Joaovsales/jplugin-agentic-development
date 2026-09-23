# References move

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: design.specs-single-instruction-file-md.references-move
kind: task
spec: specs/single-instruction-file.md
evidence: design: specs/single-instruction-file.md § Build order, slice 1
<!-- task-registry:end -->

- status: open
- updated: 2026-09-22

## Summary

Slice 1/6: the three protocol references under .agents/references/ with verbatim text, CLAUDE.md stubs, citations repointed, dispatching skills read the reference at dispatch time. After: none.

## Acceptance Criteria

- [ ] each reference file has its fixed heading set and every § citation in .agents/, .claude/agents/ and AGENTS.md resolves
- [ ] no file under .agents/ or .claude/agents/ cites CLAUDE.md § Finding Model, Review Dispatch Contract, Model Routing or Independence Accounting
- [ ] C:/Program Files/Git/quality-gate, /wrap-up-session, /software-design-expert-review and /sweep read finding-model.md § Emission format at dispatch time and state the refusal line
- [ ] .agents/references/ is a syncable root in every copy; bash tests/run.sh green
