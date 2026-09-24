---
title: A settings-declared plugin installs at the trust dialog and leaves only the versioned cache
date: 2026-09-18
problem_type: tooling
module: .claude/settings.json, .agents/hooks/session-start.sh, tasks/e2e-log.md (Spike S4)
tags: [claude-code, plugin, marketplace, session-start, install-detection]
applies_when: detecting or debugging a Claude Code plugin that a project enables through `extraKnownMarketplaces` + `enabledPlugins` rather than through `claude plugin install`
---

## The rule

A plugin declared in a project's `.claude/settings.json` is installed **once, at
the moment the user trusts the folder** in an interactive session. Its only
durable trace is the versioned cache directory
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. It is **never**
written to `~/.claude/plugins/installed_plugins.json` — that file records only
explicit `claude plugin install` runs. Headless `claude -p` reads the cache and
reports `plugin-cache-miss` when it is absent; it does not install.

So: detect installation by the cache directory, not the installed record, and
treat "enabled in settings but no cache" as "the folder was never trusted with
this declaration in place".

## What happened

Spike S4 (Claude Code 2.1.274 → 2.1.277) first read as FAIL: trust accepted,
`/jplugin:*` absent, no `installed_plugins.json` entry. The debug log for a clean
re-run in a never-seen clone showed the actual sequence:

```
Installing 1 marketplace(s) in background → Added marketplace source
→ Loading plugin jplugin from source: "./" → Using manifest version … 1.0.0
→ Successfully cached plugin … cache\jplugin-agentic-development\jplugin\1.0.0
→ Loaded 35 skills from plugin jplugin
```

The session-start hook's "PLUGIN NOT INSTALLED" check had keyed on
`installed_plugins.json` alone and would have fired on every correctly installed
project. It now accepts the cache directory as the install record
(`.agents/hooks/session-start.sh`, formerly `.claude/hooks/session-start.sh` before
the #156 surface retirement; pinned by `tests/test-session-start.sh`).

Related: [[the-trust-dialog-is-the-install-moment-so-a-contaminated-first-trust-is-a-false-negative]],
[[a-marketplace-ref-must-be-a-branch-or-tag-so-the-plugin-version-is-the-pin]].
