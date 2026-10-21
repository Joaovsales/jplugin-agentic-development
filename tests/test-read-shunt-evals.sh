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
#      fires on it look correct. Each scaffold is run into its own temp dir and
#      measured, so the size a case promises is the size it produces.
#
#   4. DETERMINISM — fixtures come from a fixed seed. Two runs of one scaffold
#      must be byte-identical, or two arms of the suite read different inputs.
#
#   5. RUBRIC — the judge's axes are written before any run, so the rubric file
#      must exist and name all four of them.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Python probes must not leave __pycache__ in the tree (tests/ checks parity).
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUTF8=1

SUITE="$REPO/evals/read-shunt"

LARGE_CASES="billing-client-zero-total nightly-pipeline-failure catalog-currency-field orders-extract-tax pipeline-checks-intermittent settings-loader-port load-record-callers changelog-release-notes"
CONTROL_CASES="readme-typo timeparse-coverage ratelimit-clock-skew"
ALL_CASES="$LARGE_CASES $CONTROL_CASES"

TMP="$(mktemp -d)"
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf '  FAIL could not create fixture dir\n'; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# measure DIR — print "<total bytes> <max line count in one file> <file count>".
measure() {
  "$TEST_PYTHON" - "$1" <<'PY'
import os, sys
root = sys.argv[1]
total = maxlines = files = 0
for d, _, names in os.walk(root):
    for n in names:
        p = os.path.join(d, n)
        data = open(p, "rb").read()
        total += len(data)
        files += 1
        maxlines = max(maxlines, data.count(b"\n"))
print(total, maxlines, files)
PY
}

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
assert_eq "present" "$([ -d "$SUITE" ] && echo present || echo missing)" "evals/read-shunt exists"
assert_eq "present" "$([ -f "$SUITE/fixture_gen.py" ] && echo present || echo missing)" "the shared seeded generator exists"
assert_eq "present" "$([ -f "$SUITE/rubric.md" ] && echo present || echo missing)" "the judge rubric file exists"
assert_eq "present" "$([ -f "$SUITE/README.md" ] && echo present || echo missing)" "the run instructions exist"

found="$(find "$SUITE" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
want="$(printf '%s\n' $ALL_CASES | sort | tr '\n' ' ')"
assert_eq "$want" "$found" "exactly the eleven named case directories"

for c in $ALL_CASES; do
  d="$SUITE/$c"
  for f in prompt.md case.yaml fixture.sh; do
    assert_eq "present" "$([ -f "$d/$f" ] && echo present || echo missing)" "$c: $f exists"
  done
  graders="$(find "$d/graders" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "yes" "$([ "${graders:-0}" -ge 1 ] && echo yes || echo no)" "$c: at least one grader (a case without one fails to load)"
  assert_eq "present" "$([ -f "$d/graders/judge.md" ] && echo present || echo missing)" "$c: carries the llm grader"
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
  read -r bytes maxlines files <<EOF
$(measure "$out")
EOF
  assert_eq "yes" "$([ "${files:-0}" -ge 1 ] && echo yes || echo no)" "$c: scaffold wrote at least one file"
  case " $LARGE_CASES " in
    *" $c "*)
      assert_eq "yes" "$([ "${bytes:-0}" -gt 32768 ] && echo yes || echo no)" "$c: fixture over 32 KB (got ${bytes:-0})"
      ;;
    *)
      assert_eq "yes" "$([ "${bytes:-999999}" -lt 32768 ] && echo yes || echo no)" "$c: control fixture under 32 KB (got ${bytes:-?})"
      assert_eq "yes" "$([ "${maxlines:-999999}" -lt 800 ] && echo yes || echo no)" "$c: control file under 800 lines (got ${maxlines:-?})"
      ;;
  esac
  assert_eq "" "$(blind_hits "$out")" "$c: no blinding word in a generated path or file"
done

# Per-case promises the spec makes in prose.
sz() { wc -c < "$1" | tr -d ' '; }
nlines() { wc -l < "$1" | tr -d ' '; }
assert_eq "yes" "$([ "$(nlines "$TMP/nightly-pipeline-failure/ci-run-48213.log")" -ge 20000 ] && echo yes || echo no)" "nightly log has 20K+ lines"
assert_eq "yes" "$([ "$(sz "$TMP/catalog-currency-field/fixtures/catalog.json")" -gt 262144 ] && echo yes || echo no)" "catalog.json over 256 KB"
assert_eq "yes" "$([ "$(nlines "$TMP/billing-client-zero-total/billing_client.py")" -ge 4000 ] && echo yes || echo no)" "billing client is ~5000 lines"
assert_eq "yes" "$([ "$(nlines "$TMP/orders-extract-tax/orders.py")" -ge 2500 ] && echo yes || echo no)" "orders module is ~3000 lines"
assert_eq "yes" "$([ "$(nlines "$TMP/pipeline-checks-intermittent/verify_pipeline.py")" -ge 1800 ] && echo yes || echo no)" "pipeline checks are ~2000 lines"
assert_eq "yes" "$([ "$(nlines "$TMP/settings-loader-port/reference/settings_loader.js")" -ge 1300 ] && echo yes || echo no)" "settings loader is ~1500 lines"
assert_eq "yes" "$([ "$(nlines "$TMP/changelog-release-notes/CHANGELOG.md")" -ge 800 ] && echo yes || echo no)" "changelog is ~900 lines"
assert_eq "40" "$(ls "$TMP/load-record-callers/svc" | grep -c '^mod_[0-9][0-9]\.py$')" "forty svc modules"
assert_eq "23" "$(grep -l 'fetch_record' "$TMP"/load-record-callers/svc/mod_*.py | wc -l | tr -d ' ')" "23 modules still call the old name"
assert_eq "yes" "$([ "$(sz "$TMP/ratelimit-clock-skew/ratelimit.py")" -ge 20000 ] && echo yes || echo no)" "ratelimit.py is ~25 KB"
assert_eq "60" "$(nlines "$TMP/readme-typo/README.md")" "README has 60 lines"
assert_file_contains "$TMP/readme-typo/README.md" "recieve" "README carries the typo"
assert_file_contains "$TMP/nightly-pipeline-failure/ci-run-48213.log" "KeyError: 'release_tag'" "the log carries its one traceback"
assert_eq "1" "$(grep -c '^Traceback' "$TMP/nightly-pipeline-failure/ci-run-48213.log")" "exactly one traceback in the log"
assert_file_contains "$TMP/billing-client-zero-total/billing_client.py" 'payload.get("total", 0)' "billing client carries the bug"
# A fixture that already satisfies its own outcome grader would pass a run that did nothing.
assert_eq "0" "$(grep -c 'total_cents' "$TMP/billing-client-zero-total/billing_client.py")" "billing client does not yet read total_cents"
assert_eq "0" "$(grep -c 'currency' "$TMP/catalog-currency-field/models.py")" "models.py has no currency field yet"
assert_eq "0" "$(grep -c 'tax_for' "$TMP/orders-extract-tax/orders.py")" "orders.py has no tax_for yet"
assert_eq "0" "$(grep -c 'checks' "$TMP/timeparse-coverage/timeparse.py")" "timeparse fixture ships no checks yet"
assert_eq "no" "$([ -e "$TMP/settings-loader-port/settings_loader.py" ] && echo yes || echo no)" "no Python port ships with the loader"
assert_eq "no" "$([ -e "$TMP/changelog-release-notes/RELEASE_NOTES.md" ] && echo yes || echo no)" "no release notes ship with the changelog"
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
