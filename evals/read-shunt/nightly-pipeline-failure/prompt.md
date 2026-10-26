---
name: nightly-pipeline-failure
description: Explain a failed nightly pipeline from its log.
tags: [large]
runs: 1
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill]
---

Our nightly pipeline failed overnight and the log is ci-run-48213.log. What broke, and where in the code did it happen? I only need an explanation, no changes. Don't push anything or open a PR.
