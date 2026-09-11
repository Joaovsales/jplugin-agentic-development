---
title: Admit a cross-harness hook by input shape, not tool name
date: 2026-09-11
problem_type: pattern
module: .claude/hooks/bulk-read-gate.py, pi/extensions/bulk-read-gate.ts
tags: [hooks, codex, pi, pre-tool-use, cross-harness, shell-parsing]
applies_when: writing a PreToolUse / tool_call hook that one script must serve on more than one harness, or gating shell commands a model composes
---

## The pattern

A hook that branches on `tool_name` breaks the moment a second harness names its
tools differently. Claude Code sends `Read`, `Bash`, `PowerShell`; Codex sends a
different shell tool name and registers hooks with **no matcher**, so the same
script sees every tool call. The bulk-read gate therefore admits by the shape of
`tool_input` instead:

- a `file_path` key → the read-tool rule (`offset`/`limit` arithmetic)
- a `command` key, string **or** argv list → the shell rule

`decide()` in `.claude/hooks/bulk-read-gate.py` dispatches on those keys and
ignores `tool_name` entirely; `tests/test-bulk-read-gate.sh` feeds a Codex-style
`shell` event as both a string and an argv list to pin it. Codex and Claude Code
run the byte-identical script (`tests/test-codex-install.sh` asserts the
installed copy matches).

## Shell parsing that survives Windows

`shlex` is the obvious tokenizer and the wrong one here: `posix=True` eats the
backslashes in Windows paths, `posix=False` keeps the quotes glued to the token.
The gate ships a ~30-line quote-aware tokenizer that treats backslashes as
literal and splits only on `| || && ; &`, then inspects the **final pipeline
stage** — `cat big | grep x` prints one line into the model's context, so only
the last command decides. The Pi mirror (`pi/extensions/bulk-read-gate.ts`)
implements the same tokenizer so both harnesses agree on every fixture.

## Documented limit

A relative path after `cd` (`cd src && cat big.txt`) is allowed ungated: the hook
runs with the repo root as cwd and cannot resolve it. `specs/bulk-read-gate.md`
§ Edge Cases records this; a fix would have to simulate `cd`, which is out of
proportion for a soft cost gate.

## Related

- [a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos](a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos.md) —
  the deployment half: this gate is registered project-level in
  `.claude/settings.json` and installed by `scripts/install-codex.sh`, so it
  reaches the harnesses that read those files, not user-level config.
