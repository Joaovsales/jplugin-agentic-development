---
title: Isolate explicit Codex home overrides in installer fixtures
date: 2026-11-15
problem_type: test-failure
module: install.sh, tests/test-install-sh.sh
tags: [code-graph, installer, fixture-isolation, codex-home]
symptoms: Eight existing installer cleanup assertions fail under a coding-agent environment
root_cause: Inherited CODEX_HOME overrides the fixture's temporary HOME
resolution: Unset CODEX_HOME before creating isolated installer fixtures
---

The installer intentionally honors `CODEX_HOME` before `$HOME/.codex`
(`install.sh:213`). Overriding only `HOME` therefore leaves a fixture reading
the agent's real Codex configuration. The cleanup tests then miss the managed
block planted under their temporary home.

The fixture suite now clears the inherited override (`tests/test-install-sh.sh:10`)
and its graphify cases supply an explicit temporary Codex home. Keep the real
installer's override behavior; isolate the test environment instead.

This session's baseline had 8128 passing assertions and eight failures, all in
those cleanup assertions. The affected run after isolation and the requested
graphify changes passed 6522 assertions across 67 files. No real graphify package
was installed or upgraded. This is a fixture-isolation learning, not evidence
for a code-graph adoption verdict.
