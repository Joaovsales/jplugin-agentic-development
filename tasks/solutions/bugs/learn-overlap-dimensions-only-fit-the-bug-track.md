---
title: /learn overlap dimensions only fit the bug track, so knowledge documents never update in place
date: 2026-10-13
problem_type: bug
module: .agents/skills/learn/SKILL.md, tasks/solutions/README.md, .agents/skills/brainstorm/references/domain-modeling.md, .agents/skills/memory-maintain/SKILL.md
tags: [learning-store, overlap-scoring, knowledge-track, learn, memory-maintain]
symptoms: A recurring architecture decision or pattern always scored Moderate and created a cross-linked sibling instead of updating the existing document, and /memory-maintain never merged a duplicate knowledge-track pair
root_cause: Step 4 scored every candidate on one five-dimension set (problem, root cause, solution, files touched, prevention rule) that only a bug-track document fills, so a knowledge-track pair matched at most three and the 4–5 High branch was unreachable; /memory-maintain's merge test restated the same bug shape ("same problem, same root cause")
resolution: Step 4 and the store README define one dimension set per track; the knowledge set is situation (applies_when), claim, files or module, rule, consequence. /memory-maintain merges only a same-category pair that Step 4 scores High
---

**Status**: fixed — 2026-10-13
**Regression test**: tests/test-solutions-schema.sh § Overlap dimensions; tests/test-grilling-adoption.sh § AC 5 (#168 pins); tests/test-memory-maintain-doc.sh § Merge test

Issue #168, flagged on PR #165. Evidence (level 2, primary artifacts): of the 82
knowledge-track documents in the store on 2026-10-13, one mentions a root cause
and no `architecture-decision` or `convention` document carries a prevention
rule, so two of the five dimensions are empty for every such pair.

Disconfirmed alternatives: a share-of-applicable-dimensions threshold would make
High reachable but leaves a knowledge document compared on nothing it carries;
a fix local to `/brainstorm`'s domain-modeling layer misses that `/learn` Step 2
routes decisions and patterns through Step 4 itself.

Follow-up, same day: `/memory-maintain`'s Phase 2 merged a same-category pair
only on "same problem, same root cause" over 70%, and none of the 82
knowledge-track documents carries `root_cause:`, so a duplicate knowledge pair
could never merge; its light pass restated an undefined ">70% semantic overlap".
Both passes now score a pair through Step 4 and merge only on High: over 70% of
five dimensions is 4 or 5, which is the High band, so the threshold kept its
meaning. Review on PR #287 moved the same-category condition from Phase 2's
pair filter into the merge test, so the light pass, which cites the test, no
longer merges across categories; the pin now reads the High band from Step 4's
table instead of carrying a copy. Prevention: a skill that scores or merges on
overlap points at Step 4 for the dimension sets instead of listing its own.
