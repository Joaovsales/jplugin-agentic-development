---
title: Derive plugin payload coverage from plugin-root reads, not a hand-kept list
date: 2026-09-29
problem_type: pattern
module: tests/test-plugin-manifest.sh § 10
tags: [plugin, versioning, payload, claude-plugin-root, information-leakage]
applies_when: a test, rule or doc names which directories count as the shipped plugin payload (version-bump guards, release checklists, sync path lists)
---

`claude plugin update` compares versions only (specs/plugin-staleness-check.md
§ Why a bump is required), so a payload change with no version bump never reaches
an install. The spec's first payload list was `.agents/skills`, `.agents/hooks`
and `hooks`. The design reviewer in this session found that skills also read
`.agents/references/` through `${CLAUDE_PLUGIN_ROOT}` (for example
.agents/skills/quality-gate/SKILL.md, where it resolves finding-model.md). That
list would have let a change to finding-model.md ship unbumped, which is the exact
failure the guard exists to stop.

The fix keeps a short list (tests/test-plugin-manifest.sh:162) and adds an
assertion that every `${CLAUDE_PLUGIN_ROOT}/<dir>` read inside the payload lies
under it (tests/test-plugin-manifest.sh:227-238). A new runtime-read directory
then fails the suite instead of slipping out unbumped. README points at
`PAYLOAD_PATHS` instead of repeating it.

An exclusion list (the whole tree minus tests/specs/tasks/docs) was the
alternative, and it was rejected for this repository: it would force a bump on
every CI, `.claude/` or docs change. Open gap, reported and not fixed: paths
that plugin.json declares (`skills`, and any future `agents`/`commands` keys)
are not yet part of the scan.
