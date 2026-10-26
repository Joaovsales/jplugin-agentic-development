#!/bin/bash
# tests/test-read-shunt-evals.sh — the read-shunt suite cannot lie about its own inputs.
#
# evals/read-shunt/ is a `claude plugin eval` suite: eleven cases, eight that
# force a large read and three controls under the threshold. A paid run costs
# real money and a flawed fixture wastes all of it, so every property the
# measurement depends on is pinned here, before any run:
#
#   1. SHAPE — eleven case directories, each loadable by the runner. A case
#      with no grader fails to load; one with no scaffold has no fixture; a
#      missing tag silently moves a case between the large and control arms.
#
#   2. BLINDING — the candidate must never learn it is measured. The /eval
#      blinding words may not appear in a case name, a prompt, a scaffold, or
#      any path or file the scaffold writes into the candidate's workspace; and
#      a prompt may not mention size, context, sub-agents, cost or measurement.
#      A prompt that says "this file is huge" teaches the candidate to behave
#      differently from a real user.
#
#   3. PROMISED SIZES — a "large" case whose generated fixture falls under 32 KB
#      measures nothing, and a control that creeps over it makes a gate that
#      fires on it look correct. Each case's sizes are one Promise row in
#      fixture_gen.CASES, checked by the generator against what it wrote; the
#      suite runs every scaffold into its own temp dir, so exit 0 is a met row.
#
#   4. DETERMINISM — fixtures come from a fixed seed. Two runs of one scaffold
#      must be byte-identical, or two arms of the suite read different inputs.
#
#   5. RUBRIC — the judge's axes are written before any run, so the rubric file
#      must exist and name all four of them.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SUITE="$REPO/evals/read-shunt"

ALL_CASES="billing-client-zero-total nightly-pipeline-failure catalog-currency-field orders-extract-tax pipeline-checks-intermittent settings-loader-port load-record-callers changelog-release-notes readme-typo timeparse-coverage ratelimit-clock-skew"

# A case's arm is its Promise row's: a floor above the threshold is a large case.
arm_cases() {
  "$TEST_PYTHON" - "$SUITE" "$1" <<'PY' | tr -d '\r'
import sys
sys.path.insert(0, sys.argv[1])
import fixture_gen as fg
arm = lambda promise: "large" if (promise.total_bytes.min or 0) > fg.LARGE_BYTES else "control"
print(" ".join(sorted(c for c, (_, _, promise) in fg.CASES.items() if arm(promise) == sys.argv[2])))
PY
}
LARGE_CASES="$(arm_cases large)"
CONTROL_CASES="$(arm_cases control)"

TMP="$(fixture_dir)"

# count_files DIR — print the number of files under DIR.
count_files() { find "$1" -type f | wc -l | tr -d ' '; }

# blind_hits DIR — one line per blinding word found in a generated path or file.
blind_hits() {
  "$TEST_PYTHON" - "$1" <<'PY'
import os, re, sys
root = sys.argv[1]
words = re.compile(r"(?<![A-Za-z0-9_])(eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena)(?![A-Za-z0-9_])", re.I)
for d, dirs, names in os.walk(root):
    for n in dirs + names:
        rel = os.path.relpath(os.path.join(d, n), root)
        m = words.search(rel)
        if m:
            print("path:%s:%s" % (rel, m.group(0)))
    for n in names:
        p = os.path.join(d, n)
        text = open(p, encoding="utf-8", errors="replace").read()
        m = words.search(text)
        if m:
            print("content:%s:%s" % (os.path.relpath(p, root), m.group(0)))
PY
}

# static_hits — blinding words in case names, prompt bodies and scaffold scripts.
static_hits() {
  "$TEST_PYTHON" - "$SUITE" <<'PY'
import os, re, sys
suite = sys.argv[1]
words = re.compile(r"(?<![A-Za-z0-9_])(eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena)(?![A-Za-z0-9_])", re.I)
meta = re.compile(r"(?<![A-Za-z0-9_])(size|sizes|large|huge|big|context|sub-?agents?|cost|costs|measure[sd]?|measuring)(?![A-Za-z0-9_])", re.I)
for case in sorted(os.listdir(suite)):
    cdir = os.path.join(suite, case)
    if not os.path.isdir(cdir):
        continue
    m = words.search(case)
    if m:
        print("name:%s:%s" % (case, m.group(0)))
    for fname in ("prompt.md", "fixture.sh"):
        p = os.path.join(cdir, fname)
        if os.path.exists(p):
            m = words.search(open(p, encoding="utf-8").read())
            if m:
                print("%s:%s:%s" % (fname, case, m.group(0)))
    p = os.path.join(cdir, "prompt.md")
    if os.path.exists(p):
        text = open(p, encoding="utf-8").read()
        body = text.split("---", 2)[2] if text.startswith("---") else text
        m = meta.search(body)
        if m:
            print("meta:%s:%s" % (case, m.group(0)))
PY
}

# --- 1. shape ----------------------------------------------------------------
assert_file_exists "$SUITE" "evals/read-shunt exists"
assert_file_exists "$SUITE/fixture_gen.py" "the shared seeded generator exists"
assert_file_exists "$SUITE/rubric.md" "the judge rubric file exists"
assert_file_exists "$SUITE/README.md" "the run instructions exist"

# `results/` is where `claude plugin eval` writes each run (gitignored), not a case.
found="$(find "$SUITE" -mindepth 1 -maxdepth 1 -type d ! -name results -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
want="$(printf '%s\n' $ALL_CASES | sort | tr '\n' ' ')"
assert_eq "$want" "$found" "exactly the eleven named case directories"
assert_eq "$want" "$(printf '%s\n' $LARGE_CASES $CONTROL_CASES | sort | tr '\n' ' ')" "fixture_gen.CASES names exactly those eleven cases"

for c in $ALL_CASES; do
  d="$SUITE/$c"
  for f in prompt.md case.yaml fixture.sh; do
    assert_file_exists "$d/$f" "$c: $f exists"
  done
  graders="$(find "$d/graders" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_true "$c: at least one grader (a case without one fails to load)" -- [ "${graders:-0}" -ge 1 ]
  assert_file_exists "$d/graders/judge.md" "$c: carries the llm grader"
  assert_file_contains "$d/graders/judge.md" "type: llm" "$c: judge.md is an llm grader"
  assert_file_contains "$d/case.yaml" "scaffold_script: fixture.sh" "$c: case.yaml names its scaffold"
  assert_file_contains "$d/case.yaml" "name: $c" "$c: case.yaml name matches the directory"
  assert_file_contains "$d/prompt.md" "max_turns:" "$c: prompt.md frontmatter sets max_turns"
  assert_file_contains "$d/prompt.md" "runs: 1" "$c: one run per case; the runner's --runs overrides"
  assert_file_contains "$d/prompt.md" "push" "$c: the prompt carries the no-push clause"
  assert_file_contains "$d/fixture.sh" "fixture_gen.py" "$c: scaffold is the thin call to the shared generator"
done

for c in $LARGE_CASES; do
  assert_file_matches "$SUITE/$c/case.yaml" "^tags: \[large\]" "$c: tagged large"
  assert_file_contains "$SUITE/$c/graders/parent-read.md" "type: tool_used" "$c: parent-read indicator grader present"
  assert_file_contains "$SUITE/$c/graders/parent-read.md" "tool: Read" "$c: parent-read indicator watches Read"
done
for c in $CONTROL_CASES; do
  assert_file_matches "$SUITE/$c/case.yaml" "^tags: \[control\]" "$c: tagged control"
done
assert_eq "8" "$(grep -l '^tags: \[large\]' "$SUITE"/*/case.yaml 2>/dev/null | wc -l | tr -d ' ')" "eight large cases"
assert_eq "3" "$(grep -l '^tags: \[control\]' "$SUITE"/*/case.yaml 2>/dev/null | wc -l | tr -d ' ')" "three controls"

# --- 2. blinding (static) ----------------------------------------------------
assert_eq "" "$(static_hits)" "no blinding word in a case name, prompt or scaffold; no meta cue in a prompt"

# --- 3. promised sizes, 4. blinding of generated files, determinism ---------------
for c in $ALL_CASES; do
  out="$TMP/$c"
  mkdir -p "$out"
  if ! (cd "$out" && bash "$SUITE/$c/fixture.sh"); then
    assert_eq "exit 0" "scaffold failed" "$c: scaffold exits 0"
    continue
  fi
  assert_true "$c: scaffold wrote at least one file" -- [ "$(count_files "$out")" -ge 1 ]
  assert_eq "" "$(blind_hits "$out")" "$c: no blinding word in a generated path or file"
done

# The sizes each case promises are the Promise rows of fixture_gen.CASES; a
# scaffold that exits 0 has met its row. A row its output breaks must fail the
# scaffold, naming the case and the bound.
err="$("$TEST_PYTHON" - "$SUITE" "$TMP/broken-promise" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import fixture_gen as fg
seed, generate, _ = fg.CASES["readme-typo"]
fg.CASES["readme-typo"] = (seed, generate, fg.Promise(total_bytes=fg.Bound(max=100)))
sys.exit(fg.main(["readme-typo", "--out", sys.argv[2]]))
PY
)"; rc=$?
assert_eq "1" "$rc" "promise: a scaffold whose output breaks its row exits 1"
assert_contains "$err" "readme-typo" "promise: the message names the case"
assert_contains "$err" "total_bytes max 100" "promise: the message names the quantity, the broken side and its bound"
out="$("$TEST_PYTHON" - "$SUITE" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import fixture_gen as fg
print("sides", fg.Bound(max=100).broken_side(150), fg.Bound(min=4).broken_side(4), fg.Bound(min=4000).broken_side(3))
PY
)"
assert_contains "$out" "sides ('max', 100) None ('min', 4000)" "promise: Bound.broken_side() names the side and its bound as data, and None inside the interval"
bad="$("$TEST_PYTHON" - "$SUITE" "$CONTROL_CASES" <<'PY' | tr -d '\r'
import sys
sys.path.insert(0, sys.argv[1])
import fixture_gen as fg
print(" ".join(c for c in sys.argv[2].split() if not (fg.CASES[c][2].total_bytes.max or fg.LARGE_BYTES) < fg.LARGE_BYTES))
PY
)"
assert_eq "" "$bad" "promise: every control's row caps its total below the threshold"
assert_eq "40" "$(ls "$TMP/load-record-callers/svc" | grep -c '^mod_[0-9][0-9]\.py$')" "forty svc modules"
assert_eq "23" "$(grep -l 'fetch_record' "$TMP"/load-record-callers/svc/mod_*.py | wc -l | tr -d ' ')" "23 modules still call the old name"
assert_file_contains "$TMP/readme-typo/README.md" "recieve" "README carries the typo"
assert_file_contains "$TMP/nightly-pipeline-failure/ci-run-48213.log" "KeyError: 'release_tag'" "the log carries its one traceback"
assert_eq "1" "$(grep -c '^Traceback' "$TMP/nightly-pipeline-failure/ci-run-48213.log")" "exactly one traceback in the log"
assert_file_contains "$TMP/billing-client-zero-total/billing_client.py" 'payload.get("total", 0)' "billing client carries the bug"
# A fixture that already satisfies its own outcome grader would pass a run that did nothing.
assert_eq "0" "$(grep -c 'total_cents' "$TMP/billing-client-zero-total/billing_client.py")" "billing client does not yet read total_cents"
assert_eq "0" "$(grep -c 'currency' "$TMP/catalog-currency-field/models.py")" "models.py has no currency field yet"
assert_eq "0" "$(grep -c 'tax_for' "$TMP/orders-extract-tax/orders.py")" "orders.py has no tax_for yet"
assert_eq "0" "$(grep -c 'checks' "$TMP/timeparse-coverage/timeparse.py")" "timeparse fixture ships no checks yet"
assert_file_absent "$TMP/settings-loader-port/settings_loader.py" "no Python port ships with the loader"
assert_file_absent "$TMP/changelog-release-notes/RELEASE_NOTES.md" "no release notes ship with the changelog"
assert_eq "1" "$(grep -c 'fetch_record' "$TMP/load-record-callers/svc/mod_07.py" | awk '{print ($1>0)}')" "mod_07.py still uses the old name"
assert_eq "0" "$(grep -c 'fetch_record' "$TMP/load-record-callers/svc/mod_12.py")" "mod_12.py does not use the old name"

# Determinism: a second run of one scaffold is byte-identical to the first.
digest() {
  "$TEST_PYTHON" - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
h = hashlib.sha256()
for d, dirs, names in os.walk(root):
    dirs.sort()
    for n in sorted(names):
        p = os.path.join(d, n)
        h.update(os.path.relpath(p, root).replace(os.sep, "/").encode())
        h.update(open(p, "rb").read())
print(h.hexdigest())
PY
}
for c in nightly-pipeline-failure load-record-callers; do
  again="$TMP/again-$c"
  mkdir -p "$again"
  (cd "$again" && bash "$SUITE/$c/fixture.sh")
  assert_eq "$(digest "$TMP/$c")" "$(digest "$again")" "$c: a second scaffold run is byte-identical"
done

# The tree stays clean of interpreter droppings (the .agents/ parity test cares).
assert_eq "" "$(find "$SUITE" -name '__pycache__' | head -1)" "no __pycache__ under evals/read-shunt"

# --- 5. rubric and run instructions -----------------------------------------
rub="$SUITE/rubric.md"
assert_file_contains "$rub" "Patch correctness" "rubric: axis 1"
assert_file_contains "$rub" "Diff minimality" "rubric: axis 2"
assert_file_contains "$rub" "Re-derivation" "rubric: axis 3"
assert_file_contains "$rub" "Unsupported claims" "rubric: axis 4"
assert_file_contains "$rub" "both orders" "rubric: the judge sees both orders"
assert_file_contains "$rub" "sanitised" "rubric: the judge sees sanitised labels"
assert_file_contains "$SUITE/README.md" "--scaffold" "README: --scaffold is mandatory"
assert_file_contains "$SUITE/README.md" "--max-cost-usd" "README: a cost ceiling is mandatory"

finish
