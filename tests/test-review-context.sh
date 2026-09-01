#!/bin/bash
# tests/test-review-context.sh — reviewers must be handed intent, not only a diff.
#
# A dispatched reviewer sees whatever the orchestrator improvised. Before this
# guard, one site of four specified a payload at all, so a reviewer routinely
# reviewed a diff without the spec it implements, without the acceptance criteria
# it must satisfy, and without the list of decisions the user already made. The
# failure is silent in the worst way: the review still runs and still reports
# findings, so a re-litigated `TODO(shortcut):` is indistinguishable from a real
# defect.
#
# What can be pinned statically is the *instruction* — that each dispatch site
# names the contract, that the contract enumerates its items, and that each
# persona declares its intake. Whether a given runtime call actually carried them
# is not observable from disk, the same limit the tier floors have.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# The three skill FILES that dispatch a reviewer. They hold four sites between
# them -- wrap-up-session carries two (Step 4 and Parallel Code Review), which is
# why the second one gets its own needle below rather than riding on the file.
# auto-improve is absent by exception, not by oversight: its discovery scan surveys
# the whole repo rather than a session's work, so items 2/3/6 have no subject. The
# contract names that exception explicitly and still requires the empty markers, so
# the rule stays stated rather than silently dropped.
DISPATCH_SITE_FILES="skills/wrap-up-session/SKILL.md skills/quality-gate/SKILL.md skills/software-design-expert-review/SKILL.md skills/route/SKILL.md"

REVIEW_PERSONAS="code-reviewer critic security-reviewer software-design-expert-review"

# --- 1. The contract exists, in one place ------------------------------------
# Canonical rather than copied into each skill: #61 removed four model IDs that
# had been duplicated across three files because the copies nobody updates are
# the ones that go stale. A seven-item payload list is a bigger version of that.
assert_file_matches CLAUDE.md '^## Review Dispatch Contract' \
  "ReviewContext: CLAUDE.md has a Review Dispatch Contract section"

# Each payload item, pinned individually. A section heading alone would stay green
# with the table emptied.
assert_prose_contains CLAUDE.md 'the AC list verbatim' \
  "ReviewContext: contract requires the acceptance criteria, not just the spec path"
assert_prose_contains CLAUDE.md '[AMBIGUITY]' \
  "ReviewContext: contract requires the ambiguity lines from this run"
assert_prose_contains CLAUDE.md 'TODO(shortcut):' \
  "ReviewContext: contract requires the shortcut markers"
assert_prose_contains CLAUDE.md 'issues **introduced** by this session' \
  "ReviewContext: contract passes the scope boundary to the agent"
assert_prose_contains CLAUDE.md 'Large-Artifact Handoff' \
  "ReviewContext: contract defers to the truncate-with-pointer convention for the diff"

# --- 2. Empty must be distinguishable from absent ----------------------------
# A reviewer handed no deferral list cannot tell "nothing was deferred" from
# "nobody told me", and the safe reading of the ambiguous case is to re-flag
# everything -- which is the noise this contract removes. Same hazard class as the
# vacuous `assert_not_contains` closed in #61.
assert_prose_contains CLAUDE.md 'deferrals: none' \
  "ReviewContext: contract requires an explicit empty marker for deferrals"
assert_prose_contains CLAUDE.md 'distinguish **empty** from **absent**' \
  "ReviewContext: contract states the absent-vs-empty rule as a rule"

# --- 3. Intent is shared; conclusions are not --------------------------------
# The load-bearing half. Sharing the builder's reasoning would import the priors
# that Independence Accounting exists to keep out, and the promotion rule would
# then count an echo as a witness. The needles name the *reason*, not the slogan:
# a section that says "share intent" without saying why is one edit from being
# widened to "share everything".
assert_prose_contains CLAUDE.md '**Share intent** — spec, acceptance criteria' \
  "ReviewContext: contract says intent is shared"
assert_prose_contains CLAUDE.md 'Withhold conclusions' \
  "ReviewContext: contract says conclusions are withheld"
assert_prose_contains CLAUDE.md 'would import exactly those priors' \
  "ReviewContext: contract explains why conclusions are withheld"

# --- 4. Anchor 75 has a named dependency and a way out ------------------------
# The anchor already says correctness "turns on a caller, config, or runtime value
# outside the reviewed scope" -- and then nothing tells the reviewer to go read it.
# So findings park at 75, where the Apply Gate reports and never applies them,
# even when one grep would settle it. Two rules close that: name the dependency,
# then resolve it.
assert_prose_contains CLAUDE.md 'must **name** the specific caller, config key, or runtime value' \
  "ReviewContext: a finding at 75 must name what it depends on"
assert_prose_contains CLAUDE.md 'without naming one is a `50`' \
  "ReviewContext: an unnamed dependency demotes to 50"
assert_prose_contains CLAUDE.md 'promote to `100` with a second `evidence` line' \
  "ReviewContext: the verification path resolves a 75 rather than parking it"
assert_prose_contains CLAUDE.md 'must say what stopped the check' \
  "ReviewContext: a finding held at 75 states why it could not be verified"

# --- 5. Verification-promotion is not agreement-promotion ---------------------
# Conflating them breaks the gate in whichever direction the reader guesses:
# either Independence Accounting forbids a legitimate one-context verification, or
# "I verified it" licenses promoting on agreement. Both were reachable from the
# text before this rule existed, so the distinction is pinned, not implied.
assert_prose_contains CLAUDE.md 'agreement-promotion, and *Independence Accounting*
does not constrain it' \
  "ReviewContext: CLAUDE.md separates the two promotion mechanisms"
assert_prose_contains CLAUDE.md 'promotes on *evidence*' \
  "ReviewContext: verification promotes on evidence, so one context suffices"
assert_prose_contains CLAUDE.md 'promotes on *witnesses*' \
  "ReviewContext: agreement promotes on witnesses, which is what needs independence"

# --- 6. Every dispatch site cites the contract and its empty markers ----------
# Pinned per tree, not once: the `.agents` -> `.claude` copy is a plain `cp`, and
# a site updated canonically but not copied ships the old prompt to Claude Code
# while the test reads the fixed one. Parity tests catch a diff, not a stale pair
# that was never re-copied -- so both are named here.
for tree in .agents .claude; do
  for site in $DISPATCH_SITE_FILES; do
    f="$tree/$site"
    # Prose, not literal: the citation is a sentence and wraps. A wrap-fragile
    # needle here would fail on reflow and teach the next author to delete it.
    assert_prose_contains "$f" 'CLAUDE.md` § *Review Dispatch Contract*' \
      "ReviewContext: $f cites the Review Dispatch Contract"
    assert_file_contains "$f" 'deferrals: none' \
      "ReviewContext: $f passes an explicit empty marker for deferrals"
    assert_file_contains "$f" 'no spec —' \
      "ReviewContext: $f passes an explicit marker when there is no spec"
  done
  # wrap-up-session holds two of the four sites, and a per-file needle is satisfied
  # by either. Pin the second one -- the parallel-dispatch path -- separately: it is
  # the only path the skill says "licenses confidence promotion", so a payload that
  # silently stops reaching it degrades exactly the run that promotes on it.
  assert_prose_contains "$tree/skills/wrap-up-session/SKILL.md" \
    'carries the *Review Payload* assembled in Step 4' \
    "ReviewContext: $tree wrap-up parallel dispatch carries the payload too"
  # Counted, not merely present. The AC is "all four sites cite the contract", and
  # a per-file needle is satisfied by the Step 4 citation alone -- probed: dropping
  # the citation from the parallel-dispatch site left the suite fully green. Two
  # sites in this file, so two citations.
  cites="$(tr -s '[:space:]' ' ' < "$tree/skills/wrap-up-session/SKILL.md" \
    | grep -oF 'CLAUDE.md` § *Review Dispatch Contract*' | wc -l | tr -d ' ')"
  [ "$cites" -ge 2 ] && cites_ok=yes || cites_ok="no (found $cites)"
  assert_eq "yes" "$cites_ok" \
    "ReviewContext: $tree wrap-up cites the contract at both of its dispatch sites"
done

# --- 7. Each reviewer persona declares its intake ----------------------------
# Anthropic's multi-agent guidance requires four things of a sub-agent prompt:
# objective, output format, tools/sources, boundaries. Every persona already
# carries the first two. Before this section none carried the last two, so each
# agent improvised its own scope -- and a reviewer that decides its own scope is
# the one that reports pre-existing patterns as this session's defects.
for tree in .agents/agents .claude/agents; do
  for p in $REVIEW_PERSONAS; do
    f="$tree/$p.md"
    assert_file_matches "$f" '^## Context Intake' \
      "ReviewContext: $f declares a Context Intake section"
    # Anchored at line start. `assert_file_contains` is a substring match and
    # `**Never out of scope**:` contains `Out of scope`, so the unanchored needle
    # stayed green with the entire boundary paragraph deleted from the one persona
    # that also carries a carve-out. Found by probing, not by reading.
    assert_file_matches "$f" '^\*\*Out of scope\*\*' \
      "ReviewContext: $f states its boundary"
    assert_file_matches "$f" '^\*\*Given to you\*\*' \
      "ReviewContext: $f states what it will be handed"
    assert_file_contains "$f" 'Fetch yourself' \
      "ReviewContext: $f says what to fetch itself"
    assert_prose_contains "$f" 'CLAUDE.md` § *Review Dispatch Contract*' \
      "ReviewContext: $f points at the contract it is the receiving end of"
    assert_file_contains "$f" 'deferrals: none' \
      "ReviewContext: $f knows an empty deferral list from a missing one"
  done
done

# The Ceiling-in-a-table-cell rule lives in tests/test-model-tiers.sh section 8b,
# not here. An earlier draft asserted it in both files and called that redundancy;
# probing showed this copy was strictly weaker (it required exact single spacing,
# so `|Design review | sonnet |` walked past it while 8b caught it). Two guards
# where one is weaker is not two witnesses -- it is one witness and a decoy that
# makes the pair look stronger than it is.

finish
