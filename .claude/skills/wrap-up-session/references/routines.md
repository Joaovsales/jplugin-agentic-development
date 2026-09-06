# The routine contract

> Defined by `specs/category-routines.md`. Read by `/wrap-up-session`, which
> parses the branch convention below and opens the terminal pull request.

A **routine** is a scheduled category of work. It selects issues by a single
label axis, runs a named step list, and ends at a pull request a human reviews.

Where a routine *lives* is out of scope: an Orca prompt, a Docker job, a Claude
skill, a shell script — any host works, because this document is the whole
contract. What is emphatically **in** scope is the step list, for the reason in
*The step ledger* below.

## Why there is no autonomy computation

Routines answer the autonomy question by not asking it. The issue-routing engine
they replaced derived how much autonomy an issue permitted by having a model
describe the work and running that description through a policy lattice — so it
needed a monotonicity guarantee, a claim schema, a downgrade ledger, and a
post-hoc radius tripwire to catch descriptions that were wrong.

An automation firing at 03:00 has already chosen its routine. Asking a model to
re-derive whether the work is autonomous adds a guess where there was a fact.

Autonomy is therefore a property of the routine, not of the issue. `plan`
produces a **draft** PR because a plan is a proposal; the others produce a ready
PR because human review *is* the gate.

## The four routines

| Routine | Selects on kind label | Terminal artifact | Issue linkage | Status |
|---|---|---|---|---|
| `plan` | `design-decision` | **draft** PR carrying a spec | `Refs #N` | active |
| `fix` | `bug`, `tech-debt` | ready PR | `Closes #N` | active |
| `improve` | `enhancement`, `documentation` | ready PR | `Closes #N` | active |
| `build` | any kind, **and** a merged linked plan, **and** no open blockers | ready PR | `Closes #N` | **deferred — see below** |

### `build` is deferred and must not be scheduled

`build`'s selector needs `blockedBy` read through `/task-registry`, and the
GitHub provider does not request that field — it hardcodes
`native_dependencies=False` on the deliberate grounds that claiming an inferred
link as native is the one thing capability degradation must never do.

- **#97** revisits that capability with a runtime probe.
- **#98** tracks the `build` routine itself.

Until both land, a `routine/build/...` branch parses and round-trips correctly
but no scheduler fires it. The branch parser is general over routine names, so
adding `build` never touches the regex — but it is not a documentation-only
change either. A new routine edits `DEFAULT_SELECTORS`, `CONTRACT_ROUTINES`, the
`[routines.selectors]` template block, and this document's step table. The regex
is general; the vocabulary is not, and the vocabulary is where the work is.

## Selecting an issue

### Kind precedence

An issue may carry more than one kind label. Precedence is a fixed order, first
match wins:

```
bug > design-decision > tech-debt > enhancement > documentation
```

**The chain orders provider label names — the left-hand keys of `[labels.kind]`
in the project's task-tracking configuration — not the registry's canonical
kinds.** That distinction is load-bearing. The canonical vocabulary is
`epic | feature | bug | decision | research | operational | task`; `tech-debt`
and `documentation` are absent from it and both normalize to `task`, so a chain
over canonical kinds could not tell them apart and could not rank them.

Every label in the chain is claimed by exactly one routine, so the chain's domain
and the union of the selectors are the same set.

### Priority is not a selector

`now` and `next` are the **priority** axis. They order candidates *within* a
routine's pool; they never select a routine. Measured against the pipeline repo,
9 of 28 open issues carried both a priority and a kind label — so a design that
selected on both axes had two routines claiming one issue in a third of all
cases. Ordering within a pool is what makes the selectors a total function.

### An unclassified issue belongs to nobody

An issue carrying no kind label is **not selected by any routine**. That is
correct rather than a gap: an unclassified issue has not been triaged. Each
routine reports the count of such issues so the gap stays visible.

### The vocabulary comes from configuration

Selector labels, the precedence order, and the claim label are read from the
project's task-tracking configuration, never hardcoded here. Hardcoding English
label names would reproduce, at six times the surface, the halt where a scheduled
run found zero eligible issues because a label had never been created.

A configured selector label that does not exist upstream is a **loud** failure:
non-zero exit naming the label. "Nothing matched" and "the vocabulary is wrong"
are different outcomes and must not share an exit code.

### Already-claimed and already-in-review issues are skipped

Disjoint selectors stop two *different* routines claiming one issue. They do not
stop two runs of the *same* routine overlapping. Before creating its branch, a
routine writes a **claim label** (configured; default `in-progress`) and skips
any issue that already carries one. `task-registry select` performs the skip
half; the write half is a tracker write and goes through `/task-registry` under
its normal write gate, like every other tracker write. No routine calls a
tracker's task API directly.

Every routine also excludes any issue that already has an **open linked pull
request** — from a `routine/` branch or from a human. The wider rule is the
deliberate one: an issue with a PR open against it is being worked on, and the
routine has nothing to add by opening a second one. That is a read rather than a
write, and it is strictly more accurate than closing the issue on PR creation
ever was: it also suppresses re-picking while a PR is still in review.

`select` refuses, loudly and non-zero, when it cannot evaluate this exclusion —
`closedByPullRequestsReferences` needs `gh` 2.73.0. An unanswerable exclusion
reads as "nothing is in flight", which is indistinguishable from a clean backlog
and re-picks every issue already under review.

## The branch carries the routine and the issue

`/wrap-up-session` opens the PR but runs in a later context and cannot know which
issue the session addressed. Rather than a state file, the routine encodes both
facts where every harness preserves them:

```
routine/<name>/<issue-number>-<slug>
```

`routine/plan/90-auxiliary-input-contract`, `routine/fix/97-recipe-morph-beats`.

The `routine/` namespace exists because anchoring on bare routine names does not
work. `feature/2024-refactor` correctly fails to match, but `fix/2024-refactor`
**matches** and yields issue 2024 — a human branch that never opted in, silently
linked to an unrelated issue. No human branch starts with `routine/`.

Both directions live in `.agents/skills/wrap-up-session/scripts/routine_branch.py`:
`format_routine_branch(routine, issue, slug)` creates the branch and
`parse_routine_branch(branch)` reads it back. Routines call the formatter rather
than building the string, so the serialization has a round-trip test. A branch
outside the namespace yields no routine and no issue, and wrap-up behaves exactly
as it does today — the convention is opt-in by shape.

## Issue closure happens on merge

The PR body carries `Closes #N` — `Refs #N` for `plan` — and the tracker closes
the issue when the PR merges. No routine closes an issue itself. This dissolves
four problems at once:

- The `plan` → `build` handoff stays possible: a merged plan PR leaves the issue
  open, now carrying a merged linked plan, which is exactly `build`'s selector.
  Closing on PR creation broke it, and `build`'s silence was indistinguishable
  from "nothing to do".
- No skill outside `/task-registry` needs a tracker's task API, so the provider
  coupling guard stays intact and Jira keeps working.
- "PR created but close failed" stops existing as a failure mode.
- An abandoned PR no longer leaves a closed issue with no fix.

## Step ledger

Each routine below names an ordered, **mandatory** step list. The routine writes
that list into `tasks/todo.md` and into the PR body — both, always — and a step
that could not run **keeps its row** carrying `skip: <reason>`.

Two sinks rather than one, because each is blind where the other sees. The index
is what a running session reads; the PR body is what a reviewer reads, and the
omission that caused #93 is invisible in exactly the second one.

Silent omission is the one thing that is never allowed. Pipeline #93 shipped
green with `/quality-gate` and the pre-push reviewers never having run — *not by
decision, by omission*. Human PR review is a real backstop for bad code and no
backstop at all for an **absent gate**, because an absent gate leaves no trace in
the diff a human reads. A materialized row does.

Steps marked **non-skippable** may still fail to run, but they may never be
dropped: their row reaches `tasks/todo.md` and the PR body either executed or
carrying its reason.

### The shared spine

Every routine runs the same five steps. Only the work in the middle differs, so
the spine is stated once — a gate written out per routine is a gate that gets
added to two tables out of three, which is the omission-not-decision failure this
ledger exists to prevent, reproduced in the document that prevents it.

| # | Step | Gate |
|---|---|---|
| 1 | Read the candidate: `task-registry select --routine <name>`. It skips issues already carrying the claim label or any open linked PR, and reports how many open issues carry no kind label at all. It refuses non-zero if a selector label, the claim label, or the linked-PR capability is missing | — |
| 2 | Claim it: `task-registry claim <issue> --routine <name> --apply --approve`. Idempotent, and it refuses an issue belonging to another routine | — |
| 3 | Create the branch: `routine_branch.py format <name> <issue> <slug>` | — |
| 4 | **The routine-specific work.** See each routine below | — |
| 5 | `/wrap-up-session` — review passes, tests, and the pull request | **non-skippable** |

Step 5 is non-skippable for every routine without exception: it is the review
gate whose omission shipped #93 green.

Each routine below gives **only** its step 4 and any gate the spine does not
already carry.

### `plan` — steps

Selector: `design-decision`. Terminal artifact: a **draft** PR whose body carries
`Refs #N` and this step list.

| # | Step | Gate |
|---|---|---|
| 4 | `/plan` — write `specs/<feature>.md` and the task breakdown | **non-skippable** — the spec is the routine's entire artifact |

`/build` and `/quality-gate` are deliberately absent. `plan` produces a spec and
no implementation, so requiring them here would write a `skip:` row on every
single run — and a ledger that always reads `skip:` teaches a reader nothing,
which is exactly the failure this ledger exists to prevent.

### `fix` — steps

Selector: `bug`, `tech-debt`. Terminal artifact: a ready PR whose body carries
`Closes #N` and this step list.

| # | Step | Gate |
|---|---|---|
| 4a | `/debug` — root cause before code, for a `bug`; for `tech-debt`, read the item's evidence | — |
| 4b | `/build` — TDD against the issue's acceptance criteria | **non-skippable** — no fix ships without a failing test that now passes |
| 4c | `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside `/build` Phase 3; the row records where it ran) | **non-skippable** |

### `improve` — steps

Selector: `enhancement`, `documentation`. Terminal artifact: a ready PR whose body
carries `Closes #N` and this step list.

| # | Step | Gate |
|---|---|---|
| 4a | `/plan` — write or extend the spec, unless the issue already links a merged one | — |
| 4b | `/build` — TDD against the acceptance criteria | **non-skippable** |
| 4c | `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside `/build` Phase 3; the row records where it ran) | **non-skippable** |

### `build` — steps (deferred, #98)

Listed so the deferral is legible, not so it can be run. Identical to `improve`
except that step 4a reads the merged linked spec instead of writing one, and
selection additionally requires `blockedBy` to be empty — the capability #97
tracks.

## Edge cases

| Situation | Behavior |
|---|---|
| Branch outside `routine/` | No routine, no issue. Wrap-up opens a PR exactly as today. Not an error. |
| Branch inside `routine/`, issue missing or closed | Loud non-zero exit naming the issue — **and open the PR anyway**. A bad link must not discard the work. |
| Issue carries two kind labels | Precedence resolves it; the routine records which label matched. |
| Issue carries no kind label | Never selected. The routine reports the count so the gap is visible. |
| Issue already carries the claim label | Skipped as in-flight. |
| `gh` predates `closedByPullRequestsReferences` (< 2.73.0) | Asserted **once at routine start**, loudly. Every routine depends on the field; degrading per-routine gave two different answers to one missing capability. |
| No candidate found | Exit silently and successfully. A routine with nothing to do is not a failure. |
| A mandatory step could not run | Its row stays in `tasks/todo.md` and the PR body with `skip: <reason>`. |
