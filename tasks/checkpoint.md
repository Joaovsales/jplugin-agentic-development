# Checkpoint — 2026-09-18T20:32:35Z

> Auto-written by PreCompact hook (trigger: auto). Re-read on resume.

## Git
- Branch: worktree-plugin-manifest

```
 M .agents/agents/README.md
 M .agents/skills/create-verification-skill/SKILL.md
 M .agents/skills/maintain-verification-skill/SKILL.md
 M .agents/skills/sync/SKILL.md
 M .agents/skills/task-registry/scripts/registry/config.py
 M .agents/skills/task-registry/scripts/task-registry.py
 M .agents/skills/task-registry/templates/task-tracking.md
 M .agents/skills/tidy/SKILL.md
 M .agents/skills/verify-evidence/SKILL.md
D  .claude/skills/README.md
D  .claude/skills/auto-push/SKILL.md
D  .claude/skills/brainstorm/SKILL.md
D  .claude/skills/build/SKILL.md
D  .claude/skills/build/references/subagent-resilience.md
D  .claude/skills/build/references/testing-anti-patterns.md
D  .claude/skills/build/scripts/bootstrap-worktree.sh
D  .claude/skills/checkpoint/SKILL.md
D  .claude/skills/create-verification-skill/LICENSE.pstack
D  .claude/skills/create-verification-skill/SKILL.md
D  .claude/skills/create-verification-skill/references/feature-map-example/README.md
D  .claude/skills/create-verification-skill/references/feature-map-example/archive-note.md
D  .claude/skills/create-verification-skill/references/feature-map-example/create-note.md
D  .claude/skills/create-verification-skill/references/feature-map-example/search.md
D  .claude/skills/debug/SKILL.md
D  .claude/skills/debug/condition-based-waiting.md
D  .claude/skills/debug/defense-in-depth.md
D  .claude/skills/debug/evidence-hierarchy.md
D  .claude/skills/debug/find-polluter.sh
D  .claude/skills/debug/root-cause-tracing.md
D  .claude/skills/debug/templates/bug-report-template.md
D  .claude/skills/eval/LICENSE.pstack
D  .claude/skills/eval/SKILL.md
D  .claude/skills/eval/references/probe-recipe.md
D  .claude/skills/eval/scripts/grade-skill-loads.sh
D  .claude/skills/folder-context-optimization/SKILL.md
D  .claude/skills/html-presentation/SKILL.md
D  .claude/skills/html-presentation/references/design-principles.md
D  .claude/skills/html-presentation/scripts/generate-presentation.py
D  .claude/skills/learn/SKILL.md
D  .claude/skills/maintain-verification-skill/LICENSE.pstack
D  .claude/skills/maintain-verification-skill/SKILL.md
D  .claude/skills/memory-maintain/SKILL.md
D  .claude/skills/plan/SKILL.md
D  .claude/skills/prd/SKILL.md
D  .claude/skills/quality-gate/SKILL.md
D  .claude/skills/receive-review/SKILL.md
D  .claude/skills/refresh/SKILL.md
D  .claude/skills/security-scan/SKILL.md
D  .claude/skills/setup-deployment/SKILL.md
D  .claude/skills/software-design-expert-learn/SKILL.md
D  .claude/skills/software-design-expert-learn/references/principles.md
D  .claude/skills/software-design-expert-review/SKILL.md
D  .claude/skills/start-qa/SKILL.md
D  .claude/skills/sweep/SKILL.md
D  .claude/skills/sweep/references/lens-architect.md
D  .claude/skills/sweep/references/lens-janitor.md
D  .claude/skills/sync/SKILL.md
D  .claude/skills/sync/scripts/sync-retire.py
D  .claude/skills/system-design-planning/SKILL.md
D  .claude/skills/system-design-planning/references/review-card.md
D  .claude/skills/system-design-planning/templates/architecture-spec-template.md
D  .claude/skills/system-design-planning/templates/content-model.json
D  .claude/skills/task-registry/SKILL.md
D  .claude/skills/task-registry/references/configuration.md
D  .claude/skills/task-registry/references/progressive-disclosure.md
D  .claude/skills/task-registry/scripts/registry/__init__.py
D  .claude/skills/task-registry/scripts/registry/config.py
D  .claude/skills/task-registry/scripts/registry/detail.py
D  .claude/skills/task-registry/scripts/registry/escalation.py
D  .claude/skills/task-registry/scripts/registry/index.py
D  .claude/skills/task-registry/scripts/registry/model.py
D  .claude/skills/task-registry/scripts/registry/providers/__init__.py
D  .claude/skills/task-registry/scripts/registry/providers/base.py
D  .claude/skills/task-registry/scripts/registry/providers/github.py
D  .claude/skills/task-registry/scripts/registry/providers/local.py
D  .claude/skills/task-registry/scripts/registry/redaction.py
D  .claude/skills/task-registry/scripts/registry/routines.py
D  .claude/skills/task-registry/scripts/registry/upsert.py
D  .claude/skills/task-registry/scripts/task-registry.py
D  .claude/skills/task-registry/templates/task-tracking.md
D  .claude/skills/tidy/SKILL.md
D  .claude/skills/verify-deployment/SKILL.md
D  .claude/skills/verify-evidence/SKILL.md
D  .claude/skills/verify-task-registry/SKILL.md
D  .claude/skills/verify-task-registry/features/README.md
D  .claude/skills/verify-task-registry/features/escalate-investigation.md
D  .claude/skills/verify-task-registry/features/external-reference-fallback.md
D  .claude/skills/verify-task-registry/features/read-task.md
D  .claude/skills/verify-task-registry/features/record-task.md
D  .claude/skills/verify-task-registry/features/routines.md
D  .claude/skills/visual-plan/SKILL.md
D  .claude/skills/visual-recap/SKILL.md
D  .claude/skills/visual-recap/scripts/visual-render.py
D  .claude/skills/wrap-up-session/SKILL.md
D  .claude/skills/wrap-up-session/references/routine-prompts/README.md
D  .claude/skills/wrap-up-session/references/routine-prompts/architect.md
D  .claude/skills/wrap-up-session/references/routine-prompts/fix.md
D  .claude/skills/wrap-up-session/references/routine-prompts/improve.md
D  .claude/skills/wrap-up-session/references/routine-prompts/janitor.md
D  .claude/skills/wrap-up-session/references/routine-prompts/plan.md
D  .claude/skills/wrap-up-session/references/routine-prompts/tidy.md
D  .claude/skills/wrap-up-session/references/routines.md
D  .claude/skills/wrap-up-session/scripts/pr_linkage.py
D  .claude/skills/wrap-up-session/scripts/routine_branch.py
D  .claude/skills/wrap-up-session/scripts/spec-reconcile.py
D  .claude/skills/writing-skills/SKILL.md
D  .claude/skills/yolo/SKILL.md
 M CLAUDE.md
 M README.md
 M tasks/concepts.md
 M tasks/e2e-log.md
 M tasks/todo.md
 M tests/test-doc-conventions.sh
 M tests/test-e2e-classifier.sh
 M tests/test-eval-skill.sh
 M tests/test-html-presentation.sh
 M tests/test-living-spec-reconciliation.sh
 M tests/test-memory-maintain-doc.sh
 M tests/test-model-tiers.sh
 M tests/test-plugin-manifest.sh
 M tests/test-pre-push-gate.sh
 M tests/test-refresh-skill.sh
 M tests/test-review-context.sh
 M tests/test-routine-escalation-handoff.sh
 M tests/test-routine-selectors.sh
 M tests/test-routine-skills.sh
 M tests/test-routine-step-ledger.sh
 M tests/test-routine-wrapup.sh
 M tests/test-routines-contract.sh
 M tests/test-skill-frontmatter.sh
 M tests/test-skill-invocation-chain.sh
D  tests/test-skill-parity.sh
 M tests/test-skill-references.sh
 M tests/test-sweep-handoff.sh
 M tests/test-sweep-routines.sh
 M tests/test-sync-retirement.sh
 M tests/test-syncable-paths.sh
 M tests/test-task-registry.sh
 M tests/test-tdd-retirement.sh
 M tests/test-verification-skill-integration.sh
 M tests/test-verifier-source-waves.sh
 M tests/test-visual-render.sh
```

## In-Progress & Pending Tasks (tasks/todo.md)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/
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
