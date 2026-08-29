# Migration Guide

For a repository whose `tasks/todo.md` has grown into a detailed backlog — plan
blocks, closed session summaries, ticked history, specs in `specs/pending/` that
nobody has looked at in months.

The goal is not to import all of it. It is to separate what is still work from
what is now history, and to publish only the first.

---

## What migration does

| Classification | Meaning | ID minted | Published |
|---------------|---------|-----------|-----------|
| `active` | open row in a plan block that is still open | yes | on `publish` |
| `stale` | open row in a plan block a Session Summary already closed | yes | after you review it |
| `completed` | `[x]` or `[-]` row | **no** | **never** |
| `superseded` | its governing spec declares `> Superseded by: ...` | no | never |

Three rules, and they are the whole design:

1. **One external task per deliverable, never one per checkbox.** Rows are grouped
   by the plan block that contains them. A closed plan with nine ticked rows
   contributes zero issues; an open plan with four rows contributes one group.
2. **Operational work survives.** Rows about deployment, smoke tests, e2e runs,
   rollout verification, or runbooks are classified `operational` rather than
   flattened into "feature" or dropped as noise.
3. **Nothing is deleted.** `stale` and `superseded` are labels for a human. The
   tool writes a report; it never removes a row, a spec, or a backlog item.

---

## Procedure

### 1. Dry run

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py migrate
```

Writes nothing. Prints counts, the proposed grouping, and a per-row table of
classification, inferred kind, minted ID, and linked spec.

### 2. Read the classification, not just the counts

Check three things specifically:

- Is anything `completed` that is actually still open? (A row ticked optimistically.)
- Is anything `active` that is actually dead? (A plan nobody closed.)
- Are the inferred kinds right? Kind comes from the wording of the row and its
  plan heading — a heuristic, and the report says so.

Fix the source rows in `tasks/todo.md` and re-run. The classifier reads the file;
it does not remember its last answer.

### 3. Apply

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py migrate --apply
```

Local writes only:

- inserts `<!-- task-id: ... -->` after the title of every `active` and `stale`
  row, leaving the rest of the row byte-identical;
- writes `tasks/task-registry-migration.md`, an audit trail listing **every** row
  scanned, including the completed ones, plus the proposed grouping and notes.

Re-running is idempotent: a row that already has an ID keeps it.

### 4. Publish deliberately

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py publish
python3 .agents/skills/task-registry/scripts/task-registry.py publish --apply --approve
```

Dry run first. `publish` creates external tasks only for non-terminal rows that
have an ID and no provider match — so `completed` and `superseded` rows are
structurally incapable of becoming issues.

### 5. Reconcile from then on

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py reconcile
```

This is the steady state, and it is what `/wrap-up-session` runs.

---

## Worked example

A `tasks/todo.md` with three plan blocks and nine checkboxes:

```markdown
## Plan: Still-motion animation
> Spec: specs/completed/still-motion.md

[x] TDD: living texture flow -> impl
[x] TDD: zoom path agreement -> impl
[x] TDD: blur knob parameters -> impl
[ ] TDD: parametrize move intensity -> left open when the plan closed

## Session Summary — 2026-08-13
- Completed: 3 tasks

## Plan: Recipe morphs
> Spec: specs/pending/morph-recipes.md

- [ ] Morph live grid recipe — ship the live grid morph
- [ ] Colour LUT loader — palette mapping for 8-bit sources
- [!] Verify nightly render deploy — smoke the rollout after each release
- [ ] Decide dither strategy — pick one before the next recipe lands

## Plan: Pre-convert effects
> Spec: specs/pending/pre-convert-effects.md   (declares itself superseded)

- [ ] Wire pre-convert effects — replaced by the stage pipeline
```

Produces:

```
  rows scanned:        9
  active:              4
  stale (open in a closed plan): 1
  completed (history, no external task): 3
  superseded:          1
  proposed external tasks: 2 group(s) covering 5 row(s)
```

Nine checkboxes, two proposed external tasks. The three ticked rows stay as
history and are never published. The `[!]` row is classified `operational` and
keeps its blocked status. The pre-convert row is `superseded` — reported, left in
place, not published.

---

## Adopting this in a repository that already uses GitHub Issues

If some work is already in issues (the `ascii_video_pipeline` case):

1. `migrate --apply` to mint IDs locally.
2. For each row that already has an issue, add the link and the ID by hand once:
   put `<!-- task-id: ... -->` on the row, and paste the same ID into the issue
   body's metadata block. After that, matching is automatic and permanent.
3. `reconcile` to see what is left: rows with no issue (`unlinked-local`), issues
   with no row (`unlinked-external`), and drift between the two.
4. `pull --apply` to bring the issues that should be in the index into it, then
   `publish --apply` for the rows that should become issues.

Step 2 is the only manual part, and only for pre-existing issues — because the
alternative is matching by title, which is exactly what this design refuses to do.

---

## What migration will not do

- Create one issue per historical checkbox.
- Delete a stale spec, a superseded row, or a backlog item.
- Change an existing label, or create a new one.
- Decide that two same-titled tasks are the same task.
- Publish anything. Migration is local; publishing is a separate, gated command.
