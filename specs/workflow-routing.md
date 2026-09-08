---
status: draft
implementation_paths:
  - .agents/skills/task-registry/**
  - .claude/skills/task-registry/**
  - .agents/skills/wrap-up-session/**
  - .claude/skills/wrap-up-session/**
  - docs/task-tracking.md
  - CLAUDE.md
  - tests/test-task-registry.sh
  - tests/test-routine-*.sh
  - tests/test-routines-contract.sh
---

# Shrinking the task registry

> **v2.** v1 proposed replacing the registry with a new `workflow` skill. Two
> independently dispatched reviews rejected it. The rejection was correct and its
> arithmetic is reproduced below, because the discarded design is the main
> evidence for this one.

## The mistake v1 made

v1 diagnosed the registry as bloated and then rewrote **routing**, which was
never the bloat.

| | LOC | Share |
|---|---|---|
| `routines.py` — all routing logic | 126 | **2.6%** |
| Local mirror — `reconcile` + `index` + `upsert` | 1,273 | 25.9% |
| Migration engine — `migrate.py` | 437 | 8.9% |
| Speculative provider — `jira.py` | 437 | 8.9% |

> Percentages above are of the **v1** 4,924-LOC tree, kept as the diagnosis
> that motivated the cuts. § *Honest accounting* explains why that denominator
> no longer describes the tree and states the measured deltas instead.

v1's own numbers convict it: it deleted 2,571 LOC and added ~380, landing at
**2,733**. Deleting the dead subsystems and changing nothing else lands at
**2,479**. v1 produced *more* code than doing less.

Two further v1 claims were false against the tree:

- **`.agents/skills/` is a syncable root** (`sync/SKILL.md`: "Canonical skills →
  overwritten wholesale"). v1 put the project's label configuration there, where
  `/sync` destroys it on every update. `docs/` is in no syncable root. v1's
  "deciding argument" for its chosen design ran backwards.
- **There is no `yaml` in this repo** (zero imports); `configparser` is already
  used by two modules. v1 charged a parser cost to the design that had one free
  and none to the design that needed a new one.

**The existing configuration already has the right shape.** `routine_selectors`
is keyed by workflow name with a *set* of labels; `kind_precedence` is a single
ordered list. v1 regressed both into per-file singular fields.

## Requirements

| # | Requirement | Status today |
|---|---|---|
| R1 | Issues carry a category label | ✅ works; 4 labels missing upstream (data, not code) |
| R2 | **Manual** — given an issue, the agent knows the workflow | ❌ **absent** — this is the only real gap |
| R3 | **Scheduled** — a routine picks the next issue in a category | ✅ `select` |
| R4 | Every session ends in a PR | ⚠️ **overstated** — see below |
| R5 | Tracker claimed on start, closed on merge | ✅ `claim` + `Closes #N` |
| R6 | Simple and modular | ❌ 4,924 LOC is the complaint |

**R2 is one command over a function that already exists.** `select_routine()`
already maps labels to a workflow; it is wired only as a filter. R6 is a deletion
problem. Nothing else needs building.

### R4 is not guaranteed today, and this spec does not pretend otherwise

`/wrap-up-session` has at least six documented exits that produce no PR: no
changes detected (`SKILL.md:24`), tests failing after 2 fix attempts (`:516`),
unresolved MUST-FIX (`:543`), the push gate (`:554`), an unwritable local record
(`:260`), and a `blocked` maintainer outcome (`:301`).

R4 is therefore restated as: **every workflow attempts a PR, and a run that ends
without one says so loudly.** A scheduled run gets a terminal assertion — `gh pr
view` on the branch, non-zero and loud if absent — because the failure mode this
prevents is a 03:00 run that ends silently having produced nothing.

## The key correction: the file survives, the sync machinery does not

The user's decision is that `tasks/todo.md` is **not a mirror of the tracker**.
An earlier draft read that as "delete the file," which forced a step-ledger
relocation, which in turn depended on two open issues. That was wrong, and it was
the largest source of contradictions in this spec.

`tasks/todo.md` stops being a *tracker mirror* and remains the session's *local
working file*. What gets deleted is the machinery that syncs it against a tracker
— `reconcile`, `index`, `upsert` — not the file.

Everything downstream simplifies:

- The **step ledger keeps its session-side sink**. No rehoming, no new format.
- **#81 is unaffected.** Its acceptance criteria mandate writing the ritual into
  `tasks/todo.md`; that stays true.
- **#106 is unrelated work**, not a dependency. It is a `/plan`→`/build`
  chunk-sizing and handover feature; none of its eight acceptance criteria
  mentions the ledger, gate omission, `/wrap-up-session`, or `/quality-gate`.
- The `improve` routine keeps a ledger home. It has no spec and no debug
  document, so a spec-only sink would have left it with nowhere to write —
  reintroducing exactly the omission #81 exists to catch.

Writing the ledger needs no parser: `/wrap-up-session` appends Markdown rows.
Only *reconciliation* needed `index.py`, and reconciliation is what stops.

## Design

Three changes. No new skill, no new vocabulary, no new config format.

### 1. Skill chains, in two configuration layers

| Layer | Home | Synced? | Purpose |
|---|---|---|---|
| Default | `.agents/skills/task-registry/scripts/registry/config.py`, beside `DEFAULT_KIND_PRECEDENCE` | yes | every adopter has working chains on install |
| Override | `docs/task-tracking.md` | no | this project's configured case |

Verified: `.agents/skills/` and `.claude/skills/` are both syncable roots, and
`docs/` appears in neither the roots block nor any retirement scan. So the
default layer reaches adopters and the override layer survives `/sync`. Under
AC14 the default lands in two byte-identical copies.

The override section:

```ini
[routines.skills]
plan    = /plan, /build, /wrap-up-session
fix     = /debug, /build, /wrap-up-session
improve = /auto-improve, /build, /quality-gate, /wrap-up-session
```

`[routines.skills]` **replaces wholesale**, matching the documented precedent of
`[routines.selectors]` rather than the per-key merge of `[labels.kind]`. A
project that overrides one chain therefore supplies all of them — which is safe
only because of AC9 below, which refuses a routine that has a selector and no
chain. Per-key merge would be the wrong fix: it hides which chains a project
actually chose.

### 2. The pointer moves out of `CLAUDE.md` — this is what makes #82 tractable

`CLAUDE.md` currently declares `Task tracking instructions: docs/task-tracking.md`.
`CLAUDE.md` is synced and overwritten wholesale; `docs/` is synced to nobody. So
**every fresh adopter receives a declaration pointing at a file that cannot
arrive** — permanently in the "declared but missing" state.

That makes the two obvious requirements contradictory: refuse a
declared-but-missing pointer loudly, *and* give a fresh install working defaults.
No rule can do both while the synced file carries the declaration.

**Resolution: the declaration moves to `.claude/project.md`** (and `AGENTS.md`
for Pi), which `/sync` never touches. `config.py` already reads all three
(`POINTER_FILES`). Then:

| Project state | Declaration | File | Behaviour |
|---|---|---|---|
| Fresh install | absent | absent | defaults, silently — correct, not a failure |
| Configured | present | present | overrides apply |
| Broken | present | absent | **refuse loudly, name the path** |

No project is ever in two states at once, and the loud refusal now fires only
when somebody actually declared something. This is the substance of #82, and it
requires editing `CLAUDE.md` — legal here, because this repository is the
template source (`install.sh` is present) and the "do not edit" banner governs
downstream copies.

### 3. `workflow <issue-ref>` — the R2 command

```
task-registry workflow 77     # → fix    /debug → /build → /wrap-up-session
```

~40 LOC over `select_routine()`, which already performs the lookup as a filter.
It must distinguish five outcomes the existing function collapses into one `None`:

| Outcome | Meaning | Exit |
|---|---|---|
| Workflow found | prints routine + chain | 0 |
| Resolves to `build` | prints the chain **and** that `build` is deferred (#98) | 0 |
| No kind label | untriaged; names the known labels | 0 |
| Claim label present | in flight; names the claimant | 0 |
| Unknown reference | refuses, names the reference | 1 |
| Config or upstream-label fault | refuses, names the label or file | 2 |

Exit `1` is "what you asked about does not exist"; exit `2` is "this tool is
misconfigured." A nightly wrapper distinguishes them.

## Deletion, in two cuts

The boundary between them is **module ownership**, not risk. `publish`, `pull` and
`frontier` are methods on `Registry` inside `reconcile.py` (`:408`, `:506`,
`:536`), so neither cut can delete them without owning that file.

### Cut 1 — the two dead modules (874 LOC)

| Module | LOC |
|---|---|
| `jira.py` | 437 |
| `migrate.py` | 437 |

Neither has a code caller. Both have a **documentation surface** that must be
retired in the same commit — this is not a codeless deletion:

- `jira.py` → `CLAUDE.md`, `references/configuration.md`,
  `templates/task-tracking.md` (`[jira.issuetype]`, `[jira.priority]`)
- `migrate.py` → `references/migration.md` (the entire file), `SKILL.md:186`,
  `references/progressive-disclosure.md:48`, `references/configuration.md:252`

**`migrate` is the only documented remedy for `missing-id`.** Deleting it strands
any downstream project mid-migration. Cut 1 must therefore either keep a
one-shot script outside the skill or state that unmigrated projects are
unsupported. This spec proposes the former: `scripts/migrate-learning-store.py`
already sets the precedent for a conversion that lives outside the skill it
serves.

### Cut 2 — the todo.md sync engine (1,273 LOC)

`reconcile.py` 793 + `index.py` 276 + `upsert.py` 204, and with them the
`publish`, `pull`, and `frontier` commands and the dependency solver
(`_dependency_order`, `_cycles` — a topological sort with cycle detection over a
15-issue backlog).

Callers to repoint — the survey that produced this list is mechanical, because
two hand-surveys each missed entries:

| Caller | Command |
|---|---|
| `plan/SKILL.md:195` | `reconcile` |
| `plan/SKILL.md:200` | `publish --apply` |
| `wrap-up-session/SKILL.md:75` | `reconcile` |
| `wrap-up-session/SKILL.md:79` | `publish --apply` |
| `wrap-up-session/SKILL.md:220` | `upsert --apply` |
| `CLAUDE.md:472` | `frontier` (skills table) |
| `session-start.sh:214,418` | `publish`, `frontier` (banner text) |
| `specs/task-registry.md:76,165` | **AC-18 is a shipped acceptance criterion for `frontier`** |
| `tests/test-task-registry.sh:1166` | `reconcile publish pull frontier doctor migrate` |
| `tests/test-routine-selectors.sh:419` | `frontier` |

`specs/task-registry.md` matters most: `/wrap-up-session` now reconciles living
specs before the review and commit gates (`b157369`), so a spec still asserting
AC-18 for a deleted command fires actively rather than sitting dormant.

## What is explicitly kept

- **`references/routines.md`.** It carries the branch convention parsed by
  `routine_branch.py`, the `Closes #N` / `Refs #N` closure rules that are R5's
  second half, and the step ledger. Six test files assert its contents. Only its
  routing-vocabulary sections retire, because the config now holds them. Its
  § *Step ledger* keeps naming `tasks/todo.md` — the file survives.
- **`local.py`.** The second provider implementation, which is what makes the
  seam real rather than speculative, and the zero-config path for an adopter
  without `gh`.
- **`CONTRACT_ROUTINES`.** `config.py:99` refuses a routine outside
  `("plan","fix","improve","build")`, deliberately: *"Adding one is a deliberate
  edit to the contract, not a configuration key."* That refusal is correct and is
  kept — which is why AC12 is scoped to configuring an *existing* routine.

## Ordering — R3 needs a total order

Precedence selects the *workflow*; it cannot order candidates *within* one, since
they all share a label. The order is:

```
(priority rank: now < next < unset, then ascending issue number)
```

Ascending issue number is intrinsic and stable and needs no tracker field.
Without it a scheduled run picks whatever `gh issue list` happened to return.

**This is not what `by_priority` does today, and an earlier revision of this spec
wrongly said it was.** `model.py:38` returns `(rank, task.id)`, and `task.id` for
a GitHub issue is a *title-derived slug*: `_to_task` passes `fallback_id=""`
(`github.py:262`), so `model.py:305` falls through to `slugify_id(title)`. So the
determinism half of AC3 already holds — a slug sort is stable — while the
ascending-issue-number half is new work. The tie-break becomes the numeric
external id where the provider supplies one, falling back to the slug. Editing an
issue title must not reshuffle the backlog.

`by_priority` has two callers today (`routines.py:105` and four sites in
`reconcile.py`); after Cut 2 it has one. Both change together.

## Writes stay gated

`claim` is the only mutating command and keeps today's `WriteGate`: dry-run by
default, `--apply` to write, `--approve` where the project requires it. A
scheduled routine passes both on standing authorization recorded in
`docs/task-tracking.md`. Not negotiable down — `CLAUDE.md` requires explicit
authorization for external status changes.

## Honest accounting

The v1 table stated absolute end-state figures against a 4,924-LOC baseline.
Phase A then *added* to the tree, so those absolutes described a tree that no
longer existed before Cut 1 began. Measured deltas replace them: a delta stays
true across a moving baseline, which an absolute cannot.

| Path | Deleted from the scripts tree | Measured |
|---|---|---|
| Cut 1 | 977 (`wc -l`) | 5,539 -> 4,562 against `f6bb43c` |
| Cut 2 | 1,395 (`wc -l`) | `reconcile.py` 797 + `index.py` 394 + `upsert.py` 204, measured on this branch |

Cut 1 deletes more than the 874 the two modules weigh, because removing the Jira
adapter orphaned its configuration: `DEFAULT_JIRA_*`, five `Config` fields, the
`Secret` wrapper, the insecure-transport floor, and `_url_credentials`.

**437 of those lines are relocated, not removed.** `migrate.py`'s logic now lives
in `scripts/migrate-task-registry.py` (765 LOC — the port, plus the row parser it
had been importing from `index.py`, which Cut 2 deletes, plus the confinement and
encoding handling it had been getting from `Config` and `index.py`). The
scripts-tree figure is what AC16 measures and what the skill's readers carry.
Netting the relocation back in, plus `references/migration.md` (165), the
*shipped* surface is 377 lines lighter, not 977 — and 193 more come off the test
fixtures, which ship to nobody. Both numbers are true of different things, and
quoting only the first would be the kind of accounting this section is named
against.

**The honest summary is that this cut is a correctness and distribution win, not
a size win.** Deleting a provider nobody ever ran, and moving a one-shot out of a
tree `/sync` overwrites, are both worth doing on their own terms. The LOC delta
is real but small once the relocation is netted out, and no decision here should
rest on it.

`cloc` is not installed in this environment; the non-blank, non-comment count
above is the stand-in, computed the same way for both sides of the comparison.

**Rollback.** Cut 1 is a revert of one commit. Cut 2 is not: it repoints
ten callers across two skill trees, `CLAUDE.md`, and two specs. It ships as a
single commit with no interleaved changes, so `git revert` restores both the
modules and their callers together.

## Test surface

| File | LOC | Disposition |
|---|---|---|
| `test-task-registry.sh` | 1,812 | 23 `reconcile` / 12 `migrate` / 8 `upsert` refs — retire with A/B |
| `test-living-spec-reconciliation.sh` | 1,105 | audit — couples to `reconcile` |
| `test-routine-selectors.sh` | 569 | extend for `workflow`; **also invokes `frontier` at `:419`** |
| `test-routine-branch.sh` / `-contract` / `-step-ledger` / `-wrapup` | 528 | unaffected — `routines.md` survives |
| `test-syncable-paths.sh` | — | in blast radius if the config vocabulary changes; it pins six copies of the roots list |
| `test-doc-conventions.sh`, `test-skill-references.sh`, `test-skill-parity.sh`, `test-skill-invocation-chain.sh` | — | assertions naming deleted paths must be updated |

Every new assertion must be falsifiable by mutation. PR #105 shipped four that
could not fail and one test that ran `tasks/todo.md` as a shell command and
reported `ok`.

## Acceptance criteria

- **AC1** `task-registry workflow <ref>` prints the routine and its skill chain
- **AC2** All six outcomes in § 3 are distinguishable in output **and** exit code
- **AC3** `select --routine <name>` orders candidates by `(priority rank, ascending issue number, id)`; two runs on an unchanged backlog return the same issue. The issue-number rung applies where the provider numbers its tasks — GitHub. A local slug is not a number, so it falls to the `id` rung; the fallback stays because a tracker added later may number its tasks differently again, and ordering two id schemes against each other would be a guess. Determinism holds on every provider; ascending-by-number does not
- **AC4** Load refuses a chain naming a skill absent from disk, naming the skill
- **AC5** Load refuses a chain whose last element is not `/wrap-up-session`
- **AC6** A workflow label absent upstream is refused, naming the label
- **AC7** A *declared-but-missing* config file is refused loudly, naming the path, and is distinguishable from *no declaration*; a fresh install with no declaration loads defaults silently (closes #82)
- **AC8** `[routines.skills]` replaces wholesale; a project override supplies every chain
- **AC9** Load refuses a routine that has a selector but no chain, naming the routine
- **AC10** `claim` without `--apply` writes nothing and says so; `claim` is idempotent and refuses an issue claimed by another routine
- **AC11** A **scheduled** run whose branch has no PR at completion reports it loudly and exits non-zero
- **AC12** A project changes an **existing contract routine's** chain by editing one file (`docs/task-tracking.md`) and no code; adding a new routine remains a deliberate `CONTRACT_ROUTINES` edit
- **AC13** No command takes more than one required argument
- **AC14** `jira.py`, `migrate.py`, `frontier`, `publish`, `pull` are absent, and no test, skill, hook, `CLAUDE.md`, `README.md`, or **`specs/`** references them
- **AC15** `.agents/` and `.claude/` trees are byte-identical
- **AC16** Cut 1 removes `jira.py` and `migrate.py` and everything they orphan
  from `.agents/skills/task-registry/scripts/`, a measured 991-line reduction
  against `f6bb43c` (5,539 -> 4,562 by `wc -l`); Cut 2 removes a further 1,395,
  measured on this branch. Both stated as deltas against a named commit rather than
  as absolutes, because Phase A moved the baseline the v1 absolutes were derived
  from — see § *Honest accounting*. AC14 is met when no **live** reference
  remains: a documented retirement note and a test asserting a name's absence are
  records of the deletion, not references to the deleted thing

AC12 and AC13 replace v1's "under 500 LOC" — a criterion that measured volume
while complexity relocated into unchecked data.

## Affected work

Surveyed 2026-09-06 against 13 open issues, after #94 and #108 were closed and
#105 merged.

| Item | Relationship |
|---|---|
| **#82** | Blocks § 2 and the `workflow` command. Resolved by moving the pointer out of `CLAUDE.md`. |
| **#97** | Sequence after Cut 2 — its AC4 names `reconcile.py:350,355` and `dependency_strategy=auto`, which Cut 2 deletes. The *local* solver removed here is not the *provider* capability probe it asks for. |
| **#98** | `build` survives; its chain becomes a config line. Still blocked by #97. |
| **#107** | Answered by configuration: `fix = /debug, /build, /wrap-up-session`. |
| **#93** | Re-scope against `claim` — its `publish` premise dissolves in Cut 2, and its `/route` motivation is already gone. |
| **#90** | **Not affected.** Both root causes are outside `publish` — `_split_title_summary` (`index.py:127`) runs on every row parse, `_seed_body` (`github.py:337`) is on the `upsert` path. It also carries an independent ask (naming-conventions stub in `templates/task-tracking.md`). |
| **#81** | **Not blocking.** Its ACs mandate `tasks/todo.md`; the file survives, so they stand. |
| **#106** | **Not this work.** A `/plan`→`/build` chunking and handover feature; no AC of its eight touches the ledger or the gates. |
| **#99, #100, #101, #102** | Unrelated — project bootstrap. |
| **#103** | Unrelated — verifier review waves. |
| `specs/task-registry.md` | AC-18 asserts `frontier`; must be amended in the Cut 2 commit. |

## Dependency order

```
#82 ──→ § 2 pointer move ──→ workflow command (R2)

(nothing) ──→ Cut 1

Cut 1 ──→ Cut 2 ──→ #97 ──→ #98
```

- **Cut 1 is unblocked now.** PR #105 is merged; the two modules have no code
  callers. Its cost is the documentation surface and the `migrate` replacement.
- **The `workflow` command needs #82** — specifically the pointer move in § 2.
- **Cut 2 follows Cut 1** only to keep the two deletions revertable
  independently; there is no technical coupling.
- **#97 then #98** are downstream of Cut 2, because their acceptance criteria
  reference code it deletes.

Nothing blocks starting.
