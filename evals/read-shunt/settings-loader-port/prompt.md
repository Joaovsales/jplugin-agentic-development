---
name: settings-loader-port
description: Port a JavaScript settings loader to Python.
tags: [large]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Agent, Skill]
---

Port reference/settings_loader.js to Python as settings_loader.py in the project root, keeping the same precedence rules. Don't push anything or open a PR.
