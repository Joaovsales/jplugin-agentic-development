---
implementation_paths:
  - .agents/skills/slice/SKILL.md
  - tests/test-doc-conventions.sh
---

# Spec: simplify — duplicate-rule in .agents/skills/slice/SKILL.md

> Origin: #308 (`/make-it-simpler --unattended`, simplify routine, 2026-10-20) · Signal: `duplicate-rule` · Class: minor · Review status: **built** 2026-10-20

## Behavior

`/slice` Step 4 writes the plan block. Its `SKILL.md` shows the fenced example
and then restates, as four bullets, the grammar rules that
`references/plan-block.md` already owns: slice names never start with `/`,
in-place replacement and one block per feature, when `> Issue:` is written and
`> Spec:` standing alone, and what the `[ ] TDD:` rows are. The two copies
already differ in wording, although `SKILL.md` says they must stay byte-for-byte
identical. After this change `SKILL.md` keeps the fenced example, which a test
pins byte-identical to the reference, and cites `references/plan-block.md` for
the grammar. The reference is the only place the rules are written.

## Inputs

- `.agents/skills/slice/SKILL.md` § *4. Mint ids and write the plan block into `tasks/todo.md`*: the four grammar bullets under the fenced example.
- `.agents/skills/slice/references/plan-block.md`: the one home.
- `tests/test-doc-conventions.sh` § slice: three pins that read the bullets in `SKILL.md`.

## Outputs

- `.agents/skills/slice/SKILL.md`: the four bullets (8 lines) become a 3-line citation. The lead-in sentence now says only the fenced example is mirrored.
- `tests/test-doc-conventions.sh`: the pins on "never start with `/`", "replaced section by section, in place" and "Never two blocks for one feature" now check `references/plan-block.md`, the file the rules now live in.

## Edge Cases

- **The fenced example stays in both files.** A test pins it byte-identical, and `test-living-spec-reconciliation.sh` pins `> Spec: specs/<feature>.md` in `SKILL.md`. That duplication is deliberate and is out of scope.
- **The build-prompt template stays in both files.** A test also pins it byte-identical. Out of scope.
- **`plan-block.md` is not edited.** It is the home, so its wording stays byte-identical.
- **Wording drift.** The reference limits in-place replacement to a block "with `[ ]` rows", but `SKILL.md` stated the rule without that condition. The reference's wording now governs. This is declared under Behavior changes.

## Decisions

| # | Decision | Status |
|---|----------|--------|
| D1 | Scope: only the four grammar bullets of `/slice` Step 4 and the lead-in sentence; the fenced example and the build prompt stay | settled (unattended pick) |
| D2 | Byte-identical: every `/slice` heading, `references/plan-block.md` in full, the fenced example, the build-prompt template, every assertion's intent | settled |
| D3 | Behavior changes: one. The in-place replacement rule now reads only from `plan-block.md`, which limits it to a block with `[ ]` rows | settled |
| D4 | Slice cap: 1 | settled |
| S1 | Headings are names only (`make-it-simpler/references/safe-moves.md` 1). No heading changes | settled |
| S2 | Callers cite by § name; `bash tests/test-citations.sh` passes before and after (safe-moves 2) | settled |
| S3 | A moved assertion is repointed, never deleted without a replacement (safe-moves 3). The three pins move to `plan-block.md` | settled |
| S4 | One home per rule: `.agents/skills/slice/references/plan-block.md` (safe-moves 4) | settled |
| S5 | No script behavior change unless declared minor (safe-moves 5). No script is touched | settled |

## Acceptance Criteria

1. The sentence "`> Issue:` is written when `--issue` is given" appears in `references/plan-block.md` and not in `slice/SKILL.md`. The `duplicate-rule` homes `signals.py rank` finds in `slice/SKILL.md` are only the build-prompt lead-in, which is deliberately mirrored (Edge Cases).
2. `slice/SKILL.md` Step 4 cites `.agents/skills/slice/references/plan-block.md` for the grammar and still carries the fenced example.
3. The before-proof commands give the same result after the change: `bash tests/affected.sh --run origin/master` (origin/master at 4c2f3c2) and `bash tests/test-citations.sh`.

## Build Order

Sizing: 1 slice. Ceiling: per `slice/references/sizing.md`. Over: none.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | slice cites plan-block grammar | `/slice` Step 4 cites `references/plan-block.md` instead of restating it | `.agents/skills/slice/SKILL.md`, `tests/test-doc-conventions.sh` | — | 1, 2, 3 | `bash tests/test-doc-conventions.sh` | 2 files · 1 system · 3 ACs |
