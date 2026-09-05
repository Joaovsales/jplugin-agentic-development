# Bootstrap projects never remove the four legacy retired skills

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.bootstrap-skips-legacy-retirements
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: the removed hunk `-for retired in tdd deslop simplify verify-e2e; do` in `git diff master -- .agents/skills/sync/SKILL.md`, against `**A project with no `.claude/sync-keep` is in bootstrap.** The script retires nothing` (`.agents/skills/sync/SKILL.md`); a repo-wide grep finds no other removal path for those four names — not in `install.sh`, not in the hooks, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: done
- updated: 2026-09-04

## Summary

This change deleted the only mechanism in the repo that removed `tdd`, `deslop`, `simplify` and `verify-e2e` from downstream projects, and did not replace it for projects in bootstrap. A project with no `.claude/sync-keep` retires nothing by design — so those four stale skills now persist indefinitely where the old hardcoded loop deleted them unconditionally.

**This is the one case where the new mechanism is strictly weaker than what it replaced.** The old loop was already deterministic; it was the surrounding per-run judgement that was not. Determinism was bought here at the cost of the migration those four names encoded.

Raised as `owner: human` because the resolution is a policy choice, not an implementation detail.

## Acceptance Criteria

- [x] A bootstrap project still loses the four known-retired skills, or the cost of not doing so is recorded in the spec
- [x] Whatever mechanism is chosen does not reintroduce a hand-maintained name list that drifts
- [x] `tests/test-sync-retirement.sh` covers the bootstrap path either way
- [x] The decision is written down where the next person to read Step 6.4 will find it

## Notes

Options considered: keep the four-name loop as an explicitly-scoped legacy sweep until a project has promoted its candidate; have bootstrap flag known-retired names in the candidate; or accept and document the regression. Found in code review (Pass 1) of the deterministic-retirement build. Related: [[sync.retired-root-orphans]].

## Resolution

Resolved in the same session it was filed: bootstrap now retires paths with template provenance (`template_history_paths`), so the four legacy skills are removed without a hand-maintained name list. Pinned by `tests/test-sync-retirement.sh` §19.
