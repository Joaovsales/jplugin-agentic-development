---
title: Classify a null-result Read from its numbered text and count the block the parent received
date: 2026-10-21
problem_type: pattern
module: .agents/skills/eval/scripts/read_transcript.py § classify_read
tags: [transcript-format, jsonl, read-tool, toolUseResult, eval, parser]
applies_when: parsing Claude Code session JSONL to measure what the Read tool delivered into a context — the read-shunt baseline, or any grader that counts bytes or lines per read
---

## The shape the real root carries

The structured `toolUseResult` (`{"type":"text","file":{filePath,content,numLines,
startLine,totalLines}}`) is the minority shape. Over the 296-session root this
machine held on 2026-10-21, **2037 Read results had `toolUseResult: null`**. Of
those, 1947 carried the file as `cat -n` numbered lines inside the `tool_result`
block — some prefixed by one or more `<system-reminder>…</system-reminder>`
blocks — and 90 were notes with no file text at all: "Wasted call — file
unchanged" (45), the empty-file reminder (37), an empty image block (4), "PDF
file read:" (3), an offset past the end of the file (1). A Read the harness
could not parse carries `input: {"__unparsedToolInput": {raw, len}}`, no
`file_path`, and an error result.

## The rule

1. **Classify from the numbered text when the metadata is null.** Strip the
   leading reminders, count `^\s*(\d+)\t` lines, and take the first and last
   numbers as the range (`read_transcript.py:194-230`). Treat the three note
   families as `excluded`, not as drift (`:198-206`, `:308`): nothing of the file
   entered the context. Only text that is neither numbered nor a known note is
   `TranscriptDrift`.
2. **Check for an error or unparsed input before the `file_path` check**
   (`:290-296`), or the unparsed Read reports "no file_path" as drift instead of
   being excluded.
3. **A Read's bytes are the `tool_result` block the parent received**, not
   `file.content` (`:139`, `:311`, `:324`): the numerator and the denominator of
   the share then divide like for like.

## Why it matters

A parser pinned on the structured shape dies on the first real session with
"format changed", and one that drops null results silently undercounts by two
thirds. The fixture `tests/fixtures/transcripts/root/proj-b/s3.jsonl` carries one
Read of every shape above.

Related: [eval-grader-anchor-matched-the-inline-tool-schema](../bugs/eval-grader-anchor-matched-the-inline-tool-schema.md)
is the same lesson for the `Skill` block — anchor on the record's type
discriminator and the input shape, not on one key.
