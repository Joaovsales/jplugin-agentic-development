---
routine: consumer
selects: bug, tech-debt
cues: broken, fails, wrong output, regression, error text pasted
ends: ready PR
---
# Lane: fix

Runs when an issue carries a `bug` or `tech-debt` label, or the goal reports
something broken, failing, wrong, or regressed, or pastes error text. A typed
defect and a labelled issue run identically; only `<ref>` differs.

1. `/debug <ref>` — root cause before code; the prelude stops before any edit until a candidate is confirmed, and a constraint in the goal ("don't change code yet", "repro first") is part of its problem statement. Reproduced and progressable work continues; an inconclusive or blocked investigation is held and reported by the canonical escalation owner
2. `/build` — TDD against the reproduced failure; no fix ships without a failing test that now passes — **non-skippable**
3. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran) — **non-skippable**
4. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

## Reply

The root cause with its `file:line`, the failing test that now passes, and the
PR URL. Name every step skipped and why.
