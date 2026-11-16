# Code-graph evaluation checkpoint

Updated: 2026-11-16T03:48:50.057288+00:00

- Active task: `/build specs/code-graph-adoption.md`, user steering: “Unblock the eval”. Persistent loop continues until MERGED, NO-GO-RECORDED or HALTED-NEEDS-USER in `tasks/code-graph-run.md`.
- Branch: code-graph/treatment; recovery commit: 9cb5487. Slices 1–7 done, 8 done, 9 ready on the no-go path. Phase A PR #416 is merged.
- Read `tasks/code-graph-run.md`, `tasks/eval-results/code-graph/job-control.json`, and `execution-state.json` before launching anything. An active batch owns the shared cached-suite lock. Do not start another runner or any full suite while it is active.
- Completed execution session: 57570, exit 0; no active launcher. Log: `/tmp/code-graph-paid-compat-1-2026-11-16.log`.
- Reviewed compatibility migration is already applied and committed. Do not reapply. It preserves failed attempt A/invoice-rounding/1/0/1 and its $1.660241 accounted charge. Same-slot retry A/invoice-rounding/1/0/2 completed successfully, score 1.0, nominal $0.1524704/accounted $0.23920710; the batch advanced to the fixed next slot.
- Active manifest: `tasks/eval-results/code-graph/run-manifest-usage-compat-1.json`, SHA256 f91ff5d287569ab8c6cb8594d6c55f01ce9c2bbeaa3c39e39f557af01150c23a. Protocol commit f1f4df8715029e380c8b4e382a4547152f4082df and SHA256 eceb8b458bf7b0464d0b523de8e87eec61f621151818aa29c1b4881932798dfd stay frozen. Never edit protocol/go-rule bytes, initial manifest, prior attempts or charges.
- Verified runtime hashes, graphify pin, committed protocol identity and unchanged retry state before launch. Offline unittest discovery: 41 tests pass in 14.474 seconds. Prior reviewed receipt includes 43 checks with relay tests and 86.25% aggregate coverage.
- Budget: $4 per attempt/$320 total, conservative upper accounting, including failures. Cohort: A/B/D, 10 cases, N=3, fixed 90 selected slots; no added threshold-chasing runs. No package installation or force-push. Future admission assumption failure requires evidence review before any payment.
- Monitor background session until completion or halt; verify results, finish slice 8 with a handover, dispatch released slice 9, then quality/full-suite/Linux-CI and `/wrap-up-session` under the spec's outcome branch rules.

## Latest result
- All 90 selected runs completed, 91 charged attempts, pending null, no halt. Native nominal $12.60879440; accounted upper $20.58969660.
- Grader: no-go on rules 2/4/6; 1/3/5 pass. B token ratio 1.230145, adoption 0/21; D token ratio 1.270499; all localization outcomes 100%. No rule-only retry. Results and evidence index under tasks/eval-results/code-graph/2026-11-16/.
- Next: close slice8 commit; prepare slice9 optional wording/numerical learning and independent pin transport on results branch; quality gates, full suites, treatment PR closed unmerged, results PR merged on green Linux CI. No additional paid runs.

- Slice8 closed in36a1805. Slice9 optional wording/numerical and compatibility learnings prepared; 47 solutions-schema assertions pass. Independent discarded-treatment design review has one manual SHOULD-FIX (duplicated freshness policy), retained in /tmp/code-graph-treatment-design-review.md; treatment must not merge. New results worktree: /home/joaosouto/orca/workspaces/jplugin-agentic-development/code-graph-results on code-graph/results at origin/master4883c06. pin_transport_no_go worker owns only its installer/test, carrying the one-line adjacent pin hygiene fix without treatment hooks. No full suite active.
