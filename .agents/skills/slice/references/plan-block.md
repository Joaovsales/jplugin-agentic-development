# Plan block grammar

`/slice` writes one block per feature into `tasks/todo.md`. `/build` reads
it top to bottom; `/wrap-up-session` reads its `> Spec:` line to reconcile
the spec against what was built.

```markdown
## Plan: <feature>
> Spec: specs/<feature>.md
> Issue: https://github.com/<owner>/<repo>/issues/<N>

### Slice 1/<N> — <name>
- [ ] <name> <!-- task-id: plan.<id> --> — <delivers> (blocked-by: plan.<id>)
  [ ] TDD: <test that pins AC n> -> <minimal implementation>
  [ ] TDD: <test that pins AC m> -> <minimal implementation>
```

- The `- [ ]` row under each `### Slice` heading is the registry's row:
  compact fields only, `(blocked-by:)` in the form the index parses, no
  surface. The surface lives once, in the spec's § Build Order table, and
  `/build` reads it there by slice number and name.
- Ids are minted by a dry-run `upsert --derive-id plan --spec <spec>
  --fold-title --title '<slice name>'`, so the `--file` phase refreshes the
  seeded row in place instead of appending. Slice names never start with
  `/` — Git Bash on Windows rewrites a leading `/name` into a path.
- The `[ ] TDD:` rows are written here, one or more per AC the slice
  carries. They are not what the human reviews; the Build Order is.
- `> Spec:` stands alone on its line. An existing `## Plan: <feature>`
  block with `[ ]` rows is replaced section by section, in place; a
  different feature is appended. Never two blocks for one feature.
- `> Issue:` is written when `--issue` is given or the spec's origin line
  names one.
