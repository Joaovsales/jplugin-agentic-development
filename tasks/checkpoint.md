# Checkpoint — 2026-09-22T14:18:38Z

> Auto-written by PreCompact hook (trigger: ). Re-read on resume.

## Git
- Branch: feat/106-plan-slices-and-handover

```
 M .agents/skills/task-registry/SKILL.md
 M .agents/skills/task-registry/scripts/registry/upsert.py
 M .agents/skills/task-registry/scripts/task-registry.py
 M .agents/skills/wrap-up-session/scripts/spec-reconcile.py
?? .agents/skills/slice/scripts/
?? .agents/skills/task-registry/scripts/registry/globs.py
?? tests/fixtures/slice/
```

## In-Progress & Pending Tasks (tasks/todo.md)
  [ ] TDD: tests/test-slice.sh § validate — fixture with an intersecting pair and no blocker exits 1 naming both slices; a cycle exits 1 naming the cycle; a surface path outside `implementation_paths` exits 1 naming the path; the clean fixture exits 0 -> `slice.py validate --spec` parsing § Build Order and the frontmatter (AC 1)
  [ ] TDD: tests/test-slice.sh § ready — fixture index with three slices where 2 is blocked by 1: `ready` lists 1 and 3 with surfaces and the intersecting pair `1 ↔ 3`; after 1 is `[x]` it lists 2 and 3; a block with no `### Slice` headings yields one implicit slice whose surface equals `implementation_paths` -> `slice.py ready --index --spec` over `TaskIndex` (AC 2)
  [ ] TDD: tests/test-slice.sh § check — fixture repo where the diff touches one declared and one undeclared path: prints `undeclared:` and `untouched:`, exit 1; clean diff exits 0 and prints nothing -> `slice.py check --spec --slice --base` over `git diff --name-only` (AC 3)
  [ ] TDD: tests/test-slice.sh § globs — `registry/globs.py` rejects absolute, `..`, backslash and unsupported-glob patterns naming spec and value; tests/test-living-spec-reconciliation.sh stays green with `spec-reconcile.py` importing `_pattern_to_regex` and `match_path` from it -> extract the matcher, repoint `spec-reconcile.py` through `sys.path` (AC 3)
  [ ] TDD: tests/test-task-registry.sh § parent — `--parent '#N'` on the local fixture records a native parent; on the github fixture writes `parent:` metadata and prints the disclosure line; the dry run calls no provider; `SKILL.md` documents the flag -> `--parent` on `upsert` wired to `link_parent` (AC 7)
  [ ] TDD: tests/test-task-registry.sh § seeded blocked-by — a first `upsert --apply` against an index row that carries `(blocked-by: id)` keeps the marker on the refreshed row, and a second run keeps it too -> carry the index row's `depends_on` into the merge when the incoming task has none (added in `/build` pre-flight: the probe on a local fixture dropped the marker, so filing before this fix would corrupt the plan block)
  [ ] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § plan — Step 1 keeps its six questions, has no `Invoke /grilling` line, names `/grill-me` and `/brainstorm` as optional precursors and states `DECISIONS CARRIED`; Step 1.5 has `Escalating to /system-design-planning`; the template lists Behavior, Inputs, Outputs, Edge Cases, Decisions, Acceptance Criteria, Implementation Paths in order with `user`, `assumed`, `open`; Step 3 has an `Invoke /slice` line; "Does this spec and plan meet your requirements" is absent; Step 6 names `Spec and plan are ready to be built`; no `Invoke /build`, no hand-written `## Plan:` template, no `upsert` invocation and no `> Approved` remains -> rewrite `/plan` Steps 3 to 6, delete Step 7 (AC 8)
  [ ] TDD: tests/test-doc-conventions.sh § pipelines — `/yolo`'s override table has a Step 1 row naming `assumed` rows, a Step 6 row naming no prompt and `/build` in place, and a Phase B line naming `--file` without `--approve`; `/auto-push` Phase A contains "Does this spec and plan meet your requirements?" as an override on `/plan` Step 6 and Phase B names `--approve`; both name the fresh-session rule they are excepted from -> edit the rows in both pipelines (AC 9)
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
