# Checkpoint — 2026-10-22T18:04:00Z

> Auto-written by PreCompact hook (trigger: ). Re-read on resume.

## Git
- Branch: claude/test-suite-aposd-build-14b7ef

```
 M tasks/checkpoint.md
 M tasks/concepts.md
 M tasks/history.md
 M tasks/solutions/process/a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md
 M tasks/solutions/process/four-unresolved-should-fix-make-a-hold-and-a-delta-receipt-inherits-them.md
 M tasks/todo.md
?? tasks/solutions/conventions/a-fixture-builder-run-in-a-command-substitution-keeps-its-exit-143-guard.md
```

## In-Progress & Pending Tasks (tasks/todo.md)
  [ ] TDD: tests/test-task-registry.sh § parent — `--parent '#N'` on the local fixture records a native parent; on the github fixture writes `parent:` metadata and prints the disclosure line; the dry run calls no provider; `SKILL.md` documents the flag -> `--parent` on `upsert` wired to `link_parent` (AC 7) — pending: the PR's Linux CI run (the GitHub-mock pins cannot reach the `gh` mock from Python on Windows, #129)
  [ ] TDD: tests/test-doc-conventions.sh § workflow — `CLAUDE.md` steps 1 to 3 name `/grill-me` and `/brainstorm` as optional precursors, `/grilling` as mandatory in `/system-design-planning`, `DECISIONS CARRIED`, `/slice`, the build prompt, a fresh session and `> Handover:`; "Confirm with 'y' to begin" and the **approved** parenthetical are gone; `tasks/concepts.md` defines slice, surface, ready set, handover and build prompt; `bash tests/run.sh` green on CI -> rewrite § Workflow 1 to 3; `/learn` the five terms (AC 14) — pending: `bash tests/run.sh` green on the PR's Linux CI run (580 § workflow assertions pass here; Windows carries 159 pre-existing failures)
  [ ] Verify: parallel dispatch of two disjoint slices and a handover read by a dispatched blocked slice — rerun under an isolated `CLAUDE_CONFIG_DIR` with two ready slices each large enough for `/build` to dispatch (tasks/backlog.md § From #106)
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/
  [ ] /eval triggerability gate on /plan, /build, /quality-gate — manual, before the slice-2 merge; report path goes in the PR body — DEFERRED (manual gate; run before the slice-2 PR merges, not inside /build)
  [ ] Verify: `/eval` Mode B, N >= 2 per arm, current vs updated code-reviewer vs ponytail-review on the seeded diffs: recall and false positives against the key, readability by a blinded Ceiling judge, cost; report path in the PR body — manual gate (AC 9)
  [ ] TDD: CI — `bash tests/run.sh` is green on the pull request's Linux run; the Windows receipt is compared against the base with `comm`, never by count -> no code beyond the slices above (AC 12)
  [ ] TDD: tests/test-helix-gates.sh § schema — malformed, missing, stale, wrong-slice and unknown-version records refuse; identical input is idempotent; bookkeeping edits do not stale Surface evidence and old receipts verify against their historical commit -> versioned evidence validator and activation ledger (AC 4)
  [ ] TDD: tests/test-helix-prototype.sh § interaction — offline HTML reaches each declared state by an actual control and follows approved design inputs -> prototype skill and state manifest (AC 7)
  [ ] TDD: tests/test-slice.sh § helix-ready — a done blocker without committed receipt or exact-set combined-tree barrier refuses; valid proof releases dependents; legacy fixtures stay green -> readiness verifier (AC 5)
  [ ] TDD: tests/test-helix-unit-gate.sh § unit-base — a completed unit with later slices pending runs all six existing quality phases against one parent base and retains a keyed receipt; changed head/base invalidates it -> unit-scoped gate and receipt write --base (AC 23)
  [ ] TDD: tests/test-helix-behavior.sh § red-green — separate test-planning and implementation contexts produce a meaningful failure then a tree-bound green affected run -> behavior gate (AC 6)
  [ ] TDD: tests/test-helix-ui.sh § state-match — matching state/viewport captures report located differences, mismatch reports INVALID, non-UI skip carries a reason -> UI gate (AC 9)
  [ ] TDD: tests/test-helix-review.sh § dual-verdict — isolated reviewers use seven-item dispatch and existing GO/HOLD/STOP policy; a code fix stales affected evidence -> review gate (AC 10)
  [ ] TDD: tests/test-helix-human.sh § grant — only a host role-tagged owner turn issues an exact next-N grant; agent-authored or unverifiable resumed records refuse; named slices record delegated, never owner-approved -> human gate (AC 11)
  [ ] TDD: tests/test-helix-human.sh § retry — exhausted attempts block the slice and descendants while unrelated ready slices continue -> bounded repair (AC 12)
  [ ] TDD: tests/test-helix-build.sh § close-commit — source, receipt, handover and done header land in one slice commit; commit failure leaves dependents blocked -> build integration (AC 13)
  [ ] TDD: tests/test-helix-parallel.sh § merge-barrier — two disjoint workers never edit shared status; central integration serializes commits, tests and quality, then commits an exact-set barrier before descendants release -> integration barrier (AC 14)
  [ ] TDD: tests/test-helix-build.sh § feedback — human correction reaches typed learning and next handover/context without flat memory -> learning flow (AC 15)
  [ ] TDD: tests/test-helix-wrapup.sh § closure — final human acceptance and pre-existing slice commits precede receipt checks, full suite, capture publication and one PR; ordinary build remains green -> wrap-up integration (AC 18)
  [ ] TDD: tests/test-helix-plan.sh § marker — Helix planning writes workflow: helix/1 and checkpoint reference/gate/done criteria into the spec and prompt -> plan contract (AC 3)
  [ ] TDD: tests/test-helix-plan.sh § prototype-digest — prompt carries approved prototype bytes; changed bytes invalidate UI evidence and grants -> digest propagation (AC 8)
  [ ] TDD: tests/test-helix-view.sh § view — rendered checkpoint order, status and evidence links match canonical spec/todo/receipts -> read-only viewer (AC 16)
  [ ] TDD: tests/test-helix-stop.sh § stop — Claude reports active open gates but permits waiting_human/blocked; advancement CLI remains cross-harness -> Stop reminder (AC 17)
  [ ] TDD: tests/test-lane-catalogue.sh § helix-lane — explicit Helix cues register as a separate lane without changing ordinary lane selection -> lane declaration (AC 1)
  [ ] TDD: tests/test-go-lanes.sh § helix-route — explicit Helix build request selects the lane; ordinary build and investigate requests keep their current route -> /go selection (AC 2)
  [ ] TDD: tests/test-helix-stack-plan.sh § review-units — contiguous units cover every slice once; published ID/range/base freeze, reopened slices retain IDs, new scope appends a tail unit and only an unpublished suffix may shift; absent units keep one PR -> unit grammar and `/slice` validation (AC 19)
  [ ] TDD: tests/test-helix-stack-branch.sh § remote-state — branch/PR head-base lookup is idempotent; timeout is unknown; parent updates merge without rebase; wrong base, duplicate PR and rewritten SHA refuse -> stack inspect and branch contract (AC 20)
  [ ] TDD: tests/test-helix-stack-build.sh § boundary — a unit opens only after all slice commits and its barrier; the next unit starts on its declared parent head; blocked/stale ancestors keep descendants draft -> `/build` review-unit transition (AC 21)
  [ ] TDD: tests/test-helix-stack-wrapup.sh § closure — each PR has a retained unit receipt/suite/CI/evidence; intermediate uses Refs, final uses Closes; merge commit preserves slice SHAs; retarget and final acceptance recheck integrated tree; single-PR and ordinary modes stay green -> stacked wrap-up (AC 22)

## Active Spec
- specs/test-suite-aposd.md

## How to Resume
1. Read this file and `tasks/todo.md`
2. Grep `tasks/solutions/` frontmatter (problem_type, module, tags) for relevant learnings
3. Continue from the first `[~]` (or `[ ]`) item in `tasks/todo.md`
