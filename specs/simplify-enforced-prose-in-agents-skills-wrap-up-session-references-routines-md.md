---
implementation_paths:
  - .agents/skills/wrap-up-session/references/routines.md
---

# Spec: simplify — enforced-prose in .agents/skills/wrap-up-session/references/routines.md

> Origin: #453 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-19) · Signal: `enforced-prose` · Class: minor · Review status: **built** 2026-11-19

## Behavior

`.agents/skills/wrap-up-session/references/routines.md` § *Priority is not a
selector* states the rule — `now` and `next` order candidates within a
routine's pool and never select a routine — and then restates the measurement
that motivated it ("Measured against the pipeline repo, 9 of 28 open issues …").
That measurement is design history: its home is the design record,
`specs/category-routines.md` (the paragraph beside "This is the correction that
makes the selectors a total function"), and `tests/test-routines-contract.sh`
already pins the rule ("never select a routine"). After this change the section
states the rule and its consequence only, and every routine that reads the
contract pays for two fewer lines. No routine behaves differently.

## Inputs

- `.agents/skills/wrap-up-session/references/routines.md:101-107` — § *Priority is not a selector*.
- `specs/category-routines.md:101-105` — the same measurement, in the design record.
- `tests/test-routines-contract.sh:60-65` — `assert_prose_contains "$CANON" "never select a routine"`.

## Outputs

- `routines.md` § *Priority is not a selector*: the measurement sentence removed; the rule sentence and "Ordering within a pool is what makes the selectors a total function." kept.

## Edge Cases

- **The rationale is not lost.** The spec keeps the measurement, and the test comment keeps it beside the assertion.
- **The pinned needle survives.** "never select a routine" stays in the section, so the test is untouched (safe-moves 3 does not apply: nothing moves).
- **The heading stays.** `### Priority is not a selector` is unchanged, so no citation breaks.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the measurement sentence in `routines.md` § *Priority is not a selector*; the spec and the test stay byte-identical | settled (unattended pick) |
| D2 | Byte-identical: every heading, the rule sentence, the "total function" sentence, every other line of `routines.md` | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| D5 | Keep the measurement in the spec, not in the reference — the reference is the operational contract, the spec the design record | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) — no heading changes | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3) — no assertion moves | settled |
| S4 | One home per rule (safe-moves 4) — the measurement keeps one home, the spec | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5) — no script is touched | settled |

## Acceptance Criteria

1. `routines.md` § *Priority is not a selector* no longer contains "9 of 28" and still contains "never select a routine" and "total function".
2. The before-proof commands (`bash tests/run.sh <affected tests>` and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | priority rule without its history | a shorter § *Priority is not a selector* | `.agents/skills/wrap-up-session/references/routines.md` | — | 1, 2 | `bash tests/affected.sh --run 887e959` | 1 file · 1 system · 2 ACs |
