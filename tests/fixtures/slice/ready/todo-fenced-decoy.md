# Tasks

## Plan: ready-fixture
> Spec: tests/fixtures/slice/ready/spec.md

### Slice 1/3 — one

A hand edit pasted the row grammar as an example above the real row:

```markdown
- [ ] <name> <!-- task-id: plan.<id> --> — <delivers>
```

- [x] one <!-- task-id: plan.ready-fixture.one --> — first
  [x] TDD: t1 -> impl1

### Slice 2/3 — two
- [ ] two <!-- task-id: plan.ready-fixture.two --> — second (blocked-by: plan.ready-fixture.one)
  [ ] TDD: t2 -> impl2

### Slice 3/3 — three
- [ ] three <!-- task-id: plan.ready-fixture.three --> — third
  [ ] TDD: t3 -> impl3
