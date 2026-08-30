#!/bin/bash
# tests/test-e2e-classifier.sh — the e2e browser tier contract in /verify.
#
# WHY THIS EXISTS
#
# `/verify --scope e2e` may now resolve to lightpanda, which executes JavaScript
# over a real network but never lays out or paints the result. A page with
# completely broken layout still exposes a correct DOM, so "the button exists and
# says Submit" passes on a page where the button is invisible, off-screen, or
# behind a modal.
#
# The protection is a classifier that routes each acceptance criterion to a tier
# and REFUSES to run visual criteria on a browser that cannot see. Its load-
# bearing property is the direction it fails in: uncertain means VISUAL, never
# DOM-functional. Reverse that one sentence and the whole gate inverts from
# "refuse to guess" to "guess and pass" — silently, with every test still green,
# because nothing else in the suite reads it.
#
# So this test pins the sentence verbatim rather than paraphrasing it, and pins
# it in BOTH skill trees. A rule that holds in the canonical copy and not in the
# one Claude Code actually loads protects nobody.
#
# SCOPE BOUNDARY — this is a prose contract, so these are static assertions:
# they prove the rule is WRITTEN, not that an agent OBEYS it. Behavioural
# evidence for the fail-closed rule lives in tasks/e2e-log.md per the spec's
# AC-4. Neither check substitutes for the other.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CANONICAL=".agents/skills/verify/SKILL.md"
COMPAT=".claude/skills/verify/SKILL.md"

for f in "$CANONICAL" "$COMPAT"; do

  # --- 0. Project-local verification skill resolution ----------------------
  assert_prose_contains "$f" 'exactly one project-local `verify-<app>` skill' \
    "$f: exactly one local verification skill is selected"
  assert_prose_contains "$f" 'more than one project-local `verify-<app>` skill' \
    "$f: ambiguous local verification skills STOP for selection"
  assert_prose_contains "$f" "do not choose one" \
    "$f: ambiguity never guesses a target"
  assert_prose_contains "$f" 'no project-local `verify-<app>` skill' \
    "$f: absence preserves the generic backend fallback"
  assert_prose_contains "$f" 'recommend `/create-verification-skill`' \
    "$f: absent local skill yields an actionable recommendation"
  assert_prose_contains "$f" "never create or launch it automatically" \
    "$f: fallback never performs implicit generation or launch"
  assert_prose_contains "$f" "declared surface and capability ceiling" \
    "$f: local recipes declare their usable verification ceiling"
  assert_prose_contains "$f" "must satisfy the classified AC" \
    "$f: local recipes cannot bypass the AC classifier"

  # --- 1. Backend resolution order -------------------------------------------
  # Ordered, first match wins. A full-fidelity backend must outrank lightpanda,
  # or the cheap tier would win on machines that have a real browser available.
  assert_prose_contains "$f" "Chrome MCP" \
    "$f: resolution order names Chrome MCP"
  assert_prose_contains "$f" "Playwright MCP" \
    "$f: resolution order names Playwright MCP"
  assert_prose_contains "$f" "Lightpanda" \
    "$f: resolution order names Lightpanda"

  # Absence of every backend must still STOP — the pre-existing behaviour this
  # change must not weaken.
  assert_file_contains "$f" "MCP browser unavailable" \
    "$f: retains the no-backend STOP rule"

  # --- 2. Both tiers are defined ---------------------------------------------
  assert_file_contains "$f" "DOM-FUNCTIONAL" "$f: defines the DOM-FUNCTIONAL tier"
  assert_file_contains "$f" "VISUAL"         "$f: defines the VISUAL tier"

  # --- 3. THE fail-closed sentence, verbatim ---------------------------------
  # Pinned literally. A paraphrase here would let a reworded skill drift into
  # permissive behaviour while this test kept passing.
  assert_prose_contains "$f" "when classification is uncertain, the AC is VISUAL" \
    "$f: states the fail-closed rule VERBATIM"

  # --- 4. The BLOCKED outcome ------------------------------------------------
  # A visual AC on a DOM-only backend is neither PASS nor a step failure: it was
  # never attempted. Without a distinct outcome it would be recorded as one or
  # the other, and PASS is the dangerous direction.
  assert_file_contains "$f" "BLOCKED" \
    "$f: defines the BLOCKED outcome for unrunnable ACs"
  assert_prose_contains "$f" "never" \
    "$f: BLOCKED is stated as never a PASS"

  # A run containing any BLOCKED AC must not report overall success, or partial
  # coverage would read as full coverage to /build Phase 4.
  assert_prose_contains "$f" "non-success" \
    "$f: a BLOCKED AC makes the run report non-success"

  # --- 5. Iron Law 1 cross-reference -----------------------------------------
  # Iron Law 1 forbids "headless emulation bypassing the network". Lightpanda
  # loads over libcurl and does not bypass it, but a reader hitting that line
  # will infer a contradiction unless the skill says so at that point.
  assert_prose_contains "$f" "libcurl" \
    "$f: explains why lightpanda satisfies Iron Law 1"

  # --- 6. Evidence records which tier ran (Task 4 / AC-6) --------------------
  # Without this, a reader six months on cannot tell whether a PASS was seen or
  # inferred.
  assert_file_contains "$f" "Browser:" \
    "$f: e2e-log template records the backend"
  assert_prose_contains "$f" "DOM-tier" \
    "$f: e2e-log template records the fidelity tier"

  # EVERY logged AC carries its tier, not only the blocked ones. A PASS whose
  # tier is unrecorded is unreadable after the fact: the reader cannot tell
  # whether the criterion was deliberately classified DOM-FUNCTIONAL or never
  # classified at all — precisely the judgement the log exists to preserve.
  assert_file_contains "$f" "Tier: DOM-FUNCTIONAL" \
    "$f: the PASS example records its tier too"
  assert_file_contains "$f" "Tier: VISUAL" \
    "$f: the BLOCKED example records its tier"

done

# --- 7. Both trees agree ------------------------------------------------------
# The canonical/compat split is only safe while the two are identical; a rule
# present in one and not the other is worse than absent from both, because it
# reads as covered.
assert_files_identical "$CANONICAL" "$COMPAT" \
  "verify/SKILL.md is byte-identical across both trees"

finish
