---
title: A fixture that cannot satisfy the input proves nothing about the guard
date: 2026-09-07
problem_type: process
module: tests/test-routine-skills.sh, .agents/skills/task-registry/scripts/registry/config.py
tags: [testing, mutation-probe, vacuous-assertion, fixtures, security]
applies_when: asserting that a guard rejects a hostile input, where the input would also fail for an unrelated reason
---

## The rule

A guard that rejects hostile input can only be tested against a fixture where the
**unguarded** code would have accepted it. If the hostile value fails anyway —
because the file it names does not exist, the row it queries is absent, the key
it reads is unset — the assertion measures the world, not the guard. Deleting the
guard leaves the suite green.

Fix the **fixture**, not the assertion. Make the hostile path succeed, so
refusing and not-refusing produce different answers.

## How it showed up

`_skill_on_disk` refuses a chain step carrying a path separator or a `..` segment,
because without it the probe reads
`<root>/.agents/skills/../../../etc/SKILL.md` — an existence oracle for arbitrary
paths, built from repository text. Four assertions checked that each hostile step
is refused. All four passed with the shape check deleted, and so did the other 48
in the file: nothing exists at `<root>/etc/SKILL.md` in a temp fixture, so the
probe returned False either way and the load was refused for the wrong reason.

The tell was that the refusal message was *also* wrong — it said "not installed"
for a step no installation could ever satisfy. Two symptoms, one cause: the test
and the message both described absence when the property was shape.

## The fix

Create the file the unguarded probe would find, at the literal unnormalized path
the implementation builds:

```bash
bait="$trav/.agents/skills/${hostile#/}/SKILL.md"
mkdir -p "$(dirname "$bait")"
printf -- '---\nname: bait\n---\n' > "$bait"
[ -f "$bait" ] || { printf 'FIXTURE BROKEN: no bait at %s\n' "$bait"; exit 1; }
```

Deleting the guard now fails 4 assertions. The `[ -f ]` line matters as much as
the rest: a fixture whose setup silently failed reproduces the original defect
exactly, and nothing would say so.

## What generalises

- **Ask what the code would do without the guard.** If the answer is "the same
  thing", there is no test yet — only an assertion.
- A hostile-input test needs a **benign twin** in the same fixture: one input that
  is well-formed and absent, one that is malformed and present. Without both, a
  single refusal message covers both cases and neither is pinned.
- A refusal that names the wrong reason is a smell for exactly this: the
  implementation is reporting the check that actually fired.
- Four dispatched review passes argued about this one; the mutation probe settled
  it in a minute. Prefer the probe.

## Related

- [[an-assertion-can-pass-because-a-different-guard-fired]] — sibling case, where
  the redundant rejection comes from another *guard* rather than from the fixture.
- [[assertion-must-be-scoped-to-the-half-it-tests]]
- [[a-config-equal-to-its-defaults-cannot-prove-it-was-read]] — the same shape on
  the configuration side: the declared value and the default agreed, so deleting
  the declaration changed nothing observable.
- [[a-null-probe-result-needs-a-control-run]]
