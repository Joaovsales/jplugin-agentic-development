# Tasks

## Plan: tdd-outside-surface
> Spec: tests/fixtures/slice/validate-tdd-outside-surface/spec.md

### Slice 1/2 — one
- [ ] one <!-- task-id: plan.tdd-outside-surface.one --> — first
  [ ] TDD: tests/test-one.sh § one — pins AC 1 -> impl1 (AC 1)

### Slice 2/2 — two
- [ ] two <!-- task-id: plan.tdd-outside-surface.two --> — second (blocked-by: plan.tdd-outside-surface.one)
  [ ] TDD: tests/test-two.sh § two — pins AC 2 -> impl2 (AC 2)
  [ ] TDD: t3 -> impl3
  [x] TDD: tests/test-done.sh § done — already written, outside the surface -> impl4 (AC 2)

## Session Summary — 2026-10-16 [abc1234..def5678]
- [ ] TDD: tests/test-later.sh § later — a row after the last slice heading, not slice 2's -> impl5
