# Checkpoint — 2026-09-05T12:12:23Z

> Auto-written by PreCompact hook (trigger: auto). Re-read on resume.

## Git
- Branch: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe

```
M  .agents/skills/sync/SKILL.md
AM .agents/skills/sync/scripts/sync-retire.py
M  .claude/skills/sync/SKILL.md
A  .claude/skills/sync/scripts/sync-retire.py
A  specs/sync-deterministic-retirement.md
M  tasks/checkpoint.md
A  tasks/details/glob-matcher-redos.md
A  tasks/details/glob-matcher-shared-module.md
A  tasks/details/sync.bootstrap-skips-legacy-retirements.md
A  tasks/details/sync.candidate-emits-per-file-patterns.md
A  tasks/details/sync.emptied-root-blocks-retirement.md
A  tasks/details/sync.retire-blast-radius-cap.md
A  tasks/details/sync.retired-root-orphans.md
A  tasks/details/sync.retirement-lands-after-commit.md
A  tasks/details/sync.stale-root-blocks-retirement.md
A  tasks/details/sync.syncable-paths-single-source.md
M  tasks/history.md
A  tasks/route-decision.md
A  tasks/solutions/architecture/current-state-cannot-distinguish-removed-from-never-present.md
A  tasks/solutions/process/an-assertion-can-pass-because-a-different-guard-fired.md
A  tasks/solutions/process/scoping-a-guard-per-item-can-silently-weaken-it.md
A  tasks/solutions/security/running-git-in-an-untrusted-checkout-executes-its-config.md
A  tasks/solutions/tooling/mawk-has-no-interval-expressions.md
M  tasks/todo.md
A  tests/test-sync-retirement.sh
M  tests/test-syncable-paths.sh
```

## In-Progress & Pending Tasks (tasks/todo.md)
[ ] prelude: skip: not needed for this kind
[ ] /plan (auto-confirm: no; wait for approval)
[ ] /build (runs /quality-gate on completion)
[ ] route radius tripwire: finalize_route before verification or push
[ ] /verify (evidence: tests)
[ ] /wrap-up-session (wait at pre-push gate)

## Active Spec
- specs/sync-deterministic-retirement.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (`problem_type`, `module`, `tags`) for the
   areas this task touches — never bulk-load the store
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
