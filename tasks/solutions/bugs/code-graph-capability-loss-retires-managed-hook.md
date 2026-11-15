---
title: Retire an optional managed hook when its capability disappears
date: 2026-11-15
problem_type: test-failure
module: scripts/render-codex.py, tests/test-codex-install.sh
tags: [code-graph, codex, hooks, capability-probe]
symptoms: A supported install followed by an unsupported probe retained the earlier graph callback
root_cause: Conditional registration added the callback but did not retire it when support disappeared
resolution: Remove only the installed canonical Python callback on unsupported reruns
---

Conditional registration must handle both transitions. A successful probe can
add the optional callback; a later unsupported probe must remove the managed
callback while preserving personal hooks.

The renderer matches the exact installed script path and Python invocation,
not a filename substring (`scripts/render-codex.py:235`). The regression also
preserves a personal command that merely echoes the canonical path
(`tests/test-codex-install.sh:459`). Its central run failed before the repair
and passed afterward, with 59 targeted assertions green.

This concerns the unmerged treatment's installer behavior. It is not evidence
of a code-graph adoption verdict or a change to the user's global configuration.
