---
name: terms-failure
description: Navigate the commerce services.
tags: [localization]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill, Agent]
---

The worker fails on the basic plan; its traceback is in logs/worker.log. Follow the stack to the root cause and name the responsible file and function. Do not change files.
