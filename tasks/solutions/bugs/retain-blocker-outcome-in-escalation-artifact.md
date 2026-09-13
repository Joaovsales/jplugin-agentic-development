---
title: Escalation artifact dropped a confirmed blocker outcome
date: 2026-09-12
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/escalation.py
tags: [task-registry, escalation, artifacts, structured-results]
symptoms: An execution-blocked run recorded its local blocker in stages and the parent comment, but the retained artifact encoded blocker_disposition as null.
root_cause: The coordinator passed blocker_result to parent-comment rendering, then discarded it when calling the shared artifact-finishing boundary.
resolution: Thread blocker_result through _finish and _write_artifact so both durable reports render from the same structured outcome.
---

**Status**: fixed — 2026-09-12
**Regression test**: `tests/test-task-escalation.sh` — `AC7: retained artifact carries the confirmed blocker outcome`

The isolated execution-blocked skill run supplied Level 1 evidence: its parent
comment encoded `"blocker_disposition": "local"`, while the artifact from the
same escalation encoded `null`. The blocker write and selection behavior were
correct, which ruled out provider persistence and result construction. The value
was lost at the coordinator boundary: `_apply_escalation` rendered the comment
with `blocker_result` but previously called `_finish` without it
(`.agents/skills/task-registry/scripts/registry/escalation.py:208-214`). The
artifact now receives the same object
through `_finish` and `_write_artifact`
(`.agents/skills/task-registry/scripts/registry/escalation.py:274-291`).
