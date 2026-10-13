---
title: Merging restated rules into one home can silently drop a clause
date: 2026-10-09
problem_type: pattern
module: .agents/references/finding-model.md § Deferrals; review personas under .agents/agents/
tags: [one-home, consolidation, review-personas, information-leakage, aposd, deferrals]
applies_when: several files each restate a version of one rule and a change replaces the copies with a citation to a single home
---

## What happened

The review-load build (specs/review-load-and-failure-cases.md, slice 2) merged
the `TODO(shortcut):` rule into `finding-model.md` § *Deferrals* and replaced
three persona copies with a citation. The spec named two exceptions, load and
the never-cut list, and the home stated exactly those two. One persona copy
carried a third clause that no spec row mentioned: a shortcut "whose limit turns
out to be wider than its author wrote down" was a `MUST-FIX`. The merge deleted
it. Every slice test stayed green, because the tests pinned what the spec named.

The dispatched Phase 4 design review caught it by reading the old text at the
base commit. The fix widened exception (a) to cover "the code's real limit when
that is narrower than the one named" (.agents/references/finding-model.md:105).

## The rule

Before deleting a restated copy, list each of its clauses and find each one in
the new home. A clause with no match is either moved or dropped on purpose, and
a dropped one is recorded in the spec's § Decisions. A spec that lists what the
merged rule says is not a list of what the old copies said.

The same review found a second leak in the same consolidation. Critic kept a
critic-only exception (a deferral that fails an AC) and then cited the home as
"the other two exceptions", which coupled its text to the home's count. Cite the
home without counting what is in it.

Related: [[a-caller-that-restates-its-callees-format-makes-the-callee-optional]].
