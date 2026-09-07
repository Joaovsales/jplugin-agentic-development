# Checkpoint — 2026-09-07

> A checkpoint is a **snapshot**, not a ledger. The merge of `origin/master` into
> this branch conflicted here because both sides described their own session; the
> resolution is one accurate snapshot of the current state, not both. #110's
> snapshot is preserved where it belongs — in `tasks/history.md` and
> `tasks/e2e-log.md`, which are append-only and kept both sides.

## State
- Branch: `feat/workflow-routing-phase-a`
- Base: `origin/master` at `d1b4b14` (merged in; the branch was cut at `bbef230`)
- Active spec: `specs/workflow-routing.md`
- Open PR: [#111](https://github.com/Joaovsales/jplugin-agentic-development/pull/111) — Phase A
- Landed on master while this branch was open: PR #110 (issue #90, legacy row publishing)

## Verification
- `bash tests/run.sh`: 39 test files passed
- Every new guard in Phase A mutation-probed: implementation deleted, suite red,
  implementation restored
- `tests/test-skill-parity.sh`: 78 assertions — `.agents/` and `.claude/` trees
  byte-identical apart from the three allowlisted Claude-only extras

## In-Progress & Pending Tasks (tasks/todo.md)
(none — all seven Phase A rows are `[x]`)

## Remaining work
- PR #111 review. Its test plan carries one unchecked box: confirm the `workflow`
  exit-code split (1 = no routine to start, 2 = a human must edit a file) before
  a scheduler depends on it.
- Four `owner: human` findings in `tasks/handover-workflow-routing.md` § 11, led
  by AC2 being unsatisfiable as worded against spec § 3's own table.
- Phase B (Cut 1) — rows in `tasks/handover-workflow-routing.md` § 7. Not on this
  branch: one phase per `/build`, one PR per phase.

## How to Resume
1. Read this file, then `tasks/handover-workflow-routing.md`, then `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Phase B starts from handover § 7, off a freshly pulled `master`
