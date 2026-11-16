---
name: receipt-module
description: Navigate the commerce services.
tags: [control]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write, Skill, Agent]
---

Add reporting/receipt.py with format_receipt(reference, minor) returning reference followed by a colon and the integer minor amount. Tell me the file and function you added.
