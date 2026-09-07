---
title: A configuration equal to its defaults cannot prove it was read
date: 2026-09-07
problem_type: process
module: tests/test-routine-skills.sh, .agents/skills/task-registry/scripts/registry/config.py
tags: [testing, vacuous-assertion, mutation-probe, configuration]
applies_when: asserting that a project's configuration file is actually being read, when that project configured the same values the defaults already ship
---

## The rule

Asserting on **resolved values** cannot distinguish "the project declared this"
from "the project declared nothing and inherited it". When the two produce the
same output, every such assertion survives deleting the configuration section
entirely.

Pin the **fact of declaration**, not the value. Carry a load-time boolean on the
config object and assert that.

## What happened

`docs/task-tracking.md` was added for this repository with a `[routines.skills]`
section (`specs/workflow-routing.md` AC12). Three assertions checked it was being
read:

```sh
assert_contains "$project_chains" "chain fix: /debug -> /build -> /quality-gate -> /wrap-up-session"
assert_contains "$project_chains" "routines: build,fix,improve,plan"
assert_not_contains "$project_chains" "REFUSED:"
```

All three passed with the `[routines.skills]` section **deleted from the file** —
because this project deliberately declares the shipped defaults, so the resolved
chains are byte-identical either way. The mutation probe caught it; reading the
assertions did not.

The trap is that declaring the defaults is the *right* thing for the project to
do. It makes a vocabulary change a one-file edit, and it is exactly the
configuration most likely to be written. So this is not a contrived case.

## The fix

`load_config` already had to know, in order to scope the on-disk skill check to
declared chains only, so the fact was recorded rather than invented for the test:

```python
routine_skills_declared: bool = False
```

```sh
assert_contains "$project_chains" "declared: True" \
  "AC8/AC12 live: the chains come from the file, not from the shipped defaults"
```

Deleting the section now turns that assertion red.

## Generalization

The same shape appears wherever a layer is *allowed* to restate what it
overrides: env-var overrides set to the default value, a feature flag defaulted
on, a CSS override matching the cascade. If the test asserts the outcome, delete
the layer and re-run before believing it.

## Related

- [[assertion-must-be-scoped-to-the-half-it-tests]]
- [[an-assertion-can-pass-because-a-different-guard-fired]]
- [[validate-in-the-loader-not-in-one-optional-command]]
