---
title: Layered config (CLAUDE.md template + .claude/project.md project + CLAUDE.local.md personal)
date: 2026-09-01
problem_type: architecture-decision
module: CLAUDE.md, .agents/skills/sync/SKILL.md
tags: [configuration, sync, ownership, project-overrides]
applies_when: Adding instructions whose ownership is shared-template, project-specific, or personal
date_source: git-log
migrated_from: tasks/memory.md
---

## Layered config (CLAUDE.md template + .claude/project.md project + CLAUDE.local.md personal)

`CLAUDE.md` holds sync-managed shared rules and imports `.claude/project.md` plus
`CLAUDE.local.md` (`CLAUDE.md:5-11`). Project and personal layers remain outside
the overwrite boundary; `/sync` documents the same ownership split
(`.agents/skills/sync/SKILL.md:25-42`). Put each instruction in the layer whose
owner is allowed to change it.
