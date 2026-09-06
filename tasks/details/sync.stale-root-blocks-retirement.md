# A root retired upstream turns a valid sync-keep into a hard failure

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.stale-root-blocks-retirement
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `if not _reaches_a_root(pattern, roots):` raising `is outside every syncable root ... it can never protect anything` in `validate_pattern` (`.agents/skills/sync/scripts/sync-retire.py`); reproduced in code review of the deterministic-retirement change — a project sync-keep naming `.claude/browsers/**` against a template whose doc block no longer declares that root exits 1 and retires nothing at all, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

`validate_pattern` resolves sync-keep patterns against the *current template's* root list, so a pattern that was correct yesterday becomes a hard exit 1 the day upstream drops that root — blocking every unrelated retirement in the same run, and blaming the project's file for a change that happened in the template.

Distinct from [[sync.retired-root-orphans]], which is about orphaned *files* surviving; this is about a stale *pattern* disabling the whole pass.

Raised as `owner: human` because softening a hard failure in a tool that deletes files is a policy call: reporting `orphaned:` and continuing trades a loud stop for a quieter one, and the right default depends on how much upstream root churn is expected.

## Acceptance Criteria

- [ ] A pattern whose head names a root the template no longer declares is reported, not fatal
- [ ] The report distinguishes it from a pattern that never named any root, which stays fatal
- [ ] Unrelated retirements in the same run still proceed
- [ ] The message names the template as the thing that changed, not the project's file
- [ ] `tests/test-sync-retirement.sh` covers both classes and pins that they are not conflated

## Notes

Found in the second review round of the deterministic-retirement build. Related: [[sync.retired-root-orphans]], [[sync.retire-blast-radius-cap]].
