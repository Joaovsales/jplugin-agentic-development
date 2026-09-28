---
implementation_paths:
  - .agents/skills/wrap-up-session/**
  - .agents/skills/yolo/SKILL.md
  - .agents/skills/auto-push/SKILL.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/tidy/SKILL.md
  - .agents/skills/memory-maintain/SKILL.md
  - .agents/skills/verify-evidence/SKILL.md
  - .agents/skills/verify-deployment/SKILL.md
  - .agents/skills/sync/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/task-registry/lanes/*.md
  - .agents/git-hooks/pre-push
  - .agents/agents/code-reviewer.md
  - .claude/agents/code-reviewer.md
  - README.md
  - specs/quality-receipt-closure.md
  - tests/test-doc-conventions.sh
  - tests/test-living-spec-reconciliation.sh
  - tests/test-routine-wrapup.sh
  - tests/test-routine-step-ledger.sh
  - tests/test-routine-escalation-handoff.sh
  - tests/test-sweep-routines.sh
  - tests/test-skill-invocation-chain.sh
  - tests/test-review-context.sh
  - tests/test-model-tiers.sh
  - tests/test-instruction-budget.sh
  - tests/test-closure.sh
  - tests/test-agents.sh
---

# Spec: /wrap-up-session in five named phases

## Behavior

`/wrap-up-session` is organised as five named phases, run in order:

1. **Bookkeeping**: the no-change exit, base-branch detection, `/learn`,
   `/memory-maintain`, the `tasks/todo.md` register and its Session Summary
   line, bug documents, project-context staleness, and the shortcut ledger.
2. **Reconcile**: living-spec reconciliation, the changed verification map,
   and the E2E coverage gate.
3. **Gate**: the closure loop starts here. The quality receipt is checked
   (re-entering `/quality-gate` at most once per tree, and approving a HOLD
   only in interactive runs), then the full suite runs through `cached-suite.sh`.
4. **Ship**: commit and push, the single pull-request procedure, then the
   remaining closure actions: mergeability, CI watch and repair, conflict
   repair, deployment verification, recording the closure, marking a partial
   PR as draft. Worktree integration comes last.
5. **Done**: the terminal PR assertion for unattended runs, and the report.

Every tree edit the session needs happens in Bookkeeping or Reconcile. From Gate
onward, `closure.py` names each action and the skill performs it. The only tree
edits after that point are the closure loop's own repairs. Each repair goes back
through the receipt and the suite before it is pushed.

The skill's lookup detail lives in reference files. SKILL.md keeps the rule and
the command:

- `references/spec-reconcile.md` owns reconciliation. It covers the outcome
  table, the semantic-comparison rule, legacy migration, deferred tasks through
  `upsert --derive-id`, the write-policy table and the report format.
- `references/closure-actions.md` has one section per closure action after
  `pr-sync`. It also holds the PR re-sync, linkage and handovers procedure and
  the push-failure table.
- `references/routines.md` § *Wrap-up on a routine branch* owns everything that
  applies only to `routine/` branches or unattended callers:
  - the fix-escalation terminal;
  - the step-ledger rows;
  - the draft and linkage table;
  - the `routine/fix` e2e handoff;
  - how an unattended run is detected.
- Design rationale stays in the specs that already hold it
  (`specs/quality-receipt-closure.md`, `specs/living-spec-reconciliation.md`,
  `specs/category-routines.md`). SKILL.md cites them and does not restate them.

Every early STOP ends through § *Terminal PR assertion*. The rule is stated once
in the overview, and the assertion's exits table lists each exit by the section
that produces it.

Other skills refer to wrap-up by section name, not by number. For example:
`/wrap-up-session` § *Full suite*. Every such citation must resolve.

No script changes its behavior. `closure.py` keeps its action names, its
observation shapes and its bounds.

## Inputs

These are unchanged: the session's branch and diff, `AGENTS.md`'s
`Full suite:` / `Affected tests:` lines, the quality receipt, the caller's
override table (yolo, auto-push), and the branch shape parsed by
`routine_branch.py`.

## Outputs

- **Artifacts:** unchanged. These are the commits, the PR body (with its
  `Quality receipt:` line, `## Closure` and `## Handovers` sections), the
  `tasks/` registers and the Done report.
- **Done report:** the `Closure:` line still quotes `closure.py`'s terminal
  line.
- **SKILL.md:** at most 300 lines, with no numbered step headings.

## Edge Cases

- **E2E gate before the suite.** The E2E walkthrough can write
  `tasks/e2e-log.md` or an `[e2e-gap]` document. It now runs before the receipt
  check and the suite, so those edits are covered by both.
- **`routine/fix` escalation.** A `routine/fix` investigation escalation stays
  terminal and skips the PR assertion. This is now stated in routines.md, and
  SKILL.md's overview points at it.
- **Unattended detection.** A caller that declares an unattended run (yolo,
  auto-push) names § *Terminal PR assertion* in its override table instead of
  "Step 8.5".
- **Exits table.** Tests that enumerate the table must fail when it lists
  nothing. They must not pass trivially.

## Decisions (planning session, 2026-09-28)

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | How callers refer to wrap-up's parts | By section name (§ *Heading*), never by step or phase number | user | `tests/test-citations.sh` verifies § citations, and insertions no longer force renumbering |
| 2 | Where the E2E coverage gate runs | In Reconcile, before the receipt and the suite | user | Its writes would otherwise land after `cached-suite.sh` hashed the tree |
| 3 | Scope of stale-reference fixes | Everything found, including behavioral drift in callers | user | A single pass leaves no reference pointing at a step that no longer exists |
| 4 | Process | Spec, then `/slice`, then a fresh-session `/build` | user | AGENTS.md workflow for a change this size |
| 5 | Heading style | Names only (`## Gate`), with the order given in an overview list; all `##`/`###` | assumed | test-citations resolves only `##`/`###` headings, and numbered headings recreate the 7.5/8.5 problem |
| 6 | How tests follow moved text | Repoint each assertion to the file the text now lives in, and re-key heading cuts to the new names; delete none without a replacement | assumed | About 190 assertions read SKILL.md only, and moving text must not weaken them |

## Acceptance Criteria

- SKILL.md is at most 300 lines, and `tests/test-instruction-budget.sh`
  enforces it. It has exactly five `##` phase headings, in order: Bookkeeping,
  Reconcile, Gate, Ship, Done. It has no `## Step` heading.
- Every behavior the pre-change tests asserted is still asserted, against the
  file that now holds it. The negative checks in `test-review-context.sh` and
  `test-model-tiers.sh` also cover the new reference files.
- `references/spec-reconcile.md` and `references/closure-actions.md` exist.
  `references/routines.md` has `## Wrap-up on a routine branch`. SKILL.md links
  all three.
- `/maintain-verification-skill --scope changed` appears before the E2E
  invocation, which appears before § *Quality receipt*, which appears before
  § *Full suite*, and a test asserts that order.
- The exits-table test in `test-routine-wrapup.sh` asserts it found exactly six
  exits, and that each named section mentions § *Terminal PR assertion*.
- `grep -rnE "wrap-up[^ ]* (§ 5\.1|Step [0-9])" .agents .claude README.md AGENTS.md`
  prints nothing, and every new § citation passes `tests/test-citations.sh`.
- The yolo and auto-push override tables drop the "Step 5.1 Apply Gate" and
  "MUST-FIX commit gate" rows. They cite wrap-up sections by name.
- The push-failure table in `verify-deployment/SKILL.md` merges and never
  rebases, matching § *Conflict repair*.
- The `code-reviewer` persona (both copies) no longer claims wrap-up dispatches
  it.
- The `task-registry` lane files and the README flow line describe wrap-up as
  checking the quality receipt, not as running review passes.
- `bash tests/run.sh` is green.

## Build Order

Sizing: 7 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 3: 9 files, because the closure-action text and every test pinning it must move together or the suite goes red between slices. Slice 4: 7 test files plus SKILL.md, because the heading rename breaks every section cut at once. Slice 6: 11 files, because it is one mechanical find-and-replace of step citations across callers. Slice 7: 13 files, because the 7 lane files each get one phrase.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Extract spec reconciliation | The Step 3.2 detail moves to `references/spec-reconcile.md`, and its prose tests are repointed | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/wrap-up-session/references/spec-reconcile.md`, `tests/test-living-spec-reconciliation.sh` | — | 3 | `bash tests/test-living-spec-reconciliation.sh && bash tests/test-skill-references.sh && bash tests/test-citations.sh` | 3 files · 2 systems · 1 AC |
| 2 | Extract routine-only wrap-up rules | routines.md gains `## Wrap-up on a routine branch` (fix-escalation terminal, step-ledger rows, draft/linkage table, `routine/fix` e2e handoff, unattended detection), and its tests are repointed | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/wrap-up-session/references/routines.md`, `tests/test-routine-wrapup.sh`, `tests/test-routine-step-ledger.sh`, `tests/test-routine-escalation-handoff.sh`, `tests/test-sweep-routines.sh` | 1 | 2 | `bash tests/test-routine-wrapup.sh && bash tests/test-routine-step-ledger.sh && bash tests/test-routine-escalation-handoff.sh && bash tests/test-sweep-routines.sh` | 6 files · 2 systems · 1 AC |
| 3 | Extract closure actions | `references/closure-actions.md` holds one section per action after `pr-sync`, plus PR re-sync, linkage, handovers and push failures. Negative checks extend to the new file | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/wrap-up-session/references/closure-actions.md`, `tests/test-doc-conventions.sh`, `tests/test-routine-wrapup.sh`, `tests/test-review-context.sh`, `tests/test-model-tiers.sh`, `tests/test-instruction-budget.sh`, `tests/test-routine-step-ledger.sh`, `tests/test-skill-invocation-chain.sh` | 2 | 2, 3 | `bash tests/test-doc-conventions.sh && bash tests/test-routine-wrapup.sh && bash tests/test-review-context.sh && bash tests/test-model-tiers.sh && bash tests/test-instruction-budget.sh` | 9 files · 2 systems · 2 ACs |
| 4 | Rewrite SKILL.md into five phases | Five named phases, E2E coverage moved into Reconcile, one exits table, SKILL.md at most 300 lines. The heading, order and budget tests are re-keyed | `.agents/skills/wrap-up-session/SKILL.md`, `tests/test-doc-conventions.sh`, `tests/test-routine-wrapup.sh`, `tests/test-living-spec-reconciliation.sh`, `tests/test-skill-invocation-chain.sh`, `tests/test-routine-step-ledger.sh`, `tests/test-instruction-budget.sh`, `tests/test-routine-escalation-handoff.sh` | 3 | 1, 4, 5 | `bash tests/test-doc-conventions.sh && bash tests/test-routine-wrapup.sh && bash tests/test-living-spec-reconciliation.sh && bash tests/test-skill-invocation-chain.sh && bash tests/test-instruction-budget.sh && bash tests/test-citations.sh` | 8 files · 2 systems · 3 ACs |
| 5 | Repoint caller override tables | The yolo and auto-push override tables cite wrap-up sections by name and drop the dead "Step 5.1 Apply Gate" and "MUST-FIX commit gate" rows. The auto-push "4 parallel passes" line is fixed | `.agents/skills/yolo/SKILL.md`, `.agents/skills/auto-push/SKILL.md`, `tests/test-routine-wrapup.sh` | 4 | 7 | `bash tests/test-routine-wrapup.sh && bash tests/test-citations.sh` | 3 files · 3 systems · 1 AC |
| 6 | Repoint remaining step citations | Every other wrap-up step-number reference becomes a § citation: build, quality-gate, tidy, memory-maintain, verify-evidence, sync, system-design-planning, the `closure.py` docstring, the pre-push comment and the test-closure label | `.agents/skills/build/SKILL.md`, `.agents/skills/quality-gate/SKILL.md`, `.agents/skills/tidy/SKILL.md`, `.agents/skills/memory-maintain/SKILL.md`, `.agents/skills/verify-evidence/SKILL.md`, `.agents/skills/sync/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md`, `.agents/skills/wrap-up-session/scripts/closure.py`, `.agents/git-hooks/pre-push`, `tests/test-closure.sh`, `tests/test-doc-conventions.sh` | 4 | 6 | `bash tests/test-citations.sh && bash tests/test-closure.sh && bash tests/test-doc-conventions.sh` | 11 files · 11 systems · 1 AC |
| 7 | Fix behavioral drift in callers | verify-deployment merges and never rebases. The code-reviewer persona (both copies) no longer claims wrap-up dispatches it. The lane files and the README describe the receipt check. The quality-receipt-closure spec's step diagram is updated | `.agents/skills/verify-deployment/SKILL.md`, `.agents/agents/code-reviewer.md`, `.claude/agents/code-reviewer.md`, `.agents/skills/task-registry/lanes/*.md`, `README.md`, `specs/quality-receipt-closure.md`, `tests/test-doc-conventions.sh`, `tests/test-agents.sh` | 6 | 8, 9, 10 | `bash tests/test-agents.sh && bash tests/test-doc-conventions.sh && bash tests/test-skills-table.sh` | 13 files · 7 systems · 3 ACs |

AC numbering follows § Acceptance Criteria in order (1 = SKILL.md budget and phases … 11 = full suite green). AC 11 is the last slice's close check. `/wrap-up-session` runs the full suite once, and every slice keeps its own tests green.

Build prompt:

```
Invoke `/build` for `specs/wrap-up-phases.md`.
Plan: `## Plan: wrap-up-phases` in `tasks/todo.md`, 7 slices, ready set <1>.
Files: .agents/skills/wrap-up-session/**, .agents/skills/yolo/SKILL.md, .agents/skills/auto-push/SKILL.md, .agents/skills/build/SKILL.md, .agents/skills/quality-gate/SKILL.md, .agents/skills/tidy/SKILL.md, .agents/skills/memory-maintain/SKILL.md, .agents/skills/verify-evidence/SKILL.md, .agents/skills/verify-deployment/SKILL.md, .agents/skills/sync/SKILL.md, .agents/skills/system-design-planning/SKILL.md, .agents/skills/task-registry/lanes/*.md, .agents/git-hooks/pre-push, .agents/agents/code-reviewer.md, .claude/agents/code-reviewer.md, README.md, specs/quality-receipt-closure.md, tests/test-doc-conventions.sh, tests/test-living-spec-reconciliation.sh, tests/test-routine-wrapup.sh, tests/test-routine-step-ledger.sh, tests/test-routine-escalation-handoff.sh, tests/test-sweep-routines.sh, tests/test-skill-invocation-chain.sh, tests/test-review-context.sh, tests/test-model-tiers.sh, tests/test-instruction-budget.sh, tests/test-closure.sh, tests/test-agents.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/wrap-up-phases.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Callers cite wrap-up by § section name, never a step or phase number (D1).
Constraints: E2E coverage runs in Reconcile, before the receipt check and the suite (D2).
Constraints: Headings are names only, at ## or ### level (D5).
Constraints: Every moved assertion is repointed, never deleted without a replacement (D6).
Constraints: No script behavior changes; closure.py action names stay.
```

## Implementation Paths

See `implementation_paths` frontmatter.
