---
title: Validate in the loader, not in one optional command
date: 2026-09-05
problem_type: pattern
module: .agents/skills/task-registry/scripts/registry/config.py
tags: [validation, invariants, configuration, gates, unrepresentable-states]
applies_when: A validation function exists for a config invariant and is called from a reporting or doctor-style command
---

## The failure shape

A validator existed, was correct, had tests, and never ran. `validate_selectors`
refused a configuration where two routines claim one label — and it was called
from exactly one place: the `selectors` subcommand, which no skill, no ledger
step, and no hook invoked. `load_config` did not call it.

So an invalid configuration loaded fine, every other command ran fine, and
selection fell back to dict insertion order — the precise failure the validator
was written to make impossible. The gate was real code with no trigger.

## The rule

A validator reachable only from a command a human chooses to type protects
nothing that runs unattended. Call it from the **constructor or loader**, so the
invalid state is unrepresentable rather than merely detectable:

```python
config = Config(...)
validate_selectors(config)   # every command inherits the guarantee
return config
```

The reporting command then keeps only the part that genuinely needs to be
optional — here, the upstream check that requires network.

## How to spot it

Grep for the validator's call sites. If they are all inside one CLI subcommand,
one debug path, or one test, the invariant it names is unenforced everywhere
else. "It has a test" is not the same as "it runs": the test calls it directly.

Related: [[hard-gate-on-tasks-todo-md]] is the same failure one
level up — a gate that exists in prose but not in the register nobody can skip.
