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
  # coupling guard with it.
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

  # --- AC11: an unattended run that produces no PR is never SILENT -----------
  # R4 as written ("every session ends in a PR") is false today and this does not
  # make it true: wrap-up has six documented no-PR exits — no changes, tests
  # failing after 2 fix attempts, unresolved MUST-FIX, the push gate, an
  # unwritable local record, and a `blocked` maintainer outcome. Each is a
  # legitimate outcome and none is removed here.
  #
  # What changes is the FAILURE MODE the spec actually names: a 03:00 run that
  # ends having produced nothing, and says so to nobody. So the assertion is
  # about loudness and exit code, not about forcing a PR into existence.
  assert_file_matches "$f" '^## Step 8.5' \
    "AC11: $tree/wrap-up-session has a terminal PR assertion step"

  terminal="$(awk '/^## Step 8.5/{f=1;next} f&&/^## /{exit} f' "$f")"

  assert_contains "$terminal" "gh pr view" \
    "AC11: $tree checks for the PR with gh pr view on the branch"
  # The exact ACTION, not the bare phrase: "non-zero" also appears in the
  # closing paragraph, so a needle that loose stays green with the action row
  # gutted — which is the one line that makes the run fail.
  assert_contains "$terminal" "and **exit non-zero**" \
    "AC11: $tree's no-PR row exits non-zero rather than merely reporting"
  assert_prose_contains "$f" "does not make every session end in a pull request" \
    "AC11: $tree does NOT claim R4 is now true — the six no-PR exits survive"
  assert_contains "$terminal" "interactive" \
    "AC11: $tree scopes the assertion — an interactive run has a human watching"

  # The assertion is worthless if it only runs on the happy path: the exits it
  # exists to make loud are exactly the ones that stop wrap-up early.
  assert_prose_contains "$f" "runs even when an earlier gate stopped the run" \
    "AC11: $tree runs the assertion on the early-exit paths too"

  # ...and the claim above is prose. A reader following this skill top to bottom
  # hits "STOP" and stops, so the step is reachable only if each early exit says
  # so where the exit is written. The exits are read from Step 8.5's own table,
  # so a new exit added there is checked without editing this test.
  for exit_step in $(printf '%s\n' "$terminal" \
      | sed -nE 's/^\|[^|]*\|[[:space:]]*Step ([0-9.]+)[[:space:]]*\|.*/\1/p' \
      | sort -u); do
    section="$(awk -v want="## Step $exit_step " \
      'index($0, want) == 1 { f = 1; next } f && /^## / { exit } f' "$f")"
    assert_contains "$section" "Step 8.5" \
      "AC11: $tree's Step $exit_step exit routes to Step 8.5 rather than just stopping"
  done

  # Silence on success. A terminal check that prints on every green run trains
  # readers to ignore it, which is how the loud case stops being loud.
  assert_prose_contains "$f" "says nothing when the pull request exists" \
    "AC11: $tree keeps the success path silent (failure-only reporting)"

  # `gh pr view` exits non-zero for "no such PR" AND for "could not ask". Reading
  # the second as the first reports a missing PR that may well exist — a false
  # alarm on every night gh is unhappy, which is how a nightly check gets muted.
  assert_contains "$terminal" "could not ask" \
    "AC11: $tree tells a failed gh apart from an absent pull request"

  # The scope test is the parser, not the prefix: `routine/plna/90-x` matches
  # `routine/` and belongs to no routine.
  assert_contains "$terminal" "routine_branch.py" \
    "AC11: $tree decides 'is this a routine branch' with the parser that owns the format"

  # --- the contract document is reachable from the skill that implements it ---
  assert_file_contains "$f" "references/routines.md" \
    "AC7: $tree/wrap-up-session cites the routine contract"
done

# The other half of the scope rule: an unattended run on an ORDINARY branch is
# invisible to the parser, so the caller has to say so. A skill that invokes
# wrap-up unattended and never declares it silently opts out of the assertion.
for caller in yolo auto-improve auto-push; do
  for tree in .agents .claude; do
    assert_file_contains "$REPO/$tree/skills/$caller/SKILL.md" "Step 8.5" \
      "AC11: $tree/$caller declares its wrap-up run unattended"
  done
done

assert_files_identical \
  ".agents/skills/wrap-up-session/SKILL.md" \
  ".claude/skills/wrap-up-session/SKILL.md" \
  "Parity: the wrap-up skill is byte-identical across trees"

finish
