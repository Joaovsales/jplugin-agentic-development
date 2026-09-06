# Checkpoint — 2026-09-05T17:30:21Z

> Auto-written by PreCompact hook (trigger: auto). Re-read on resume.

## Git
- Branch: analysis/simplify-routing

```
M  .agents/skills/auto-improve/SKILL.md
M  .agents/skills/memory-maintain/SKILL.md
D  .agents/skills/route/SKILL.md
D  .agents/skills/route/playbooks/autonomous.md
D  .agents/skills/route/playbooks/gated-at-plan-and-pre-push.md
D  .agents/skills/route/playbooks/gated-at-plan.md
D  .agents/skills/route/scripts/route_issue.py
M  .agents/skills/task-registry/scripts/registry/config.py
M  .agents/skills/task-registry/scripts/registry/providers/base.py
M  .agents/skills/task-registry/scripts/registry/providers/github.py
A  .agents/skills/task-registry/scripts/registry/routines.py
M  .agents/skills/task-registry/scripts/task-registry.py
M  .agents/skills/task-registry/templates/task-tracking.md
M  .agents/skills/wrap-up-session/SKILL.md
A  .agents/skills/wrap-up-session/references/routines.md
A  .agents/skills/wrap-up-session/scripts/routine_branch.py
M  .claude/hooks/session-start.sh
D  .claude/hooks/user-prompt-route.sh
M  .claude/settings.json
M  .claude/skills/auto-improve/SKILL.md
M  .claude/skills/memory-maintain/SKILL.md
D  .claude/skills/route/SKILL.md
D  .claude/skills/route/playbooks/autonomous.md
D  .claude/skills/route/playbooks/gated-at-plan-and-pre-push.md
D  .claude/skills/route/playbooks/gated-at-plan.md
D  .claude/skills/route/scripts/route_issue.py
M  .claude/skills/task-registry/scripts/registry/config.py
M  .claude/skills/task-registry/scripts/registry/providers/base.py
M  .claude/skills/task-registry/scripts/registry/providers/github.py
A  .claude/skills/task-registry/scripts/registry/routines.py
M  .claude/skills/task-registry/scripts/task-registry.py
M  .claude/skills/task-registry/templates/task-tracking.md
M  .claude/skills/wrap-up-session/SKILL.md
A  .claude/skills/wrap-up-session/references/routines.md
A  .claude/skills/wrap-up-session/scripts/routine_branch.py
M  CLAUDE.md
M  README.md
A  specs/category-routines.md
D  specs/issue-lane-routing.md
MM tasks/checkpoint.md
M  tasks/history.md
A  tasks/solutions/architecture/a-bidirectional-map-cannot-be-widened-for-one-direction.md
M  tasks/solutions/architecture/hard-gate-on-tasks-todo-md.md
M  tasks/solutions/bugs/grep-zero-matches-aborts-hooks-under-set-e-pipefail.md
M  tasks/solutions/patterns/consume-structured-records-before-rendering-human-summaries.md
A  tasks/solutions/patterns/shape-validation-cannot-catch-a-membership-error.md
A  tasks/solutions/patterns/validate-in-the-loader-not-in-one-optional-command.md
M  tasks/todo.md
M  tasks/wrap-up-debt.md
A  tests/test-auto-improve-rewire.sh
M  tests/test-doc-conventions.sh
M  tests/test-model-tiers.sh
M  tests/test-review-context.sh
D  tests/test-route-decision.sh
D  tests/test-route-hook.sh
D  tests/test-route-skill.sh
A  tests/test-routine-branch.sh
A  tests/test-routine-selectors.sh
A  tests/test-routine-step-ledger.sh
A  tests/test-routine-wrapup.sh
A  tests/test-routines-contract.sh
M  tests/test-session-start.sh
M  tests/test-skill-invocation-chain.sh
M  tests/test-task-registry.sh
?? tasks/tmp/
```

## In-Progress & Pending Tasks (tasks/todo.md)
(none)

## Active Spec
- specs/category-routines.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
