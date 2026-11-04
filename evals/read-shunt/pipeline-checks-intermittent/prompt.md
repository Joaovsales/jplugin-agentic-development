---
name: pipeline-checks-intermittent
description: Explain an intermittent CI failure in a check function.
tags: [large]
runs: 1
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill]
---

check_batch_order in verify_pipeline.py passes on my machine but fails about one run in five on CI. Can you explain why, from the file? Don't change anything. Don't push anything or open a PR.
