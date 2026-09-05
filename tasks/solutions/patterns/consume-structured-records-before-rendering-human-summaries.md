---
title: Consume structured records before rendering human summaries
date: 2026-09-05
problem_type: pattern
module: .agents/skills/task-registry
tags: [task-registry, structured-data, progressive-disclosure, metadata]
applies_when: One workflow needs complete machine-readable state owned by another workflow whose CLI intentionally prints bounded prose
---

Human summaries are lossy by design. A caller that parses or reconstructs a record
from progressive-disclosure output can silently omit state that policy depends on.

Expose a provider-neutral library seam instead. `Registry.resolve_task` resolves a
reference, preserves provider metadata, annotates incomplete reads and unknown
dependencies, and returns the normalized task directly
(`.agents/skills/task-registry/scripts/registry/reconcile.py:161-165`).

Callers reach for the seam, never the rendered output. Routine selection reads
labels and configuration through `select_routine`
(`.agents/skills/task-registry/scripts/registry/routines.py`) rather than parsing
a report, and the `selectors` command checks the tracker's vocabulary through the
`known_labels()` provider method rather than scraping `doctor`. The original
example was the issue router, which has since been deleted; the seam it consumed
is unchanged, which is the point — the pattern survives its first consumer.

Use the CLI summary for humans and semantic inspection; use the structured operation
for policy. This keeps provider selection and failure degradation inside the module
that owns them.
