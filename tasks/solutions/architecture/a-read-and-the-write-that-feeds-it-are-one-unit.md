---
title: A read and the write that feeds it are one unit — deleting the write leaves the read lying
date: 2026-09-08
problem_type: architecture-decision
module: .agents/skills/task-registry/scripts/registry/upsert.py, registry/providers/local.py
tags: [deletion, data-loss, idempotency, provider-abstraction, scope]
applies_when: a deletion cut plans to remove a write path while keeping a reader that consults what it wrote
---

## The rule

Before deleting a write, find every read of the state it produced. If a surviving
reader consults that state to decide whether an action already happened, the write
is not incidental — it is the **only memory** of the action, and removing it turns
an idempotent operation back into a duplicating one.

A read/write pair that guards an external side effect is one unit. Ship both or
neither.

## What happened

Cut 2 planned to delete `upsert.py` whole. Two of its functions are a matched
pair:

```python
def _published_ref(config, task_id: str):          # upsert.py:136 — read
    row = load_index_strict(...).by_id(task_id)
def _sync_index(config, task: Task) -> str:        # upsert.py:152 — write
```

`_published_ref` answers "has this task already been published to GitHub?" so a
second `upsert` updates the existing issue instead of minting a new one.

The reason the local index row is the only place that answer lives is in the
*other* provider:

```python
return task.with_(external=ExternalRef("local", task.id, self._relative(path)))
```
— `providers/local.py:86` and `:93`

The local provider **overwrites** `external` with its own local ref on every
create and update. So the in-memory task never carries the GitHub reference back;
the index row `_sync_index` writes is the sole surviving record of a GitHub
publication.

Deleting the write while keeping `_published_ref` — or deleting both while
anything still calls `upsert` — reintroduces duplicate-issue minting. It forced
keeping `upsert.py` whole, and is most of why the cut measured 608 LOC against a
1,395 projection.

## Why the plan missed it

The plan reasoned about *modules* (`upsert.py` is going) rather than about
*state* (who else reads the row it writes). Module-level scoping is the right unit
for a deletion cut right up to the point where a module owns a durable record. A
file boundary does not tell you that `local.py` clobbers the field `upsert.py`
depends on — that only shows up by following the data.

The failure mode is also **silent and delayed**: the duplicate appears on the
second run, in a different command, against an external tracker.

## How to apply

- For each write being deleted, grep for readers of the field or row it produces —
  not for callers of the function.
- Ask what the reader would conclude if the state were simply absent. "Not yet
  published" is a dangerous default: absence and never-happened are
  indistinguishable, and the safe-looking branch is the one that repeats the side
  effect.
- Under a provider abstraction, check whether a *sibling* provider overwrites the
  field. Only one implementation needs to clobber it for the persisted copy to
  become load-bearing.
- When this forces a module to survive a cut, record the measured scope change
  rather than quietly restating the projection.

Related: [[ship-the-write-half-or-neither]],
[[a-declared-intent-with-a-broken-target-is-not-an-absent-one]]
