---
implementation_paths:
  - .agents/skills/tidy/SKILL.md
---

# Spec: simplify — duplicate-rule in .agents/skills/tidy/SKILL.md

> Origin: #231 (`/make-it-simpler`, interactive, 2026-09-30) · Signal: `duplicate-rule` · Class: minor · Review status: **built** 2026-09-30

## Behavior

`/tidy` § *Filing a Tier 2 finding* restates, nearly word for word, the dedupe-set
rule that `/sweep` § *2. Read the backlog* owns: which open tasks form the set, how
a `file:line` match updates the existing task, and why an escalated task is
hands-off. After this change `/tidy` cites that section and keeps only its
own difference: an escalated task's reference goes in *the session record*.
How `/tidy` behaves doesn't change.

## Inputs

- `.agents/skills/tidy/SKILL.md:176-182` — the restated paragraph.
- `.agents/skills/sweep/SKILL.md` § *2. Read the backlog* — the one home.

## Outputs

- `.agents/skills/tidy/SKILL.md`: a 7-line paragraph becomes a 2-line citation.

## Edge Cases

- **The six session-record sections stay.** `/tidy` § *Outputs* also restates the
  six record sections `/sweep` defines, but `tests/test-doc-conventions.sh`
  pins them in `/tidy` by order (tidy spec AC-11: a consumer reads *Filed* by
  position), and tidy's wording is adapted to checks, not copied. That's a
  deliberate contract, not a duplicate. It's out of scope.
- **`/sweep` is not edited.** It's the home, so its wording stays byte-identical.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: only the dedupe-set paragraph of `/tidy` § *Filing a Tier 2 finding*; § *Outputs*'s six sections are out | settled (operator pick) |
| D2 | Byte-identical: every `/tidy` heading, `/sweep` in full, every test assertion | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3) — no assertion pins the paragraph | settled |
| S4 | One home per rule: `/sweep` § *2. Read the backlog* (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5) — no script is touched | settled |

## Acceptance Criteria

1. `/tidy` states the dedupe-set rule only by citing `/sweep` § *2. Read the backlog*; the sentence "An open task carrying the configured escalation label" appears in exactly one skill.
2. `/tidy` still says an escalated task's existing reference is recorded in its session record.
3. The before-proof commands (`bash tests/affected.sh --run origin/master`, with `origin/master` at a849698 and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | tidy cites sweep dedupe set | `/tidy` cites `/sweep` § *2. Read the backlog* instead of restating it | `.agents/skills/tidy/SKILL.md` | — | 1, 2, 3 | `bash tests/test-citations.sh` | 1 file · 1 system · 3 ACs |
