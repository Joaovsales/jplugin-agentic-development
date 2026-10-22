---
name: slice
description: Break a spec's acceptance criteria and implementation paths into session-sized slices — a Build Order table, a plan block in tasks/todo.md, and a build prompt — and the one dry-run that mints the feature row's id. Use after a spec carries § Decisions and § Acceptance Criteria, or to refresh the Build Order and plan block after the spec changes.
argument-hint: "<spec path> [--issue #N]"
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
prompt, and stops. It files nothing; `/build`'s pre-flight makes the one
feature upsert, in the session the build prompt started.

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
or a surface path outside `implementation_paths`. Once a `## Plan:` block already exists for the spec (a re-run),
it also refuses two feature links in one block (a `> Issue:` line and a
feature row, or two of either) and an open `[ ] TDD:
tests/… § …` row whose test file no pattern in its slice's Surface matches,
naming the slice and the path — the agent a slice dispatches edits only its
Surface, so the test it must write has to be inside it. `/slice` writes nothing on
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

### 4. Write the plan block into `tasks/todo.md`

The block links its feature once. With `--issue`, or a spec `> Origin:` that
names an issue, write the `> Issue:` line. Otherwise mint one id with a single
**dry-run** upsert, never applied here, and write the feature row it names:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert \
  --derive-id plan --spec <spec> --title '<feature>'
```

Slice header rows take no id. Grammar and the fenced example below must stay
byte-for-byte identical to `.agents/skills/slice/references/plan-block.md`.

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
- [ ] <feature> <!-- task-id: plan.<spec-id> -->

### Slice 1/<N> — <name>
- [ ] <name> — <delivers>
```

- The example shows the feature row; with an issue, a `> Issue:
  https://github.com/<owner>/<repo>/issues/<N>` line replaces it. Never both,
  never two of either: `slice.py validate` refuses it.
- A slice's header row carries no task id, no `(blocked-by:)` and no `TDD:`
  child; blockers live only in § Build Order.
- Slice names never start with `/` — Git Bash on Windows rewrites a leading
  `/name` into a path.
- An existing `## Plan: <feature>` block is replaced section by section, in
  place; a different feature is appended. Never two blocks for one feature.
- `> Spec:` stands alone on its line.

### 5. Print the build prompt and stop

First the readiness gate — a build started while a decision is open just
guesses it:

```bash
python3 .agents/skills/slice/scripts/slice.py readiness --spec <spec>
```

Silent and exit 0 when every § Decisions row is settled and no open question
blocks a slice. Otherwise it prints `not ready: <ids>` — the open decisions,
then the questions whose `Blocks` names a slice — and exits 1: `/slice` prints
that line in place of the prompt, writes no prompt fence, and exits non-zero.
A question whose `Blocks` is `none` never gates. Exit 2 names a malformed
section as `<spec>:<line>: <reason>`. The visual plan page reads the spec the
same way and shows the same ids as **Not ready** with copy disabled.

The closing fenced block of § Build Order. Template must stay byte-for-byte
identical to `.agents/skills/slice/references/build-prompt.md`.

Build prompt:

```
Invoke `/build` for `specs/<feature>.md`.
Plan: `## Plan: <feature>` in `tasks/todo.md`, <N> slices, ready set <1, 2>.
Files: <implementation_paths, comma-separated>.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
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

or, when the readiness gate refuses:

```
✓ Build Order written: <abs spec path>
✓ Plan written: <abs todo path>
not ready: <ids>
```

`/slice` never files anything itself; the caller relays the prompt as the
last thing its session says.

## Edge Cases

- **Spec changed after the prompt was printed.** Re-run `/slice <spec>`:
  the Build Order, the plan block and the prompt are all replaced in place.
- **Hand-edited plan with an unordered overlap.** `slice.py ready` reports
  the pair; `/build` serializes it in table order instead of guessing.

- **How callers read a block's link.** `slice.py link --index tasks/todo.md --spec <spec>`
  prints `link: <state>` and `done: <yes|no>`; `<state>` is `legacy`, `issue #N`,
  `linked <id> #N` (the `#N` is what a PR writes after `Closes`), `unlinked <id>`
  or `none` (also a feature row with no task-id, which `validate` refuses).
  Without `--spec` it prints one `<spec> link: <state> done: <yes|no>` line per
  plan block that names a spec.

## Integration

- **Called by**: `/plan` Step 3 and `/system-design-planning` Step 3.5.
- **Calls**: `/task-registry` (one dry-run `upsert` to mint the feature id).
- **Precedes**: `/build`, which reads the plan block's slice rows and the
  Build Order's Surface column, one slice at a time.

## Key Principles

- Callers pass a spec path and know nothing about sizing or ordering.
- `/slice` files nothing: the one feature upsert belongs to `/build`'s
  pre-flight, in a session a human started with the build prompt.
- One ceiling, stated once, in `references/sizing.md`.
- The plan block's `- [ ]` row is the registry's row; the surface lives
  once, in the spec's § Build Order table.
