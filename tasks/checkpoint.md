# Checkpoint — 2026-09-17T17:31:59Z

> Auto-written by PreCompact hook (trigger: ). Re-read on resume.

## Git
- Branch: worktree-plugin-manifest

```
 M .agents/skills/sync/SKILL.md
 M .agents/skills/sync/scripts/sync-retire.py
 M .claude/hooks/session-start.sh
 M .claude/skills/sync/SKILL.md
 M .claude/skills/sync/scripts/sync-retire.py
 M install.sh
 M tasks/checkpoint.md
 M tasks/e2e-log.md
 M tasks/todo.md
 M tests/test-sync-retirement.sh
?? specs/claude-plugin-manifest.md
?? specs/claude-plugin-manifest.plan.html
```

## In-Progress & Pending Tasks (tasks/todo.md)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/
  [ ] Spike S2: `/eval` triggerability for `/quality-gate`, `/verify`, `/task-registry` with the `~/.claude/skills/` template copies removed and the project `.claude/skills/` moved aside, plugin loaded via `--plugin-dir` -> PASS recorded in tasks/e2e-log.md; a FAIL halts the plan here and reopens § Decisions (slice criterion 4, AC 2)
  [ ] Spike S4: scratch clone whose `.claude/settings.json` declares the github marketplace at a `ref` and enables the plugin -> record whether the install is offered/auto-registered and whether that ref is what loads; a FAIL rewrites the pinning-model row of § Decisions before slice 5 (slice criterion 4, AC 3)
  [ ] Gate: tasks/e2e-log.md holds S2 PASS; otherwise stop here and reopen § Decisions (AC 2)
  [ ] TDD: the 23 tests that walk `.claude/skills/` rewritten to loop over `.agents/skills/` only; `tests/test-skill-parity.sh` deleted; `git grep -l test-skill-parity` empty -> `git rm -r .claude/skills` (slice criteria 1, 3, AC 1, AC 10)
  [ ] TDD: tests/test-plugin-manifest.sh — `git grep -l 'jplugin:' -- .agents/skills .claude/agents AGENTS.md PI_SETUP.md` empty; CLAUDE.md contains the namespace sentence exactly once -> CLAUDE.md Key Directories loses the `.claude/skills/` row and § Skills gains the sentence from spec § CLAUDE.md — namespace sentence (slice criterion 2, AC 9)
  [ ] TDD: tests/test-skill-references.sh premise reworded (the template ships nothing under `.claude/skills/`; executed paths there still forbidden) -> README.md § Skills row, `.agents/agents/README.md:11`, tasks/concepts.md, tidy inventory rows, task-registry `SKILL_ROOTS` comment and `templates/task-tracking.md:119`, project-local-skill wording in `create-verification-skill`, `maintain-verification-skill`, `verify` (spec § Project-local skills)
  [ ] Verification: `bash tests/run.sh` green (slice criterion 4)

## Active Spec
- specs/claude-plugin-manifest.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
