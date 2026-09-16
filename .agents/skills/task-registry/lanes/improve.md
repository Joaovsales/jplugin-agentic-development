---
routine: consumer
selects: enhancement, documentation
cues: add, change, support, new behaviour
ends: ready PR
---
# Lane: improve

Runs when an issue carries an `enhancement` or `documentation` label, or the
goal asks to add, change, or support new behaviour.

1. Choose the spec route for <ref> by CLAUDE.md § *Spec First*: `/brainstorm` first when the design is open, `/system-design-planning` instead of step 2 when the change crosses a component boundary, changes a persisted data model, or changes an external contract; otherwise straight to step 2. Skip when the issue already links a merged spec
2. `/plan <ref>` — write or extend the spec and the task breakdown; this is where the human is asked before code changes. Kept with ` — skip: spec written by /system-design-planning` when step 1 took that route
3. `/build` — TDD against the acceptance criteria — **non-skippable**
4. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran) — **non-skippable**
5. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

## Reply

The spec route taken, the acceptance criteria verified, and the PR URL.
