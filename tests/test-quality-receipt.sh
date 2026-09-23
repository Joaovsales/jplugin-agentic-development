#!/bin/bash
# tests/test-quality-receipt.sh — .agents/skills/quality-gate/scripts/receipt.py
# (specs/quality-receipt-closure.md AC 1-3): fingerprint the tasks-excluded
# diff between a branch's merge-base and its working tree, mint a
# quality-receipt/1 whose verdict is derived from findings and never accepted
# as input, and check/approve a stored receipt against the current tree and
# policy.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY="$TEST_PYTHON"
RECEIPT="$REPO/.agents/skills/quality-gate/scripts/receipt.py"

BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT
[ -n "$BOX" ] && [ -d "$BOX" ] || { printf 'mktemp -d failed\n' >&2; exit 1; }

receipt() { "$PY" "$RECEIPT" "$@"; }

# new_repo <dir> — a fixture repo on branch "feature" with one commit on
# "main" and one further commit on "feature", so HEAD != the base ref and
# merge-base is the "main" tip.
new_repo() {
  dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name t
  git -C "$dir" config user.email t@t
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
  printf 'base\n' > "$dir/base.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -q -m init
  git -C "$dir" checkout -q -b feature
  printf 'feature\n' > "$dir/feature.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -q -m feature
}

fp_field() { # fp_field <n> <fingerprint-output>
  printf '%s\n' "$2" | awk -v n="$1" '{print $n}'
}

# ===========================================================================
printf '\n--- fingerprint ---\n'
# ===========================================================================

REPO1="$BOX/repo1"
new_repo "$REPO1"

OUT="$(cd "$REPO1" && receipt fingerprint --base main)"
CODE=$?
assert_eq "0" "$CODE" "fingerprint: exits 0"
WORDS=$(printf '%s' "$OUT" | wc -w | tr -d ' ')
assert_eq "3" "$WORDS" "fingerprint: prints merge-base, tree and fingerprint"

EXPECT_BASE="$(cd "$REPO1" && git merge-base HEAD main)"
assert_eq "$EXPECT_BASE" "$(fp_field 1 "$OUT")" "fingerprint: first field is the merge-base"

FP0="$(fp_field 3 "$OUT")"

# --- unchanged by tasks/** ------------------------------------------------
mkdir -p "$REPO1/tasks"
printf 'notes\n' > "$REPO1/tasks/notes.md"
OUT2="$(cd "$REPO1" && receipt fingerprint --base main)"
assert_eq "$FP0" "$(fp_field 3 "$OUT2")" "fingerprint: an untracked file under tasks/** does not change it"

git -C "$REPO1" add -A
git -C "$REPO1" -c commit.gpgsign=false commit -q -m "tasks bookkeeping"
OUT3="$(cd "$REPO1" && receipt fingerprint --base main)"
assert_eq "$FP0" "$(fp_field 3 "$OUT3")" "fingerprint: committing the same non-tasks tree does not change it"

# --- unchanged by diff config --------------------------------------------
git -C "$REPO1" config diff.noprefix true
git -C "$REPO1" config diff.external "echo fake"
OUT4="$(cd "$REPO1" && receipt fingerprint --base main)"
assert_eq "$FP0" "$(fp_field 3 "$OUT4")" "fingerprint: diff.noprefix/diff.external config does not change it"
git -C "$REPO1" config --unset diff.noprefix
git -C "$REPO1" config --unset diff.external

# --- changed by a tracked edit --------------------------------------------
printf 'feature changed\n' > "$REPO1/feature.txt"
OUT5="$(cd "$REPO1" && receipt fingerprint --base main)"
assert_not_contains "$FP0" "$(fp_field 3 "$OUT5")" "fingerprint: a tracked edit changes it"
git -C "$REPO1" add -A
git -C "$REPO1" -c commit.gpgsign=false commit -q -m "edit feature.txt"
FP1="$(fp_field 3 "$OUT5")"

# --- changed by an untracked file -----------------------------------------
printf 'new\n' > "$REPO1/untracked.txt"
OUT6="$(cd "$REPO1" && receipt fingerprint --base main)"
assert_not_contains "$FP1" "$(fp_field 3 "$OUT6")" "fingerprint: an untracked file outside tasks/** changes it"
rm -f "$REPO1/untracked.txt"

# --- changed by a specs/ edit ---------------------------------------------
mkdir -p "$REPO1/specs"
printf 'spec\n' > "$REPO1/specs/thing.md"
OUT7="$(cd "$REPO1" && receipt fingerprint --base main)"
assert_not_contains "$FP1" "$(fp_field 3 "$OUT7")" "fingerprint: an edit under specs/ changes it (stays in scope)"
rm -rf "$REPO1/specs"

# --- base resolution: omitted, falls back to local main -------------------
OUT8="$(cd "$REPO1" && receipt fingerprint)"
CODE=$?
assert_eq "0" "$CODE" "fingerprint: --base omitted resolves a default"
EXPECT_BASE_LOCAL="$(cd "$REPO1" && git merge-base HEAD main)"
assert_eq "$EXPECT_BASE_LOCAL" "$(fp_field 1 "$OUT8")" "fingerprint: omitted --base resolves local main when no remote exists"

# --- base resolution: origin/master preferred when present ----------------
git -C "$REPO1" update-ref refs/remotes/origin/master "$(git -C "$REPO1" rev-parse main)"
OUT9="$(cd "$REPO1" && receipt fingerprint)"
EXPECT_BASE_ORIGIN="$(cd "$REPO1" && git merge-base HEAD refs/remotes/origin/master)"
assert_eq "$EXPECT_BASE_ORIGIN" "$(fp_field 1 "$OUT9")" "fingerprint: omitted --base prefers origin/master over local main"

# ===========================================================================
printf '\n--- write ---\n'
# ===========================================================================

REPO2="$BOX/repo2"
new_repo "$REPO2"
export GIT_COMMON_DIR_2="$(cd "$REPO2" && git rev-parse --path-format=absolute --git-common-dir)"

make_outcome() { # make_outcome <file> <tree> <must-fix?> <should-fix-count> <design-verdict> <tests-exit> <scope-json> <verdict-lie>
  file="$1"; tree="$2"; mustfix="$3"; shouldfix="$4"; design="$5"; texit="$6"; scope="$7"; lie="$8"
  findings="[]"
  entries=()
  if [ "$mustfix" = "yes" ]; then
    entries+=('{"severity":"MUST-FIX","confidence":100,"autofix_class":"manual","owner":"human","location":"x.py:1","summary":"bad"}')
  fi
  i=0
  while [ "$i" -lt "$shouldfix" ]; do
    entries+=('{"severity":"SHOULD-FIX","confidence":75,"autofix_class":"manual","owner":"human","location":"x.py:2","summary":"minor"}')
    i=$((i + 1))
  done
  joined=""
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

FP_OUT="$(cd "$REPO2" && receipt fingerprint --base main)"
TREE2="$(fp_field 2 "$FP_OUT")"
FP2="$(fp_field 3 "$FP_OUT")"
STORE2="$GIT_COMMON_DIR_2/quality-receipts"

# --- valid GO --------------------------------------------------------------
make_outcome "$BOX/outcome-go.json" "$TREE2" no 0 GO 0 '"full"' ""
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-go.json")"
CODE=$?
assert_eq "0" "$CODE" "write: a clean outcome exits 0"
assert_contains "$OUT" "receipt: written ${FP2:0:8} verdict GO policy qg1-" "write: prints the written line with verdict GO"
assert_file_contains "$STORE2/$FP2.json" "\"schema\": \"quality-receipt/1\"" "write: stores the schema field"
assert_file_contains "$STORE2/$FP2.json" "\"verdict\": \"GO\"" "write: stores the derived verdict"
assert_file_contains "$STORE2/$FP2.json" "\"fingerprint\": \"$FP2\"" "write: stores its own fingerprint"
BRANCH_SAN="$(cd "$REPO2" && git rev-parse --abbrev-ref HEAD | tr '/' '-')"
assert_eq "1" "$( [ -f "$STORE2/branch-$BRANCH_SAN.json" ] && echo 1 || echo 0 )" "write: stores the branch pointer"
assert_file_contains "$STORE2/branch-$BRANCH_SAN.json" "\"fingerprint\": \"$FP2\"" "write: pointer names this fingerprint"

# --- MUST-FIX forces STOP regardless of a supplied verdict -----------------
make_outcome "$BOX/outcome-mustfix.json" "$TREE2" yes 0 GO 0 '"full"' "GO"
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-mustfix.json")"
assert_contains "$OUT" "verdict STOP" "write: an unresolved MUST-FIX forces STOP"
assert_file_contains "$STORE2/$FP2.json" "\"verdict\": \"STOP\"" "write: a supplied verdict of GO is ignored in favor of STOP"

# --- design STOP forces STOP -------------------------------------------
make_outcome "$BOX/outcome-designstop.json" "$TREE2" no 0 STOP 0 '"full"' ""
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-designstop.json")"
assert_contains "$OUT" "verdict STOP" "write: design_verdict STOP forces STOP"

# --- red tests forces STOP -------------------------------------------------
make_outcome "$BOX/outcome-redtests.json" "$TREE2" no 0 GO 1 '"full"' ""
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-redtests.json")"
assert_contains "$OUT" "verdict STOP" "write: tests.exit != 0 forces STOP"

# --- >3 unresolved SHOULD-FIX forces HOLD ----------------------------------
make_outcome "$BOX/outcome-hold4.json" "$TREE2" no 4 GO 0 '"full"' ""
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-hold4.json")"
assert_contains "$OUT" "verdict HOLD" "write: more than 3 unresolved SHOULD-FIX forces HOLD"

# --- exactly 3 SHOULD-FIX stays GO -----------------------------------------
make_outcome "$BOX/outcome-should3.json" "$TREE2" no 3 GO 0 '"full"' ""
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-should3.json")"
assert_contains "$OUT" "verdict GO" "write: exactly 3 unresolved SHOULD-FIX stays GO"

# --- design HOLD forces HOLD ------------------------------------------------
make_outcome "$BOX/outcome-designhold.json" "$TREE2" no 0 HOLD 0 '"full"' ""
OUT="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-designhold.json")"
assert_contains "$OUT" "verdict HOLD" "write: design_verdict HOLD forces HOLD"

# --- schema failure: nothing written, exit 2 -------------------------------
cat > "$BOX/outcome-bad-schema.json" <<'EOF'
{"reviewers": [], "unresolved": [], "tests": {"exit": 0}, "design_verdict": "GO", "scope": "full"}
EOF
BEFORE_COUNT=$(ls "$STORE2" | wc -l | tr -d ' ')
ERR="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-bad-schema.json" 2>&1 1>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "write: a schema failure exits 2"
assert_contains "$ERR" "receipt: invalid outcome" "write: names the refusal"
AFTER_COUNT=$(ls "$STORE2" | wc -l | tr -d ' ')
assert_eq "$BEFORE_COUNT" "$AFTER_COUNT" "write: a schema failure writes nothing"

# --- tests.tree mismatch: exit 2, nothing written --------------------------
make_outcome "$BOX/outcome-wrongtree.json" "0000000000000000000000000000000000000000000000000000000000000000" no 0 GO 0 '"full"' ""
ERR="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-wrongtree.json" 2>&1 1>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "write: a tests.tree mismatch exits 2"
assert_contains "$ERR" "tests.tree" "write: names the tree mismatch"

# --- delta scope with no stored parent: exit 2, nothing written ------------
make_outcome "$BOX/outcome-delta-noparent.json" "$TREE2" no 0 GO 0 '["x.py"]' ""
ERR="$(cd "$REPO2" && receipt write --outcome "$BOX/outcome-delta-noparent.json" --parent deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2>&1 1>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "write: a delta scope naming an unstored parent exits 2"
assert_contains "$ERR" "parent" "write: names the missing parent"

# --- delta receipt: SHOULD-FIX carried back to the nearest approved HOLD ---
REPO2B="$BOX/repo2b"
new_repo "$REPO2B"
FP_OUT_B="$(cd "$REPO2B" && receipt fingerprint --base main)"
TREE2B="$(fp_field 2 "$FP_OUT_B")"
FP2B="$(fp_field 3 "$FP_OUT_B")"
GIT_COMMON_2B="$(cd "$REPO2B" && git rev-parse --path-format=absolute --git-common-dir)"
STORE2B="$GIT_COMMON_2B/quality-receipts"

make_outcome "$BOX/outcome-parent-hold.json" "$TREE2B" no 2 HOLD 0 '"full"' ""
cd "$REPO2B" && receipt write --outcome "$BOX/outcome-parent-hold.json" >/dev/null; cd "$REPO" || exit 1
assert_file_contains "$STORE2B/$FP2B.json" "\"verdict\": \"HOLD\"" "write: parent receipt with 2 unresolved SHOULD-FIX is HOLD"
cd "$REPO2B" && receipt approve --fingerprint "$FP2B" --by tester >/dev/null; cd "$REPO" || exit 1
assert_file_contains "$STORE2B/$FP2B.json" "\"hold_approved_by\": \"tester\"" "approve: records the approver on the parent HOLD"

printf 'delta change\n' > "$REPO2B/feature.txt"
git -C "$REPO2B" add -A
git -C "$REPO2B" -c commit.gpgsign=false commit -q -m "delta change"
FP_OUT_B2="$(cd "$REPO2B" && receipt fingerprint --base main)"
TREE2B2="$(fp_field 2 "$FP_OUT_B2")"
FP2B2="$(fp_field 3 "$FP_OUT_B2")"
make_outcome "$BOX/outcome-delta-carry.json" "$TREE2B2" no 2 GO 0 '["feature.txt"]' ""
OUT="$(cd "$REPO2B" && receipt write --outcome "$BOX/outcome-delta-carry.json" --parent "$FP2B")"
assert_contains "$OUT" "verdict HOLD" "write: a delta's own 2 SHOULD-FIX plus the approved-HOLD parent's 2 exceeds 3, forcing HOLD"

# ===========================================================================
printf '\n--- check and approve ---\n'
# ===========================================================================

REPO3="$BOX/repo3"
new_repo "$REPO3"
GIT_COMMON_3="$(cd "$REPO3" && git rev-parse --path-format=absolute --git-common-dir)"
STORE3="$GIT_COMMON_3/quality-receipts"

OUT="$(cd "$REPO3" && receipt check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: a tree with no receipt and no pointer is stale missing"
assert_contains "$OUT" "receipt: stale missing" "check: names the reason missing"

FP_OUT3="$(cd "$REPO3" && receipt fingerprint --base main)"
TREE3="$(fp_field 2 "$FP_OUT3")"
FP3="$(fp_field 3 "$FP_OUT3")"
make_outcome "$BOX/outcome3-go.json" "$TREE3" no 0 GO 0 '"full"' ""
cd "$REPO3" && receipt write --outcome "$BOX/outcome3-go.json" >/dev/null; cd "$REPO" || exit 1

OUT="$(cd "$REPO3" && receipt check --base main)"
CODE=$?
assert_eq "0" "$CODE" "check: a valid GO receipt exits 0"
assert_contains "$OUT" "receipt: valid GO ${FP3:0:8} policy qg1-" "check: names the valid GO line"

# --- diff-changed: a new tree with the branch pointer naming a valid parent -
printf 'diff changed\n' > "$REPO3/feature.txt"
git -C "$REPO3" add -A
git -C "$REPO3" -c commit.gpgsign=false commit -q -m "diff change"
OUT="$(cd "$REPO3" && receipt check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: an unreviewed new tree is stale"
assert_contains "$OUT" "receipt: stale diff-changed parent ${FP3:0:8}" "check: diff-changed names the parent"
assert_contains "$OUT" "delta feature.txt" "check: diff-changed names the changed path"

# write a HOLD outcome for this new tree, then check reports stale verdict HOLD
FP_OUT3B="$(cd "$REPO3" && receipt fingerprint --base main)"
TREE3B="$(fp_field 2 "$FP_OUT3B")"
FP3B="$(fp_field 3 "$FP_OUT3B")"
make_outcome "$BOX/outcome3-hold.json" "$TREE3B" no 4 GO 0 '"full"' ""
cd "$REPO3" && receipt write --outcome "$BOX/outcome3-hold.json" >/dev/null; cd "$REPO" || exit 1
OUT="$(cd "$REPO3" && receipt check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: an unapproved HOLD receipt is stale"
assert_contains "$OUT" "receipt: stale verdict HOLD" "check: names the reason verdict HOLD"

# --- approve refuses a non-HOLD receipt ------------------------------------
ERR="$(cd "$REPO3" && receipt approve --fingerprint "$FP3" --by tester 2>&1 1>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "approve: refuses a GO receipt"
assert_contains "$ERR" "only HOLD can be approved" "approve: names the refusal"

ERR="$(cd "$REPO3" && receipt approve --fingerprint deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef --by tester 2>&1 1>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "approve: refuses an unknown fingerprint"

# --- approve makes the HOLD receipt valid and a valid chain link ----------
cd "$REPO3" && receipt approve --fingerprint "$FP3B" --by tester >/dev/null; cd "$REPO" || exit 1
OUT="$(cd "$REPO3" && receipt check --base main)"
CODE=$?
assert_eq "0" "$CODE" "check: an approved HOLD receipt is valid"
assert_contains "$OUT" "receipt: valid HOLD-approved ${FP3B:0:8}" "check: names the approved HOLD line"

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
OUT="$(cd "$REPO3" && receipt check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: a receipt with another schema is stale"
assert_contains "$OUT" "receipt: stale schema" "check: names the reason schema"
cp "$BOX/backup-schema.json" "$STORE3/$FP3B.json"

# --- policy-changed: a copied skill tree with one policy file edited -------
COPY_ROOT="$BOX/policy-copy"
mkdir -p "$COPY_ROOT"
cp -r "$REPO/.agents" "$COPY_ROOT/.agents"
RECEIPT_COPY="$COPY_ROOT/.agents/skills/quality-gate/scripts/receipt.py"
printf '\n<!-- test edit -->\n' >> "$COPY_ROOT/.agents/skills/quality-gate/SKILL.md"
OUT="$(cd "$REPO3" && "$PY" "$RECEIPT_COPY" check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: an edited policy file is stale"
assert_contains "$OUT" "receipt: stale policy-changed" "check: names the reason policy-changed"

# --- parent-invalid: corrupt a chain ancestor's policy ---------------------
REPO4="$BOX/repo4"
new_repo "$REPO4"
GIT_COMMON_4="$(cd "$REPO4" && git rev-parse --path-format=absolute --git-common-dir)"
STORE4="$GIT_COMMON_4/quality-receipts"
FP_OUT4="$(cd "$REPO4" && receipt fingerprint --base main)"
TREE4="$(fp_field 2 "$FP_OUT4")"
FP4="$(fp_field 3 "$FP_OUT4")"
make_outcome "$BOX/outcome4-go.json" "$TREE4" no 0 GO 0 '"full"' ""
cd "$REPO4" && receipt write --outcome "$BOX/outcome4-go.json" >/dev/null; cd "$REPO" || exit 1

printf 'child change\n' > "$REPO4/feature.txt"
git -C "$REPO4" add -A
git -C "$REPO4" -c commit.gpgsign=false commit -q -m "child change"
FP_OUT4B="$(cd "$REPO4" && receipt fingerprint --base main)"
TREE4B="$(fp_field 2 "$FP_OUT4B")"
FP4B="$(fp_field 3 "$FP_OUT4B")"
make_outcome "$BOX/outcome4-delta.json" "$TREE4B" no 0 GO 0 '["feature.txt"]' ""
cd "$REPO4" && receipt write --outcome "$BOX/outcome4-delta.json" --parent "$FP4" >/dev/null; cd "$REPO" || exit 1

OUT="$(cd "$REPO4" && receipt check --base main)"
CODE=$?
assert_eq "0" "$CODE" "check: a delta receipt with a valid GO parent is valid"

"$PY" - "$STORE4/$FP4.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["policy"] = "qg1-00000000"
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
OUT="$(cd "$REPO4" && receipt check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: a delta receipt whose parent's policy no longer matches is stale"
assert_contains "$OUT" "receipt: stale parent-invalid" "check: names the reason parent-invalid"

# --- delta after a base merge excludes files only the base changed ---------
REPO5="$BOX/repo5"
new_repo "$REPO5"
GIT_COMMON_5="$(cd "$REPO5" && git rev-parse --path-format=absolute --git-common-dir)"
STORE5="$GIT_COMMON_5/quality-receipts"
FP_OUT5="$(cd "$REPO5" && receipt fingerprint --base main)"
TREE5="$(fp_field 2 "$FP_OUT5")"
FP5="$(fp_field 3 "$FP_OUT5")"
make_outcome "$BOX/outcome5-go.json" "$TREE5" no 0 GO 0 '"full"' ""
cd "$REPO5" && receipt write --outcome "$BOX/outcome5-go.json" >/dev/null; cd "$REPO" || exit 1

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

OUT="$(cd "$REPO5" && receipt check --base main)"
CODE=$?
assert_eq "3" "$CODE" "check: after a base merge plus a branch edit the tree is stale"
assert_not_contains "$OUT" "base-only.txt" "check: the delta excludes a file only the base branch changed"
assert_contains "$OUT" "delta feature.txt" "check: the delta still names the branch's own edit"
assert_contains "$OUT" "receipt: stale diff-changed" "check: reports diff-changed after the base merge"

finish
