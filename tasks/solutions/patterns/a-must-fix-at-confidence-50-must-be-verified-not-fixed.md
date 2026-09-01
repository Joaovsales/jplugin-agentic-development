---
title: "A `MUST-FIX` at `confidence: 50` must be *verified*, not fixed"
date: 2026-08-10
problem_type: pattern
module: CLAUDE.md, .agents/skills/wrap-up-session
tags: [review-findings, confidence, verification, apply-gate]
applies_when: A reviewer reports a severe finding without line-level proof
migrated_from: tasks/memory.md
---

## A `MUST-FIX` at `confidence: 50` must be *verified*, not fixed

**Pattern**: A `MUST-FIX` at `confidence: 50` must be *verified*, not fixed and not blocked on — otherwise a speculative finding deadlocks every commit. Caught in this session's own Phase 3 gate, in the very rule being written.

The current apply gate forbids auto-applying at confidence 50 and requires reading
the dependency before either promotion or refutation
(`.agents/skills/wrap-up-session/SKILL.md:266-292`).

Related: [Confidence and severity are independent](confidence-and-severity-are-independent-severity-says-how-mu.md).

_Extracted from session history entry "Compound engineering Tier 2 (review epistemics)" (2026-08-10) in `tasks/history.md`._
