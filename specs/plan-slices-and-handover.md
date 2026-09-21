---
status: draft
implementation_paths:
  - .agents/skills/plan/SKILL.md
  - .agents/skills/plan/references/plan-block.md
  - .agents/skills/plan/references/sizing.md
  - .claude/skills/plan/**
  - .agents/skills/build/SKILL.md
  - .agents/skills/build/scripts/slice_surface.py
  - .claude/skills/build/**
  - .agents/skills/system-design-planning/SKILL.md
  - .claude/skills/system-design-planning/SKILL.md
  - .agents/skills/task-registry/SKILL.md
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/scripts/registry/model.py
  - .agents/skills/task-registry/scripts/registry/upsert.py
  - .agents/skills/task-registry/scripts/registry/detail.py
  - .agents/skills/task-registry/scripts/registry/providers/*.py
  - .claude/skills/task-registry/**
  - .agents/skills/auto-push/SKILL.md
  - .agents/skills/yolo/SKILL.md
  - .claude/skills/auto-push/SKILL.md
  - .claude/skills/yolo/SKILL.md
  - CLAUDE.md
  - tests/test-plan-slices.sh
  - tests/test-doc-conventions.sh
  - tests/test-skill-invocation-chain.sh
  - tests/test-task-registry.sh
  - tests/fixtures/plan-slices/**
---

# Spec: `/plan` writes session-sized slices with a declared surface, and `/build` hands over between them

> Origin: [#106](https://github.com/Joaovsales/jplugin-agentic-development/issues/106),
> plus the user's direction (2026-09-16) to restructure spec creation and
> planning the way Addy Osmani's `spec-driven-development` and
> `planning-and-task-breakdown` skills do, while staying consistent with this
> harness — `tasks/todo.md` as the index and session scratchpad, the task
> registry as the only path to GitHub Issues, specs as living contracts.
>
> Prerequisite design, referenced not restated: `specs/upsert-depends-on.md`
> (draft, critic pass applied, not built). Adjacent and **not** folded in:
> #97 (native GitHub `blockedBy`/`parent` probe), #98 (`build` routine),
> #81 (copy-verbatim step ledger for `/build`, `/quality-gate`, `/wrap-up-session`).

## Problem

`/plan` emits one flat, totally ordered list of `[ ] TDD:` rows. Three things
are missing, each groundable in the tree (`plan/SKILL.md:151-160`,
`build/SKILL.md:100-126`, `:138-142`):

1. **No unit sized to a session.** A row is sized to a *test*. Nothing says
   whether a 40-row plan is one session or forty.
2. **Dependency is list order.** `/build`'s parallel dispatch needs a partial
   order and reconstructs one from prose ("they modify different files"),
   mitigated by worktree isolation so a wrong guess becomes a merge conflict.
   It is still a guess about something `/plan` knew and discarded.
3. **No handover.** The delegation prompt is four items — enough to start a
   task, nothing to end one with. What a session learned is written nowhere
   the next agent reads.

`/system-design-planning` already solved the first two for architecture-shaped
changes: it emits slices under `### Slice n/total` headings with a registry
row per slice, and `/build` knows not to build the slice header
(`build/SKILL.md:94-98`). It did not solve the third, its slice table has no
file surface, and `/plan` — the entry point for everything below the
architecture bar, and the one `/auto-push`, `/yolo`, `/go feature`, and the
`improve` routine call — has none of it.

## Addy Osmani's structure, mapped onto this harness

Each element of the two upstream skills lands in exactly one place. Where the
harness already holds it, nothing moves; the table says so rather than adding a
second home.

| Upstream element | Home here | Change |
|---|---|---|
| Phase 0 — capability map, stable module ids, dependency direction, build order | `/system-design-planning` § *Build order* (architecture bar); **`/plan` § Build Order** (everything else) | **new in `/plan`** |
| Phase 1 — `ASSUMPTIONS I'M MAKING → correct me now` | `/plan` Step 1 ends with the assumption list; spec § Assumptions | **new** |
| Phase 1 — Objective, success criteria; "reframe vague instructions as success criteria" | spec § Behavior, § Acceptance Criteria; a rule in Step 2 | rule added |
| Phase 1 — Commands, Project Structure, Code Style, Boundaries (Always / Ask first / Never) | project-level, not per-feature: `tasks/project-context.md`, `CLAUDE.md` § Clean Code, `.claude/project.md` § Surgical Changes / § Code Economy *Never-on-the-chopping-block*; `/build` pre-flight 5 discovers the runner | none — the spec template says where they live so nobody re-declares them per feature |
| Phase 1 — Testing Strategy | spec § Testing Strategy: each AC tagged `logic \| integration \| user-facing` | **moved upstream** from `/build` pre-flight 7, which now reads the tag and classifies only untagged ACs |
| Phase 1 — Open Questions | spec § Open Questions | **new**; `/yolo` answers them conservatively and records the pick |
| Phase 2 — `tasks/plan.md` | the spec's § Build Order — the spec doubles as the design document (user, #106 comment) | no `tasks/plan.md` |
| Phase 3 — task template: Acceptance, Verify, Files, Dependencies, Estimated scope | one **slice** row in § Build Order: ACs carried, Verify, **Surface**, **Blocked by**, Size | **new** |
| Phase 3 — "completable in one session", "≤ ~5 files", XS–XL table, "break down when…" | § Sizing rule — ceiling **and floor**, both derived from the surface | **new**; upstream has no floor |
| Step 5 — checkpoints every 2–3 tasks | a slice boundary *is* the checkpoint: full suite, surface check, handover, `pre-compact.sh` flush | reuses the task-boundary flush |
| "Never overwrite an incomplete plan" | `/plan` appends today; adds the in-place replacement rule `/system-design-planning` Step 8 already has | rule added |
| External tracker: one item per task, dependencies via the tracker's linking, plan doc keeps an index of ids | one `upsert` per slice through `/task-registry`; `(blocked-by:)` on the row; `depends-on:` / `parent:` in the record | **`--parent`, `--handover` new**; `--depends-on` per its spec |
| Gated workflow: a human reviews each phase | `/plan` gains a gate after Specify; the existing gate stays after Tasks | **D1** |
| Phase 4 — context-engineering: load the right spec sections and files, not the whole spec | `/build` delegation prompt: the slice's spec rows, its surface, its blockers' handovers | **new** |
| Parallelization: safe / sequential / contract-first | ready set from `blocked-by`; disjoint surfaces run in parallel; overlap without a blocker is a plan defect | **new** |

## Vocabulary

- **slice** — the session-sized unit of work. Issue #106 says "chunk"; this
  spec keeps **slice** because the harness already has it (`### Slice n/total`,
  the slice header rule in `/build`, `--derive-id design`, and the tests that
  pin the token). One name, two producers. **D2**
- **surface** — the repository paths a slice reads and edits, in the
  `implementation_paths` grammar (`specs/README.md`): repo-relative POSIX,
  `*`/`?` non-crossing, `**` crossing, never absolute or `..`.
- **ready set** — the slices whose every `blocked-by` is `[x]`.
- **handover** — the bounded record a finished slice leaves for whoever claims
  a slice it blocks.

## Behavior

### `/plan` — Specify, then Plan and Tasks, with a gate after each

Step numbers refer to the current `plan/SKILL.md`; steps not named are
unchanged.

**Step 1 — Interview** ends by printing the assumptions being made, in the
upstream form, and waits:

```
ASSUMPTIONS I'M MAKING:
1. …
→ Correct me now or I'll proceed with these.
```

**Step 2 — Write the spec.** The living-contract template gains four sections
and one rule. Sections, in order: Behavior · Inputs · Outputs · Edge Cases ·
**Assumptions** · **Open Questions** · **Testing Strategy** · Acceptance
Criteria · **Build Order** · Implementation Paths. A vague requirement is
rewritten as a measurable criterion before it enters § Acceptance Criteria
("faster" becomes a number), and the rewrite is shown to the user.

§ Testing Strategy is one line per AC: its number, its tag (`logic`,
`integration`, `user-facing`), and how it is verified (a test name, an
integration fixture, or an e2e walkthrough). `/build` reads the tag from here.

§ Build Order is the slice table, always present — a one-slice plan has a
one-row table:

```markdown
## Build Order

Sizing: <N> slices. Systems counted by <rule>. Ceiling: … Floor: …
Split: <none | slice X into X.1/X.2 — reason>. Merged: <none | Y+Z — reason>.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | <name> | <one sentence> | `path/**`, `tests/test-x.sh` | — | 1, 2 | `bash tests/test-x.sh` | S (1 system, 3 files, 2 ACs) |
| 2 | <name> | … | … | 1 | 3 | … | M (…) |
```

- **Slice names are frozen** at Gate A; a rename after filing retires the old
  task explicitly (the `/system-design-planning` rule).
- **Surface** is a subset of the spec's `implementation_paths`; the union of
  all surfaces covers every path the plan edits. A slice whose surface names
  a path outside `implementation_paths` is a spec defect and `/plan` fixes the
  frontmatter before Gate A.
- **Blocked by** lists slice numbers. Two slices with overlapping surfaces
  must have one blocking the other, directly or transitively; `/plan` refuses
  to reach Gate A while an unordered overlap or a cycle exists, naming the
  slices.
- **Size** is stated with the three counts it derives from.

**Gate A — after the spec.** Print `✓ Spec written: <abs path>` and ask:

> "Does this spec — behavior, assumptions, and build order — match what you
> want? Confirm with **'y'** and I'll write the TDD tasks."

**Step 3 — Write the plan.** The `## Plan:` block follows the grammar in
`plan/references/plan-block.md`, which `/system-design-planning` Step 8 cites
instead of carrying its own copy; a test pins the two skills' examples equal.

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
> Sizing: <N> slices — ceiling <…>, floor <…>
> Approved <YYYY-MM-DD> by <who>

### Slice 1/<N> — <name>
- [ ] <name> <!-- task-id: plan.<id> --> — <delivers> (blocked-by: plan.<id>)
  [ ] TDD: <test that pins AC 1> -> <minimal implementation>
  [ ] TDD: <test that pins AC 2> -> <minimal implementation>
```

The `- [ ]` row is the registry's row for the slice: compact fields only
(`/task-registry` Iron Law 4), `(blocked-by: …)` in the form `DEPS_RE` already
parses, no surface — the surface lives once, in the spec's table, and `/build`
reads it there by slice number and name. `> Spec:` stands alone on its line.
If a `## Plan: <feature>` block already exists with `[ ]` rows: same feature
being replanned → replace its `### Slice` sections in place; different feature
→ append. Never two blocks for one feature.

**Gate B — after the tasks** is today's confirmation ("Does this spec and plan
meet your requirements? … 'y'"), unchanged in wording so `/auto-push` keeps
matching it.

**Step 6 — Register.** After Gate B, one `upsert` per slice in build order,
`--derive-id plan --spec specs/<feature>.md --fold-title`, dry-run then
`--apply` under the project's write policy; each slice after the first passes
`--depends-on` with the ids the applied lines printed. When the plan came from
an issue (`/plan #N`, `/go #N`, a routine), every slice passes `--parent '#N'`.
The row seeded in Step 3 is refreshed in place. Nothing external is created
before Gate B — the existing "never creates an external issue implicitly" rule.

**Gate collapse for unattended callers.** `/yolo` and `/auto-push` already
override `/plan` steps through a table; both add a row: *Gate A — auto-confirm
and record `Gate A: auto-confirmed (<skill>)` in the plan block's header*.
`/auto-push`'s one human approval stays Gate B; the `improve` and `plan`
routines behave as `/yolo` does. **D1**

### Sizing rule

Stated once in `plan/references/sizing.md`, applied by `/plan`, and quoted in
the plan block's `> Sizing:` line so a reader can check it.

Three counts, all read off the surface after glob expansion against the tree:

| Count | Definition |
|---|---|
| **files** | paths the surface expands to |
| **systems** | distinct modules the surface spans. A module is the first path segment, or the second when the first is a container (`src`, `lib`, `app`, `packages`, `tests`, `.agents/skills`, `.claude/skills`, `.claude/hooks`). A skill's `.claude/` mirror is the same system as its `.agents/` original. |
| **ACs** | acceptance criteria the slice carries |

**Ceiling — split when any holds:** files > 8 · systems > 2 · ACs > 3 · the
slice changes a public interface (CLI flag, exported function, file format)
*and* a consumer of it in another system · the name needs "and".

**Floor — merge two slices when all hold:** one directly blocks the other with
nothing between · each is under half the ceiling on every count · the merged
slice is under the ceiling. Every boundary costs a handover, and a handover is
lossy by construction; the floor is what stops a 40-row plan becoming 40
handovers.

**Size labels** for the table and for the dispatch budget: S (≤ 3 files, 1
system, ≤ 2 ACs) · M (otherwise under the ceiling) · L (at the ceiling on one
count — allowed, flagged). XL does not exist: it is a split.

**Context budget** is not measurable at plan time. It is estimated from the
same surface — files to read, the slice's spec rows, the expected diff — and
expressed as the tool-call budget `/build` puts in the dispatch (S 15 · M 35 ·
L 50, `subagent-resilience.md` Rule 1). Because it is an estimate, the
overrun rule below is load-bearing, not defensive.

### `/build` — dispatch on the declared order, verify the surface, hand over

**Pre-flight** reads the spec's § Testing Strategy tags; step 7 classifies
only ACs without a tag. A plan whose `## Plan:` block has no `### Slice`
headings (every plan written before this spec) is read as **one implicit
slice** whose surface is the spec's `implementation_paths`, so every existing
plan still builds.

**Ready set replaces the independence guess.** Before dispatch, and after every
slice closes:

```bash
python3 .agents/skills/build/scripts/slice_surface.py ready \
  --index tasks/todo.md --spec specs/<feature>.md
```

It prints each ready slice with its surface, and every pair of ready slices
whose surfaces intersect. Disjoint ready slices dispatch in parallel with
`isolation: "worktree"` when they write files; an intersecting pair without a
blocker between them is a **plan defect**: `/build` serializes the pair in
table order, reports it, and does not guess. Slices with an open blocker wait.
`/build` no longer assesses independence from prose.

**Delegation prompt** carries, in addition to the four items today:

5. the slice's declared surface, with the rule *edit only inside it; a file
   you must touch outside it is reported on its own line as
   `[SURFACE] +<path> | reason: <one sentence>` and the work continues*;
6. the handover of every slice this one is directly blocked by, read through
   `task-registry show <id>` — one hop, because a handover folds forward what
   its author consumed;
7. the tool-call budget for the slice's size, with the escape hatch verbatim
   from `subagent-resilience.md` Rule 1, and the instruction to list unfinished
   `TDD:` rows under `## Not finished`.

**Surface check** runs when the slice's last `TDD:` row passes, before the
suite:

```bash
python3 .agents/skills/build/scripts/slice_surface.py check \
  --spec specs/<feature>.md --slice <n> --base <slice-base-sha>
```

It matches `git diff --name-only <base>..HEAD` against the declared surface
and prints `undeclared: <paths>` and `untouched: <globs>`; exit 0 when both
are empty, 1 otherwise. Both lists go into the handover. An undeclared path
that lies inside the surface of another slice **dispatched in parallel this
round** is a real conflict: `/build` stops that pair, merges the worktrees
serially, and records `conflict: <slice> ↔ <slice> on <path>` in both
handovers. Every other undeclared or untouched path is informational and is
surfaced in the Phase 4.5 batch alongside `[AMBIGUITY]` lines — never silent,
never blocking.

**Handover** is written when the slice closes, through the registry:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert plan.<id> --apply \
  --handover 'done: <what landed> (<short-sha>..<short-sha>)' \
  --handover 'learned: <constraint hit or assumption invalidated>' \
  --handover 'surface: undeclared <paths> | untouched <globs> | clean' \
  --handover 'next: <what the next slice must not re-derive>' \
  --handover 'open: <question left for a human, or none>'
```

Bounded: at most 12 lines, each one line, each opening with one of `done:`,
`learned:`, `surface:`, `next:`, `open:`, `split:`, `conflict:`. The registry
refuses a handover without a `done:` and a `surface:` line — a slice boundary
whose surface was never checked must be visible, not absent (#81's principle,
applied to this gate). The home is the task record: the local detail file
under `tasks/details/` when no tracker is configured, and the tracker body's
managed section when one is — where a human reads it beside the acceptance
criteria. It is **not** written into the spec (a handover is dated narrative;
the spec states present-tense facts) and **not** copied into the index row
(Iron Law 4). `show` renders it. **D3**

**Overrun splits; it never truncates.** When a dispatched agent returns with
rows under `## Not finished`, or the budget's escape hatch fired, `/build`:

1. marks the finished `TDD:` rows `[x]` and runs the surface check on what
   landed;
2. appends `### Slice <n>.1/<N> — <name> (remainder)` after the original
   slice, with a registry row `(blocked-by: plan.<original id>)`, the same
   surface, and the unfinished `TDD:` rows moved beneath it;
3. writes the original's handover with a `split: <reason> → plan.<remainder id>`
   line and closes it `[x]`;
4. files the remainder through `upsert` under the same write gate, and
   re-runs `ready`.

A slice header marked `[x]` while any of its `TDD:` rows is `[ ]` is the
forbidden state; Phase 6's persistence proof counts rows with
`^[[:space:]]*\[x\]` so nested rows are counted, and reports any slice in
that state as a build failure.

**Slice boundary is the checkpoint.** After the handover: full suite once,
centrally (`/build` Phase 1 rule 4), then the existing task-boundary flush
(`bash .claude/hooks/pre-compact.sh </dev/null`), then the next `ready`.

### `/task-registry` — three fields, one flag, no new command

- `--depends-on <id>` on `upsert`, exactly as `specs/upsert-depends-on.md`
  designs it (refuse a dangling id in dry run and apply; disclose metadata
  storage when the provider has no native dependency).
- `--parent <ref>` on `upsert`: records the origin issue. The provider's
  existing `link_parent` decides the form — native where the provider reports
  `native_hierarchy`, `parent:` metadata otherwise (`github.py:263-266`
  today; #97 flips it with no change here). Sub-issues on GitHub are therefore
  a #97 outcome, not a promise of this spec.
- `--handover <line>` on `upsert`, repeatable, line-per-entry like
  `--reproduction`: a `handover` tuple on `Task`, a `handover:` key in the
  metadata block, a `## Handover` managed section in the local detail file and
  the GitHub body (after *Evidence*), rendered by `show`. Re-running replaces
  the section; the field is **not** carried from the existing record when the
  flag is absent — a handover is the closing slice's statement, not an
  accumulating log. The prefix and line-count rules above are validated in the
  pre-config CLI block (D3 of the depends-on spec), exit 2 naming the line.

Every write stays behind `--apply` and the project's approval floor.

### `/system-design-planning`

Cites `plan/references/plan-block.md` and `sizing.md` instead of its own plan
block and `After:` prose; its § Build order table gains the `Surface` column;
Step 8 files sequentially with `--depends-on` and `--parent` (retiring its
`TODO(shortcut)`). Its gates, render, and critic pass are unchanged.

## Inputs

| Input | Source | Read through |
|---|---|---|
| Feature idea, backlog item, or issue `#N` | user, `tasks/backlog.md`, `/go`, a routine | as today; `#N` through `task-registry show` |
| The spec's `implementation_paths` and § Build Order | `specs/<feature>.md` | `slice_surface.py` |
| Slice rows and `(blocked-by:)` | `tasks/todo.md` | `registry.index.TaskIndex` |
| Blockers' handovers | task records | `task-registry show <id>` |
| Files a slice actually touched | `git diff --name-only <base>..HEAD` | `slice_surface.py check` |
| Dispatched agent's `## Not finished` and `[SURFACE]` lines | agent return | `/build` orchestrator |

## Outputs

| Output | Path | Consumer |
|---|---|---|
| Spec with Assumptions, Open Questions, Testing Strategy, Build Order | `specs/<feature>.md` | Gate A reviewer, `/build`, `/wrap-up-session` reconciliation |
| Plan block with `### Slice` headings and registry rows | `tasks/todo.md` | `/build`, the session banner, `/wrap-up-session` Step 2 |
| One task per slice with `depends-on`, `parent`, and later `handover` | local `tasks/details/` or the tracker, via `upsert` | `/build` (reads handovers), the `build` routine when #98 lands (reads `blocked-by`), humans |
| Ready set and overlap report | stdout of `slice_surface.py ready` | `/build` dispatch |
| Surface report | stdout of `slice_surface.py check`; handover `surface:` line | handover, Phase 4.5 batch |
| Remainder slice on overrun | appended to the plan block and filed | `/build` next round |

## Edge Cases

- **No tracker configured.** The local provider is canonical: `depends-on`,
  `parent`, and `handover` live in `tasks/details/<id>.md`; `(blocked-by:)`
  on the row; `ready`, `check`, dispatch and handover consumption all work.
  No sub-issues, as #106 AC8 states.
- **Tracker configured but unreachable.** `upsert` records locally and reports
  `publication pending`; `/build` continues from the local record; nothing is
  retried silently.
- **GitHub without native links** (every `gh` today; this machine's 2.76.2
  has no `parent` field). `parent:` and `depends-on:` are body metadata and
  the disclosure line says so. #97 makes them native without touching this
  spec.
- **Flat legacy plan** (no `### Slice` headings). One implicit slice, surface
  = `implementation_paths`; handover written at the end; no `ready` fan-out.
- **One-slice plan.** The table has one row; the handover is still written —
  it is what an interrupted build's next session reads.
- **Overlap without a blocker, or a cycle.** `/plan` refuses Gate A naming the
  slices; a plan that reaches `/build` with one anyway (hand-edited) is
  serialized in table order and reported, never guessed.
- **Surface names a path outside `implementation_paths`.** `/plan` extends the
  frontmatter before Gate A; the § Implementation Paths section gains the
  path's role.
- **Undeclared path touched.** Recorded in the handover and the Phase 4.5
  batch; STOP only when it lies inside a concurrently dispatched slice's
  surface. **Declared path untouched.** Recorded; informational — the first
  case #106 calls silent is now a line on disk.
- **Agent hangs instead of returning.** Unchanged: the budget and stall
  monitor in `subagent-resilience.md`; a degraded return with `## Not
  finished` is the split path above.
- **Remainder of a remainder.** `<n>.1` splits into `<n>.2`, blocked by
  `<n>.1`; a third split of the same slice halts with the circuit breaker's
  `⛔ HALTED` report — three overruns mean the sizing rule, not the budget, is
  wrong.
- **Handover missing `done:` or `surface:`, over 12 lines, or with an unknown
  prefix.** `upsert` exits 2 naming the line; nothing is written.
- **Session banner and `/go` lane blocks.** Nested rows already match the
  banner's `^[[:space:]]*\[` counts; lane blocks are numbered lines, not rows,
  and are untouched.
- **`/wrap-up-session`.** Its Session Summary carry-forward stays as the
  session-level record; slice handovers are the finer grain beneath it. Living
  spec reconciliation treats § Build Order like any other section: it states
  the current slices, and a slice retired or split is edited there in the
  same commit.

## Assumptions

1. "Slice" and #106's "chunk" are the same thing, and the harness keeps the
   existing name (**D2**).
2. The spec is the design document; there is no `tasks/plan.md`.
3. `/build` reading a slice's surface from the spec table (by number and name)
   is acceptable; the index row stays compact.
4. `specs/upsert-depends-on.md` is built as designed, as the first slice here,
   rather than re-specified.
5. Native GitHub sub-issues are out of scope (#97).

## Open Questions

None. D1, D2 and D3 were put to the user on 2026-09-16 and decided as
recommended; D7 follows from D3's direction (reuse the registry's machinery
rather than add a copy). The `sync-retire.py` half of the open task
`glob-matcher-shared-module` stays open — slice 4 consumes the shared matcher
from `spec-reconcile.py` only, because pulling `/sync` into the surface would
put the slice over the systems ceiling.

## Testing Strategy

| AC | Tag | Verified by |
|---|---|---|
| 1–6, 13–16 | logic | grep assertions in `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh`, parity |
| 7–9 | logic | `tests/test-plan-slices.sh` running `slice_surface.py` over fixtures under `tests/fixtures/plan-slices/` |
| 10–12 | integration | `tests/test-task-registry.sh` running `upsert` against the local provider and the `gh` mock |
| 17 | integration | one live `/plan` → `/build` run on a two-slice plan, recorded in `tasks/e2e-log.md` |

## Acceptance Criteria

1. `/plan`'s spec template carries, in order, Behavior, Inputs, Outputs, Edge
   Cases, Assumptions, Open Questions, Testing Strategy, Acceptance Criteria,
   Build Order, Implementation Paths; Step 1 ends with `ASSUMPTIONS I'M MAKING`
   and `Correct me now`.
2. `/plan` states the sizing rule with a ceiling and a floor, both derived from
   the surface, and the plan block's `> Sizing:` line quotes the rule applied
   and any split or merge.
3. `/plan` has a gate after the spec (Gate A) and the unchanged confirmation
   after the tasks (Gate B); `/yolo` and `/auto-push` document auto-confirming
   Gate A and recording it in the plan block; `/auto-push` still matches
   Gate B's wording.
4. `/plan` refuses Gate A on an overlapping surface pair with no blocker, a
   cycle, or a surface path outside `implementation_paths`, naming the slices
   or path.
5. The plan-block grammar lives in `plan/references/plan-block.md`; `/plan`
   and `/system-design-planning` both cite it; a test pins their examples
   equal; the registry row carries `(blocked-by: …)` in the shape
   `render_row` emits and no surface.
6. `/build` reads § Testing Strategy tags and classifies only untagged ACs;
   a plan block without `### Slice` headings builds as one implicit slice.
7. `slice_surface.py ready` prints the ready set and every intersecting pair
   among ready slices from a fixture index and spec; a slice with an open
   blocker is absent; an intersecting pair is reported, and `/build` documents
   serializing it in table order.
8. `slice_surface.py check` prints `undeclared:` and `untouched:` against a
   fixture repository, exit 0 only when both are empty; `/build` documents the
   parallel-conflict STOP and the informational path.
9. `/build`'s delegation prompt lists the surface with the `[SURFACE]` line,
   the direct blockers' handovers via `task-registry show`, and the size-based
   tool-call budget with the escape hatch.
10. `upsert --handover` stores a bounded, prefixed, line-per-entry field in
    the metadata block, the local `## Handover` section, and the GitHub body;
    `show` renders it; a handover without `done:` and `surface:`, over 12
    lines, or with an unknown prefix exits 2 naming the line; the field is not
    carried when the flag is absent.
11. `upsert --parent` records the origin through the provider's `link_parent`,
    native when reported and `parent:` metadata otherwise, with the disclosure
    line; `upsert --depends-on` meets `specs/upsert-depends-on.md`'s criteria.
12. Every new write is dry-run by default and honours `--apply` and the
    project's approval floor; the local provider is canonical with no tracker.
13. `/build` documents the split: finished rows `[x]`, a `(remainder)` slice
    blocked by the original with the unfinished rows, a `split:` handover line,
    the remainder filed; Phase 6 counts nested rows and reports a `[x]` slice
    with `[ ]` children as a failure; a third split of one slice halts.
14. `/build` writes the handover through `upsert`, never by editing a detail
    file or calling `gh`; the slice boundary runs suite, surface check,
    handover, then the shared flush.
15. `/system-design-planning`'s table has a `Surface` column, Step 8 files
    with `--depends-on` and `--parent`, and its `TODO(shortcut)` is gone.
16. `CLAUDE.md` § Workflow steps 1–3 describe Specify → Plan (slices) → Tasks
    with the two gates; `.agents/` and `.claude/` trees are byte-identical;
    `bash tests/run.sh` is green on CI.
17. One live two-slice `/plan` → `/build` run shows parallel dispatch of two
    disjoint slices, a handover read by a blocked slice, and a surface report,
    recorded in `tasks/e2e-log.md` with the commit sha.

## Build Order

Sizing: 6 slices. Systems counted by skill directory (a `.claude/` mirror is
its `.agents/` original). Ceiling: files > 8, systems > 2, ACs > 3. Floor: two
adjacent slices each under half the ceiling merge. Split: none. Merged: `--parent`
and `--handover` share `model.py`, `upsert.py`, both providers, `detail.py` and
the same test section, and neither alone reaches half the ceiling on files.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | `upsert --depends-on` | the flag per `specs/upsert-depends-on.md` slices 1–2 (ownership-aware merge, CLI, refusals, disclosure) | `.agents/skills/task-registry/scripts/task-registry.py`, `…/registry/upsert.py`, `.agents/skills/task-registry/SKILL.md`, `.claude/skills/task-registry/**`, `tests/test-task-registry.sh`, `tests/fixtures/task-registry/**` | — | 11 (depends-on half), 12 | `bash tests/test-task-registry.sh` | M (1 system, 6 files, 2 ACs) |
| 2 | `upsert --parent` and `--handover` | `Task.handover`, metadata key, managed sections in both providers, `show`, `--parent` through `link_parent`, validation in the pre-config block | `…/registry/model.py`, `…/registry/upsert.py`, `…/registry/detail.py`, `…/registry/providers/local.py`, `…/registry/providers/github.py`, `task-registry.py`, `task-registry/SKILL.md`, `.claude/skills/task-registry/**`, `tests/test-task-registry.sh` | 1 | 10, 11 (parent half), 12 | `bash tests/test-task-registry.sh` | L (1 system, 8 files, 3 ACs) — at the ceiling on files; flagged |
| 3 | `/plan` restructure | `references/plan-block.md`, `references/sizing.md`, the new template sections, Gate A, refusals, per-slice filing; `/system-design-planning` cites the references; `/yolo` and `/auto-push` gate rows | `.agents/skills/plan/**`, `.claude/skills/plan/**`, `.agents/skills/system-design-planning/SKILL.md`, `.claude/skills/system-design-planning/SKILL.md`, `.agents/skills/{yolo,auto-push}/SKILL.md`, `.claude/skills/{yolo,auto-push}/SKILL.md`, `tests/test-doc-conventions.sh` | — | 1, 2, 3, 4, 5, 15 | `bash tests/test-doc-conventions.sh tests/test-skill-parity.sh` | L (2 systems + 2 one-line callers, 3 ACs over the count — kept whole because the sections, gate and filing are one contract a reviewer reads together; flagged) |
| 4 | `slice_surface.py` | `ready` and `check`, over `registry.index.TaskIndex` and a shared `registry/globs.py` matcher that `spec-reconcile.py` also consumes (`sync-retire.py`'s copy stays for the open task `glob-matcher-shared-module`); fixtures | `.agents/skills/build/scripts/slice_surface.py`, `…/registry/globs.py`, `.agents/skills/wrap-up-session/scripts/spec-reconcile.py`, `.claude/skills/{build,task-registry,wrap-up-session}/**`, `tests/test-plan-slices.sh`, `tests/fixtures/plan-slices/**` | — | 7, 8 | `bash tests/test-plan-slices.sh tests/test-living-spec-reconciliation.sh` | M (2 systems, 6 files, 2 ACs) |
| 5 | `/build` on slices | ready-set dispatch, delegation items 5–7, surface check, handover write, split, implicit slice, Phase 6 counts, Testing Strategy tags | `.agents/skills/build/SKILL.md`, `.claude/skills/build/SKILL.md`, `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh` | 2, 3, 4 | 6, 9, 13, 14 | `bash tests/test-doc-conventions.sh tests/test-skill-invocation-chain.sh` | M (1 system, 4 files, 4 ACs — one over; the four are one skill's single rewrite and split would leave `/build` half-converted between slices) |
| 6 | Workflow text and live run | `CLAUDE.md` § Workflow 1–3, glossary terms via `/learn`, the two-slice e2e run | `CLAUDE.md`, `tasks/e2e-log.md`, `tests/test-doc-conventions.sh` | 3, 5 | 16, 17 | `bash tests/run.sh` | S |

Slices 1, 3 and 4 have disjoint surfaces and no blockers: they are the first
ready set and dispatch in parallel. Slice 2 follows 1 (same files). Slice 5
waits on 2, 3 and 4. Slice 6 closes.

## Decisions

D1, D2, D3 decided by the user on 2026-09-16, each as recommended. D4–D7 are
the author's calls, recorded so a reviewer can see them.

| # | Decision | Options | Recommended | Wrong when |
|---|---|---|---|---|
| D1 | Gates in `/plan` | two (after spec, after tasks) interactive, one unattended / one everywhere | **two interactive, collapsed for `/yolo`, `/auto-push`, routines** (decided) — the build order is the cheapest thing to review and the most expensive to get wrong; `/auto-push`'s contract ("the `y` was the only decision") is kept by collapsing Gate A there | the human finds two prompts per plan more friction than one bad build order costs; then one gate presenting spec and tasks together |
| D2 | Name of the unit | slice / chunk | **slice** (decided) — `/build`, `/system-design-planning`, `--derive-id design` and three tests already carry it; a second name for one thing is glossary debt | the user wants #106's vocabulary in the skills; then rename in both producers and the tests in slice 3 |
| D3 | Handover home | task record (local detail / tracker body) · spec · `tasks/todo.md` · a file under `tasks/` | **task record** (decided) — read by `show`, visible to a human on the issue, canonical locally with no tracker, round-trips through the managed-section machinery that already exists; the spec is present-tense and the index row is compact by law | the project wants handovers grep-able in one file without the registry; then `tasks/handover/<feature>.md` as a second sink, never the only one |
| D4 | Where the surface is stored | spec table only · also on the index row · a `surface` field on `Task` | **spec table only** — one declaration, three uses; the row stays compact; `/build` already reads the spec | `/build` stops reading specs; then a `Task.surface` field |
| D5 | Overrun | split into a remainder slice · truncate and report · extend the budget and retry | **split** — the remainder is filed, ordered and handed over like any slice; a truncation is #106's silent failure and a retry re-reads the same context | the overrun is a hang, not a budget exhaustion; then `subagent-resilience.md`'s retry-with-changed-strategy applies first |
| D6 | Handover carry on re-upsert | replace · append · carry when absent | **replace, not carried** — a handover is the closing statement of one slice; carrying it would let a stale handover survive a re-file | several sessions close one slice in turns; then `split:` lines chain the records instead |
| D7 | Glob matcher for `check` | shared `registry/globs.py` consumed by `spec-reconcile.py` too · third copy | **shared module** — the open task `glob-matcher-shared-module` names this exact risk, and a third copy would triple it | the shared module cannot ship in a syncable path; it can (`task-registry/scripts/registry/`) |

## Implementation Paths

- `.agents/skills/plan/SKILL.md` — Steps 1–3 and 6 as specified; Gate A; refusals
- `.agents/skills/plan/references/plan-block.md` — the one plan-block grammar both producers cite
- `.agents/skills/plan/references/sizing.md` — the counts, ceiling, floor, size labels and budgets
- `.agents/skills/build/SKILL.md` — ready-set dispatch, delegation items 5–7, surface check, handover, split, implicit slice, Phase 6 counts
- `.agents/skills/build/scripts/slice_surface.py` — `ready` and `check`
- `.agents/skills/system-design-planning/SKILL.md` — cites the shared grammar; `Surface` column; sequential filing with `--depends-on` and `--parent`
- `.agents/skills/task-registry/SKILL.md`, `scripts/task-registry.py`, `scripts/registry/{model,upsert,detail}.py`, `scripts/registry/providers/*.py` — `--depends-on`, `--parent`, `--handover`; `registry/globs.py`
- `.agents/skills/{auto-push,yolo}/SKILL.md` — the Gate A override row
- `.claude/skills/**` — byte-identical copies of every file above
- `CLAUDE.md` — § Workflow steps 1–3
- `tests/test-plan-slices.sh`, `tests/fixtures/plan-slices/**` — `ready` and `check` over fixtures
- `tests/test-doc-conventions.sh`, `tests/test-skill-invocation-chain.sh`, `tests/test-task-registry.sh` — the pins named in § Testing Strategy
