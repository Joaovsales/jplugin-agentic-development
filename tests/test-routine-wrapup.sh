#!/bin/bash
# tests/test-routine-wrapup.sh — one PR procedure, reached from both steps (AC6, AC7).
#
# /wrap-up-session opened a pull request in two places: Step 7's "Commit & Push"
# and Step 7.5's worktree integration. Two descriptions of one irreversible,
# outward-facing action is how they drift, and the routine contract now adds a
# conditional to it — a `plan` routine's PR must be a DRAFT, and every routine's
# body must carry the issue linkage that closes the issue on merge.
#
# A conditional duplicated across two sites is a conditional that will eventually
# be true in one and false in the other, and the failure is invisible: a plan
# proposal marked ready to merge looks exactly like a plan proposal.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

for tree in .agents .claude; do
  f="$tree/skills/wrap-up-session/SKILL.md"

  # --- AC7: exactly one place describes PR creation --------------------------
  # `gh pr create` is the executable proof. Prose may point AT the procedure from
  # anywhere; only one place may BE it.
  creates="$(grep -c 'gh pr create' "$f" || true)"
  assert_eq "1" "$creates" \
    "AC7: $tree/wrap-up-session names \`gh pr create\` exactly once"

  assert_file_matches "$f" '^### The Pull Request' \
    "AC7: $tree/wrap-up-session has one canonical PR section"

  # --- AC7: both Step 7 and Step 7.5 reach that one place --------------------
  step7="$(awk '/^## Step 7 — Commit & Push/{f=1;next} f&&/^## Step 7.5/{exit} f' "$f")"
  step75="$(awk '/^## Step 7.5/{f=1;next} f&&/^## Step 8/{exit} f' "$f")"

  assert_contains "$step7" "The Pull Request" \
    "AC7: $tree Step 7 reaches the canonical PR section"
  assert_contains "$step75" "The Pull Request" \
    "AC7: $tree Step 7.5 reaches the canonical PR section"
  assert_not_contains "$step75" "gh pr create" \
    "AC7: $tree Step 7.5 points at the procedure instead of restating it"

  # --- AC6: --draft iff the routine is plan ----------------------------------
  assert_prose_contains "$f" "routine_branch.py" \
    "AC6: $tree/wrap-up-session reads the routine from the branch with the shared parser"
  assert_prose_contains "$f" "--draft" \
    "AC6: $tree/wrap-up-session names the draft flag"
  assert_prose_contains "$f" "when and only when the routine is \`plan\`" \
    "AC6: $tree states --draft is passed when AND ONLY WHEN the routine is plan"

  # --- AC6: issue linkage in the body, closure on merge ----------------------
  assert_prose_contains "$f" "Closes #N" \
    "AC6: $tree states the body carries Closes #N"
  assert_prose_contains "$f" "Refs #N" \
    "AC6: $tree states plan's body carries Refs #N instead"

  # Closure happens on merge. A `gh issue close` here would break the provider
  # coupling guard and take Jira with it.
  assert_file_not_matches "$f" "gh issue" \
    "AC6: $tree/wrap-up-session never closes an issue itself"

  # --- AC7: a branch outside routine/ keeps today's behavior -----------------
  assert_prose_contains "$f" "outside the \`routine/\` namespace" \
    "AC7: $tree names the non-routine case explicitly"
  assert_prose_contains "$f" "exactly as it does today" \
    "AC7: $tree states a non-routine branch keeps today's behavior"

  # --- the bad-link edge case: report loudly, still open the PR ---------------
  # A routine branch whose issue is missing must not discard the session's work.
  assert_prose_contains "$f" "open the PR anyway" \
    "Edge: $tree opens the PR even when the issue link is bad"

  # --- the contract document is reachable from the skill that implements it ---
  assert_file_contains "$f" "references/routines.md" \
    "AC7: $tree/wrap-up-session cites the routine contract"
done

assert_files_identical \
  ".agents/skills/wrap-up-session/SKILL.md" \
  ".claude/skills/wrap-up-session/SKILL.md" \
  "Parity: the wrap-up skill is byte-identical across trees"

finish
