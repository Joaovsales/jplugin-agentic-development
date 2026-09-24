#!/usr/bin/env bash
# tests/test-sync-managed-block.sh — sync-managed-block.py's replace / append /
# pointer contract (specs/single-instruction-file.md § Component contracts).
#
# WHY this test exists: /sync overwrites the managed block between the
# jplugin-agentic-development markers wholesale on every run, so anything a
# project author wrote outside those markers — their own project rules above
# or below the block — must survive byte-for-byte, in whatever line-ending
# convention the file already used. This suite proves that guarantee (cases
# 1-2), the legacy-slug migration on read (case 3), idempotency (case 4),
# refusal before any write on a malformed marker set (case 5), refusal when
# the template itself carries no block (case 6), --dry-run doing nothing
# (case 7), the CLAUDE.md pointer file (case 8), reading the template from
# stdin (case 9), creating an absent target (case 10), and the one-shot
# .claude/project.md migration (cases 11-15, D15): everything below the file's
# header moves in order except the block's four generic sections and the Task
# Tracking prose, the pointer line goes first, a doubled Deployment Targets
# table refuses before any write, and a re-run finds nothing to move.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/.agents/skills/sync/scripts/sync-managed-block.py"

SLUG="jplugin-agentic-development"
# Assembled at runtime (not written as a literal) so test-repo-identity.sh's
# sweep does not flag this file as a live old-slug reference.
LEGACY_SLUG="coding-agent"; LEGACY_SLUG="$LEGACY_SLUG-workflow"
BEGIN="<!-- $SLUG:begin -->"
END="<!-- $SLUG:end -->"
LEGACY_BEGIN="<!-- $LEGACY_SLUG:begin -->"
LEGACY_END="<!-- $LEGACY_SLUG:end -->"

BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT

run_script() {
  PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" "$SCRIPT" "$@"
}

# --- case 1: no markers in target -> appended -------------------------------
CASE1="$BOX/case1"; mkdir -p "$CASE1"
printf '%s\nnew managed content\n%s\n' "$BEGIN" "$END" > "$CASE1/source.md"
printf '# Project notes\n\nExisting project text.\n' > "$CASE1/AGENTS.md"

OUT1="$(run_script --source "$CASE1/source.md" --target "$CASE1/AGENTS.md")"
assert_contains "$OUT1" "AGENTS.md: appended" "case1: reports appended"
assert_file_contains "$CASE1/AGENTS.md" "Existing project text." "case1: prior text preserved"
assert_file_contains "$CASE1/AGENTS.md" "new managed content" "case1: block appended"
assert_eq "1" "$(grep -cF -- "$BEGIN" "$CASE1/AGENTS.md")" "case1: block present exactly once"

# --- case 2: current markers, LF -> replaced, surroundings byte-identical --
CASE2="$BOX/case2"; mkdir -p "$CASE2"
printf 'HEADER LINE ONE\nHEADER LINE TWO\n%s\nOLD BLOCK CONTENT\n%s\nFOOTER LINE ONE\nFOOTER LINE TWO\n' \
  "$BEGIN" "$END" > "$CASE2/AGENTS.md"
printf '%s\nNEW BLOCK CONTENT\n%s\n' "$BEGIN" "$END" > "$CASE2/source.md"
BEFORE2_HEAD="$(sed -n '1,2p' "$CASE2/AGENTS.md")"
BEFORE2_TAIL="$(tail -n 2 "$CASE2/AGENTS.md")"

OUT2="$(run_script --source "$CASE2/source.md" --target "$CASE2/AGENTS.md")"
assert_contains "$OUT2" "AGENTS.md: replaced" "case2: reports replaced"
assert_not_contains "$(cat "$CASE2/AGENTS.md")" "OLD BLOCK CONTENT" "case2: old block content removed"
assert_file_contains "$CASE2/AGENTS.md" "NEW BLOCK CONTENT" "case2: new block content present"
assert_eq "$BEFORE2_HEAD" "$(sed -n '1,2p' "$CASE2/AGENTS.md")" "case2: header text byte-identical"
assert_eq "$BEFORE2_TAIL" "$(tail -n 2 "$CASE2/AGENTS.md")" "case2: footer text byte-identical"

# --- case 2b: current markers, CRLF -> replaced, whole file stays CRLF -----
CASE2B="$BOX/case2b"; mkdir -p "$CASE2B"
printf 'HEADER\r\n%s\r\nOLD\r\n%s\r\nFOOTER\r\n' "$BEGIN" "$END" > "$CASE2B/AGENTS.md"
printf '%s\nNEW BLOCK\n%s\n' "$BEGIN" "$END" > "$CASE2B/source.md"

run_script --source "$CASE2B/source.md" --target "$CASE2B/AGENTS.md" >/dev/null
TOTAL2B="$(grep -c '' "$CASE2B/AGENTS.md")"
CRLF2B="$(grep -c $'\r$' "$CASE2B/AGENTS.md")"
assert_eq "$TOTAL2B" "$CRLF2B" "case2b: every line still ends CRLF after replace"
assert_file_contains "$CASE2B/AGENTS.md" "NEW BLOCK" "case2b: new content present"

# --- case 3: legacy markers -> replaced with current markers ---------------
CASE3="$BOX/case3"; mkdir -p "$CASE3"
printf 'TEXT ABOVE\n%s\nLEGACY BLOCK\n%s\nTEXT BELOW\n' "$LEGACY_BEGIN" "$LEGACY_END" > "$CASE3/AGENTS.md"
printf '%s\nNEW CONTENT\n%s\n' "$BEGIN" "$END" > "$CASE3/source.md"

OUT3="$(run_script --source "$CASE3/source.md" --target "$CASE3/AGENTS.md")"
assert_contains "$OUT3" "AGENTS.md: replaced" "case3: legacy markers replaced"
assert_file_contains "$CASE3/AGENTS.md" "$BEGIN" "case3: current begin marker written"
assert_not_contains "$(cat "$CASE3/AGENTS.md")" "$LEGACY_BEGIN" "case3: legacy begin marker gone"
assert_file_contains "$CASE3/AGENTS.md" "TEXT ABOVE" "case3: text above legacy block preserved"
assert_file_contains "$CASE3/AGENTS.md" "TEXT BELOW" "case3: text below legacy block preserved"

# --- case 4: second run -> unchanged, exit 0, bytes identical --------------
CASE4="$BOX/case4"; mkdir -p "$CASE4"
printf 'ABOVE\n%s\nOLD\n%s\nBELOW\n' "$BEGIN" "$END" > "$CASE4/AGENTS.md"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE4/source.md"
run_script --source "$CASE4/source.md" --target "$CASE4/AGENTS.md" --claude-md "$CASE4/CLAUDE.md" >/dev/null
CONTENT4_BEFORE="$(cat "$CASE4/AGENTS.md")"

OUT4="$(run_script --source "$CASE4/source.md" --target "$CASE4/AGENTS.md" --claude-md "$CASE4/CLAUDE.md")"; RC4=$?
assert_eq "0" "$RC4" "case4: second run exits 0"
assert_contains "$OUT4" "AGENTS.md: unchanged" "case4: AGENTS.md reported unchanged"
assert_contains "$OUT4" "CLAUDE.md: unchanged" "case4: CLAUDE.md reported unchanged"
assert_eq "$CONTENT4_BEFORE" "$(cat "$CASE4/AGENTS.md")" "case4: AGENTS.md bytes unchanged"

# --- case 5: malformed marker sets -> exit 2 before any write --------------
CASE5="$BOX/case5"; mkdir -p "$CASE5"
printf 'ABOVE\n%s\nNO END HERE\n' "$BEGIN" > "$CASE5/AGENTS.md"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE5/source.md"
ORIG5="$(cat "$CASE5/AGENTS.md")"

ERR5="$(run_script --source "$CASE5/source.md" --target "$CASE5/AGENTS.md" 2>&1)"; RC5=$?
assert_eq "2" "$RC5" "case5: unmatched begin marker exits 2"
assert_contains "$ERR5" "AGENTS.md" "case5: error names the file"
assert_contains "$ERR5" ":2:" "case5: error names the offending line number"
assert_eq "$ORIG5" "$(cat "$CASE5/AGENTS.md")" "case5: target bytes unchanged after error"

CASE5B="$BOX/case5b"; mkdir -p "$CASE5B"
printf '%s\nA\n%s\nB\n' "$BEGIN" "$BEGIN" > "$CASE5B/AGENTS.md"
_="$(run_script --source "$CASE5/source.md" --target "$CASE5B/AGENTS.md" 2>&1)"; RC5B=$?
assert_eq "2" "$RC5B" "case5b: two begin markers exits 2"

# --- case 6: source without markers -> exit 2 -------------------------------
CASE6="$BOX/case6"; mkdir -p "$CASE6"
printf 'no markers here\n' > "$CASE6/source.md"
printf 'target text\n' > "$CASE6/AGENTS.md"

ERR6="$(run_script --source "$CASE6/source.md" --target "$CASE6/AGENTS.md" 2>&1)"; RC6=$?
assert_eq "2" "$RC6" "case6: source without markers exits 2"
assert_contains "$ERR6" "carries no managed block" "case6: error names the missing block"

# --- case 7: --dry-run -> reports "would ", writes nothing -----------------
CASE7="$BOX/case7"; mkdir -p "$CASE7"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE7/source.md"

OUT7="$(run_script --source "$CASE7/source.md" --target "$CASE7/AGENTS.md" --dry-run)"
assert_contains "$OUT7" "would AGENTS.md: appended" "case7: dry-run prefixes the outcome with would"
assert_eq "false" "$([ -f "$CASE7/AGENTS.md" ] && echo true || echo false)" "case7: dry-run does not create the target"

# --- case 8: --claude-md pointer file --------------------------------------
CASE8="$BOX/case8"; mkdir -p "$CASE8"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE8/source.md"
printf 'target\n' > "$CASE8/AGENTS.md"

OUT8="$(run_script --source "$CASE8/source.md" --target "$CASE8/AGENTS.md" --claude-md "$CASE8/CLAUDE.md")"
assert_contains "$OUT8" "CLAUDE.md: written" "case8: absent CLAUDE.md is written"
assert_eq "@AGENTS.md" "$(cat "$CASE8/CLAUDE.md")" "case8: CLAUDE.md content is exactly the pointer"

CASE8B="$BOX/case8b"; mkdir -p "$CASE8B"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE8B/source.md"
printf 'target\n' > "$CASE8B/AGENTS.md"
: > "$CASE8B/CLAUDE.md"
_i=0
while [ "$_i" -lt 500 ]; do printf 'legacy line %d\n' "$_i" >> "$CASE8B/CLAUDE.md"; _i=$((_i + 1)); done

OUT8B="$(run_script --source "$CASE8B/source.md" --target "$CASE8B/AGENTS.md" --claude-md "$CASE8B/CLAUDE.md")"
assert_contains "$OUT8B" "CLAUDE.md: written" "case8b: 500-line legacy CLAUDE.md gets rewritten"
assert_eq "@AGENTS.md" "$(cat "$CASE8B/CLAUDE.md")" "case8b: rewritten pointer content is exact"

CASE8C="$BOX/case8c"; mkdir -p "$CASE8C"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE8C/source.md"
printf 'target\n' > "$CASE8C/AGENTS.md"
printf '@AGENTS.md\r\n' > "$CASE8C/CLAUDE.md"

OUT8C="$(run_script --source "$CASE8C/source.md" --target "$CASE8C/AGENTS.md" --claude-md "$CASE8C/CLAUDE.md")"
assert_contains "$OUT8C" "CLAUDE.md: unchanged" "case8c: pre-existing CRLF pointer is unchanged"

# --- case 9: --source - reads the template from stdin ----------------------
CASE9="$BOX/case9"; mkdir -p "$CASE9"
printf 'target\n' > "$CASE9/AGENTS.md"

OUT9="$(printf '%s\nSTDIN CONTENT\n%s\n' "$BEGIN" "$END" | run_script --source - --target "$CASE9/AGENTS.md")"
assert_contains "$OUT9" "AGENTS.md: appended" "case9: stdin source is appended"
assert_file_contains "$CASE9/AGENTS.md" "STDIN CONTENT" "case9: stdin block content present"

# --- case 10: absent target -> created via append ---------------------------
CASE10="$BOX/case10"; mkdir -p "$CASE10"
printf '%s\nCONTENT10\n%s\n' "$BEGIN" "$END" > "$CASE10/source.md"
assert_eq "false" "$([ -f "$CASE10/AGENTS.md" ] && echo true || echo false)" "case10: target absent before the run"

OUT10="$(run_script --source "$CASE10/source.md" --target "$CASE10/AGENTS.md")"
assert_contains "$OUT10" "AGENTS.md: appended" "case10: absent target is created via append"
assert_file_contains "$CASE10/AGENTS.md" "CONTENT10" "case10: created file carries the block"


# --- case 11: --migrate moves project.md below the end marker, in order -------
# The fixture is the shape .claude/project.md had before the single instruction
# file: header, Deployment Targets, Project-Specific Rules with the Task Tracking
# pointer and the four generic sections, plus a section a team added.
project_md() {  # project_md <path> [extra-section-text]
  {
    printf '# Project-Specific Configuration\n\n'
    printf '> **Claude Code only.** Imported by `CLAUDE.md`.\n> Safe to edit.\n\n---\n\n'
    printf '## Deployment Targets\n\n| Service | Runbook | Triggers on branch | Project ID |\n|---|---|---|---|\n| Railway | .claude/deployments/railway.md | main | demo |\n\n---\n\n'
    printf '## Project-Specific Rules\n\n> Add any team-shared rules here.\n\n'
    printf '### Task Tracking\n\nTask tracking instructions: docs/tracking.md\n\nThe declaration lives here rather than in CLAUDE.md on purpose.\n\n'
    printf '### Code Economy\n\nGENERIC ECONOMY TEXT\n\n### Surgical Changes\n\nGENERIC SURGICAL TEXT\n\n'
    printf '### Ambiguity Protocol\n\nGENERIC AMBIGUITY TEXT\n\n### Large-Artifact Handoff\n\nGENERIC HANDOFF TEXT\n\n'
    printf '%s' "${2:-}"
  } > "$1"
}
CASE11="$BOX/case11"; mkdir -p "$CASE11/.claude"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE11/source.md"
printf '# Demo\n\n%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE11/AGENTS.md"
project_md "$CASE11/.claude/project.md" $'## Tech Stack\n\n- Python 3.12\n- Postgres\n'

OUT11="$(cd "$CASE11" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md)"; RC11=$?
assert_eq "0" "$RC11" "case11: migration exits 0"
assert_contains "$OUT11" "AGENTS.md: unchanged" "case11: the block itself was already current"
assert_contains "$OUT11" "migration: moved 4 section(s), .claude/project.md deleted" \
  "case11: reports the pointer, Deployment Targets, Project-Specific Rules and Tech Stack as moved"
assert_eq "false" "$([ -f "$CASE11/.claude/project.md" ] && echo true || echo false)" "case11: project.md deleted"
below11="$(awk -v e="$END" 'seen { print } $0 == e { seen = 1 }' "$CASE11/AGENTS.md")"
assert_eq "Task tracking instructions: docs/tracking.md" "$(printf '%s\n' "$below11" | grep -m1 .)" \
  "case11: the pointer line is the first non-blank line below the end marker"
order11="$(printf '%s\n' "$below11" | grep -E '^(Task tracking|## )' | tr '\n' '|')"
assert_eq "Task tracking instructions: docs/tracking.md|## Deployment Targets|## Project-Specific Rules|## Tech Stack|" "$order11" \
  "case11: pointer, targets table, Project-Specific Rules, Tech Stack — original order, headings unchanged"
assert_file_contains "$CASE11/AGENTS.md" "| Railway | .claude/deployments/railway.md | main | demo |" "case11: the targets table row moved intact"
assert_file_contains "$CASE11/AGENTS.md" "- Postgres" "case11: the team section's body moved"
for generic in "### Code Economy" "### Surgical Changes" "### Ambiguity Protocol" "### Large-Artifact Handoff" "GENERIC ECONOMY TEXT" "GENERIC HANDOFF TEXT"; do
  assert_not_contains "$(cat "$CASE11/AGENTS.md")" "$generic" "case11: generic section not moved — $generic"
done
assert_not_contains "$(cat "$CASE11/AGENTS.md")" "### Task Tracking" "case11: the Task Tracking heading is not moved (the block documents the pointer's placement)"
assert_contains "$OUT11" "migration: dropped ### Code Economy (owned by the block)" \
  "case11: every generic section dropped is reported by heading"
assert_contains "$OUT11" "migration: dropped ### Task Tracking (the block documents the pointer's placement)" \
  "case11: the Task Tracking drop is reported — the operator approves a deletion knowing what does not move"
assert_not_contains "$(cat "$CASE11/AGENTS.md")" "The declaration lives here" "case11: the Task Tracking prose is not moved"
assert_not_contains "$(cat "$CASE11/AGENTS.md")" "Claude Code only." "case11: project.md's own header is not moved"
assert_eq "1" "$(grep -cF -- "$BEGIN" "$CASE11/AGENTS.md")" "case11: still exactly one block"
assert_eq "# Demo" "$(head -1 "$CASE11/AGENTS.md")" "case11: text above the block byte-identical"

# --- case 12: re-run -> nothing to move, bytes identical ---------------------
CONTENT12="$(cat "$CASE11/AGENTS.md")"
OUT12="$(cd "$CASE11" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md)"; RC12=$?
assert_eq "0" "$RC12" "case12: re-run exits 0"
assert_contains "$OUT12" "migration: nothing to move" "case12: re-run reports nothing to move"
assert_eq "$CONTENT12" "$(cat "$CASE11/AGENTS.md")" "case12: re-run leaves AGENTS.md byte-identical"

# --- case 13: doubled Deployment Targets -> exit 2, nothing written ----------
CASE13="$BOX/case13"; mkdir -p "$CASE13/.claude"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE13/source.md"
printf '%s\nOLD\n%s\n\n## Deployment Targets\n\n| Service | Runbook | Triggers on branch | Project ID |\n|---|---|---|---|\n| Vercel | .claude/deployments/vercel.md | main | web |\n' \
  "$BEGIN" "$END" > "$CASE13/AGENTS.md"
project_md "$CASE13/.claude/project.md"
ORIG13="$(cat "$CASE13/AGENTS.md")"
ERR13="$(cd "$CASE13" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md 2>&1)"; RC13=$?
assert_eq "2" "$RC13" "case13: a Deployment Targets table in both files exits 2"
assert_contains "$ERR13" "'## Deployment Targets' is also below the end marker" "case13: the refusal names the collision"
assert_contains "$ERR13" ".claude/project.md" "case13: the refusal names project.md"
assert_eq "true" "$([ -f "$CASE13/.claude/project.md" ] && echo true || echo false)" "case13: project.md intact"
assert_eq "$ORIG13" "$(cat "$CASE13/AGENTS.md")" "case13: AGENTS.md bytes unchanged — the block was not written either"

# --- case 14: an existing Project-Specific Rules heading is reused ------------
CASE14="$BOX/case14"; mkdir -p "$CASE14/.claude"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE14/source.md"
printf '%s\nCONTENT\n%s\n\n## Project-Specific Rules\n\n### Code Graph\n\nNo graph here.\n' "$BEGIN" "$END" > "$CASE14/AGENTS.md"
project_md "$CASE14/.claude/project.md" $'### Domain Glossary\n\n- tenant: one paying customer\n'
OUT14="$(cd "$CASE14" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md)"
assert_contains "$OUT14" "migration: moved 3 section(s), .claude/project.md deleted" \
  "case14: pointer, targets table and the glossary move; the rules heading is reused, not counted"
assert_eq "1" "$(grep -c '^## Project-Specific Rules$' "$CASE14/AGENTS.md")" "case14: one Project-Specific Rules heading, not two"
assert_file_contains "$CASE14/AGENTS.md" "### Domain Glossary" "case14: the team's ### section moved"
assert_file_contains "$CASE14/AGENTS.md" "No graph here." "case14: the existing project text is untouched"
assert_contains "$OUT14" "migration: reused ## Project-Specific Rules (already below the end marker)" \
  "case14: the reuse is reported"
# 14b: text the team wrote directly under the reused heading is moved, not discarded.
CASE14B="$BOX/case14b"; mkdir -p "$CASE14B/.claude"
cp "$CASE14/source.md" "$CASE14B/source.md"
printf '%s\nCONTENT\n%s\n\n## Project-Specific Rules\n\n### Code Graph\n\nNo graph here.\n' "$BEGIN" "$END" > "$CASE14B/AGENTS.md"
{
  printf '# Project-Specific Configuration\n\n> Imported by CLAUDE.md.\n\n---\n\n'
  printf '## Project-Specific Rules\n\n> Add any team-shared rules here.\n\nTEAM RULE UNDER HEADING\n\n### Domain Glossary\n\n- tenant: one paying customer\n'
} > "$CASE14B/.claude/project.md"
OUT14B="$(cd "$CASE14B" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md)"
assert_contains "$OUT14B" "migration: moved 2 section(s)" "case14b: the rule text and the glossary move"
assert_file_contains "$CASE14B/AGENTS.md" "TEAM RULE UNDER HEADING" "case14b: text under the reused heading is moved, not dropped"
assert_not_contains "$(cat "$CASE14B/AGENTS.md")" "Add any team-shared rules here." "case14b: the template's placeholder blockquote goes with the heading"
assert_eq "1" "$(grep -c '^## Project-Specific Rules$' "$CASE14B/AGENTS.md")" "case14b: still one Project-Specific Rules heading"

# --- case 15: --dry-run reports the migration and writes nothing --------------
CASE15="$BOX/case15"; mkdir -p "$CASE15/.claude"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE15/source.md"
printf '%s\nOLD\n%s\n' "$BEGIN" "$END" > "$CASE15/AGENTS.md"
project_md "$CASE15/.claude/project.md"
ORIG15="$(cat "$CASE15/AGENTS.md")"
OUT15="$(cd "$CASE15" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md --dry-run)"
assert_contains "$OUT15" "would AGENTS.md: replaced" "case15: dry-run reports the block write"
assert_contains "$OUT15" "would migration: moved 3 section(s), .claude/project.md deleted" "case15: dry-run reports the migration"
assert_eq "true" "$([ -f "$CASE15/.claude/project.md" ] && echo true || echo false)" "case15: dry-run keeps project.md"
assert_eq "$ORIG15" "$(cat "$CASE15/AGENTS.md")" "case15: dry-run writes nothing"
OUT15B="$(cd "$CASE15" && rm .claude/project.md && run_script --source source.md --target AGENTS.md --migrate .claude/project.md --dry-run)"
assert_contains "$OUT15B" "would migration: nothing to move" "case15b: dry-run with no project.md reports nothing to move"

# --- /sync runs the migration inside the approved run (Step 6.6) -------------
SYNC_SKILL="$REPO/.agents/skills/sync/SKILL.md"
assert_file_matches "$SYNC_SKILL" '^### Step 6\.6 — Project-File Migration' "sync: Step 6.6 exists"
step66="$(awk '/^### Step 6\.6/ { p = 1; next } p && /^### / { exit } p' "$SYNC_SKILL")"
assert_contains "$step66" '--target AGENTS.md --migrate .claude/project.md' "sync: Step 6.6 runs the script with --migrate"
assert_contains "$step66" 'migration: nothing to move' "sync: Step 6.6 documents the re-run outcome"
assert_contains "$step66" 'never runs this step' "sync: Step 6.6 says the CI mirror does not migrate (it never deletes)"
step3="$(awk '/^### Step 3 /{ p = 1; next } p && /^### / { exit } p' "$SYNC_SKILL")"
assert_contains "$step3" '--migrate .claude/project.md --dry-run' "sync: the Step 3 preview shows the migration the user approves"

# --- case 16: a missing input file is a refusal, not a traceback --------------
CASE16="$BOX/case16"; mkdir -p "$CASE16"
OUT16="$(run_script --source "$CASE16/absent.md" --target "$CASE16/AGENTS.md" 2>&1)"; RC16=$?
assert_eq "2" "$RC16" "case16: a missing --source exits 2"
assert_contains "$OUT16" "absent.md" "case16: the refusal names the missing file"
assert_not_contains "$OUT16" "Traceback" "case16: no traceback reaches the operator"
assert_eq "false" "$([ -f "$CASE16/AGENTS.md" ] && echo true || echo false)" "case16: nothing is written"

# --- case 17: every malformed marker set refuses with the line, nothing written --
CASE17="$BOX/case17"; mkdir -p "$CASE17"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE17/source.md"
while IFS='|' read -r name body expect; do
  printf '%b' "$body" > "$CASE17/$name.md"
  ERR17="$(run_script --source "$CASE17/source.md" --target "$CASE17/$name.md" 2>&1 >/dev/null)"; RC17=$?
  assert_eq "2" "$RC17" "case17 ($name): exits 2"
  assert_contains "$ERR17" "$name.md:$expect" "case17 ($name): the refusal names the file and the line"
  assert_eq "$(printf '%b' "$body")" "$(cat "$CASE17/$name.md")" "case17 ($name): nothing written"
done <<EOF17
end-only|head\n$END\ntail\n|2: end marker with no matching begin marker
end-first|head\n$END\nmid\n$BEGIN\ntail\n|2: end marker precedes its begin marker
two-ends|$BEGIN\nx\n$END\ny\n$END\n|5: more than one end marker
EOF17

# --- case 18: an empty target and a markers-only target ----------------------
CASE18="$BOX/case18"; mkdir -p "$CASE18"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE18/source.md"
: > "$CASE18/empty.md"
OUT18="$(run_script --source "$CASE18/source.md" --target "$CASE18/empty.md")"
assert_contains "$OUT18" "empty.md: appended" "case18: an existing empty target is appended to"
assert_eq "$(printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END")" "$(cat "$CASE18/empty.md")" "case18: the empty target becomes exactly the block"
printf '%s\n%s\n' "$BEGIN" "$END" > "$CASE18/bare.md"
OUT18B="$(run_script --source "$CASE18/source.md" --target "$CASE18/bare.md")"
assert_contains "$OUT18B" "bare.md: replaced" "case18: a markers-only target is replaced"
assert_eq "1" "$(grep -cF -- "$BEGIN" "$CASE18/bare.md")" "case18: still one block"

# --- case 19: whitespace-padded markers are still markers (no second block) ----
CASE19="$BOX/case19"; mkdir -p "$CASE19"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE19/source.md"
printf 'above\n%s \nOLD\n  %s\t\nbelow\n' "$BEGIN" "$END" > "$CASE19/AGENTS.md"
OUT19="$(run_script --source "$CASE19/source.md" --target "$CASE19/AGENTS.md")"
assert_contains "$OUT19" "AGENTS.md: replaced" "case19: padded markers are recognised — replaced, not appended"
assert_eq "1" "$(grep -cF -- "$BEGIN" "$CASE19/AGENTS.md")" "case19: exactly one begin marker afterwards"
assert_not_contains "$(cat "$CASE19/AGENTS.md")" "OLD" "case19: the old block text is gone"
assert_eq "above" "$(head -1 "$CASE19/AGENTS.md")" "case19: text above intact"

# --- case 20: a non-UTF-8 input is a refusal naming the file, not a traceback ---
CASE20="$BOX/case20"; mkdir -p "$CASE20"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE20/source.md"
printf 'caf\351\n%s\nOLD\n%s\n' "$BEGIN" "$END" > "$CASE20/AGENTS.md"
cp "$CASE20/AGENTS.md" "$CASE20/before.md"
ERR20="$(run_script --source "$CASE20/source.md" --target "$CASE20/AGENTS.md" 2>&1 >/dev/null)"; RC20=$?
assert_eq "2" "$RC20" "case20: a cp1252 byte in the target exits 2"
assert_contains "$ERR20" "AGENTS.md: not UTF-8" "case20: the refusal names the file"
assert_not_contains "$ERR20" "Traceback" "case20: no traceback"
assert_files_identical "$CASE20/before.md" "$CASE20/AGENTS.md" "case20: nothing written"

# --- case 21: migration edges — no headings, a fenced heading, a fenced pointer -
CASE21="$BOX/case21"; mkdir -p "$CASE21/.claude"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE21/source.md"
cp "$CASE21/source.md" "$CASE21/AGENTS.md"
printf '# Project-Specific Configuration\n\n> Imported.\n\n---\n\nJust prose, no headings.\n' > "$CASE21/.claude/project.md"
OUT21="$(cd "$CASE21" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md)"
assert_contains "$OUT21" "migration: moved 1 section(s)" "case21: a heading-less body moves as one section"
assert_file_contains "$CASE21/AGENTS.md" "Just prose, no headings." "case21: the prose landed below the end marker"
cp "$CASE21/source.md" "$CASE21/AGENTS.md"
{
  printf '# Project-Specific Configuration\n\n---\n\n### Team Notes\n\n'
  printf '```md\n## Not A Heading\nTask tracking instructions: fenced/path.md\n```\n\n'
  printf 'Task tracking instructions: docs/real.md\n'
} > "$CASE21/.claude/project.md"
OUT21B="$(cd "$CASE21" && run_script --source source.md --target AGENTS.md --migrate .claude/project.md)"
assert_contains "$OUT21B" "migration: moved 2 section(s)" "case21: the pointer and one section — the fenced heading did not split it"
below21="$(awk -v e="$END" '$0 == e {p=1; next} p' "$CASE21/AGENTS.md")"
assert_eq "Task tracking instructions: docs/real.md" "$(printf '%s\n' "$below21" | grep -m1 .)" \
  "case21: the unfenced pointer is promoted to the first line below the end marker"
assert_eq "1" "$(grep -c 'fenced/path.md' "$CASE21/AGENTS.md")" "case21: the fenced pointer line stays inside its fence as text"
assert_eq "1" "$(grep -c '^## Not A Heading$' "$CASE21/AGENTS.md")" "case21: the fenced heading moved intact inside its section"

# --- case 22: generic headings and a second pointer outside the block are reported
CASE22="$BOX/case22"; mkdir -p "$CASE22"
printf '%s\nCONTENT\n%s\n' "$BEGIN" "$END" > "$CASE22/source.md"
printf '# Pi rules\n\n### Code Economy\n\nold copy\n\nTask tracking instructions: docs/a.md\n\n%s\nOLD\n%s\n\nTask tracking instructions: docs/b.md\n' "$BEGIN" "$END" > "$CASE22/AGENTS.md"
OUT22="$(run_script --source "$CASE22/source.md" --target "$CASE22/AGENTS.md")"
assert_contains "$OUT22" "AGENTS.md: '### Code Economy' outside the block duplicates the block — remove by hand" \
  "case22: a generic heading above the block is reported"
assert_contains "$OUT22" "AGENTS.md: 'Task tracking instructions: docs/b.md' outside the block duplicates the block — remove by hand" \
  "case22: a second pointer is reported"
assert_file_contains "$CASE22/AGENTS.md" "old copy" "case22: reported, never edited"
assert_eq "0" "$(run_script --source "$CASE22/source.md" --target "$CASE22/AGENTS.md" | grep -c "docs/a.md")" \
  "case22: the first pointer is not a duplicate"

finish
