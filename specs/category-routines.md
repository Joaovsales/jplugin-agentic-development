---
implementation_paths:
  - .agents/skills/wrap-up-session/**
  - .claude/skills/wrap-up-session/**
  - .agents/skills/task-registry/**
  - .claude/skills/task-registry/**
  - .agents/skills/auto-improve/SKILL.md
  - .claude/skills/auto-improve/SKILL.md
  - tests/test-routine-branch.sh
  - tests/test-routines-contract.sh
  - tests/test-routine-selectors.sh
  - tests/test-routine-wrapup.sh
  - tests/test-routine-step-ledger.sh
  - tests/test-auto-improve-rewire.sh
---

# Spec — Category Routines

> Status: implemented. `build` remains deferred to #97/#98; see *Scope*.
> Blast radius: template-wide. Ships to every consumer via `/sync` and `install.sh`.
> Supersedes: `specs/issue-lane-routing.md`

## Problem

`/route` decides *how much autonomy* an issue permits by having a model describe
the work and running that description through a policy lattice
(`min(channel_grant, label_grant, content_ceiling)`). The description derives from
untrusted prose, so the lattice needs a monotonicity guarantee, a claim schema, a
downgrade ledger, and a post-hoc radius tripwire to catch descriptions that were
wrong.

That machinery costs 923 LOC of policy plus 728 LOC of tests, and produced three
unattended halts in one week of scheduled runs:

| Halt | Owner | Cause |
|---|---|---|
| Zero eligible issues | `route` `label_grant` | the `auto-mode-allowed` label was never created |
| `Unknown JSON field` | `task-registry` github provider | fixed in PR #92 |
| `provisional-title-slug` refusal | `route` `_refuse_if_blocked` | issue had no identity block |

Two of three were routing preconditions, not properties of the work.

The autonomy question the lattice answers is one a **schedule** already answers.
An automation firing at 03:00 has chosen its routine; asking a model to re-derive
whether the work is autonomous adds a guess where there was a fact.

## Design

### What this spec keeps from the thing it replaces

The lattice goes. **The gate ledger stays.** `issue-lane-routing.md` records that
pipeline #93 shipped green with `/quality-gate` and the pre-push reviewers never
having run — *"Not by decision — by omission."* The mechanism that fixed it was
not the radius tripwire but the materialized step rows: a skipped gate had to
appear in `tasks/todo.md` carrying `skip: <reason>`, turning an unobservable
invariant into a line on disk.

Human PR review is a real backstop for bad code. It is not a backstop for an
**absent gate**, because an absent gate leaves no trace in the diff a human reads.
So the ledger survives as a convention rather than an engine: the routine contract
names each routine's mandatory step list, and the routine writes that list into
`tasks/todo.md` and into the PR body, retaining skipped rows with a reason. That
costs a reference document and no policy code.

### A routine is a category, and the category is one label axis

Four routines. Each selects issues by **kind** label, runs a named step list, and
ends at a pull request a human reviews.

| Routine | Selects on kind | Terminal artifact | Issue linkage | Status |
|---|---|---|---|---|
| `plan` | `design-decision` | **draft** PR carrying a spec | `Refs #N` | active |
| `fix` | `bug`, `tech-debt` | ready PR | `Closes #N` | active |
| `improve` | `enhancement` | ready PR | `Closes #N` | active |
| `build` | any kind, **and** a merged linked plan, **and** `blockedBy.totalCount == 0` | ready PR | `Closes #N` | **deferred — issue #98** |

### Scope

`build` is specified here but **not implemented in the first change**. Its
selector needs `blockedBy` read through `/task-registry`, and the GitHub provider
does not request that field: `OPTIONAL_ISSUE_FIELDS` is
`("closedByPullRequestsReferences",)`, and `capabilities` hardcodes
`native_dependencies=False` on the deliberate grounds (`github.py:60-63`) that
claiming an inferred link as native is the one thing capability degradation must
never do. Issue #97 revisits that with a runtime probe; #98 tracks `build` itself.

Deferring costs little and buys a lot. `plan`, `fix` and `improve` need nothing
from #97, and they carry the whole point of this spec — deleting 923 LOC of policy
and 728 LOC of tests, and closing the three halt classes in the problem table.
Gating that on #97 would block a well-understood deletion behind an unresolved
migration question: existing projects already carry `parent:` and `depends-on:`
metadata in issue bodies, and nothing yet says whether native links supersede it,
mirror it, or require a backfill.

Two things survive the deferral intact. The branch parser stays **general** over
routine names, so `routine/build/<n>-<slug>` parses and round-trips today (AC3,
AC5). Activating the routine later leaves the regex alone but is still a
deliberate multi-place edit: `references/routines.md`, `CONTRACT_ROUTINES` in both
`routine_branch.py` and `registry/config.py`, and `DEFAULT_SELECTORS`. Two tests
pin those mirrors against the contract document so the set cannot drift. And the
close-on-merge design below ships in full; #98 is what finally gives it a consumer.

`now` and `next` are the **priority** axis. They order candidates *within* a
routine's pool; they never select a routine. This is the correction that makes the
selectors a total function: measured against the pipeline repo, 9 of 28 open
issues (32%) carry both a priority and a kind label, so a design that selected on
both axes had two routines claiming one issue in a third of all cases.

Autonomy is not computed. `plan` produces a draft because a plan is a proposal;
the others produce a ready PR because human review *is* the gate.

**Where a routine lives is out of scope.** A routine is an Orca prompt, a Docker
job, a Claude skill, or a shell script — this spec defines the contract it
follows, so any host works unchanged. The *step list* is explicitly **in** scope,
per the gate ledger above.

### Kind precedence

An issue may carry more than one kind label (#95 in the pipeline repo carries
`documentation` and `tech-debt`). Precedence is a fixed order, first match wins:

```
bug > design-decision > tech-debt > enhancement > documentation
```

**The chain orders provider label names — the left-hand keys of `[labels.kind]` —
not the registry's canonical kinds.** That distinction is load-bearing, because
the canonical vocabulary cannot express this order. `KINDS` in `model.py` is
`epic | feature | bug | decision | research | operational | task`; `tech-debt` and
`documentation` are absent from it and both normalize to `task`, so a chain over
canonical kinds could not tell them apart and could not rank them. Ordering the
label keys leaves `KINDS` untouched and keeps the vocabulary per-project, which is
what the next section requires anyway.

`documentation` maps to `improve`. Every label in the chain is claimed by exactly
one routine; the chain's domain and the selector union are the same set.

An issue carrying no kind label is **not selected by any routine**. That is
correct: an unclassified issue has not been triaged. Four issues in the pipeline
repo (#113–#116) are in that state and should stay there — they are human
verification tasks.

### Selector labels come from configuration, not from this spec

The kind vocabulary is already configurable per project in `task-tracking.md`
(`[labels.kind]`, `[labels.priority]`). Hardcoding six English label names here
would reproduce the halt in the problem table at six times the surface. Routines
read the map from the project's configuration.

Today's default map is `bug`, `enhancement`, `design-decision` only, so two labels
this spec's chain depends on — `tech-debt` and `documentation` — resolve to nothing
out of the box. A project that never edits its configuration would therefore find
`fix` and `improve` silently under-selecting: exactly the "label was never created"
halt in the problem table, arriving as a quiet miss instead of a loud one. The
default vocabulary is extended to cover the chain, and the precedence order itself
is configurable alongside it.

A configured selector label that does not exist upstream is a **loud** failure:
non-zero exit naming the label. Per `CLAUDE.md` § Observability Discipline,
"nothing matched" and "the vocabulary is wrong" are different outcomes and must
not share an exit code.

### Where the contract document lives

Not `docs/routines.md`. `/sync` ships `CLAUDE.md`, `.agents/skills/`,
`.agents/agents/`, `.claude/skills/`, `.claude/agents/`, `.claude/hooks/`,
`.claude/browsers/`, `.claude/settings.json` and `.agents/git-hooks/`, and
`install.sh` copies only `.claude/skills/` and `.agents/`. A `docs/` path is in
neither set, so the contract would reach no consumer — while this spec's blast
radius line promises it ships to every one of them. The contract is pure
convention with no project-specific content, so it belongs inside the syncable
tree: `.agents/skills/wrap-up-session/references/routines.md`, with the
byte-identical `.claude/` copy that `tests/test-skill-parity.sh` requires.

Wrap-up owns it because wrap-up is the skill that parses the branch convention and
opens the PR; `routine_branch.py` already lands in the same skill.

### The branch name carries the routine and the issue

`/wrap-up-session` opens the PR but cannot know which issue the session addressed.
Rather than reintroduce a state file, the routine encodes both facts where every
harness preserves them — the branch name, under a reserved namespace:

```
routine/<name>/<issue-number>-<slug>
```

`routine/plan/90-auxiliary-input-contract`, `routine/fix/97-recipe-morph-beats`.
The parser is general over the name and anchored on the namespace:

```
^routine/([a-z][a-z-]*)/(\d+)-.
```

The `routine/` namespace exists because prefix-anchoring on bare routine names
does not work. `feature/2024-refactor` fails to match, but `fix/2024-refactor`
**matches** and yields issue 2024 — a human branch that never opted in, silently
linked to an unrelated issue. No human branch starts with `routine/`. The
namespace also makes the parser general: adding a fifth routine touches the
contract, not the regex.

A branch outside the namespace yields no routine and no issue, and wrap-up behaves
exactly as it does today. The convention is opt-in by shape, so no existing
workflow changes behavior.

Parser and **formatter** ship together. `format_routine_branch(routine, issue,
slug)` is what routines call to create the branch, so the serialization has both
ends in the repo and a round-trip test. A format with only a reader in-tree is
leakage the tests cannot see: a routine emitting `routine/plan/90_slug` would
yield `None`, wrap-up would silently open a ready PR instead of a draft, and
nothing would error.

### Issue closure happens on merge, not on PR creation

Revision 1 closed the issue when the PR opened. That is withdrawn. It broke the
`plan` → `build` handoff — `plan` closed the issue while opening its *draft* PR,
so `build`, which selects open issues with a merged linked plan, could never fire
and its silence was indistinguishable from "nothing to do."

Instead the PR body carries `Closes #N` (or `Refs #N` for `plan`) and GitHub
closes the issue when the PR merges. This dissolves four problems at once:

- The `plan` → `build` handoff becomes possible: a merged plan PR leaves the issue
  open, now carrying a merged linked plan, which is exactly `build`'s selector.
  Unexercised until `build` lands (#98), but the state it depends on is produced
  correctly from the first change — a later `build` needs no migration.
- No skill needs `gh issue close`, so the provider-coupling guard at
  `tests/test-doc-conventions.sh:369` stays intact and Jira keeps working.
- "PR created but close failed" stops existing as a failure mode.
- An abandoned PR no longer leaves a closed issue with no fix.

The requirement closure was meant to serve — *don't pick the same issue again
tomorrow* — is served instead by every routine's selector excluding issues that
already have an open linked PR from a `routine/` branch. That is a read, not a
write, and it is strictly more accurate: it also suppresses re-picking while a PR
is still in review, which closing-on-create did not.

### Concurrency

Disjoint selectors stop two *different* routines claiming one issue. They do not
stop two runs of the *same* routine overlapping, and this repo has already
recorded that incident class. Before creating its branch, a routine writes a
claim label (configured; default `in-progress`) and skips any issue that already
carries one. The claim is a tracker write, so it goes through `/task-registry`
like every other tracker write: `task-registry claim <ref> --routine <name>
--apply --approve`. It is idempotent, and it refuses an issue whose winning kind
label routes it to a different routine.

### Deletions

`/route` is removed entirely, including the radius tripwire (`check_actual_diff` /
`finalize_route`) and reviewer accounting (`finalize_reviewers`). The tripwire
compared claim-declared paths against the actual diff; with no claim there is
nothing to compare, and human PR review is the accepted backstop for scope
overrun. `tasks/route-decision.md` is read only by `/route` and `/auto-improve`
Phase 3, so removal touches no other skill.

`/task-registry` loses nothing, and gains exactly three reads and one write:
the selector-label map and precedence order above, the claim label under
*Concurrency* (the `claim` subcommand), and the upstream-existence check behind
AC12's loud failure — asserted by `select`, which is the command a routine
actually runs. It also loses `autonomy_label`, whose only reader was `/route`. An
earlier revision of this spec claimed the registry "gains nothing"; that was
withdrawn, because it contradicted both AC12 and this spec's own *Concurrency*
section, and a spec that understates its blast radius on the one component every
routine depends on is worse than one that overstates it. What the registry does
**not** gain is routing policy — no lane table, no autonomy computation, no
successor to the lattice.

The `provisional-title-slug` refusal that halted run 4 lives in
`route_issue.py:372`, not in the registry — `model.py:299` only sets the flag.
Deleting route removes the refusal.

`/auto-improve` keeps its discovery loop and remains callable by a routine. Its
Phase 3 dependency on `materialize_route` is cut, and its Phase 4 and Phase 5
references to "the materialized lane's" reviewer, verification, and wrap-up rows
must be replaced with the named steps. Phase 4's only reviewer dispatch today *is*
that dangling reference; leaving it would silently remove independent review from
the daily unattended runner — #93 verbatim, in the highest-risk consumer.

## Inputs

| Input | Source | Trust |
|---|---|---|
| Candidate issues, labels, claim | `/task-registry` | title/body untrusted, labels trusted |
| Dependency state (`build` only — deferred, #97) | `gh --json blockedBy` via the registry | trusted; **not yet supplied** |
| Linked PR state | `gh --json closedByPullRequestsReferences` via the registry | trusted; asserted at start |
| Kind/priority/claim vocabulary | project `task-tracking.md` | trusted |
| Routine + issue number | current branch name | trusted |

## Outputs

- A pull request — draft only for `plan` — whose body carries `Closes #N`
  (`Refs #N` for `plan`) and the executed step list with skip reasons.
- The routine's step list in `tasks/todo.md`, skipped rows retained.
- Unchanged wrap-up behavior on any branch outside the `routine/` namespace.

## Edge Cases

- **Branch outside `routine/`** — no routine, no issue; wrap-up opens a PR exactly
  as today. No error.
- **Branch inside `routine/` but the issue does not exist or is closed** — loud
  non-zero exit naming the issue; open the PR anyway. A bad link must not discard
  the work.
- **Issue carries two kind labels** — precedence resolves it; the routine records
  which label matched.
- **Issue carries no kind label** — never selected. The routine reports the count
  of such issues so the gap is visible.
- **Issue already carries the claim label** — skipped as in-flight.
- **`gh` predates `closedByPullRequestsReferences`** (< 2.73.0) — asserted **once
  at routine start**, loudly. Every routine depends on the field to exclude issues
  with an open linked routine PR, and degrading per-routine gave two different
  answers to one missing capability; `build`, when it lands, would have skipped
  every issue nightly and exited 0.
- **`blockedBy` non-empty** — `build` skips and names the blocker. Deferred with
  `build` itself (#98); no active routine reads dependency state.
- **No candidate found** — exit silently and successfully. A routine with nothing
  to do is not a failure.
- **A mandatory step could not run** — its row stays in `tasks/todo.md` and the PR
  body with `skip: <reason>`. Silent omission is the one thing that is never
  allowed.

## Acceptance Criteria

- AC1 — `.agents/skills/route/` and `.claude/skills/route/` do not exist, and
      no file outside `tasks/solutions/` references `/route`, `route_issue`, or
      `materialize_route`.
- AC2 — `user-prompt-route.sh` is deleted, its `UserPromptSubmit` entry is gone
      from `.claude/settings.json`, and the `/route` banner line in
      `.claude/hooks/session-start.sh` is gone.
- AC3 — `parse_routine_branch` returns `(routine, issue)` for
      `routine/plan/90-x`, `routine/fix/97-x`, `routine/improve/12-x`,
      `routine/build/3-x`.
- AC4 — `parse_routine_branch` returns `None` for `fix/2024-refactor`,
      `feature/2024-refactor`, `routine/fix/no-number`, `routine/fix/90` (no slug),
      `master`, and `routine//90-x`.
- AC5 — `format_routine_branch` round-trips through `parse_routine_branch` for
      every routine name in the contract.
- AC6 — `/wrap-up-session`'s PR procedure states `--draft` is passed when and
      only when the routine is `plan`, and that the body carries `Closes #N`
      (`Refs #N` for `plan`).
- AC7 — `/wrap-up-session` describes PR creation in exactly one place, and both
      Step 7 and Step 7.5 reach it; a branch outside `routine/` keeps today's
      behavior.
- AC8 — `.agents/skills/wrap-up-session/references/routines.md`
      documents the four routines, their kind selectors, the precedence order, the
      branch convention, **and each routine's mandatory step list with its
      non-skippable gates**; `build` is marked deferred, naming #97 and #98, so a
      reader cannot mistake it for available. Ships byte-identically to
      `.claude/skills/wrap-up-session/references/routines.md`.
- AC9 — A routine's executed step list, with skipped rows and reasons, appears
      in `tasks/todo.md` and in the PR body.
- AC10 — `/auto-improve` Phases 3, 4, and 5 name no routing engine and no
      "materialized lane"; Phase 4 names its reviewer set directly and carries the
      seven Review Dispatch Contract items; the skill still ships one PR per run.
- AC11 — No skill outside `/task-registry` calls `gh issue` or a Jira REST
      path; `tests/test-doc-conventions.sh`'s coupling guard passes unmodified.
- AC12 — Selector labels and the precedence order are read from the project's
      task-tracking configuration; the shipped default vocabulary covers every label
      in the precedence chain; and a configured label absent upstream exits non-zero
      naming the label. The check covers the three active routines' selectors; it
      does not fail on a capability only the deferred `build` needs.
- AC13 — `tasks/solutions/architecture/hard-gate-on-tasks-todo-md.md` and
      `tasks/solutions/patterns/consume-structured-records-before-rendering-human-summaries.md`
      are reconciled to cite the routine contract rather than deleted paths.
- AC14 — The full suite in `tests/` passes, and the skill tables in `CLAUDE.md`
      and `README.md` carry no `/route` row.

## Implementation Paths

- `.agents/skills/route/**`, `.claude/skills/route/**` — deleted
- `.claude/hooks/user-prompt-route.sh`, `.claude/settings.json` — hook removed
- `.claude/hooks/session-start.sh` — banner line removed
- `tests/test-route-decision.sh`, `test-route-hook.sh`, `test-route-skill.sh` — deleted
- `tests/test-doc-conventions.sh` — three `/route` presence assertions replaced
- `specs/issue-lane-routing.md` — superseded, deleted
- `.agents/skills/wrap-up-session/SKILL.md` — PR procedure converged and extended
- `.agents/skills/wrap-up-session/scripts/routine_branch.py` — parse + format;
  the regex is general over routine names, the membership check is not
- `.agents/skills/auto-improve/SKILL.md` — Phases 3, 4, 5 rewired
- `.agents/skills/task-registry/**` — selector map + precedence reader,
  claim-label read/write, upstream label-existence check; `KINDS` unchanged
- `.agents/skills/task-registry/templates/task-tracking.md` — default kind
  vocabulary extended to cover the precedence chain; claim label documented
- `.agents/skills/wrap-up-session/references/routines.md` — new, the routine contract and step lists (+ `.claude` parity copy)
- `CLAUDE.md`, `README.md` — table rows
- `tasks/solutions/**` — two documents reconciled
