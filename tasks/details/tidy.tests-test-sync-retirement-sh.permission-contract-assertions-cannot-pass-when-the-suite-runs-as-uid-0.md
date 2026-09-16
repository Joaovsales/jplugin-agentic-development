# Permission-contract assertions cannot pass when the suite runs as uid 0

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: tidy.tests-test-sync-retirement-sh.permission-contract-assertions-cannot-pass-when-the-suite-runs-as-uid-0
kind: task
source: tests/test-sync-retirement.sh
evidence: [SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent] tests/test-sync-retirement.sh:1014 — chmod a-w cannot make a path undeletable for uid 0, so the assertion that it survived always fails
evidence: chmod a-w "$P16/.agents/skills/z-locked" (tests/test-sync-retirement.sh:1014)
evidence: chmod 000 "$F_BADSPEC/specs/locked.md" (tests/test-task-registry.sh:1357)
evidence: discovered: tidy 2026-09-16 @ 80e265c
proposed-fix: Skip or re-express the permission-dependent assertions when os.geteuid()==0 (guard + explicit skip note), so the suite reports inconclusive rather than red on a root runner.
<!-- task-registry:end -->

- status: open
- labels: tech-debt, next
- updated: 2026-09-16

## Summary

Eleven assertions across two test files encode "the OS refuses this write/read"; uid 0 holds CAP_DAC_OVERRIDE, so they always fail and Law 3 blocks every Tier 0 repair in the scheduled container.

## Proposed fix

- Skip or re-express the permission-dependent assertions when os.geteuid()==0 (guard + explicit skip note), so the suite reports inconclusive rather than red on a root runner.

## Acceptance Criteria

- [ ] bash tests/run.sh exits 0 as root, with the permission-dependent assertions reported as explicitly skipped rather than failed.
