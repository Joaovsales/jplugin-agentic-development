---
title: Task-tracking pointer to a missing file was indistinguishable from no pointer
date: 2026-09-06
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/config.py, .agents/skills/task-registry/scripts/task-registry.py, CLAUDE.md
tags: [task-registry, configuration, silent-failure, sync, pointer]
symptoms: A project whose CLAUDE.md declared `Task tracking instructions: docs/task-tracking.md` with no such file ran on defaults, and `doctor` printed byte-identical output to a project with no pointer at all
root_cause: find_config_path folded a pointer whose target was missing (or escaped the root) into the no-pointer path, and the template's CLAUDE.md emitted a live pointer to a file `/sync` can never ship
resolution: find_config_path raises ConfigPointerError naming the declaring file and path; doctor renders it on the configuration line and every other command refuses; CLAUDE.md documents the convention with the inert `<path>` placeholder instead of a live pointer
---

**Status**: fixed — 2026-09-06
**Regression test**: `tests/test-task-registry.sh` ("Pointer states" block, line 411; escape block, line 1473) and `tests/test-doc-conventions.sh:337`

Issue #82. Reproduced at Level 1 by running `doctor` against three throwaway
repos: pointer with missing target, no pointer, and an escaping pointer
(`../../etc/passwd`). All three printed the same three lines and exited 0.

Three candidates were ranked. The regex (`POINTER_RE`) was disconfirmed by
running it over `CLAUDE.md` — it matched. The `doctor` renderer was disconfirmed
by reading `Config`: it has no field for a declared path, so it had nothing to
render. That left the loader. `find_config_path` checked `isfile` on the
resolved pointer and, on failure, fell through to the default path and then to
`None` — the same return as "never configured". The sibling branch three lines
up swallowed the confinement error for an escaping pointer the same way, while
`references/configuration.md` already documented escapes as refused.

The fix keeps the two silent states silent and makes the third loud
(`.agents/skills/task-registry/scripts/registry/config.py:262`): a declared target that is missing raises
`ConfigPointerError` (line 292), and an escaping one wraps the
confinement error in the same type (line 287). The first pointer
found wins, broken or not — a dangling `.claude/project.md` pointer is not
rescued by a valid `CLAUDE.md` one. `load_config` gained `strict`, replacing
`validate_routines`: `doctor` loads non-strictly (line 362) and renders
the fault on its `configuration:` line (`.agents/skills/task-registry/scripts/task-registry.py:312`), exit 1;
every other command refuses with the same message.

The template side: `CLAUDE.md` shipped a bare, parseable pointer to
`docs/task-tracking.md`, and `docs/` is outside every syncable root, so every
consumer inherited a dangling pointer on `/sync`. The issue's suggested fix —
backtick-wrap the pointer — does not work: `POINTER_RE` stops at a backtick but
does not require one, so `` `Task tracking instructions: docs/x.md` `` still
matches. Only the `<path>` placeholder is inert, which is why `SKILL.md` never
self-triggered. `CLAUDE.md:428` now documents the convention that way
and tells projects to put a real pointer in `.claude/project.md` or `AGENTS.md`.
The doc-conventions test that used to pin the dangling pointer in place now
asserts the convention is documented and that any live pointer resolves to a
shipped file.

Documented behaviour change (issue AC7): an escaping pointer was previously
skipped silently and is now refused, matching what the configuration guide
already claimed. Noted in `references/configuration.md`, `SKILL.md`, and
`specs/task-registry.md`.

Two decisions made without the user: refuse rather than warn-and-run, because
the issue's own comment carries spec AC7 "refused loudly" and malformed
configuration already refuses with `doctor` exempt; and widen scope to the
escaping-pointer branch, because it is the same defect in the same function.

Related pattern: [A declared intent with a broken target is not an absent one](../patterns/a-declared-intent-with-a-broken-target-is-not-an-absent-one.md).
Related: [Validate in the loader, not in one optional command](../patterns/validate-in-the-loader-not-in-one-optional-command.md).
