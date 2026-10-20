# Evidence and conventions

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: plan.specs-diagram-skill-md.evidence-and-conventions
kind: feature
depends-on: plan.specs-diagram-skill-md.skill-core
spec: specs/diagram-skill.md
evidence: design: specs/diagram-skill.md § Build Order, slice 2
<!-- task-registry:end -->

- status: open
- updated: 2026-10-19

## Summary

Slice 2/7: Upstream SKILL.md read at run time, the four jplugin conventions, the pre-finalize evidence check, and `--refresh` as the only regeneration path

## Acceptance Criteria

- [ ] AC4: `SKILL.md` instructs the agent to read `$ARCHIFY_HOME/archify/SKILL.md` and names the four jplugin conventions (evidence, output paths, browser, diagrams only); it contains no restatement of Archify's type router, schemas or finalize repair contract (`tests/test-diagram-skill.sh` greps for the upstream read and for the absence of those headings).
- [ ] AC5: For a codebase subject, `SKILL.md` requires `meta.repository` pinned to `HEAD`, `sources` on every component and `--repo-root` on `finalize`; a test fixture candidate without `sources` is named as rejected by the skill's pre-finalize check.
- [ ] AC14: `/diagram --refresh <path>` is documented in `SKILL.md` as the only regeneration path, and `/wrap-up-session`'s SKILL.md is unchanged by this feature (`git diff --stat` on it is empty at wrap-up).
