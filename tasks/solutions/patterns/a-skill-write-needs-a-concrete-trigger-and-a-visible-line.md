---
title: A skill's write needs a concrete trigger and a visible output line, or the model narrates instead of acting
date: 2026-09-21
problem_type: pattern
module: skill prose — .agents/skills/brainstorm/references/domain-modeling.md and brainstorm Step 3
tags: [skill-authoring, prose, e2e, triggers, glossary]
applies_when: writing skill prose that tells the model to write a file "when" some condition holds, and no static test can pin whether the write happened
---

## The rule

An instruction of the form "write X the moment Y resolves" produces narration, not
a write: the model correctly recognises Y, says so, and moves on. Bind the write
to a **turn boundary** it cannot miss ("the reply to the answer that resolves Y
opens with the write, before the next question") and give the action a **visible
output line** so a reader can tell "wrote" from "did not need to". Without the
line, a no-op and a success look identical in the transcript.

## This session

The domain-modeling layer first said terms are written "the moment it resolves".
The first `/brainstorm` e2e run recognised **quarantine** as new project
vocabulary in turn 1, took the user's answer in turn 2, and produced round 2 with
no `Edit` at all (`tasks/e2e-log.md:1243`). Nothing failed; the term simply never
reached `tasks/concepts.md`.

The prose was then tightened in two places:

- `references/domain-modeling.md:38-39` — "A term resolves when the user's answer
  …" and the write happens right then, not at session end.
- `brainstorm/SKILL.md:52` — "The moment a term resolves is the user's answer. The
  reply to a round opens with the glossary writes that round's answers settled",
  reported as `glossary: **term** written`.

The second run wrote the entry in the first reply after the answer and printed
the line (`tasks/e2e-log.md`, AC 12, run 2). Same model, same idea, same
harness; only the trigger and the visible line changed.

## Why the static suite cannot catch this

`tests/test-grilling-adoption.sh` pins that the prose *mentions* the write. Only
an e2e run shows whether the write *happens*, which is why AC 12 is user-facing
and why the first run is recorded as the finding rather than deleted.

## Related

- [../process/ship-the-write-half-or-neither.md](../process/ship-the-write-half-or-neither.md)
  — the same "write half missing" shape one layer down, where the missing half
  was an unimplemented command rather than an untriggered instruction.
- [../conventions/write-skill-prose-so-the-static-guards-can-read-it.md](../conventions/write-skill-prose-so-the-static-guards-can-read-it.md)
  — the static guards read tokens; this document is about the behaviour the
  tokens cannot see.
