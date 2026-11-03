---
title: Idle compaction fires while a background task runs, so persist what the turn collects
date: 2026-10-30
problem_type: tooling
module: .agents/skills/build/SKILL.md
tags: [claude-code, compaction, idle-compaction, prompt-cache, background-tasks, build]
applies_when: a skill ends its turn to wait on a run_in_background suite or background agent, or keeps state that exists only in the conversation
---

## The rule

Anything a skill collects from agent output and reads back later belongs on disk
at the moment it arrives. Claude Code's idle compaction can summarise the
conversation while the main turn waits on background work, and agent output
held only in context does not survive the summary.

## What this session observed

Claude Code's idle compaction (`idleCompaction`, default `true`, v2.1.290+)
summarises a long conversation shortly before its one-hour prompt cache
expires. Read from the installed 2.1.308 binary, not the docs, so treat it as
version-specific:

- The timer is re-armed on every **main-conversation** request and fires at
  0.9 × the cache lifetime — 54 minutes on the one-hour TTL. Subagent and
  background-task requests do not re-arm it.
- The host refuses only when another process holds the session, the transcript
  advanced, a **turn is in flight** (`busy`), the user interacted in the last
  60 s (`present`), the context is under the threshold
  (`CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`, default 200 000), or the cache has
  lapsed.
- It does **not** check background tasks. The binary's away-summary feature
  does (`hasBackgroundAgents()`); idle compaction has no such guard.

So a foreground `Agent` call is safe (the turn is in flight), but a turn that
ends to wait for a `run_in_background` notification is exposed. `/build` and
`/wrap-up-session` both do that for the full suite, which takes 30–78 min on
this Windows host, and the project's `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`
lets a conversation pass the 200 000-token threshold before auto-compact runs.

The official hooks reference lists idle compaction under the `PreCompact` and
`PostCompact` `auto` matcher, so `.agents/hooks/pre-compact.sh` already flushes
`tasks/checkpoint.md` before it. What the checkpoint does not hold is anything
gathered only in context — `/build` Phase 4.5 grepped "every agent output
captured this build" for `[AMBIGUITY]` lines. That is fixed: each returning
dispatch's `[AMBIGUITY]` lines are copied under the slice heading in
`tasks/todo.md` (`.agents/skills/build/SKILL.md` § *Ambiguities go to disk as
they arrive*).

## Consequence of ignoring it

A batch that was supposed to reach the user before the quality gate is
silently empty after a compaction — no error, just nothing found. Turning
`idleCompaction` off does not help: auto-compaction is equally lossy, and the
request after a long background run would then hit an expired cache and
reprocess the whole history uncached.
