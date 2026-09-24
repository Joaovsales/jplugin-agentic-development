---
name: go
description: "Natural-language front door for interactive work. Give it a goal in plain words — a question about the code, a defect, a rename, a slowness, an open PR to drive green, or a feature — and it picks one lane from the shared lane catalogue, prints a [ROUTE] line, records the lane's steps in tasks/todo.md, and runs the existing skills that lane names. Use when starting any interactive task and the right slash command is not obvious. Triggers on: 'how does X work', 'this is broken', 'rename/extract/dedupe', 'this is slow', 'get PR #N green', 'add support for'."
argument-hint: "<goal — free text; may carry #issue, a PR URL or number, pasted error text, or a constraint>"
disable-model-invocation: false
harness: universal
---

# /go — Natural-Language Front Door

## Overview

`/go <goal>` is the one command to remember for interactive work. It matches
the goal to a lane, prints the route, records the lane's steps, and runs the
skills the lane names. It adds no review, build, verification, or confirmation
logic of its own: every gate the human meets belongs to a skill the lane
invokes (`/plan`'s "Confirm with 'y'", `/debug`'s root-cause prelude,
`/system-design-planning`'s **approved**). Every code-changing lane passes
through exactly one of them by construction.

A **lane** is one markdown file in the task-registry skill's `lanes/` directory
(specs/lane-catalogue.md). The same file is the routine the scheduler runs on a
labelled issue and the route this skill picks from a goal: its frontmatter
carries the cues `/go` matches and the selector labels the registry matches,
and its numbered steps are what both record. The scheduled router is
deterministic and wins wherever its fact exists; `/go` fills in only where there
is no label to read, and no routine host ever invokes it.

## The Iron Law

```
NOTHING HAPPENS BEFORE THE [ROUTE] LINE, AND /go ITSELF NEVER ASKS THE HUMAN A QUESTION
```

The line makes a misroute visible in the transcript the moment it happens, not
after the work. Questions belong to the chain skills, which already own them.

Matching is how the line is computed, not an action the law forbids: the two
registry commands in step 1 each read one fact and change nothing. Everything
else — reading the code, writing the lane block, invoking a skill — waits for
the line. A refusal (exit 2 from either command) is printed in place of the
line: the request was not routed, so there is no route to print.

## The Process

### 1. Match

**Issue reference first.** If the goal carries `#N` or a tracker URL the
registry understands, ask the deterministic router before reading the lanes:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py workflow '#N'
```

| Result | Route |
|---|---|
| exit 0, `routine:` names a routine | `lane=<routine>`, `chain=` the registry's chain — its skills, in its order, comma-separated as the `[ROUTE]` format requires. That routine is a lane in the catalogue; proceed into its first skill with `<ref>` = the issue reference. |
| exit 0, `routine:  none` (no kind label) | Untriaged. Match the rest of the goal text against the lanes; quote the registry's `routine:` line in `reason:`. |
| exit 1 | Unknown reference, closed issue, or the tracker did not answer. Say so, match the rest of the goal text, quote the reference in `reason:`. |
| exit 2 | Misconfigured tracker. Refuse the whole request: print the registry's message verbatim and name the configuration file (`task-registry doctor` reports which one resolved). A misconfigured tracker is never routed around. |

**Otherwise read the lane catalogue** and pick exactly one lane:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py lanes
```

It prints one block per lane: the lane's kind, its `cues:` — the goal phrases
that pick it — its effective chain, and what it ends with. Match the goal
against the `cues:` lines. A lane with no `cues:` line (`build`, the producers)
is never picked from a goal; it is reached only through a registry answer.
`lanes` reads no tracker, so a configuration fault never blocks a question
about how the code works; it exits 2 only when a broken shipped lane file makes
the catalogue itself unreadable, and that too is printed verbatim and never
routed around.

**Precedence when two lanes match.** `investigate` is decided first, by what
the human wants back: a goal that asks a question and no change is
`investigate` even when it pastes error text, and a goal that asks for the
error to go away is `fix`. Among the change lanes, `fix` outranks `perf`,
`perf` outranks `refactor`, and anything with a defect cue outranks `improve`.
`plan` is picked only when the goal asks for a spec or a decision and no
implementation. `none` is the fallback when nothing matches or the goal is too
large or unclear to be one lane. `reason:` names the tie it broke.

**Constraints travel.** On a goal that asks for a change, "don't change any
code yet" and "repro first" go into the first chain skill's problem statement,
never into a lane downgrade. A read-only goal that names an open bug issue
still runs `lane=fix`: `/debug`'s prelude is read-only until the human
confirms a candidate, so nothing is lost.

**Resolve the lane before writing anything.** Fetch the chosen lane's playbook:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py lanes <lane>
```

It exits 2, naming the skill, when a chain step is not installed under
`.agents/skills/` — the one canonical tree, and the same root the registry
resolves configured chains against. That refusal is printed in place of the route: a missing
step is found before work starts, not at the step. When the project's
`[routines.skills]` replaced the shipped chain, the output carries a `note:`
line and the steps shown are the shipped playbook; the effective chain is the
one to print.

**Emit the route**, on its own line, before any other action:

```
[ROUTE] lane=<lane> | chain=<skill, skill, ...> | reason: <one sentence>
```

`chain` is the effective chain the `lanes` output printed — the skill steps'
names, in order. For a registry-routed issue it is the registry's chain
verbatim; the two never disagree, because both read the same lane.

### 2. Record

Append one block to `tasks/todo.md`, the playbook's numbered steps copied
verbatim from the `lanes <lane>` output, with `<ref>` replaced by the goal (or
the issue reference, when the registry routed it):

```markdown
## Lane: investigate — why does the cache entry survive logout
1. Restate the question as a falsifiable claim and name the files it turns on
2. Read those files; quote the lines that answer it
3. Trace one live run if the code alone is inconclusive — skip: answered from source
4. Reply with the cited answer
5. `/checkpoint` — keep the answer on disk, only if the human asks — optional
```

Plain numbered lines. Never checkbox rows: `/build` executes every `[ ]` row
it finds in that file and the session banner counts them, so a checkbox lane
row would be dispatched as a task. The block is a record of what `/go` chose,
not a task list. A step the agent decides not to run keeps its line with
` — skip: <reason>` appended; it is never deleted. That append is the one
edit `/go` makes to a block after writing it — it never reorders, deletes, or
rewrites a line — and a second `/go` appends a second block and leaves the
first as written; its unfinished steps are the record of where that lane
stopped.

### 3. Run the chain

Follow the steps in order. They invoke the existing skills as the playbook
names them; those skills persist their own state (`[ ]` and `[~]` rows, specs,
debug documents, PRs) and stop at their own gates. An inline step (one that
does not open with a skill) is done in place. A step whose case does not apply
— `babysit`'s `/debug` when no job is red, `improve`'s `/plan` when
`/system-design-planning` wrote the spec — keeps its line with a `skip:`
reason, which is the step ledger's own convention. Resuming interrupted work
needs nothing from `/go`: the session banner already opens on the first
unfinished row the chain skills wrote.

### 4. Reply

Every lane ends with: the lane taken, the steps run and skipped, and the
evidence the playbook's *Reply* section names.

## Lanes

The lanes live in the task-registry skill, not here, because the registry is
what both routers already call and it validates every lane at load: the
filename is the name, a routine lane's chain must end at `/wrap-up-session`,
every frontmatter key is one of five, and no step may be a checkbox row. The
chain is derived from the steps — a step that opens with a backticked skill is
a skill step, unless it ends ` — optional` — so there is no second statement of
it to drift. `tests/test-lane-catalogue.sh` pins the shipped catalogue; this
skill's own test, `tests/test-go-lanes.sh`, pins that this file consults both
registry commands and carries no lane table of its own.

Lanes are project-configurable exactly as far as routines are: a project's
`[routines.skills]` replaces a consumer lane's chain, and `lanes` prints that
effective chain. Interactive-only lanes ship as written.

## When NOT to use

- **From a routine host.** `/sweep`, `/tidy`, `/yolo`, `/auto-push`, and the
  scheduled routines choose their lane from a label or a fixed pipeline. There
  is no prompt to match, and `tests/test-go-lanes.sh` pins that none of them
  names `/go`.
- **When the skill is already obvious.** Typing `/plan` or `/debug` directly is
  unchanged. `/go` is an entry point, not a wrapper the other skills depend on.

## Integration

- **Calls**: `task-registry workflow` for issue references, `task-registry
  lanes` for the catalogue, and whatever skills the chosen lane's steps name
  (`/debug`, `/plan`, `/build`, `/quality-gate`, `/receive-review`,
  `/wrap-up-session`, `/brainstorm`, `/system-design-planning`, `/checkpoint`).
- **Called by**: nobody. Interactive entry point only.
- **Writes**: one lane block per invocation in `tasks/todo.md`. Reads nothing
  back from it.
