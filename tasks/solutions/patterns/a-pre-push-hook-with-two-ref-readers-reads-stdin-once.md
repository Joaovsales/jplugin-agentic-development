---
title: A pre-push hook with two ref readers reads stdin once, and a gate that must outrank the kill switch reads it first
date: 2026-11-18
problem_type: pattern
module: .agents/git-hooks/pre-push
tags: [git-hooks, pre-push, stdin, kill-switch, unattended-scan]
applies_when: adding a second per-ref gate to .agents/git-hooks/pre-push, or a gate that SKIP_PREPUSH must not silence
---

## The rule

git writes the pushed refs to the hook's stdin once. The first `while read` loop
drains it, so a second gate that also loops over stdin silently sees no refs and
passes everything. Read stdin once at the top (`PUSH_REFS=$(cat)`) and feed every
loop from a here-document (`done <<EOF … $PUSH_REFS … EOF`).

A gate an unattended agent must not be able to switch off (the unattended scan,
#444) runs **before** the `SKIP_PREPUSH` line: an agent can set an environment
variable, so only `git push --no-verify` — a human's override — skips it.

## Testing it

`unattended_scan.py --transcript auto` resolves the running Claude Code session
from `CLAUDE_CODE_SESSION_ID`. A test that drives the hook from inside a Claude
Code session must clear that variable (`env -u CLAUDE_CODE_SESSION_ID`), or the
scan reads the session running the suite, whose commands name the very rules it
tests (`tests/test-pre-push-gate.sh` § unattended-scan).
