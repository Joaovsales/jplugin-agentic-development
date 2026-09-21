---
title: Enforce canonical and compatibility skill parity
date: 2026-09-21
problem_type: pattern
module: tests/test-skill-parity.sh, .agents/skills, .claude/skills
tags: [skill-parity, canonical-tree, compatibility-mirror, tests]
applies_when: Adding or editing a harness-neutral skill or any file owned by that skill
migrated_from: tasks/memory.md
---

> **Correction 2026-09-21:** #156 retired the `.claude/skills/` compatibility copy and
> `tests/test-skill-parity.sh`; `.agents/skills/` is now the only skill tree, shipped to
> Claude Code as the `jplugin` plugin (`.claude-plugin/`). The parity mechanics below are historical record; the surviving guards are `tests/test-skill-frontmatter.sh`, `tests/test-skill-references.sh` and `tests/test-plugin-manifest.sh`, which now read one tree.

## Enforce canonical and compatibility skill parity

**Pattern**: The bash test suite enforces `.agents/` ↔ `.claude/` byte-identical skill parity (`test-skill-parity.sh`) + doc-convention token greps (`test-doc-conventions.sh`). Any new skill must be authored in BOTH trees identically and wired into both tests.

The parity test declares `.agents/skills/` canonical and requires every canonical
file to exist byte-identically in `.claude/skills/`, except its explicit allowlist
(`tests/test-skill-parity.sh:1-36`).

_Extracted from session history entry "Visual plan/recap skills" (2026-07-08) in `tasks/history.md`._
