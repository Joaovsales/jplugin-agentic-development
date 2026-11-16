# Wrap-Up Debt

> Recorded by the pre-push wrap-up gate: pushes carrying code commits that
> no `/wrap-up-session` run covers. File them as issues with
> `/task-registry upsert <id> --title '<what>' --apply --approve`, then delete the entry.

<!--
Two rows were voided on 2026-10-27, both computed by the same defect and both
already covered by earlier sessions:

  ## Joaovsales/jev-routing f621be7..8fb5bf9   (76 commits)
  ## Joaovsales/jev-routing 98d77e3..77e257b   (3 commits)

`resolve_base()` measured them against a local `master` that was 192 commits behind
`origin/master`, so the ranges were dominated by commits already on the base branch.
The resolver now prefers `refs/remotes/origin/<base>`, pinned by
tests/test-pre-push-gate.sh; see tasks/solutions/bugs/a-stale-local-base-branch-inflates-every-range-the-harness-derives.md.
They are recorded here rather than deleted so the audit trail survives — do not file
issues for them.

Three more rows were reconciled on 2026-11-16 by the covering wrap-up of the
2026-11-15/16 session (branch Joaovsales/session-wrapup). That session decided
to close them without filing a separate issue for each commit. Each range is
already on origin/master and was merged through a PR:

  ## Joaovsales/wrap-u 11ced0e..5912f21   (2 commits, recorded 2026-09-03)
     11ced0e = PR #83, 5912f21 = PR #85; both are ancestors of origin/master.
  ## fix/task-registry-gh-optional-fields 5c5fa9a..5c5fa9a   (1 commit, recorded 2026-09-04)
     5c5fa9a itself is not on master. Its change landed squash-merged as PR #92 (c3809a1).
  ## Joaovsales/jev-routing 4ff3c23..4ff3c23   (1 commit, recorded 2026-10-27)
     4ff3c23 = PR #363 (the 1.7.4 plugin-version bump), an ancestor of origin/master.
     It was correctly recorded as uncovered because its session fingerprint
     `[c9f429a..HEAD]` named no commit. It is closed here by decision, not because
     it turned out to be covered.

None of these ranges came from the 2026-11-15/16 session's own pushes.
Do not file issues for them.
-->

## Joaovsales/airllm a97f2d0..15177ce
- Recorded: 2026-11-15
- Uncovered commits: 6
- Note: a merge-range false positive, not real debt. The push carried
  `c84b542`, a merge of `origin/master` (37 commits) into this branch, and the
  gate's range spans master's history rather than this branch's two commits.
  All six — `15177ce e8dd1e2 17a7a15 7903e3a 02a2416 830db7c` — are ancestors
  of `origin/master` and were covered by their own sessions. Do not file issues
  for them.
