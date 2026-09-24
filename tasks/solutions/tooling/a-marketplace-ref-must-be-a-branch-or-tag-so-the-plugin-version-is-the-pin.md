---
title: A marketplace ref must be a branch or tag, so the plugin version is the pin
date: 2026-09-18
problem_type: tooling
module: .agents/skills/sync/SKILL.md (Step 5), .claude-plugin/plugin.json, README.md § Keeping It Up to Date
tags: [claude-code, plugin, marketplace, pinning, sync]
applies_when: deciding how a downstream project pins the version of a plugin it receives through a github-source marketplace
---

## The rule

`extraKnownMarketplaces.<name>.source.ref` is passed to `git clone --branch`,
so it accepts a branch or a tag and **fails on a commit sha**. A `/sync` that
wrote the checked-out sha as `ref` would leave every downstream project with a
marketplace that never registers.

Pin by the plugin's manifest `version` instead (Addy Osmani's `agent-skills`
model): github source, no `ref`, and `version` in `.claude-plugin/plugin.json`
bumped in the same commit as any skill change — Claude Code caches by version and
users receive an update only when it changes. The marketplace source floats on
the default branch; the version is what a project actually receives.

## What happened

Slice 5 of `specs/claude-plugin-manifest.md` had `/sync` Step 5 write
`ref = <sha>`. Spike S4 showed the clone failing on it. Slice 5b removed the
`ref` write, named `version` as the pin in the sync runbook and README, and
`tests/test-plugin-manifest.sh` §7 now fails on any `["ref"]` write in the
sync skill.

Related: [[settings-declared-plugin-installs-at-trust-and-leaves-only-the-cache]].
