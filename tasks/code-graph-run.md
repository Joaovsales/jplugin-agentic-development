# Code-graph adoption run ledger

State: SMOKE
Feature: https://github.com/Joaovsales/jplugin-agentic-development/issues/401
Spec: specs/code-graph-adoption.md
Base: 317a71717c34226891c3e3b019b83bebc591449d
Planning commit: bd44e96
Branch: code-graph/treatment

## Budget

- Total ceiling: $320
- Per-run ceiling: $4
- Cumulative evaluation spend: $0.14927200000000002
- Paid runs: 1 charged attempts; pending reservation: $0; protocol commit: f1f4df8715029e380c8b4e382a4547152f4082df

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
| 8 | preregistration ready; smoke next | 32 checks and full unpaid integration pass; every core module exceeds 80% statement coverage; AC8 remains unfinished |
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

### Runtime prerequisite receipt — 2026-11-15T20:42:00.960619+00:00

Canonical prerequisite-only runtime guard exited 2. The executable is `/home/joaosouto/.local/bin/graphify` (launcher `/usr/bin/python3`); filesystem distribution metadata records `graphifyy 0.4.23`, while the verified baseline installer pin is `0.9.109`. `pipx` is available at `/usr/bin/pipx`. Exact stdout/stderr and read-only CLI/distribution evidence: `tasks/eval-results/code-graph/preflight-2026-11-15.json`. This is a human-only machine prerequisite, not a measured eval outcome or a no-go verdict. Slice 8 remains unfinished (AC4/AC8); slice 9 blocked. `paid_runs: []`, spend $0; no protocol, paid run, verdict, or treatment merge.

Human command (prepared, not executed):

```bash
cd /tmp/harbor-setup-hddf8lis && bash /tmp/harbor-workflow/install.sh
```

A person must run it in a terminal with pipx on PATH and CI unset, and accept the graphify y/N offer. The setup directory is fresh and empty; neither experiment checkout is the installer working directory. Resume by rerunning the canonical runtime guard; after it passes, establish the exact model id and commit the complete protocol before any paid run.

### Runtime recovery and runner budget receipt — 2026-11-15T22:24:01.014016+00:00

The person accepted the pinned graphify install offer in the existing neutral
installer session. Installer exited 0; graphifyy 0.9.109 is now the pipx CLI, and
`python3 evals/code-graph/fixture_gen.py --check-runtime` exited 0. The
installer's git-hook wiring warning applies to the neutral setup directory.
Read-only runtime/model/native-runner provenance is
`tasks/eval-results/code-graph/preflight-after-install-2026-11-15.json`.

Claude Code 2.1.325 is configured with alias `opus`; its native default and this
workspace's existing Claude transcript support exact ID `claude-opus-5-5`. No
new model call was used to establish this. The unregistered protocol draft is
`tasks/eval-results/code-graph/protocol-draft-2026-11-15.md`; official `protocol.md`
has not been written or committed.

The inspected native eval child argv builder forwards no `--max-budget-usd`.
`--max-cost-usd` gates the next launch and explicitly allows an in-flight run to
exceed its threshold. D7 requires $4 per run, so no paid run can start through
that recipe. This is a runner prerequisite failure, not a measured no-go.
A supported runner that actually enforces the settled ceiling must be proven
before registration. Parent tool discovery found no Workflow execution tool in
`ALL_TOOLS`, so the documented fallback is not verified in this session; this
does not establish that every alternative runner is impossible. No custom proxy
or unapproved surface expansion was added.

## Not finished

- AC4: register and commit an executable protocol before any paid run.
- AC8: run fixed arms/seeds/N, retain transcripts and costs, and obtain the
  six-rule verdict. Slice 9 remains blocked.
- Paid runs: none. Cumulative evaluation spend: $0.

## Budget unblock in progress

The user requested "Unblock the eval". Resume work is preparing a per-request
localhost admission gateway, preserving the native eval runner and the settled
$4/$320 ceilings. Offline mock requests prove `ANTHROPIC_BASE_URL` routing;
no paid model endpoint was reachable during the transport probe. Gateway unit
checks and independent source review are in progress. Native Bash grants also
need a task-local relay because this host has no `socat`; no global package is
being installed. Operational code and receipts stay under
`tasks/eval-results/code-graph/`.

The short run-root layout outside `/tmp` now passes native Bash and graphify
execution with the native sandbox still enabled. The task-local relay covers
only the native bridge's two exact modes. The canonical free token-count
endpoint accepted the existing OAuth credential and exact model (HTTP 200);
its receipt contains no credential values. Gateway regressions cover unknown
billable usage and the captured native request shape.

Registration remains blocked until integrated gateway/credential transport,
candidate path blinding and fixture graph freshness are verified. No official
`protocol.md`, paid run, verdict, treatment PR or merge exists. Spend remains $0.

Native OAuth bearer transport is proven offline. The native plugin-eval runner
exposes `claude-eval` in API-visible candidate paths, so the spec-permitted direct
CLI fallback is being integrated with neutral paths and the same enabled native
Bash sandbox. Its fixture repository is initialized before graph construction.
The admission gateway passed independent review after usage-tier and SSE-order
repairs; its guarantee uses the explicit conservative tokenization/structural
bound and pinned normal-price union documented in `admission-gateway.md`.
The final fallback mock integration must pass before protocol registration.

## Preregistration readiness — 2026-11-16

- Final unpaid direct integration passes native OAuth FD transport, Bash graph
  queries, app reads, all privacy probes, deterministic grading and unchanged
  transcript arrangement. No real model endpoint was reachable in that probe.
- All 32 operational checks pass. Statement coverage is 85.63% overall, with
  gateway 88.06%, launcher 82.70% and relay 89.83%, without exclusions. Evidence:
  `tasks/eval-results/code-graph/operational-coverage-2026-11-16.json`.
- Independent scoped code review is GO under the documented admission
  assumptions. The real-Git AC4 tests close staged-index acceptance and protocol
  mutation gaps; every attempt and restart checks the frozen commit identity.
- The finalized protocol SHA256 is
  `eceb8b458bf7b0464d0b523de8e87eec61f621151818aa29c1b4881932798dfd`.
  The six-rule go text matches the spec verbatim. The manifest contains exactly
  90 fixed slots and verified immutable sources/runtime hashes.
- This readiness record, protocol, manifest and operational code are committed
  together before any paid request. Spend is still $0 at registration.
- Live execution control: `tasks/eval-results/code-graph/job-control.json`;
  controller state: `tasks/eval-results/code-graph/execution-state.json`;
  retained progress log: `/tmp/code-graph-paid-2026-11-16.log`. Check the recorded
  process/session before starting another runner. The shared suite lock covers
  the paid batch, so no local full suite runs alongside an arm.

- Run receipt: {"id": "A/invoice-rounding/1", "arm": "A", "case": "invoice-rounding", "repetition": 1, "seed": 101, "kind": "localization", "generation": 0, "attempt": 1, "attempt_id": "A/invoice-rounding/1/0/1", "protocol_commit": "f1f4df8715029e380c8b4e382a4547152f4082df", "source_sha": "c7360e41fc0c466764b0bb4e32df6dd35d279b5b", "artifact_root": "/home/joaosouto/hr-5rjsygzg/round", "reserved_usd": "4", "reserved_at": "2026-11-16T02:50:43.008724+00:00"}

- Run receipt: {"score": 0.0, "passed": false, "turns": 2, "costUsd": 0.14927200000000002, "costSource": "native_cli", "judgeCostUsd": 0, "startedAt": "2026-11-16T02:50:43.118919+00:00", "durationSeconds": 2.104, "tracePath": "/home/joaosouto/hr-5rjsygzg/round/out/trace.jsonl", "graders": [{"name": "outcome", "passed": false, "weight": 1.0}], "status": "errored", "budgetAccountedUsd": "1.660241", "admissionBlocked": true, "billingBreach": false, "gatewayAccountedUsd": "1.660241", "exitCode": 1, "finishedAt": "2026-11-16T02:50:46.645291+00:00", "kind": "localization", "seed": 101, "id": "A/invoice-rounding/1", "arm": "A", "case": "invoice-rounding", "repetition": 1, "generation": 0, "attempt": 1, "attempt_id": "A/invoice-rounding/1/0/1", "protocol_commit": "f1f4df8715029e380c8b4e382a4547152f4082df", "source_sha": "c7360e41fc0c466764b0bb4e32df6dd35d279b5b", "artifact_root": "/home/joaosouto/hr-5rjsygzg/round"}

## First paid smoke — usage-format investigation

The registered batch stopped after A/invoice-rounding/1/0/1. Native nominal
spend is $0.149272; the unchanged conservative reservation retains $1.660241.
No selected run or second paid attempt exists. The gateway reported
`inconsistent_usage` and blocked the next request. Evidence root:
`/home/joaosouto/hr-5rjsygzg/round`; audit `out/admission.jsonl`, native output
`out/trace.jsonl`, and the controller state retain the failure.

The first paid request freezes protocol commit
`f1f4df8715029e380c8b4e382a4547152f4082df` and SHA256
`eceb8b458bf7b0464d0b523de8e87eec61f621151818aa29c1b4881932798dfd`.
Those bytes and the initial manifest remain unchanged. A read-only `/debug`
investigation is distinguishing normal delta-counter normalization from a real
billing/stream assumption breach. Contract review precedes any implementation
repair or same-slot retry. The previous process has exited; do not start a
second batch while this investigation is unresolved.

## Audited operational compatibility recovery

[AMBIGUITY] The frozen protocol names versioned revision manifests but does not explicitly name operational compatibility repairs | options: A) permit a separately audited operational-only revision under the existing debug-and-retry rule B) treat every operational repair as a forbidden protocol change | picked: A | reason: the spec authorizes step repair and same-seed retry while the frozen protocol preserves initial registration and treatment payloads.

- Pinned native Jwe supports nullable/zero input/cache delta placeholders; the
  old gateway rejected legitimate variants. Controlled offline reproduction
  establishes that incompatibility, not the unique trigger of the lost raw SSE.
- Independent parser and guarded-migration reviews are GO. All 43 operational
  checks pass; current aggregate statement coverage is 86.25%. Exact proofs are
  `usage-compatibility-proof.json`, `controller-usage-compatibility-proof.json`
  and `compatibility-coverage-2026-11-16.json` in the results directory.
- Applied one guarded recovery with a durable state snapshot and append-only
  apply journal. Original protocol/manifest/attempt and all charges are unchanged.
  The prior state is `execution-state-before-usage-compat-1.json`; the journal is
  `usage-compatibility-migration-applied.jsonl`. Only the diagnosed halt was cleared.
- Active manifest: `run-manifest-usage-compat-1.json`, SHA256
  `f91ff5d287569ab8c6cb8594d6c55f01ce9c2bbeaa3c39e39f557af01150c23a`.
  Only the gateway/controller operational hashes differ; relay, model, cohort,
  seeds, order, payload sources, budgets and measurement rules are unchanged.
- Next authorized planned attempt: `A/invoice-rounding/1/0/2`. The failed first
  attempt and its $1.660241 accounted amount remain in the controller. Future
  attempt receipts carry their active manifest hash. No third retry is authorized.
- Retained retry log: `/tmp/code-graph-paid-compat-1-2026-11-16.log`. Check
  `job-control.json` before launching any process. This repair and its exact
  manifest are committed before another paid request.
