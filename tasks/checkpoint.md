# Checkpoint — 2026-09-16T20:15:27Z
# Checkpoint — 2026-09-22T16:45:13Z

> Auto-written by PreCompact hook (trigger: ). Re-read on resume.

## Git
- Branch: routing

```
 M .agents/skills/go/SKILL.md
D  .agents/skills/go/lanes/babysit.md
D  .agents/skills/go/lanes/fix.md
D  .agents/skills/go/lanes/investigate.md
D  .agents/skills/go/lanes/perf.md
D  .agents/skills/go/lanes/refactor.md
 M .agents/skills/task-registry/SKILL.md
 M .agents/skills/task-registry/scripts/registry/config.py
 M .agents/skills/task-registry/scripts/registry/escalation.py
 M .agents/skills/task-registry/scripts/task-registry.py
 M .agents/skills/task-registry/templates/task-tracking.md
 M .agents/skills/wrap-up-session/references/routines.md
 M .claude/skills/go/SKILL.md
D  .claude/skills/go/lanes/babysit.md
D  .claude/skills/go/lanes/fix.md
D  .claude/skills/go/lanes/investigate.md
D  .claude/skills/go/lanes/perf.md
D  .claude/skills/go/lanes/refactor.md
 M .claude/skills/task-registry/SKILL.md
 M .claude/skills/task-registry/scripts/registry/config.py
 M .claude/skills/task-registry/scripts/registry/escalation.py
 M .claude/skills/task-registry/scripts/task-registry.py
 M .claude/skills/task-registry/templates/task-tracking.md
 M .claude/skills/wrap-up-session/references/routines.md
 M README.md
 M specs/go-front-door.md
 M tasks/concepts.md
 M tasks/todo.md
 M tests/test-go-lanes.sh
 M tests/test-routine-selectors.sh
 M tests/test-routines-contract.sh
 M tests/test-sweep-routines.sh
?? .agents/skills/task-registry/lanes/
?? .agents/skills/task-registry/scripts/registry/lanes.py
?? .claude/skills/task-registry/lanes/
?? .claude/skills/task-registry/scripts/registry/lanes.py
?? specs/lane-catalogue.md
?? tests/test-lane-catalogue.sh
- Branch: feat/106-plan-slices-and-handover

```
 M tasks/checkpoint.md
```

## In-Progress & Pending Tasks (tasks/todo.md)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/
[ ] TDD: tests/test-lane-catalogue.sh RED — shipped catalogue views (routines, producers, deferred, selectors, chains, interactive, names) equal the spec table; eight load refusals on temp fixture directories each name the file -> `registry/lanes.py` (frontmatter + step grammar, Lane, LaneCatalogue, load_catalogue) and the twelve lane files under `.agents/skills/task-registry/lanes/` (AC1, AC2, AC3)
[ ] TDD: test-routine-skills.sh, test-routine-selectors.sh (literal-in-config.py pin repointed at the catalogue), test-routines-contract.sh deferred pins, test-task-registry.sh, test-sweep-routines.sh all green with config.py's five constants bound to the catalogue and holding no lane literal -> config.py edit (AC1, AC5)
[ ] TDD: `lanes` table with effective chain; `lanes <name>` steps + Reply; unknown name exit 2 listing lanes; chain skill absent from both roots exit 2 naming it; `[routines.skills]` override prints `note:`; misconfigured tracker exit 2 -> `lanes` command in task-registry.py; SKILL.md command table row and section (AC4)
[ ] TDD: test-routines-contract.sh pins the routine table equal to the catalogue and reads each routine's step rows from its lane file; per-routine sections carry no step rows; test-sweep-routines.sh section pins repointed -> routines.md per-routine sections shrink to the lane pointer plus rationale (AC6)
[ ] TDD: test-go-lanes.sh rewritten — SKILL.md names `task-registry lanes` and `workflow`, no lane table, no `go/lanes/`; interactive code-changing lanes gate before /build; investigate never names /wrap-up-session; host sweep and banner pins unchanged -> rewrite `.agents/skills/go/SKILL.md`, delete `go/lanes/`, README row, concepts.md entries, go-front-door.md supersession note, template `[routines.skills]` comment (AC7, AC8)
[ ] Verify: byte-identical `.claude` copies (test-skill-parity.sh); `bash tests/run.sh` against the recorded baseline; `/quality-gate` on all changed files (AC9)

## Active Spec
- specs/lane-catalogue.md

## Active Spec
- specs/grilling-adoption.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
