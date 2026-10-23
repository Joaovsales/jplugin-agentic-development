---
name: load-record-callers
description: List modules that still use a renamed function.
tags: [large]
runs: 1
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill]
---

I renamed fetch_record to load_record in svc/core.py. List every file under svc/ that still uses the old name. Just list them, don't change anything. Don't push anything or open a PR.
