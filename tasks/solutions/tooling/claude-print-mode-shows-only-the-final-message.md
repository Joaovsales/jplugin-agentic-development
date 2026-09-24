---
title: claude -p prints only the final message, so a line printed mid-session needs stream-json
date: 2026-09-24
problem_type: tooling
module: .agents/skills/wrap-up-session/scripts/routine_run.py — launching a harness and reading what the agent printed
tags: [claude-p, stream-json, routines, harness, envelope]
applies_when: a launcher, probe or scheduler judges a `claude -p` run by lines the agent prints before its last turn (a start marker, progress, a heartbeat)
---

## The trap

`claude -p <prompt>` with the default `--output-format text` writes only the
final assistant message to stdout. A line the agent prints at the top of the
session, such as `ROUTINE-ENVELOPE start {...}`, never reaches the caller.
A launcher that scans stdout would then read every Claude run as "never started"
and retry it after its claim step had already run.

`specs/routine-run-envelope.md` first specified `claude -p <prompt>
--strict-mcp-config`. The launcher builds
`--output-format stream-json --verbose` in addition (stream-json requires
`--verbose` with `-p`), and reads each JSONL event:

- `assistant` events: their `text` blocks are split into lines, and those lines count.
- `user` events carrying `tool_result`: dropped, so a `cat` of the prompt file is never read as the agent speaking.
- `system` and `result` events: dropped (`result` repeats the last message).
- a line that is not JSON: kept as-is, which is how the fake harness and Codex output pass through.

See `_event_lines` in `routine_run.py` and the
`test_claude_stream_json_counts_only_assistant_text` case in
`tests/test-routine-run.sh`.

## Codex differs

`codex exec` prints the final message on stdout and the session's progress on
stderr, so scanning both streams sees mid-session lines without a flag. Its
per-server `-c mcp_servers.<name>.enabled=false` is still unverified on this
build host (the spec records it as an assumed Decision).
