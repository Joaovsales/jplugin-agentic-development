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
  line replaces it. Never both, never two of either.
- The `- [ ]` row under each `### Slice` heading is the slice's header row:
  a name and what it delivers, no task id, no `(blocked-by:)`, no `TDD:`
  child. Blockers and the surface live once, in the spec's § Build Order
  table, and `/build` reads them there by slice number and name.
- Slice names never start with `/` — Git Bash on Windows rewrites a leading
  `/name` into a path.
- `> Spec:` stands alone on its line. An existing `## Plan: <feature>`
  block with `[ ]` rows is replaced section by section, in place; a
  different feature is appended. Never two blocks for one feature.
- A block is **legacy** when any slice header row carries a `task-id:` marker
  (`<!-- task-id: … -->`); `slice.py` tests only for that text on the header
  row, never for `TDD:` children. It still validates and readies a legacy
  block, and no new block is written in that form.
