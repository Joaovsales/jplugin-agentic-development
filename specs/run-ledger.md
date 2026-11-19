---
implementation_paths:
  - .agents/skills/build/scripts/run_ledger.py
  - .agents/skills/build/references/run-ledger.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/receive-review/SKILL.md
  - tests/test-run-ledger.sh
  - tests/test-doc-conventions.sh
---

# Spec: Run ledger — one durable record per build run

> Origin: #442 · Designed 2026-11-18 · Review status: **unattended improve-lane run, critic lens run inline** (no sub-agent tool in this worker: 0 MUST-FIX, 3 SHOULD-FIX applied, 1 declined as D7)
> Visual: specs/run-ledger.plan.html

## Summary

Every `/build` session, and every rework run after review, writes one JSON
record to `tasks/runs/<run-id>.json`: the spec, the base SHA, the model per
tier, each slice's attempts and three outcomes, tokens and cost, the parent
run it reworks, and the human result of its pull request. `run_ledger.py
stats` recalculates first-pass rate, attempts per merged PR and cost per
merged PR from those files alone. The decision not to miss: the human result
has its own command, `decide`, and `record` has no option that sets it, so no
later run can overwrite a human's merge or close.

## Problem

A build or routine run leaves a PR and a handover, but nothing durable links
its attempts, models, cost and the human outcome, so first-pass rate and cost
per accepted PR cannot be calculated. This change adds the per-run record and
the report over it. Out of scope: reading PR state from GitHub automatically
(the human result is recorded by whoever observes it), and Helix's
`run.json` (`specs/helix-checkpoint-loop.md:262`, not built).

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Totals are derived | `stats` reads only the per-run files; no file stores a running total | issue | `tests/test-run-ledger.sh` § stats: deleting a record changes the report |
| Idempotent by run id | recording the same run twice leaves every `stats` count unchanged and the record file byte-identical | issue | § idempotent |
| A final human decision is final | `merged` and `closed` are never replaced; `record` cannot set `human_result` at all | issue | § human decision |
| Unknown is not zero | missing tokens or cost are stored as the string `unknown` and an aggregate over any unknown value prints `unknown` with a count | issue | § unknown |
| The three outcomes are #441's | slice outcomes reuse `slice_outcome.py`'s values and its `derive()`; a label inconsistent with its results is refused | issue (depends on #441) | § record validation |
| A bad record is loud | an unreadable, wrong-schema or misnamed file makes `stats` exit 1 naming the file; nothing is skipped silently | inferred | § stats refuses a malformed record |
| Rollback | deleting `tasks/runs/` and the Phase 6 call restores the prior behaviour; no other store reads the ledger | inferred | no migration exists |

## System design

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `run_ledger.py` (new) | the record schema `run-ledger/1`, the run-id rule, the human-result transitions, every derived total | `slice_outcome.derive` and its value names |
| `tasks/runs/<run-id>.json` (new) | one run's facts, written only through `run_ledger.py` | — |
| `/build` Phase 6 (changed) | when a build run is recorded and what it passes | the plan block's `> Outcome:` lines, the base SHA |
| `/receive-review` (changed) | recording a rework run and the parent's `changes_requested` | the branch's latest run (`run_ledger.py last`) |
| the person or job that merges or closes the PR | the `merged` or `closed` decision | — |

### Interaction

```flow
caption: who writes a run record and who reads it
build["/build Phase 6"] -> ledger["run_ledger.py (new)"] : (1) record
review["/receive-review"] -> ledger : (2) decide changes_requested + record --parent
merger["merger"] -> ledger : (3) decide merged or closed
ledger -> runs["tasks/runs/*.json (new)"] : (4) atomic write
stats["run_ledger.py stats"] -> runs : (5) read all records
```

| Arrow | Mode | On timeout | On duplicate |
|-------|------|------------|--------------|
| (1) | sync, local file | no network; a crash leaves the previous file or the new one (write to temp, then rename) | same run id rewrites the same file; human fields kept |
| (2) | sync, local file | as (1) | `decide` with the current value is a no-op |
| (3) | sync, local file | as (1) | as (2); a different final value is refused |
| (4) | sync | as (1) | rename is atomic |
| (5) | sync, read-only | n/a | duplicate run ids are impossible: the file name is the run id, and a mismatch is refused |

### Failure unit

A failing `record` call fails only the ledger step of Phase 6: the build's
commits and handovers are already written, and Phase 6 reports the error.

## Component contracts

### run_ledger.py

```text
run_ledger.py record --branch B --base SHA [--run-id ID] [--spec PATH] [--pr N]
                     [--parent RUN_ID] [--model TIER=NAME]... [--slice "<id> attempts=<n> <outcome line>"]...
                     [--tokens N|unknown] [--cost USD|unknown] [--ledger DIR]   -> 0 recorded | 2 usage
run_ledger.py decide --run-id ID --result merged|changes_requested|closed [--ledger DIR]
                                                                               -> 0 recorded/unchanged | 1 refused | 2 usage
run_ledger.py last --branch B [--ledger DIR]                                    -> 0 prints run id | 1 none/error
run_ledger.py stats [--ledger DIR]                                              -> 0 report | 1 malformed record
```

| Aspect | Contract |
|--------|----------|
| Inputs | `--slice` is the slice id, `attempts=<n>` (n ≥ 1), then the `> Outcome:` line verbatim (`agent_result=… verification_result=… slice_result=… <LABEL>`); `--ledger` defaults to `tasks/runs` |
| Outcomes | `record: recorded <run-id>`; `decide: recorded <run-id> <result>` or `decide: unchanged …`; `decide: refused <run-id> — already <final>, a final human decision is never overwritten` (exit 1) |
| Raises | usage errors exit 2 naming the value; a malformed stored record exits 1 naming the file; `decide` on a run id with no record exits 1 (`decide: no run <id>`) |
| Idempotency | key = run id. The default run id is `<branch slug>-<base SHA, 12 chars>`, so re-recording the same build lands on the same file. `last` picks the branch's run with the latest `recorded_at`, ties broken by run id. `record` keeps the stored `recorded_at`, `human_result` and `decisions`; an option left out keeps the stored value |
| Versioning | every record carries `"schema": "run-ledger/1"`; another schema is refused by `stats` and `decide` |

Only the exact `last: no run on branch <branch> in <ledger>` diagnostic means
absence; every other failure stops and reports the caller's ledger step.
Both writers serialize their read/check/modify/atomic-replace transaction
with the same per-run OS lock (Unix `flock`, Windows `msvcrt`, 10-second wait).
Kernel ownership ends on process exit; the local `.lock` file is kept and ignored.
Stored decision history and finite non-negative telemetry are validated on load.

`stats` prints, exit 0:

```text
run-ledger: runs=<n> prs=<n> merged=<n> closed=<n> open=<n>
run-ledger: first_pass_rate=<k>/<decided> (<pct>%)
run-ledger: attempts_per_merged_pr=<x.xx>
run-ledger: cost_per_merged_pr=<usd> | unknown — cost missing on <k> of <n> merged PRs
run-ledger: tokens_per_merged_pr=<n> | unknown — tokens missing on <k> of <n> merged PRs
```

With no decided or no merged PR, the rate and the per-PR values print
`unknown — no merged PRs` (or `no decided PRs`) instead of a number.

```sequence
caption: a rework after review never touches the parent's final decision
participant reviewer
participant receive["/receive-review"]
participant ledger["run_ledger.py"]
reviewer -> receive : changes requested on PR
receive -> ledger : last --branch B
ledger --> receive : parent run id
receive -> ledger : decide parent changes_requested
alt parent already merged or closed
ledger --> receive : refused, exit 1
else parent open or changes_requested
ledger --> receive : recorded
end
receive -> ledger : record --branch B --base HEAD --parent parent
```

## Data models

### Entities

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `schema` | `"run-ledger/1"` | constant | `load_record` |
| `run_id` | string `[A-Za-z0-9][A-Za-z0-9._-]*` | equals the file name stem; a dot-file in the ledger is a write's temp, never a record | `record`, `load_record`, `load_ledger` |
| `branch`, `base_sha` | string, hex ≥ 7 | present | `record` arguments are required |
| `spec`, `pr`, `parent_run_id` | string, int ≥ 1, run id — or `null` | `parent_run_id` ≠ `run_id` | `record` |
| `models` | `{tier: name}` | non-empty strings | `--model` parser |
| `slices` | list of `{id, attempts, agent_result, verification_result, slice_result, label}` | label and slice_result equal `slice_outcome.derive(agent, verification)` | `--slice` parser |
| `tokens` | int ≥ 0 or `"unknown"` | never a stand-in 0 | `--tokens` parser, default `unknown` |
| `cost_usd` | number ≥ 0 or `"unknown"` | never a stand-in 0 | `--cost` parser, default `unknown` |
| `recorded_at` | ISO-8601 UTC | set on first record, kept after | `record` |
| `candidates` | `{slice id: [entry]}`, optional | one entry per candidate with rank, selected, the three outcomes, measurements and reason; `record` keeps it (specs/parallel-candidates.md) | `candidates.py rank` through `add_candidates` only |
| `human_result` | `null`, `changes_requested`, `merged`, `closed` | follows the transition table | `decide` only |
| `decisions` | list of results, append-only | last entry equals `human_result` | `decide` only |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| `human_result` set by a build run | `record` has no human-result option |
| `merged` replaced by another result | `decide` refuses any change from `merged` or `closed` |
| cost or tokens of 0 meaning "not reported" | absent values default to `"unknown"` |
| a stored running total | `stats` derives every number from the records; the schema has no total field |
| two records for one run | the file name is the run id |

### Transitions — `human_result`

| From | To | Trigger |
|------|----|---------|
| `null` | `changes_requested`, `merged`, `closed` | `decide` |
| `changes_requested` | `merged`, `closed` | `decide` |
| `changes_requested` | `changes_requested` | `decide` — unchanged, nothing appended |
| `merged`, `closed` | the same value | `decide` — unchanged |
| `merged`, `closed` | anything else | refused, exit 1 |

### Derived totals

A *PR* is a chain of runs linked by `parent_run_id`, rooted at the run with
no parent (or whose parent is not in the ledger). A chain is `merged` when any
run in it is `merged`, otherwise `closed` when any is `closed`, otherwise
`open`. *First pass* is a merged chain of one run whose `decisions` are
exactly `["merged"]`; the rate's denominator is the merged plus closed chains.
*Attempts* are the runs in a chain. Cost and tokens per merged PR sum every
run in the merged chains and divide by their count; one `unknown` run makes
its chain unknown, and any unknown chain makes the aggregate `unknown` with
the count. A parent cycle exits 1 naming the runs.

### Migration and compatibility

No existing data. Records written before a future `run-ledger/2` are read by
a `/1` reader only; `stats` refuses an unknown schema rather than guessing.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|----|------|------------|--------|------------|-------|
| R1 | Nobody records `merged`, so every PR stays `open` and the rate is `unknown` | H | M | `stats` prints `open=<n>` and `unknown — no decided PRs`, never a false 0%; the reference names the merger's `decide` step; automatic GitHub sync is a follow-up issue | 2 |
| R2 | Two runs on one branch and one base share a default run id and count as one | L | L | `--run-id` overrides the default; `/receive-review` records from the current HEAD, a new base | 1 |

## Build Order

Sizing: 2 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: four ACs, because they are one script's semantics and AC2's counts come from the `stats` command AC1 builds; slice 2: three systems (build, receive-review and their doc test), because the record call and its rework caller are one contract.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Run ledger script | `run_ledger.py` records runs, decides human results, finds a branch's last run and prints the derived totals | `.agents/skills/build/scripts/run_ledger.py`, `tests/test-run-ledger.sh` | — | 1, 2, 3, 4 | `bash tests/run.sh tests/test-run-ledger.sh` | 2 files · 2 systems · 4 ACs |
| 2 | Runs record themselves | `/build` Phase 6 records the run; `/receive-review` records a rework with its parent; the reference names every caller | `.agents/skills/build/references/run-ledger.md`, `.agents/skills/build/SKILL.md`, `.agents/skills/receive-review/SKILL.md`, `tests/test-doc-conventions.sh` | 1 | 5 | `bash tests/run.sh tests/test-doc-conventions.sh` | 4 files · 3 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/run-ledger.md`.
Plan: `## Plan: run-ledger` in `tasks/todo.md`, 2 slices, ready set <1>.
Files: .agents/skills/build/scripts/run_ledger.py, .agents/skills/build/references/run-ledger.md, .agents/skills/build/SKILL.md, .agents/skills/receive-review/SKILL.md, tests/test-run-ledger.sh, tests/test-doc-conventions.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: record has no human-result option (D3); outcomes reuse slice_outcome.derive (D5); unknown is a string, never 0 (D6); build/SKILL.md stays at most 600 lines.
```

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|----|----------|---------|-------------|------------|--------|
| D1 | Where records live | A) one JSON file per run under `tasks/runs/`; B) one JSONL log; C) Helix's `tasks/helix/<feature>/run.json` | A | B is right if records were append-only, but `decide` updates a record in place; C is right only once Helix exists, and it owns activation and final review per feature, not per-run attempts — when Helix lands, its run id is this ledger's run id | settled |
| D2 | Run id | A) `<branch slug>-<base SHA[:12]>` by default, `--run-id` to override; B) a timestamp minted at pre-flight | A | B is right if a session could not know its base; a derived id needs no state carried through the session and makes a re-record land on the same file | settled |
| D3 | How a human decision is protected | A) a separate `decide` command, `record` has no human option, `merged`/`closed` final; B) `record --human-result` with a merge rule | A | B is right if every writer were trusted; a missing input channel is a structural guarantee | settled |
| D4 | What an attempt is | A) a run in the PR's chain; B) the sum of slice attempts | A | B is right if every rework went through `/build`; a `/receive-review` rework has no slices, so B would count it as 0. Slice attempts stay in the record for drill-down | settled |
| D5 | Slice outcome values | A) reuse `slice_outcome.py`'s values and `derive()`; B) a second definition | A | never — #441 owns the contract | settled |
| D6 | Unknown in an aggregate | A) the aggregate is `unknown` with a count of the chains missing it; B) sum the known values | A | B is right only if a partial sum were labelled partial; a sum that silently omits runs reads as a cheaper PR | settled |
| D7 | Who records `merged` and `closed` | A) `decide`, called by whoever merges or closes; B) `stats` reads PR state from GitHub | A | B is right once the ledger must be complete without a human step — filed as a follow-up; reading the tracker here would couple a build script to one provider | settled |
| D8 | First-pass rate denominator | A) merged plus closed PRs; B) merged PRs only | A | B is right if abandoned work should not count against the first pass; a closed PR is a failed attempt | settled |

## Acceptance Criteria

- AC1: `run_ledger.py stats` prints `first_pass_rate`, `attempts_per_merged_pr` and `cost_per_merged_pr` derived from the records in the ledger directory, and removing a record changes the report.
- AC2: recording the same run twice — the same `record` call run again — leaves the record file byte-identical and every `stats` count unchanged.
- AC3: once a run is decided `merged` or `closed`, `decide` with another result exits 1 and a later `record` of the same run keeps the decision; `record` accepts no human-result option.
- AC4: a run recorded without tokens or cost stores `"unknown"` for each, and `stats` prints `cost_per_merged_pr=unknown` and `tokens_per_merged_pr=unknown` with the count of merged PRs missing them, never `0`.
- AC5: `/build` Phase 6 records the run through `run_ledger.py record`; `/receive-review` decides the parent `changes_requested` and records the rework with `--parent`; `.agents/skills/build/references/run-ledger.md` names every caller, including the merger's `decide`.

## Implementation Paths

- `.agents/skills/build/scripts/run_ledger.py` — the record schema, the human-result transitions and the derived totals.
- `.agents/skills/build/references/run-ledger.md` — who records what, and when.
- `.agents/skills/build/SKILL.md` — Phase 6 records the build run.
- `.agents/skills/receive-review/SKILL.md` — a rework run records its parent.
- `tests/test-run-ledger.sh` — the four script ACs.
- `tests/test-doc-conventions.sh` — pins the Phase 6 and `/receive-review` calls.
