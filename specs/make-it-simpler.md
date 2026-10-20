---
implementation_paths:
  - .agents/skills/make-it-simpler/**
  - .agents/skills/task-registry/lanes/simplify.md
  - .agents/skills/task-registry/scripts/registry/config.py
  - .agents/skills/task-registry/templates/task-tracking.md
  - .agents/skills/wrap-up-session/scripts/routine_branch.py
  - .agents/skills/wrap-up-session/references/routines.md
  - .agents/skills/go/SKILL.md
  - docs/task-tracking.md
  - AGENTS.md
  - README.md
  - tests/test-make-it-simpler.sh
  - tests/test-lane-catalogue.sh
  - tests/test-routines-contract.sh
  - tests/test-routine-selectors.sh
  - tests/test-routine-branch.sh
  - tests/test-routine-wrapup.sh
  - tests/test-go-lanes.sh
  - tests/test-instruction-budget.sh
  - tests/test-doc-conventions.sh
  - tests/test-task-registry.sh
  - tests/fixtures/make-it-simpler/**
  - .agents/skills/wrap-up-session/references/routine-prompts/simplify.md
  - .agents/skills/wrap-up-session/references/routine-prompts/README.md
  - tests/test-sweep-routines.sh
---

# Spec: make-it-simpler

> Origin: "prompt" (2026-09-29 grilling session, after #204) · Designed 2026-09-29 · Review status: **built** 2026-09-29 (#212–#220) — critic: 15 findings, 12 applied as edits, 3 answered by the operator (Q28–Q30), 0 declined
> Visual: specs/make-it-simpler.plan.html

## Problem

The operator of this harness wants one behavior-preserving simplification a
day, sized to one review, shipped as a pull request — interactively with a
short grilling, or unattended as a routine. Today `/sweep --routine architect`
files APOSD design debt over the tree but never builds, and nothing looks for
the harness-shaped bulk the wrap-up-phases work (#204) removed: one rule stated
in many files, citations that no longer resolve, always-loaded prose over
budget. Out of scope: replacing `/sweep` or `/tidy`, building a *significant*
change, changing `/yolo` or `/auto-push`, and new `task-registry` verbs.

## Constraints

| # | Constraint | Value | Source | Detected by |
|---|------------|-------|--------|-------------|
| C1 | A significant change is never built unattended | "significant" is the bar in `/system-design-planning` § *When to Use / When Not*, cited by name and never restated | user (D5, D6) | `tests/test-make-it-simpler.sh` pins the citation and the absence of a restated list |
| C2 | An unattended build is small | ≤ 3 slices and one area — one skill with its `references/`, or one script with its tests — estimated against `slice/references/sizing.md` before filing | user (D9, Q28) | discovery sizes before it files (doc pin); the scope stop catches a miss |
| C3 | Minor behavior changes are declared | the PR body carries `Behavior changes:` — a list or `none`; an undeclared change found by review is **STOP** | user (D11) | lane step text (doc pin); `/quality-gate`'s dispatch carries the declared list as intent |
| C4 | Before- and after-proof | the affected-test command plus `bash tests/test-citations.sh`, run before the first edit and after the last, both quoted in the PR body | user (D11) | lane step text pin; PR body |
| C5 | The skill passes its own lens | `SKILL.md` ≤ 150 lines | user (Q26) | `tests/test-instruction-budget.sh` |
| C6 | `/yolo` and `/auto-push` are unchanged | no edit to either `SKILL.md` | user (Q22) | slice 5's Verify: `git diff --quiet master -- .agents/skills/yolo .agents/skills/auto-push` |
| C7 | Only the `simplify` routine selects a `simplify` task | `simplify` ranked in `kind_precedence` ahead of `tech-debt`; exactly one selector claims it | user (Q24) | `validate_selectors` (`config.py:537`); `tests/test-routine-selectors.sh` |
| C8 | Every routine lane ends at `/wrap-up-session` | chain's last skill | lane grammar | `lanes.py:308`; `tests/test-lane-catalogue.sh` |
| C9 | `signals.py` is read-only and offline | no write, no network, no subprocess other than `git ls-files` / `git rev-parse` | inferred | the test asserts `git status --porcelain` is unchanged after `rank` |
| C10 | `signals.py` is deterministic | identical tree → byte-identical JSON | user (Q25) | the test runs it twice and compares |
| C11 | An unattended run leaves the clone clean | every `tasks/todo.md` row its filing wrote (`registry/upsert.py:242`) is committed on its routine branch; a run that files nothing and selects nothing exits 0 with no output and no branch | user (Q29) | doc pin on the unattended sequence; the skill's closing `git status --porcelain` check |
| C12 | The lens never re-reports what `/tidy` owns | excluded: `suite`, `inventory`, `retired`, `installed`, `refs`, `worktrees`, `strays`, `graph`, `registers` (`tidy/SKILL.md:98-108`) | user (D4) | fixture: an unresolved backticked path and a retired-skill reference produce no candidate |
| C13 | No new always-loaded prose beyond one sentence | `AGENTS.md` grows by at most the named-exceptions edit | inferred | `tests/test-instruction-budget.sh` block budget |
| C14 | Rollback | the unit is the merged PR (slices 6–9 build on each other): reverting it removes the lane and the precedence entry; open `simplify` issues become unclassified — selected by no routine and counted in every routine's report (routines.md § *An unclassified issue belongs to nobody*); no data migration | inferred | `tests/test-lane-catalogue.sh` and `tests/test-routine-selectors.sh` on the reverted tree |
| C15 | No new `task-registry` surface | only existing verbs: `show`, `upsert`, `select`, `claim`, `lanes`, `selectors` | user (Q28) | `git diff --quiet master -- .agents/skills/task-registry/scripts/task-registry.py .agents/skills/task-registry/scripts/registry/upsert.py` |

## System design

### Current state

```text
 scheduler ──► routine spine (routines.md § The shared spine)
                 1 task-registry select --routine <name>      routines.py:56  (kind_precedence, config.py:106)
                 2 task-registry claim                        in-progress label
                 3 routine_branch.py format <name> <n> <slug> CONTRACT_ROUTINES, routine_branch.py:54
                 4 lane steps  (lanes/<name>.md)              lanes.py:290 validates; chain must end /wrap-up-session
                 5 /wrap-up-session

 lanes today: fix(bug,tech-debt) improve(enhancement,documentation) plan(design-decision)
              producers janitor/architect/tidy · interactive refactor/perf/investigate/babysit/none
 /plan Step 6 prints a build prompt and stops; only /yolo and /auto-push override it (AGENTS.md:16)
 /build pre-flight files one issue per slice (/slice --file)
 upsert writes tasks/todo.md on every --apply (upsert.py:242) and reopens a closed id (upsert.py:166)
 task-registry has no release or close verb; escalate takes investigation reasons only (escalation.py:20)
```

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `make-it-simpler/scripts/signals.py` — NEW | the candidate list and its rank for a given tree | the working tree, `git ls-files` |
| `/make-it-simpler` `SKILL.md` — NEW | classification (minor/significant), the size estimate, the scope written into the spec, the seeded grilling, the unattended sequence, the `/plan` and `/build` overrides, the scope stop | `signals.py` output, the registry, `references/*` |
| `make-it-simpler/references/lens.md` — NEW | the seven signals' definitions, the weight `W`, the `tests/fixtures/` and `/tidy` exclusions | — |
| `make-it-simpler/references/safe-moves.md` — NEW | the five practices seeded into every spec's § Decisions | — |
| `lanes/simplify.md` — NEW | the routine's step list, chain, selector, cues | — |
| `/task-registry` | task state, claim, derived identity (dedup key), the `tasks/todo.md` index | `docs/task-tracking.md` |
| `docs/task-tracking.md` + `config.py` defaults | kind precedence, selectors, chains | lane catalogue |
| `routine_branch.py` | the routine-name allow-list | — |
| `/system-design-planning` | the significance bar | — |
| `/plan`, `/slice`, `/build`, `/quality-gate`, `/wrap-up-session` | spec format, slices, TDD, receipt, PR — unchanged | the spec the skill writes |

### Interaction

```text
 interactive:  operator  ─(1)► /make-it-simpler [<arg>]
                                 rank(2) → top 3 → pick → file+claim(3) → /grilling(4) → spec(5) → lane steps 2–5
 unattended:   scheduler ─(1)► /make-it-simpler --unattended                                        NEW sequence
                                 a. rank(2) → deep review → classify → size
                                 b. file(3): minor & in cap → `simplify` task; else `decision`+`simplify`; skip closed ids
                                 c. spine 1–3: select --routine simplify → claim → branch routine/simplify/<n>-<slug>
                                    the index rows from b are the branch's first commit
                                 d. lane step 1 /make-it-simpler <ref> → spec(5) → lane steps 2–5 → ready PR
                                 decisions only: branch routine/simplify/<YYYYMMDD>-record → docs-only PR of the index rows
                                 nothing filed, nothing selected: exit 0, silent, no branch
 preview:      operator  ─(1)► /make-it-simpler --prepare   (steps a–b only; the operator commits the index rows)

 lane steps 2–5:  /plan <spec> (Step 6: no prompt, /build in place) ─► /build (pre-flight: no slice filing)
                  ─► /quality-gate ─► /wrap-up-session
```

| Arrow | Mode | On timeout | On duplicate |
|-------|------|------------|--------------|
| (1) | sync, in-session | n/a — no external call | a second unattended run the same day: its filing re-derives the same ids (update, not create); `select` skips the claimed task (`routines.py:70`) |
| (2) | sync subprocess | n/a — local; a non-zero exit stops the run loudly before anything is filed | read-only; re-running is free |
| (3) | sync, network (GitHub) | unreachable tracker → `local-pending`, reported, never retried silently (existing `upsert`) | `--derive-id simplify --source <path> --fold-title`; a `done`/`cancelled` id is skipped after `show`, because `upsert` would reopen it (`upsert.py:166`) |
| (4) | sync, human | the operator never answers → nothing further written; the filed task stays open for tomorrow | n/a |
| (5) | sync, local write | n/a | the spec path is derived from the task's slug; an existing spec for it is reopened, not duplicated |

### Failure unit

- `signals.py` failing stops only `/make-it-simpler`; no other skill calls it.
- A bad `simplify` lane fails `task-registry lanes` for **every** router (`lanes.py:290` refuses the catalogue), and a `kind_precedence`/selector mismatch fails `load_config` for every routine (`config.py:442`) — which is why the lane, the config, the routines-table mirror and `CONTRACT_ROUTINES` land in one slice.
- The dual write (file the task, then write the spec) is ordered registry first: a crash between leaves an open task with no spec, and the next run re-derives the same id and resumes it.
- A scope stop leaves one task claimed and no branch pushed; nothing else is held.

## Component contracts

### `signals.py rank`

```text
python3 .agents/skills/make-it-simpler/scripts/signals.py rank [--path <p>]... [--limit N]
  stdout: {"head": "<short sha>", "candidates": [Candidate, ...]}   sorted by score desc, then key asc
  exit 0: success, including "candidates": []
  exit 2: usage error, or a --path that matches no tracked file (message names it)
```

| Aspect | Contract |
|--------|----------|
| Inputs | tracked files (`git ls-files`) minus `tests/fixtures/` and `tasks/` (stated in `lens.md`), narrowed by `--path` prefixes; `--limit` default 10. Tests run `rank` inside a temporary `git init` repository built from `tests/fixtures/make-it-simpler/`, so fixtures are tracked there and never rank here |
| Outcomes | a ranked list; an empty list is success |
| Raises | exit 1 with a traceback only on a programmer error |
| Idempotency | pure over the tree (C10) |
| Versioning | no version field: its one consumer, this skill's `SKILL.md`, ships in the same commit |

### `/make-it-simpler`

```text
/make-it-simpler [<arg>]       interactive
/make-it-simpler --unattended  the scheduled entry: sequence a–d above
/make-it-simpler --prepare     preview: a–b only, interactive
/make-it-simpler <ref>         lane step 1 (from the spine or from /go)

<arg>, first match wins:
  `#N` or a registry id  → that task. On a `routine/simplify/` branch it is unattended lane step 1;
                           anywhere else it is interactive and grilled (routines.md § *Unattended detection* decides)
  a tracked path prefix  → interactive, candidates narrowed to it (`rank --path`)
  any other text         → interactive; the text is the focus the top 3 are chosen against (how `/go` passes a goal)
  nothing                → interactive over the whole tree
```

| Mode | Outcomes the caller must handle |
|------|---------------------------------|
| interactive | built (PR) · significant → handed to `/plan` or `/system-design-planning` · "none today" (nothing written) |
| `--unattended` | ready PR · docs-only record PR (decisions filed, nothing buildable) · silent exit 0 (nothing filed, nothing selected) · tracker unreachable (`local-pending` lines, no branch) · scope stop |
| `--prepare` | filed *n* (the registry's own lines) · nothing to file · tracker unreachable |
| scope stop | lane step 1 finds the claimed task significant, over the cap, or no longer reproducing at `HEAD` → before any edit: non-zero exit, no PR, the claim left in place, and one line naming the task, the reason and the remedy (relabel `design-decision`, or close it) |

Each candidate shown interactively carries its signal, a `file:line` evidence quote, the estimated lines saved, the callers touched, and minor/significant.

### Overrides owned by `/make-it-simpler` (like `/yolo` Phase A)

| Step | Override |
|---|---|
| `/plan` Step 1 — Interview | the spec the skill wrote carries § Decisions; `/plan` prints `DECISIONS CARRIED` and asks nothing unattended. Interactive runs already grilled |
| `/plan` Step 6 — Hand over | prints no prompt; `/build` runs in place |
| `/build` pre-flight — filing | no `/slice --file`: the `simplify` task is the tracked unit, the slices stay plan-block rows, and slice headers are not claimed |

### `task-registry` — as called

```text
show <derived-id>                                             # skip done / cancelled
upsert --derive-id simplify --source <path> --fold-title --title '<signal> in <path>' \
       --kind task --label simplify --evidence '<file:line> — <quote>' --criterion '<checkable>' --apply
upsert ... --kind decision --label simplify ...               # significant or over cap
select --routine simplify ; claim <ref> --routine simplify --apply --approve
```

`--kind decision` maps to the `design-decision` label (`DEFAULT_KIND_LABELS`, `registry/config.py:72`), which outranks `simplify`, so the `plan` routine owns a significant candidate — the unattended form of "hand it to `/plan`".

### Lane `simplify`

```text
---
routine: consumer
selects: simplify
cues: simplify, make it simpler, one home per rule, too long, trim
ends: ready PR whose body carries what step 5 names
---
1. /make-it-simpler <ref> — before-proof, scope, spec with safe-moves Decisions; a scope stop ends the run here — non-skippable
2. /plan <spec> — under the overrides /make-it-simpler § Overrides owns
3. /build — non-skippable
4. /quality-gate — non-skippable
5. /wrap-up-session — PR body: before/after proof, `Behavior changes:`, `Simplified:` — non-skippable
```

## Data models

### Entities

`Candidate` — one row of `signals.py` output.

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `signal` | `duplicate-rule` · `citation-drift` · `over-budget` · `doc-script-contradiction` · `enforced-prose` · `orphan-or-overlap` · `code-red-flag` | one of seven | a module-level tuple; the test asserts every emitted value is in it |
| `path` | tracked repo-relative path | tracked at `head`, not under `tests/fixtures/` or `tasks/` | `git ls-files` membership |
| `line` | int ≥ 1 | inside the file | computed from the match |
| `evidence` | str | the verbatim line at `path:line` | read, never composed |
| `lines_saved` | int ≥ 0 | an estimate | per-signal rule in `lens.md` |
| `callers` | int ≥ 0 | tracked files citing `path` | grep over tracked files |
| `always_loaded` | bool | `AGENTS.md`, `CLAUDE.md`, a `SKILL.md` frontmatter, the session banner | a fixed list in `signals.py`, named in `lens.md` |
| `score` | int | `lines_saved × max(callers, 1) × (W if always_loaded else 1)` | one function; `W` defined once in `signals.py` |
| `key` | str | `<signal> in <path>` — the registry title | one formatter |

`doc-script-contradiction`, `enforced-prose` and `code-red-flag` are **cues** at the script level (a doc sentence naming a flag, exit code or verb the script it cites does not contain; a sentence whose key phrase a test already asserts; a `.py`/`.sh` file over a size bound) — the skill's deep review confirms or drops each before it is shown or filed.

`simplify` task — a registry record: `--kind task`, label `simplify`, derived id `simplify.<…>` from `--source <path>` and the folded title.

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| a `simplify`+`tech-debt` task selected by `fix` | not unrepresentable — the skill never passes `--label tech-debt`, but an adopted architect task keeps it (`upsert` preserves labels, `upsert.py:164`); precedence resolves it to `simplify` (`routines.py:71`) |
| two open tasks for one file+signal | derived id (`--derive-id simplify --source --fold-title`) |
| a declined or merged candidate reopened by the next run | `show` before `upsert`; `done`/`cancelled` ids are skipped |
| a significant candidate filed as a buildable `simplify` task | classification precedes filing; significant files `--kind decision`, whose `design-decision` label outranks `simplify` |
| an unattended build over the cap | sizing precedes filing; the scope stop catches a misestimate before any edit |
| a dirty clone after an unattended run | the index rows are committed on the routine branch; the closing clean-tree check |
| a PR without `Behavior changes:` | lane step 5 text; the design reviewer receives the declared list |

### Transitions — `simplify` task

| From | To | Trigger |
|------|----|---------|
| — | `open` | unattended filing, `--prepare`, or an interactive pick of an unfiled candidate |
| `open` | `in_progress` | spine claim (unattended) or the interactive run's claim |
| `in_progress` | `done` | the PR merges (`Closes #N`) |
| `in_progress` | `in_progress` (held) | scope stop — the claim stays; the operator relabels `design-decision` (the `plan` routine then owns it once the claim is removed) or closes it |
| `open` / `in_progress` | `cancelled` | the operator closes the task by hand — declining in chat, or closing the PR unmerged; no registry verb does this (C15) |
| `done` / `cancelled` | — | terminal; `show` before `upsert` keeps it from being reopened |

### Migration and compatibility

No persisted data format changes, but the shipped selector set is an external
contract for every downstream project, and `/sync` never repairs `docs/` (it
is outside every syncable root). After a plugin upgrade, `load_config` refuses
on every command in two cases: a project that declares `kind_precedence`
without `[routines.selectors]` gets "selected but not ranked"
(`config.py:800`); one that declares `[routines.skills]` wholesale without
selectors gets "select issues but have no skill chain" (`config.py:656`). The
fix in both is to add `simplify` to `kind_precedence` ahead of `tech-debt`,
`simplify = simplify` to `[routines.selectors]`, and the lane's chain to
`[routines.skills]`; the template's comment says so. This repository's own
`docs/task-tracking.md` is edited in the routine slice. The GitHub `simplify`
label is created once by the operator; `select --routine simplify` refuses,
naming it, until then.

## Build Order

Sizing: 9 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 1–3: each test and fixture path counts as its own system, so a script or reference with its test is 3; slice 4: 4 ACs, all pinning one new file; slice 5: 3 systems, because the exception lives in the skill and is named in `AGENTS.md` with its pin; slice 6: 10 files, 8 systems, because `lanes.py`, `validate_selectors`, the routines-table mirror (`tests/test-routine-branch.sh` ContractAgreementTests) and the selector pins each refuse a lane the others do not know — split, the suite is red between slices; slice 7: 3 systems, one reference with two tests.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Rank the seven signals | `signals.py rank` emits the seven signals over a temporary fixture repository, scored and sorted, deterministic and read-only | `.agents/skills/make-it-simpler/scripts/signals.py`, `tests/fixtures/make-it-simpler/**`, `tests/test-make-it-simpler.sh` | — | 1, 2 | `bash tests/test-make-it-simpler.sh` | 3 files · 3 systems · 2 ACs |
| 2 | Signal boundaries | `--path` matching nothing exits 2; `tests/fixtures/` and `/tidy`-owned findings never surface | `.agents/skills/make-it-simpler/scripts/signals.py`, `tests/fixtures/make-it-simpler/**`, `tests/test-make-it-simpler.sh` | 1 | 3, 4 | `bash tests/test-make-it-simpler.sh` | 3 files · 3 systems · 2 ACs |
| 3 | Lens references | `references/lens.md` (signals, `W`, exclusions) and `references/safe-moves.md` (five practices) | `.agents/skills/make-it-simpler/references/lens.md`, `.agents/skills/make-it-simpler/references/safe-moves.md`, `tests/test-make-it-simpler.sh` | 2 | 5, 6 | `bash tests/test-make-it-simpler.sh && bash tests/test-citations.sh` | 3 files · 2 systems · 2 ACs |
| 4 | Skill body | `SKILL.md`: grammar, top-3 fields, significance citation, grilling seeds, safe-moves seeding, unattended sequence and its ends, scope stop; README row | `.agents/skills/make-it-simpler/SKILL.md`, `README.md`, `tests/test-make-it-simpler.sh`, `tests/test-instruction-budget.sh` | 3 | 7, 8, 9, 10 | `bash tests/test-make-it-simpler.sh && bash tests/test-instruction-budget.sh && bash tests/test-skills-table.sh && bash tests/test-skill-frontmatter.sh` | 4 files · 3 systems · 4 ACs |
| 5 | Pipeline overrides | `SKILL.md` owns the `/plan` Step 1, Step 6 and `/build` pre-flight filing overrides; `AGENTS.md` names the third exception; `/yolo`, `/auto-push` and the registry CLI untouched | `.agents/skills/make-it-simpler/SKILL.md`, `AGENTS.md`, `tests/test-doc-conventions.sh` | 4 | 11, 12 | `bash tests/test-doc-conventions.sh && bash tests/test-instruction-budget.sh && git diff --quiet master -- .agents/skills/yolo .agents/skills/auto-push .agents/skills/task-registry/scripts/task-registry.py .agents/skills/task-registry/scripts/registry/upsert.py` | 3 files · 3 systems · 2 ACs |
| 6 | Register the simplify routine | Lane file; `kind_precedence`, selector and chain in `config.py`, the template and `docs/task-tracking.md`; the `routines.md` table row and precedence block; `CONTRACT_ROUTINES`; and every test that mirrors them | `.agents/skills/task-registry/lanes/simplify.md`, `.agents/skills/task-registry/scripts/registry/config.py`, `.agents/skills/task-registry/templates/task-tracking.md`, `docs/task-tracking.md`, `.agents/skills/wrap-up-session/references/routines.md`, `.agents/skills/wrap-up-session/scripts/routine_branch.py`, `tests/test-lane-catalogue.sh`, `tests/test-routines-contract.sh`, `tests/test-routine-branch.sh`, `tests/test-routine-selectors.sh` | 4 | 13, 14, 15 | `bash tests/test-lane-catalogue.sh && bash tests/test-routines-contract.sh && bash tests/test-routine-branch.sh && bash tests/test-routine-selectors.sh && bash tests/test-task-registry.sh && bash tests/test-go-lanes.sh` | 10 files · 8 systems · 3 ACs |
| 7 | Routine wrap-up rules | `routines.md` gains the `simplify` steps section, the two branch rows, and the scope stop in § *Fix-escalation terminal* | `.agents/skills/wrap-up-session/references/routines.md`, `tests/test-routine-wrapup.sh`, `tests/test-routines-contract.sh` | 6 | 16, 17 | `bash tests/test-routine-wrapup.sh && bash tests/test-routines-contract.sh && bash tests/test-citations.sh` | 3 files · 3 systems · 2 ACs |
| 8 | Selection precedence | Pins: `simplify`+`tech-debt` → `simplify`; `design-decision`+`simplify` → `plan` | `tests/test-routine-selectors.sh` | 6 | 18 | `bash tests/test-routine-selectors.sh` | 1 file · 1 system · 1 AC |
| 9 | Go routing | `/go` states `fix` > `perf` > `simplify` > `refactor`, pinned | `.agents/skills/go/SKILL.md`, `tests/test-go-lanes.sh` | 6 | 19 | `bash tests/test-go-lanes.sh` | 2 files · 2 systems · 1 AC |

AC numbering follows § Acceptance Criteria in order. Slices 5 and 6 are disjoint and run in parallel after 4; slices 7, 8 and 9 are disjoint and run in parallel after 6. `/wrap-up-session` runs the full suite once.

Build prompt:

```
Invoke `/build` for `specs/make-it-simpler.md`.
Plan: `## Plan: make-it-simpler` in `tasks/todo.md`, 9 slices, ready set <1>.
Files: .agents/skills/make-it-simpler/**, .agents/skills/task-registry/lanes/simplify.md, .agents/skills/task-registry/scripts/registry/config.py, .agents/skills/task-registry/templates/task-tracking.md, .agents/skills/wrap-up-session/scripts/routine_branch.py, .agents/skills/wrap-up-session/references/routines.md, .agents/skills/go/SKILL.md, docs/task-tracking.md, AGENTS.md, README.md, tests/test-make-it-simpler.sh, tests/test-lane-catalogue.sh, tests/test-routines-contract.sh, tests/test-routine-selectors.sh, tests/test-routine-branch.sh, tests/test-routine-wrapup.sh, tests/test-go-lanes.sh, tests/test-instruction-budget.sh, tests/test-doc-conventions.sh, tests/fixtures/make-it-simpler/**.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/make-it-simpler.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: The significance bar is cited from /system-design-planning § When to Use / When Not, never restated (D5).
Constraints: /yolo, /auto-push and the task-registry CLI and upsert modules are not edited (D8, D22, C15).
Constraints: simplify tasks carry only the simplify label, ranked ahead of tech-debt (D17).
Constraints: signals.py is deterministic, read-only and offline; tests run it in a temporary git repo (D18).
Constraints: make-it-simpler SKILL.md stays at most 150 lines (D19).
Constraints: The GitHub simplify label is created by the operator, never by a test or script.
```

## Decisions

| # | Decision | Options | Picked | Source | Wrong when |
|---|----------|---------|--------|--------|------------|
| D1 | Name and relation to `/sweep` | `/make-it-simpler` separate skill · a `/sweep` lens · `/simplify` | separate skill, harness lens; open `tech-debt` tasks are an input | user | the built-in `simplify` stops shipping and a rename is wanted |
| D2 | Targets | docs/skills · code · both | both | user | — |
| D3 | Discovery | full tree review daily · cheap signals then deep review · area only | cheap signals, deep review of the top few, optional `<arg>` | user | cheap signals miss what matters (watch the pick rate) |
| D4 | Signals | the seven in § Data models, ranked by `score` | all seven; `/tidy`'s checks and `tests/fixtures/` excluded | user | — |
| D5 | Minor vs significant | cite `/system-design-planning` § *When to Use / When Not* · own list · size threshold | cite the bar | user | — |
| D6 | Significant candidate | grill → `/plan` (interactive); `--kind decision` (unattended) | as stated | user | — |
| D7 | Modes | interactive · `--prepare` · unattended | interactive; `--unattended` (discovery + build, Q29); `--prepare` kept as an interactive preview | user (Q29 revises) | — |
| D8 | Pipeline | `/yolo`+`/auto-push` · lane lists the chain | the lane lists `/plan`→`/build`→`/quality-gate`→`/wrap-up-session`; `/yolo` loops the backlog and is "not invoked by other skills" (`yolo/SKILL.md:275`) | user (Q22) | `/yolo` gains a single-item callable mode |
| D9 | Size cap | ≤ 3 slices, one area, unattended | as stated; interactive cap agreed in grilling | user | — |
| D10 | Lane shape | one consumer lane · producer · two lanes | one consumer lane, `selects: simplify`; the unattended entry runs discovery before the spine | user (Q23, Q29) | — |
| D11 | Proof | refactor-lane before/after + `Behavior changes:` · suite only | refactor-lane proof, required section, undeclared = STOP | user | — |
| D12 | Practices home | `references/safe-moves.md` · `tasks/solutions/` · `AGENTS.md` | `safe-moves.md`, seeded as § Decisions rows | user | — |
| D13 | Grilling | four seeds + frontier · open · one question | four seeds: scope in/out; what stays byte-identical; expected minor behavior changes; slice cap | user | — |
| D14 | Dedup | registry `simplify` label · ledger · none | registry, derived id per file+signal, `show` before `upsert` | user | — |
| D15 | Reporting | `Simplified:` line · none | lines before→after per file, always-loaded delta, duplicates collapsed | user | — |
| D16 | Nothing buildable | record PR · silent | decisions filed → docs-only record PR of the index rows; nothing filed → silent exit 0 | user (Q29 revises) | — |
| D17 | Labels | `simplify` only · `simplify`+`tech-debt` | `simplify` only, ranked ahead of `tech-debt` | user (Q24) | — |
| D18 | Signal computation | script · agent grep | `signals.py`, TDD, deterministic JSON | user (Q25) | — |
| D19 | Skill size | ≤ 150 lines · no cap | ≤ 150, pinned | user (Q26) | — |
| D20 | `/go` routing | no cues · cues + precedence | cues; `fix` > `perf` > `simplify` > `refactor` | user (Q27); placement against `fix`/`perf` assumed | cues misroute ordinary refactors (watch `[ROUTE]` lines) |
| D21 | Crossing `/plan`'s handover | third named exception owning overrides · a new `/plan` flag | third named exception; `AGENTS.md:16` names it | assumed — follows from D7 + Q22 | the separate lane-handover fix (improve/refactor) lands one general rule first — then cite it instead |
| D22 | Unattended run that cannot build | new `release`/`close` verbs · stop loudly · avoid by sizing first | size and classify before filing; a miss is a scope stop (non-zero, no PR, claim left) | user (Q28) | scope stops become common — then add `release`/`close` to `/task-registry` as their own change |
| D23 | Declined PR → cancelled | automatic · by hand | by hand; no registry verb exists (C15) | user (Q28) | a `close` verb lands |
| D24 | `signals.py` weight `W` for always-loaded | 3 · 5 · 10 | 5 | assumed | pick history shows always-loaded candidates dominate or never surface |
| D25 | Where the index rows go | same PR · producer record PR · operator | the unattended run commits them on its routine branch; decisions-only days get a docs-only PR on `routine/simplify/<YYYYMMDD>-record` | user (Q29) | — |
| D26 | Slice issues | file per slice · skip | skip: `/build` pre-flight filing is overridden; the `simplify` task is the tracked unit | user (Q30) | a build ever needs per-slice tracking (then pass `--parent #N`) |
| D27 | Size signals and noisy paths (from the first run, #231) | keep · cue-weight size hits · exclude logs | `code-red-flag`, and `over-budget` outside always-loaded files, save 1 line (a cue: moving or splitting lines saves none); `tasks/` is excluded like `tests/fixtures/`; `specs/` is never a `duplicate-rule` home | user (2026-10-01, after the first run ranked 8 size hits in the top 10 and 36th-place real duplicates) | a size hit the deep review confirms keeps ranking below the prose signals it should beat |

## Acceptance Criteria

- `signals.py rank`, run inside a temporary `git init` repository built from `tests/fixtures/make-it-simpler/`, emits one candidate for each of the seven signals, with `path`, `line`, a verbatim `evidence` line and `score = lines_saved × max(callers,1) × (5 if always_loaded else 1)`, sorted by score then key.
- `signals.py rank` run twice over the same tree prints byte-identical output, writes nothing (`git status --porcelain` unchanged), and exits 0 with `"candidates": []` on a tree with no signal.
- `signals.py rank --path <p>` exits 2 naming `<p>` when it matches no tracked file, and no candidate is ever under `tests/fixtures/` or `tasks/`.
- A fixture unresolved backticked path and a fixture retired-skill reference produce no candidate.
- `.agents/skills/make-it-simpler/references/lens.md` defines the seven signals, the weight `W` by name, the `tests/fixtures/` and `tasks/` exclusions, `specs/` as never a `duplicate-rule` home, and the nine `/tidy` checks it excludes.
- `.agents/skills/make-it-simpler/references/safe-moves.md` states five practices: headings are names only; callers cite by § name; a moved assertion is repointed, never deleted without a replacement; one home per rule; no script behavior change unless declared minor.
- `.agents/skills/make-it-simpler/SKILL.md` has frontmatter `name: make-it-simpler`, is at most 150 lines, and follows `/writing-skills`' section order; `README.md`'s skills table lists it (`tests/test-skills-table.sh` passes).
- `SKILL.md` cites `/system-design-planning` § *When to Use / When Not* as the significance bar and does not restate its list.
- `SKILL.md` states the argument grammar (`#N`/registry id, tracked path, free text, nothing), the top-3 fields (signal, `file:line` evidence, lines saved, callers, minor/significant), "none today writes nothing", the four grilling seeds, and that the five `safe-moves.md` practices are seeded as § Decisions rows in every spec it writes.
- `SKILL.md` states the unattended sequence — rank, classify, size against `slice/references/sizing.md`, `show` before `upsert` skipping `done`/`cancelled`, file, spine 1–3, index rows as the branch's first commit — its three ends (ready PR; docs-only record PR on `routine/simplify/<YYYYMMDD>-record`; silent exit 0), and the scope stop (non-zero, no PR, claim left, one line with the remedy).
- `SKILL.md` owns an override table with `/plan` Step 1, `/plan` Step 6 (no prompt, `/build` in place) and `/build` pre-flight filing (no `/slice --file`, slice headers unclaimed) rows, and names the fresh-session rule it is excepted from; `AGENTS.md`'s named-exceptions sentence names `/make-it-simpler`.
- `.agents/skills/yolo/SKILL.md`, `.agents/skills/auto-push/SKILL.md` and the `task-registry` CLI and `upsert` modules are unchanged.
- `task-registry lanes simplify` prints a consumer lane selecting `simplify` whose chain is `/make-it-simpler, /plan, /build, /quality-gate, /wrap-up-session`, and whose step 5 requires the PR body to quote the before- and after-proof, a `Behavior changes:` section (a list or `none`) and a `Simplified:` line; `tests/test-lane-catalogue.sh` passes with the lane counted.
- `kind_precedence` is `bug, design-decision, simplify, tech-debt, enhancement, documentation` in `config.py`, `docs/task-tracking.md`, the template and the `routines.md` § *Kind precedence* block; `docs/task-tracking.md` and the template declare `simplify = simplify` and its chain; `task-registry selectors` validates, and `tests/test-routine-selectors.sh`'s default-chain, selector-union and label-fixture pins include `simplify`.
- `routines.md` § *The routines* has a `simplify` row (consumer, selects `simplify`, ready PR, `Closes #N`), `CONTRACT_ROUTINES` includes `simplify`, and `routine_branch.py format simplify 12 trim-agents` prints `routine/simplify/12-trim-agents`, which `parse` reads back; `tests/test-routine-branch.sh` and `tests/test-routines-contract.sh` pass.
- `routines.md` has a `### \`simplify\` — steps` section that points to the lane file and states the discovery that precedes the spine, and the branch-row table (§ *Draft and linkage*, under § *Wrap-up on a routine branch*) has `routine/simplify/<n>-<slug>` (ready, `Closes #N`) and `routine/simplify/<YYYYMMDD>-record` (ready, docs-only, `Refs #N` per filed issue) rows.
- `routines.md` § *Fix-escalation terminal* also names the `simplify` scope stop: before any edit, non-zero, no PR, no PR ledger, the terminal PR assertion not run.
- An issue labelled `simplify` and `tech-debt` selects the `simplify` routine; one labelled `design-decision` and `simplify` selects `plan`.
- `/go` § precedence states `fix` > `perf` > `simplify` > `refactor`, and `tests/test-go-lanes.sh` pins that sentence (a static doc test; the routing itself is not claimed by it).

## Implementation Paths

- `.agents/skills/make-it-simpler/SKILL.md` — modes, grammar, classification, sizing, unattended sequence, overrides, scope stop
- `.agents/skills/make-it-simpler/references/lens.md` — the seven signals, `W`, exclusions
- `.agents/skills/make-it-simpler/references/safe-moves.md` — the five practices seeded into every spec
- `.agents/skills/make-it-simpler/scripts/signals.py` — the ranked candidate list
- `.agents/skills/task-registry/lanes/simplify.md` — the routine and interactive lane
- `.agents/skills/task-registry/scripts/registry/config.py` — `DEFAULT_KIND_PRECEDENCE` gains `simplify`
- `.agents/skills/task-registry/templates/task-tracking.md` — precedence, selector, chain defaults and the downstream-upgrade note
- `docs/task-tracking.md` — this project's precedence, selector and chain
- `.agents/skills/wrap-up-session/scripts/routine_branch.py` — `CONTRACT_ROUTINES` gains `simplify`
- `.agents/skills/wrap-up-session/references/routines.md` — routines row, precedence block, `simplify` steps, branch rows, scope-stop terminal
- `.agents/skills/go/SKILL.md` — precedence sentence
- `AGENTS.md` — the named-exceptions sentence
- `README.md` — regenerated skills table
- `tests/test-make-it-simpler.sh`, `tests/fixtures/make-it-simpler/**` — `signals.py` and the skill's doc pins
- `tests/test-task-registry.sh` — its GitHub label fixtures carry the `simplify` selector label
- `tests/test-lane-catalogue.sh`, `tests/test-routines-contract.sh`, `tests/test-routine-selectors.sh`, `tests/test-routine-branch.sh`, `tests/test-routine-wrapup.sh`, `tests/test-go-lanes.sh`, `tests/test-instruction-budget.sh`, `tests/test-doc-conventions.sh` — the counts and pins the new lane, routine and overrides move
