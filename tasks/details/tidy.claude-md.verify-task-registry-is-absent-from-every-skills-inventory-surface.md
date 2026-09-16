# verify-task-registry is absent from every skills inventory surface

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: tidy.claude-md.verify-task-registry-is-absent-from-every-skills-inventory-surface
kind: task
source: CLAUDE.md
evidence: [SHOULD-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent] CLAUDE.md:454 — the table is headed .agents/skills/ and verify-task-registry ships there, yet has no row
evidence: ## Skills — `.agents/skills/` (CLAUDE.md:454)
evidence: description: Verify this repository's task-registry CLI through isolated local task creation, reading, and routine selection with retained PTY evidence. (.agents/skills/verify-task-registry/SKILL.md:3)
evidence: discovered: tidy 2026-09-16 @ 80e265c
proposed-fix: Add a row for /verify-task-registry to CLAUDE.md § Skills and README.md § Skills, and a line to the SKILLS AVAILABLE block in .claude/hooks/session-start.sh, using the skill description verbatim.
<!-- task-registry:end -->

- status: open
- labels: documentation, next
- updated: 2026-09-16

## Summary

The skill ships in both trees but appears in no skills table and not in the session-start banner, so it is invisible to any reader of the docs or the startup listing.

## Proposed fix

- Add a row for /verify-task-registry to CLAUDE.md § Skills and README.md § Skills, and a line to the SKILLS AVAILABLE block in .claude/hooks/session-start.sh, using the skill description verbatim.

## Acceptance Criteria

- [ ] Each of CLAUDE.md, README.md and .claude/hooks/session-start.sh names /verify-task-registry.
