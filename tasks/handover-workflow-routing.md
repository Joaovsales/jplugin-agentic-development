# Handover — shrinking the task registry

> **Read this first, then `tasks/todo.md`, then `specs/workflow-routing.md`.**
> Written 2026-09-06 on `analysis/simplify-routing` so a fresh session can pick the
> work up with no prior context. The spec is the contract; this file is the
> sequence, the gates, and the mistakes already paid for.
>
> **Status, 2026-09-07: Phase A is built and pushed on
> `feat/workflow-routing-phase-a`.** The #82 gate below is satisfied — PR #109
> merged as `bbef230`. Phase B is the next session's work; § 7 now carries what
> Phase A learned that changes it. Do not re-read §§ 2, 4, 5 as instructions —
> they are kept as the record of what was decided and why, and § 6's traps still
> apply to every phase.

---

## 1. What this work is

`specs/workflow-routing.md` — three changes and two deletions that take the task
registry from 4,924 LOC to 2,817 while adding the one capability the user actually
asked for and does not have.

The finding that reframed everything: **the bloat was never in routing.**
`routines.py` is 126 LOC — 2.6% of the tree. The bloat is a `tasks/todo.md`
tracker mirror nobody wants (1,273 LOC), a migration engine carried forever
(437), and a Jira client never run against a real Jira (437).

The user's decision that unblocked the design: `tasks/todo.md` is **not a mirror
of the tracker**. That does *not* mean deleting the file. The file survives as
the session's local working register; only the sync machinery dies. An earlier
draft read it as "delete the file" and produced a cascade of false dependencies.
**If a task in this plan seems to require rehoming the step ledger, that draft
has leaked back in — stop and re-read § *The key correction* in the spec.**

---

## 2. Gate — do not start until #82 has merged ✅ SATISFIED

> **Cleared 2026-09-07.** PR #109 merged; `master` carries `bbef230`. Phase A
> branched from it. Nothing below is still a gate; it is kept because the reason
> for the sequencing still governs Phases B and C.

Another agent is finishing **#82** in a separate worktree. As of this writing
there is no open PR for it (`gh pr list` → empty).

**Both chains of this work edit `CLAUDE.md`, and so does #82.** It is the one
file every path touches. Starting here before #82 lands guarantees a conflict in
exactly that file, in a repo where two sessions racing on one branch has already
cost a session.

```
Step 0.  gh pr list --state merged --limit 5      # confirm #82 landed
Step 1.  git checkout master && git pull
Step 2.  git checkout -b feat/workflow-routing-phase-a
```

Do not branch off `analysis/simplify-routing`. That branch carries only the spec
and this document, both of which are being committed to it now and merged ahead
of the build.

### What #82 does, and what it deliberately leaves for us

| | Owner |
|---|---|
| `find_config_path()` distinguishes *declared-but-missing* from *absent* | **#82's agent** |
| `CLAUDE.md` stops emitting a bare parseable pointer | **#82's agent** |
| `tests/test-doc-conventions.sh:327` inverted + 3-state regression test | **#82's agent** |
| This project's `docs/task-tracking.md` actually exists | **this plan, task A4** |
| The declaration lives in `.claude/project.md`, which `/sync` never touches | **this plan, task A4** |

The boundary is clean: #82 fixes the *engine* and stops the template lying. A4
supplies *this project's* configuration. Neither needs the other's code. If #82's
agent has already done A4's half, drop A4 and say so — do not redo it.

---

## 3. Sequence — three phases, three PRs

```
Phase A — the workflow command (R2)        ← DONE. feat/workflow-routing-phase-a
Phase B — Cut 1, the two dead modules      ← NEXT. needs nothing but a merged A.
Phase C — Cut 2, the todo.md sync engine   ← needs Cut 1 only for revertability.
             └─→ #97 ─→ #98
```

**One phase per `/build`, one PR per phase.** This is not ceremony. The spec's
rollback section requires Cut 1 to be a single revertable commit and Cut 2 to
ship its ten caller repoints in one commit with nothing interleaved. A single
build spanning all three destroys both properties.

**Why the feature comes before the cleanup.** Phase A is the only phase that
delivers something the user asked for; B and C are 2,147 LOC of deletion that add
no capability. Doing them first means a week of deletion before anything works
better. There is also a practical reason: A4 and Cut 1 both edit
`templates/task-tracking.md` and `references/configuration.md`, so doing the
config work first means Cut 1 edits them once, already in final shape.

---

## 4. Phase A — scope, as built ✅

Rows are already in `tasks/todo.md` under `## Plan: Phase A`. Spec ACs in
parentheses.

| Task | Delivers | New code? |
|---|---|---|
| A1 `routines.skill-chains` | `[routines.skills]` config layer + 3 validators | yes — `config.py` |
| A2 `routines.workflow-command` | `task-registry workflow <ref>`, six outcomes | yes — ~40 LOC |
| A3 `routines.total-order` | deterministic candidate order | yes — `model.py`, see § 5 |
| A4 `routines.project-config` | this repo's `docs/task-tracking.md` + declaration | no code |
| A5 `routines.pr-assertion` | scheduled run without a PR fails loudly | doc + test |
| A6 `routines.parity-suite` | byte-identical trees, full suite green | no |

**A2 is the whole point.** `select_routine()` in `routines.py:49` already maps
labels to a routine — it is wired only as a *filter*. The command is a thin shell
over a function that exists. What it must add is discrimination: today the
function collapses five distinct situations into one `None`. The six-outcome
table in spec § 3 is the contract, and AC2 requires each to be distinguishable in
**both** stdout and exit code. Exit `1` = "what you asked about does not exist";
exit `2` = "this tool is misconfigured". A nightly wrapper needs to tell those
apart.

**A1's wholesale-replace rule is deliberate.** `[routines.skills]` replaces
entirely rather than merging per key, matching `[routines.selectors]` rather than
`[labels.kind]`. That is only safe because AC9 refuses a routine with a selector
and no chain. Do not "fix" it into a per-key merge — that hides which chains a
project actually chose.

**`CONTRACT_ROUTINES` stays.** `config.py:99` refuses a routine outside
`("plan","fix","improve","build")` on purpose: *"Adding one is a deliberate edit
to the contract, not a configuration key."* AC12 is scoped to reconfiguring an
**existing** routine. A task that makes AC12 pass by weakening that gate has
misread it.

### Already satisfied — verify, do not rebuild

- **AC6** (workflow label absent upstream is refused, naming it) — shipped as
  `_selector_upstream_check` in `task-registry.py:436`.
- **AC10** (`claim` write gating, idempotency) — shipped in PR #105.

Add an assertion pinning each. Do not write new implementations.

---

## 5. Correction to make before building — AC3 is wrong as written

The spec says the order is "the existing `by_priority` key, stated". **It is not.**

```python
# model.py:38
def by_priority(task) -> Tuple[int, str]:
    return (PRIORITY_ORDER.get(task.priority, 3), task.id)
```

`task.id` for a GitHub issue is **not the issue number** — `_to_task` passes
`fallback_id=""`, so `model.py:305` derives the id from the body's `task-id`
metadata comment or from `slugify_id(title)`. The tie-break is a title-derived
slug.

So AC3's second half already holds (slug sort is deterministic — two runs do
return the same issue) and its first half is false (that order is not ascending
issue number).

**Recommended resolution:** change the tie-break to
`(rank, int(external.id) if numeric else inf, id)` and keep AC3 as written.
Ascending issue number is intrinsic, stable, and needs no tracker field; a
title slug reshuffles the whole backlog when someone edits a title.

`by_priority` has two callers today (`routines.py:105` and four sites in
`reconcile.py`). After Cut 2 deletes `reconcile.py` it has one. Changing it in
Phase A means updating both; that is correct and cheap, and doing it later would
mean changing a function whose second caller is mid-deletion.

Amend the spec's § *Ordering* and AC3 in the same commit as A3, so the spec never
describes code that does not exist.

---

## 6. Traps — every one of these has already been hit once

1. **Hand-surveying callers.** Two separate hand-surveys of `reconcile`/`publish`
   callers each missed entries — the second missed `plan/SKILL.md:200`, five
   lines from the `:195` it had just cited. **Regenerate the caller list with
   grep before Cut 2, do not trust the table in the spec.** It is recorded as
   mechanical for exactly this reason.

2. **`.agents/skills/` is a syncable root.** `sync/SKILL.md` — "Canonical skills
   → overwritten wholesale." Any project configuration placed there is destroyed
   on the next `/sync`. `docs/` appears in no syncable root; that is the whole
   reason it is the override home.

3. **Tests that cannot fail.** PR #105 shipped four assertions that could not
   fail and one test that ran `tasks/todo.md` as a shell command and reported
   `ok` (a stray backtick). **Every new assertion must be falsifiable by
   mutation** — break the implementation, watch the test go red, restore.

4. **Editing `CLAUDE.md` is legal here and only here.** Its banner says do not
   edit. This repository is the template *source* (`install.sh` is present), so
   the banner governs downstream copies. Phase A's A4 and Cut 1 both edit it.

5. **`references/routines.md` is kept, not deleted.** It carries the branch
   convention `routine_branch.py` parses, the `Closes #N` / `Refs #N` closure
   rules that are half of R5, and the step ledger. Six test files assert its
   contents. Only its *routing-vocabulary* sections retire.

6. **`migrate` is the only documented remedy for `missing-id`.** Deleting it in
   Cut 1 strands any downstream project mid-migration. Cut 1 must ship a one-shot
   replacement outside the skill — `scripts/migrate-learning-store.py` is the
   precedent — or state in the same commit that unmigrated projects are
   unsupported. Do not delete it silently.

7. **R4 is overstated and the spec says so.** "Every session ends in a PR" is not
   true today — `/wrap-up-session` has six documented no-PR exits. A5 does not
   make it true; it makes the failure loud. Do not write an AC claiming
   otherwise.

---

## 7. Phase B — Cut 1, the two dead modules (874 LOC)

Append these rows to `tasks/todo.md` when Phase A has merged.

- [ ] TDD: `grep -rn "jira" .agents .claude CLAUDE.md README.md tests/ specs/` returns no live reference; provider vocabulary is `github` or `local` everywhere it is named -> delete `registry/providers/jira.py` (437) and retire its documentation surface: `CLAUDE.md` (Task Tracking § provider list), `references/configuration.md`, `templates/task-tracking.md` (`[jira.issuetype]`, `[jira.priority]`)
- [ ] TDD: `task-registry migrate` is gone and exits non-zero as an unknown command; `missing-id` has a named remedy that resolves to a shipped file; `tests/test-task-registry.sh`'s 12 `migrate` references retire with it -> delete `registry/migrate.py` (437), delete `references/migration.md`, update `SKILL.md:186`, `references/progressive-disclosure.md:48`, `references/configuration.md:252`, and ship the one-shot replacement under `scripts/`
- [ ] TDD: `cloc --include-lang=Python .agents/skills/task-registry/scripts/` reports 4,090 (AC16); `tests/test-skill-parity.sh` green; `bash tests/run.sh` green -> parity copies + full suite

Cut 1 is a revert of one commit. Keep it that way — no interleaved changes.

### What Phase A changed for Cut 1

- **`templates/task-tracking.md` and `references/configuration.md` are already in
  final shape for the `[routines.*]` half.** Phase A added `[routines.skills]` to
  both. Cut 1's edit to them is now purely the `[jira.*]` removal, which is what
  § 3 predicted when it put the feature before the cleanup. Do not re-derive the
  routines sections; delete the Jira ones around them.
- **The Jira sweep has one more surface than the row above lists.** Phase A's
  `docs/task-tracking.md` and the two harness declarations (`.claude/project.md`,
  `AGENTS.md`) name a provider. They say `github`, so they need no edit — but
  `tests/test-routine-skills.sh` now asserts both declarations resolve to the same
  file, and a Cut 1 that moves either one breaks that pair rather than one
  assertion.
- **`tests/fixtures/task-registry/fake-jira.py` retires with `jira.py`.** It is
  not in the row above and it is the only other file whose whole reason to exist
  is the Jira provider.
- **AC3's wording now scopes the issue-number rung to providers that number their
  tasks.** Deleting Jira removes one of the two schemes that motivated the `id`
  fallback in `_external_number`; the fallback still earns its place for the local
  provider, so do not simplify it away with the Jira adapter.

---

## 8. Phase C — Cut 2, the todo.md sync engine (1,273 LOC)

`reconcile.py` 793 + `index.py` 276 + `upsert.py` 204, and with them the
`publish`, `pull`, `frontier` commands and the `_dependency_order` / `_cycles`
solver — a topological sort with cycle detection over a 15-issue backlog.

`publish` (`:408`), `pull` (`:506`) and `frontier` (`:536`) are **methods on
`Registry` inside `reconcile.py`**. That is why the cut boundary is module
ownership rather than risk: no other cut can delete them without owning the file.

Callers to repoint — **regenerate this list, see trap 1**:

| Caller | Command |
|---|---|
| `plan/SKILL.md:195` | `reconcile` |
| `plan/SKILL.md:200` | `publish --apply` |
| `wrap-up-session/SKILL.md:75` | `reconcile` |
| `wrap-up-session/SKILL.md:79` | `publish --apply` |
| `wrap-up-session/SKILL.md:220` | `upsert --apply` |
| `CLAUDE.md:472` | `frontier` (skills table) |
| `session-start.sh:214,418` | `publish`, `frontier` (banner text) |
| `specs/task-registry.md:76,165` | **AC-18 is a shipped AC for `frontier`** |
| `tests/test-task-registry.sh:1166` | `reconcile publish pull frontier doctor migrate` |
| `tests/test-routine-selectors.sh:419` | `frontier` |

`specs/task-registry.md` matters most. `/wrap-up-session` now reconciles living
specs before the review and commit gates (commit `b157369`), so a spec still
asserting AC-18 for a deleted command **fires actively** rather than sitting
dormant. Amend it in the Cut 2 commit, not after.

Ships as one commit so `git revert` restores the modules and their callers
together.

### What Phase A changed for Cut 2 — one new caller, and a class to keep

**`workflow` is an eleventh caller and it is not in the table above.** Phase A
added it, and it takes a `Registry` (`task-registry.py` imports `Registry` from
`registry.reconcile`). So does `select`, and so does `claim`. Regenerating the
caller list per trap 1 will find them; the point of naming them here is that the
table above was written before they existed and reads as complete.

**`Registry` itself must survive Cut 2, or move.** It is a three-line holder —
`config`, `provider`, `selection_reason` — with the reconcile methods hung off
it. Every command that survives the cut (`doctor`, `show`, `selectors`, `select`,
`claim`, `workflow`) uses only those three attributes and none of the methods.
Two honest options, and the choice is a design decision rather than a mechanical
one:

1. Move the three-attribute class into a module the cut does not touch, and let
   `reconcile.py` go whole. Smallest surviving surface, largest diff.
2. Keep `reconcile.py` as the holder and delete only the sync methods. Smaller
   diff, but the file keeps a name that no longer describes it, and AC16's LOC
   target is measured against the whole scripts tree.

Option 1 is the one the spec's framing points at — the cut is about deleting the
sync engine, not about relocating the registry — but it is worth stating rather
than assuming, because it changes what "one revertable commit" contains.

**Two things Cut 2 must not take with it.** `provider.list_tasks()` is used by
`select` and by `workflow`'s scan fallback, and `provider.result_truncated` is
read by both as a refusal condition. They live on the provider, not in
`reconcile.py`, but `reconcile.py:422` is the other reader and deleting the file
is the moment someone notices the flag and assumes it was only for sync.

---

## 9. Downstream, after Cut 2

- **#97** — its AC4 names `reconcile.py:350,355` and `dependency_strategy=auto`,
  which Cut 2 deletes. Note carefully: the *local* solver removed here is not the
  *provider capability probe* #97 asks for. Re-scope, do not close.
- **#98** — the `build` routine. It survives; its chain becomes one config line
  in `[routines.skills]`. Still blocked by #97.
- **#93** — re-scope against `claim`. Its `publish` premise dissolves in Cut 2
  and its `/route` motivation is already gone.
- **#90** — **not affected by any of this.** Both root causes are outside
  `publish`: `_split_title_summary` (`index.py:127`) runs on every row parse and
  `_seed_body` (`github.py:337`) is on the `upsert` path. A correction to this
  effect is already posted on the issue. It also carries an independent ask (a
  naming-conventions stub in `templates/task-tracking.md`).
- **#81, #106** — **not blocked and not this work.** #81's ACs mandate writing
  into `tasks/todo.md`; the file survives, so they stand. #106 is a
  `/plan`→`/build` chunking and handover feature; none of its eight ACs touches
  the ledger or the gates.
- **#99–#103** — unrelated.

Closed during this analysis: **#94** (obsolete — `route_issue.py` and the
`/route` skill verified absent) and **#108** (superseded by AC1).

---

## 10. Definition of done for Phase A ✅

- Every AC1–AC16 row that Phase A owns has a falsifiable assertion. ✅ — each new
  guard was mutation-tested: the guard was deleted, the suite went red, the guard
  was restored. Two rounds of assertions were rewritten because they did *not*
  go red; see § 11.
- `bash tests/run.sh` green. ✅ — 39 files.
- `.agents/` and `.claude/` trees byte-identical (AC15). ✅
- Spec § *Ordering* and AC3 amended per § 5 above. ✅ — § *Ordering* was already
  correct on `analysis/simplify-routing`; AC3 needed the code change plus a
  scoping clause added during review (see § 11).
- One PR, `Closes #82` **not** used — #82 belongs to the other worktree. ✅

---

## 11. Phase A postscript — what the review changed, and what a human still owns

### Assertions that passed for the wrong reason

Twice this session an assertion was green against a *broken* implementation. Both
are now mutation-tested, and both are worth reading before writing Phase B's:

- **The AC4 traversal guard.** Four assertions checked that a path-shaped chain
  step (`/../wrap-up-session`) is refused. Every one passed with the guard
  deleted, because the hostile step was refused anyway — nothing existed where it
  pointed. The fixture now *creates* the file the unguarded probe would find, so
  refusing and traversing give different answers.
- **The `[routines.skills]` config assertions.** They compared a project chain
  against the shipped default and the two were equal, so deleting the whole
  config section left them green. Pinned on `routine_skills_declared` instead.

The general shape: **an assertion is only a test if some reachable state makes it
fail.** Deleting the implementation and re-running is the cheapest way to find
out, and it caught things four dispatched review passes had to argue about.

### Owner: human — surfaced, deliberately not applied

Four findings are recorded here rather than fixed, because fixing them means
deciding something the spec does not say:

1. **AC2 is unsatisfiable as worded.** It requires all six § 3 outcomes to be
   distinguishable in output **and** exit code, and § 3's own table assigns exit
   `0` to four of the six. The implementation distinguishes all six in output and
   maps them onto three exit codes; that is the most any implementation can do
   against this table. Either AC2 or the table has to move.
2. **The exit-code contract has no row for an outage or a closed issue.** Phase A
   routes both to exit 1 and says so in the skill, on the reasoning that a
   scheduler must not page for either. That reasoning is stated, not specified.
   A third non-zero code for "retry" is the obvious alternative and would make
   AC2's count wrong in a new way.
3. **AC13 says no command takes more than one required argument, and `claim`
   takes two** (`<task-id>` and `--routine`). `--routine` is an option by
   argparse's reckoning and required by the command's, so whether this is met
   depends on which reading AC13 intends.
4. **`docs/task-tracking.md` restates the shipped defaults exactly.** Nothing
   pins them, so a load failure that silently falls back to defaults produces
   byte-identical behaviour and no test fails. `require_write_approval = true` was
   deliberately *not* lowered, which is the one line that would have made the
   difference visible. Changing this project's tracker configuration to prove the
   file is read is a project decision, not a review fix.

### Carry-forward into Phase B

- `tests/fixtures/task-registry/gh` now answers `issue view` from `issues.json`
  when no per-issue file exists. Fixtures that relied on `view` failing for an
  issue the same mock *lists* will behave differently.
- Every `SKILL.md` line number in §§ 7 and 8 predates Phase A and has moved.
  Trap 1 already says regenerate; this is the concrete reason.
