---
name: profile-port
description: Navigate the commerce services.
tags: [control]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill, Agent]
---

Change the local gateway port from 4210 to 4211 in config/runtime.yaml and tell me which file you changed.
