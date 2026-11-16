---
name: invoice-rounding
description: Navigate the commerce services.
tags: [localization]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill, Agent]
---

Checkout for two units at 1099 cents returns 2197 cents rather than 2198. Follow the checkout path and identify the function responsible, giving its file and name. Do not change files.
