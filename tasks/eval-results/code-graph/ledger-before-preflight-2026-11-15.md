# Code-graph adoption run ledger

State: TREATMENT
Feature: https://github.com/Joaovsales/jplugin-agentic-development/issues/401
Spec: specs/code-graph-adoption.md
Base: 317a71717c34226891c3e3b019b83bebc591449d
Planning commit: bd44e96
Branch: code-graph/treatment

## Budget

- Total ceiling: $320
- Per-run ceiling: $4
- Cumulative evaluation spend: $0
- Paid runs: none; protocol not yet committed. Never start a paid run first.

## Slices

| Slice | Status | Evidence |
|---|---|---|
| 1 | done | c6aebd3, 998b58b; handover in tasks/todo.md; affected 65 files / 6481 assertions green |
| 2 | done | cd372bc; handover and clean surface check; targeted 201 assertions green |
| 3 | done | 68ed02b, 506c1eb; handover in tasks/todo.md; affected 65 files / 6481 assertions green |
| 4 | done | da5bb18; handover and clean surface check; all fixture contracts green; paid smoke deferred |
| 5 | done | c2c4826; 34 affected files/3489 assertions green; handover recorded |
| 6 | done |66f597d; typed-schema support;59 targeted assertions and shared affected run green |
| 7 | done |1655f58 plus prose repair;600-line budget; affected55files/5331assertions green |
| 8 | ready for prerequisite check | No paid run or protocol commit yet; installed CLI must match pin |
| 9 | pending | Blocked by 8 |

## Evidence and environment

- Baseline: `bash .agents/skills/build/scripts/cached-suite.sh -- env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh </dev/null` exited 1: 95 files, 8128 assertions passed, 8 failed, no skips. Log: `/tmp/code-graph-baseline.log`.
- All eight failures are installer fixture cleanup assertions; inherited `CODEX_HOME` bypasses their temporary `HOME`. Slice 1 isolates that environment in its tests.
- Installed graphifyy: 0.4.23. PyPI pin checked 2026-11-15: 0.9.109; metadata names https://github.com/Graphify-Labs/graphify. No package installed or upgraded.
- Claude Code: 2.1.325. Runner command is available; capabilities still require the slice-4 spike.
- PRs and CI run IDs: none yet. PR 1 must merge before paid evaluation.
- Shared suite lock: neighboring worktree `state-machines-skill`, PID 1872566, started 2026-11-15T18:18:56Z. Final grader command refused with exit 3; no test ran. An event-driven pidfd observer is watching process completion; no concurrent suite is launched.
- Slice 4 ordering gap: paid smoke is deferred until the protocol is committed, because AC4 governs every paid run. No smoke or evaluation has run.

## Resume

Read this ledger, then run `slice.py ready` for the linked spec. Preserve settled decisions and budget. No treatment merge without the literal six-rule go verdict and quality, full-suite and Linux CI gates. No agent package installation; no stock GRAPH_REPORT hook; no force-push.

## Batch 1 handover

- Installer and grader targeted run: 277 assertions green before review repairs.
- Final affected command: `bash .agents/skills/build/scripts/cached-suite.sh -- bash tests/affected.sh --run 317a71717c34226891c3e3b019b83bebc591449d`; exit 0, 65 files, 6481 passed, no failures or skips. Log: `/tmp/code-graph-batch-1-affected-final.log`.
- Review repairs: source-resolved sync pin; multiline and conditional shell invocations classified without treating quoted prose as calls.
- Release-only surface addition: `.claude-plugin/plugin.json` 1.8.9 -> 1.8.10, mandated by README Releasing skills and test-plugin-manifest.sh. Generated session memory block removed from AGENTS.md; no product rule changed yet.
- Neighboring suite completion observed via pidfd; no concurrent test run launched.

## Phase A release gate

- Slices 1–4 are complete. State HARNESS awaits quality gate, full suite, PR 1 and green Linux CI before merge.
- Batch 2 affected tests exited 0: 67 files, 6522 assertions passed, no failures or skips; `/tmp/code-graph-batch-2-affected.log`.
- Slice 5 is mechanically ready but embargoed by Run Protocol until PR 1 merges. No treatment files or paid results have landed.
- C excluded by the spike; exact session model id remains to be established before any protocol or paid run.
- Phase 4 design review HOLD: a copied Codex banner loses the source-tree pin. Slice 2 is adding an adjacent-pin resource contract and explicit broken state when absent; slice 6 must provision `graphify.pin` next to the copied shell hook through its already-owned installer and test surface. No Phase A installer-surface expansion.

## Phase A quality status

- Copied-hook source repair 0f31434: targeted 209 assertions green; Phase 4 design re-review GO. Adjacent pin provisioning remains an explicit slice 6 obligation.
- New standalone Python coverage: 83% overall (grader 87%, fixture generator 75%, fault stub 93%); measured with installed coverage tooling and no new dependency.
- Integrated origin/master 42eb935 in 6cb79d7. The only conflict was tasks/todo.md; both branches of the index were retained. No managed-block conflict.
- Gate test attempt refused while override-guard worktree owns PID 2241675 (2026-11-15T18:54:00Z); process exit is observed via pidfd, with no concurrent test run.

- Post-merge CLI walkthrough at 6cb79d7: 489 assertions green across the installer, session banner and grader CLI. Source and copied-hook paths were exercised against isolated fixtures.
- Quality Phases 1–3 completed inline; Phase 4 dispatched re-review GO; Phase 5 affected test and test-engineer review remain before receipt.

## Phase A gate receipt

- Quality receipt: valid GO b7cfd232, policy qg1-9478b51c, parent 1b7aec6f. Two test-encapsulation findings were repaired through public CLI fixtures and independent public-case expectations; test-engineer re-review reports no findings.
- Latest affected gate: 71 files, 6703 assertions passed, zero failures/skips; `/tmp/code-graph-phase-a-delta-tests.log`. New standalone Python coverage remains 83%.
- Full-suite evidence path: `/tmp/code-graph-phase-a-full-suite.log`; command is `bash .agents/skills/build/scripts/cached-suite.sh -- env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh </dev/null`. The cache and command exit determine the release outcome.
- PR 1: https://github.com/Joaovsales/jplugin-agentic-development/pull/416; tested head `45d05a6042585b702109a613740b3ea5fb9701e7`, mergeable. Feature issue stays open because slices 5–9 remain.
- Local full suite exited 0: 97 files, 8217 assertions passed, no failures or skips. CI is running; the watcher log is `/tmp/code-graph-pr1-ci.log`.

## Phase A merged

- PR 1 #416 merged 2026-11-15T19:27:42Z at c7360e41fc0c466764b0bb4e32df6dd35d279b5b.
- Linux CI run 43752230413 succeeded for tested head45d05a6042585b702109a613740b3ea5fb9701e7; full suite97files/8217assertions green; wrap-up closure terminal complete.
- Arm A baseline is c7360e41fc0c466764b0bb4e32df6dd35d279b5b. Treatment remains unmerged.
- The local pre-push debt entry for this completed Phase A was transient and is not carried into treatment; preexisting debt entries remain unchanged.

- Before paid runs, AC7 clarified an impossible combination: file-only hook cannot observe an uncalled hanging CLI. Picked file-only freshness hints, bounded runtime/no invocation; CLI timeout and Grep fallback handle liveness. Go-rule bytes unchanged; 9 surfaces/blockers unchanged.

- Slice5 targeted contract green (3 top-level checks); affected run3444passed/1failed across33files: stale tests/test-hooks-json.sh exact three-event expectation. Required integration repair updates it for planned PreToolUse; treatment manifest patch bump to1.8.11 is parent-owned release metadata. No feature-agent surface expansion.

- Codex probe: codex-cli0.166.0; https://learn.chatgpt.com/docs/hooks explicitly documents PreToolUse matcher groups. Native Bash matcher is documented; adapter must normalize native search calls rather than assume Codex has Claude Grep/Glob tool names. No user config changes or model calls.

## Treatment implementation handover

- Slices5–7 complete; no treatment PR or merge. Parent source review repaired unsupported Codex hook retirement; public CLI tests confirmed red then green.
- Affected treatment run:55files,5331passed,0failed/xfail/skipped; `/tmp/code-graph-batch-6-7-affected-final.log`.
- Both source6/7 checks were clean per commit. Build handover graph refresh has no existing graph here and is skipped.
- Frozen armA checkout prepared at `/tmp/harbor-workflow` on code-graph/harbor, exact baselinec7360e4; no treatment source in that checkout.

- Treatment runtime excerpts received an independent partial review with no findings; full skill prose/tests/installer execution were not cleared by that review. A full post-verdict quality/full-suite/Linux-CI gate remains mandatory before any treatment merge.

- No-go off-ramp note: the copied-banner pin transport is an independent hygiene correction. Preserve that transport separately from optional hint registration if the results branch is later used.
