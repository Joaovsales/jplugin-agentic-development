# Code-graph adoption run ledger

State: HARNESS
Feature: https://github.com/Joaovsales/jplugin-agentic-development/issues/401
Spec: specs/code-graph-adoption.md
Base: 317a71717c34226891c3e3b019b83bebc591449d
Planning commit: bd44e96
Branch: Joaovsales/code-graph

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
| 5 | pending | Treatment; starts after PR 1 merge |
| 6 | pending | Blocked by 5 |
| 7 | pending | Blocked by 5 |
| 8 | pending | Blocked by 4, 6, 7 |
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
