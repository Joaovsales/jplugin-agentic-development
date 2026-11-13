---
name: catalog-currency-field
description: Add a currency field to a product model and its catalog data.
tags: [large]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Agent, Skill]
---

Add a currency field to the Product dataclass in models.py, defaulting to "USD", and make every product in fixtures/catalog.json carry it. Don't push anything or open a PR.
