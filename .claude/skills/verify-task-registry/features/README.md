# Task registry feature map

Scope: the three principal task-registry feature groups, driven through the real
local-provider CLI. Launch and Doctor are in the parent skill’s `SKILL.md`. Use a fresh
owned scratch repository per run; all mutations stay there. No auth is needed.

- [Record a task](record-task.md): preview, create, update, derive identity.
- [Read task detail](read-task.md): stable ID, local path, and missing record.
- [Choose routine work](routines.md): selectors, selection, workflow, claim.

Use `drive` from the skill to retain action, output, and exit status. Seed only via
`upsert`; confirm persistence through `show`. Artifact names must be unique within
a run. Record every entry point independently as PASS, FAIL, BLOCKED, or NOT RUN.
GitHub references (`#N`, issue URL), external publication, full agent routines,
and installation require separate live verification; the local recipes prove none
of them. Preserve evidence outside the disposable repository during cleanup.
