---
implementation_paths:
  - .agents/skills/how/SKILL.md
  - .agents/skills/why/SKILL.md
---

# Spec: simplify — duplicate-rule in .agents/skills/how/SKILL.md

> Origin: #363 (`/make-it-simpler --unattended`, the `simplify` routine, 2026-10-25) · Signal: `duplicate-rule` · Class: minor · Review status: **built** 2026-10-25

## Behavior

`/how` and `/why` each close their tier paragraph with the same three lines on
Codex dispatch: use the named roles from `config/agent-policy.toml`, let the
policy own model and effort, and check the effective route when a local or
project configuration shadows a managed role. `.agents/references/model-routing.md`
§ *Codex dispatch* already owns that rule, and it names the exact role each skill
spawns (`explorer` for `/how`, `scout` for `/why`). After this change both skills
cite that section in one line. Neither skill behaves differently.

## Inputs

- `.agents/skills/how/SKILL.md:13-15` and `.agents/skills/why/SKILL.md:15-17` — the restated lines.
- `.agents/references/model-routing.md` § *Codex dispatch* — the one home.

## Outputs

- Both skills: a 3-line restatement becomes a 1-line citation.

## Edge Cases

- **`model-routing.md` isn't edited.** It's the home, so it stays byte-identical.
- **The Pi sentence stays.** Every dispatching skill states it in its own words,
  and it isn't part of this signal.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: only the Codex lines of `/how` and `/why`. Both homes are in scope, because a one-home fix has to touch every restatement | settled (unattended; `why` names itself `how`'s companion) |
| D2 | Byte-identical: every heading in both skills, `model-routing.md` in full, every test assertion | settled |
| D3 | Behavior changes: none | settled |
| D4 | Slice cap: 1 | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1) | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3). No assertion pins these lines | settled |
| S4 | One home per rule: `.agents/references/model-routing.md` § *Codex dispatch* (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5). No script is touched | settled |

## Acceptance Criteria

1. The sentence "On Codex, use the named roles from `config/agent-policy.toml`" appears in no skill, and `/how` and `/why` each cite `.agents/references/model-routing.md` § *Codex dispatch*.
2. `python3 .agents/skills/make-it-simpler/scripts/signals.py rank --limit 200` reports no `duplicate-rule` on the Codex lines of `/how` or `/why`. The remaining `duplicate-rule in .agents/skills/how/SKILL.md` hit, at line 68 (the model-routing note in § *Provenance*), is a different rule and out of scope.
3. The before-proof commands (`bash tests/affected.sh --run master` with `master` at c9f429a, and `bash tests/test-citations.sh`) give the same result after the change.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | how and why cite Codex dispatch | `/how` and `/why` cite `model-routing.md` § *Codex dispatch* instead of restating it | `.agents/skills/how/SKILL.md`, `.agents/skills/why/SKILL.md` | — | 1, 2, 3 | `bash tests/test-citations.sh` | 2 files · 1 system · 3 ACs |
