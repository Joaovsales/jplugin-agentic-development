#!/bin/bash
# tests/test-e2e-evidence.sh — "no file, no PASS" for VISUAL acceptance criteria.
#
# WHY THIS EXISTS
#
# A VISUAL AC is about what a person sees. A log entry that says PASS for one,
# with no screenshot behind it, is a claim nobody can check after the session
# ends — the reviewer reading the PR has only the agent's word that the page
# looked right. specs/visual-e2e-evidence.md makes the PNG the evidence: the
# entry names it on a `Screenshot:` line, and e2e_evidence.py refuses an entry
# whose line or file is missing.
#
# The script is the mechanical half; the prose in /verify-evidence is what tells
# an agent to take the screenshot at all. Both are pinned here, because either
# one drifting alone turns the check into a formality: prose without the check
# is unenforced, and a check without the prose fails every honest run.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SKILL=".agents/skills/verify-evidence/SKILL.md"
SCRIPT="$REPO/.agents/skills/verify-evidence/scripts/e2e_evidence.py"

# --- 1. prose (AC 4) ---------------------------------------------------------
# The template is a fenced block full of `### AC-n` headings, so the section
# ends at the next heading outside a fence, not at the next `### `.
EVIDENCE="$(awk '/^```/{fence=!fence} /^### Evidence Format/{f=1;next} f&&!fence&&/^### /{exit} f' "$SKILL")"
assert_contains "$EVIDENCE" 'Screenshot: tasks/e2e-artifacts/<short-sha>/<AC-id>.png' \
  "prose: Evidence Format carries the Screenshot: line"
assert_contains "$EVIDENCE" "Tier: VISUAL" "prose: the Screenshot: example is a VISUAL entry"
assert_prose_contains "$SKILL" "5. Evidence is the \`tasks/e2e-log.md\` entry" \
  "prose: Iron Law 5 still names the log entry"
assert_prose_contains "$SKILL" "a VISUAL PASS without its PNG on disk is not a PASS" \
  "prose: Iron Law 5 names the PNG"
assert_prose_contains "$SKILL" "e2e_evidence.py check" "prose: the skill names the check"

# --- 2. check (AC 5) ---------------------------------------------------------
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/tasks/e2e-artifacts/abc1234"
: > "$SANDBOX/tasks/e2e-artifacts/abc1234/AC-2.png"

# write_log <body> — a log with one walkthrough entry at short-sha abc1234.
write_log() {
  printf '# E2E log\n\n## E2E Walkthrough — Fixture — 2026-09-29 abc1234\n\nBrowser: playwright-cli 0.1.22 (full-fidelity)\n\n%s\n' "$1" \
    > "$SANDBOX/tasks/e2e-log.md"
}

# run_check [args...] — runs from the sandbox root; sets OUT and RC.
run_check() {
  OUT="$(cd "$SANDBOX" && "$TEST_PYTHON" "$SCRIPT" check "$@" 2>&1)"; RC=$?
}

DOM_PASS='### AC-1: the order total is shown
Tier: DOM-FUNCTIONAL (element text)
Result: PASS'
VISUAL_OK='### AC-2: the submit button is visible
Tier: VISUAL (visibility is a rendering property)
Result: PASS
Screenshot: tasks/e2e-artifacts/abc1234/AC-2.png'

write_log "$DOM_PASS

$VISUAL_OK"
run_check
assert_eq "0" "$RC" "check: every VISUAL PASS has its PNG → exit 0"
assert_eq "" "$OUT" "check: success is silent"

write_log "### AC-3: the chart renders
Tier: VISUAL (canvas)
Result: PASS"
run_check
assert_eq "1" "$RC" "check: VISUAL PASS without a Screenshot: line → exit 1"
assert_contains "$OUT" "abc1234" "check: the missing-line failure names the entry"
assert_contains "$OUT" "AC-3" "check: the missing-line failure names the AC"
assert_contains "$OUT" "no Screenshot: line" "check: says the line is missing"

write_log "### AC-4: the dark theme applies
Tier: VISUAL (theme)
Result: PASS
Screenshot: tasks/e2e-artifacts/abc1234/AC-4.png"
run_check
assert_eq "1" "$RC" "check: VISUAL PASS whose PNG is absent → exit 1"
assert_contains "$OUT" "AC-4" "check: the missing-file failure names the AC"
assert_contains "$OUT" "tasks/e2e-artifacts/abc1234/AC-4.png" "check: names the absent file"

# DOM-FUNCTIONAL passes on text assertions, and BLOCKED was never attempted —
# neither owes a screenshot (Decision 7). Bold markup on the result, as the
# real log writes it, must not change the reading.
write_log "$DOM_PASS

### AC-5: the layout is responsive
Tier: VISUAL (responsiveness)
Result: **BLOCKED** — requires a file-capable full-fidelity browser"
run_check
assert_eq "0" "$RC" "check: DOM-FUNCTIONAL and BLOCKED entries are ignored"

write_log "### AC-6: the modal animates
Tier: VISUAL (animation)
Result: **PASS** (both states observed)"
run_check
assert_eq "1" "$RC" "check: a bold/annotated PASS is still a PASS"

# --log reads another file; a missing log is an error, not a silent pass.
mv "$SANDBOX/tasks/e2e-log.md" "$SANDBOX/other-log.md"
run_check --log other-log.md
assert_eq "1" "$RC" "check: --log reads the named file"
run_check
assert_eq "2" "$RC" "check: a missing log exits 2"
assert_contains "$OUT" "tasks/e2e-log.md" "check: names the missing log"

# --sha scopes the check to one commit's entries. The log is append-only, so
# entries written before screenshots existed must not fail every later run.
write_log "### AC-7: legacy visual entry
Tier: VISUAL (layout)
Result: PASS"
printf '\n## E2E Walkthrough — Later — 2026-09-30 def5678\n\n%s\n' "$VISUAL_OK" >> "$SANDBOX/tasks/e2e-log.md"
run_check --sha def5678
assert_eq "0" "$RC" "check: --sha ignores other commits' entries"
run_check --sha abc1234
assert_eq "1" "$RC" "check: --sha still checks its own entries"

# --- 3. gitignore (AC 12) ----------------------------------------------------
# PNGs are committed only to the e2e-evidence branch (Decision 11).
for ignore in .gitignore project-template/.gitignore; do
  assert_file_matches "$ignore" '^tasks/e2e-artifacts/$' "$ignore: ignores tasks/e2e-artifacts/"
  assert_file_matches "$ignore" '^\.playwright-cli/$' "$ignore: ignores .playwright-cli/"
done

finish
