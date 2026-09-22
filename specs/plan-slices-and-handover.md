---
status: draft
implementation_paths:
  - .agents/skills/slice/**
  - .agents/skills/plan/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/system-design-planning/templates/architecture-spec-template.md
  - .agents/skills/brainstorm/SKILL.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/wrap-up-session/scripts/spec-reconcile.py
  - .agents/skills/task-registry/SKILL.md
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/scripts/registry/upsert.py
  - .agents/skills/task-registry/scripts/registry/globs.py
  - .agents/skills/yolo/SKILL.md
  - .agents/skills/auto-push/SKILL.md
  - .claude/hooks/session-start.sh
  - CLAUDE.md
  - README.md
  - tests/test-slice.sh
  - tests/fixtures/slice/**
  - tests/test-doc-conventions.sh
  - tests/test-skill-invocation-chain.sh
  - tests/test-task-registry.sh
---

# Spec: `/slice` breaks a spec into session-sized slices; `/plan` and `/system-design-planning` call it; `/build` hands over between them

> Origin: [#106](https://github.com/Joaovsales/jplugin-agentic-development/issues/106),
> the user's direction to restructure spec creation and planning the way Addy
> Osmani's `spec-driven-development` and `planning-and-task-breakdown` skills
> do, and a `/grilling` interview on 2026-09-21 that settled the design below
> and replaced the 2026-09-16 draft of this spec.
>
> Facts this spec rests on: `.claude/skills/` is a retired root (#156), so there
> are no copies to keep in step; `/grilling` is a model-invocable interview
> primitive that `/brainstorm` Step 3 already calls (#165); a row seeded with
> `(blocked-by: id)` already round-trips through `upsert` without a flag
> (`registry/index.py:165`, `registry/upsert.py:151`, `registry/model.py:240`).
>
> Adjacent and not folded in: #97 (native GitHub parent and dependency links),
> #98 (`build` routine), #81 (copy-verbatim step ledger),
> `specs/upsert-depends-on.md` (a flag nothing here needs).

## Decisions (interview, 2026-09-21)

Source is `user` when the user decided it in the interview, `assumed` when the
author picked it and says why, `open` when nobody has yet. `/plan` reads this
table before it interviews and asks only about `open` rows.

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where the shared "spec to slices" step lives | A new skill, `/slice`, that both planners invoke the way every skill invokes `/task-registry` | user | One owner; callers pass a spec path and know nothing about sizing, ordering or filing |
| 2 | What the module owns | Sizing, dependency order and its validation, the surface per slice, the plan-block grammar, filing through the registry, the handover schema. Callers own the interview, the spec depth, the human gate, and for the design skill the render and critic pass | user | The module runs on any spec with acceptance criteria and `implementation_paths`, whichever planner wrote it |
| 3 | Human gates | One per caller, on the spec plus its Build Order. TDD rows are a mechanical expansion of each slice's criteria and are not gated | user | Reverses the two-gate decision of 2026-09-16; the build order is what is cheap to review and expensive to get wrong |
| 4 | Handover | Kept, with two required facts: what landed, what the next slice must not re-derive | user | #106's third gap; a task record with criteria but no closing note does not fill it |
| 5 | Simplifications | No sizing floor, no size labels or per-size budgets, no overrun split into remainder slices, no parallel-conflict STOP, no per-criterion testing tags | user | Each was machinery for a case the gate or the plan-time refusal already covers |
| 6 | Where the handover lives | A `> Handover:` blockquote under the slice heading in the plan block, written and read by `/build` | user | Its only reader is the next slice, dispatched from the same file. Reverses the task-record decision of 2026-09-16 |
| 7 | `/slice` phases | `/slice <spec>` proposes and stops; `/slice <spec> --file` files after the caller's gate | user | The module cannot own a gate whose word differs per caller |
| 8 | Routing between the two front doors | `/plan` escalates to `/system-design-planning` when one of its three criteria holds; the design skill keeps its off-ramp | user | The criteria are stated once, and the information to decide first appears in `/plan`'s interview |
| 9 | `--parent` on `upsert` | Added now, through the existing `link_parent` | user | #97 flips it native later without touching callers |
| 10 | Name and shape | `/slice <spec> [--issue #N] [--file]` | user | Matches the unit's name; reads as a verb in the caller's text |
| 11 | How handovers reach the parent issue | A `## Handovers` section in the PR body that closes the issue, written by `/wrap-up-session` before its linkage check | assumed | The user asked for the handovers on the issue's closing record; the PR body is the write wrap-up already makes and the linkage check already guards, and it degrades to the commit message with no tracker |
| 12 | Interviews and their reuse | `/plan` does not invoke `/grilling`; `/grill-me` and `/brainstorm` are the user's choice before planning. `/plan` asks its own six questions, and when a spec already carries this table, or the conversation already ran `/grilling` to an empty frontier for this feature, it asks only the `open` rows and the gaps. `/system-design-planning` interviews through `/grilling`, mandatorily | user | A feature may be grilled or brainstormed and never built, or planned without ceremony; the architecture bar is where the extra rigor pays for itself |
| 13 | Where assumptions and open questions go | This table, through the `Source` column, instead of separate Assumptions and Open Questions sections | assumed | One table serves the human at the gate, `/plan`'s carry-forward and `/yolo`'s unattended picks; three sections would say the same thing three ways |

## Problem

`/plan` emits one flat, ordered list of `[ ] TDD:` rows. Nothing says how many
sessions the list is, `/build` guesses which rows are independent from prose,
and what a session learned is written nowhere the next agent reads (#106).
`/system-design-planning` already emits slices with a registry row each, and
`/build` knows not to build the slice header, so the harness has two planners
that differ only in how they write the spec and then do the same job twice with
different text. `/brainstorm` now interviews through `/grilling`, and a feature
that went through it is interviewed again by `/plan` from scratch.

## Addy Osmani's structure, mapped onto this harness

| Upstream element | Home here |
|---|---|
| Phase 0: capability map, dependency direction, build order | § Build Order of the spec, written by `/slice` |
| `ASSUMPTIONS I'M MAKING`, Open Questions | § Decisions rows with `Source` `assumed` and `open` |
| Objective, success criteria, "reframe vague instructions as success criteria" | § Behavior and § Acceptance Criteria; a rule in `/plan` Step 2 |
| Commands, Project Structure, Code Style, Boundaries | Project-level already: `tasks/project-context.md`, `CLAUDE.md`, `.claude/project.md`. Not repeated per feature |
| Task template: Acceptance, Verify, Files, Dependencies, Scope | One row of § Build Order: ACs, Verify, Surface, Blocked by, Size |
| "Completable in one session", "break down when" | § Sizing: one ceiling |
| Checkpoints | A slice boundary: suite, surface check, handover, flush |
| External tracker: one item per task, plan doc keeps the ids | One `upsert` per slice through `/slice --file`; ids on the plan-block rows |
| Human review per phase | One gate per caller, on spec plus Build Order |
| Context engineering: load the slice's sections and files | `/build`'s delegation prompt: the slice's rows, surface, and its blockers' handovers |

## Vocabulary

- **slice**: the session-sized unit of work; the name the harness already uses.
- **surface**: the repository paths a slice edits, in the `implementation_paths`
  grammar (`specs/README.md`).
- **ready set**: the slices whose every `blocked-by` is `[x]`.
- **handover**: the one-to-four-line note a closed slice leaves under its
  heading for the slices it blocks.
- **design tree**, **frontier**, **round**: as `tasks/concepts.md` defines them
  for `/grilling`.

## Behavior

### `/slice <spec> [--issue #N]`: propose

Reads the spec's § Acceptance Criteria, `implementation_paths` and § Decisions,
and the tree. Writes two things and stops.

**§ Build Order into the spec**, replacing the section in place when it exists:

```markdown
## Build Order

Sizing: <N> slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: <none | slice n: reason>.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | <name> | <one sentence> | `path/**`, `tests/test-x.sh` | — | 1, 2 | `bash tests/test-x.sh` | 3 files · 1 system · 2 ACs |
| 2 | <name> | … | … | 1 | 3 | … | … |
```

- Every AC appears in exactly one slice. The union of surfaces covers every
  path the plan edits; each surface is a subset of `implementation_paths`.
- Two slices whose surfaces intersect have one blocking the other, directly or
  transitively.
- **Sizing** is one ceiling, stated once in `slice/references/sizing.md`: split
  when files > 8, systems > 2, ACs > 3, when the slice changes a public
  interface and a consumer of it in another system, or when its name needs
  "and". Files and systems are counted off the expanded surface; a system is
  the first path segment, or the second under a container (`src`, `lib`,
  `.agents/skills`, `tests`); a skill's inventory rows (skills tables, session
  banner) count as that skill's system. A slice over the ceiling is allowed
  when the `Sizing:` line names it and says why; it is never silent.
- **Validation** runs before anything is written:
  `python3 .agents/skills/slice/scripts/slice.py validate --spec <spec>`
  refuses an intersecting pair with no blocker between them, a cycle, and a
  surface path outside `implementation_paths`, naming the slices or the path
  and exiting 1. `/slice` writes nothing on a refusal.

**The plan block into `tasks/todo.md`**, per `slice/references/plan-block.md`:

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
> Issue: https://github.com/<owner>/<repo>/issues/<N>

### Slice 1/<N> — <name>
- [ ] <name> <!-- task-id: plan.<id> --> — <delivers> (blocked-by: plan.<id>)
  [ ] TDD: <test that pins AC n> -> <minimal implementation>
  [ ] TDD: <test that pins AC m> -> <minimal implementation>
```

- The `- [ ]` row is the registry's row: compact fields only, `(blocked-by:)`
  in the form the index parses, no surface. The surface lives once, in the
  spec's table, and `/build` reads it there by slice number and name.
- Ids are minted by a dry-run `upsert --derive-id plan --spec <spec>
  --fold-title --title '<slice name>'`, so the `--file` phase refreshes the
  seeded row in place instead of appending. Slice names never start with `/`
  (Git Bash on Windows rewrites a leading `/name` into a path).
- The `[ ] TDD:` rows are written here, one or more per AC the slice carries.
  They are not the subject of the gate.
- `> Spec:` stands alone on its line. An existing `## Plan: <feature>` block
  with `[ ]` rows is replaced section by section; a different feature is
  appended. Never two blocks for one feature.
- `> Issue:` is written when `--issue` is given or the spec's origin line names
  one.

Required output: `✓ Build Order written: <abs spec path>`,
`✓ Plan written: <abs todo path>`, then `Caller gates before /slice --file.`

### `/slice <spec> --file [--approve]`: file

Refuses, naming the block, when the plan block has no `> Approved <date> by
<who>` line: nothing is filed before a human gate, and the line is the
caller's proof of one. Then one `upsert` per slice in build order:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert \
  --derive-id plan --spec specs/<feature>.md --fold-title \
  --title '<slice name>' --kind <feature|task> \
  --summary 'Slice <n>/<N> of #<issue>: <delivers>' \
  --criterion '<AC text>' \
  --evidence 'design: specs/<feature>.md § Build Order, slice <n>' \
  --parent '#<issue>'
```

Dry run first, then `--apply`; `--approve` only when the caller passed it,
carrying the reviewer's word into the write gate. `--parent` is passed when
the block has a `> Issue:` line. The seeded row is refreshed in place and its
`(blocked-by:)` marker is carried from the row. Every write honours the
project's approval floor; an unreachable tracker reports `local-pending` and
is never retried silently. Output: one `✓ Filed: <id> → <#N | local,
publication pending>` line per slice.

### `/plan`

Steps not named are unchanged.

**Step 1: Interview, carrying settled decisions forward.** `/plan` asks its
six stock questions itself and does not invoke `/grilling`. `/grill-me` and
`/brainstorm` are the user's choice before planning, and a feature may go
through either and never reach `/plan`. Before asking, `/plan` looks for the
settled tree:

- a `specs/<feature>.md` with a § Decisions table (a `/brainstorm` output), or
- a `/grilling` run in this conversation whose frontier is already empty for
  this feature.

When either exists it prints `DECISIONS CARRIED: <n> from <spec path |
conversation>` and asks only the `open` rows plus whatever the six questions
still leave unanswered. Settled rows are never re-asked. With neither, it
interviews as today and § Decisions is filled from the answers. A backlog item
pre-fills answers as today.

**Step 1.5: Escalate when the design bar is met.** When a settled answer shows
the change re-routes a call between components, adds or changes a persisted
entity or status field, or changes an external contract (the list in
`/system-design-planning` § When to Use, cited not restated), print
`Escalating to /system-design-planning: <criterion>` and invoke it with the
decisions so far; it does not re-ask them.

**Step 2: Write the spec.** Sections, in order: Behavior · Inputs · Outputs ·
Edge Cases · **Decisions** · Acceptance Criteria · Implementation Paths.
§ Decisions is the table above, filled from the interview: `user` rows from
answers, `assumed` rows for what `/plan` picked without asking, `open` rows
for what nobody decided. A vague requirement is rewritten as a measurable
criterion before it enters § Acceptance Criteria, and the rewrite is shown.
§ Build Order is not written here.

**Step 3: `Invoke /slice specs/<feature>.md [--issue #N]`.** Replaces the
hand-written plan block.

**Step 4: Gate.** Wording unchanged: "Does this spec and plan meet your
requirements? Once you confirm with **'y'**, I'll begin the TDD loop." On `y`,
write `> Approved <YYYY-MM-DD> by user` under the plan block's header lines.

**Step 6: `Invoke /slice specs/<feature>.md --file`.** Replaces the
hand-written `upsert`. Nothing external is created before Step 4.

**Unattended callers.** `/yolo`'s override table changes two rows: Step 1
runs no interview and every gap becomes an `assumed` row in § Decisions
(`open` rows are answered conservatively and recorded the same way); Step 4
writes `> Approved <date> by /yolo (unattended)` and proceeds. `/auto-push`
runs `/plan` as-is and still matches the Step 4 sentence.

### `/system-design-planning`

- **Step 1**: a spec with § Decisions is read; its `user` rows are constraints
  with source `user` and are not re-asked; its `open` rows seed Step 2.5.
- **Step 2.5: Interview through `/grilling`, mandatory.** After recon and
  before the spec, `Invoke /grilling` with the problem statement as the root
  and, as the seed frontier, the questions the architecture template asks
  (constraints and how a violation is detected, ownership, each boundary's
  outcomes and failure unit, illegal states and transitions) plus any `open`
  rows carried from Step 1. Facts come from the recon, decisions from the
  reviewer. The settled tree is written to the spec's § Decisions; what the
  reviewer left open stays an `inferred` constraint, which the skill already
  treats as a question to the reviewer. The design bar is where a second
  interview pays for itself, so this step has no opt-out beyond `/grilling`'s
  own one-question-at-a-time line.
- **Step 3**: the architecture template's own build-order table and "Slice
  criteria" list are removed; "contract exposed" is stated in the Delivers
  text of `/slice`'s table.
- **Step 3.5**: `Invoke /slice specs/<feature>.md --issue #N` before the
  render, so the HTML the reviewer approves carries § Build Order.
- **Step 8**: on the word **approved**, write `> Approved <date> by <reviewer>`
  and `Invoke /slice specs/<feature>.md --file --approve`. The
  `TODO(shortcut)` about ordering is gone.

### `/brainstorm`

Step 6's spec template gains § Decisions, filled from the tree Step 3 settled,
every row `user`. That is what lets `/plan` Step 1 carry them forward.

### `/build`

- **Pre-flight**: a `## Plan:` block with no `### Slice` headings is one
  implicit slice whose surface is the spec's `implementation_paths`, so every
  plan written before this spec still builds.
- **Ready set replaces the independence guess.** Before dispatch and after
  every slice closes:
  `python3 .agents/skills/slice/scripts/slice.py ready --index tasks/todo.md --spec <spec>`
  prints each ready slice with its surface and every intersecting pair among
  them. Disjoint ready slices dispatch in parallel with `isolation:
  "worktree"` when they write files. An intersecting pair without a blocker is
  a plan defect: serialized in table order and reported, never guessed.
- **Delegation prompt** carries, beyond today's four items: (5) the slice's
  surface, with the rule *edit only inside it; a file you must touch outside
  it is reported as `[SURFACE] +<path> | reason: <one sentence>` and the work
  continues*; (6) the `> Handover:` lines of every slice this one is blocked
  by, verbatim; (7) the tool-call budget and escape hatch from
  `subagent-resilience.md` Rule 1, and the instruction to list unfinished
  `TDD:` rows under `## Not finished`.
- **Surface check** when the slice's last `TDD:` row passes:
  `python3 .agents/skills/slice/scripts/slice.py check --spec <spec> --slice <n> --base <sha>`
  matches `git diff --name-only <base>..HEAD` against the declared surface and
  prints `undeclared: <paths>` and `untouched: <globs>`, exit 0 only when both
  are empty. The result goes into the handover and the Phase 4.5 batch. It is
  informational; nothing stops.
- **Handover**: `/build` writes a `> Handover:` blockquote under the slice
  heading, after its rows, one to four lines: what landed
  (`<short-sha>..<short-sha>`), what the next slice must not re-derive, then
  optionally the surface report and one open question. It is written for a
  one-slice plan too: it is what an interrupted build's next session reads.
- **Unfinished slice**: when the agent returns rows under `## Not finished` or
  the escape hatch fired, finished rows are marked `[x]`, the header and the
  remaining rows stay `[ ]`, the handover says `unfinished: <rows>`, and the
  slice is in the next `ready` set. No renumbering, no remainder slice. A
  header `[x]` with a `[ ]` child is the forbidden state; Phase 6 counts rows
  with leading whitespace before `[x]` so nested rows are counted, and reports
  the forbidden state as a build failure.
- **Slice boundary is the checkpoint**: full suite once, centrally; the
  handover; the task-boundary flush (`bash .claude/hooks/pre-compact.sh
  </dev/null`); the next `ready`.

### `/wrap-up-session`

When the branch's plan block carries `> Handover:` lines, the PR body gains a
`## Handovers` section, one `### Slice n/N — <name>` per slice with its lines,
written before the linkage check runs on the body. With no tracker the same
section lands in the commit message.

### `/task-registry`

`--parent <ref>` on `upsert`: records the origin through the provider's
`link_parent`, native where the provider reports `native_hierarchy`, `parent:`
metadata otherwise, with the existing disclosure line. Dry run by default,
`--apply` and the approval floor as for every write. `registry/globs.py` holds
the `implementation_paths` matcher that `spec-reconcile.py` carries today;
`slice.py` imports it. Repointing `spec-reconcile.py` and `sync-retire.py` to
it is the open task `glob-matcher-shared-module`.

## Inputs

| Input | Source | Read through |
|---|---|---|
| Feature idea, backlog item, or `#N` | user, `tasks/backlog.md`, a routine | `/plan` Step 0; `#N` through `task-registry show` |
| Settled decisions | `specs/<feature>.md` § Decisions, or the conversation's `/grilling` run | `/plan` Step 1, `/system-design-planning` Step 1 |
| ACs, `implementation_paths`, § Decisions | `specs/<feature>.md` | `/slice` |
| Slice rows and `(blocked-by:)` | `tasks/todo.md` | `registry.index.TaskIndex` inside `slice.py` |
| Blockers' handovers | `tasks/todo.md` `> Handover:` lines | `/build` |
| Files a slice touched | `git diff --name-only <base>..HEAD` | `slice.py check` |

## Outputs

| Output | Path | Consumer |
|---|---|---|
| Spec with § Decisions and § Build Order | `specs/<feature>.md` | the gate, `/build`, `/wrap-up-session` reconciliation |
| Plan block with `### Slice` sections, seeded rows, `> Approved` | `tasks/todo.md` | `/build`, the session banner |
| One task per slice with `parent` | local `tasks/details/` or the tracker | humans; the `build` routine when #98 lands |
| Ready set and overlap report | stdout of `slice.py ready` | `/build` dispatch |
| Surface report | stdout of `slice.py check`; the handover | `/build` Phase 4.5 |
| `> Handover:` per closed slice | `tasks/todo.md` | the slices it blocks; `/wrap-up-session` |
| `## Handovers` | PR body | the parent issue's readers |

## Edge Cases

- **No tracker.** `--file` records locally; `ready`, `check`, dispatch and
  handovers all work from `tasks/todo.md`. No parent link; #106 AC8 holds.
- **Tracker unreachable.** `local-pending`, reported, never retried silently.
- **GitHub without native links** (every `gh` today). `parent:` is body
  metadata with the disclosure line; #97 makes it native without touching this
  spec.
- **Flat legacy plan.** One implicit slice; handover written at the end.
- **One-slice plan.** A one-row table; the handover is still written.
- **`--file` without `> Approved`.** Refused, naming the block.
- **Hand-edited plan with an unordered overlap.** `ready` reports the pair and
  `/build` serializes it in table order.
- **Surface names a path outside `implementation_paths`.** `validate` refuses;
  the author extends the frontmatter and the § Implementation Paths section.
- **Undeclared path touched.** In the handover and the Phase 4.5 batch;
  nothing stops.
- **Agent hangs.** Unchanged: the budget and stall monitor in
  `subagent-resilience.md`; a degraded return is the unfinished-slice path.
- **`/plan` after `/brainstorm` in one conversation.** `DECISIONS CARRIED` from
  the spec; the frontier holds only `open` rows and gaps. The same feature
  brainstormed in an earlier session is carried from the spec alone.
- **`/plan` escalates after a spec was written.** The design skill reads the
  spec's § Decisions and proceeds to recon.
- **`/plan` with no prior grilling or brainstorm.** Interviews as today; no
  `DECISIONS CARRIED` line; § Decisions is filled from the answers.
- **`/grilling` fails to load in `/system-design-planning`.** Step 2.5 asks
  its seed questions in one round in the `❓` / `➡️` format anyway (the
  `/brainstorm` Step 3 fallback) and says the primitive did not load.
- **Session banner and lane blocks.** Nested rows and `>` lines already fall
  outside the banner's row counts and the lane grammar.

## Acceptance Criteria

1. `slice.py validate` exits 1 naming the slices for an intersecting pair with
   no blocker and for a cycle, and naming the path for a surface outside
   `implementation_paths`; exit 0 on a fixture that passes all three.
2. `slice.py ready` prints the ready set with surfaces and every intersecting
   pair among ready slices from a fixture index and spec; a slice with an open
   blocker is absent; a plan block without `### Slice` headings yields one
   implicit slice whose surface is `implementation_paths`.
3. `slice.py check` prints `undeclared:` and `untouched:` against a fixture
   repository and exits 0 only when both are empty; it imports the matcher
   from `registry/globs.py`, whose rejections of absolute, `..`, backslash and
   unsupported-glob patterns are pinned.
4. `.agents/skills/slice/SKILL.md` exists, model-invocable, `harness:
   universal`, with `references/plan-block.md` and `references/sizing.md`; the
   skill is listed in `CLAUDE.md`, `README.md` and the session banner; the
   ceiling is stated once and no floor or size label appears.
5. `/slice <spec>` documents writing § Build Order in place and the plan block
   per the grammar, minting ids by dry-run upsert, writing TDD rows under each
   slice, refusing on a `validate` failure, and stopping with `Caller gates`.
6. `/slice --file` documents the `> Approved` refusal, one upsert per slice in
   build order with `--parent` when `> Issue:` is present, `--approve` only
   when the caller passed it, and the `✓ Filed:` line.
7. `upsert --parent '#N'` records a native parent on the local fixture and
   `parent:` metadata plus the disclosure line on the GitHub fixture; dry run
   by default; `SKILL.md` documents the flag.
8. `/plan` Step 1 keeps its six questions, contains no `Invoke /grilling`
   line, names `/grill-me` and `/brainstorm` as the user's optional
   precursors, and states the `DECISIONS CARRIED` rule; Step 1.5 has the
   `Escalating to /system-design-planning` line; Step 2's template has the sections in order with § Decisions and its
   three sources; Steps 3 and 6 have `Invoke /slice` lines; Step 4's sentence
   is unchanged and writes the `> Approved` line.
9. `/yolo`'s override table carries the two new rows; `/auto-push` still
   contains the Step 4 sentence verbatim.
10. `/system-design-planning` Step 1 names § Decisions; Step 2.5 has an
    `Invoke /grilling` line with its seed questions and the not-re-asked rule
    (pinned in the invocation-chain test beside `/brainstorm`'s); the
    template's own build-order table and "Slice criteria" are gone; Steps 3.5
    and 8 have `Invoke /slice` lines; no `TODO(shortcut)` remains.
11. `/brainstorm` Step 6's template carries § Decisions with the `Source`
    column.
12. `/build` documents the implicit slice, the `ready` call replacing the
    independence assessment, delegation items 5 to 7, the `check` call at slice
    close, the `> Handover:` write with its two required facts, the
    unfinished-slice rule, and the nested Phase 6 count with the forbidden
    state.
13. `/wrap-up-session` documents the `## Handovers` section before the linkage
    check.
14. `CLAUDE.md` § Workflow steps 1 to 3 describe Specify (optional
    `/grill-me` or `/brainstorm` first, decisions carried; `/grilling`
    mandatory at the design bar) → Slice → one gate → Build with handovers;
    `tasks/concepts.md` defines slice, surface, ready set and handover; `bash
    tests/run.sh` is green on CI.
15. One live two-slice `/plan` → `/build` run shows `DECISIONS CARRIED`,
    parallel dispatch of two disjoint slices, a handover read by a blocked
    slice and a surface report, recorded in `tasks/e2e-log.md` with the commit
    sha.

## Build Order

Sizing: 7 slices. Ceiling: files > 8, systems > 2, ACs > 3. Over: slice 4
(3 systems: `/plan` plus two one-row override edits in `/yolo` and
`/auto-push`, kept together because the gate sentence and the override rows are
one contract a reviewer reads together).

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | slice script and shared glob matcher | `slice.py validate`, `ready`, `check`; `registry/globs.py` extracted from `spec-reconcile.py`; fixtures | `.agents/skills/slice/scripts/slice.py`, `.agents/skills/task-registry/scripts/registry/globs.py`, `.agents/skills/wrap-up-session/scripts/spec-reconcile.py`, `tests/test-slice.sh`, `tests/fixtures/slice/**` | — | 1, 2, 3 | `bash tests/test-slice.sh tests/test-living-spec-reconciliation.sh` | 5 files + fixtures · 3 systems (one file each in registry and wrap-up) · 3 ACs |
| 2 | slice skill | `SKILL.md`, `references/plan-block.md`, `references/sizing.md`, the three inventory rows | `.agents/skills/slice/SKILL.md`, `.agents/skills/slice/references/**`, `CLAUDE.md`, `README.md`, `.claude/hooks/session-start.sh`, `tests/test-doc-conventions.sh` | — | 4, 5, 6 | `bash tests/test-doc-conventions.sh` | 7 files · 1 system + inventory · 3 ACs |
| 3 | upsert parent flag | `--parent` through `link_parent`, disclosure, docs | `.agents/skills/task-registry/scripts/task-registry.py`, `.agents/skills/task-registry/scripts/registry/upsert.py`, `.agents/skills/task-registry/SKILL.md`, `tests/test-task-registry.sh` | — | 7 | `bash tests/test-task-registry.sh` | 4 files · 1 system · 1 AC |
| 4 | plan skill calls slice | Step 1 carry-forward without `/grilling`, Step 1.5 escalation, § Decisions template, `Invoke /slice` in Steps 3 and 6, `> Approved`; `/yolo` rows | `.agents/skills/plan/SKILL.md`, `.agents/skills/yolo/SKILL.md`, `.agents/skills/auto-push/SKILL.md`, `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh` | 2 | 8, 9 | `bash tests/test-doc-conventions.sh tests/test-skill-invocation-chain.sh` | 5 files · 3 systems (over, see above) · 2 ACs |
| 5 | design planning and brainstorm call slice | Step 1 reads § Decisions, Step 2.5 interviews through `/grilling`, template trimmed, Steps 3.5 and 8 invoke `/slice`; `/brainstorm` Step 6 § Decisions | `.agents/skills/system-design-planning/SKILL.md`, `.agents/skills/system-design-planning/templates/architecture-spec-template.md`, `.agents/skills/brainstorm/SKILL.md`, `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh` | 4 | 10, 11 | `bash tests/test-doc-conventions.sh tests/test-skill-invocation-chain.sh tests/test-grilling-adoption.sh` | 5 files · 2 systems · 2 ACs |
| 6 | build and wrap-up on slices | implicit slice, `ready`, delegation items, `check`, handover write, unfinished rule, Phase 6 count; `## Handovers` | `.agents/skills/build/SKILL.md`, `.agents/skills/wrap-up-session/SKILL.md`, `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh` | 1, 5 | 12, 13 | `bash tests/test-doc-conventions.sh tests/test-skill-invocation-chain.sh` | 4 files · 2 systems · 2 ACs |
| 7 | workflow text and live run | `CLAUDE.md` § Workflow, glossary terms through `/learn`, the two-slice e2e run | `CLAUDE.md`, `tasks/concepts.md`, `tasks/e2e-log.md`, `tests/test-doc-conventions.sh` | 2, 3, 6 | 14, 15 | `bash tests/run.sh` | 4 files · docs · 2 ACs |

Slices 1, 2 and 3 have disjoint surfaces and no blockers: they are the first
ready set. Slice 4 follows 2 (it cites the references), 5 follows 4 (shared
test files), 6 follows 1 and 5, 7 closes.

## Implementation Paths

- `.agents/skills/slice/SKILL.md`: propose and `--file`, the refusals, the outputs
- `.agents/skills/slice/references/plan-block.md`: the one plan-block grammar
- `.agents/skills/slice/references/sizing.md`: the ceiling and the counting rule
- `.agents/skills/slice/scripts/slice.py`: `validate`, `ready`, `check`
- `.agents/skills/task-registry/scripts/registry/globs.py`: the shared `implementation_paths` matcher
- `.agents/skills/wrap-up-session/scripts/spec-reconcile.py`: source of the matcher being extracted
- `.agents/skills/plan/SKILL.md`: Steps 1, 1.5, 2, 3, 4, 6 as specified
- `.agents/skills/system-design-planning/SKILL.md` and `templates/architecture-spec-template.md`: Steps 1, 3, 3.5, 8; the trimmed template
- `.agents/skills/brainstorm/SKILL.md`: Step 6 § Decisions
- `.agents/skills/build/SKILL.md`: ready set, delegation items 5 to 7, surface check, handover, unfinished slice, Phase 6 count
- `.agents/skills/wrap-up-session/SKILL.md`: `## Handovers`
- `.agents/skills/task-registry/SKILL.md`, `scripts/task-registry.py`, `scripts/registry/upsert.py`: `--parent`
- `.agents/skills/yolo/SKILL.md`, `.agents/skills/auto-push/SKILL.md`: the override rows and the unchanged gate sentence
- `.claude/hooks/session-start.sh`, `CLAUDE.md`, `README.md`: the inventory rows; `CLAUDE.md` § Workflow steps 1 to 3
- `tests/test-slice.sh`, `tests/fixtures/slice/**`: `validate`, `ready`, `check` over fixtures
- `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh`, `tests/test-task-registry.sh`: the pins named in § Acceptance Criteria
