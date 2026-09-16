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
evidence: [SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: human] tests/test-sync-retirement.sh:1014 — chmod a-w cannot make a path undeletable for uid 0, so the assertion that it survived always fails
evidence: CONFIRMED, separate execution environment: .github/workflows/tests.yml runs the identical `bash tests/run.sh` on ubuntu-latest (non-root) and check run 104822246328 on PR #140 concluded success in 52s, while the same command fails 2/42 files as uid 0. The repository is not defective; the routine host is.
evidence: run: bash tests/run.sh (.github/workflows/tests.yml:22)
evidence: discovered: tidy 2026-09-16 @ 80e265c; corroborated by CI @ 7e6be6c
proposed-fix: Preferred: run the scheduled routine container as a non-root user, matching CI — this keeps full coverage. Alternative, if root is unavoidable: guard the permission-dependent assertions on os.geteuid()==0 and report them explicitly skipped, accepting the coverage loss on that host.
<!-- task-registry:end -->

- status: open
- labels: tech-debt, next
- updated: 2026-09-16

## Summary

Eleven assertions across two test files encode "the OS refuses this write/read"; uid 0 holds CAP_DAC_OVERRIDE, so they always fail and Law 3 blocks every Tier 0 repair in the scheduled container. CONFIRMED by CI: the identical command passes on a non-root runner.

## Proposed fix

- Preferred: run the scheduled routine container as a non-root user, matching CI — this keeps full coverage. Alternative, if root is unavoidable: guard the permission-dependent assertions on os.geteuid()==0 and report them explicitly skipped, accepting the coverage loss on that host.

## Acceptance Criteria

- [ ] bash tests/run.sh exits 0 in the routine container, with no permission-dependent assertion silently failing.
