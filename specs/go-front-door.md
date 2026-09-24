---
status: draft
implementation_paths:
  - .agents/skills/go/SKILL.md
  - AGENTS.md
  - README.md
  - tests/test-go-lanes.sh
  - tests/test-doc-conventions.sh
  - tasks/e2e-log.md
---

> **Rebased 2026-09-24 onto the plugin-era harness.** `.claude/skills/` is retired
> (#156), so "both trees" in AC2/AC3 reads as the one canonical tree; the
> session-start hook no longer lists skills, so AC5's banner pins are gone; and
> `CLAUDE.md` is a pointer to `AGENTS.md` (#177), so AC4's entry-point sentence
> lives in `AGENTS.md` § *Workflow* and the `/go` row in the README is rendered
> from the skill's frontmatter by `scripts/render-skills-table.py`. The lanes
> themselves moved to the registry's catalogue — see `specs/lane-catalogue.md`.

# `/go` — a natural-language front door over lane playbooks

> Source analysis: `cursor/plugins` `pstack` @ `main` (2026-09-15, MIT), the
> `/poteto-mode` skill and its 23 playbooks. Ideas and protocol only. No prose,
> playbook text, or file is copied from the source repo.
>
> Brainstormed 2026-09-15 on the `routing` branch. Option A of three; the sticky
> hook-based mode (Option C) is recorded below as the upgrade path, not built.
>
> **v3, 2026-09-16 — superseded in part by `specs/lane-catalogue.md`.** The five
> playbooks under `.agents/skills/go/lanes/`, the lane table in `SKILL.md`, the
> `feature` lane and the *No `[lanes.skills]`* decision below are replaced by the
> lane catalogue: twelve lane files under `.agents/skills/task-registry/lanes/`,
> one per lane, read by both routers, printed by `task-registry lanes`. `feature`
> is folded into `improve`; `none` becomes a file. AC2 and AC3 below are
> superseded by that spec's AC3 and AC7; the rest stand.
>
> **v2, 2026-09-16.** v1 wrapped the lanes in a protocol pstack does not have:
> a per-lane `start`/`propose` authority with its own `y` gate, playbook
> frontmatter declaring a `chain` the steps already named, a persistence state
> machine in `tasks/todo.md` with `continue` and `new task` phrases, and an
> eval sized for a subsystem. A design review against pstack's router found the
> core proportionate and the shell not, plus one defect: v1's lane rows used the
> checkbox shape `/build` consumes, so a lane that invoked `/build` would have
> had its own steps dispatched as tasks. v2 keeps the core and removes the
> shell. `/go` routes, records, and runs. It never asks; the skills it calls
> keep the gates they already have.

## Problem

An interactive session in this harness starts with the human choosing among
30 slash commands. The right entry point depends on facts the human has to hold
in their head: `/brainstorm` before `/plan` for design decisions,
`/system-design-planning` when a component boundary or data model changes,
`/debug` for a defect, `/plan` for a well-understood feature. A read-only
question, a refactor, a measured slowness, or an open PR that needs driving to
green has no entry point at all.

The scheduled side does not have this problem. An issue's kind label selects a
routine, and the routine owns a fixed skill chain declared in
`[routines.skills]` (`docs/task-tracking.md`, `config.py`). That router is
deterministic, tested, and refuses misconfiguration with distinct exit codes.
It cannot take a prompt as input, and it must not: the routine contract
(`wrap-up-session/references/routines.md` § *Why there is no autonomy
computation*) rejects model-judged autonomy for scheduled runs because "asking a
model to re-derive whether the work is autonomous adds a guess where there was a
fact." That decision stands. This spec adds an interactive router beside it,
never in front of it.

Two facts from the tree bound the design:

- Claude Code already routes organic prompts to skills by each SKILL.md
  `description`. The 2026-08-28 triggerability audit found the load-bearing
  gates never fire that way and are reached only because upstream skills invoke
  them (`tests/test-skill-invocation-chain.sh` header). Description routing is
  therefore not the mechanism; one explicit command is.
- `.agents/skills/` is canonical and byte-mirrored to `.claude/skills/`, copied
  wholesale to `~/.agents/skills` by `install.sh`, and read by Pi from there. A
  new skill reaches all three harnesses with no per-harness plumbing. A hook or
  extension does not.

## Behavior

`/go <goal>` is the one command a human needs to remember for interactive work.
It does four things, in order, and nothing else.

1. **Match.** Read the goal against the lane table below, pick one lane, and
   emit a single line before any other action:

   ```
   [ROUTE] lane=<lane> | chain=<skill, skill, ...> | reason: <one sentence>
   ```

   `chain` is the `/skill` names the chosen playbook's steps invoke, in order.
   The line exists so a misroute is visible in the transcript the moment it
   happens, not after the work.

   If the goal names an issue reference (`#N`, or a tracker URL the registry
   understands), run `task-registry workflow <ref>` first. When it returns a
   routine, use that routine's chain verbatim with `lane=<routine>`. The
   deterministic router wins wherever its fact exists; the matcher fills in only
   where there is no label to read.

2. **Record.** Append a lane block to `tasks/todo.md` (format in *Outputs*):
   the playbook's numbered steps, copied verbatim, as plain numbered lines. Not
   checkbox rows. Checkbox rows in that file belong to `/plan`, `/debug`,
   `/system-design-planning` and the registry, and `/build` executes every
   `[ ]` row it finds (`build/SKILL.md:92`). The lane block is a record of
   what `/go` chose, not a task list for `/build`. A step the agent decides not
   to run stays in the block with `— skip: <reason>` appended. It is never
   deleted.

3. **Run the chain.** Follow the steps. They invoke the existing skills
   (`/debug`, `/plan`, `/build`, `/quality-gate`, `/receive-review`,
   `/wrap-up-session`, ...) as the playbook names them. `/go` adds no review,
   build, verification, or confirmation logic of its own. Every gate the human
   meets is one an invoked skill already owns: `/plan`'s "Confirm with 'y'",
   `/debug`'s root-cause prelude that stops before touching a file,
   `/system-design-planning`'s **approved** against the rendered document. Every
   code-changing lane below passes through exactly one of them by construction.

4. **Reply.** Every lane ends with a reply that states the lane taken, the
   steps run and skipped, and the evidence the playbook demanded. The
   playbook's own *Reply* section names what is unique to it.

There is no mode, no stickiness, and no reserved phrase. Typing `/go` again
starts a new match and appends a new lane block; the previous block stays as
written. Resuming interrupted work needs nothing from `/go`: the chain skills
persist their own state as `[ ]` and `[~]` rows, and the session banner already
opens on the first of those.

### The lanes

| Lane | Cues in the goal | Playbook | Chain | Ends with |
|---|---|---|---|---|
| `investigate` | a question that wants an answer, not a change: how does X work, why was Y built this way, is Z safe, compare A and B | `lanes/investigate.md` | inline evidence gathering; `/checkpoint` only if the human asks to keep it | a cited answer, no diff |
| `fix` | broken, fails, wrong output, regression, error text pasted | `lanes/fix.md` | `/debug`, `/build`, `/quality-gate`, `/wrap-up-session` | PR |
| `refactor` | rename, extract, inline, dedupe, move, "no behaviour change" | `lanes/refactor.md` | inline before-proof (tests green, or a recorded characterization run), `/plan`, `/build`, `/quality-gate`, `/wrap-up-session` | PR whose body quotes the before and after proof |
| `perf` | slow, latency, memory, "takes N seconds", a profile attached | `lanes/perf.md` | inline baseline measurement, `/debug` for the cause, `/build`, `/quality-gate`, `/wrap-up-session` | PR whose body quotes baseline and after numbers |
| `babysit` | PR URL or number plus "get it green", "address the comments", "anything outstanding", CI red | `lanes/babysit.md` | `/receive-review` for review threads, inline CI log reading; then `/debug` for a red job or `/plan` for a requested change, `/build`, `/wrap-up-session` to push | PR merge-ready, or a named blocker |
| `feature` | add, change, support, new behaviour | none — direct route | `/brainstorm`, `/plan`, or `/system-design-planning` chosen by CLAUDE.md § *Spec First*'s own criteria; that skill hands to `/build`, `/quality-gate`, `/wrap-up-session` itself | PR |
| `none` | no lane matches, or the goal is large or unclear ("rework the whole registry", "make it better") | none — direct route | `/brainstorm` | whatever `/brainstorm` produces |

`fix` is the `fix` routine's chain, so an issue-referenced defect and a typed
one run identically. `refactor` goes through `/plan` because nothing else in its
chain writes the `[ ] TDD:` rows `/build` consumes, and `/plan` is where the
harness already asks the human before code changes. `babysit`'s first steps are
read-only; the moment it needs a code change it hands to `/debug` or `/plan`,
whose own rules apply.

`feature` and `none` have no playbook file. A playbook whose only content is
"apply the criteria CLAUDE.md already states" is a pass-through, so the table
row carries the route and the `[ROUTE]` line is still emitted. `none` is the
harness's existing answer to "we do not yet know what this is", and `/go` does
not invent a second one.

**Precedence when two lanes match.** `investigate` is decided first, by what
the human wants back: a goal that asks a question and no change is
`investigate` even when it pastes error text, and a goal that asks for the
error to go away is `fix`. Among the change lanes, `fix` outranks `perf`,
`perf` outranks `refactor`, and anything with a defect cue outranks `feature`.
The `reason:` names the tie it broke.

### Playbooks are free markdown

A playbook under `.agents/skills/go/lanes/` is a markdown file named for its
lane, with a heading, an ownership sentence, numbered steps, and a *Reply*
section. No frontmatter. The chain is whatever `/skill` names the steps invoke,
in order; nothing declares it a second time. The lane's identity is the
filename. This is pstack's playbook shape, and it is enough: the one property
v1 put in frontmatter that the body could not express, `authority`, no longer
exists.

### What this spec does not do

- **No confirmation of its own.** v1 gave four of six lanes a `propose`
  authority that asked "Run this lane? y" before the chain's first skill asked
  its own question. That doubled the gate on the three most common code paths
  for the benefit of one lane, and the pre-mortem's top risk is that nobody
  types `/go`. Authority is gone. `/go` behaves like pstack: read the goal, pick
  the lane, start. Irreversible actions are still guarded, by the skills that
  perform them.
- **No `[lanes.skills]` configuration section** *(superseded — see v3 note and
  `specs/lane-catalogue.md`; the objections below are attributes of routines, not of
  the lane as a class)*. The brainstorm recommended one
  so lanes would be project-configurable beside `[routines.skills]`. Reading the
  parser changed that: `[routines.skills]` is validated against
  `CONTRACT_ROUTINES`, every chain must terminate at `/wrap-up-session`, and the
  registry owns the file. `investigate` must not end at `/wrap-up-session`,
  `/go` takes a prompt the registry has no concept of, and a section the
  registry parses but never uses is a coupling with no caller. The `fix`
  playbook is pinned by test to equal `DEFAULT_ROUTINE_SKILLS["fix"]` so the two
  routers cannot drift on the one lane they share. `TODO(shortcut):`
  project-level lane overrides are the upgrade path if a downstream project asks.
- **No hook, extension, or per-turn injection, and no persistence protocol in
  their place.** Cursor gives pstack a harness-level Custom Mode and a per-turn
  reminder line; none of our three harnesses has that. v1 rebuilt it as an
  HTML-comment header in `tasks/todo.md` with `started=`/`closed=` rewrites and
  two reserved phrases. That was a harness feature reimplemented in a shared
  text file that already has six writers. v2 writes one plain block and reads
  nothing back. The upgrade path, if a month of use shows sessions losing
  their lane, is a `UserPromptSubmit` hook on Claude Code that prints the last
  lane heading, and nothing more.
- **No new agents, no new review logic, no change to model routing.** The lanes
  call existing skills; those skills dispatch their own sub-agents under the
  existing tier rules.
- **No scheduled use.** No routine host (`/sweep`, `/yolo`, `/auto-push`,
  `wrap-up-session/references/`, `.claude/hooks/`) invokes `/go`. A test pins
  this.

## Inputs

- `/go <goal>` — free text. May contain an issue reference, a PR URL or
  number, pasted error text, or a constraint ("don't change any code yet",
  "repro first"). A constraint is carried into the chain's first skill as part
  of its problem statement.
- `task-registry workflow <ref>` — consulted when the goal carries an issue
  reference; its exit codes are honoured (0 routine found, 0 untriaged or
  claimed with the printed reason, 1 unknown reference, 2 misconfigured).
- The five playbooks under `.agents/skills/go/lanes/`.

## Outputs

- One `[ROUTE]` line per match, on its own line, before any other action.
- `tasks/todo.md` gains a lane block, appended:

  ```markdown
  ## Lane: investigate — why does the cache entry survive logout
  1. Restate the question as a falsifiable claim and name the files it turns on
  2. Read those files; quote the lines that answer it
  3. Trace one live run if the code alone is inconclusive — skip: answered from source
  4. Reply with the cited answer
  ```

  Plain numbered lines, never checkbox rows. The session banner counts
  `^\s*\[ \]` and `^\s*\[~\]`, and `/build` executes every `[ ]` row; a lane
  block matches neither, by design. `/wrap-up-session` folds the block into
  `tasks/history.md` with the rest of the file as it does today. The
  ` — skip: <reason>` append is the one edit `/go` makes to a block after
  writing it; it never reorders, deletes, or rewrites a line.
- The chain's own artifacts (specs, `[ ] TDD:` rows, PRs, debug documents)
  unchanged and owned by the skills that write them.
- The closing reply described in *Behavior* step 4.

## Edge Cases

| Case | Behaviour |
|---|---|
| Goal matches two lanes (a slow path that is also wrong) | Precedence above. `reason:` names the tie it broke. |
| Goal is read-only but names an open bug issue | The registry's routine wins: `lane=fix`, chain `/debug ...`. The constraint ("no code requested") is passed into `/debug`'s problem statement. `/debug`'s prelude is read-only until the human confirms a candidate, so nothing is lost by not downgrading to `investigate`. |
| `task-registry workflow` exits 2 | `/go` refuses the whole request, prints the registry's message verbatim, and names the configuration file. A misconfigured tracker is never routed around. |
| `task-registry workflow` exits 1 | Unknown reference. `/go` says so and falls back to matching the rest of the goal text, with the reference quoted in `reason:`. |
| `/go` is typed while a previous lane block has unfinished steps | A new block is appended. The old block is left exactly as written; its unfinished steps are the record of where that lane stopped. `/go` never asks which one was meant. |
| A playbook step names a skill not on disk | Refused at match time, naming the playbook and the skill, before the lane block is written. Same shape as `_refuse_unterminated_chains` in the registry: a missing step is found before work starts, not at the step. |
| `tasks/todo.md` is being edited by a parallel session | Known hazard (memory: parallel sessions share one clone). `/go` appends one block and never rewrites the file. Out of scope to solve further. |
| The human types `/plan` or `/debug` directly | Unchanged. `/go` is an entry point, not a wrapper the other skills depend on. |
| A routine host invokes `/go` | Forbidden by test. The routine contract chooses the chain from the label; there is no prompt to match. |

## Acceptance Criteria

- [ ] **AC1** `.agents/skills/go/SKILL.md` exists with the lane table (lane, cues, playbook, chain, terminal artifact), the precedence rule, the `[ROUTE]` emission format, and one Iron Law: no action of any kind before the `[ROUTE]` line, and `/go` itself never asks the human a question.
- [ ] **AC2** Five playbooks exist under `.agents/skills/go/lanes/` (`investigate`, `fix`, `refactor`, `perf`, `babysit`), each free markdown with no frontmatter: a heading, numbered steps, and a *Reply* section. Every `/skill` named in any step resolves to `<name>/SKILL.md` under either skill root (`.agents/skills/` or `.claude/skills/` — a downstream project may carry only the Claude Code copy; the test checks the canonical root because the template carries both, byte-identical).
- [ ] **AC3** `tests/test-go-lanes.sh` pins: AC2's file set and skill resolution in both trees; that the `/skill` tokens in `fix.md`, in order of first appearance, equal `DEFAULT_ROUTINE_SKILLS["fix"]` read from `config.py`; that `investigate.md` does not name `/wrap-up-session`; that `refactor.md` and `babysit.md` name `/plan` or `/debug` before `/build`; and that no file under `.agents/skills/sweep/`, `.agents/skills/yolo/`, `.agents/skills/auto-push/`, `.agents/skills/wrap-up-session/references/`, or `.claude/hooks/` mentions `/go` as an invocation (the banner line from AC5 is the one allowed mention, matched by its exact text). `tests/test-skill-parity.sh` stays green (byte-identical `.claude/skills/go/`).
- [ ] **AC4** `CLAUDE.md` § *Workflow* gains one sentence before step 1 naming `/go <goal>` as the interactive entry point; the skills table gains a `/go` row; `README.md`'s skills table gains the same row. `tests/test-doc-conventions.sh` pins both rows and the sentence.
- [ ] **AC5** `.claude/hooks/session-start.sh` lists `/go` first in the skills block and the closing line reads "Use /go <goal> to start, or continue from tasks/todo.md." `tests/test-doc-conventions.sh` pins the closing line.
- [ ] **AC6** Live proof, recorded in `tasks/e2e-log.md`: (a) `/go how does task-registry choose a provider` emits `[ROUTE] lane=investigate`, appends a lane block with no checkbox rows, and ends with a cited answer and no diff; (b) `/go #<open issue carrying a kind label>` emits `lane=<that issue's routine>` with the registry's chain verbatim and proceeds straight into that chain's first skill, stopping only where that skill's own gate stops; if no labelled open issue exists at build time, the walkthrough instead records the untriaged path, the registry's "no kind label" message quoted and the fallback match on the goal text; (c) `/go rename _label_list to _csv_list` emits `lane=refactor` and stops at `/plan`'s own confirmation, not before. Each entry quotes the `[ROUTE]` line verbatim.
- [ ] **AC7** `/eval` mode A (triggerability) is run once on the finished skill with four organic prompts chosen to sit on the confusable boundaries: fix-vs-perf, refactor-vs-feature, investigate-vs-fix, and babysit. N = 2 per prompt. The result table is recorded in `tasks/e2e-log.md`. A miss is a cue defect: fix the lane table's cues and note the fix in the log. No miss blocks wrap-up, because every code-changing lane still passes through its first skill's own gate.
- [ ] **AC8** `bash tests/run.sh` is fully green, output recorded; `/quality-gate` run on all changed files.

## Implementation Paths

See frontmatter. `docs/task-tracking.md` and the registry's `config.py` are
deliberately **not** in the list: this spec reads `DEFAULT_ROUTINE_SKILLS` and
calls `task-registry workflow`, and changes neither. `/build`, `/plan`,
`/debug`, and `/receive-review` are not in the list either: `/go` writes
nothing they read and reads nothing they write.

## Testing approach

Static, in the tradition of `tests/test-model-tiers.sh` and
`tests/test-skill-invocation-chain.sh`: the contract is prose, so the test pins
that the prose is present, names only things that exist, and agrees with the
registry on the one lane they share. A green run means the lanes are written
down and internally consistent, not that an agent obeyed them. The behavioural
half is AC6 and AC7: a recorded live run and a small blinded triggerability
eval, both with their output in `tasks/e2e-log.md`.

## Pre-mortem carried forward

The one failure that was both likely and high-impact in the brainstorm was
"nobody types `/go`". Mitigations in this spec: the session banner leads with it
(AC5), CLAUDE.md names it as the entry point (AC4), and `/go` adds no friction
of its own to the common path. If after a month of use the history log shows
sessions still opening with `/plan` or `/debug` directly, that is data for the
hook-based upgrade path, not a reason to widen this spec.
