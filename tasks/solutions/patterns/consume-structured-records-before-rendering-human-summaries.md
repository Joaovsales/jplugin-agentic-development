---
title: Consume structured records before rendering human summaries
date: 2026-09-01
problem_type: pattern
module: .agents/skills/task-registry, .agents/skills/route
tags: [task-registry, structured-data, progressive-disclosure, metadata]
applies_when: One workflow needs complete machine-readable state owned by another workflow whose CLI intentionally prints bounded prose
---

Human summaries are lossy by design. A caller that parses or reconstructs a record
from progressive-disclosure output can silently omit state that policy depends on.

Expose a provider-neutral library seam instead. `Registry.resolve_task` resolves a
reference, preserves provider metadata, annotates incomplete reads and unknown
dependencies, and returns the normalized task directly
(`.agents/skills/task-registry/scripts/registry/reconcile.py:161-176`). The public
router accepts only a task reference and delegates resolution to that seam
(`.agents/skills/route/scripts/route_issue.py:356-361`).

Use the CLI summary for humans and semantic inspection; use the structured operation
for policy. This keeps provider selection and failure degradation inside the module
that owns them.
