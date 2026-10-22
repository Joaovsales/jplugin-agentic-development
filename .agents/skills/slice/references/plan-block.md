# Plan block grammar

`/slice` writes one block per feature into `tasks/todo.md`. `/build` reads
it top to bottom; `/wrap-up-session` reads its `> Spec:` line to reconcile
the spec against what was built.

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
- [ ] <feature> <!-- task-id: plan.<spec-id> -->

### Slice 1/<N> — <name>
- [ ] <name> — <delivers>
```

- The block links its feature exactly once: a `> Issue:` line, written when
  `--issue` is given or the spec's origin line names an issue, or one feature
  row carrying the id of a single dry-run `upsert --derive-id plan --spec
  <spec>`. The example shows the feature row; with an issue, the `> Issue:`
  line replaces it. Never both, never two of either, and the feature row
  always carries its id: `validate` reports a breach (exit 1), and `link` and
  `ready` refuse it (exit 2).
- The `- [ ]` row under each `### Slice` heading is the slice's header row:
  a name and what it delivers, no task id, no `(blocked-by:)`, no `TDD:`
  child. Blockers and the surface live once, in the spec's § Build Order
  table, and `/build` reads them there by slice number and name.
- Slice names never start with `/` — Git Bash on Windows rewrites a leading
  `/name` into a path.
- `> Spec:` stands alone on its line. An existing `## Plan: <feature>`
  block with `[ ]` rows is replaced section by section, in place; a
  different feature is appended. Never two blocks for one feature.
- A block with a `task-id:` marker on a slice header row is **legacy**: see
  § *Legacy block* below. No new block is written in that form.

## Legacy block

The one place this is stated; every other skill links here and keeps only the
action it performs itself.

A block is **legacy** when any slice header row carries a `task-id:` marker
(`<!-- task-id: … -->`): the slices were filed per row. `slice.py link` prints
`legacy` for it, testing only for that text on the header row, never for `TDD:`
children. `slice.py link --index tasks/todo.md` (no `--spec`) lists the state
of every block that names a spec.

| Step | Treatment |
|------|-----------|
| `/slice` | `validate` and `ready` accept it unchanged; no new block is written in this form |
| `/build` | pre-flight files nothing; each slice's `TDD:` rows ride in the delegation prompt and run through `/tdd`; only its rows are claimed through `/task-registry`; Slice Close fires when the last `TDD:` row passes |
| `/debug`, `/tdd` | an open block whose rows carry a `TDD:` prefix runs like criterion rows |
| `/wrap-up-session` | keeps the per-row closure path: each slice header row carries its own task id and link |
| `/yolo` | resumes a legacy `TDD:` row like an open slice header |

**Sunset:** retire this section, the `legacy` link state and the per-row paths
above when no open `## Plan:` block in `tasks/todo.md` classifies as legacy.
