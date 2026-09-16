---
routine: consumer
ends: ready PR
deferred: deferred behind the blockedBy provider capability (#97) and the routine itself (#98) — not runnable yet
---
# Lane: build

Runs on an issue of any kind that carries a merged linked plan and no open
blockers. Listed so the deferral is legible, not so it can be run: its selector
needs `blockedBy` read through the registry, which the GitHub provider does not
request yet.

1. `/build` — read the merged spec linked from <ref> instead of writing one; TDD against its acceptance criteria — **non-skippable**
2. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran) — **non-skippable**
3. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

## Reply

The merged spec implemented, the acceptance criteria verified, and the PR URL.
