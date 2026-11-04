---
name: orders-extract-tax
description: Extract tax arithmetic from an order module into its own function.
tags: [large]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Agent, Skill]
---

In orders.py, pull the tax calculation out of compute_totals into its own function tax_for(subtotal, region), and make sure every caller keeps working. Don't push anything or open a PR.
