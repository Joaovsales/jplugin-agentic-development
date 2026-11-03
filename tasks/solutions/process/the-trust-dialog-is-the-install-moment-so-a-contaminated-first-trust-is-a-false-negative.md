---
title: The trust dialog is the install moment, so a contaminated first trust is a false negative
date: 2026-09-18
problem_type: process
module: tasks/e2e-log.md (Spike S4), .claude/settings.json
tags: [claude-code, plugin, spike, false-negative, verification]
applies_when: probing whether a fresh clone installs a settings-declared plugin, or re-running any check whose side effect happens exactly once per project
---

## The rule

Claude Code runs the settings-driven marketplace + plugin install exactly once
per project, when the folder is trusted. If the declaration is invalid at that
moment (S4: a Windows `C:/…` source url the CLI refuses; `file:///C:/…` works),
or the user's config already carries a stale marketplace or plugin cache from a
manual `claude plugin install`, the install silently does nothing — and never
runs again for that path, because trust is already recorded in `~/.claude.json`.

A negative result from a probe with those preconditions dirty proves nothing.
Before calling a spike FAIL:

1. Remove the marketplace (`claude plugin marketplace remove <name>`) and the
   cache dir under `~/.claude/plugins/cache/<name>`.
2. Fix the declaration in the committed tree first.
3. Clone to a **never-seen path** (a new `.claude/worktrees/s4-cloneN`), so the
   trust dialog fires again.
4. Run with `claude --debug` and read the install lines; `/reload-plugins` does
   not re-run the install.

## What happened

The first S4 verdict was recorded as FAIL and reopened a spec decision. The trust
had been accepted while the declaration held the invalid `C:/` url and a leftover
cache existed. A clean re-run in `s4-clone3` on 2.1.277 PASSED with the plugin
cached and 35 skills loaded (`tasks/e2e-log.md`, "Spike S4 — follow-up").
The user also ran `claude` in the main checkout on a branch without
`.claude-plugin/` and saw "No commands match /jplugin" — check the header's
cwd/branch before debugging the plugin.

Related: [[settings-declared-plugin-installs-at-trust-and-leaves-only-the-cache]].
