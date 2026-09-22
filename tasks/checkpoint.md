# Checkpoint — 2026-09-22T13:06:44Z

> Auto-written by PreCompact hook (trigger: manual). Re-read on resume.

## Git
- Branch: feat/106-plan-slices-and-handover

```
(working tree clean)
```

## In-Progress & Pending Tasks (tasks/todo.md)
  [ ] TDD: tests/test-slice.sh § validate — fixture with an intersecting pair and no blocker exits 1 naming both slices; a cycle exits 1 naming the cycle; a surface path outside `implementation_paths` exits 1 naming the path; the clean fixture exits 0 -> `slice.py validate --spec` parsing § Build Order and the frontmatter (AC 1)
  [ ] TDD: tests/test-slice.sh § ready — fixture index with three slices where 2 is blocked by 1: `ready` lists 1 and 3 with surfaces and the intersecting pair `1 ↔ 3`; after 1 is `[x]` it lists 2 and 3; a block with no `### Slice` headings yields one implicit slice whose surface equals `implementation_paths` -> `slice.py ready --index --spec` over `TaskIndex` (AC 2)
  [ ] TDD: tests/test-slice.sh § check — fixture repo where the diff touches one declared and one undeclared path: prints `undeclared:` and `untouched:`, exit 1; clean diff exits 0 and prints nothing -> `slice.py check --spec --slice --base` over `git diff --name-only` (AC 3)
  [ ] TDD: tests/test-slice.sh § globs — `registry/globs.py` rejects absolute, `..`, backslash and unsupported-glob patterns naming spec and value; tests/test-living-spec-reconciliation.sh stays green with `spec-reconcile.py` importing `_pattern_to_regex` and `match_path` from it -> extract the matcher, repoint `spec-reconcile.py` through `sys.path` (AC 3)
  [ ] TDD: tests/test-doc-conventions.sh § slice — `.agents/skills/slice/SKILL.md` has `name: slice`, `disable-model-invocation: false`, `harness: universal`, an `argument-hint`; both references exist; `CLAUDE.md` and `README.md` skills tables and `.claude/hooks/session-start.sh` list `/slice`; `sizing.md` states `files > 8`, `systems > 2`, `ACs > 3` and contains no `floor`, `S (`, `M (` or `L (` label -> write the skill, the two references and the three rows (AC 4)
  [ ] TDD: tests/test-doc-conventions.sh § slice propose — SKILL.md names `slice.py validate`, `✓ Build Order written:`, `✓ Plan written:`, `Caller gates`, `--derive-id plan`, `--fold-title`, the leading-`/` rule, and the in-place replacement rule; the plan-block example in SKILL.md and `references/plan-block.md` compare equal after flattening -> document the propose phase against the reference (AC 5)
  [ ] TDD: tests/test-doc-conventions.sh § slice file — SKILL.md names the `> Approved` refusal, `--parent`, `--approve`, `local-pending` and `✓ Filed:`; the upsert invocation contains no `--depends-on` -> document the `--file` phase (AC 6)
  [ ] TDD: tests/test-task-registry.sh § parent — `--parent '#N'` on the local fixture records a native parent; on the github fixture writes `parent:` metadata and prints the disclosure line; the dry run calls no provider; `SKILL.md` documents the flag -> `--parent` on `upsert` wired to `link_parent` (AC 7)
  [ ] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § plan — Step 1 keeps its six questions, has no `Invoke /grilling` line, names `/grill-me` and `/brainstorm` as optional precursors and states `DECISIONS CARRIED`; Step 1.5 has `Escalating to /system-design-planning`; the template lists Behavior, Inputs, Outputs, Edge Cases, Decisions, Acceptance Criteria, Implementation Paths in order with `user`, `assumed`, `open`; Steps 3 and 6 have `Invoke /slice` lines; Step 4's sentence is unchanged and names `> Approved`; no hand-written `## Plan:` template or `upsert` invocation remains -> rewrite `/plan` Steps 1 to 6 (AC 8)
  [ ] TDD: tests/test-doc-conventions.sh § unattended — `/yolo`'s override table has a Step 1 row naming `assumed` rows and a Step 4 row naming `> Approved` and `(unattended)`; `/auto-push` still contains "Does this spec and plan meet your requirements?" verbatim -> edit the two rows; leave `/auto-push` as it is (AC 9)
  [ ] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § design planning — Step 1 names § Decisions; Step 2.5 has an `Invoke /grilling` line with its seed questions, `DECISIONS CARRIED` and the empty-frontier rule, pinned in the invocation-chain test beside `/brainstorm`'s; the template has no `| # | Slice |` table and no `### Slice criteria`; Steps 3.5 and 8 have `Invoke /slice` lines, Step 8 with `--file --approve`; `TODO(shortcut)` is absent; the existing chain pins (reads issues, files through the registry, renders, hands off to `/build`) still hold -> rewrite Steps 1, 3, 3.5 and 8; trim the template (AC 10)
  [ ] TDD: tests/test-grilling-adoption.sh stays green and tests/test-doc-conventions.sh § brainstorm pins `## Decisions` with a `Source` column in the Step 6 template -> extend Step 6's template by one section (AC 11)
  [ ] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § build — pre-flight names the implicit slice; Phase 1 names `slice.py ready` and no longer assesses independence from prose; the delegation list has items 5 to 7 with `[SURFACE] +`, `> Handover:` and the budget; slice close names `slice.py check`, `undeclared:`, `untouched:`; the handover rule names the two required facts and `unfinished:`; Phase 6 counts nested `[x]` rows and names the forbidden state; `slice header` still present -> rewrite Phase 1 and Phase 6 (AC 12)
  [ ] TDD: tests/test-doc-conventions.sh § wrap-up — the PR body step names `## Handovers` before the linkage check and the commit-message fallback -> add the section rule to Step 7 (AC 13)
  [ ] TDD: tests/test-doc-conventions.sh § workflow — `CLAUDE.md` steps 1 to 3 name `/grill-me` and `/brainstorm` as optional precursors, `/grilling` as mandatory in `/system-design-planning`, `DECISIONS CARRIED`, `/slice`, one gate and `> Handover:`; `tasks/concepts.md` defines slice, surface, ready set and handover; `bash tests/run.sh` green on CI -> rewrite § Workflow 1 to 3; `/learn` the four terms (AC 14)
  [ ] Verify: one live two-slice `/plan` → `/build` run on a fixture feature shows `DECISIONS CARRIED`, parallel dispatch of two disjoint slices, a handover read by a blocked slice and a surface report; recorded in tasks/e2e-log.md with the commit sha (AC 15)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/

## Active Spec
- specs/grilling-adoption.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
