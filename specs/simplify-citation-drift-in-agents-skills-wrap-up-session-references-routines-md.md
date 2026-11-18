---
implementation_paths:
  - .agents/skills/tidy/SKILL.md
  - tests/test-doc-conventions.sh
---

# Spec: simplify — citation-drift in .agents/skills/wrap-up-session/references/routines.md

> Origin: #437 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-18) · Signal: `citation-drift` · Class: minor · Review status: **built** 2026-11-18

## Behavior

Three files point at `/tidy`'s check table with `/tidy` § *The checks* —
`wrap-up-session/references/routines.md:402`, `task-registry/lanes/tidy.md:10` and
`wrap-up-session/references/routine-prompts/tidy.md:13` — but the heading in
`.agents/skills/tidy/SKILL.md` is `### 1–11. The checks`. A reader or a citation
checker following the pointer finds no heading by that name. After this change
the heading is `### The checks`, so all three citations resolve, and the heading
carries no count that can go stale when a check is added. How `/tidy` behaves
doesn't change.

## Inputs

- `.agents/skills/tidy/SKILL.md:85` — `### 1–11. The checks`.
- The three callers above, each citing `/tidy` § *The checks*.
- `tests/test-doc-conventions.sh:215` — reads the check list from the table under a heading matched by `/^### [0-9]+.*The checks/`.

## Outputs

- `.agents/skills/tidy/SKILL.md`: one heading renamed; line count 347 → 347.
- `tests/test-doc-conventions.sh`: the awk heading pattern repointed to `/^### The checks/`; line count unchanged.

## Edge Cases

- **Fixing the callers instead** would edit three files in two other skills and keep a count (`1–11`) in a heading — the drift #202 removed from the restatements. One heading rename resolves all three.
- **`### 0. Preconditions` keeps its number.** Renaming it is not needed for any citation; it is out of scope.
- **The test reads the table by its heading.** A rename without repointing the awk pattern would make the list empty and fail the non-vacuity assertion — repointed in the same commit (safe-moves 3).

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the `/tidy` checks heading and the one test pattern that finds it; the three callers stay byte-identical | settled (unattended pick) |
| D2 | Byte-identical: every other line of `/tidy`, the three callers, every assertion message | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| D5 | Rename the heading rather than repoint the callers — one edit resolves three citations and drops a count | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) — the renamed heading drops its step range | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3) — the awk heading pattern follows the rename | settled |
| S4 | One home per rule: the check list stays in `/tidy`'s table (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5) — no script is touched | settled |

## Acceptance Criteria

1. `.agents/skills/tidy/SKILL.md` has a `### The checks` heading, and every `/tidy` § *The checks* citation outside `tasks/` resolves to it.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --path .agents/skills/wrap-up-session --limit 50` reports no `citation-drift` candidate.
3. The before-proof commands (`bash tests/run.sh <affected tests>`, base `origin/master` at 887e959, and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | tidy's checks heading is a name | `/tidy` § *The checks* resolves | `.agents/skills/tidy/SKILL.md`, `tests/test-doc-conventions.sh` | — | 1, 2, 3 | `bash tests/affected.sh --run origin/master` | 2 files · 1 system · 3 ACs |
