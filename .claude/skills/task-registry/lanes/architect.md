---
routine: producer
ends: ready, docs-only PR carrying the session record
---
# Lane: architect

Runs on a schedule, never on an issue. Lens: design. Engine:
`/software-design-expert-review --scope tree` — the APOSD red flags over the
whole tree, not a diff. Files as `task` + `tech-debt`, or `design-decision` when
the proposed fix is a choice between designs.

1. `/sweep --routine architect` — read the backlog, run the engine, verify, file, write the session record. The bar to file is an `evidence` line quoting the motivating code with `file:line` at confidence `75` or above; `NITPICK` is never filed — **non-skippable**
2. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

## Reply

The session record path, every issue filed (or `Filed: none`), and the PR URL.
