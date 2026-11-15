---
implementation_paths:
  - .agents/skills/quality-gate/SKILL.md
  - tests/test-doc-conventions.sh
---

# Spec: simplify — duplicate-rule in .agents/skills/quality-gate/SKILL.md

> Origin: #372 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-12) · Signal: `duplicate-rule` · Class: minor · Review status: **built** 2026-11-12

## Behavior

`/quality-gate` § *Finding Model* restated `.agents/references/finding-model.md`
§ *Four axes*, § *Emission format*, § *Confidence anchors* and § *Gates* almost
word for word, and the copy had drifted: its gate list lacked "a fix that moves a
module boundary is never `gated_auto`". After this change the gate reads
finding-model.md before Phase 1, resolved as *Claude Code Enhancements* already
describes for the Phase 4 dispatch, and cites those four sections. § *Apply Gate*
keeps only what is specific to this gate: apply in-phase and then run the tests,
the one verification attempt for a `MUST-FIX` at `50`, and the rule that an
unapplied `MUST-FIX` stays a `MUST-FIX`. The owner decided the deduplication on
2026-11-12 (#372 evidence, PR #390).

## Inputs

- `.agents/skills/quality-gate/SKILL.md` § *Finding Model* (lines 40–93 at 17a7a15).
- `.agents/references/finding-model.md`, the home, unchanged.
- `tests/test-doc-conventions.sh` § Tier 2 (M2), which pinned the restated machinery in the gate.

## Outputs

- `/quality-gate` § *Finding Model*: 54 lines → 26 (SKILL.md 400 → 372).
- M2 no longer loops over the gate; it pins the gate's four § citations, the home's path, the read before Phase 1, the stop line, `` `gated_auto` **and** `confidence >= 75` `` with a pointer to the home for the full rule list, and the absence of the home's anchor rows and gate wording.

## Edge Cases

- **The gate now picks up the module-boundary rule** from § *Gates*, which its copy had dropped. That is the drift the change removes, declared below.
- **A missing finding-model.md** stops the gate before Phase 1 with the refusal Item 7 gives (one message for one condition), instead of at Phase 4's dispatch. The lookup order stays in *Claude Code Enhancements* (Item 7): that paragraph is pinned word for word in four dispatch skills by `tests/test-review-context.sh`, so moving it is a cross-skill change outside this run (Phase 4 review finding, recorded in the PR).
- **Phase cites stay.** Phases 1–4 cite the bold **Apply Gate** and Phase 3's body pins the token `Apply Gate` (quality-receipt test); the `### Apply Gate` heading stays.
- **`/software-design-expert-review` also restates the model.** Out of scope: one area per run.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: `/quality-gate` § *Finding Model* and its M2 pin. `finding-model.md` and `/software-design-expert-review` are out | settled (owner 2026-11-12) |
| D2 | Byte-identical: every heading (`## Finding Model`, `### Apply Gate`), every phase body, finding-model.md, the receipt and its script | settled |
| D3 | Behavior changes: finding-model.md is read before Phase 1 rather than first at Phase 4; the module-boundary gate now applies in Phases 1–4; a missing home stops the gate before Phase 1 with Item 7's refusal | settled |
| D4 | Slice cap: 1 | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1). No heading changes | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3). The M2 token pins on the gate become citation pins, and the home keeps its own M2 pins | settled |
| S4 | One home per rule: `.agents/references/finding-model.md` (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5). No script is touched | settled |

## Acceptance Criteria

1. `/quality-gate` § *Finding Model* cites finding-model.md § *Four axes*, § *Emission format*, § *Confidence anchors* and § *Gates*, and holds no confidence-anchor table or gate bullet list.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --path .agents/skills/quality-gate/SKILL.md` reports no `duplicate-rule` against finding-model.md's anchors or gates. Command-validated once in the PR's after-proof, not a suite assertion: the M2 `assert_not_contains` pins on the home's anchor rows and gate wording are the regression guard.
3. The before-proof commands give the same result after the change, with M2 repointed.

## Implementation Paths

- `.agents/skills/quality-gate/SKILL.md` — § *Finding Model* only.
- `tests/test-doc-conventions.sh` — the M2 loop and its repointed pins.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | quality-gate cites the finding model | § *Finding Model* cites finding-model.md instead of restating it; M2 repointed | `.agents/skills/quality-gate/SKILL.md`, `tests/test-doc-conventions.sh` | — | 1, 2, 3 | `bash tests/test-doc-conventions.sh && bash tests/test-citations.sh` | 2 files · 1 system · 3 ACs |
