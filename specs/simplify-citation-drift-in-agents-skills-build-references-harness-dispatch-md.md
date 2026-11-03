---
implementation_paths:
  - .agents/skills/build/references/harness-dispatch.md
  - .agents/skills/build/SKILL.md
---

# Spec: simplify — citation-drift in .agents/skills/build/references/harness-dispatch.md

> Origin: #378 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-02) · Signal: `citation-drift` · Class: minor · Review status: **built** 2026-11-02

## Behavior

`/build`'s harness-dispatch reference sends a Pi reader to the regression ladder
with `/build` § *Escalation ladder for test regressions* (in
`.agents/skills/build/SKILL.md`). The target is the bold label
`**Escalation ladder for test regressions:**`. Both citation resolvers
(`signals.py`, `tests/test-citations.sh`) read a bold label as `**<Name>**` or
`**<Name>.**`, so the colon becomes part of the name and the pointer resolves to
nothing. The citation is also in the `/skill` form, which `test-citations.sh`
doesn't check, so it can drift again without a test noticing.

After this change the label ends in a period, matching the other bold labels in
`/build` (`**A refusal is not a test result.**`). The citation uses the checked
`` `<path>.md` § *<Heading>* `` form, which also drops the parenthetical path.
How `/build` and the Pi dispatch rules behave doesn't change.

## Inputs

- `.agents/skills/build/references/harness-dispatch.md:32`: the drifted citation.
- `.agents/skills/build/SKILL.md:29`: the label it targets.

## Outputs

- `.agents/skills/build/SKILL.md`: one label's trailing colon becomes a period.
- `.agents/skills/build/references/harness-dispatch.md`: one citation rewritten to the path form. Line counts are unchanged.

## Edge Cases

- **No other caller.** `Escalation ladder for test regressions` appears only in these two files (outside `tasks/` history).
- **No pin.** No test asserts the label text with its colon. `tests/test-model-tiers.sh` § 12 pins the ladder's rules, not its label.
- **The label stays a label.** Promoting it to a `###` heading would re-nest the ladder inside `/build`'s section structure, which is a larger change than the fix needs.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: the one citation at `harness-dispatch.md:32` and its target label at `build/SKILL.md:29` | settled (unattended pick) |
| D2 | Byte-identical: every other line of both files, every script, every test | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| D5 | Fix both ends: the label takes the period form both resolvers accept, and the citation takes the path form `test-citations.sh` checks, so the pointer is guarded from now on | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1): the label loses its punctuation and keeps its name | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3): no assertion pins either line | settled |
| S4 | One home per rule: the ladder stays in `/build` (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5): no script is touched | settled |

## Acceptance Criteria

1. `harness-dispatch.md` cites `` `.agents/skills/build/SKILL.md` § *Escalation ladder for test regressions* ``, and `build/SKILL.md` carries the label `**Escalation ladder for test regressions.**`.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --path .agents/skills/build --limit 50` reports no `citation-drift` candidate.
3. `bash tests/test-citations.sh` passes and now checks this citation. The before-proof commands (`bash tests/affected.sh --run 3c49472`, `bash tests/test-citations.sh`) pass after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | harness-dispatch cites the ladder by a resolvable name | the ladder label resolves and its citation is test-checked | `.agents/skills/build/SKILL.md`, `.agents/skills/build/references/harness-dispatch.md` | — | 1, 2, 3 | `bash tests/test-citations.sh` | 2 files · 1 system · 3 ACs |
