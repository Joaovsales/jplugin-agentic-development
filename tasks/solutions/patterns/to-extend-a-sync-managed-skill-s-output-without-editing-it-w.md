---
title: Wrap sync-managed output instead of patching its producer
date: 2026-07-08
problem_type: pattern
module: .agents/skills/visual-plan, .agents/skills/visual-recap
tags: [sync, wrapper, post-processor, ownership]
applies_when: A project needs to extend generated output while the producing skill remains template-owned
migrated_from: tasks/memory.md
---

## Wrap sync-managed output instead of patching its producer

**Pattern**: To extend a `/sync`-managed skill's output without editing it, wrap it — a new skill owns a post-processor that operates on the managed skill's OUTPUT. Keeps the managed file untouched so `/sync` never clobbers the work.

The visual-plan/visual-recap pair follows this ownership: visual-plan calls the
shared post-processor owned by visual-recap rather than duplicating or editing the
presentation generator (`.agents/skills/visual-plan/SKILL.md:79-112`).

_Extracted from session history entry "Visual plan/recap skills" (2026-07-08) in `tasks/history.md`._
