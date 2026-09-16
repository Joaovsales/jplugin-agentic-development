---
name: go
description: "Natural-language front door for interactive work. Give it a goal in plain words — a question about the code, a defect, a rename, a slowness, an open PR to drive green, or a feature — and it picks one lane, prints a [ROUTE] line, records the lane's steps in tasks/todo.md, and runs the existing skills that lane names. Use when starting any interactive task and the right slash command is not obvious. Triggers on: 'how does X work', 'this is broken', 'rename/extract/dedupe', 'this is slow', 'get PR #N green', 'add support for'."
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

The scheduled side has its own router: an issue's kind label selects a routine
and the routine owns a fixed chain (`task-registry workflow`). That router is
deterministic and wins wherever its fact exists. `/go` fills in only where
there is no label to read, and no routine host ever invokes it.

## The Iron Law

```
NOTHING HAPPENS BEFORE THE [ROUTE] LINE, AND /go ITSELF NEVER ASKS THE HUMAN A QUESTION
```

The line makes a misroute visible in the transcript the moment it happens, not
after the work. Questions belong to the chain skills, which already own them.

## The Process

### 1. Match

**Issue reference first.** If the goal carries `#N` or a tracker URL the
registry understands, ask the deterministic router before reading the lane
table:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py workflow '#N'
```

| Result | Route |
|---|---|
| exit 0, `routine:` names a routine | `lane=<routine>`, `chain=` the registry's chain — its skills, in its order, comma-separated as the `[ROUTE]` format requires. Proceed into that chain's first skill. |
| exit 0, `routine:  none` (no kind label) | Untriaged. Match the rest of the goal text against the lane table; quote the registry's `routine:` line in `reason:`. |
| exit 1 | Unknown reference, closed issue, or the tracker did not answer. Say so, match the rest of the goal text, quote the reference in `reason:`. |
| exit 2 | Misconfigured tracker. Refuse the whole request: print the registry's message verbatim and name the configuration file (`task-registry doctor` reports which one resolved). A misconfigured tracker is never routed around. |

**Otherwise read the lane table** and pick exactly one lane.

| Lane | Cues in the goal | Playbook | Chain | Ends with |
|---|---|---|---|---|
| `investigate` | how does X work, why was Y built this way, is Z safe, compare A and B, no code requested | `lanes/investigate.md` | inline evidence gathering; `/checkpoint` only if the human asks to keep it | a cited answer, no diff |
| `fix` | broken, fails, wrong output, regression, error text pasted | `lanes/fix.md` | `/debug`, `/build`, `/quality-gate`, `/wrap-up-session` | PR |
| `refactor` | rename, extract, inline, dedupe, move, "no behaviour change" | `lanes/refactor.md` | inline before-proof, `/plan`, `/build`, `/quality-gate`, `/wrap-up-session` | PR whose body quotes the before and after proof |
| `perf` | slow, latency, memory, "takes N seconds", a profile attached | `lanes/perf.md` | inline baseline measurement, `/debug` for the cause, `/build`, `/quality-gate`, `/wrap-up-session` | PR whose body quotes baseline and after numbers |
| `babysit` | PR URL or number plus "get it green", "address the comments", "anything outstanding", CI red | `lanes/babysit.md` | `/receive-review` for review threads, inline CI log reading; then `/debug` for a red job or `/plan` for a requested change, `/build`, `/wrap-up-session` to push | PR merge-ready, or a named blocker |
| `feature` | add, change, support, new behaviour | none — direct route | `/brainstorm`, `/plan`, or `/system-design-planning`, chosen by CLAUDE.md § *Spec First*'s own criteria; that skill hands to `/build`, `/quality-gate`, `/wrap-up-session` itself | PR |
| `none` | no lane matches, or the goal is large or unclear ("rework the whole registry", "make it better") | none — direct route | `/brainstorm` | whatever `/brainstorm` produces |

**Precedence when two lanes match.** `fix` outranks `perf`, `perf` outranks
`refactor`, and anything with a defect cue outranks `feature`. `reason:` names
the tie it broke.

**Constraints travel.** "Don't change any code yet", "repro first", "no code
requested" go into the first chain skill's problem statement, never into a
lane downgrade. A read-only goal that names an open bug issue still runs
`lane=fix`: `/debug`'s prelude is read-only until the human confirms a
candidate, so nothing is lost.

**Resolve the chain before writing anything.** Every skill a playbook step
names must exist as `<name>/SKILL.md` under `.agents/skills/` or
`.claude/skills/` — the same two roots the registry resolves chains against,
because a downstream project may carry only the Claude Code copy. A step
naming a skill that is in neither refuses the lane, naming the playbook and
the skill, before the lane block is written — a missing step is found before
work starts, not at the step.

**Emit the route**, on its own line, before any other action:

```
[ROUTE] lane=<lane> | chain=<skill, skill, ...> | reason: <one sentence>
```

`chain` is the skill names the chosen playbook's steps invoke, in order. For a
registry-routed issue it is the registry's chain verbatim.

### 2. Record

Append one block to `tasks/todo.md`, the playbook's numbered steps copied
verbatim:

```markdown
## Lane: investigate — why does the cache entry survive logout
1. Restate the question as a falsifiable claim and name the files it turns on
2. Read those files; quote the lines that answer it
3. Trace one live run if the code alone is inconclusive — skip: answered from source
4. Reply with the cited answer
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

`feature` and `none` have no playbook. Their block is the chain from the table
row, one skill per numbered line, so the route is still on disk.

### 3. Run the chain

Follow the steps in order. They invoke the existing skills as the playbook
names them; those skills persist their own state (`[ ]` and `[~]` rows, specs,
debug documents, PRs) and stop at their own gates. Resuming interrupted work
needs nothing from `/go`: the session banner already opens on the first
unfinished row the chain skills wrote.

### 4. Reply

Every lane ends with: the lane taken, the steps run and skipped, and the
evidence the playbook's *Reply* section names.

## Playbooks

A playbook under `lanes/` is free markdown named for its lane: a heading, an
ownership sentence, numbered steps, and a *Reply* section. No frontmatter. The
chain is whatever skills the steps invoke, in order. The lane table's *Chain*
column restates it for the reader choosing a lane, and
`tests/test-go-lanes.sh` pins the two equal so a step added to one cannot
drift from the other. The same test pins the `fix` playbook to the registry's
`fix` chain, so the two routers cannot drift on the one lane they share.

`TODO(shortcut):` lanes are not project-configurable. There is no
`[lanes.skills]` section beside `[routines.skills]` — the registry validates
that block against the routine contract, requires every chain to end at
`/wrap-up-session`, and has no concept of a prompt, so `investigate` could not
live there. Project-level lane overrides are the upgrade path if a downstream
project asks.

## When NOT to use

- **From a routine host.** `/sweep`, `/yolo`, `/auto-push`, and the scheduled
  routines choose their chain from a label or a fixed pipeline. There is no
  prompt to match, and `tests/test-go-lanes.sh` pins that none of them names
  `/go`.
- **When the skill is already obvious.** Typing `/plan` or `/debug` directly is
  unchanged. `/go` is an entry point, not a wrapper the other skills depend on.

## Integration

- **Calls**: `/debug`, `/plan`, `/build`, `/quality-gate`, `/receive-review`,
  `/wrap-up-session`, `/brainstorm`, `/system-design-planning`, `/checkpoint`,
  and `task-registry workflow` for issue references.
- **Called by**: nobody. Interactive entry point only.
- **Writes**: one lane block per invocation in `tasks/todo.md`. Reads nothing
  back from it.
