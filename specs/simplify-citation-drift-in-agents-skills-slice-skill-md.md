---
implementation_paths:
  - .agents/skills/visual-plan/SKILL.md
---

# Spec: simplify — citation-drift in .agents/skills/slice/SKILL.md

> Origin: #357 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-10-23) · Signal: `citation-drift` · Class: minor · Review status: **built** 2026-10-23

## Behavior

`/slice`'s propose phase applies `/visual-plan` § *Skip when trivial* before it
renders, but `/visual-plan` titles that section `## Skip when trivial (gate)`, so
the pointer names no heading. After this change the heading is
`## Skip when trivial` — a name only, the same heading `/visual-recap` already
uses — and the citation resolves. How `/slice` and `/visual-plan` behave doesn't
change.

## Inputs

- `.agents/skills/slice/SKILL.md:143` — the citation, pinned verbatim by `tests/test-plan-render.sh` (`'§ *Skip when trivial*'`).
- `.agents/skills/visual-plan/SKILL.md:31` — the heading `## Skip when trivial (gate)`.

## Outputs

- `.agents/skills/visual-plan/SKILL.md`: one heading loses its `(gate)` qualifier; the line count stays the same.

## Edge Cases

- **The heading moves, not the citation.** Rewriting the citation to `§ *Skip when trivial (gate)*` would break the `test-plan-render.sh` pin and keep a qualifier in a heading (safe-moves 1). The heading is the drift.
- **No other caller.** `Skip when trivial (gate)` appears nowhere else outside `tasks/` history; `test-doc-conventions.sh` asserts the token `Skip when trivial`, which the new heading still carries. The body's "see the skip gate below" still reads correctly.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the one heading at `visual-plan/SKILL.md:31`; `/slice` and every test are out | settled (unattended pick) |
| D2 | Byte-identical: `/slice` in full, every other `/visual-plan` line, every test | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| D5 | Rename the heading rather than the citation, matching `/visual-recap` § *Skip when trivial* | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) — the qualifier is dropped | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3) — no assertion moves | settled |
| S4 | One home per rule: the skip gate stays in `/visual-plan` (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5) — no script is touched | settled |

## Acceptance Criteria

1. `.agents/skills/visual-plan/SKILL.md` carries the heading `## Skip when trivial`, so `/slice`'s `/visual-plan` § *Skip when trivial* citation resolves.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --path .agents/skills/slice --limit 50` reports no `citation-drift` candidate.
3. The before-proof commands (`bash tests/run.sh tests/test-doc-conventions.sh tests/test-plan-render.sh`, the affected tests for the change, with `origin/master` at e7c14eb, and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | visual-plan heading is a name only | `/visual-plan` § *Skip when trivial* | `.agents/skills/visual-plan/SKILL.md` | — | 1, 2, 3 | `bash tests/affected.sh --run origin/master` | 1 file · 1 system · 3 ACs |
