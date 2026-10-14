---
title: /learn overlap dimensions only fit the bug track, so knowledge documents never update in place
date: 2026-10-13
problem_type: bug
module: .agents/skills/learn/SKILL.md, tasks/solutions/README.md, .agents/skills/brainstorm/references/domain-modeling.md, .agents/skills/memory-maintain/SKILL.md
tags: [learning-store, overlap-scoring, knowledge-track, learn, memory-maintain]
symptoms: A recurring architecture decision or pattern always scored Moderate and created a cross-linked sibling instead of updating the existing document, and /memory-maintain never merged a duplicate knowledge-track pair
root_cause: Step 4 scored every candidate on one five-dimension set (problem, root cause, solution, files touched, prevention rule) that only a bug-track document fills, so a knowledge-track pair matched at most three and the 4–5 High branch was unreachable; /memory-maintain's merge test restated the same bug shape ("same problem, same root cause")
resolution: Step 4 and the store README define one dimension set per track; the knowledge set is situation (applies_when), claim, files or module, rule, consequence. /memory-maintain scores a pair through Step 4 and merges only on High, with Step 4's track cap as its only boundary
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
meaning. Review on PR #287 dropped Phase 2's same-category pair filter: it
made Step 4's cross-track cap unreachable there, and it would have given
`/memory-maintain` a merge boundary `/learn` does not have at write time. Step
4's track cap is now the only boundary in both passes. The pin reads the High
band and each track's dimension count from Step 4's tables, so neither can
change under the ">70%" translation unnoticed. Prevention: a skill that scores
or merges on overlap points at Step 4 for the dimension sets and the boundary
instead of adding its own.
