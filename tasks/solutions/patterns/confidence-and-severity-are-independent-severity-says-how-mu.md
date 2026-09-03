---
title: Keep confidence independent from severity
date: 2026-08-10
problem_type: pattern
module: CLAUDE.md, .agents/skills/wrap-up-session
tags: [review-findings, confidence, severity, finding-model]
applies_when: Classifying or reconciling findings from code, security, or design reviews
migrated_from: tasks/memory.md
---

## Keep confidence independent from severity

**Pattern**: Confidence and severity are independent. Severity says how much a finding matters if real; confidence says whether it is real. Collapsing them is what lets an unproven guess be auto-applied with the authority of a proven defect.

The review contract stores severity, confidence, autofix class, and owner as four
orthogonal fields (`.agents/skills/wrap-up-session/SKILL.md:191-239`).

Related: [Verify a confidence-50 MUST-FIX](a-must-fix-at-confidence-50-must-be-verified-not-fixed.md).

_Extracted from session history entry "Compound engineering Tier 2 (review epistemics)" (2026-08-10) in `tasks/history.md`._
