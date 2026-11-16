---
title: Count executed graph commands rather than availability probes
date: 2026-11-15
problem_type: test-failure
module: .agents/skills/eval/scripts/grade-code-graph.py
tags: [code-graph, transcripts, adoption, shell]
symptoms: Availability probes counted as adoption while multiline navigation calls were missed
root_cause: Shell token classification discarded command boundaries and treated command -v as execution
resolution: Preserve unquoted newline boundaries and distinguish capability checks from invocations
---

The adoption threshold measures graph navigation, so `command -v graphify`
cannot count as use. Conversely, a Bash command that changes directory and then
runs `timeout 20 graphify query` on another line must count.

`graph_command` preserves unquoted newlines as punctuation and keeps quoted
multiline prose as one argument. It also distinguishes `command -v/-V` from
execution (`.agents/skills/eval/scripts/grade-code-graph.py:49`). Tests exercise
those distinctions through the classifier and the real grader CLI
(`tests/test-grade-code-graph.sh:1`). No shell command is executed to classify it.

The shared transcript reader remains responsible for record/usage deduplication;
shell classification belongs in the metric's grader. This prevents a capability
probe from turning an unused treatment into an apparent adoption success.
