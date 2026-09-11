---
implementation_paths:
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/scripts/registry/upsert.py
  - .agents/skills/task-registry/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - .claude/skills/task-registry/**
  - .claude/skills/system-design-planning/**
  - tests/test-task-registry.sh
  - tests/fixtures/task-registry/**
  - tests/test-doc-conventions.sh
---

# Spec: `upsert --depends-on` — record slice order as a dependency

> Origin: prompt — the `TODO(shortcut)` in `/system-design-planning` Step 8 · Designed 2026-09-11 · Review status: **draft, critic pass applied** (dispatched `critic`: 0 MUST-FIX, 9 SHOULD-FIX and 5 NITPICK, all folded in below)
> Visual: specs/upsert-depends-on.plan.html
> Adjacent, not folded in: #97 (native GitHub `blockedBy`), #98 (`build` routine)

## Problem

`/system-design-planning` files one task per build slice, but `upsert` cannot
record that slice 3 waits on slice 2, so the order lives in a prose `After:`
line that nothing reads. This change adds one flag, `--depends-on`, that lands
in the three places a dependency already renders. No consumer reads
`blocked-by` today — `/build` does not, and the `build` routine that will is
deferred to #98 — so every guarantee below is a **forward guarantee** for that
consumer, not a present-day protection. Out of scope: GitHub's native
`blockedBy` link (#97), a dependency solver (retired as `specs/task-registry.md`
AC-18), `select --routine build` (#98), and clearing a dependency (D8).

**Current state** — every path below was read.

```text
 skill (SKILL.md)          task-registry.py            registry/upsert.py           providers/*            index.py
   │ upsert --title …  ──►  build_parser :70-148        upsert_task :182            create_task/update_task  render_row :339
   │ (no dependency flag)   Task(...) :269-281  ──────► _merge :115-128 ──────────► metadata block           (blocked-by: …) :352
   │                        no depends_on passed        CARRIED_FROM_EXISTING :112   model.py:239 depends-on  parsed by DEPS_RE :51
   │                                                    depends_on carried from       local.py:176 reads it
   │                                                    the existing record, so       github.py:338 writes it
   │                                                    the CLI could never set it
 add_dependency (base.py:196, local.py:115, github.py:242): implemented, no caller anywhere.
```

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Idempotence | the same `upsert` run twice leaves the record and its index row byte-identical; a second run reports `updated`, never a second row | `registry/upsert.py:1-17` module contract; `_merge` returns `updated` for any non-terminal record (`:128`) | `tests/test-sweep-handoff.sh:222` pins `updated`; **new** assertion counts index rows after two runs with `--depends-on` |
| Write policy is never widened | `--depends-on` adds no provider write and no provider read; it rides the `create_task` / `update_task` call the command already makes, under the same `--apply` gate | `registry/upsert.py:36-63` `resolve_destination` | dry run prints `would …` and issues no `gh` call — `tests/test-task-registry.sh:950-957` pattern |
| Preview equals apply | the dry run refuses exactly what `--apply` refuses, including a missing dependency row | `registry/upsert.py:189-197` (index loaded before any provider access so the preview describes the run `--apply` performs) | dry run and apply with the same dangling id both exit 2 with the same message |
| Degrade visibly | when the provider the record is (or will be) published to has `native_dependencies=False`, the applied output says the dependency is stored as metadata; it is never reported native | `specs/task-registry.md` AC-8; `providers/github.py:68-75` | new assertions on the `upsert:` output for the local, github-pending and github-applied fixtures (D9) |
| Index row shape is unchanged | the row ends `(blocked-by: a, b)` exactly as `render_row` emits today and `DEPS_RE` parses | `registry/index.py:51`, `:352-353` | `tests/test-task-registry.sh:353` (canonical row) keeps passing |
| Every dependency is a valid task id | each `--depends-on` value passes `is_valid_id` (`registry/model.py:148`); a task never depends on itself | inferred | usage error, exit 2, message names the offending value, **before configuration is loaded** (D3) |
| Every dependency names an index row | each value is the id of a row already in `tasks/todo.md` | inferred — **question for the reviewer**, see D2 | exit 2 before any provider call, message names the missing id and the two ways to create the row |
| No silent replacement | when the flag replaces a non-empty existing set with a different one, the preview and applied lines show `blocked-by: <old> → <new>` | `CLAUDE.md` § No Silent Failures; hand-typed blockers exist in this index (`tasks/todo.md:467`) | new assertion: re-file over a hand-typed row and read the arrow |
| Legacy rows keep parsing | a hand-typed row such as `(blocked-by: Beta work)` still loads; validation is a CLI concern, not a model one | `tests/test-task-registry.sh:1774-1785` | that test keeps passing |
| Both trees stay identical after every slice | each slice copies its files to `.claude/skills/**` | `tests/test-skill-parity.sh:40` walks every canonical file | parity test green after slice 1, 2 and 3 separately |
| Rollback | removing the flag leaves every written record readable: all three consumers already parse `depends-on` today | `registry/model.py:265`, `providers/local.py:176`, `registry/index.py:241-247` | no migration step exists to undo |

## System design

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `task-registry.py` (CLI) | argument shape; usage errors (exit 2) for invalid or self-referencing ids, raised in the pre-configuration block `:180-199` beside the existing `upsert` usage errors; the set of fields the caller set explicitly | `args` only — no config, no provider |
| `registry/upsert.py` | merge semantics — which fields the incoming record replaces and which are carried from disk; the existence check of referenced ids; the replacement disclosure; the destination; the capability disclosure | the index (only place that knows every local id, precedent `_published_ref` `:152-165`); `registry.provider.capabilities` and `.name` |
| `registry/model.py` `Task` | the `depends_on` field, tuple-normalised, projected into the metadata block | — |
| `providers/local.py`, `providers/github.py` | where the body lands; both already read and write `depends-on` in the block | `Task.depends_on` |
| `registry/index.py` | the compact row, including `(blocked-by: …)` | `Task.depends_on` |
| `registry/detail.py` `show` | the `blocked-by:` line a human or a future consumer reads | row and provider record |

Nothing new owns anything. The change moves one fact — *who sets `depends_on`* — from "the existing record" to "the caller, when the caller says so".

### Interaction

```text
 caller                task-registry.py          registry/upsert.py                 provider / index
   │ (1) upsert         │                          │                                  │
   │  --depends-on a ──►│ (2) validate ids NEW     │                                  │
   │                    │   pre-config block :180  │                                  │
   │                    │ load_config, select_provider (unchanged; may call gh auth status :216)
   │                    │ Task(depends_on=(a,))    │                                  │
   │                    │ owned={"depends_on"} ───►│ (3) load_index_strict            │
   │                    │                    NEW   │     every dep id in index?  NEW  │
   │                    │                          │ (4) provider.discover ──────────►│ gh / fs
   │                    │                          │ (5) _merge(existing, incoming,   │
   │                    │                          │            owned)          NEW   │
   │                    │                          │ (6) _persist ───────────────────►│ create_task / update_task
   │                    │                          │ (7) _sync_index ────────────────►│ render_row → (blocked-by: a)
   │ ◄── report lines ──│◄─────────────────────────│ + "old → new" when replaced NEW  │
   │                    │                          │ + "stored as metadata" when the  │
   │                    │                          │   configured provider is not     │
   │                    │                          │   native_dependencies      NEW   │
```

| Arrow | Mode | On failure | On duplicate run |
|-------|------|------------|------------------|
| (2) | sync, in-process, before `load_config` | exit 2; no config read, no `gh auth status`, nothing written | same answer |
| (3) | sync, local file | missing id → exit 2 before any provider call, in dry run and in apply alike | same answer |
| (4)–(6) | sync, subprocess for github | `ProviderError` → `upsert: could not persist …`, exit 1, index untouched (`upsert.py:214-219`, unchanged). In-doubt case, pre-existing: `gh issue create` succeeds but its URL cannot be parsed (`github.py:180-184`) — the issue exists, the command reports failure, and the next run finds it only if the index already holds the reference | `_existing` finds the record → `updated`; `_merge` replaces `depends_on` because it is owned |
| (7) | sync, local file | as today | row refreshed in place, not appended |

### Failure unit

The command is one process. A failure at any arrow stops the run and nothing after it happens. The one partial state is pre-existing and unchanged by this design: the provider record and the index row are two writes with no transaction (`upsert.py:212-221`), so a crash between them leaves a record with no row, which `_sync_index` repairs on the next run (D6).

## Component contracts

### `task-registry.py upsert --depends-on`

```text
upsert (<task-id> | --derive-id NS (--spec P | --source P) [--fold-title]) --title T
       [--depends-on ID]...          # repeatable, order kept, duplicates dropped
```

| Aspect | Contract |
|--------|----------|
| Inputs | each `ID` passes `is_valid_id`; `ID` ≠ the task's own id (positional, or `_derived_id(args)`, which needs only `args`) |
| Placement | validated in the pre-configuration usage block (`task-registry.py:180-199`), so an invalid value never reaches `load_config` or `select_provider` — the latter shells out to `gh auth status` on a repo with a GitHub remote and no `provider =` line (`config.py:748, :765`) |
| Outcomes | exit 2 `task-registry: --depends-on <value> is not a valid task id` · exit 2 `task-registry: <id> cannot depend on itself` · otherwise the record carries `depends_on` and `owned` contains `"depends_on"` |
| Raises | nothing new |
| Idempotency | the flag is part of the command, so re-running the same command is a no-op update |
| Versioning | additive flag; every existing invocation (`/plan:195`, `/sweep:97`, `/wrap-up-session:225`) is unchanged and keeps carrying `depends_on` from disk |

### `registry/upsert.py`

```python
def upsert_task(registry, task: Task, apply: bool, *, owned: FrozenSet[str] = frozenset()) -> Tuple[List[str], int]: ...
def _merge(existing: Optional[Task], incoming: Task, owned: FrozenSet[str] = frozenset()) -> Tuple[Task, str]: ...
```

(`typing` names, matching the module's existing style and its `Python 3.8+` header at `task-registry.py:16`.)

| Aspect | Contract |
|--------|----------|
| Inputs | `owned` names fields the caller set explicitly; the CLI passes `{"depends_on"}` when the flag appears, `frozenset()` otherwise |
| Existence check | after the existing `load_index_strict` at `:189-197` and before `provider.discover`: every `task.depends_on` id must be `index.by_id(...) is not None`; otherwise exit 2 with `upsert: <task.id> depends on <dep>, which is not a row in tasks/todo.md — upsert the blocker first, or type its row by hand`. Identical in dry run and apply |
| Preview line | `upsert: would <create|update|reopen> <id> (<destination>); index row would be synced; blocked-by: a, b` when set; when the existing set is non-empty and differs: `blocked-by: <old> → <new>` |
| Applied lines | the existing line, plus `blocked-by: …` / `<old> → <new>` in the same form; plus, when `registry.provider.capabilities.native_dependencies` is false, one line composed here (not taken from `add_dependency`): `upsert: dependency stored as depends-on: metadata — <registry.provider.name> has no native issue dependency`. The **configured** provider is consulted, for every destination including `local-pending`: the record is pending publication to it, and the pending line at `:222-227` already names it. On the local provider (`native_dependencies=True`) the line is absent |
| Merge rule | `carried = {f for f in CARRIED_FROM_EXISTING if f not in owned}`. A field in `owned` is replaced by the incoming value; everything else keeps today's behaviour exactly |
| Raises | nothing new |
| Idempotency | unchanged — two runs, one record |
| Versioning | keyword-only parameter with a default; the three existing callers keep working: `tests/test-task-registry.sh:980-1015`, `tests/test-sweep-handoff.sh:29`, `tests/test-living-spec-reconciliation.sh:1090` |

### Providers, index, `show`

No contract change. `render_metadata_block` (`model.py:239-240`), `local.py:176`, `github.py:338`, `render_row` (`index.py:352-353`) and `show` (`detail.py:151-152`) already handle a non-empty `depends_on`. `add_dependency` stays as it is — it links after the fact; `upsert` writes the whole record.

## Data models

### `Task.depends_on`

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `depends_on` | `Tuple[str, ...]` | order as given; no duplicates | CLI: `tuple(dict.fromkeys(values))` (same idiom as `local.py:116`) |
| each entry | task id | passes `is_valid_id`; not the task's own id | CLI validation, exit 2 |
| each entry | task id | names a row in the index at write time | `upsert_task` existence check, exit 2 (D2) |

Three projections, all pre-existing, all written from the same field:

```text
index row        - [ ] Slice 2/3 — … <!-- task-id: design.x --> — … ([#12](url)) (blocked-by: design.w)
local detail     depends-on: design.w            (inside <!-- task-registry:begin/end -->)
github body      depends-on: design.w            (same block, model.py:239)
```

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| task depends on itself | CLI refusal, pre-configuration |
| dependency that no row names, **written through this flag** | `upsert_task` refusal before any provider call. Not unrepresentable in general: a hand-typed row can name anything, and a predecessor re-filed under a new title mints a new id and leaves the old row standing (D7) |
| the same id twice | `dict.fromkeys` de-duplication at the CLI |
| flag value silently overwritten by the record on disk | `owned` removes `depends_on` from the carried set for that run |
| existing blocker silently dropped by the flag | the `<old> → <new>` disclosure on the preview and applied lines |

### Transitions — `depends_on` across runs

`depends_on` is not a status; it never changes `Task.status`. `[!] blocked` stays a human-set state and is never inferred from a dependency (`specs/task-registry.md` AC-7 keeps holding).

| Existing record | Flag on this run | Result | Reported |
|-----------------|------------------|--------|----------|
| none | absent | `()` | — |
| none | `a, b` | `(a, b)` | `blocked-by: a, b` |
| `(a,)` | absent | `(a,)` — carried, today's behaviour | — |
| `(a,)` | `b` | `(b,)` — replaced (D1) | `blocked-by: a → b` |
| `(a,)` | `a, b` | `(a, b)` | `blocked-by: a → a, b` |
| `(a,)` | *clear* | not expressible — out of scope (D8) | — |

### Migration and compatibility

None. No stored shape changes; old rows and bodies without a dependency are read exactly as before, and rows that already carry `(blocked-by: …)` by hand are read exactly as before.

## Build order

| # | Slice | Delivers | Depends on | Contract exposed | Size |
|---|-------|----------|------------|------------------|------|
| 1 | Ownership-aware merge | `upsert_task(..., owned=)` and `_merge(..., owned)`; default preserves every current caller; `.claude/` copy synced | — | the Python signature above | S |
| 2 | CLI flag, validation, existence check, disclosures | `--depends-on`, exit-2 refusals in the pre-config block, preview and applied lines, replacement arrow, capability disclosure; a **new authenticated-gh `upsert --apply` fixture** (the mock already answers `issue create`/`edit`, `tests/fixtures/task-registry/gh:163-175`); `.claude/` copy synced | 1 | the CLI shape above | M |
| 3 | Consumers and docs | `/system-design-planning` Step 8 rewritten to **file sequentially**: for each slice, dry-run, apply, capture the id from the applied `upsert: created <id>` line, pass it as `--depends-on` to the next slice; `After:` and the `TODO(shortcut)` removed; `/task-registry` SKILL.md documents the flag and its two refusals; doc-conventions pin moves from `TODO(shortcut)` to `--depends-on`; `.claude/` copies synced | 2 | — | S |

Slice 1 first because slice 2 cannot set the field without it, and it is a pure-function change that leaves the suite green on its own once its `.claude/` copy is synced. The largest unknown — refusal versus report for a dangling id (D2) — sits in slice 2 and is settled by this review, not by a spike.

### Slice criteria

- Slice 1: a bare re-upsert of a record carrying `(a,)` still yields `(a,)`; `owned={"depends_on"}` with incoming `(b,)` yields `(b,)`; the three existing call sites run unchanged; parity green.
- Slice 2: `--depends-on 'Beta work'` exits 2 naming the value with no config read; `--depends-on <own id>` exits 2; `--depends-on ghost.id` exits 2 naming `ghost.id` in dry run and in apply, with no provider call; a valid run renders `(blocked-by: a)` on the row, `depends-on: a` in the local detail block, and `blocked-by: a` in `show`; the preview line contains `blocked-by: a`; re-filing over a row that carries `(blocked-by: x)` prints `blocked-by: x → a`; on the local fixture no metadata line appears; on the github-pending fixture (`tests/test-task-registry.sh:955`) and on the new github-applied fixture the applied output contains `stored as depends-on: metadata — github has no native issue dependency`; the same command twice leaves one row; parity green.
- Slice 3: `.agents/skills/system-design-planning/SKILL.md` contains `--depends-on`, the sequential filing rule, and no `TODO(shortcut)`; `.agents/skills/task-registry/SKILL.md` lists `--depends-on`; both trees byte-identical.

## Decisions

| # | Decision | Options | Recommended | Wrong when |
|---|----------|---------|-------------|------------|
| D1 | Flag given on an existing record | replace / union | **replace, disclosed** — the caller owns what it passes; union makes a dependency impossible to remove; the `<old> → <new>` line keeps a hand-typed blocker from vanishing silently | several independent filers add blockers to one task; then union |
| D2 | `--depends-on` names an id with no index row | refuse in dry run and apply / accept and report / refuse on apply only | **refuse in both** — preview fidelity is a stated property of `upsert` (`:189-197`), and a dangling blocker would make a future consumer skip the task forever. Consequence: Step 8 must file **sequentially** (slice 3), because slice *n*'s row exists only after slice *n−1* is applied (`:221`). A reviewer who wants every preview before any write cannot have it; the rendered document is that review. **Open — needs the reviewer** | a project files from several machines whose indexes diverge; or the blocker is a GitHub issue never `upsert`ed here (#97, #98 today) — the refusal names both remedies, and a provider-known second rung is the upgrade path (D7) |
| D3 | Where ids are validated | pre-config CLI block / beside `Task(...)` / `Task.__post_init__` | **pre-config CLI block** — the model also parses hand-typed rows and legacy prose blockers (`tests/test-task-registry.sh:1774`), which must load and be reported, not raise; and `_dispatch` runs after `select_provider`, which may call `gh auth status` | the model is only ever built from the CLI |
| D4 | Flag name | `--depends-on` / `--blocked-by` | **`--depends-on`** — matches the metadata key and the model field; `DEPS_RE` accepts both spellings on read | never — the reader is symmetric |
| D5 | Native GitHub link | now / after #97 | **after #97** — the disclosure reads `native_dependencies` from the configured provider, so when #97 flips it the line disappears with no change here | #97 is abandoned; then the metadata form is permanent and the line stays |
| D6 | Provider record and index row are two writes (`upsert.py:212-221`) | leave as is / make atomic | **leave as is** — pre-existing, self-repairing on the next run, outside this change under the orphan rule | a consumer starts trusting the index alone for dependency state |
| D7 | Blocker that exists only in the tracker (no row) | refuse with remedies / provider lookup rung | **refuse with remedies now**; a `_existing`-style provider lookup is the upgrade path once #97 makes the link native — record it as `TODO(shortcut)` in slice 2 | the tracker is the primary index for a project; then the lookup rung comes first |
| D8 | Clearing a dependency through the flag | `--no-depends-on` / out of scope | **out of scope** — with the flag absent the value is carried, and an empty incoming tuple is refilled by the local provider from the file (`local.py:247-248`), so clearing needs a provider change. Done by hand on the row or section until a consumer needs it | a consumer starts acting on `blocked-by`; then clearing must be a command |
| D9 | Which provider's capabilities drive the disclosure under `local-pending` | configured provider / write target | **configured provider** — the record is pending publication to it, and the existing pending line already names it | the project has no tracker; then provider and target coincide and the question vanishes |

Review-card questions that do not apply: D3 (no amounts or timestamps on this path) and D4 (no tenant- or owner-scoped entity; one repository, one index).

## Acceptance Criteria

- `upsert` accepts `--depends-on <id>`, repeatable, and stores the ids in order without duplicates.
- A value that fails `is_valid_id`, or equals the task's own id, exits 2 with a message naming the value, before configuration is loaded and before any provider is selected or read.
- A value naming no row in `tasks/todo.md` exits 2 with a message naming the value and both remedies, in dry run and in apply alike, before any provider call.
- The preview line names the dependency set; when a non-empty existing set is replaced by a different one, preview and applied lines show `blocked-by: <old> → <new>`.
- A valid run renders `(blocked-by: …)` on the index row, `depends-on:` in the metadata block of the local detail file and of the GitHub issue body, and `blocked-by:` in `show`.
- When the configured provider's `native_dependencies` is false — including when the write lands `local-pending` — the applied output contains one line stating the dependency is stored as metadata and naming the provider; on the local provider that line is absent.
- Running the same command twice leaves one index row and reports `updated` the second time.
- A re-upsert without the flag carries the dependency already on disk; a re-upsert with the flag replaces it.
- The three existing callers of `upsert_task` and `_merge` run unchanged.
- `/system-design-planning` Step 8 files slices sequentially, passes `--depends-on` with the id captured from the previous applied line, and no longer carries the `TODO(shortcut)`; `/task-registry` SKILL.md documents the flag; the skill trees stay byte-identical after every slice.

## Implementation Paths

- `.agents/skills/task-registry/scripts/task-registry.py` — the flag; id validation and self-reference refusal in the pre-configuration usage block; the `owned` hand-off
- `.agents/skills/task-registry/scripts/registry/upsert.py` — `owned` in `upsert_task` and `_merge`; the existence check; the preview, replacement and capability disclosure lines
- `.agents/skills/task-registry/SKILL.md` — the `--depends-on` line and its refusals in *Commands*
- `.agents/skills/system-design-planning/SKILL.md` — Step 8 files sequentially with the flag; `After:` and the shortcut marker are removed
- `.claude/skills/task-registry/**`, `.claude/skills/system-design-planning/**` — byte-identical copies, synced in every slice
- `tests/test-task-registry.sh` — the slice 1 and 2 criteria, in the existing file per *Right-Sizing Mechanical Guards*
- `tests/fixtures/task-registry/**` — the authenticated-gh `upsert --apply` fixture slice 2 needs
- `tests/test-doc-conventions.sh` — the pin moves from `TODO(shortcut)` to `--depends-on` for the planning skill
