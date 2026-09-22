---
name: slice
description: Break a spec's acceptance criteria and implementation paths into session-sized slices — a Build Order table, a plan block in tasks/todo.md, and a build prompt — then, in a later session, file one task per slice through /task-registry. Use after a spec carries § Decisions and § Acceptance Criteria, or to refresh the Build Order and plan block after the spec changes.
argument-hint: "<spec path> [--issue #N] [--file [--approve]]"
disable-model-invocation: false
harness: universal
---

# /slice — Spec to Session-Sized Slices

## Overview

`/plan` and `/system-design-planning` both end with a spec that carries
acceptance criteria and `implementation_paths`. Neither planner owns sizing,
ordering, filing or the handover message — `/slice` does, once, and both
call it the way every planner calls `/task-registry`. `/slice <spec>`
**proposes**: it writes § Build Order and the plan block, prints the build
prompt, and stops. `/slice <spec> --file` **files**: it runs in the session
the build prompt started, never in the planning session that printed it.

## Inputs

The spec's § Acceptance Criteria, its `implementation_paths` frontmatter and
§ Decisions, and the current tree.

## Propose: `/slice <spec> [--issue #N]`

### 1. Validate before writing anything

```bash
python3 .agents/skills/slice/scripts/slice.py validate --spec <spec>
```

Refuses, naming the slices or the path, on: two slices whose surfaces
intersect with no blocker between them (directly or transitively), a cycle,
or a surface path outside `implementation_paths`. `/slice` writes nothing on
a refusal — fix the spec's table or paths and re-run.

### 2. Size the slices

One ceiling, counted the same way every time —
`.agents/skills/slice/references/sizing.md`. Every acceptance criterion
appears in exactly one slice; the union of surfaces covers every path the
plan edits.

### 3. Write § Build Order, replacing the section in place when it exists

```markdown
## Build Order

Sizing: <N> slices. Ceiling: per `slice/references/sizing.md`. Over: <none | slice n: reason>.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | <name> | <one sentence> | `path/**`, `tests/test-x.sh` | — | 1, 2 | `bash tests/test-x.sh` | 3 files · 1 system · 2 ACs |
| 2 | <name> | … | … | 1 | 3 | … | … |
```

A slice over the ceiling is allowed only when the `Sizing:` line names it and
says why; it is never silent.

### 4. Mint ids and write the plan block into `tasks/todo.md`

Ids are minted by a **dry-run** upsert per slice, never applied here:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert \
  --derive-id plan --spec <spec> --fold-title --title '<slice name>'
```

The dry run's id seeds the row below, so the `--file` phase refreshes it in
place instead of appending a stray row. Grammar and the fenced example below
must stay byte-for-byte identical to
`.agents/skills/slice/references/plan-block.md`.

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
> Issue: https://github.com/<owner>/<repo>/issues/<N>

### Slice 1/<N> — <name>
- [ ] <name> <!-- task-id: plan.<id> --> — <delivers> (blocked-by: plan.<id>)
  [ ] TDD: <test that pins AC n> -> <minimal implementation>
  [ ] TDD: <test that pins AC m> -> <minimal implementation>
```

- Slice names never start with `/` — Git Bash on Windows rewrites a leading
  `/name` into a path.
- An existing `## Plan: <feature>` block is replaced section by section, in
  place; a different feature is appended. Never two blocks for one feature.
- `> Issue:` is written when `--issue` is given or the spec's origin line
  names one. `> Spec:` stands alone on its line.
- The `[ ] TDD:` rows are written here, one or more per AC the slice
  carries. They are not what the human reviews; the Build Order is.

### 5. Print the build prompt and stop

The closing fenced block of § Build Order. Template must stay byte-for-byte
identical to `.agents/skills/slice/references/build-prompt.md`.

Build prompt:

```
Invoke `/build` for `specs/<feature>.md`.
Plan: `## Plan: <feature>` in `tasks/todo.md`, <N> slices, ready set <1, 2>.
Files: <implementation_paths, comma-separated>.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/<feature>.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: <one line per § Decisions row the builder must keep; omit the field when none>
```

Everything in it is read off the spec and the plan block; nothing is asked.
The instruction lines are fixed text; `Constraints:` is the one free slot.

### Required output

```
✓ Build Order written: <abs spec path>
✓ Plan written: <abs todo path>
Spec and plan are ready to be built. Start a fresh session with this prompt:
<build prompt, verbatim>
```

`/slice` never files anything itself; the caller relays the prompt as the
last thing its session says.

## File: `/slice <spec> --file [--approve]`

Invoked from `/build`'s pre-flight, in the session the build prompt started.

Refuses, naming the spec, when `tasks/todo.md` has no `## Plan:` block for
it: there is nothing to file before a proposal.

One `upsert` per slice, in build order, dry run first, then `--apply`:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert \
  --derive-id plan --spec specs/<feature>.md --fold-title \
  --title '<slice name>' --kind <feature|task> \
  --summary 'Slice <n>/<N> of #<issue>: <delivers>' \
  --criterion '<AC text>' \
  --evidence 'design: specs/<feature>.md § Build Order, slice <n>' \
  --parent '#<issue>'
```

- `--parent '#<issue>'` is passed only when the plan block carries a
  `> Issue:` line.
- `--approve` is passed exactly as the caller passed it: the build prompt a
  human typed is the reviewer's word, so `/build` passes it by default;
  `/yolo` omits it, so its slices land `local-pending` like every other
  unattended write on a project with `require_write_approval = true`.
- The seeded row is refreshed in place and its `(blocked-by:)` marker is
  carried from the row, so a second run after an interrupted filing is
  safe — filing is idempotent.
- Every write honours the project's approval floor; an unreachable tracker
  reports `local-pending` and is never retried silently.

### Required output

One line per slice: `✓ Filed: <id> → <#N | local, publication pending>`.

## Edge Cases

- **`--file` before any proposal.** Refused, naming the spec: no plan
  block, nothing to file.
- **Spec changed after the prompt was printed.** Re-run `/slice <spec>`:
  the Build Order, the plan block and the prompt are all replaced in place.
- **Build session resumed after an interrupted filing.** Pre-flight sees a
  header without a provider link and re-runs `--file`; linked rows are
  refreshed, never duplicated.
- **Hand-edited plan with an unordered overlap.** `slice.py ready` reports
  the pair; `/build` serializes it in table order instead of guessing.

## Integration

- **Called by**: `/plan` Step 3, `/system-design-planning` Step 3.5, and
  `/build`'s pre-flight (`--file --approve`, or `--file` alone from
  `/yolo`).
- **Calls**: `/task-registry` (`upsert`, dry run then `--apply`).
- **Precedes**: `/build`, which reads the plan block's slice rows and the
  Build Order's Surface column, one slice at a time.

## Key Principles

- Callers pass a spec path and know nothing about sizing, ordering or
  filing.
- Nothing is filed in a session nobody approved by starting it with the
  build prompt.
- One ceiling, stated once, in `references/sizing.md`.
- The plan block's `- [ ]` row is the registry's row; the surface lives
  once, in the spec's § Build Order table.
