---
title: Keep a shared core with harness-specific adapters
date: 2026-09-01
problem_type: architecture-decision
module: CLAUDE.md, .agents, .claude
tags: [harness, shared-core, adapters, claude-code, pi]
applies_when: Adding workflow behavior that must work across Claude Code, Pi, Codex, or another supported harness
date_source: git-log
migrated_from: tasks/memory.md
---

## Keep a shared core with harness-specific adapters

The original Claude-Code-primary decision has broadened. Shared workflow rules live
in `CLAUDE.md`, which both Claude Code and Pi read, while project-specific layers
differ by harness (`CLAUDE.md:5-8`). Canonical skills and agents live under
`.agents/`; `.claude/` supplies Claude-specific compatibility copies and hooks.

Put portable behavior in the shared core. Use harness adapters only where the
runtime surface genuinely differs.
