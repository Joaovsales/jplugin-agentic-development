# Checkpoint — 2026-10-19T18:21:22Z

> Auto-written by PreCompact hook (trigger: ). Re-read on resume.

## Git
- Branch: claude/practical-knuth-31f2ht

```
 M tasks/todo.md
```

## In-Progress & Pending Tasks (tasks/todo.md)
  [ ] TDD: tests/test-task-registry.sh § parent — `--parent '#N'` on the local fixture records a native parent; on the github fixture writes `parent:` metadata and prints the disclosure line; the dry run calls no provider; `SKILL.md` documents the flag -> `--parent` on `upsert` wired to `link_parent` (AC 7) — pending: the PR's Linux CI run (the GitHub-mock pins cannot reach the `gh` mock from Python on Windows, #129)
  [ ] TDD: tests/test-doc-conventions.sh § workflow — `CLAUDE.md` steps 1 to 3 name `/grill-me` and `/brainstorm` as optional precursors, `/grilling` as mandatory in `/system-design-planning`, `DECISIONS CARRIED`, `/slice`, the build prompt, a fresh session and `> Handover:`; "Confirm with 'y' to begin" and the **approved** parenthetical are gone; `tasks/concepts.md` defines slice, surface, ready set, handover and build prompt; `bash tests/run.sh` green on CI -> rewrite § Workflow 1 to 3; `/learn` the five terms (AC 14) — pending: `bash tests/run.sh` green on the PR's Linux CI run (580 § workflow assertions pass here; Windows carries 159 pre-existing failures)
  [ ] Verify: parallel dispatch of two disjoint slices and a handover read by a dispatched blocked slice — rerun under an isolated `CLAUDE_CONFIG_DIR` with two ready slices each large enough for `/build` to dispatch (tasks/backlog.md § From #106)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/
  [ ] /eval triggerability gate on /plan, /build, /quality-gate — manual, before the slice-2 merge; report path goes in the PR body — DEFERRED (manual gate; run before the slice-2 PR merges, not inside /build)
  [ ] Verify: `/eval` Mode B, N >= 2 per arm, current vs updated code-reviewer vs ponytail-review on the seeded diffs: recall and false positives against the key, readability by a blinded Ceiling judge, cost; report path in the PR body — manual gate (AC 9)
  [ ] TDD: tests/test-diagram-skill.sh § how — how/SKILL.md ends its output contract with the one-line offer; explainer-prompt.md no longer says mermaid or ASCII -> offer line and prompt edit (AC 10)
  [ ] TDD: tests/test-diagram-skill.sh § plan — plan/SKILL.md § 4 Present carries the one-line offer for multi-component features -> offer line (AC 11)
  [ ] TDD: tests/test-diagram-skill.sh § sdp — system-design-planning/SKILL.md names the architecture diagram beside the spec and the no-tool line (install command, continue) -> deliverable paragraph (AC 12)
  [ ] TDD: tests/test-doc-conventions.sh and tests/test-skill-references.sh pass with the new `tools` row naming ARCHIFY_HOME, the inconclusive case and the Tier 1 remedy -> `tools` row in § The checks plus its edge cases (AC 13)
  [ ] TDD: tests/test-diagram-skill.sh § frontmatter still passes after the description edit; the eval report path is linked from § Decisions row 10 or the PR description -> /eval triggerability run and description wording (AC 9)

## Active Spec
- specs/diagram-skill.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
