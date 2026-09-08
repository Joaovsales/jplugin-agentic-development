---
title: A stable sort hides a missing final tie-break
date: 2026-09-07
problem_type: process
module: tests/test-routine-selectors.sh, .agents/skills/task-registry/scripts/registry/model.py
tags: [testing, mutation-probe, vacuous-assertion, sorting, determinism]
applies_when: testing a sort key whose last component only decides ties, using a fixture whose input order already matches the expected output
---

## The rule

`sorted` is stable in Python, so elements with equal keys keep **input order**. A
fixture listed in the expected output order therefore produces the right answer
with the final tie-break component deleted — the stability supplies it for free.

Build the fixture with input order that **disagrees** with the expected output.
Otherwise the assertion measures the fixture's literal order, not the key.

## What happened

`by_priority` was changed from `(rank, task.id)` to
`(rank, ascending issue number, task.id)` (`specs/workflow-routing.md` AC3). One
assertion covered the final `task.id` tie-break among tasks the provider never
numbered — both sort to infinity, so only `task.id` separates them:

```python
tasks = [
    Task(id="aaa", title="Aaa", external=None),
    Task(id="zzz", title="Zzz", external=ExternalRef("github", "7", "u")),
    Task(id="mmm", title="Mmm", external=ExternalRef("github", "not-a-number", "u")),
]
```

Expected `zzz,aaa,mmm`. Dropping `task.id` from the key still produced
`zzz,aaa,mmm`: `zzz` sorts first on its number, and `aaa`/`mmm` are tied, so
stability emits them in input order — which was already `aaa` then `mmm`.

Flipping the input to `mmm, zzz, aaa` made the mutation red while leaving the
expected output unchanged.

## Why this evades review

The fixture reads as neutral. Nobody writes input order intending it to be
load-bearing, and the natural instinct is to list fixture rows in the order you
expect them back — which is precisely the arrangement that disables the test.

## Related

- [[assertion-must-be-scoped-to-the-half-it-tests]]
- [[a-config-equal-to-its-defaults-cannot-prove-it-was-read]]
