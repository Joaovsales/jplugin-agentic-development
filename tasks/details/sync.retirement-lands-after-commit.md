# Step 6.4 deletes after Step 6 has already asked the user to commit

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: sync.retirement-lands-after-commit
kind: task
spec: specs/sync-deterministic-retirement.md
evidence: `### Step 6 — Post-Sync` and `2. Ask the user if they want to commit the sync:` precede `### Step 6.4 — Retired Path Removal` in `.agents/skills/sync/SKILL.md`; raised in code review of the deterministic-retirement change, revision: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe @ HEAD
<!-- task-registry:end -->

- status: open
- updated: 2026-09-04

## Summary

The commit prompt the user is told closes the sync fires *before* the retirement pass runs, and no later step commits. The deletions — and the `.claude/sync-keep.candidate` written in bootstrap mode — are left uncommitted, so a `git checkout .` resurrects everything and the next `/sync` re-reports the same retire list.

**Pre-existing, amplified.** The old hardcoded `rm -rf` block sat in the same position; what changed is that the deletion set grew from four fixed paths to an arbitrary computed set. Filed rather than fixed in-session because reordering a user-facing procedure step is outside the boundary of the change that surfaced it.

## Acceptance Criteria

- [ ] The retirement pass and its deletions are covered by a commit
- [ ] `.claude/sync-keep.candidate` is likewise not left dangling
- [ ] The user is not told the sync is committed while deletions are still pending
- [ ] `tests/test-syncable-paths.sh` / doc-convention tests still pin the step ordering

## Notes

Found in the second review round of the deterministic-retirement build (`owner: human`). Related: [[sync.retire-blast-radius-cap]].
