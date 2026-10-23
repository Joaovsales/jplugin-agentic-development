#!/bin/bash
# tests/test-quality-receipt.sh — .agents/skills/quality-gate/scripts/receipt.py
# (specs/quality-receipt-closure.md AC 1-3): fingerprint the tasks-excluded
# diff between a branch's merge-base and its working tree, mint a
# quality-receipt/1 whose verdict is derived from findings and never accepted
# as input, and check/approve a stored receipt against the current tree and
# policy.
. "$(dirname "$0")/lib.sh"

PY="$TEST_PYTHON"
RECEIPT="$(under_test .agents/skills/quality-gate/scripts/receipt.py)"
REPO="${RECEIPT%/.agents/skills/quality-gate/scripts/receipt.py}"

BOX="$(fixture_dir)"

# receipt_in <repo> <receipt args...> — the receipt CLI with <repo> as cwd.
receipt_in() { local repo="$1"; shift; ( cd "$repo" && "$PY" "$RECEIPT" "$@" ); }

# feature_repo — a fixture repo on branch "feature" with one commit on
# "main" and one further commit on "feature", so HEAD != the base ref and
# merge-base is the "main" tip.
feature_repo() {
  local dir
  dir="$(fixture_repo)" || exit 143
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  printf 'base\n' > "$dir/base.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -q -m init
  git -C "$dir" checkout -q -b feature
  printf 'feature\n' > "$dir/feature.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -q -m feature
  printf '%s\n' "$dir"
}

fp_field() { # fp_field <n> <fingerprint-output>
  printf '%s\n' "$2" | awk -v n="$1" '{print $n}'
}

# ===========================================================================
printf '\n--- fingerprint ---\n'
# ===========================================================================

REPO1="$(feature_repo)"

run receipt_in "$REPO1" fingerprint --base main
OUT="$output"
assert_exit 0 "fingerprint: exits 0"
WORDS=$(printf '%s' "$OUT" | wc -w | tr -d ' ')
assert_eq "3" "$WORDS" "fingerprint: prints merge-base, tree and fingerprint"

EXPECT_BASE="$(git -C "$REPO1" merge-base HEAD main)"
assert_eq "$EXPECT_BASE" "$(fp_field 1 "$OUT")" "fingerprint: first field is the merge-base"

FP0="$(fp_field 3 "$OUT")"

# --- unchanged by tasks/** ------------------------------------------------
mkdir -p "$REPO1/tasks"
printf 'notes\n' > "$REPO1/tasks/notes.md"
OUT2="$(receipt_in "$REPO1" fingerprint --base main)"
assert_eq "$FP0" "$(fp_field 3 "$OUT2")" "fingerprint: an untracked file under tasks/** does not change it"

git -C "$REPO1" add -A
git -C "$REPO1" -c commit.gpgsign=false commit -q -m "tasks bookkeeping"
OUT3="$(receipt_in "$REPO1" fingerprint --base main)"
assert_eq "$FP0" "$(fp_field 3 "$OUT3")" "fingerprint: committing the same non-tasks tree does not change it"

# --- unchanged by diff config --------------------------------------------
git -C "$REPO1" config diff.noprefix true
git -C "$REPO1" config diff.external "echo fake"
OUT4="$(receipt_in "$REPO1" fingerprint --base main)"
assert_eq "$FP0" "$(fp_field 3 "$OUT4")" "fingerprint: diff.noprefix/diff.external config does not change it"
git -C "$REPO1" config --unset diff.noprefix
git -C "$REPO1" config --unset diff.external

# --- changed by a tracked edit --------------------------------------------
printf 'feature changed\n' > "$REPO1/feature.txt"
OUT5="$(receipt_in "$REPO1" fingerprint --base main)"
assert_not_contains "$FP0" "$(fp_field 3 "$OUT5")" "fingerprint: a tracked edit changes it"
git -C "$REPO1" add -A
git -C "$REPO1" -c commit.gpgsign=false commit -q -m "edit feature.txt"
FP1="$(fp_field 3 "$OUT5")"

# --- changed by a line-ending-only edit -----------------------------------
printf 'feature changed\r\n' > "$REPO1/feature.txt"
OUT5B="$(receipt_in "$REPO1" fingerprint --base main)"
assert_not_contains "$FP1" "$(fp_field 3 "$OUT5B")" "fingerprint: a CRLF-only edit changes it"
git -C "$REPO1" checkout -q -- feature.txt

# --- changed by an untracked file -----------------------------------------
printf 'new\n' > "$REPO1/untracked.txt"
OUT6="$(receipt_in "$REPO1" fingerprint --base main)"
assert_not_contains "$FP1" "$(fp_field 3 "$OUT6")" "fingerprint: an untracked file outside tasks/** changes it"
rm -f "$REPO1/untracked.txt"

# --- changed by a specs/ edit ---------------------------------------------
mkdir -p "$REPO1/specs"
printf 'spec\n' > "$REPO1/specs/thing.md"
OUT7="$(receipt_in "$REPO1" fingerprint --base main)"
assert_not_contains "$FP1" "$(fp_field 3 "$OUT7")" "fingerprint: an edit under specs/ changes it (stays in scope)"
rm -rf "$REPO1/specs"

# --- base resolution: omitted, falls back to local main -------------------
run receipt_in "$REPO1" fingerprint
OUT8="$output"
assert_exit 0 "fingerprint: --base omitted resolves a default"
EXPECT_BASE_LOCAL="$(git -C "$REPO1" merge-base HEAD main)"
assert_eq "$EXPECT_BASE_LOCAL" "$(fp_field 1 "$OUT8")" "fingerprint: omitted --base resolves local main when no remote exists"

# --- base resolution: origin/master preferred when present ----------------
git -C "$REPO1" update-ref refs/remotes/origin/master "$(git -C "$REPO1" rev-parse main)"
OUT9="$(receipt_in "$REPO1" fingerprint)"
EXPECT_BASE_ORIGIN="$(git -C "$REPO1" merge-base HEAD refs/remotes/origin/master)"
assert_eq "$EXPECT_BASE_ORIGIN" "$(fp_field 1 "$OUT9")" "fingerprint: omitted --base prefers origin/master over local main"

# ===========================================================================
printf '\n--- write ---\n'
# ===========================================================================

REPO2="$(feature_repo)"
GIT_COMMON_DIR_2="$(git -C "$REPO2" rev-parse --path-format=absolute --git-common-dir)"

make_outcome() { # make_outcome <file> <tree> <must-fix?> <should-fix-count> <design-verdict> <tests-exit> <scope-json> <verdict-lie>
  local file="$1" tree="$2" mustfix="$3" shouldfix="$4" design="$5" texit="$6" scope="$7" lie="$8"
  local entries=() i=0 joined="" e
  if [ "$mustfix" = "yes" ]; then
    entries+=('{"severity":"MUST-FIX","confidence":100,"autofix_class":"manual","owner":"human","location":"x.py:1","summary":"bad"}')
  fi
  while [ "$i" -lt "$shouldfix" ]; do
    entries+=('{"severity":"SHOULD-FIX","confidence":75,"autofix_class":"manual","owner":"human","location":"x.py:2","summary":"minor"}')
    i=$((i + 1))
  done
  for e in "${entries[@]:-}"; do
    [ -z "$e" ] && continue
    if [ -z "$joined" ]; then joined="$e"; else joined="$joined,$e"; fi
  done
  cat > "$file" <<EOF
{
  "reviewers": [
    {"phase": 1, "lens": "simplify", "dispatch": "inline"},
    {"phase": 2, "lens": "deslop", "dispatch": "inline"},
    {"phase": 3, "lens": "security-scan", "dispatch": "inline"},
    {"phase": 4, "lens": "software-design-expert-review", "dispatch": "dispatched", "verdict": "$design"}
  ],
  "unresolved": [$joined],
  "tests": {"command": "bash tests/run.sh", "exit": $texit, "tree": "$tree"},
  "design_verdict": "$design",
  "scope": $scope
EOF
  if [ -n "$lie" ]; then printf '  ,"verdict": "%s"\n' "$lie" >> "$file"; fi
  printf '}\n' >> "$file"
}

FP_OUT="$(receipt_in "$REPO2" fingerprint --base main)"
TREE2="$(fp_field 2 "$FP_OUT")"
FP2="$(fp_field 3 "$FP_OUT")"
STORE2="$GIT_COMMON_DIR_2/quality-receipts"

# --- valid GO --------------------------------------------------------------
make_outcome "$BOX/outcome-go.json" "$TREE2" no 0 GO 0 '"full"' ""
run receipt_in "$REPO2" write --outcome "$BOX/outcome-go.json"
OUT="$output"
assert_exit 0 "write: a clean outcome exits 0"
assert_contains "$OUT" "receipt: written ${FP2:0:8} verdict GO policy qg1-" "write: prints the written line with verdict GO"
assert_file_contains "$STORE2/$FP2.json" "\"schema\": \"quality-receipt/1\"" "write: stores the schema field"
assert_file_contains "$STORE2/$FP2.json" "\"verdict\": \"GO\"" "write: stores the derived verdict"
assert_file_contains "$STORE2/$FP2.json" "\"fingerprint\": \"$FP2\"" "write: stores its own fingerprint"
BRANCH_SAN="$(git -C "$REPO2" rev-parse --abbrev-ref HEAD | tr '/' '-')"
assert_file_exists "$STORE2/branch-$BRANCH_SAN.json" "write: stores the branch pointer"
assert_file_contains "$STORE2/branch-$BRANCH_SAN.json" "\"fingerprint\": \"$FP2\"" "write: pointer names this fingerprint"

# --- a phase-5 reviewer entry (the test-engineer Review job) is accepted and recorded
awk '{ if ($0 ~ /"phase": 4/) { print $0 ","; print "    {\"phase\": 5, \"lens\": \"test-engineer\", \"dispatch\": \"dispatched\"}" } else print $0 }'   "$BOX/outcome-go.json" > "$BOX/outcome-phase5.json"
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-phase5.json")"
CODE=$?
assert_eq "0" "$CODE" "write: an outcome with a phase-5 reviewer entry is accepted"
assert_file_contains "$STORE2/$FP2.json" "\"lens\": \"test-engineer\"" "write: the phase-5 test-engineer reviewer is recorded in the receipt"
assert_file_contains ".agents/skills/quality-gate/scripts/receipt.py" "agents\", \"test-engineer.md\""   "write: POLICY_FILES includes the test-engineer persona"

# --- a required but undispatchable review is recorded as lost, and still validated
sed 's/"dispatch": "dispatched"}$/"dispatch": "lost"}/' "$BOX/outcome-phase5.json" > "$BOX/outcome-lost.json"
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-lost.json")"
CODE=$?
assert_eq "0" "$CODE" "write: a reviewer entry with dispatch lost is accepted"
assert_file_contains "$STORE2/$FP2.json" "\"dispatch\": \"lost\"" "write: the lost dispatch is carried in the receipt"
sed '/"phase": 4/ s/"dispatch": "[a-z]*"/"dispatch": "lost"/' "$BOX/outcome-phase5.json" > "$BOX/outcome-lost-phase4.json"
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-lost-phase4.json" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "write: dispatch lost on a phase 1-4 entry is refused"
assert_contains "$OUT" "lost is only for the phase 5 test-engineer" "write: the lost-on-phase-4 refusal says where lost is allowed"
sed 's/"lens": "test-engineer", "dispatch": "dispatched"}$/"lens": "other", "dispatch": "lost"}/' "$BOX/outcome-phase5.json" > "$BOX/outcome-lost-other-lens.json"
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-lost-other-lens.json" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "write: dispatch lost on a phase 5 entry with another lens is refused"
assert_contains "$OUT" "lost is only for the phase 5 test-engineer" "write: the lost-on-another-lens refusal says where lost is allowed"
sed 's/"dispatch": "dispatched"}$/"dispatch": "skipped"}/' "$BOX/outcome-phase5.json" > "$BOX/outcome-skipped.json"
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-skipped.json" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "write: an unknown dispatch value is still refused"

# --- MUST-FIX forces STOP regardless of a supplied verdict -----------------
make_outcome "$BOX/outcome-mustfix.json" "$TREE2" yes 0 GO 0 '"full"' "GO"
OUT="$(receipt_in "$REPO2" write --outcome "$BOX/outcome-mustfix.json")"
assert_contains "$OUT" "verdict STOP" "write: an unresolved MUST-FIX forces STOP"
assert_file_contains "$STORE2/$FP2.json" "\"verdict\": \"STOP\"" "write: a supplied verdict of GO is ignored in favor of STOP"

# --- design STOP forces STOP -------------------------------------------
make_outcome "$BOX/outcome-designstop.json" "$TREE2" no 0 STOP 0 '"full"' ""
OUT="$(receipt_in "$REPO2" write --outcome "$BOX/outcome-designstop.json")"
assert_contains "$OUT" "verdict STOP" "write: design_verdict STOP forces STOP"

# --- red tests forces STOP -------------------------------------------------
make_outcome "$BOX/outcome-redtests.json" "$TREE2" no 0 GO 1 '"full"' ""
OUT="$(receipt_in "$REPO2" write --outcome "$BOX/outcome-redtests.json")"
assert_contains "$OUT" "verdict STOP" "write: tests.exit != 0 forces STOP"

# --- >3 unresolved SHOULD-FIX forces HOLD ----------------------------------
make_outcome "$BOX/outcome-hold4.json" "$TREE2" no 4 GO 0 '"full"' ""
OUT="$(receipt_in "$REPO2" write --outcome "$BOX/outcome-hold4.json")"
assert_contains "$OUT" "verdict HOLD" "write: more than 3 unresolved SHOULD-FIX forces HOLD"

# --- exactly 3 SHOULD-FIX stays GO -----------------------------------------
make_outcome "$BOX/outcome-should3.json" "$TREE2" no 3 GO 0 '"full"' ""
OUT="$(receipt_in "$REPO2" write --outcome "$BOX/outcome-should3.json")"
assert_contains "$OUT" "verdict GO" "write: exactly 3 unresolved SHOULD-FIX stays GO"

# --- design HOLD forces HOLD ------------------------------------------------
make_outcome "$BOX/outcome-designhold.json" "$TREE2" no 0 HOLD 0 '"full"' ""
OUT="$(receipt_in "$REPO2" write --outcome "$BOX/outcome-designhold.json")"
assert_contains "$OUT" "verdict HOLD" "write: design_verdict HOLD forces HOLD"

# --- schema failure: nothing written, exit 2 -------------------------------
cat > "$BOX/outcome-bad-schema.json" <<'EOF'
{"reviewers": [], "unresolved": [], "tests": {"exit": 0}, "design_verdict": "GO", "scope": "full"}
EOF
BEFORE_COUNT=$(ls "$STORE2" | wc -l | tr -d ' ')
assert_refused 2 "receipt: invalid outcome" "write: a schema failure exits 2 and names the refusal" -- \
  receipt_in "$REPO2" write --outcome "$BOX/outcome-bad-schema.json"
AFTER_COUNT=$(ls "$STORE2" | wc -l | tr -d ' ')
assert_eq "$BEFORE_COUNT" "$AFTER_COUNT" "write: a schema failure writes nothing"

# --- tests.tree mismatch: exit 2, nothing written --------------------------
make_outcome "$BOX/outcome-wrongtree.json" "0000000000000000000000000000000000000000000000000000000000000000" no 0 GO 0 '"full"' ""
assert_refused 2 "tests.tree" "write: a tests.tree mismatch exits 2 and names the tree mismatch" -- \
  receipt_in "$REPO2" write --outcome "$BOX/outcome-wrongtree.json"

# --- delta scope with no stored parent: exit 2, nothing written ------------
make_outcome "$BOX/outcome-delta-noparent.json" "$TREE2" no 0 GO 0 '["x.py"]' ""
assert_refused 2 "parent: no stored receipt" "write: a delta scope naming an unstored parent exits 2 and names the missing parent" -- \
  receipt_in "$REPO2" write --outcome "$BOX/outcome-delta-noparent.json" --parent deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef

# --- delta receipt: SHOULD-FIX carried back to the nearest approved HOLD ---
REPO2B="$(feature_repo)"
FP_OUT_B="$(receipt_in "$REPO2B" fingerprint --base main)"
TREE2B="$(fp_field 2 "$FP_OUT_B")"
FP2B="$(fp_field 3 "$FP_OUT_B")"
GIT_COMMON_2B="$(git -C "$REPO2B" rev-parse --path-format=absolute --git-common-dir)"
STORE2B="$GIT_COMMON_2B/quality-receipts"

make_outcome "$BOX/outcome-parent-hold.json" "$TREE2B" no 2 HOLD 0 '"full"' ""
receipt_in "$REPO2B" write --outcome "$BOX/outcome-parent-hold.json" >/dev/null
assert_file_contains "$STORE2B/$FP2B.json" "\"verdict\": \"HOLD\"" "write: parent receipt with 2 unresolved SHOULD-FIX is HOLD"
receipt_in "$REPO2B" approve --fingerprint "$FP2B" --by tester >/dev/null
assert_file_contains "$STORE2B/$FP2B.json" "\"hold_approved_by\": \"tester\"" "approve: records the approver on the parent HOLD"

printf 'delta change\n' > "$REPO2B/feature.txt"
git -C "$REPO2B" add -A
git -C "$REPO2B" -c commit.gpgsign=false commit -q -m "delta change"
FP_OUT_B2="$(receipt_in "$REPO2B" fingerprint --base main)"
TREE2B2="$(fp_field 2 "$FP_OUT_B2")"
FP2B2="$(fp_field 3 "$FP_OUT_B2")"
make_outcome "$BOX/outcome-delta-carry.json" "$TREE2B2" no 2 GO 0 '["feature.txt"]' ""
OUT="$(receipt_in "$REPO2B" write --outcome "$BOX/outcome-delta-carry.json" --parent "$FP2B")"
assert_contains "$OUT" "verdict GO" "write: an approved-HOLD parent's SHOULD-FIX were accepted, so a delta's own 2 stay GO"

# A GO link is summed through: this delta's 2 plus its GO parent's 2 exceed 3,
# and the walk stops at the approved HOLD behind them.
printf 'second delta\n' > "$REPO2B/feature.txt"
git -C "$REPO2B" add -A
git -C "$REPO2B" -c commit.gpgsign=false commit -q -m "second delta"
TREE2B3="$(fp_field 2 "$(receipt_in "$REPO2B" fingerprint --base main)")"
make_outcome "$BOX/outcome-delta-carry2.json" "$TREE2B3" no 2 GO 0 '["feature.txt"]' ""
OUT="$(receipt_in "$REPO2B" write --outcome "$BOX/outcome-delta-carry2.json" --parent "$FP2B2")"
assert_contains "$OUT" "verdict HOLD" "write: SHOULD-FIX carried through a GO link back to the approved HOLD force HOLD"

# ===========================================================================
printf '\n--- check and approve ---\n'
# ===========================================================================

REPO3="$(feature_repo)"
GIT_COMMON_3="$(git -C "$REPO3" rev-parse --path-format=absolute --git-common-dir)"
STORE3="$GIT_COMMON_3/quality-receipts"

assert_refused 3 "receipt: stale missing" "check: a tree with no receipt and no pointer is stale missing" -- \
  receipt_in "$REPO3" check --base main

FP_OUT3="$(receipt_in "$REPO3" fingerprint --base main)"
TREE3="$(fp_field 2 "$FP_OUT3")"
FP3="$(fp_field 3 "$FP_OUT3")"
make_outcome "$BOX/outcome3-go.json" "$TREE3" no 0 GO 0 '"full"' ""
receipt_in "$REPO3" write --outcome "$BOX/outcome3-go.json" >/dev/null

run receipt_in "$REPO3" check --base main
assert_exit 0 "check: a valid GO receipt exits 0"
assert_contains "$output" "receipt: valid GO ${FP3:0:8} policy qg1-" "check: names the valid GO line"

# --- diff-changed: a new tree with the branch pointer naming a valid parent -
printf 'diff changed\n' > "$REPO3/feature.txt"
git -C "$REPO3" add -A
git -C "$REPO3" -c commit.gpgsign=false commit -q -m "diff change"
run receipt_in "$REPO3" check --base main
assert_exit 3 "check: an unreviewed new tree is stale"
assert_contains "$output" "receipt: stale diff-changed parent $FP3 " "check: diff-changed names the parent's full fingerprint"
assert_contains "$output" "delta feature.txt" "check: diff-changed names the changed path"

# write a HOLD outcome for this new tree, then check reports stale verdict HOLD
FP_OUT3B="$(receipt_in "$REPO3" fingerprint --base main)"
TREE3B="$(fp_field 2 "$FP_OUT3B")"
FP3B="$(fp_field 3 "$FP_OUT3B")"
make_outcome "$BOX/outcome3-hold.json" "$TREE3B" no 4 GO 0 '"full"' ""
receipt_in "$REPO3" write --outcome "$BOX/outcome3-hold.json" >/dev/null
assert_refused 3 "receipt: stale verdict HOLD" "check: an unapproved HOLD receipt is stale, reason verdict HOLD" -- \
  receipt_in "$REPO3" check --base main

# --- approve refuses a non-HOLD receipt ------------------------------------
assert_refused 2 "only HOLD can be approved" "approve: refuses a GO receipt" -- \
  receipt_in "$REPO3" approve --fingerprint "$FP3" --by tester

assert_refused 2 "no such receipt" "approve: refuses an unknown fingerprint" -- \
  receipt_in "$REPO3" approve --fingerprint deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef --by tester

# --- approve makes the HOLD receipt valid and a valid chain link ----------
receipt_in "$REPO3" approve --fingerprint "$FP3B" --by tester >/dev/null
run receipt_in "$REPO3" check --base main
assert_exit 0 "check: an approved HOLD receipt is valid"
assert_contains "$output" "receipt: valid HOLD-approved ${FP3B:0:8}" "check: names the approved HOLD line"

# --- schema: corrupt the stored receipt's schema field ---------------------
cp "$STORE3/$FP3B.json" "$BOX/backup-schema.json"
"$PY" - "$STORE3/$FP3B.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["schema"] = "quality-receipt/0"
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
assert_refused 3 "receipt: stale schema" "check: a receipt with another schema is stale, reason schema" -- \
  receipt_in "$REPO3" check --base main
cp "$BOX/backup-schema.json" "$STORE3/$FP3B.json"

# --- corrupt: a stored receipt that is not JSON is stale schema, not a crash --
printf '{"schema":' > "$STORE3/$FP3B.json"
assert_refused 3 "receipt: stale schema" "check: a corrupt stored receipt is stale, reason schema" -- \
  receipt_in "$REPO3" check --base main
assert_not_contains "$output" "Traceback" "check: a corrupt stored receipt prints no traceback"
cp "$BOX/backup-schema.json" "$STORE3/$FP3B.json"

# --- policy-changed: a copied skill tree with one policy file edited -------
COPY_ROOT="$BOX/policy-copy"
mkdir -p "$COPY_ROOT"
cp -r "$REPO/.agents" "$COPY_ROOT/.agents"
RECEIPT_COPY="$COPY_ROOT/.agents/skills/quality-gate/scripts/receipt.py"
printf '\n<!-- test edit -->\n' >> "$COPY_ROOT/.agents/skills/quality-gate/SKILL.md"
assert_refused 3 "receipt: stale policy-changed" "check: an edited policy file is stale, reason policy-changed" -- \
  bash -c 'cd "$1" && shift && "$@"' _ "$REPO3" "$PY" "$RECEIPT_COPY" check --base main

# --- policy-changed: editing the test-engineer persona alone stales a receipt
COPY_ROOT2="$BOX/policy-copy-persona"
mkdir -p "$COPY_ROOT2"
cp -r "$REPO/.agents" "$COPY_ROOT2/.agents"
printf '
<!-- test edit -->
' >> "$COPY_ROOT2/.agents/agents/test-engineer.md"
OUT="$(cd "$REPO3" && "$PY" "$COPY_ROOT2/.agents/skills/quality-gate/scripts/receipt.py" check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: an edited test-engineer persona is stale"
assert_contains "$OUT" "receipt: stale policy-changed" "check: the test-engineer persona edit names policy-changed"

# --- parent-invalid: corrupt a chain ancestor's policy ---------------------
REPO4="$(feature_repo)"
GIT_COMMON_4="$(git -C "$REPO4" rev-parse --path-format=absolute --git-common-dir)"
STORE4="$GIT_COMMON_4/quality-receipts"
FP_OUT4="$(receipt_in "$REPO4" fingerprint --base main)"
TREE4="$(fp_field 2 "$FP_OUT4")"
FP4="$(fp_field 3 "$FP_OUT4")"
make_outcome "$BOX/outcome4-go.json" "$TREE4" no 0 GO 0 '"full"' ""
receipt_in "$REPO4" write --outcome "$BOX/outcome4-go.json" >/dev/null

printf 'child change\n' > "$REPO4/feature.txt"
git -C "$REPO4" add -A
git -C "$REPO4" -c commit.gpgsign=false commit -q -m "child change"
FP_OUT4B="$(receipt_in "$REPO4" fingerprint --base main)"
TREE4B="$(fp_field 2 "$FP_OUT4B")"
FP4B="$(fp_field 3 "$FP_OUT4B")"
make_outcome "$BOX/outcome4-delta.json" "$TREE4B" no 0 GO 0 '["feature.txt"]' ""
receipt_in "$REPO4" write --outcome "$BOX/outcome4-delta.json" --parent "$FP4" >/dev/null

run receipt_in "$REPO4" check --base main
assert_exit 0 "check: a delta receipt with a valid GO parent is valid"

"$PY" - "$STORE4/$FP4.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["policy"] = "qg1-00000000"
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
assert_refused 3 "receipt: stale parent-invalid" "check: a delta receipt whose parent's policy no longer matches is stale, reason parent-invalid" -- \
  receipt_in "$REPO4" check --base main

# --- delta after a base merge excludes files only the base changed ---------
REPO5="$(feature_repo)"
GIT_COMMON_5="$(git -C "$REPO5" rev-parse --path-format=absolute --git-common-dir)"
STORE5="$GIT_COMMON_5/quality-receipts"
FP_OUT5="$(receipt_in "$REPO5" fingerprint --base main)"
TREE5="$(fp_field 2 "$FP_OUT5")"
FP5="$(fp_field 3 "$FP_OUT5")"
make_outcome "$BOX/outcome5-go.json" "$TREE5" no 0 GO 0 '"full"' ""
receipt_in "$REPO5" write --outcome "$BOX/outcome5-go.json" >/dev/null

# main advances with a file the feature branch never touched, feature merges
# it in, and then the branch makes its own further edit. The delta must name
# only the branch's own edit, not the base-only file the merge brought in.
git -C "$REPO5" checkout -q main
printf 'main advanced\n' > "$REPO5/base-only.txt"
git -C "$REPO5" add -A
git -C "$REPO5" -c commit.gpgsign=false commit -q -m "base-only change"
git -C "$REPO5" checkout -q feature
git -C "$REPO5" -c commit.gpgsign=false merge -q --no-edit main
printf 'feature edited after merge\n' > "$REPO5/feature.txt"
git -C "$REPO5" add -A
git -C "$REPO5" -c commit.gpgsign=false commit -q -m "feature edit after merge"

run receipt_in "$REPO5" check --base main
assert_exit 3 "check: after a base merge plus a branch edit the tree is stale"
assert_not_contains "$output" "base-only.txt" "check: the delta excludes a file only the base branch changed"
assert_contains "$output" "delta feature.txt" "check: the delta still names the branch's own edit"
assert_contains "$output" "receipt: stale diff-changed" "check: reports diff-changed after the base merge"

# --- a fingerprint argument never names a path outside the store ----------
REPO6="$(feature_repo)"
STORE6="$(git -C "$REPO6" rev-parse --path-format=absolute --git-common-dir)/quality-receipts"
mkdir -p "$STORE6"
printf '{"verdict": "HOLD"}\n' > "$BOX/escape.json"
assert_refused 2 "receipt: not a fingerprint" "approve: a non-hex fingerprint exits 2 and names the refused fingerprint" -- \
  receipt_in "$REPO6" approve --fingerprint "../../../escape" --by mallory
assert_file_not_matches "$BOX/escape.json" "mallory" "approve: never writes outside the receipt store"

finish
