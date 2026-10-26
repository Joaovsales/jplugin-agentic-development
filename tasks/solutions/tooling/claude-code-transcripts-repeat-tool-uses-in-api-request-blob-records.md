---
title: Claude Code transcripts repeat a tool use in api-request-blob records and re-logged turns, so a parser absorbs a tool-use id once
date: 2026-10-22
problem_type: tooling
module: ~/.claude/projects session JSONL (Claude Code 2.1.x); .agents/skills/eval/scripts/read_transcript.py
tags: [transcripts, jsonl, claude-code, parser, double-counting, api-request-blob]
applies_when: reading Claude Code session transcripts to count or measure tool calls, results or reads
---

## What the root holds

Found on 2026-10-22 while re-measuring the read-shunt baseline after a change to
the share's denominator moved it by 6 MB (`tasks/eval-results/read-shunt/baseline-2026-10-21.md`
§ *Revision 2026-10-22 — repeated tool uses*). Over 1044 files, 5036 of 50885
`tool_use` blocks repeated an id already seen in the same file:

- **`api-request-blob` records** (3521). `{"type": "api-request-blob", "sessionId",
  "hash", "message": {"role": "assistant", "content": [...]}}` copies the request
  the client sent — the turn's thinking, text and every `tool_use` block — with no
  `uuid`, no `timestamp` and no `isSidechain`. A parser that collects tool uses
  from any record with a `message.content` list counts each call twice, and
  counts a repeated **sidechain** use as the parent's, because the blob carries
  no flag.
- **Re-logged assistant records** (1515). A resumed or forked session appends an
  earlier `assistant` record verbatim — same `uuid`, same `message.id`.

Both shapes repeat *uses*; a `tool_result` keyed by `tool_use_id` in a dict was
already deduplicated by construction, which is why a sum over result records
disagreed with a sum over uses and exposed the defect.

## The rule

Read only `assistant`, `user` and `system` records, and absorb a tool-use id once
per transcript (first record wins — the first is the live assistant turn). Pin it
with a fixture that carries both shapes (`tests/fixtures/transcripts/repeated-uses/`).
When a measurement over a real root is the deliverable, re-run it after every
parser change and diff per session against the previous run: a figure that moves
when the change should have been neutral is the cheapest detector of a counting
bug the fixtures never held. Here every count in the committed baseline was
inflated by about a sixth (reads 1259 → 1041, whole-file large 60 → 54, shell
reads 5865 → 5207) and the go rule's inputs did not move.
