---
title: /learn overlap dimensions only fit the bug track, so knowledge documents never update in place
date: 2026-10-13
problem_type: bug
module: .agents/skills/learn/SKILL.md, tasks/solutions/README.md, .agents/skills/brainstorm/references/domain-modeling.md
tags: [learning-store, overlap-scoring, knowledge-track, learn]
symptoms: A recurring architecture decision or pattern always scored Moderate and created a cross-linked sibling instead of updating the existing document
root_cause: Step 4 scored every candidate on one five-dimension set (problem, root cause, solution, files touched, prevention rule) that only a bug-track document fills, so a knowledge-track pair matched at most three and the 4–5 High branch was unreachable
resolution: Step 4 and the store README define one dimension set per track; the knowledge set is situation (applies_when), claim, files or module, rule, consequence
---

**Status**: fixed — 2026-10-13
**Regression test**: tests/test-solutions-schema.sh § Overlap dimensions; tests/test-grilling-adoption.sh § AC 5 (#168 pins)

Issue #168, flagged on PR #165. Evidence (level 2, primary artifacts): of the 82
knowledge-track documents in the store on 2026-10-13, one mentions a root cause
and no `architecture-decision` or `convention` document carries a prevention
rule, so two of the five dimensions are empty for every such pair.

Disconfirmed alternatives: a share-of-applicable-dimensions threshold would make
High reachable but leaves a knowledge document compared on nothing it carries;
a fix local to `/brainstorm`'s domain-modeling layer misses that `/learn` Step 2
routes decisions and patterns through Step 4 itself.

Not changed: `/memory-maintain`'s merge test ("same problem, same root cause",
over 70%) is a separate, bug-shaped rule outside this issue's criteria.
