---
title: Anchor a transcript grader on the record's type discriminator, not on a key the schema shares
date: 2026-09-16
problem_type: test-failure
module: .agents/skills/eval/scripts/grade-skill-loads.sh
tags: [eval, grader, transcript-format, false-positive, jsonl]
symptoms: The first grading pass of the /go triggerability eval (eight blind transcripts, four boundary prompts x N=2) died on every transcript with "holds a Skill block this parser cannot read — transcript format changed" and produced zero measurements.
root_cause: The load anchor was a bare `"name":"Skill"`. Transcripts now carry the tool schema inline as `{"name":"Skill","description":"Invoke a skill..."}`, so the anchor matched the schema object on every candidate, the input-shape check then failed, and a run in which nobody loaded anything was reported as a format change instead of as NONE.
resolution: The anchor requires the record's type discriminator earlier in the same JSON object — `"type":"tool_use"[^{}]*"name":"Skill"` — and tests/test-eval-skill.sh gained a fixture that carries only the inline schema and must grade NONE with exit 0.
---

**Status:** fixed — 2026-09-16 (branch `routing`, the `/go` front-door build).

## What happened

`grade-skill-loads.sh` counts a skill load only from a real `Skill` tool-use
block, so it anchors on a JSON key and then checks the block's `input` shape.
The anchor was the key `"name":"Skill"` alone. Transcripts had since started
carrying every tool's schema inline, and the schema object for the `Skill` tool
also contains `"name":"Skill"`. Eight transcripts in which no candidate loaded
any skill therefore each hit the anchor once, failed the shape check, and died
with the "format changed" message — a result that reads as environment drift,
not as the measurement it actually was (0/8 fired).

## The fix

The anchor now requires the type discriminator of the record it wants, kept
inside one object by the `[^{}]*` span:

```
BLOCK='"type":[[:space:]]*"tool_use"[^{}]*"name":[[:space:]]*"Skill"'
```
(`.agents/skills/eval/scripts/grade-skill-loads.sh:40`; the abort it used to
trip is at `:59`). `tests/test-eval-skill.sh:117-126` pins the inline-schema
fixture as "not an unreadable block" and "grades as no load".

## Prevention rule

- **A grep-based grader anchors on the discriminator of the record type it
  counts, never on a key other record types share.** A tool-use block, a tool
  schema, and a candidate's own console output can all contain the tool's
  name; only the `"type"` field tells them apart.
- **"Format changed" on every one of N inputs is a grader defect, not a data
  point.** A genuine transcript-format change would still leave the run's
  known-good control readable. Zero measurements from a clean run means the
  parser rejected something it should have classified — stop and read one
  transcript before trusting the abort.
- The remaining known limit: the anchor still assumes `"type"` is serialised
  before `"name"` within the object. That held in every transcript this
  session read; a JSON-parser rewrite is the upgrade path if it ever does not.

Related: [record a formal E2E gap when no project verification surface exists](../process/issue-lane-routing-e2e-gap.md) — the same eval machinery, one session earlier.
