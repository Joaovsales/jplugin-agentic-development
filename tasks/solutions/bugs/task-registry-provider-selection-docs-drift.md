---
title: Keep provider-selection documentation aligned with runtime precedence
date: 2026-09-04
problem_type: bug
module: CLAUDE.md, specs/wrap-up-gate-and-tdd-fold.md, task-registry documentation
tags: [task-registry, documentation, provider-selection, regression-test]
symptoms: Documentation claimed that absent task-tracking configuration always selects the offline local provider
root_cause: Documentation collapsed an absent explicit provider into the final local fallback and omitted GitHub auto-selection
resolution: Documented the complete precedence in every affected guide and template, replaced the hook rationale with its actual no-registry-invocation boundary, and added positive regression assertions
---

**Status**: fixed — 2026-09-04
**Regression test**: `tests/test-doc-conventions.sh`

Issue #95 exposed documentation semantic drift rather than a selector defect. The
runtime checks an explicit provider first, then a GitHub remote with authenticated
`gh`, and only then chooses local Markdown
(`.agents/skills/task-registry/scripts/registry/config.py:363-373`).

The corrected task-tracking overview, both shipped configuration templates, and
the dedicated configuration guide now keep configuration discovery separate from
provider selection (`CLAUDE.md:423-425`,
`.agents/skills/task-registry/templates/task-tracking.md:8-11`, and
`.agents/skills/task-registry/references/configuration.md:16-26`). The wrap-up
gate specification no longer infers provider selection from a missing
configuration file; it records the stronger boundary that the pre-push hook never
invokes `/task-registry` and therefore cannot reach any provider
(`specs/wrap-up-gate-and-tdd-fold.md:73-75`). Regression assertions positively pin
the corrected contract (`tests/test-doc-conventions.sh:331-377`).

Related pattern: [Consume structured records before rendering human summaries](../patterns/consume-structured-records-before-rendering-human-summaries.md).
