---
implementation_paths:
  - .agents/skills/tidy/SKILL.md
---

# Spec: simplify — citation-drift in .agents/skills/tidy/SKILL.md

> Origin: #309 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-14) · Signal: `citation-drift` · Class: minor · Review status: **built** 2026-11-14

## Behavior

`/tidy` § *Filing a Tier 2 finding* says each upsert mirrors `/sweep` § *File*,
but `/sweep` has no heading by that name — the section is `### 5. File`. A
reader or a citation checker following the pointer finds nothing. After this
change the citation names the heading exactly, so it resolves. How `/tidy` and
`/sweep` behave doesn't change.

## Inputs

- `.agents/skills/tidy/SKILL.md:182` — the drifted citation.
- `.agents/skills/sweep/SKILL.md` § *5. File* — the target.

## Outputs

- `.agents/skills/tidy/SKILL.md`: one citation's heading text corrected; the line count stays the same.

## Edge Cases

- **`/sweep` is not edited.** Renaming `### 5. File` to drop the step number (safe-moves 1) would make it the odd one out among `/sweep`'s numbered `###` steps; that belongs to a whole-file change.
- **`specs/tidy-skill.md:108` is not edited.** It is the design record that quoted the line; `specs/` is history, not a caller.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the one citation at `tidy/SKILL.md:182`; `/sweep`'s headings are out | settled (unattended pick) |
| D2 | Byte-identical: `/sweep` in full, every other `/tidy` line, every test | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| D5 | Cite the exact numbered heading, as the line above already cites `/sweep` § *2. Read the backlog* | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) — no heading is touched | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3) — no assertion pins the line | settled |
| S4 | One home per rule: the filing rules stay in `/sweep` (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5) — no script is touched | settled |

## Acceptance Criteria

1. Every `/sweep` § citation in `.agents/skills/tidy/SKILL.md` resolves to a `##`/`###` heading in `.agents/skills/sweep/SKILL.md`.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --path .agents/skills/tidy --limit 50` reports no `citation-drift` candidate.
3. The before-proof commands (`bash tests/affected.sh --run origin/master`, with `origin/master` at 317a717, and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | tidy cites sweep by its heading | `/tidy` cites `/sweep` § *5. File* | `.agents/skills/tidy/SKILL.md` | — | 1, 2, 3 | `bash tests/test-citations.sh` | 1 file · 1 system · 3 ACs |
