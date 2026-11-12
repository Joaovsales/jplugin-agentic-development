---
implementation_paths:
  - .agents/skills/make-it-simpler/SKILL.md
  - .agents/skills/make-it-simpler/references/lens.md
  - .agents/skills/make-it-simpler/references/safe-moves.md
  - .agents/skills/make-it-simpler/scripts/signals.py
  - tests/test-make-it-simpler.sh
  - .claude-plugin/plugin.json
---
# Spec: retune the `simplify` routine so it can ship its own duplicate-rule finds

> Origin: owner review of the routine, 2026-11-11/12 (session overview of open PRs).
> The routine ran every day but ended in a silent exit most days: every confirmed
> `duplicate-rule` was filed `design-decision`, and no scheduled routine consumes that label.

## Behavior

1. **Cross-area deduplication is one area.** A `duplicate-rule` move that turns each
   copy of one rule into a one-line § citation of the rule's existing home counts as
   one area for the unattended cap, whatever skills the copies sit in — provided every
   citation resolves wherever the citing file is read and the pins are repointed in the
   same change. `references/safe-moves.md` § *Cross-area deduplication* is the one home
   of the conditions; `SKILL.md` § sizing cites it.
2. **A § citation line is a pointer, not a second home.** `signals.py`
   `detect_duplicate_rule` skips a line that holds a `` `<file>.md` § *<Heading>* `` or
   `` `/<skill>` § *<Heading>* `` citation, so the line a deduplication leaves behind in
   each copy is never re-flagged. `lens.md` § *Exclusions* states it.

## Edge Cases

- A citation into another skill's `references/` does not resolve from a plugin install
  (the reader's cwd is the consumer project). Such a home is not eligible: moving the rule
  into `.agents/references/` first is its own, larger change (#358's callout).
- A sub-agent persona under `.agents/agents/` starts in a fresh context and may never open
  a citation; its copies are not replaced unattended.
- A line that both restates a rule and cites a home is skipped too. Accepted: a cue
  detector trades that miss for never flagging its own output.

## Decisions

| # | Decision | Status |
|---|---|---|
| D1 | Widen the cap for `duplicate-rule` only; every other signal keeps one skill or one script | settled |
| D2 | Eligible citation targets: `/<skill>` § and `.agents/references/<file>.md` §, the two forms every harness resolves | settled |
| D3 | Leave `routines.md`'s `plan` row as is: the catalogue is generic, and scheduling a `plan` routine is each project's choice. With D1 most finds become tasks, so the queue of decisions shrinks instead of gaining a consumer | settled |
| D4 | Keep the record PR; removing it loses the `tasks/todo.md` index rows (no registry rebuild exists) and belongs with #381 | settled |
| D5 | safe-moves practices 1–5 apply; practice 4 (one home per rule) is the move itself | settled |

## Acceptance Criteria

- [ ] AC1: in a fixture repo, two files sharing a ≥60-character line that holds a § citation rank no `duplicate-rule`; two files sharing a plain ≥60-character line still do
- [ ] AC2: `lens.md` § *Exclusions* states that a § citation line is a pointer, never a duplicate home
- [ ] AC3: `safe-moves.md` § *Cross-area deduplication* names the conditions (one rule, citations only, eligible targets, personas kept, pins repointed); `SKILL.md` § sizing cites it by § name and stays within 150 lines
- [ ] AC4: `bash tests/test-make-it-simpler.sh`, `bash tests/test-citations.sh` and `bash tests/test-plugin-manifest.sh` pass; plugin version above master's

## Implementation Paths

- `.agents/skills/make-it-simpler/scripts/signals.py` — `detect_duplicate_rule` skips CITE lines
- `.agents/skills/make-it-simpler/references/lens.md`, `safe-moves.md`, `SKILL.md`
- `tests/test-make-it-simpler.sh` — AC1–AC3 pins
