# Lane: fix

Owned by the go front door. Runs when the goal reports something broken,
failing, wrong, or regressed, or pastes error text. This is the `fix` routine's
chain, so a typed defect and a labelled issue run identically.

1. `/debug <goal>` — root cause before code; the prelude stops before any edit until a candidate is confirmed, and a constraint in the goal ("don't change code yet", "repro first") is part of its problem statement
2. `/build` — TDD against the reproduced failure; no fix ships without a failing test that now passes
3. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran)
4. `/wrap-up-session` — review, tests, commit, push, PR

## Reply

The root cause with its `file:line`, the failing test that now passes, and the
PR URL. Name every step skipped and why.
