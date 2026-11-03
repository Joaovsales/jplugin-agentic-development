---
title: A state reset must keep facts about the world
date: 2026-09-23
problem_type: pattern
module: .agents/skills/wrap-up-session/scripts/closure.py § load_state
tags: [state-machine, reset, lifecycle, closure, design-review]
applies_when: a persisted state machine gains a "start fresh" or "reset" path, and its state mixes per-run counters with facts about external systems
---

`closure.py` persists one state file per branch. The first lifecycle fix reset a
finished (`done`) state to the defaults. That cleared `pr_open` along with the
per-run counters. But `pr_open` records whether the branch's PR exists on GitHub,
which outlives any single run. A re-run that ended early (red suite, declined
HOLD) then printed `terminal stopped` and left a still-open PR undrafted.
The spec's `end(r)` contract forbids exactly that.

The 2026-09-23 session's delta design review caught the bug (#163). The fix
keeps the world fact across the reset
(`.agents/skills/wrap-up-session/scripts/closure.py:99`):
`return {**DEFAULT_STATE, "pr_open": state.get("pr_open", False)}`.

Rule: before writing a reset, sort every state field into two kinds:
- **Run-scoped:** phase, counters, flags that bound retries. Reset these.
- **World facts:** a PR exists, a resource was created, an issue is claimed.
  Carry these over, or better, re-read them from the source of truth.

A test that asserts "every field is default after a reset" locks in the bug. The
first lifecycle test here did exactly that.
