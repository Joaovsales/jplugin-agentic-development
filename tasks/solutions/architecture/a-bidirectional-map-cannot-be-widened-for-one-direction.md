---
title: A bidirectional map cannot be widened for one direction
date: 2026-09-05
problem_type: architecture-decision
module: .agents/skills/task-registry/scripts/registry/config.py, providers/github.py
tags: [configuration, bidirectional-mapping, write-path, vocabulary, regression]
applies_when: A configuration map is read in one direction by one consumer and reverse-looked-up by another, and a new requirement asks to add entries
---

## What happened

`DEFAULT_KIND_LABELS` maps provider label -> canonical kind. A spec required two
new labels (`tech-debt`, `documentation`) to be "readable", so both were added
mapping to the canonical kind `task`.

That map is **read in both directions**. The GitHub provider reverse-looks-up
`kind -> first matching label` to decide what to stamp on an issue it publishes
(`_mapped_labels`), and `task` is the *default* kind for any record that does not
declare one. So every ordinary published task acquired the `tech-debt` label —
which was the `fix` routine's own selector. The registry would have been feeding
issues to a routine by writing them, a loop that closes on itself.

Reproduced by execution, not inspection:

```
kind=task -> implied labels: ('tech-debt',)    # after
kind=task -> implied labels: ()                # before
```

## The rule

Before adding an entry to a shared map, find every consumer and ask which
*direction* each reads it in. A one-way requirement never justifies widening a
two-way map. Three exits, in order of preference:

1. **The requirement does not need this map.** It usually does not. Routine
   selection reads a dedicated `[routines.selectors]` section and never touches
   the kind map at all — the premise that the entries were needed was simply
   wrong, and checking a consumer would have shown it.
2. **Split the map by direction** — a read map and a write map — if a label must
   be readable as a kind without being writable as one.
3. Widen it only when every consumer, in every direction, wants the new entry.

The reverse direction is the dangerous one because it is *lossy*: many labels map
to one kind, so the inverse is ambiguous and some caller has to pick — here, the
first match in dict order. Any entry whose value is a **default** value is
therefore applied to every record that never mentioned it.

## Guard

`tests/test-routine-selectors.sh` pins `kinds-mapping-to-task: none` — no default
label may map to the default kind. The shipped template carries the same warning
inline, because a project copying it would otherwise reproduce the bug locally.

See [[consume-structured-records-before-rendering-human-summaries]] for the other
half of this module's interface discipline.
