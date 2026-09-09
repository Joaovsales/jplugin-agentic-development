---
title: Local-pending upserts shadow published issue references
date: 2026-09-09
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/upsert.py, .agents/skills/task-registry/scripts/registry/providers/local.py
tags: [task-registry, github, local-provider, idempotency, external-reference]
symptoms: An approval-gated upsert rewrote a GitHub-linked index row to a local detail-file link, and a later approved publication could create a duplicate issue
root_cause: LocalMarkdownProvider replaced the incoming published ExternalRef with its local detail-file reference, while upsert only consulted the index reference on the local fallback path and never used it to fetch an existing external task
resolution: Preserve an incoming external reference through local writes, consult a matching index reference before provider metadata listing, and keep the index linked to the original issue through the fallback and publication cycle
---

**Status**: fixed — 2026-09-09
**Regression test**: `tests/test-task-registry.sh` — approval-gated fallback, preserved GitHub link, reference lookup, and update-without-create

The controlled reproduction showed the failure at the provider boundary. `upsert`
loaded the prior GitHub reference with `_published_ref`
(`.agents/skills/task-registry/scripts/registry/upsert.py:150-163`), but local
create and update returned `ExternalRef("local", ...)`
(`.agents/skills/task-registry/scripts/registry/providers/local.py:81-94`).
The index therefore lost the only durable address of the published issue.

The fix keeps an incoming external address in the task returned by local writes.
For an approved external run, `upsert` now resolves the preserved index reference
with `get_task` before falling back to provider metadata matching. This handles an
external task whose body does not carry the stable registry ID and refuses to
interpret an unanswered reference as absence.

The regression uses a fake GitHub provider whose metadata listing is empty. The
approved second run can update the original `github:42` task only when it uses the
reference preserved by the first local-pending run, proving that no duplicate is
created.
