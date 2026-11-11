---
title: Admit a cross-harness hook by input shape, not tool name
date: 2026-10-21
problem_type: pattern
module: hooks (PreToolUse read and shell gates), specs/read-shunt.md
tags: [hooks, codex, pi, pre-tool-use, cross-harness, shell-parsing]
applies_when: writing a PreToolUse / tool_call hook that one script must serve on more than one harness, or gating shell commands a model composes
---

Ported from PR #128 (`origin/worktree-bulk-read-gate`, learned 2026-09-11) when
`specs/read-shunt-baseline.md` superseded that draft. The gate it describes
never merged; the pattern is what the read-shunt gate inherits if the baseline
justifies building one.

## The pattern

A hook that branches on `tool_name` breaks the moment a second harness names its
tools differently. Claude Code sends `Read`, `Bash`, `PowerShell`; Codex sends a
different shell tool name and registers hooks with **no matcher**, so the same
script sees every tool call. PR #128's bulk-read gate therefore admitted by the
shape of `tool_input` instead:

- a `file_path` key → the read-tool rule (`offset`/`limit` arithmetic)
- a `command` key, string **or** argv list → the shell rule

Its `decide()` dispatched on those keys and ignored `tool_name` entirely; its
test fed a Codex-style `shell` event as both a string and an argv list to pin
it, and Codex and Claude Code ran the byte-identical script.

## Shell parsing that survives Windows

`shlex` is the obvious tokenizer and the wrong one here: `posix=True` eats the
backslashes in Windows paths, `posix=False` keeps the quotes glued to the token.
The gate shipped a ~30-line quote-aware tokenizer that treats backslashes as
literal and splits only on `| || && ; &`, then inspected the **final pipeline
stage** — `cat big | grep x` prints one line into the model's context, so only
the last command decides. The Pi mirror implemented the same tokenizer so both
harnesses agreed on every fixture. `read-incidence.py`'s bare-read classifier
keeps that rule: a piped or redirected read is not a read into the parent.

## Documented limit

A relative path after `cd` (`cd src && cat big.txt`) is allowed ungated: the
hook runs with the repo root as cwd and cannot resolve it. A fix would have to
simulate `cd`, which is out of proportion for a soft cost gate.

## Related

- [a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos](a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos.md) —
  the deployment half: a gate registered project-level reaches the harnesses
  that read those files, not user-level config.
- `specs/read-shunt.md` § Tier 1 — the cap-and-annotate gate this pattern
  would serve, built only on the baseline's verdict.
