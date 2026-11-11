---
name: changelog-release-notes
description: Turn a changelog into themed release notes.
tags: [large]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Agent, Skill]
---

Turn the 3.x entries in CHANGELOG.md into release notes grouped by theme, and save them as RELEASE_NOTES.md. Don't push anything or open a PR.
