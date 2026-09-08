---
title: Task registry publish lost legacy row detail
date: 2026-09-06
problem_type: bug
module: .agents/skills/task-registry/scripts/registry
tags: [task-registry, legacy-rows, parsing, github-publish, data-loss]
symptoms: Publishing a migrated multi-line prose row produced a truncated title and an issue body with no human-readable detail
root_cause: TaskIndex parsed each physical checkbox line independently, so indented continuation text never entered Task and arrow-delimited implementation prose remained in the title
resolution: Parsed logical row spans, derived arrow and quoted-TDD titles from the header, preserved continuation detail as summary, rejected malformed or oversized rows before any provider call, and made rewrites consume the owned span
---

**Status**: fixed — 2026-09-07
**Regression test**: `tests/test-task-registry.sh` — legacy multi-line parsing, logical-span rewrite, malformed-row refusal, size bound, and provider-boundary assertions

Issue #90 was reproduced with a migrated-shaped row carrying a stable ID. The
controlled test failed only the new title and body assertions while the other 289
task-registry assertions passed, establishing Level 1 evidence for the parser as
the lossy stage.

The parser now records the inclusive physical span of each logical row and joins
only its indented continuation lines into the summary
(`.agents/skills/task-registry/scripts/registry/index.py:80-86`,
`.agents/skills/task-registry/scripts/registry/index.py:104-118`, and
`.agents/skills/task-registry/scripts/registry/index.py:271-299`). Canonical
rewrites replace that span, while migration uses the explicit physical-line edit
operation so minting an ID does not delete continuation prose
(`.agents/skills/task-registry/scripts/registry/index.py:200-221` and
`scripts/migrate-task-registry.py`, which was `.agents/skills/task-registry/scripts/registry/migrate.py:205-220` until Cut 1 retired it).

GitHub rendering was disconfirmed: it emits a non-empty body whenever summary or
criteria exist. Migration was also disconfirmed as the lossy stage: it preserved
the continuation and only made the publish path reachable. Malformed and
oversized logical rows now become explicit parser problems, and one bad row
refuses the whole publish batch before provider discovery or writes
(`.agents/skills/task-registry/scripts/registry/index.py:141-170` and
`.agents/skills/task-registry/scripts/registry/reconcile.py:408-415`).

Related pattern: [Logical text records must own their rewrite span](../patterns/logical-text-records-must-own-their-rewrite-span.md).
