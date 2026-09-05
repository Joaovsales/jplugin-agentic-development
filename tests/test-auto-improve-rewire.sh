#!/bin/bash
# tests/test-auto-improve-rewire.sh — the unattended runner keeps its review (AC10).
#
# /auto-improve delegated lane policy to the deleted routing engine, and Phase 4's
# ONLY reviewer dispatch was a reference into it: "execute the materialized lane's
# verification and reviewer rows". Delete the engine without replacing that
# sentence and the daily unattended runner ships PRs with no independent review
# and nothing anywhere saying a gate was skipped.
#
# That is pipeline #93 verbatim — "not by decision, by omission" — reproduced in
# the highest-risk consumer this repo has, because it is the one nobody watches.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

for tree in .agents .claude; do
  f="$tree/skills/auto-improve/SKILL.md"

  phase3="$(awk '/^## Phase 3 — IMPLEMENT/{f=1;next} f&&/^## Phase 4/{exit} f' "$f")"
  phase4="$(awk '/^## Phase 4 — VERIFY/{f=1;next} f&&/^## Phase 5/{exit} f' "$f")"
  phase5="$(awk '/^## Phase 5 — SHIP/{f=1;next} f&&/^## Failure/{exit} f' "$f")"

  # --- AC10: no routing engine, no dangling lane -----------------------------
  # The retired symbols are built at runtime, never written literally, so the
  # repo-wide sweep in test-doc-conventions.sh needs no allowlist entry for this
  # file. Per tasks/solutions/patterns/construct-retired-paths-at-runtime-to-keep-
  # literal-reference-sweeps-strict.md: an allowlist rots, because every future
  # exception lands in it until the sweep decays into documentation.
  engine="rou""te_issue"
  for phase in "3:$phase3" "4:$phase4" "5:$phase5"; do
    n="${phase%%:*}"; body="${phase#*:}"
    assert_not_contains "$body" "materialize" \
      "AC10: $tree Phase $n names no routing engine"
    assert_not_contains "$body" "materialized lane" \
      "AC10: $tree Phase $n references no materialized lane"
    assert_not_contains "$body" "$engine" \
      "AC10: $tree Phase $n calls no deleted routing script"
  done

  # --- AC10: Phase 4 names its reviewer set DIRECTLY -------------------------
  assert_contains "$phase4" "code-reviewer" \
    "AC10: $tree Phase 4 names code-reviewer directly"
  assert_contains "$phase4" "critic" \
    "AC10: $tree Phase 4 names critic directly"
  assert_contains "$phase4" "/quality-gate" \
    "AC10: $tree Phase 4 still runs the quality gate"

  # --- AC10: Phase 4 carries all SEVEN Review Dispatch Contract items --------
  # A dispatched reviewer knows only what its prompt carries. Items 2-5 must
  # distinguish EMPTY from ABSENT, or the reviewer assumes "nobody told me" and
  # re-flags everything -- the noise the contract exists to remove.
  assert_contains "$phase4" "Review Dispatch Contract" \
    "Contract item 0: $tree Phase 4 cites the contract by name"
  assert_contains "$phase4" "diff" \
    "Contract item 1: $tree Phase 4 passes the session diff"
  assert_contains "$phase4" "acceptance criteri" \
    "Contract item 2: $tree Phase 4 passes each spec's AC list"
  assert_contains "$phase4" "no spec —" \
    "Contract item 2: $tree Phase 4 passes the empty form rather than omitting it"
  assert_contains "$phase4" "tasks/todo.md" \
    "Contract item 3: $tree Phase 4 passes the completed task rows"
  assert_contains "$phase4" "[AMBIGUITY]" \
    "Contract item 4: $tree Phase 4 passes the ambiguity lines"
  assert_contains "$phase4" "deferrals: none" \
    "Contract item 4/5: $tree Phase 4 passes the empty form for deferrals"
  assert_contains "$phase4" "TODO(shortcut)" \
    "Contract item 5: $tree Phase 4 passes the shortcut markers"
  assert_contains "$phase4" "introduced" \
    "Contract item 6: $tree Phase 4 bounds review to issues this run introduced"
  assert_contains "$phase4" "evidence" \
    "Contract item 7: $tree Phase 4 states the output format's evidence gate"
  assert_contains "$phase4" "confidence" \
    "Contract item 7: $tree Phase 4 states the four-axis finding format"

  # Ceiling tier: an override here caps the highest-stakes review for exactly the
  # users who chose a stronger session model.
  assert_contains "$phase4" "ceiling" \
    "AC10: $tree Phase 4 dispatches its reviewers at ceiling tier"

  # --- AC10: still one PR per run --------------------------------------------
  assert_contains "$phase5" "/wrap-up-session" \
    "AC10: $tree Phase 5 still ships through /wrap-up-session"
  assert_file_contains "$f" "ONE RUN → ONE PR" \
    "AC10: $tree/auto-improve still ships exactly one PR per run"
  assert_contains "$phase5" "exactly once" \
    "AC10: $tree Phase 5 runs wrap-up exactly once, not once per phase"

  # --- Phase 3 still implements, and still through /build --------------------
  assert_contains "$phase3" "/build" \
    "AC10: $tree Phase 3 implements through /build"
  assert_contains "$phase3" "TDD" \
    "AC10: $tree Phase 3 keeps its TDD discipline"

  # --- the gate ledger replaces what the lane rows used to guarantee ---------
  assert_contains "$phase5" "skip:" \
    "AC10: $tree Phase 5 carries skipped gates into the PR body with a reason"
done

assert_files_identical \
  ".agents/skills/auto-improve/SKILL.md" ".claude/skills/auto-improve/SKILL.md" \
  "Parity: auto-improve is byte-identical across trees"

# Exactly one site dispatches the four passes. Phase 4 names them; Phase 5 hands
# them to wrap-up rather than paying for a second identical round.
for tree in .agents .claude; do
  body="$(cat "$REPO/$tree/skills/auto-improve/SKILL.md")"
  assert_contains "$body" "Phase 4 already owns this run's review" \
    "AC10: $tree Phase 5 names which site owns reviewer dispatch"
  assert_contains "$body" "do not re-dispatch the four passes" \
    "AC10: $tree Phase 5 forbids the second identical dispatch"
  assert_contains "$body" "Independence Accounting" \
    "AC10: $tree says why a repeat round is not corroboration"
done

finish
