---
title: In the local provider a managed section is the field's home and the metadata block is a projection
date: 2026-09-07
problem_type: architecture-decision
module: .agents/skills/task-registry/scripts/registry/providers/local.py
tags: [task-registry, local-provider, information-hiding, round-trip]
applies_when: a task field is rendered twice in one Markdown detail file — as a visible section for humans and inside the machine-readable metadata block — and a hand edit must survive the next upsert
---

## The decision

`Task.reproduction` and `Task.proposed_fix` (added for the sweep routines'
issue handoff, `specs/sweep-routines.md` AC4) appear in a local detail file
twice: as `## Reproduction` / `## Proposed fix` sections, and as
`reproduction:` / `proposed-fix:` lines in the `<!-- task-registry … -->`
metadata block, one line per entry (`registry/model.py:54`, parsed at
`registry/model.py:226`).

Two homes for one value is a leakage red flag, so the provider names one of
them authoritative. The visible section is the home; the metadata block is
rewritten from it on every write and never read for these two fields
(`providers/local.py:211-215`, `_steps` at `providers/local.py:304`). When an
upsert arrives without the field, the existing value is re-derived from the
section, not from the block (`providers/local.py:238`).

## Why the section and not the block

- A human editing the file sees and edits the section. If the block were
  authoritative, that edit would be overwritten on the next bare upsert with no
  error — the exact silent-loss the registry exists to prevent.
- GitHub and Jira have no metadata block at all; their body sections are the
  only home. Making the local section authoritative keeps the three providers
  reading the same shape.
- `MANAGED_SECTIONS` (`providers/local.py:211`) is the single list of headings
  the provider owns; everything else in the file is preserved verbatim
  (`providers/local.py:271`), so the rule is stated once.

`tests/test-sweep-handoff.sh` pins it: a sed edit to the section followed by a
bare upsert must show the hand-edited text in both the section and the
projected block, and in `show`.

## Applies elsewhere

Any register with a human-readable and a machine-readable rendering of the same
fact should pick the rendering humans touch as the source and regenerate the
other. Reading both and merging is where drift hides.
