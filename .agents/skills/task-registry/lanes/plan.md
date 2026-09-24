---
routine: consumer
selects: design-decision
cues: spec only, decide between, design decision, no implementation yet
ends: draft PR carrying a spec
---
# Lane: plan

Runs when an issue carries a `design-decision` label, or the goal asks for a
spec or a decision and no implementation. A plan is a proposal, so the PR it
opens is a **draft** and its body carries `Refs #N`, never `Closes`.

1. `/plan <ref>` — write `specs/<feature>.md` and the task breakdown; this is where the human is asked before anything else happens — **non-skippable** — the spec is the lane's entire artifact
2. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

`/build` and `/quality-gate` are deliberately absent. This lane produces a spec
and no implementation, so requiring them would write a `skip:` row on every
single run — and a ledger that always reads `skip:` teaches a reader nothing,
which is exactly the failure the step ledger exists to prevent.

## Reply

The spec path, its acceptance criteria, and the draft PR URL. Name every
question the interview left open.
