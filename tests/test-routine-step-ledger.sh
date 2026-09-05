#!/bin/bash
# tests/test-routine-step-ledger.sh — the gate ledger survives as a convention (AC9).
#
# specs/category-routines.md deletes 923 LOC of routing policy but deliberately
# KEEPS one thing the deleted design produced: materialized step rows.
#
# Pipeline #93 shipped green with /quality-gate and the pre-push reviewers never
# having run — "not by decision, by omission". Human PR review is a real backstop
# for bad code and no backstop at all for an ABSENT gate, because an absent gate
# leaves nothing in the diff a human reads. What fixed it was not the radius
# tripwire; it was a row on disk that had to carry `skip: <reason>`.
#
# So this test pins the two sinks. A ledger written to one of them is a ledger
# with a blind spot: tasks/todo.md is where the running session sees it, the PR
# body is where the reviewer does, and the omission that caused #93 is invisible
# in exactly the second one.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CONTRACT=".agents/skills/wrap-up-session/references/routines.md"

for tree in .agents .claude; do
  skill="$tree/skills/wrap-up-session/SKILL.md"

  # --- sink 1: tasks/todo.md -------------------------------------------------
  step2="$(awk '/^## Step 2 — Update Task Register/{f=1;next} f&&/^## Step 3/{exit} f' "$skill")"
  assert_contains "$step2" "step list" \
    "AC9: $tree Step 2 writes the routine's step list into tasks/todo.md"
  assert_contains "$step2" "skip:" \
    "AC9: $tree Step 2 retains a skipped row carrying its reason"

  # --- sink 2: the PR body ---------------------------------------------------
  pr="$(awk '/^### The Pull Request/{f=1;next} f&&/^### Push Failure/{exit} f' "$skill")"
  assert_contains "$pr" "step list" \
    "AC9: $tree the PR body carries the executed step list"
  assert_contains "$pr" "skip: <reason>" \
    "AC9: $tree the PR body retains skipped rows with reasons"

  # --- the rule that makes the ledger worth anything -------------------------
  assert_prose_contains "$skill" "Silent omission" \
    "AC9: $tree names silent omission as the thing that is never allowed"
  assert_prose_contains "$skill" "retained" \
    "AC9: $tree states a skipped row is retained rather than deleted"

  # A row that is merely deleted when its step does not run is worse than no
  # ledger: it reads as a routine that never had that gate.
  assert_prose_contains "$skill" "never deleted" \
    "AC9: $tree forbids deleting a skipped row"

  # --- the ledger is visible in the report the session ends on ---------------
  done_report="$(awk '/^## Done/{f=1} f&&/^## Claude Code Enhancements/{exit} f' "$skill")"
  assert_contains "$done_report" "Routine:" \
    "AC9: $tree the Done report carries a Routine line"
  assert_contains "$done_report" "skipped" \
    "AC9: $tree the Done report names the skipped-step count"
done

# --- the contract is the other half of the convention ------------------------
assert_file_matches "$CONTRACT" '^## Step ledger' \
  "AC9: the contract has a Step ledger section the skill can cite"
assert_prose_contains "$CONTRACT" "keeps its row" \
  "AC9: the contract states a step that could not run keeps its row"
assert_prose_contains "$CONTRACT" '`tasks/todo.md` and into the PR body' \
  "AC9: the contract names both sinks together, so neither can be dropped alone"

# --- the two artifacts agree on the marker -----------------------------------
# One literal token, so a routine emits it and a reviewer greps it. Two spellings
# would make the ledger unsearchable, which is the same failure as not writing it.
for f in "$CONTRACT" ".agents/skills/wrap-up-session/SKILL.md"; do
  assert_file_contains "$f" 'skip: <reason>' \
    "AC9: $f uses the single literal marker skip: <reason>"
done

assert_files_identical \
  ".agents/skills/wrap-up-session/references/routines.md" \
  ".claude/skills/wrap-up-session/references/routines.md" \
  "Parity: the contract is byte-identical across trees"

finish
