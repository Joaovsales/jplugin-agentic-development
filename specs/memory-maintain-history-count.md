---
implementation_paths:
  - .agents/skills/memory-maintain/SKILL.md
  - .claude/skills/memory-maintain/SKILL.md
  - .claude/hooks/session-start.sh
  - tests/test-memory-maintain-doc.sh
  - tests/test-session-start.sh
---

# Spec: Memory maintenance history counting

## Behavior

The heavy-pass gate and session-start reminder count both session heading formats
already present in history: `### [YYYY-MM-DD] — title` and `## YYYY-MM-DD — title`.
New entries continue to use the canonical `/learn` template. Existing narrative
history does not require rewriting.

The cadence remains a positive multiple of five sessions. `--force` bypasses the
skill's cadence gate. The light pass and pending-glossary bootstrap retain their
current behavior. Catch-up and duplicate-sweep prevention are separate cadence
changes, outside this heading-recognition repair.

## Inputs

`tasks/history.md`, session-start hook input, and the skill's `--force` flag.

## Outputs

A consistent count in the skill and hook; the existing reminder at positive
multiples of five.

## Edge Cases

- Missing or empty history yields zero sessions and no reminder.
- Unrelated headings, prose dates, and malformed date headings do not count.
- Separate sessions on the same date count separately.
- Counts immediately below and above a multiple of five remain silent.

## Acceptance Criteria

- AC1: Five canonical entries trigger the real session-start reminder.
- AC2: Five alternate entries and five mixed-format entries each trigger the
  reminder with an accurate count; both fixtures fail on the original hook.
- AC3: Missing/empty history, four sessions, and six sessions remain silent;
  unrelated headings and malformed dates do not inflate the count.
- AC4: The skill and hook use equivalent recognition for both formats and the
  same positive-multiple-of-five gate; both skill copies remain byte-identical.
- AC5: Forced maintenance, the light pass, and glossary bootstrap are preserved;
  relevant tests and the full repository suite pass.

## Implementation Paths

- `.agents/skills/memory-maintain/SKILL.md` — canonical counting contract.
- `.claude/skills/memory-maintain/SKILL.md` — compatibility copy.
- `.claude/hooks/session-start.sh` — executable session counter and reminder.
- `tests/test-session-start.sh` — behavioral fixture regressions.
- `tests/test-memory-maintain-doc.sh` — skill contract and parity guards.
