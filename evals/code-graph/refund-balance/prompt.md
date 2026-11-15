---
name: refund-balance
description: Navigate the commerce services.
tags: [localization]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill, Agent]
---

Refunding 300 minor units from a balance of 1200 produces 1500. Trace the refund entry point and identify the arithmetic function responsible, giving its file and name. Do not change files.
