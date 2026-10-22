---
implementation_paths:
  - AGENTS.md
  - README.md
  - PI_SETUP.md
  - .claude/AGENTS.md
  - .claude-plugin/plugin.json
  - tasks/concepts.md
  - tasks/backlog.md
  - .agents/skills/slice/SKILL.md
  - .agents/skills/slice/references/plan-block.md
  - .agents/skills/slice/references/build-prompt.md
  - .agents/skills/slice/scripts/slice.py
  - .agents/skills/build/SKILL.md
  - .agents/skills/build/references/**
  - .agents/skills/tdd/SKILL.md
  - .agents/skills/debug/SKILL.md
  - .agents/skills/plan/SKILL.md
  - .agents/skills/yolo/SKILL.md
  - .agents/skills/make-it-simpler/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/system-design-planning/templates/architecture-spec-template.md
  - .agents/skills/task-registry/SKILL.md
  - .agents/skills/task-registry/scripts/registry/upsert.py
  - .agents/skills/task-registry/lanes/*.md
  - .agents/skills/wrap-up-session/references/closure-actions.md
  - .agents/skills/wrap-up-session/references/routines.md
  - .agents/skills/wrap-up-session/references/routine-prompts/*.md
  - .agents/skills/sync/SKILL.md
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/quality-gate/scripts/receipt.py
  - .agents/references/finding-model.md
  - .agents/references/model-routing.md
  - .agents/references/review-dispatch-contract.md
  - .agents/agents/planner.md
  - .agents/agents/test-engineer.md
  - .agents/agents/software-design-expert-review.md
  - .claude/agents/planner.md
  - .claude/agents/test-engineer.md
  - .claude/agents/software-design-expert-review.md
  - config/agent-policy.toml
  - tests/test-slice.sh
  - tests/fixtures/slice/**
  - tests/test-task-registry.sh
  - tests/test-tdd-retirement.sh
  - tests/test-install-sh.sh
  - tests/test-sweep-routines.sh
  - tests/test-doc-conventions.sh
  - tests/test-skill-invocation-chain.sh
  - tests/test-agents.sh
  - tests/test-model-tiers.sh
  - tests/test-quality-receipt.sh
  - tests/test-design-stack-*.sh
  - tests/fixtures/build-eval/**
---

# Spec: APOSD-first build

> Origin: "prompt" — the APOSD vs Clean Code review of this harness · Designed 2026-10-19 · Review status: **draft** · critic: 25 findings, 25 applied, 0 declined
> Visual: specs/aposd-first-build.plan.html

## Summary

`/build` runs every slice through one loop: a sub-agent per slice, each running
red-green-refactor through one `/tdd` skill that `/build` and `/debug` both call.
Tracking is one issue per feature: no per-slice filing, no task ids on slice
rows and no `TDD:` rows, and `/build` implements nothing itself, so every slice
is dispatched to a sub-agent. A spec may carry an optional § Interfaces section
naming each module whose interface the change creates or reshapes, and
`/quality-gate` Phase 5 dispatches a `test-engineer` Review job that checks a
slice's tests against its acceptance criteria, its edge cases and its interface.
The decision the reviewer must not miss is that `/slice` no longer files:
`/build` pre-flight makes the one feature upsert.

## Problem

Today the test is the unit of work. `/slice` writes one `[ ] TDD:` row per test,
and `/build` turns each row into failing test, minimal code, refactor, so the
module's interface is whatever the last green test needed. A plan also carries
per-slice tracker issues, minted task ids and a per-slice claim the registry
cannot perform (`build/SKILL.md:176`, `:284-287`). Out of scope: the routines'
label-based claims (`routines.py:56-74`), `/sweep`, `/tidy` and the registry's
`select`, `claim`, `closes` and `escalate` operations, which keep working
unchanged.

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Tracker writes per feature | at most one registry write per feature, made by `/build` pre-flight, and only when the plan's feature row has no provider link | user | `tests/test-doc-conventions.sh`: `build/SKILL.md` names one `upsert`; `slice/SKILL.md` has no `--file` mode |
| No new `TDD:` rows | `/slice`, `/debug`, the routine prompts, the lanes and the `planner` persona never write a `[ ] TDD:` row | user | `tests/test-slice.sh` asserts a fresh block holds none; `tests/test-doc-conventions.sh` and `tests/test-sweep-routines.sh` grep the writers |
| One home for the TDD rules | red-green-refactor and Prove-It are defined only in `.agents/skills/tdd/SKILL.md`; no file names the "or at minimum" commit escape | user | `tests/test-tdd-retirement.sh`, rewritten as an invariant test |
| In-flight plans keep working | an existing `## Plan:` block with task ids and `[ ] TDD:` rows still validates, readies, builds through `/tdd` and closes its per-slice issues | inferred | `tests/test-slice.sh` legacy fixtures; `tests/test-doc-conventions.sh` pins the legacy closing path in `closure-actions.md` |
| `/build` gets thinner | `build/SKILL.md` is at most 600 lines | user | a line-budget assertion in `tests/test-doc-conventions.sh` |
| The orchestrator implements nothing | every slice, a lone ready slice included, is dispatched to a sub-agent; on a harness with no sub-agents `/build` runs inline and says so in one line | user | `tests/test-doc-conventions.sh`: `build/SKILL.md` has no "Main context directly" row and one dispatch rule for every session |
| Agent trees stay identical | `.agents/agents/` and `.claude/agents/` copies of every changed persona stay byte-identical apart from the allowed `model:` line | issue | `tests/test-agents.sh` parity |
| Payload version | `.claude-plugin/plugin.json` bumps its minor version in the same PR (#221) | issue | `tests/test-plugin-manifest.sh` |
| `AGENTS.md` budget | `AGENTS.md` stays within its byte budget | issue | `tests/test-instruction-budget.sh` |
| Rollout and rollback | `/sync` carries the change downstream; rollback is a revert of the PR with no data migration, because legacy plan blocks stay readable | inferred | the slice-14 eval runs before the PR merges and states its keep-or-revert result |

## System design

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| Spec `specs/<feature>.md` | acceptance criteria, edge cases, § Interfaces, § Build Order (slices, surfaces, blockers) | — |
| `tasks/todo.md` plan block | the feature row or `> Issue:` link, each slice's done state (its header checkbox), and under each slice heading its `> Handover:` line | the spec path |
| `slice.py` | the ready set and the surface check, all derived and never stored | the spec, the plan block, git |
| `/tdd` | the red-green-refactor and Prove-It rules | the criteria it is handed |
| `/build` | orchestration: pre-flight, one dispatch per slice, slice close, central verification, Phases 1.5-6; it writes no implementation itself | `slice.py` output, the plan block |
| `test-engineer` | its test-adequacy findings (Review job) | the diff, the spec and the test files |
| Tracker, through `/task-registry` | the one feature issue | — |

### Interaction

```flow
caption: one slice from ready to closed, and /debug
build -> slice.py : (1) ready
build -> implementer : (2) one dispatch per slice, worktree-isolated when run in parallel
implementer -> tdd (new) : (3) red-green-refactor per acceptance criterion of the slice
build -> slice.py : (4) check the surface against the slice base
debug (changed) -> tdd (new) : (5) Prove-It per Fix row, reproduction first
```

### Failure unit

`slice.py` failing stops every `/build` run. `/tdd` failing to load stops slice
dispatch and `/debug`'s fix step. The feature-issue upsert failing or going
`local-pending` leaves the feature row unlinked and the build continues;
`/wrap-up-session` reports the missing link.

## Interfaces

<!-- The section this spec adds to /plan's and the architecture template. One
     entry per module whose interface the change creates or reshapes. -->

### `slice.py validate` and `slice.py ready`

- **Path:** `.agents/skills/slice/scripts/slice.py`
- **Hides:** how a spec's § Build Order, its § Interfaces and the plan block are cross-checked, and how a slice's done state is read from a new or a legacy block.
- **Interface:** `slice.py validate --spec <spec> [--index tasks/todo.md]` refuses, with `<path>:<line>: <reason>`, a block whose slice count or names disagree with § Build Order, and a block with two feature links. `slice.py ready --index tasks/todo.md --spec <spec>` prints `ready: <n> <name>` then `  surface: <globs>` per ready slice.
- **Alternative considered:** deriving a per-slice mode from § Interfaces `Path:` against the Surface. Not built (D23).
- **Depth:** one command answers "what can start" without the caller reading the plan grammar.


### `/tdd`

- **Path:** `.agents/skills/tdd/SKILL.md`
- **Hides:** the red-green-refactor loop, the Prove-It pattern for bugs, the anti-pattern reference and the rationalization table.
- **Interface:** called with a list of criteria (an AC id, or a bug's expected behaviour) and a surface; returns when every criterion has a test that failed first and now passes, or stops naming the criterion it could not make fail.
- **Alternative considered:** keep the rules in `/build` § TDD Discipline. Rejected: `/debug` and the lanes then restate them, the duplication that made the old `/tdd` drift.
- **Depth:** callers name what must be true; the loop, the order and the evidence rules are internal.

### `test-engineer`

- **Path:** `.agents/agents/test-engineer.md`
- **Hides:** how scenarios are enumerated from criteria, edge cases, contracts and interface comments.
- **Interface:** one job, **Review** (Reviewer tier, model passed per dispatch). It receives the diff, the spec's path with its acceptance criteria, the test files, the deferral list and the scope boundary, and emits four-axis findings of three kinds: an AC with no test, an edge case neither tested nor defined away, a test that reaches past the interface. It is read-only.
- **Alternative considered:** a second persona that writes the tests. Not built (D23).
- **Depth:** one persona, one entry point, one scenario model.


## Component contracts

### Plan block (the `tasks/todo.md` contract `/slice` writes and `slice.py` reads)

```
## Plan: <feature>
> Spec: specs/<feature>.md
> Issue: https://github.com/<owner>/<repo>/issues/<N>
- [ ] <feature> <!-- task-id: plan.<spec-id> -->

### Slice 1/<N> — <name>
- [ ] <name> — <delivers>
```

| Aspect | Contract |
|--------|----------|
| Inputs | either a `> Issue:` line, written when `--issue` is given or the spec's `> Origin:` names an issue, or one feature row with the id `/slice` mints by a single dry-run `upsert --derive-id plan --spec <spec>`; never both. Then one `### Slice n/N — <name>` heading per § Build Order row, each with one header row carrying no task id and no `(blocked-by:)`; blockers live only in § Build Order |
| Outcomes | header `[ ]` open, `[x]` done; under a closed heading `/build` writes `> Handover:` |
| Raises | `slice.py validate` refuses, with `<path>:<line>: <reason>`, a block whose slice count or names disagree with § Build Order, or that holds two `> Issue:` lines, two feature rows, or both |
| Idempotency | `/slice` re-run on an unchanged spec rewrites the same block; it never overwrites a block with a `[x]` header and stops naming it |
| Versioning | a block whose slice header rows carry task ids is **legacy**: read as today, built through `/tdd`, its `TDD:` rows run through it, and its per-row issues are each closed by `/wrap-up-session`. No new block is written in that form |

### `/build` pre-flight, feature issue

```
python3 .agents/skills/task-registry/scripts/task-registry.py upsert <id> --spec specs/<feature>.md --title "<feature>" --apply --approve
```

| Aspect | Contract |
|--------|----------|
| Inputs | runs only when the plan block holds a feature row with no provider link; `--approve` is passed when the build prompt authorized the build, omitted by `/yolo` and unattended lanes |
| Outcomes | `created` or `updated` with a link: the registry refreshes the feature row in place (`upsert.py` `_sync_index`, which replaces an existing row and appends none). `local-pending`: the row stays unlinked, `/build` prints `feature issue pending: <reason>` and continues. Failure: `/build` prints `feature issue not filed: <reason>` and continues |
| Idempotency | `/slice` derives the id once (`--derive-id plan --spec`); pre-flight upserts the `<id>` that `slice.py link` prints, so a re-run refreshes the same row and issue |
| Versioning | n/a, internal |

### `/debug` fix block

```
## Fix: #<N> — <title>
- [ ] <criterion the fix must make true>
```

| Aspect | Contract |
|--------|----------|
| Inputs | one row per criterion, plain text, no `TDD:` prefix |
| Outcomes | `/debug` itself runs the rows through `/tdd` with Prove-It and ticks each row when its test passes; `/build` is not involved |
| Versioning | an open `## Fix:` block with `[ ] TDD:` rows still runs the same way |

## Data models

### Entities

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| slice header row | `- [ ] <name> — <delivers>` | exactly one per `### Slice` heading | `slice.py validate` |
| feature link | `> Issue: <url>` or one feature row | exactly one of the two per new block | `slice.py validate` |
| § Interfaces entry | heading plus `Path:`, `Hides:`, `Interface:`, `Alternative considered:`, `Depth:` | every entry has a `Path:` (guidance; withdrawn as a check, D23) | no tool checks it |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| header `[x]` with no `> Handover:` | the existing forbidden-state rule (`build/SKILL.md:323-326`), unchanged |
| a new plan block holding `TDD:` rows | `/slice` has no code path that writes one; `tests/test-slice.sh` pins it |
| two feature links in one block | `slice.py validate` |

### Transitions — a slice

| From | To | Trigger |
|------|----|---------|
| open | done | every criterion passes through `/tdd`, `check` exits 0 or 1, the handover is written and the header is `[x]` |
| done | open | never; a change request edits the spec and re-runs `/slice` on the open slices |


### Migration and compatibility

No migration. Legacy blocks keep their readers: the `TDD:` row patterns in
`slice.py` (`OPEN_TDD_ROW_RE`, `slice.py:62`, and `_tdd_surface_problems`) and
the registry index's older backticked form (`index.py:54-56`), until a later
tidy removes them once no `tasks/todo.md` in this repo holds one. A new block's
header rows without ids are already accepted by the index (`index.py:195`), so a
downstream project still on the old `/build` reads them, and `slice.py ready`
keeps its one index-backed path for both forms.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|----|------|------------|--------|------------|-------|
| R3 | Removing `/slice --file` breaks a caller still naming it | L | M | slice 4 rewrites every caller found: `routines.md`, `/yolo`, `/make-it-simpler`, `task-registry/SKILL.md` | 4 |
| R4 | Re-creating `skills/tdd` collides with the retirement machinery | M | M | `/sync` retires only byte-identical template history (`sync/SKILL.md:494-500`); slice 6 updates `sync/SKILL.md:391` and `:557` and moves `tests/test-install-sh.sh` to another retired name | 6 |
| R5 | Every quality receipt goes stale, because the policy hash gains the `test-engineer` persona | H | L | expected and one-off; the next `/quality-gate` mints a fresh receipt | 12 |
| R6 | This spec is itself built by the current `/build`, which files per slice and reads `TDD:` rows | H | L | its plan block is legacy: built through `/tdd` throughout, per-row issues closed by the legacy path slice 4 keeps | 1, 4 |

## Build Order

Sizing: 14 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 3, 4 and 7 (systems: each rewrites one rule across every skill that states it, and splitting leaves a slice where one skill names a step another no longer performs); slice 7 and slice 10 (files: the `.agents/agents/` and `.claude/agents/` copies change together or the parity test goes red, and a persona registration touches every list of agents at once); slice 13 (systems: the persona copies and the `finding-model.md` gate rule change with the tests that pin them).

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Plan block of slice headers | `/slice` writes slice headers with no task id, no blocker marker and no `TDD:` child, plus one `> Issue:` line or one feature row; `slice.py` validates and readies new and legacy blocks | `.agents/skills/slice/SKILL.md`, `.agents/skills/slice/references/plan-block.md`, `.agents/skills/slice/scripts/slice.py`, `tests/test-slice.sh`, `tests/fixtures/slice/**`, `tests/test-doc-conventions.sh`, `.claude-plugin/plugin.json` | — | 1, 2 | `bash tests/test-slice.sh && bash tests/test-doc-conventions.sh` | 7 files · 1 system · 2 ACs |
| 2 | Interfaces section and mode | both spec templates carry `## Interfaces`; no `validate` rule on § Interfaces and no `mode=` output (both withdrawn, D23) | `.agents/skills/slice/scripts/slice.py`, `tests/test-slice.sh`, `tests/fixtures/slice/**`, `.agents/skills/plan/SKILL.md`, `.agents/skills/system-design-planning/templates/architecture-spec-template.md`, `tests/test-doc-conventions.sh` | 1 | 3, 9 | `bash tests/test-slice.sh && bash tests/test-doc-conventions.sh` | 6 files · 2 systems · 2 ACs |
| 3 | Feature issue in build | `/slice --file` is gone; `/build` pre-flight upserts the feature row once; every slice is dispatched to a sub-agent; the build prompt and the delegation prompt name no per-slice filing, rows or claims | `.agents/skills/slice/SKILL.md`, `.agents/skills/slice/references/build-prompt.md`, `.agents/skills/build/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md`, `AGENTS.md`, `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh` | 2 | 4 | `bash tests/test-doc-conventions.sh && bash tests/test-skill-invocation-chain.sh && bash tests/test-instruction-budget.sh` | 7 files · 4 systems · 1 AC |
| 4 | Callers of the old filing | routines use their claimed issue; wrap-up closes one feature issue and keeps the legacy per-row path; `/yolo`, `/make-it-simpler` and the registry skill name no `/slice --file` | `.agents/skills/wrap-up-session/references/routines.md`, `.agents/skills/wrap-up-session/references/closure-actions.md`, `.agents/skills/yolo/SKILL.md`, `.agents/skills/make-it-simpler/SKILL.md`, `.agents/skills/task-registry/SKILL.md`, `tests/test-doc-conventions.sh` | 3 | 5 | `bash tests/test-doc-conventions.sh && bash tests/test-instruction-budget.sh`; `grep -rn -- "slice.*--file" .agents` is empty | 6 files · 4 systems · 1 AC |
| 5 | Remove orphaned parent links | `upsert --parent` and `_seeded_from_row` are deleted with their tests and backlog items; a pre-written feature row refreshes in place | `.agents/skills/task-registry/scripts/registry/upsert.py`, `.agents/skills/task-registry/SKILL.md`, `tests/test-task-registry.sh`, `tasks/backlog.md` | 4 | 6 | `bash tests/test-task-registry.sh` | 4 files · 1 system · 1 AC |
| 6 | One home for TDD | `/tdd` holds red-green-refactor and Prove-It; `/build` calls it and loses § TDD Discipline; the retirement test pins the invariant | `.agents/skills/tdd/SKILL.md`, `.agents/skills/build/SKILL.md`, `.agents/skills/sync/SKILL.md`, `README.md`, `tests/test-tdd-retirement.sh`, `tests/test-install-sh.sh`, `tests/test-doc-conventions.sh` | 4 | 7 | `bash tests/test-tdd-retirement.sh && bash tests/test-install-sh.sh && bash tests/test-doc-conventions.sh` | 7 files · 3 systems · 1 AC |
| 7 | Writers stop emitting TDD rows | `/debug` writes plain criterion rows and runs them through `/tdd`; the lanes, routine prompts and `planner` persona name no `TDD:` row | `.agents/skills/debug/SKILL.md`, `.agents/skills/task-registry/lanes/*.md`, `.agents/skills/wrap-up-session/references/routine-prompts/*.md`, `.agents/agents/planner.md`, `.claude/agents/planner.md`, `tests/test-agents.sh`, `tests/test-sweep-routines.sh`, `tests/test-tdd-retirement.sh`, `tests/test-doc-conventions.sh` | 6 | 8 | `bash tests/test-tdd-retirement.sh && bash tests/test-sweep-routines.sh && bash tests/test-agents.sh && bash tests/test-doc-conventions.sh` | 9 files · 4 systems · 1 AC |
| 8 | Thinner build | the design-stack gates and harness dispatch notes move to `build/references/`; a budget pins `build/SKILL.md` at 600 lines or fewer | `.agents/skills/build/SKILL.md`, `.agents/skills/build/references/**`, `tests/test-design-stack-*.sh`, `tests/test-doc-conventions.sh` | 7 | 12 | `bash tests/test-doc-conventions.sh && bash tests/test-model-tiers.sh`, then each `tests/test-design-stack-*.sh` | 4 files · 1 system · 1 AC |
| 9 | Test freeze check | withdrawn (D23): `slice.py check` stays the surface check | `.agents/skills/slice/scripts/slice.py`, `tests/test-slice.sh`, `tests/fixtures/slice/**` | 2 | 10 | `bash tests/test-slice.sh` | 3 files · 1 system · 1 AC |
| 10 | Test-engineer persona | the persona exists in both trees with its Review job and is registered everywhere agents are listed | `.agents/agents/test-engineer.md`, `.claude/agents/test-engineer.md`, `.agents/references/model-routing.md`, `config/agent-policy.toml`, `README.md`, `PI_SETUP.md`, `.claude/AGENTS.md`, `tests/test-agents.sh`, `tests/test-model-tiers.sh` | 8 | 13 | `bash tests/test-agents.sh && bash tests/test-model-tiers.sh` | 9 files · 3 systems · 1 AC |
| 11 | Design-mode loop | withdrawn (D23): `/build` runs the one tdd loop for every slice | `.agents/skills/build/SKILL.md`, `.agents/skills/build/references/**`, `tests/test-doc-conventions.sh`, `tasks/concepts.md`, `AGENTS.md` | 8, 9, 10 | 11 | `bash tests/test-doc-conventions.sh && bash tests/test-instruction-budget.sh` | 5 files · 2 systems · 1 AC |
| 12 | Test adequacy review | `/quality-gate` Phase 5 dispatches the `test-engineer` Review job; findings count toward HOLD; the persona joins the policy hash | `.agents/skills/quality-gate/SKILL.md`, `.agents/skills/quality-gate/scripts/receipt.py`, `.agents/references/review-dispatch-contract.md`, `tests/test-quality-receipt.sh`, `tests/test-doc-conventions.sh` | 11 | 14 | `bash tests/test-quality-receipt.sh && bash tests/test-doc-conventions.sh` | 5 files · 2 systems · 1 AC |
| 13 | Gate fixes | deslop keeps decision comments and flags contradicting ones; the parameter rule names shallow interfaces; boundary-moving fixes never auto-apply; R2 and R10 follow the book | `.agents/skills/quality-gate/SKILL.md`, `.agents/references/finding-model.md`, `.agents/agents/software-design-expert-review.md`, `.claude/agents/software-design-expert-review.md`, `AGENTS.md`, `tests/test-agents.sh`, `tests/test-doc-conventions.sh` | 12 | 15, 16 | `bash tests/test-agents.sh && bash tests/test-doc-conventions.sh && bash tests/test-quality-receipt.sh && bash tests/test-instruction-budget.sh` | 7 files · 3 systems · 2 ACs |
| 14 | Build A/B eval | two seeded features with an answer key; a Mode B `/eval` compares master `/build` with the design-mode `/build` and states the keep-or-revert result (`tasks/eval-aposd-first-build.md`) | `tests/fixtures/build-eval/**` | 13 | 17 | manual: `/eval` Mode B, N ≥ 2 per arm, keep-or-revert result and report path in the PR body | 1 file · 1 system · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/aposd-first-build.md`.
Plan: `## Plan: aposd-first-build` in `tasks/todo.md`, 14 slices, ready set <1>.
Files: AGENTS.md, README.md, PI_SETUP.md, .claude/AGENTS.md, .claude-plugin/plugin.json, tasks/concepts.md, tasks/backlog.md, .agents/skills/slice/SKILL.md, .agents/skills/slice/references/plan-block.md, .agents/skills/slice/references/build-prompt.md, .agents/skills/slice/scripts/slice.py, .agents/skills/build/SKILL.md, .agents/skills/build/references/**, .agents/skills/tdd/SKILL.md, .agents/skills/debug/SKILL.md, .agents/skills/plan/SKILL.md, .agents/skills/yolo/SKILL.md, .agents/skills/make-it-simpler/SKILL.md, .agents/skills/system-design-planning/SKILL.md, .agents/skills/system-design-planning/templates/architecture-spec-template.md, .agents/skills/task-registry/SKILL.md, .agents/skills/task-registry/scripts/registry/upsert.py, .agents/skills/task-registry/lanes/*.md, .agents/skills/wrap-up-session/references/closure-actions.md, .agents/skills/wrap-up-session/references/routines.md, .agents/skills/wrap-up-session/references/routine-prompts/*.md, .agents/skills/sync/SKILL.md, .agents/skills/quality-gate/SKILL.md, .agents/skills/quality-gate/scripts/receipt.py, .agents/references/finding-model.md, .agents/references/model-routing.md, .agents/references/review-dispatch-contract.md, .agents/agents/planner.md, .agents/agents/test-engineer.md, .agents/agents/software-design-expert-review.md, .claude/agents/planner.md, .claude/agents/test-engineer.md, .claude/agents/software-design-expert-review.md, config/agent-policy.toml, tests/test-slice.sh, tests/fixtures/slice/**, tests/test-task-registry.sh, tests/test-tdd-retirement.sh, tests/test-install-sh.sh, tests/test-sweep-routines.sh, tests/test-doc-conventions.sh, tests/test-skill-invocation-chain.sh, tests/test-agents.sh, tests/test-model-tiers.sh, tests/test-quality-receipt.sh, tests/test-design-stack-*.sh, tests/fixtures/build-eval/**.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when the plan's feature row has no link. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints:
- D3, D23: no slice mode: no Mode column, no `mode=` output, no freeze check; legacy blocks keep building through the tdd loop.
- D4, D6, D16: one tracker issue per feature, upserted by `/build` pre-flight only for an unlinked feature row; `/slice --file` is deleted, not kept as a one-issue mode.
- D5, D10: no writer emits a new `TDD:` row, and legacy blocks with task ids and `TDD:` rows keep validating, readying, building and closing, this plan block included.
- D22: `/build` implements nothing itself; every slice is dispatched to a sub-agent, a lone ready slice included.
- D12: the skill is named `/tdd`; the retirement test is rewritten as an invariant, and "or at minimum" appears nowhere.
- D15: the `test-engineer` persona lands in slice 10, before the `/quality-gate` Phase 5 that dispatches it.
```

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|----|----------|---------|-------------|------------|--------|
| D1 | Who writes the contract tests | A) a separate dispatch that sees only spec and stubs, B) the implementer | A | the slice is so small a second dispatch costs more than the bug it catches; that is tdd mode's job | settled |
| D2 | Where the TDD rules live | A) an Addy-style `/tdd` called by `/build` and `/debug`, B) `/build` § TDD Discipline | A | `/build` stops calling `/tdd` structurally, which is how the old one drifted | settled |
| D3 | How mode is chosen | A) derived from § Interfaces `Path:` against Surface, B) a Build Order column | A | a slice reshapes an interface the spec never named; then § Interfaces is incomplete, and the review card catches it | settled |
| D4 | Tracker granularity | A) one issue per feature, B) one per slice | A | several people build slices of one feature in parallel and need per-slice claims | settled |
| D5 | Plan rows | A) slice headers only, B) headers plus `TDD:` rows | A | a slice is too big to hold in one session; sizing prevents that | settled |
| D6 | Feature issue when the spec has none | A) `/slice` writes one feature row, `/build` pre-flight upserts it, B) none, C) planning files it | A | the project disables external task creation; then the upsert reports `local-pending` and the build continues | settled |
| D7 | `/debug` fix block | A) plain criterion rows that `/debug` runs through `/tdd`, B) no block | A | — | settled |
| D8 | Test personas | A) one `test-engineer`, two dispatches at two tiers, B) two personas | A | the two jobs need different tool permissions; both need read and write of test files only | settled |
| D9 | Test freeze | A) a `> Frozen:` plan line, exit 3 on a violation, a `> Test amended:` escape the Review job reads, B) report-only | A | — | settled |
| D10 | Legacy plan blocks | A) keep reading, building through `/tdd` and closing them, remove later, B) migrate now | A | — | settled |
| D11 | Where adequacy review runs | A) `/quality-gate` Phase 5 Tests, B) inside Phase 4 | A | `receipt.py` rejects a Phase 5 reviewer entry; it does not (`receipt.py:218` checks only that `phase` is an int, `:228` requires phases 1-4) | settled |
| D12 | Name of the TDD skill | A) reuse `/tdd`, rewrite the retirement test as an invariant, B) a new name | A | — | settled |
| D13 | Measure before merge | A) a manual `/eval` Mode B slice with a keep-or-revert rule, B) suite only | A | — | settled |
| D14 | Orphaned `--parent` and `_seeded_from_row` | A) delete with their tests, B) keep | A | a caller seeds a row's status or blockers ahead of its task; the feature row is always `[ ]` with no blockers, so `_sync_index` refreshing it in place needs neither | settled |
| D15 | When the persona lands | A) the persona file and registration before the `/build` loop that dispatches it, B) after | A | — the order "design mode, then test engineer" holds for the Review job, which lands in Phase 5 after the loop | settled |
| D16 | Removing `/slice --file` | A) delete the mode; `/build` pre-flight makes the one upsert, B) keep the mode filing one issue | A | a caller outside slice 4's list still names it; slice 4's verify greps the tree for `--file` | settled |
| D17 | Clean Code and SOLID wording in `AGENTS.md` | A) keep the headings, rewrite the parameter rule as "a long parameter list signals a shallow interface; fix the interface, not the call site", name `/quality-gate` Phase 4 in § Quality Gate, B) remove the Clean Code principle | A | the team wants the Clean Code standard gone entirely; that is a separate change | settled |
| D18 | Riskiest unknown first | A) the legacy-compatible plan reader first and the eval last, B) a design-mode spike before any simplification | A | the eval shows design mode loses; slices 1-8 still stand alone, so only slices 9 and 11 are reverted | settled |
| D19 | Parallelism in design mode | A) design-mode slices run one at a time in the main tree, B) one shared worktree per design slice | A | design-mode slices dominate a plan; the eval reports the wall-clock cost | settled |
| D21 | How the writer's independence is held across harnesses | A) enforce timing and prompt inputs, disclose context freshness on `> Frozen:`; Claude Code and Pi dispatch fresh (`Agent`, `pi-subagents` default `context: "fresh"`); Codex discloses `forked` until Q1 shows its spawn starts fresh, B) a detached `codex exec` process for every Codex Write job, C) trust the persona's instructions alone | A | Q1 shows a Codex spawn inherits implementation reasoning; it cannot today, because the orchestrator writes no implementation | settled |
| D22 | Who implements a slice | A) always a dispatched sub-agent, in every session, a lone slice included; tdd mode one dispatch, design mode three, B) today's split: parallel slices dispatch, a lone or serialized slice may run in the main context | A | a slice is so small the dispatch costs more than it saves; sizing keeps slices above that line | settled |
| D20 | Design mode for a module that already exists | A) stubs and red tests cover only new or changed entry points; existing tests cover the rest, B) stub the whole module | A | — | settled |
| D23 | Keep or revert design mode after the AC17 eval | A) revert slices 9 and 11 and what they orphan: the freeze check, the design-mode loop, `ready`'s `mode=` (AC3's validate rule is withdrawn too: nothing reads `Path:`), the `test-engineer` Write job (AC13 keeps the persona with its Review job), Phase 5's freeze-line inputs (AC14 keeps the Review job); B) keep; C) keep behind an opt-in spec flag | A | a larger, interface-heavy feature shows an independent test writer catching what the implementer's tests miss; re-run `tests/fixtures/build-eval/` with such a feature before bringing it back | settled |

## Open questions

None.

## Acceptance Criteria

- AC1: A plan block `/slice` writes holds either a `> Issue:` line (from `--issue` or the spec's `> Origin:`) or one feature row carrying the id of a single dry-run `upsert --derive-id plan --spec`, then one `### Slice n/N — <name>` heading per § Build Order row, each with one header row carrying no task id, no `(blocked-by:)` and no `TDD:` child. `slice/references/plan-block.md` states that grammar.
- AC2: `slice.py validate` and `ready` accept the new block and still accept a legacy block; `ready` reads both through its existing index path; `validate` refuses a block with two feature links. `tests/test-slice.sh` covers new and legacy fixtures.
- AC3: withdrawn (D23); nothing reads § Interfaces `Path:`, so `slice.py validate` does not check it.
- AC4: `/slice` has no `--file` mode. `/build` pre-flight runs one `upsert <id> --spec … --apply`, `<id>` being the one `slice.py link` prints, with `--approve` when the build prompt authorized it, only when the feature row has no link, and continues on `local-pending` or failure with a printed line. The build prompt's first instruction names no `/slice --file`. `/build`'s slice delegation prompt carries the slice's Delivers and acceptance criteria from the spec instead of plan rows, and names no per-slice claim. `/build` dispatches every slice to a sub-agent in every session, a lone ready slice and each slice of a serialized pair included; the Step 1 "Main context directly" row and the separate in-place dispatch rule are gone, and a harness with no sub-agents runs inline and says so in one line.
- AC5: `routines.md` § *Crossing the plan handover* writes the routine's claimed issue as `> Issue:` and files nothing. `closure-actions.md` writes one `Closes #N` for a new block's feature issue and keeps the per-row `Closes #A, closes #B` path for legacy blocks. `/yolo` resumes an open slice header or a legacy `TDD:` row and runs pre-flight without `--approve`. `/make-it-simpler` and `task-registry/SKILL.md` name no `/slice --file`; `grep -rn -- "slice.*--file" .agents` finds nothing.
- AC6: `upsert.py` has no `--parent` flag and no `_seeded_from_row`; their tests are gone; the pending-link items under *From #106* in `tasks/backlog.md` are removed; a pre-written feature row is refreshed in place, not duplicated, by `tests/test-task-registry.sh`.
- AC7: `.agents/skills/tdd/SKILL.md` holds red-green-refactor, Prove-It, the anti-pattern reference and the rationalization table. `build/SKILL.md` has no § TDD Discipline and calls `/tdd` for tdd-mode slices. `tests/test-tdd-retirement.sh` asserts the rules appear only in `tdd/SKILL.md`, that `/build` invokes `/tdd`, and that "or at minimum" appears nowhere. `sync/SKILL.md` no longer cites `tdd` as retired, and `tests/test-install-sh.sh` uses another retired name as its fixture.
- AC8: `/debug` writes `## Fix: #N — <title>` with plain `- [ ] <criterion>` rows and runs them through `/tdd` itself. The lane files, the routine prompts and the `planner` persona (both trees) name no `TDD:` row and say `/debug` runs the fix through `/tdd`. `tests/test-tdd-retirement.sh` asserts `/debug` invokes `/tdd`, and `tests/test-sweep-routines.sh` asserts the plain-row form.
- AC9: `/plan`'s spec template and the architecture template carry an optional `## Interfaces` section with the five fields `Path:`, `Hides:`, `Interface:`, `Alternative considered:`, `Depth:`; the template heading list pinned in `tests/test-doc-conventions.sh` includes it.
- AC10: withdrawn (D23); `slice.py check` stays the surface check, exit 0 or 1.
- AC11: withdrawn (D23); `/build` runs the tdd loop for every slice.
- AC12: `build/SKILL.md` is at most 600 lines, pinned by a budget assertion in `tests/test-doc-conventions.sh`. The design-stack 3D and video gates and the harness dispatch notes live in `build/references/`, the design-stack tests read them there, and the Ceiling-tier sentence `tests/test-model-tiers.sh` pins stays in `build/SKILL.md`.
- AC13: `.agents/agents/test-engineer.md` and its `.claude/agents/` copy exist, byte-identical, with no `model:`, describing the Review job (Reviewer tier, model passed per dispatch). `model-routing.md` § Agents, `config/agent-policy.toml`, the README agent table, `PI_SETUP.md` and `.claude/AGENTS.md` list it; `tests/test-agents.sh` includes it in the four-axis list.
- AC14: `/quality-gate` Phase 5 dispatches the `test-engineer` Review job after the affected tests pass, with the diff, the test files, the spec's acceptance criteria or `no spec — <reason>`, the deferral list and the introduced-only boundary. Its findings are report-only, each unresolved SHOULD-FIX counts toward HOLD, the receipt records a phase-5 reviewer entry, and `receipt.py` POLICY_FILES includes the persona. `tests/test-quality-receipt.sh` stays green.
- AC15: `/quality-gate` Phase 2 keeps interface comments and comments stating a decision or a hidden assumption, and flags a comment that contradicts the code beside it. Phase 1 no longer says "options object"; it says a long parameter list signals a shallow interface. `AGENTS.md` matches D17.
- AC16: `finding-model.md` § *Gates* states that a fix moving a module boundary is never `gated_auto`. `software-design-expert-review.md` (both trees) rates R2 pass-through methods SHOULD-FIX and defines R10 as conjoined methods that cannot be understood apart, as the book does.
- AC17: `tests/fixtures/build-eval/` holds two seeded features with an answer key. A Mode B `/eval` run (N ≥ 2 per arm) compares arm A, master's `/build` on a legacy plan of the same features, with arm B, the design-mode `/build`, on AC coverage, test-freeze violations, `/quality-gate` design findings and cost. The report (`tasks/eval-aposd-first-build.md`) states the rule's result: keep design mode when arm B's AC coverage is at least arm A's, its design findings are fewer, and its cost is at most twice arm A's; otherwise recommend reverting slices 9 and 11. The report's result was revert (D23).

## Implementation Paths

- `.agents/skills/slice/**` — plan-block grammar, build prompt, `slice.py` ready, validate and check
- `.agents/skills/build/SKILL.md`, `.agents/skills/build/references/**` — thin orchestration, the feature upsert, the moved design-stack gates and harness dispatch notes
- `.agents/skills/tdd/SKILL.md` — the one home of red-green-refactor and Prove-It
- `.agents/skills/debug/SKILL.md`, `.agents/skills/task-registry/lanes/*.md`, `.agents/skills/wrap-up-session/references/routine-prompts/*.md`, `.agents/agents/planner.md`, `.claude/agents/planner.md` — writers that stop emitting `TDD:` rows
- `.agents/skills/yolo/SKILL.md`, `.agents/skills/make-it-simpler/SKILL.md`, `.agents/skills/wrap-up-session/references/*.md`, `.agents/skills/task-registry/SKILL.md` — callers of the old per-slice filing and closing
- `.agents/skills/plan/SKILL.md`, `.agents/skills/system-design-planning/**` — § Interfaces in both templates, hand-off text
- `.agents/skills/task-registry/scripts/registry/upsert.py` — `--parent` and `_seeded_from_row` removed
- `.agents/skills/sync/SKILL.md` — the retirement example and the `tdd` mapping
- `.agents/agents/test-engineer.md`, `.claude/agents/test-engineer.md`, `.agents/references/model-routing.md`, `config/agent-policy.toml`, `README.md`, `PI_SETUP.md`, `.claude/AGENTS.md` — the new persona
- `.agents/skills/quality-gate/**`, `.agents/references/finding-model.md`, `.agents/references/review-dispatch-contract.md`, `.agents/agents/software-design-expert-review.md`, `.claude/agents/software-design-expert-review.md` — adequacy review and gate fixes
- `AGENTS.md`, `tasks/concepts.md`, `tasks/backlog.md`, `.claude-plugin/plugin.json` — workflow text, vocabulary, dissolved backlog items, version
- `tests/**` — the pins named in each criterion
- `tests/fixtures/build-eval/**` — seeded features and answer key for the A/B
