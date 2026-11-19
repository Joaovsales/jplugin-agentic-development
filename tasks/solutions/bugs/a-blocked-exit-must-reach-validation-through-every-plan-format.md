---
title: A blocked exit must reach validation through every plan format
date: 2026-11-19
problem_type: bug
module: .agents/skills/build/SKILL.md, .agents/skills/slice/scripts/slice.py
tags: [blocked-exit, partial-build, readiness, phase-guards, implicit-slice]
symptoms: Partial builds could not enter validation, implicit slices ignored blocked state, and malformed records silently suppressed work.
root_cause: The blocked outcome was added to headed readiness without reconciling later phase guards, the implicit path, or marker validation.
resolution: Enter validation on exhausted readiness, scope checks to closed work, and share a blocked-record reader that refuses empty fields.
---

Fixed in PR #455 for #440. A new terminal outcome must be traced through every
phase entry and every supported plan format, including the legacy implicit slice.
Label-presence tests alone missed the incompatible phase guards.

- `.agents/skills/build/SKILL.md:351` and `:373` enter validation when the ready
  set is exhausted; `:418` classifies blocked ACs before completed-work e2e checks.
- `.agents/skills/slice/scripts/slice.py:472` validates blocked records for both
  headed and implicit slices before readiness is printed.
- `tests/test-doc-conventions.sh` pins the partial-build phase transition and
  classification order; `tests/test-slice.sh` exercises no-ready partial builds,
  implicit marker removal, and bare/empty blocked-record refusals.

Keep blocked/waiting headers incomplete and preserve the partial-PR linkage.
Test the transition to reporting, rather than only the final report's label.
