# Checkpoint — 2026-09-22T15:01:24Z

> Auto-written by PreCompact hook (trigger: ). Re-read on resume.

## Git
- Branch: feat/106-plan-slices-and-handover

```
(working tree clean)
```

## In-Progress & Pending Tasks (tasks/todo.md)
  [ ] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § design planning — Step 1 names § Decisions; Step 2.5 has an `Invoke /grilling` line with its seed questions, `DECISIONS CARRIED` and the empty-frontier rule, pinned in the invocation-chain test beside `/brainstorm`'s; the template has no `| # | Slice |` table and no `### Slice criteria`; Step 3.5 has an `Invoke /slice` line; Step 7 keeps the `[constraints|system-design|contracts|data-models|build-order]` format, names `Spec and plan are ready to be built` and no longer says the bare word is approval; no `File slices` heading, `upsert` invocation, `> Approved` or `TODO(shortcut)` remains; `### 9. Hand off` present; Iron Law and Red Flag name the planning session; the chain pin "files slices through task-registry" moves to `slice/SKILL.md`, the other three (reads issues, renders, hands off) still hold -> rewrite Steps 1, 3, 3.5, 7, 9, the Iron Law, the Red Flags and the description; delete Step 8; trim the template; move one chain pin (AC 10)
  [ ] TDD: tests/test-grilling-adoption.sh stays green and tests/test-doc-conventions.sh § brainstorm pins `## Decisions` with a `Source` column in the Step 6 template -> extend Step 6's template by one section (AC 11)
  [ ] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § build — pre-flight has an `Invoke /slice` line with `--file --approve`, the missing-link condition and the `/yolo` exception, and names the implicit slice; the description no longer says "after `/plan` is confirmed"; Phase 1 names `slice.py ready` and no longer assesses independence from prose; the delegation list has items 5 to 7 with `[SURFACE] +`, `> Handover:` and the budget; slice close names `slice.py check`, `undeclared:`, `untouched:`; the handover rule names the two required facts and `unfinished:`; Phase 6 counts nested `[x]` rows and names the forbidden state; `slice header` still present -> rewrite Phase 1 and Phase 6 (AC 12)
  [ ] TDD: tests/test-doc-conventions.sh § wrap-up — the PR body step names `## Handovers` before the linkage check and the commit-message fallback -> add the section rule to Step 7 (AC 13)
  [ ] TDD: tests/test-doc-conventions.sh § workflow — `CLAUDE.md` steps 1 to 3 name `/grill-me` and `/brainstorm` as optional precursors, `/grilling` as mandatory in `/system-design-planning`, `DECISIONS CARRIED`, `/slice`, the build prompt, a fresh session and `> Handover:`; "Confirm with 'y' to begin" and the **approved** parenthetical are gone; `tasks/concepts.md` defines slice, surface, ready set, handover and build prompt; `bash tests/run.sh` green on CI -> rewrite § Workflow 1 to 3; `/learn` the five terms (AC 14)
  [ ] Verify: one live two-slice run across two sessions on a fixture feature: the `/plan` session ends with the build prompt and files nothing; the fresh session started with it files the slices in pre-flight, shows `DECISIONS CARRIED`, parallel dispatch of two disjoint slices, a handover read by a blocked slice and a surface report; recorded in tasks/e2e-log.md with the commit sha (AC 15)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/

## Active Spec
- specs/grilling-adoption.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
