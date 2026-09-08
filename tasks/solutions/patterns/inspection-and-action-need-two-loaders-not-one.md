---
title: Inspection and action need two loaders, not one strictness setting
date: 2026-09-08
problem_type: pattern
module: .agents/skills/task-registry/scripts/registry/index.py
tags: [validation, loader, error-design, diagnostics, aposd]
applies_when: a loader is consumed both by a diagnostic that must read broken input and by a command that acts on it
---

## The rule

"Validate in the loader" is right, but a loader with **one** strictness is wrong
whenever a diagnostic reads the same source. Inspecting malformed input is how a
user learns what to fix, so the reader must stay permissive; acting on
half-parsed input is silent corruption, so the actor must refuse. Ship two entry
points over one shared parse, not a `strict=True` flag threaded through callers.

The permissive one keeps the parse errors as data. The strict one raises on
exactly that data.

## What happened

`load_index` collects unparseable rows into `index.problems` and returns anyway.
Every command — including the ones that rewrite rows — read through that same
permissive call. A row that failed to parse is absent from `by_id`, so an update
silently became an append and minted a second row carrying the same id, on the
second run, invisibly.

Fixed with a strict sibling rather than a parameter:

```python
class IndexUnreadable(ValueError):                                   # index.py:369
def load_index_strict(path, relative_path=None) -> TaskIndex:        # index.py:373
    index = load_index(path, relative_path)
    if index.problems:
        raise IndexUnreadable("refusing to act on a malformed index — fix these rows first:\n" + ...)
```

`upsert` takes the strict one — hoisted above the provider call, so the refusal
precedes any provider write. `show` keeps the permissive one and folds
`index.problems` into its `degraded:` block. The CLI maps `IndexUnreadable` to a
message plus exit 1.

**The first attempt got the split backwards, and the docstring hid it.** Both
loaders were wired to the strict path while the docstring claimed the permissive
one existed "because inspecting a malformed index is how a reader learns what to
fix". No such reader existed: `doctor` never reads the index at all, so
`load_index`'s only caller was its own strict wrapper. The rationale asserted a
consumer into existence and nothing contradicted it, because a comment cannot
fail a test. Three independent reviewers landed on the same seam from different
directions before it was fixed by making the code match the comment rather than
the comment match the code.

## Why not a flag

A `strict=True` parameter puts the decision at the **call site**, where it is one
keyword away from being forgotten and invisible in review — the same defect, one
indirection later. Two named functions make the choice legible in the import line
and greppable across the tree: `grep load_index(` now finds exactly the readers
that are allowed to tolerate breakage.

It also pulls complexity downward. Callers say what they intend to do (read vs.
act); nothing about `problems` or partial parses leaks into them.

## How to apply

- Split at the loader by **caller intent**, not by a boolean. Name both.
- Then check that a caller of each actually exists. A docstring justifying a
  permissive variant by naming a reader is a claim about the call graph; grep it.
  If the strict variant has every caller, the split is decoration and the next
  reader will trust the comment over the code.
- Make the strict one wrap the permissive one, so there is one parser and no
  chance of the two disagreeing.
- Put the failing rows in the exception message with `file:line`. A refusal that
  does not say which row is a worse diagnostic than the permissive read.
- Pin the refusal with a test that also asserts the **absence** of the duplicate
  row — the message and the corruption are separate guarantees.

Related: [[validate-in-the-loader-not-in-one-optional-command]],
[[one-return-value-for-several-outcomes-leaves-the-caller-nothing-to-branch-on]],
[[logical-text-records-must-own-their-rewrite-span]]
