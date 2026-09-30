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

for tree in .agents; do
  f="$tree/skills/wrap-up-session/SKILL.md"
  # Routine-only rules live in the contract's wrap-up section.
  r="$tree/skills/wrap-up-session/references/routines.md"
  ca="$tree/skills/wrap-up-session/references/closure-actions.md"
  assert_file_matches "$r" '^## Wrap-up on a routine branch' \
    "AC6: $tree routines.md carries the routine-only wrap-up section"

  # --- AC7: exactly one place describes PR creation --------------------------
  # `gh pr create` is the executable proof. Prose may point AT the procedure from
  # anywhere; only one place may BE it.
  creates="$(grep -c 'gh pr create' "$f" || true)"
  assert_eq "1" "$creates" \
    "AC7: $tree/wrap-up-session names \`gh pr create\` exactly once"
  assert_eq "0" "$(grep -c 'gh pr create' "$ca" || true)" \
    "AC7: $tree closure-actions.md points at the procedure instead of restating it"

  assert_file_matches "$f" '^### The Pull Request' \
    "AC7: $tree/wrap-up-session has one canonical PR section"

  # --- AC7: both Step 7 and Step 7.5 reach that one place --------------------
  step7="$(awk '/^### Commit and push/{f=1;next} f&&/^##/{exit} f' "$f")"
  step75="$(awk '/^### Worktree integration/{f=1;next} f&&/^##/{exit} f' "$f")"

  assert_contains "$step7" "The Pull Request" \
    "AC7: $tree Step 7 reaches the canonical PR section"
  assert_contains "$step75" "The Pull Request" \
    "AC7: $tree Step 7.5 reaches the canonical PR section"
  assert_not_contains "$step75" "gh pr create" \
    "AC7: $tree Step 7.5 points at the procedure instead of restating it"

  # --- AC6: --draft iff the routine is plan ----------------------------------
  assert_prose_contains "$r" "routine_branch.py" \
    "AC6: $tree/wrap-up-session reads the routine from the branch with the shared parser"
  assert_prose_contains "$f" "--draft" \
    "AC6: $tree/wrap-up-session names the draft flag"
  assert_prose_contains "$r" "when and only when the routine is \`plan\`" \
    "AC6: $tree states --draft is passed when AND ONLY WHEN the routine is plan"

  # --- AC6: issue linkage in the body, closure on merge ----------------------
  assert_prose_contains "$r" "Closes #N" \
    "AC6: $tree states the body carries Closes #N"
  assert_prose_contains "$r" "Refs #N" \
    "AC6: $tree states plan's body carries Refs #N instead"

  # --- AC6: a multi-issue list must repeat the keyword per issue -------------
  # GitHub binds a closing keyword to the ONE reference that immediately
  # follows it (issue #123, verified via PR #121's closingIssuesReferences).
  # `Closes #A, #B` silently links only #A; the working form repeats the
  # keyword: `Closes #A, closes #B`.
  assert_prose_contains "$ca" "Closes #A, closes #B" \
    "#123: $tree states the working multi-issue form repeats the keyword per issue"
  assert_prose_contains "$ca" "links only the first" \
    "#123: $tree names the failing multi-issue form and what it silently drops"

  # Both PR paths must run the check on the body they are about to trust: the
  # create path on its draft, and the re-sync path on the fetched body even when
  # nothing else looks stale -- an already-open PR whose only defect is the
  # linkage otherwise takes the "already accurate" path and is never checked.
  sync_section="$(awk '/^## PR re-sync/{f=1;next} f&&/^## /{exit} f' "$ca")"
  create_path="$(printf '%s\n' "$sync_section" | awk '/^\*\*No PR for this branch\*\*/{f=1} f&&/^\*\*A PR already exists\*\*/{exit} f')"
  resync_path="$(printf '%s\n' "$sync_section" | awk '/^\*\*A PR already exists\*\*/{f=1} f&&/^\*\*Correct, do not erase\.\*\*/{exit} f')"
  assert_contains "$create_path" "pr_linkage.py" \
    "#123: $tree runs the linkage check on the draft before gh pr create"
  assert_contains "$resync_path" "pr_linkage.py" \
    "#123: $tree runs the linkage check on an already-open PR's body"
  assert_contains "$resync_path" "whether or not anything else looks stale" \
    "#123: $tree runs the re-sync check unconditionally, not only on a write"
  assert_prose_contains "$f" "linkage repaired" \
    "#123: $tree reports a repaired linkage on the Done report's PR line"

  # Closure happens on merge. A `gh issue close` here would break the provider
  # coupling guard with it.
  assert_file_not_matches "$f" "gh issue" \
    "AC6: $tree/wrap-up-session never closes an issue itself"
  assert_file_not_matches "$r" "gh issue" \
    "AC6: $tree routines.md never closes an issue itself"

  # --- AC7: a branch outside routine/ keeps today's behavior -----------------
  assert_prose_contains "$r" "outside the \`routine/\` namespace" \
    "AC7: $tree names the non-routine case explicitly"
  assert_prose_contains "$r" "exactly as it does today" \
    "AC7: $tree states a non-routine branch keeps today's behavior"

  # --- the bad-link edge case: report loudly, still open the PR ---------------
  # A routine branch whose issue is missing must not discard the session's work.
  assert_prose_contains "$r" "open the PR anyway" \
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
  assert_file_matches "$f" '^### Terminal PR assertion$' \
    "AC11: $tree/wrap-up-session has a terminal PR assertion step"

  terminal="$(awk '/^### Terminal PR assertion/{f=1;next} f&&/^##/{exit} f' "$f")"

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
  # so where the exit is written. The exits are read from the assertion's own
  # table, keyed by section name, so a new exit added there is checked without
  # editing this test -- and a table that lists nothing fails instead of passing.
  exit_sections="$(printf '%s\n' "$terminal" \
    | sed -nE 's/^\|[^|]*\|[[:space:]]*§ \*([^*]+)\*[[:space:]]*\|.*/\1/p')"
  assert_eq "6" "$(printf '%s\n' "$exit_sections" | grep -c . || true)" \
    "AC11: $tree's exits table lists exactly the six no-PR exits"
  while IFS= read -r exit_section; do
    [ -n "$exit_section" ] || continue
    section="$(awk -v want="### $exit_section" \
      '$0 == want { f = 1; next } f && /^##/ { exit } f' "$f")"
    assert_contains "$section" "Terminal PR assertion" \
      "AC11: $tree's '$exit_section' exit routes to the terminal PR assertion rather than just stopping"
  done <<< "$exit_sections"

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
  unattended="$(awk '/^### Unattended detection/{f=1;next} f&&/^##/{exit} f' "$r")"
  assert_contains "$terminal" "Unattended detection" \
    "AC11: $tree's assertion points at the unattended-detection rule"
  assert_contains "$unattended" "routine_branch.py" \
    "AC11: $tree decides 'is this a routine branch' with the parser that owns the format"

  # --- the contract document is reachable from the skill that implements it ---
  assert_file_contains "$f" "references/routines.md" \
    "AC7: $tree/wrap-up-session cites the routine contract"
done

# The other half of the scope rule: an unattended run on an ORDINARY branch is
# invisible to the parser, so the caller has to say so. A skill that invokes
# wrap-up unattended and never declares it silently opts out of the assertion.
# `/sweep` is not listed: its producers run on a `routine/<name>/<stamp>-sweep`
# branch, which the parser rule above already reads as unattended.
for caller in yolo auto-push; do
  for tree in .agents; do
    c="$REPO/$tree/skills/$caller/SKILL.md"
    f="$REPO/$tree/skills/wrap-up-session/SKILL.md"
    ca="$REPO/$tree/skills/wrap-up-session/references/closure-actions.md"
    assert_file_contains "$c" "§ *Terminal PR assertion* — unattended" \
      "AC11: $tree/$caller declares its wrap-up run unattended"
    # specs/wrap-up-phases.md AC7: the override table cites wrap-up by section
    # name, and the rows for gates wrap-up no longer has are gone.
    rows="$(awk '/^\| `\/wrap-up-session` section \|/{f=1;next} f&&!/^\|/{exit} f' "$c")"
    assert_eq "5" "$(printf '%s\n' "$rows" | grep -c '^| [^-]' || true)" \
      "wrap-up phases: $tree/$caller's override table has its five section rows"
    assert_not_contains "$rows" "Step " \
      "wrap-up phases: $tree/$caller's override table cites no wrap-up step number"
    for dead in "Step 5.1" "Apply Gate" "MUST-FIX"; do
      assert_not_contains "$rows" "$dead" \
        "wrap-up phases: $tree/$caller's override table drops the dead '$dead' row"
    done
    assert_file_not_matches "$c" 'parallel passes' \
      "wrap-up phases: $tree/$caller no longer claims wrap-up runs review passes"
    # Each cited section resolves: a heading of wrap-up's SKILL.md, or of the
    # reference file the row names.
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if grep -qxF "### $name" "$f" || grep -qxF "## $name" "$ca"; then
        assert_eq "resolves" "resolves" "wrap-up phases: $tree/$caller cites § $name"
      else
        assert_eq "resolves" "no such section" "wrap-up phases: $tree/$caller cites § $name"
      fi
    done <<< "$(printf '%s\n' "$rows" | sed -nE 's/^\| [^|]*§ \*([^*]+)\*.*/\1/p')"
  done
done

# --- specs/make-it-simpler.md AC16, AC17: the simplify routine's wrap-up rules --
r=.agents/skills/wrap-up-session/references/routines.md
simplify_steps="$(awk 'index($0, "### `simplify` — steps") == 1 {f=1; next} f && /^### / {exit} f' "$r")"
assert_contains "$simplify_steps" "simplify.md" "make-it-simpler AC16: the simplify steps section points to its lane file"
assert_contains "$(printf '%s' "$simplify_steps" | tr -s '[:space:]' ' ')" "its **discovery precedes the spine**" \
  "make-it-simpler AC16: the section states the discovery that precedes the spine"
assert_file_matches "$r" '^\| `routine/simplify/<n>-<slug>` \| none \| conventional \| `Closes #N`' \
  "make-it-simpler AC16: routine/simplify/<n>-<slug> is ready and closes its issue"
assert_file_matches "$r" '^\| `routine/simplify/<YYYYMMDD>-record` \| none \|.*docs-only.*`Refs #N` per filed issue' \
  "make-it-simpler AC16: the record branch is ready, docs-only, Refs #N per filed issue"
terminal="$(awk '/^### Fix-escalation terminal/{f=1; next} f && /^### /{exit} f' "$r" | tr -s '[:space:]' ' ')"
assert_contains "$terminal" "The \`simplify\` routine's **scope stop**" \
  "make-it-simpler AC17: the Fix-escalation terminal names the simplify scope stop"
assert_contains "$terminal" "it stops before any edit, non-zero" "make-it-simpler AC17: before any edit, non-zero"
assert_contains "$terminal" "Open no PR, write no PR ledger, and do not run the terminal PR assertion" \
  "make-it-simpler AC17: no PR, no PR ledger, no terminal PR assertion"

finish
