---
implementation_paths:
  - .agents/skills/brainstorm/SKILL.md
---

# Spec: simplify — citation-drift in .agents/skills/brainstorm/SKILL.md

> Origin: #326 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-10-20) · Signal: `citation-drift` · Class: minor · Review status: **built** 2026-10-20

## Behavior

`/brainstorm`'s spec-writing step points a reader to the full Implementation Paths rules
with `/plan` § *Write the Spec*, but `/plan` has no heading by that name — the
section is `### 2. Write the Spec (MUST persist to disk)`. A reader or a
citation checker following the pointer finds nothing. After this change the
citation names the heading exactly, so it resolves. How `/brainstorm` and
`/plan` behave doesn't change.

## Inputs

- `.agents/skills/brainstorm/SKILL.md:142` — the drifted citation.
- `.agents/skills/plan/SKILL.md` § *2. Write the Spec (MUST persist to disk)* — the target; its paragraph on `implementation_paths` holds the path rules.

## Outputs

- `.agents/skills/brainstorm/SKILL.md`: one citation's heading text corrected; the line count stays the same.

## Edge Cases

- **`/plan` is not edited.** Renaming its heading to drop the step number (safe-moves 1) would make it the odd one out among `/plan`'s numbered `###` steps. That rename belongs to a whole-file change, not to this one-line fix.
- **No other caller.** `Write the Spec` appears only in these two files (outside `tasks/` history), so nothing else needs repointing.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the one citation at `brainstorm/SKILL.md:142`; `/plan`'s headings are out | settled (unattended pick) |
| D2 | Byte-identical: `/plan` in full, every other `/brainstorm` line, every test | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| D5 | Cite the exact numbered heading, as `/tidy` already cites `/sweep` § *2. Read the backlog* | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) — no heading is touched | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3) — no assertion pins the line | settled |
| S4 | One home per rule: the path rules stay in `/plan` (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5) — no script is touched | settled |

## Acceptance Criteria

1. Every `/plan` § citation in `.agents/skills/brainstorm/SKILL.md` resolves to a `##`/`###` heading in `.agents/skills/plan/SKILL.md`.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --path .agents/skills/brainstorm --limit 50` reports no `citation-drift` candidate.
3. The before-proof commands (`bash tests/run.sh <affected tests for the change>`, with `origin/master` at 2da4eab, and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | brainstorm cites plan by its heading | `/brainstorm` cites `/plan` § *2. Write the Spec (MUST persist to disk)* | `.agents/skills/brainstorm/SKILL.md` | — | 1, 2, 3 | `bash tests/test-citations.sh` | 1 file · 1 system · 3 ACs |
