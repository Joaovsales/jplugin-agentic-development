# The routine contract

> Defined by `specs/category-routines.md` and, for the producers,
> `specs/sweep-routines.md`. Read by `/wrap-up-session`, which parses the branch
> convention below and opens the terminal pull request.

A **routine** is a scheduled category of work. A **consumer** routine selects
issues by a single label axis, runs a named step list, and ends at a pull
request a human reviews. A **producer** routine selects nothing: it reads the
open backlog so it does not duplicate, runs an extensive verification engine,
files every verified finding as an issue through `/task-registry`, and ends at a
docs-only pull request carrying the session record.

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

## The routines

| Routine | Selects on kind label | Terminal artifact | Issue linkage | Status |
|---|---|---|---|---|
| `plan` | `design-decision` | **draft** PR carrying a spec | `Refs #N` | active |
| `fix` | `bug`, `tech-debt` | ready PR | `Closes #N` | active |
| `improve` | `enhancement`, `documentation` | ready PR | `Closes #N` | active |
| `simplify` | `simplify` | ready PR | `Closes #N` | active |
| `build` | any kind, **and** a merged linked plan, **and** no open blockers | ready PR | `Closes #N` | **deferred — see below** |
| `janitor` | — (producer; **files** `bug`) | ready, docs-only PR carrying the session record | `Refs #N` per filed issue | active |
| `architect` | — (producer; **files** `task` + `tech-debt`, or `design-decision`) | ready, docs-only PR carrying the session record | `Refs #N` per filed issue | active |
| `tidy` | — (producer; **files** `documentation`, or `task` + `tech-debt`; commits Tier 0 repairs) | ready PR carrying the session record and the Tier 0 repair commits | `Refs #N` per filed issue | active |

Every row is a **lane** — one file under `.agents/skills/task-registry/lanes/`
whose frontmatter carries the selector, the producer flag and the deferral, and
whose numbered steps are the routine's step 4. This table is a pinned mirror of
those files (`tests/test-routines-contract.sh`); `task-registry lanes` prints the
live one. The same files are what the interactive front door (the `go` skill)
matches a goal against, so a labelled issue and a typed goal that name the same
work run the same steps.

`plan`, `fix`, `improve`, `simplify` and `build` are consumers. `janitor`, `architect` and
`tidy` are producers — see *Producers* below. Consumers run on the **Builder** tier,
producers on the **Planner** tier; cadence is the operator's call, typically
daily for consumers and weekly for producers.

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
change either. A new routine is a new lane file with `routine:` set in
`.agents/skills/task-registry/lanes/` (specs/lane-catalogue.md), plus
`DEFAULT_KIND_PRECEDENCE` for any new selector label, this document's routine
table, `routine_branch.CONTRACT_ROUTINES`, and the template's `[routines.skills]`
block — each of the last three a mirror pinned to the catalogue by test. The
regex is general; the vocabulary is not, and the vocabulary is where the work is.

## Selecting an issue

### Kind precedence

An issue may carry more than one kind label. Precedence is a fixed order, first
match wins:

```
bug > design-decision > simplify > tech-debt > enhancement > documentation
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
  coupling guard stays intact and every tracker keeps working.
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
| 5 | `/wrap-up-session` — checks the quality receipt, tests, and the pull request | **non-skippable** |

Step 5 is non-skippable for every progressable routine run: it is the review
gate whose omission shipped #93 green. The one terminal before it is a fix
routine investigation escalation. `/debug` owns that registry call exactly once;
the retained non-zero result opens no PR and creates no PR-ledger row.

Each consumer routine below gives **only** its step 4 and any gate the spine
does not already carry.

### Crossing the plan handover

`/plan` and `/system-design-planning` end the planning session with a build
prompt and never build. A lane that chains a planner into `/build` crosses that
handover one of three ways:

- **A skill that owns a Step 6 override** — `/auto-push`, `/yolo`,
  `/make-it-simpler` — crosses on its own terms; none is restated here.
  `simplify` crosses through `/make-it-simpler` § *Overrides*, in every mode.
- **An unattended lane run with no owning skill** — the ownerless lanes are
  `improve`, `refactor` and `babysit`; unattended is § *Unattended detection*.
  The run prints no build prompt and `/build` runs in place, in the same
  session; its pre-flight runs `/slice <spec> --file` with no `--approve`, so
  the project's approval floor decides, as for `/yolo`. The same override
  covers `/system-design-planning`'s hand-over. It is the fourth named
  exception to the fresh-session rule.
- **An interactive lane run with no owning skill** — the handover is honoured:
  the build prompt stays the session's last message, the `go` skill appends
  ` — handed over: build prompt` to each lane line after the planner step, and
  its reply precedes the prompt. The build session runs those steps.

An in-place build still gets a fresh context for the code: `/build` (§ *Parallel
Dispatch Assessment*) dispatches every slice to a sub-agent when it runs in the
session that planned it. The `plan` lane stops at its planner, so none of this
applies to it.

### `plan` — steps

Selector: `design-decision`. Terminal artifact: a **draft** PR whose body carries
`Refs #N` and this step list.

Step 4 is the lane file `plan.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
plan` prints it. The rows are not restated here (specs/lane-catalogue.md).

`/build` and `/quality-gate` are deliberately absent. `plan` produces a spec and
no implementation, so requiring them here would write a `skip:` row on every
single run — and a ledger that always reads `skip:` teaches a reader nothing,
which is exactly the failure this ledger exists to prevent.

### `fix` — steps

Selector: `bug`, `tech-debt`. Terminal artifact: a ready PR whose body carries
`Closes #N` and this step list.

Step 4 is the lane file `fix.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
fix` prints it. The rows are not restated here (specs/lane-catalogue.md).
Its first step is `/debug <ref>`: `<ref>` is `#N` on a scheduled run and the goal
text when the interactive front door picked the lane — the only thing that differs between them.

### `improve` — steps

Selector: `enhancement`, `documentation`. Terminal artifact: a ready PR whose body
carries `Closes #N` and this step list.

Step 4 is the lane file `improve.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
improve` prints it. The rows are not restated here (specs/lane-catalogue.md).

### `simplify` — steps

Selector: `simplify`. Terminal artifact: a ready PR whose body carries
`Closes #N`, this step list, the before- and after-proof, `Behavior changes:`
and `Simplified:`.

Step 4 is the lane file `simplify.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
simplify` prints it. The rows are not restated here (specs/lane-catalogue.md).
Unlike the other consumers, the scheduled entry is `/make-it-simpler
--unattended`, and its **discovery precedes the spine**: it ranks, classifies
and sizes candidates and files them through `task-registry upsert` before spine
step 1 selects one, so the index rows that filing wrote are the routine
branch's first commit. A day that files only decisions and selects nothing
opens the docs-only record PR below instead; a day that files and selects
nothing exits 0 silently, with no branch.

### `build` — steps (deferred, #98)

Listed so the deferral is legible, not so it can be run. Identical to `improve`
except that step 4a reads the merged linked spec instead of writing one, and
selection additionally requires `blockedBy` to be empty — the capability #97
tracks.

## Producers

Producers never edit product code. `janitor` may carry verification-map
corrections its full pass proved, `tidy` carries its Tier 0 repairs to the
harness surfaces (specs/tidy-skill.md), and all three carry the session record
under `tasks/sweeps/`; nothing else reaches the diff. Its output is issues — one
`task-registry upsert --apply` per verified finding, ID derived from the
finding's file and title so a later run **updates** the same task rather than
minting a second one — and a docs-only PR whose body carries `Refs #N` for
every issue in the record's *Filed* section. Never `Closes`: nothing was fixed.

The branch number is a **run stamp** (`YYYYMMDD`), not an issue. The formatter
and parser treat it as any other positive integer; `/wrap-up-session` does not
look it up. `CONTRACT_ROUTINES` in `routine_branch.py` carries both names so the
branch formats, and the registry reads them as `routine: producer` lanes from the
lane catalogue, so `task-registry select` and `task-registry claim` refuse a
producer with exit 2 — it files issues, it does not select them — and a
`[routines.selectors]` key naming one is refused at load like any unknown routine.

### Producer spine

Stated once, like the consumer spine, and for the same reason.

| # | Step | Gate |
|---|---|---|
| 1 | `task-registry doctor` — records the destination policy the findings will take (local canonical, external issue, or publication pending). `janitor` additionally requires exactly one project-local `verify-<app>` skill: missing → loud non-zero naming `/create-verification-skill`, no branch, no PR | — |
| 2 | Create the branch: `routine_branch.py format <name> <YYYYMMDD> sweep`. A branch that already exists is a second run the same day: loud non-zero, no second branch | — |
| 3 | `/sweep --routine <name>` (`/tidy` for the `tidy` routine) — read the backlog, run the engine, verify, file, write the session record | **non-skippable** — the sweep is the routine's entire artifact |
| 4 | `/wrap-up-session` — checks the quality receipt, tests, and the pull request | **non-skippable** |

A clean sweep still writes the record and still opens the PR: the record is the
only place "every mapped feature was driven and nothing failed" is stated.

### `janitor` — steps

Lens: bugs. Engine: the full test suite plus `/maintain-verification-skill`'s
full pass, whose live pass drives every mapped feature under `/verify-evidence --scope
e2e` rules. Files as `bug`. Terminal artifact: a ready, docs-only PR whose body
carries `Refs #N` per filed issue and this step list.

Step 3 is the lane file `janitor.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
janitor` prints it. The rows are not restated here (specs/lane-catalogue.md).

### `architect` — steps

Lens: design. Engine: `/software-design-expert-review --scope tree` — the APOSD
red flags over the whole tree, not a diff. Files as `task` + `tech-debt`, or
`design-decision` when the proposed fix is a choice between designs. Terminal
artifact: as `janitor`.

Step 3 is the lane file `architect.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
architect` prints it. The rows are not restated here (specs/lane-catalogue.md).

### `tidy` — steps

Lens: harness hygiene. Engine: the eight `/tidy` checks — `suite`, `inventory`,
`retired`, `installed`, `refs`, `worktrees`, `strays`, `registers`
(specs/tidy-skill.md) — over the harness surfaces, never product code. Files
documentation drift as `documentation` and structural drift as `task` +
`tech-debt`, each carrying `discovered: tidy`. Unlike the other producers its
diff carries more than the record: every Tier 0 repair — a stray deleted, a
table row or banner line added, a moved reference repaired — is its own commit
on the routine branch. Terminal artifact: a ready PR titled
`chore(tidy): <YYYY-MM-DD>` whose body carries `Refs #N` per filed issue, the
Tier 0 commits by check name, and this step list. No `verify-<app>` skill is
required; step 1 is `task-registry doctor` alone, and in a fresh checkout the
`installed` and `worktrees` checks report *skipped* with a note, never clean.

Step 3 is the lane file `tidy.md` in `.agents/skills/task-registry/lanes/`: its numbered steps are this
routine's step list, its chain is derived from them, and `task-registry lanes
tidy` prints it. The rows are not restated here (specs/lane-catalogue.md).

## Wrap-up on a routine branch

Everything the wrap-up skill does only on a `routine/` branch or for an
unattended caller. An interactive session on an ordinary branch never reads
this section.

### Fix-escalation terminal

If a `routine/fix/` caller supplies a completed investigation escalation result,
preserve that non-zero terminal result and STOP: open no PR, write no PR ledger,
and do not repeat the registry command. Do not run the terminal PR assertion
(`/wrap-up-session` § *Terminal PR assertion*); the escalation is already the
retained, loud no-PR result. This exception applies only to the fix
routine's investigation path. Interactive wrap-up and deployment verification
keep their existing contracts.

The `simplify` routine's **scope stop** is the same kind of terminal: when
`/make-it-simpler <ref>` finds the claimed task significant, over the cap, or
no longer reproducing, it stops before any edit, non-zero, with the claim left
in place. Open no PR, write no PR ledger, and do not run the terminal PR
assertion; the one scope-stop line is the retained result.

### Step-ledger rows

Write the routine's executed step list into `tasks/todo.md`, one row per
mandatory step. A step that could not run **keeps its row**, carrying
`skip: <reason>` — retained, never deleted. Silent omission is the one thing
that is never allowed here, because a deleted row reads as a routine that never
had that gate, and an absent gate leaves no trace in the diff a reviewer reads.
Each routine's list is in § *Step ledger* above.

The same step list goes in the PR body — every mandatory step, and every
skipped one retained with `skip: <reason>`.

### What the branch tells you

A routine encodes the routine name and the issue number in the branch, under a
reserved namespace, because wrap-up runs in a context that never saw the issue:

```bash
python3 .agents/skills/wrap-up-session/scripts/routine_branch.py parse "$(git branch --show-current)"
```

Exit 0 prints `<routine> <issue>`. **Exit 3** means the branch is **outside the
`routine/` namespace** — no routine, no issue, and wrap-up behaves exactly as it
does today. That is the ordinary case and not an error; the convention is opt-in
by shape, so no existing workflow changes behavior.

Treat only 3 that way. Any other non-zero code is the script failing to run, and
reading that as "not a routine branch" is how a routine silently ships a PR with
no `Closes #N` and no `--draft`.

### Draft and linkage

| Branch | Flags | Title | Body carries |
|---|---|---|---|
| `routine/plan/<n>-<slug>` | `--draft` | conventional | `Refs #N` |
| `routine/janitor/<YYYYMMDD>-sweep` | none | `chore(sweep): janitor <YYYY-MM-DD>` (`— clean` suffix when nothing was filed) | step ledger, the record path `tasks/sweeps/<YYYY-MM-DD>-janitor.md`, and `Refs #N` for **every** issue in the record's *Filed* section — never `Closes` |
| `routine/architect/<YYYYMMDD>-sweep` | none | `chore(sweep): architect <YYYY-MM-DD>`, same suffix rule | as `janitor`, with the record at `tasks/sweeps/<YYYY-MM-DD>-architect.md` |
| `routine/tidy/<YYYYMMDD>-sweep` | none | `chore(tidy): <YYYY-MM-DD>` (`— clean` suffix only when nothing was filed **and** no Tier 0 repair was committed) | as `janitor`, with the record at `tasks/sweeps/<YYYY-MM-DD>-tidy.md` and the Tier 0 repair commits listed by check name |
| `routine/simplify/<n>-<slug>` | none | conventional | `Closes #N`, the before- and after-proof, `Behavior changes:` and `Simplified:` |
| `routine/simplify/<YYYYMMDD>-record` | none | `chore(simplify): record <YYYY-MM-DD>` | docs-only: the `tasks/todo.md` index rows, and `Refs #N` per filed issue — never `Closes` |
| any other `routine/<name>/<n>-<slug>` | none | conventional | `Closes #N` |
| outside `routine/` | none | conventional | whatever the session warrants |

A producer branch's number is a **run stamp** (`YYYYMMDD`), not an issue. It is
never looked up as one, so the "issue is missing or closed" report below does
not apply to it; the issues a producer PR references are the ones the session
record's *Filed* section lists, read from that file. When the record says
`Filed: none`, the body carries no `Refs` line and says so.

`--draft` is passed **when and only when the routine is `plan`**. A plan is a
proposal, so it opens as a draft; every other routine ends at a ready PR because
human review *is* the gate that the deleted policy lattice tried to compute.

The body carries the linkage and the tracker closes the issue **on merge**. No
step here closes an issue itself: that keeps the provider coupling guard intact
so every tracker keeps working, removes "PR created but close failed" as a
failure mode, and stops an abandoned PR from leaving a closed issue with no fix.
`plan` uses `Refs #N` rather than `Closes #N` precisely so a merged plan leaves
the issue open for the routine that builds it.

**If the branch is a routine branch but the issue is missing or closed**: report
it loudly, non-zero, naming the issue — and **open the PR anyway**. A bad link
must not discard the session's work.

### E2E handoff on `routine/fix`

On a `routine/fix/` branch, if `/verify-evidence --scope e2e` returns a structured blocked
outcome, return its exact command, evidence, and reproduction state to `/debug`'s
§ *Canonical unattended escalation owner*. That owner invokes the registry once;
the escalation is terminal for this run, so do not offer acknowledgement or
continue to the PR assertion.

### Unattended detection

The terminal PR assertion runs on unattended runs only. A run is unattended
when either holds:

1. The branch is a routine branch. Exit 0 means yes; exit 3 means no.
   `routine/` is a prefix, but only the parser knows which names under it are
   real — `routine/plna/90-x` is nobody's branch, and matching the prefix
   would read it as a routine run.

   ```bash
   python3 .agents/skills/wrap-up-session/scripts/routine_branch.py \
     parse "$(git branch --show-current)"
   ```

2. The caller declared it. `/yolo` and `/auto-push` each carry a
   **Terminal PR assertion — unattended** row in the override table they pass
   to wrap-up.
   Their branches are ordinary feature branches, so nothing about the branch name
   says a human stopped watching; only the caller knows, so only the caller can
   say.

What that changes is stated where it applies: `/wrap-up-session` § *Quality receipt*
(*Approving a HOLD*) and § *Terminal PR assertion*.

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
| `janitor` with no `verify-<app>` skill | Stops at doctor, loud non-zero, names `/create-verification-skill`. No branch, no PR. |
| Producer branch already exists today | Loud non-zero, no second branch. |
| Producer sweep verified nothing | Record written with `Filed: none`, PR opened, title suffixed `— clean`. |
| `tidy` repaired Tier 0 findings and filed nothing | Record written with `Filed: none`, PR opened **without** the `— clean` suffix — the diff is not empty. |
| A producer's local write fails | STOP — findings must not be lost. Pending *publication* never stops a run; a failed *record* does. |
