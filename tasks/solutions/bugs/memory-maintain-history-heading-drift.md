---
title: Memory maintenance ignores alternate session history headings
date: 2026-09-09
problem_type: bug
module: .agents/skills/memory-maintain, .claude/hooks/session-start.sh
tags: [memory-maintain, history, session-count, heading-drift]
symptoms: Five alternate-format history entries produce no maintenance reminder
root_cause: Both counters recognize only bracketed level-three dates while actual history also uses unbracketed level-two dates
resolution: Recognize both existing heading formats in the hook and mirrored skill, with behavioral regressions and a shared-pattern contract test
---

**Status**: fixed — 2026-09-09
**Regression test**: Alternate and mixed fixtures in tests/test-session-start.sh; pattern parity in tests/test-memory-maintain-doc.sh

## Reproduction

Create a temporary `tasks/history.md` with five `## 2026-09-0N — session`
headings, N=1..5. Run the repository's absolute `.claude/hooks/session-start.sh`
path from that directory with `CCW_SESSION_GUARD=0` and stdin
`{"source":"startup"}`. Exit is zero, but `MEMORY MAINTENANCE DUE` is absent.
Changing only the headings to `### [2026-09-0N] — session` produces the reminder.
A mix of four canonical entries and one alternate entry also fails.

Evidence level 1: reproduced before implementation in the primary context and
independently by a dispatched code-debugger.

## Original root cause and alternatives (before the fix)

- `.claude/hooks/session-start.sh:180` counts only bracketed level-three dates.
- `.agents/skills/memory-maintain/SKILL.md:42` specifies the same restriction.
- `tasks/history.md:405`, `:432`, and `:460` contain excluded session headings.
  Current history has 19 recognized entries plus three excluded entries.
- `tests/test-session-start.sh:185` covers only the canonical heading format.

A conflicting writer template is ruled out: `/learn` at
`.agents/skills/learn/SKILL.md:65` prescribes the canonical format. Actual writes
drifted from it. Startup suppression is ruled out by disabling the guard and
running a successful canonical control in the same environment.

This established undercounting, not that maintenance was due at the observed total
of 22 or that no previous heavy pass ever ran. Missed thresholds and repeated
sweeps are separate limitations of the documented modulo cadence.

## Resolution and verification

The hook at `.claude/hooks/session-start.sh:180` and the canonical skill's
command at `.agents/skills/memory-maintain/SKILL.md:47` now recognize both
formats. Complete brackets and a whitespace/end boundary exclude partial dates.
The date check is syntactic; it does not validate calendar dates.

The new alternate/mixed regressions failed on the original hook, then passed.
`tests/test-session-start.sh` passes 95 assertions; the documentation contract
passes 15. Four isolated mutations (drop the alternate format, remove the date
boundary, allow zero, bypass modulo) each fail the corresponding assertions.
Live-hook walkthrough observations are retained in `tasks/e2e-log.md`.

Full suite: 38 files, 3,589 assertions passed with
`env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh </dev/null`.
This session inherited `TASK_REGISTRY_TRUSTED_CONFIG=1`, which made the existing
Doctor approval-floor test fail before implementation; clearing that override
for the test process restored its expected environment. No registry code changed.

Prevention: include fixtures drawn from actual persisted history, not only the
writer's template; otherwise both the writer-shaped test and narrow reader can
agree while excluding real records.
