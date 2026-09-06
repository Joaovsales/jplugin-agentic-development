---
title: Scoping an all-or-nothing guard per item can silently weaken it
date: 2026-09-04
problem_type: process
module: .agents/skills/sync/scripts/sync-retire.py
tags: [guards, blast-radius, review, threshold, sync]
applies_when: relaxing a coarse safety check into a per-item one to fix a false positive
---

## The rule

An all-or-nothing guard often protects against a case no single item exhibits.
Splitting it per item removes that protection without the diff looking like it
removed anything. Before scoping a guard down, ask what the *aggregate* was
catching.

## How it showed up

`assert_roots_present` required the template to contain ≥1 file under every
declared syncable root, else hard error. It was too strict: two roots hold a
single file each, so one ordinary upstream deletion made every downstream `/sync`
exit 1 and retire nothing.

The obvious fix — skip the empty root, keep going — quietly reopened the
catastrophe it existed to prevent. The doc block that declares the roots lives
under `.agents/skills/`, so **that root is non-empty in any template the script
can read**. A truncated clone carrying only the sync skill would leave every other
root empty, skip them all, scan `.agents/skills/` against a near-empty inventory,
and retire the project's remaining 76 skill files.

## The fix

A threshold rather than a per-item rule: **one** empty root is an upstream
deletion (skip and report), **several** is a truncated source (refuse). Upstream
retires roots one release at a time; a broken checkout empties many at once.

Pinned by a fixture that simulates the truncated clone and asserts nothing under
`.agents/skills/` is deleted. Mutation-probed: removing the threshold fails 3
assertions.

## What generalises

- The item that can never trip a guard is the one that makes per-item scoping
  unsafe — here, the root containing the config that defines the roots.
- A false positive in a safety check is a reason to make it *more precise*, not
  more permissive. A threshold keeps the aggregate signal while admitting the
  benign single case.
- Self-referential configuration (a list that lives inside the thing it describes)
  deserves explicit thought whenever it appears in a guard.

Related: [[../architecture/current-state-cannot-distinguish-removed-from-never-present]].
