---
implementation_paths:
  - .agents/skills/system-design-planning/SKILL.md
---

# Spec: simplify — duplicate-rule in .agents/skills/system-design-planning/SKILL.md

> Origin: #384 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-11-07) · Signal: `duplicate-rule` · Class: minor · Review status: **built** 2026-11-07

## Behavior

`/system-design-planning` § *6. Render* restates what `/visual-plan` § *Process*
already owns: the list of sections the renderer types, that `flow` and
`sequence` fences become SVG diagrams, and the `<spec>:<line>: <reason>` refusal
that writes no page. After this change § *6. Render* keeps what is specific to
this skill — the render command, the rule that this skill fixes the named spec
line itself and renders again, the reason (approval attaches to a page that
shows every row), the commit-beside-the-spec rule and its Required output — and
cites `/visual-plan` § *Process* for the rest. The skill behaves the same way.

## Inputs

- `.agents/skills/system-design-planning/SKILL.md` § *6. Render* (lines 223–239 at 4abdf40).
- `.agents/skills/visual-plan/SKILL.md` § *Process*, which is the home.

## Outputs

- `/system-design-planning` § *6. Render*: a 7-line renderer paragraph and a 2-line commit paragraph become one 5-line paragraph with a citation (341 → 336 lines).

## Edge Cases

- **The refusal remedy differs on purpose.** `/visual-plan` reports the line and stops, because it never edits a spec. `/system-design-planning` owns the spec it is writing, so it fixes the line and renders again. That sentence stays in this skill.
- **`/visual-plan` isn't edited.** It is the home, so it stays byte-identical.
- **Pinned strings stay.** `tests/test-plan-render.sh` § wiring pins the render command and forbids `content-model.json`, `visual-render.py` and the phrase `text blocks` inside three backticks. `tests/test-doc-conventions.sh` pins `✓ Visual written:` before `### 7. Review Loop`. All of these are unchanged.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: only § *6. Render*'s renderer and commit paragraphs. The § *6* heading, the command block, the Required output line and the `/diagram` paragraph are out of scope | settled (unattended) |
| D2 | Byte-identical: every heading, the render command, `✓ Visual written: /absolute/path/specs/<feature>.plan.html`, `/visual-plan` in full, and every test assertion | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1). No heading changes | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2). The new pointer is `/visual-plan` § *Process*, a `##` heading | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3). No assertion pins the removed sentences | settled |
| S4 | One home per rule: `/visual-plan` § *Process* (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5). No script is touched | settled |

## Acceptance Criteria

1. `/system-design-planning` § *6. Render* cites `/visual-plan` § *Process*, and the sentence "The renderer types the known sections" appears in no skill other than `/visual-plan`, which uses its own wording.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --limit 200` reports no `duplicate-rule` on `.agents/skills/system-design-planning/SKILL.md` for the renderer's section list.
3. The before-proof commands (the covering set `tests/test-doc-conventions.sh`, `tests/test-grilling-adoption.sh`, `tests/test-skill-frontmatter.sh`, `tests/test-skill-references.sh`, plus `tests/test-plan-render.sh`, `tests/test-skill-invocation-chain.sh` and `bash tests/test-citations.sh`) give the same result after the change.

## Implementation Paths

- `.agents/skills/system-design-planning/SKILL.md` — § *6. Render* is the only section edited.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | system-design-planning cites visual-plan's Process | § *6. Render* cites `/visual-plan` § *Process* instead of restating the renderer | `.agents/skills/system-design-planning/SKILL.md` | — | 1, 2, 3 | `bash tests/test-plan-render.sh && bash tests/test-citations.sh` | 1 file · 1 system · 3 ACs |
