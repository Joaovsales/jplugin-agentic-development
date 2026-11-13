---
implementation_paths:
  - tasks/solutions/README.md
  - project-template/tasks/solutions/README.md
  - tests/test-solutions-schema.sh
---

# Spec: simplify — duplicate-rule in .agents/skills/learn/SKILL.md

> Origin: #387 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-13) · Signal: `duplicate-rule` · Class: minor · Review status: **built** 2026-11-13

## Behavior

`/learn` § *4. Score Overlap Before Writing* is the home of the overlap-scoring
rule: the per-track dimension table, the cross-track cap, the score/action table
and the never-a-contradicting-sibling rule. `tasks/solutions/README.md`
§ *Writing rules (`/learn`)* and its byte-identical seed
`project-template/tasks/solutions/README.md` restated all four nearly verbatim
and pointed at the home by step number ("`/learn` Step 4 defines each"). After
this change both READMEs cite the home by § name and keep only what is
README-specific: the slug-collision suffix rule. The owner decided the
deduplication on 2026-11-12 (#387 evidence, PR #390), reversing #168's "the same
in every copy" pinning on purpose.

## Inputs

- `tasks/solutions/README.md` § *Writing rules (`/learn`)* (lines 101–122 at 01e7cba) and its seed copy.
- `.agents/skills/learn/SKILL.md` § *4. Score Overlap Before Writing*, the home, unchanged.
- `tests/test-solutions-schema.sh` § Overlap dimensions, which pinned the rows and the cap in all three files.

## Outputs

- Both READMEs: § *Writing rules (`/learn`)* 22 lines → 5; each file 122 → 105 lines. The two stay byte-identical.
- § Overlap dimensions keeps all four pins on `/learn`; on each README it pins the § citation and the slug-collision rule, and the absence of the dimension rows, the cap and the score table.

## Edge Cases

- **The citation is read outside the plugin tree.** `tasks/solutions/README.md` sits in a project, where `/learn` is an installed skill: a `/<skill>` § citation resolves there (`safe-moves.md` § *Cross-area deduplication*), a path into `.agents/skills/` might not. `tests/test-citations.sh` does not scan `tasks/` or `project-template/`, so § Overlap dimensions asserts the cited heading exists in `/learn`.
- **`/memory-maintain` states the cap too.** Out of scope: its merge test gives the cap as its own reason (pinned separately, line 209), and one area per run.
- **The heading's step number.** `4. Score Overlap Before Writing` is `/learn`'s heading as it stands, and the citation quotes it exactly. § Overlap dimensions pins that heading, so renaming it fails the suite until the READMEs follow (as `tests/test-memory-maintain-doc.sh` already does for `/memory-maintain`'s pointer).

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the two store READMEs' § *Writing rules (`/learn`)* and their § Overlap dimensions pins. `/learn` and `/memory-maintain` are out | settled (owner 2026-11-12) |
| D2 | Byte-identical: `/learn/SKILL.md`, every README heading, every other README section, the two READMEs to each other | settled |
| D3 | Behavior changes: none — no script is touched and the rule's one statement is unchanged | settled |
| D4 | Slice cap: 1 | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1). No heading changes | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2). The step-number pointer becomes a § citation | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3). The README row and cap pins become citation and absence pins | settled |
| S4 | One home per rule: `/learn` § *4. Score Overlap Before Writing* (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5). No script is touched | settled |
| S6 | Cross-area deduplication (`safe-moves.md` § *Cross-area deduplication*): one rule, each copy becomes a § citation of the existing home, its pins repointed in the same change | settled |

## Acceptance Criteria

1. Both READMEs' § *Writing rules (`/learn`)* cite `/learn` § *4. Score Overlap Before Writing*, keep the slug-collision rule, and hold no dimension row, cross-track cap or score table.
2. `/learn` still carries both dimension rows, the cap and "the five dimensions of the candidate's track".
3. The before-proof commands give the same result after the change, with § Overlap dimensions repointed.

## Implementation Paths

- `tasks/solutions/README.md`, `project-template/tasks/solutions/README.md` — § *Writing rules (`/learn`)* only.
- `tests/test-solutions-schema.sh` — § Overlap dimensions.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | store READMEs cite /learn's overlap scoring | § *Writing rules (`/learn`)* cites the home instead of restating it; § Overlap dimensions repointed | `tasks/solutions/README.md`, `project-template/tasks/solutions/README.md`, `tests/test-solutions-schema.sh` | — | 1, 2, 3 | `bash tests/test-solutions-schema.sh && bash tests/test-citations.sh` | 3 files · 1 system · 3 ACs |
