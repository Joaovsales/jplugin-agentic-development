#!/bin/bash
# tests/test-lib.sh — tests/lib.sh as a deep module (specs/test-suite-aposd.md
# AC 1, 2, 3): `finish` refuses a file with zero assertions unless it called
# `skip`; `skip` counts and fails the file under REQUIRE_ALL=1; the trailer
# prints passed, failed, xfail and skipped; every failure prints file:line and
# the actual value, truncated at 20 lines; the fixture, capture, verdict and
# declaration primitives behave as documented; the library exports LC_ALL=C,
# PYTHONDONTWRITEBYTECODE=1 and PYTHONUTF8=1 and writes its counters only
# through pass and the failure recorder behind fail.
#
# Each case writes a tiny test file that sources the library, runs it in a
# fresh bash with stdin closed and asserts on its output and exit status, so
# the library's own counters are never confused with the ones under test.
. "$(dirname "$0")/lib.sh"

LIB="$(cd "$(dirname "$0")" && pwd)/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOX="$(fixture_dir)"

# case_file <name> <line>... — a test file under $BOX sourcing the library.
case_file() {
  local name="$1"; shift
  { printf '. "%s"\n' "$LIB"; printf '%s\n' "$@"; } > "$BOX/$name"
  printf '%s\n' "$BOX/$name"
}
# run_case [VAR=value]... <name> <line>... — write the file, run it with the
# library's CI knobs (REQUIRE_ALL, REQUIRE_BROWSER) unset — CI exports them, and
# a case that wants one sets it through a leading VAR=value — and set out and st.
run_case() {
  local -a case_env=()
  while [[ "${1-}" == *=* ]]; do case_env+=("$1"); shift; done
  local f; f="$(case_file "$@")"
  st=0; out="$(cd "$BOX" && env -u REQUIRE_ALL -u REQUIRE_BROWSER "${case_env[@]}" bash "$f" </dev/null 2>&1)" || st=$?
}
# --- § finish: zero assertions, skip, REQUIRE_ALL, the trailer ---------------
run_case zero.sh 'finish'
assert_eq "1" "$st" "finish: a file with zero assertions and no skip exits 1"
assert_contains "$out" "no assertions" "finish: the zero-assertion failure says so"

run_case skipped.sh 'skip "playwright is not importable"' 'finish'
assert_eq "0" "$st" "skip: a skipped file exits 0 without REQUIRE_ALL"
assert_contains "$out" "SKIP playwright is not importable" "skip: prints SKIP and the reason"
assert_contains "$out" "0 passed, 0 failed, 0 xfail, 1 skipped" "skip: the trailer counts the skip"

run_case REQUIRE_ALL=1 required.sh 'skip "no browser"' 'assert_eq a a "still asserts"' 'finish'
assert_eq "1" "$st" "REQUIRE_ALL=1: a skipped file fails"
assert_contains "$out" "REQUIRE_ALL=1" "REQUIRE_ALL=1: the failure names the setting"
assert_contains "$out" "1 passed, 0 failed, 0 xfail, 1 skipped" "REQUIRE_ALL=1: the trailer still counts"

run_case green.sh 'assert_eq a a "one"' 'assert_contains abc b "two"' 'finish'
assert_eq "0" "$st" "trailer: a green file exits 0"
assert_contains "$out" "  -> 2 passed, 0 failed, 0 xfail, 0 skipped" "trailer: passed, failed, xfail and skipped are printed"

run_case red.sh 'assert_eq a a "one"' 'assert_eq a b "two"' 'finish'
assert_eq "1" "$st" "trailer: a red file exits 1"
assert_contains "$out" "  -> 1 passed, 1 failed, 0 xfail, 0 skipped" "trailer: the failure is counted"

# --- § failure-output: file:line and the actual value ------------------------
run_case where.sh ': line two' 'assert_eq a b "mismatch here"' 'finish'
assert_contains "$out" "FAIL mismatch here" "failure: the message is printed"
assert_contains "$out" "at $BOX/where.sh:3" "failure: file:line of the failing assertion"
assert_contains "$out" "expected: a" "failure: assert_eq prints the expected value"
assert_contains "$out" "actual:   b" "failure: assert_eq prints the actual value"

run_case helper.sh 'check() { assert_contains "$1" needle "via helper"; }' 'check hay' 'finish'
assert_contains "$out" "at $BOX/helper.sh:2" "failure: a test-file helper is the frame reported, not the library"

run_case long.sh "hay=\"\$(seq 1 30)\"" 'assert_contains "$hay" needle "thirty lines"' 'finish'
assert_contains "$out" "expected to contain: needle" "failure: assert_contains names the needle"
assert_contains "$out" "actual: (30 lines, first 20)" "failure: a long actual value says how many lines it has"
assert_contains "$out" "       20"$'\n' "failure: the twentieth line is printed"
assert_not_contains "$out" "       21"$'\n' "failure: the twenty-first line is not"
assert_contains "$out" "… 10 more lines" "failure: the truncation pointer names the remainder"

run_case short.sh 'assert_contains "a
b" needle "two lines"' 'finish'
assert_contains "$out" "actual:" "failure: a short actual value is printed whole"
assert_not_contains "$out" "first 20" "failure: a short actual value carries no truncation header"

run_case notcontains.sh 'assert_not_contains "has needle" needle "absent"' 'finish'
assert_contains "$out" "expected NOT to contain: needle" "failure: assert_not_contains names the needle"
assert_contains "$out" "has needle" "failure: assert_not_contains prints the haystack"

printf 'alpha\nbeta\n' > "$BOX/seed.txt"
run_case filecontains.sh "assert_file_contains '$BOX/seed.txt' gamma 'lacks gamma'" 'finish'
assert_contains "$out" "lacks: gamma" "failure: assert_file_contains names the needle"
assert_contains "$out" "alpha" "failure: assert_file_contains prints the file's content"
# Builtin matching: with an empty PATH there is no grep, and the assertion
# still answers. The file is read once into the shell.
NOPATH="$(PATH= "$BASH" -c '. "$1"; assert_file_contains "$2" beta "beta via builtins"; assert_file_contains "$2" gamma "gamma via builtins"' _ "$LIB" "$BOX/seed.txt" 2>&1)"
assert_contains "$NOPATH" "ok   beta via builtins" "assert_file_contains: matches with builtins, no grep"
assert_contains "$NOPATH" "FAIL gamma via builtins" "assert_file_contains: fails with builtins, no grep"
assert_not_contains "$NOPATH" "command not found" "assert_file_contains: spawns nothing"

# --- § primitives: fixtures ----------------------------------------------------
run_case fixdir.sh 'd="$(fixture_dir)"' 'printf "DIR=%s\n" "$d"' 'assert_true "dir exists" -- test -d "$d"' 'finish'
assert_eq "0" "$st" "fixture_dir: a fixture file using it is green"
FIXDIR="$(printf '%s\n' "$out" | sed -n 's/^DIR=//p')"
assert_true "fixture_dir: prints a path" -- test -n "$FIXDIR"
assert_file_absent "$FIXDIR" "fixture_dir: the directory is removed when the file exits"

run_case fixrepo.sh 'r="$(fixture_repo)"' 'printf "REPO=%s\n" "$r"' \
  'assert_file_contains "$r/.git/config" "gpgsign = false" "signing off"' \
  'assert_file_contains "$r/.git/config" "autocrlf = false" "autocrlf off"' \
  'printf x > "$r/f"; git -C "$r" add f; git -C "$r" commit -q -m init' \
  'assert_exit 0 "commit needs no identity" -- git -C "$r" log --oneline' \
  'finish'
assert_eq "0" "$st" "fixture_repo: a repo with identity, signing and autocrlf settled"
assert_not_contains "$out" "Please tell me who you are" "fixture_repo: identity is in .git/config"

run_case fixcopy.sh 'd="$(fixture_dir)"' 'fixture_copy slice/ready "$d/ready"' \
  'assert_file_exists "$d/ready" "copied"' 'finish'
assert_eq "0" "$st" "fixture_copy: copies a seed from tests/fixtures/<area>/ to the destination"
run_case fixcopy-missing.sh 'd="$(fixture_dir)"' 'fixture_copy no-such-area/seed "$d/x"' 'assert_eq a a "never reached"' 'finish'
assert_true "fixture_copy: a missing seed stops the file" -- test "$st" -ne 0
assert_contains "$out" "no-such-area/seed" "fixture_copy: the missing seed is named"
assert_not_contains "$out" "never reached" "fixture_copy: nothing after the failed copy runs"

# --- § primitives: run and the exit-code verdicts ----------------------------
run_case run.sh 'run printf "%s\n" hello' 'assert_eq 0 "$status" "status captured"' \
  'assert_eq hello "$output" "output captured"' \
  'run sh -c "echo err >&2; exit 3"' 'assert_eq 3 "$status" "non-zero status captured"' \
  'assert_eq err "$output" "stderr is captured with stdout"' \
  'run cat' 'assert_eq "" "$output" "stdin is closed for the command"' 'finish'
assert_eq "0" "$st" "run: sets status and output, merges stderr, closes stdin"

run_case exit.sh 'run sh -c "echo boom; exit 2"' 'assert_exit 0 "wanted zero"' 'finish'
assert_contains "$out" "FAIL wanted zero" "assert_exit: a mismatched status fails"
assert_contains "$out" "exit 2, expected 0" "assert_exit: names both statuses"
assert_contains "$out" "boom" "assert_exit: prints the command's output"
run_case exit-cmd.sh 'assert_exit 4 "inline command" -- sh -c "exit 4"' 'finish'
assert_eq "0" "$st" "assert_exit: with -- runs the command itself"

run_case refused.sh \
  'assert_refused 2 "unknown base" -- sh -c "echo \"affected: unknown base: x\" >&2; exit 2"' \
  'finish'
assert_eq "0" "$st" "assert_refused: exit and reason both hold"
assert_contains "$out" "ok   " "assert_refused: prints an ok line without a message argument"
run_case refused-short.sh 'assert_refused 2 "base" -- sh -c "echo base; exit 2"' 'finish'
assert_eq "1" "$st" "assert_refused: a fragment under 6 characters fails"
assert_contains "$out" "under 6 characters" "assert_refused: the short fragment is the stated reason"
run_case refused-zero.sh 'assert_refused 2 "unknown base" "zero exit" -- sh -c "echo unknown base; exit 0"' 'finish'
assert_eq "1" "$st" "assert_refused: exit 0 fails although the fragment printed"
assert_contains "$out" "exit 0, expected 2" "assert_refused: the exit half is named"
run_case refused-reason.sh 'assert_refused 2 "unknown base" "other guard" -- sh -c "echo something else; exit 2"' 'finish'
assert_eq "1" "$st" "assert_refused: the right exit for a different reason fails"
assert_contains "$out" 'lacks "unknown base"' "assert_refused: the fragment half is named"
assert_contains "$out" "something else" "assert_refused: the actual output is printed"

# --- § primitives: boolean verdicts and files ---------------------------------
run_case bool.sh 'assert_true "one is one" -- test 1 -eq 1' 'assert_false "one is not two" -- test 1 -eq 2' \
  'assert_true "fails" -- test 1 -eq 2' 'finish'
assert_contains "$out" "ok   one is one" "assert_true: a true command passes"
assert_contains "$out" "ok   one is not two" "assert_false: a false command passes"
assert_contains "$out" "FAIL fails" "assert_true: a false command fails"
assert_contains "$out" "test 1 -eq 2" "assert_true: the failing command is printed"

run_case files.sh "assert_file_exists '$BOX/seed.txt' present" "assert_file_absent '$BOX/seed.txt' gone" \
  "assert_file_exists '$BOX/nope' there" "assert_file_absent '$BOX/nope' notthere" 'finish'
assert_contains "$out" "ok   present" "assert_file_exists: passes on a file"
assert_contains "$out" "ok   notthere" "assert_file_absent: passes on a missing path"
assert_contains "$out" "FAIL gone" "assert_file_absent: fails on a file that exists"
assert_contains "$out" "exists: $BOX/seed.txt" "assert_file_absent: names the path that exists"
assert_contains "$out" "FAIL there" "assert_file_exists: fails on a missing path"
assert_contains "$out" "missing: $BOX/nope" "assert_file_exists: names the missing path"

run_case passfail.sh 'pass "hand verdict"' 'fail "hand failure" "the actual thing"' 'finish'
assert_contains "$out" "ok   hand verdict" "pass: counts and prints ok"
assert_contains "$out" "FAIL hand failure" "fail: counts and prints FAIL"
assert_contains "$out" "the actual thing" "fail: prints the actual value it was given"
assert_contains "$out" "1 passed, 1 failed" "pass/fail: both reach the trailer"

# fail is `fail <message> [<actual>]`: an empty value is still a value, and a
# label or detail line is not the test file's to pass — it stops the file.
run_case fail-empty.sh 'fail "no value given"' 'fail "empty value given" ""' 'finish'
assert_contains "$out" "FAIL no value given
       at $BOX/fail-empty.sh:2
  FAIL empty value given" "fail: with no value, no value line is printed"
assert_contains "$out" "at $BOX/fail-empty.sh:3
       actual: (empty)" "fail: an empty value prints its value line, marked empty"
run_case fail-label.sh 'fail "labelled" "value" "my label:"' 'assert_eq a a "never reached"' 'finish'
assert_true "fail: a third argument stops the file" -- test "$st" -ne 0
assert_contains "$out" "fail takes <message> [<actual>]" "fail: the refusal says what fail takes"
assert_not_contains "$out" "never reached" "fail: nothing after the refused call runs"
run_case fail-detail.sh 'assert_exit 0 "wanted zero" -- sh -c "echo boom; exit 2"' 'finish'
assert_contains "$out" "exit 2, expected 0
       output:" "failure: a library assertion prints its detail line, then the value under its label"

# --- § primitives: sweeps ----------------------------------------------------
mkdir -p "$BOX/tree/sub"
printf 'clean line\n' > "$BOX/tree/a.md"
printf 'also clean\n' > "$BOX/tree/sub/b.md"
printf 'the needle is here\n' > "$BOX/control.md"
run_case sweep.sh "assert_sweep_empty 'no needles' '$BOX/control.md' -- grep -rn needle -- '$BOX/tree'" 'finish'
assert_eq "0" "$st" "assert_sweep_empty: a clean tree with a matching control passes"
printf 'a needle slipped in\n' > "$BOX/tree/sub/c.md"
run_case sweep-hit.sh "assert_sweep_empty 'no needles' '$BOX/control.md' -- grep -rn needle -- '$BOX/tree'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a hit fails"
assert_contains "$out" "sub/c.md:1:a needle slipped in" "assert_sweep_empty: the hits are the actual value"
rm "$BOX/tree/sub/c.md"
run_case sweep-control.sh "assert_sweep_empty 'no needles' '$BOX/tree/a.md' -- grep -rn needle -- '$BOX/tree'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a control the pattern does not match fails"
assert_contains "$out" "positive control" "assert_sweep_empty: the failed control is the stated reason"
run_case sweep-root.sh "assert_sweep_empty 'no needles' '$BOX/control.md' -- grep -rn needle -- '$BOX/tree' '$BOX/missing'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a missing swept root fails"
assert_contains "$out" "$BOX/missing" "assert_sweep_empty: the missing root is named"
run_case sweep-opts.sh "assert_sweep_empty 'md only' '$BOX/control.md' -- grep -rnE --include='*.md' -e 'need.e' -- '$BOX/tree'" 'finish'
assert_eq "0" "$st" "assert_sweep_empty: -e and --include= are passed through"
# Everything between the two `--` goes to grep verbatim, so an option the
# library never heard of (here --max-count) needs no parsing rule.
run_case sweep-verbatim.sh "assert_sweep_empty 'verbatim' '$BOX/control.md' -- -rn --max-count=1 -e needle -- '$BOX/tree'" 'finish'
assert_eq "0" "$st" "assert_sweep_empty: grep's own arguments are passed verbatim, whatever they are"
run_case sweep-nosep.sh "assert_sweep_empty 'no separator' '$BOX/control.md' -- grep -rn needle '$BOX/tree'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a call without the second -- fails"
assert_contains "$out" "no -- before the roots" "assert_sweep_empty: the missing separator is the stated reason"
run_case sweep-noroot.sh "assert_sweep_empty 'no root' '$BOX/control.md' -- grep -rn needle --" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a call with no root after the second -- fails"
assert_contains "$out" "names no root to search" "assert_sweep_empty: the missing root is the stated reason"

# --- § primitives: declarations ----------------------------------------------
run_case under.sh 'p="$(under_test tests/lib.sh)"' 'assert_eq "'"$REPO"'/tests/lib.sh" "$p" "absolute path"' 'finish'
assert_eq "0" "$st" "under_test: prints the absolute path of an existing artefact"
run_case under-missing.sh 'p="$(under_test tests/no-such-file.sh)"' 'assert_eq a a "never reached"' 'finish'
assert_true "under_test: a missing path fails the file at source time" -- test "$st" -ne 0
assert_contains "$out" "tests/no-such-file.sh" "under_test: the missing path is named"
assert_not_contains "$out" "never reached" "under_test: no assertion after the failed declaration runs"

run_case pymod.sh 'py_module tests/fixtures/slice' 'case ":$PYTHONPATH:" in *":'"$REPO"'/tests/fixtures/slice:"*) pass "on PYTHONPATH" ;; *) fail "on PYTHONPATH" "$PYTHONPATH" ;; esac' 'finish'
assert_eq "0" "$st" "py_module: puts the absolute module directory on PYTHONPATH"
assert_contains "$out" "$REPO/tests/fixtures/slice
" "py_module: prints the absolute directory, as under_test does"
# A command substitution cannot export, so a file that needs both the path and
# the PYTHONPATH entry names a variable and py_module assigns it in the file's shell.
run_case pymod-var.sh 'py_module tests/fixtures/slice MOD' 'assert_eq "'"$REPO"'/tests/fixtures/slice" "$MOD" "variable assigned"' \
  'case ":$PYTHONPATH:" in *":$MOD:"*) pass "on PYTHONPATH" ;; *) fail "on PYTHONPATH" "$PYTHONPATH" ;; esac' 'finish'
assert_eq "0" "$st" "py_module: a variable name receives the absolute directory and PYTHONPATH still gets it"
assert_not_contains "$out" "$REPO/tests/fixtures/slice" "py_module: with a variable name it prints nothing"
run_case pymod-missing.sh 'py_module tests/fixtures/none' 'assert_eq a a "never reached"' 'finish'
assert_true "py_module: a missing directory fails the file" -- test "$st" -ne 0
assert_not_contains "$out" "never reached" "py_module: nothing after the failed declaration runs"

# --- § environment ------------------------------------------------------------
ENV_OUT="$(env -i PATH="$PATH" HOME="$HOME" "$BASH" -c '. "$1"; env' _ "$LIB")"
assert_contains "$ENV_OUT" "LC_ALL=C" "environment: LC_ALL=C is exported"
assert_contains "$ENV_OUT" "PYTHONDONTWRITEBYTECODE=1" "environment: PYTHONDONTWRITEBYTECODE=1 is exported"
assert_contains "$ENV_OUT" "PYTHONUTF8=1" "environment: PYTHONUTF8=1 is still exported"

run_case precedes.sh 'assert_precedes "alpha beta" beta alpha "order"' 'assert_precedes "alpha beta" alpha gamma "missing"' 'finish'
assert_contains "$out" "beta at 6, alpha at 0" "assert_precedes: reports both offsets on a wrong order"
assert_contains "$out" "gamma missing" "assert_precedes: names the absent needle"
assert_not_contains "$out" "ordered" "assert_precedes: the ordered/ordered emulation is gone"

# --- § xfail: the platform baseline (D2) -------------------------------------
# tests/expected-failures.txt rows are `<file> <platform-glob> <message>`; the
# library loads the rows for its own file on a matching platform, prints
# XFAIL for a listed failure without counting it as failed, and fails the file
# on an XPASS so the list can only shrink. TEST_EXPECTED_FAILURES and
# TEST_PLATFORM override the file and the platform string for this test.
XF="$BOX/expected.txt"
printf '%s\n' '# file platform message' \
  'xfail.sh fake-os* known broken here' \
  'xfail.sh fake-os* now fixed' \
  'xfail.sh fake-os* path-bearing * message' \
  'other.sh fake-os* a row for another file' > "$XF"
TEST_EXPECTED_FAILURES="$XF" TEST_PLATFORM=fake-os-11 run_case xfail.sh \
  'assert_eq a b "known broken here"' 'assert_eq a a "unrelated pass"' \
  'assert_eq a b "path-bearing /tmp/x.123 message"' 'assert_eq a b "a row for another file"' 'finish'
assert_eq "1" "$st" "xfail: a listed failure is not a failure, an unlisted one still is"
assert_contains "$out" "XFAIL known broken here" "xfail: the listed failure prints XFAIL"
assert_not_contains "$out" "  FAIL known broken here" "xfail: the listed failure is not printed as FAIL"
assert_contains "$out" "XFAIL path-bearing /tmp/x.123 message" "xfail: a row's message is a glob, so a path-bearing message matches"
assert_contains "$out" "FAIL a row for another file" "xfail: another file's row does not load here"
assert_contains "$out" "1 passed, 1 failed, 2 xfail, 0 skipped" "xfail: the trailer counts xfail apart from failed"

TEST_EXPECTED_FAILURES="$XF" TEST_PLATFORM=fake-os-11 run_case xfail.sh \
  'assert_eq a b "known broken here"' 'assert_eq a a "now fixed"' 'finish'
assert_eq "1" "$st" "xpass: a listed message that passes fails the file"
assert_contains "$out" "XPASS now fixed" "xpass: prints XPASS"
assert_contains "$out" "remove its row" "xpass: tells the reader what to do"
assert_contains "$out" "0 passed, 1 failed, 1 xfail, 0 skipped" "xpass: counted as failed"

TEST_EXPECTED_FAILURES="$XF" TEST_PLATFORM=linux-gnu run_case xfail.sh 'assert_eq a b "known broken here"' 'finish'
with_rows="$out"; with_st="$st"
TEST_EXPECTED_FAILURES="$BOX/no-such-file.txt" TEST_PLATFORM=linux-gnu run_case xfail.sh 'assert_eq a b "known broken here"' 'finish'
assert_eq "1" "$with_st" "other platform: no row loads and the failure fails the file"
assert_eq "$out" "$with_rows" "other platform: output is byte-identical to a run with no baseline file at all"
assert_contains "$with_rows" "FAIL known broken here" "other platform: the failure is printed as FAIL"

assert_file_exists "$REPO/tests/expected-failures.txt" "baseline: tests/expected-failures.txt exists"
assert_file_matches "$REPO/AGENTS.md" '^Expected failures: tests/expected-failures\.txt$' \
  "baseline: AGENTS.md names the file in one line below the end marker"
assert_precedes "$(flatten "$REPO/AGENTS.md")" "Affected tests: " "Expected failures: " \
  "baseline: the pointer sits with the other test lines below the end marker"

# --- § cases: begin_case, end_case and TEST_CASE (D4) ------------------------
# A case is a named run of assertions inside one file. begin_case prints a
# header and starts a count; end_case prints the count; TEST_CASE=<glob> keeps
# only the cases whose name matches. No setup or teardown belongs to a case.
# The one supported form wraps the body: `if begin_case "name"; then ...; fi`,
# with end_case after the fi (or inside the body; it is a no-op with no case open).
CASE_ALPHA=('if begin_case "alpha"; then' 'assert_eq a a "alpha one"' 'assert_eq a b "alpha two"' 'fi' 'end_case')
CASE_BETA=('if begin_case "beta"; then' 'assert_eq a a "beta one"' 'fi' 'end_case')
run_case cases.sh "${CASE_ALPHA[@]}" "${CASE_BETA[@]}" 'assert_eq a a "after"' 'finish'
assert_contains "$out" "== case: alpha" "cases: begin_case prints a header naming the case"
assert_contains "$out" "== alpha: 1 passed, 1 failed" "cases: end_case prints the case's own count"
assert_contains "$out" "== beta: 1 passed, 0 failed" "cases: the next case starts its own count"
assert_contains "$out" "  -> 3 passed, 1 failed, 0 xfail, 0 skipped" "cases: the trailer still counts every assertion of the file"
assert_contains "$out" "[case: alpha]" "cases: a failure inside a case names the case"
assert_eq "1" "$st" "cases: a failed assertion inside a case fails the file"

TEST_CASE=beta run_case cases-beta.sh "${CASE_ALPHA[@]}" "${CASE_BETA[@]}" 'assert_eq a a "after"' 'finish'
assert_eq "0" "$st" "TEST_CASE: a case whose name does not match is not run, so its failure is not one"
assert_contains "$out" "== alpha: filtered out by TEST_CASE=beta" "TEST_CASE: a filtered case says so"
assert_not_contains "$out" "alpha two" "TEST_CASE: a filtered case's assertion prints nothing"
assert_contains "$out" "  -> 2 passed, 0 failed, 0 xfail, 0 skipped" "TEST_CASE: the matching case and an assertion outside any case are counted"

TEST_CASE='al*' run_case cases-glob.sh "${CASE_ALPHA[@]}" "${CASE_BETA[@]}" 'finish'
assert_contains "$out" "== beta: filtered out by TEST_CASE=al*" "TEST_CASE: the filter is a glob, not a literal"
assert_contains "$out" "== alpha: 1 passed, 1 failed" "TEST_CASE: a glob that matches keeps the case"

# begin_case returns 1 for a filtered case, so a file can wrap a case's whole
# body in `if` and the work of an unselected case is never done.
WRAPPED=('if begin_case "alpha"; then' ": > \"$BOX/ran-alpha\"" 'assert_eq a a "wrapped"' 'fi' 'end_case')
TEST_CASE=beta run_case cases-wrapped.sh "${WRAPPED[@]}" "${CASE_BETA[@]}" 'finish'
assert_file_absent "$BOX/ran-alpha" "TEST_CASE: the body of a wrapped, unselected case does not run"
run_case cases-wrapped.sh "${WRAPPED[@]}" "${CASE_BETA[@]}" 'finish'
assert_file_exists "$BOX/ran-alpha" "cases: the body of a wrapped case runs when no filter is set"

# Nothing matched: the file asserted nothing on purpose, which is not a failure.
TEST_CASE=nothing-matches run_case cases-none.sh "${CASE_ALPHA[@]}" 'finish'
assert_eq "0" "$st" "TEST_CASE: a file in which no case matches exits 0"
assert_contains "$out" "TEST_CASE=nothing-matches matched no case" "TEST_CASE: the output names the filter that kept every case out"
TEST_CASE=beta run_case cases-after.sh "${WRAPPED[@]}" 'assert_eq a a "after a filtered case"' "${CASE_BETA[@]}" 'finish'
assert_contains "$out" "after a filtered case" "TEST_CASE: end_case after the fi returns the file to its own level, so a later assertion counts"
# A filtered begin_case opens no case, so an end_case written inside the body
# (which never runs for it) cannot leave the file's later verdicts muted.
INSIDE=('if begin_case "alpha"; then' 'assert_eq a a "alpha one"' 'end_case' 'fi')
TEST_CASE=beta run_case cases-inside.sh "${INSIDE[@]}" 'assert_eq a a "file level after"' "${CASE_BETA[@]}" 'finish'
assert_contains "$out" "ok   file level after" "TEST_CASE: an end_case inside a filtered case's body leaves a later file-level assertion counted"
assert_contains "$out" "  -> 2 passed, 0 failed, 0 xfail, 0 skipped" "TEST_CASE: the file-level assertion and the selected case are both in the trailer"
assert_file_not_matches "$LIB" '_CASE_ON' "cases: no muted mode is left in the library"
run_case cases-unfiltered.sh 'finish'
assert_eq "1" "$st" "TEST_CASE unset: a file with no assertions still fails"

# A case never ended is closed by the next begin_case and by finish.
run_case cases-open.sh 'begin_case "one"' 'assert_eq a a "x"' 'begin_case "two"' 'assert_eq a a "y"' 'finish'
assert_contains "$out" "== one: 1 passed, 0 failed" "cases: begin_case closes a case that was never ended"
assert_contains "$out" "== two: 1 passed, 0 failed" "cases: finish closes the last open case"

# The trailer is the only line run.sh tallies, and it starts with two spaces and
# an arrow; no case line may.
run_case cases-lines.sh "${CASE_ALPHA[@]}" 'finish'
assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^  -> ')" "cases: exactly one line of the output is a trailer"

# --- § invariants: the suite-wide rules (AC 17) ------------------------------
# A test file states WHAT it checks and leaves HOW to the library, so no file of
# tests/ keeps a counter assignment of its own, a present/gone encoding, a literal
# assert_eq pair, a temp directory it made itself, a repository it initialised
# itself, a PATH export, a bytecode or locale environment, or a comment header
# naming its artefact (under_test declares it). These are the suite's only copy of
# those patterns: the area and skill-script sweeps in other files keep just
# what is specific to them. Each sweep runs against a control line that carries
# its pattern, so an empty sweep cannot be a pattern that stopped matching. The
# patterns put one character in a bracket so this file does not match itself.
TEST_FILES=("$REPO"/tests/test-*.sh)
INV_CONTROL="$(fixture_dir)/control.sh"
assert_invariant() {  # <label> <control line> <ERE pattern> <root>...
  local label="$1" control="$2" pattern="$3"; shift 3
  printf '%s\n' "$control" > "$INV_CONTROL"
  assert_sweep_empty "invariant: $label" "$INV_CONTROL" -- grep -nE -e "$pattern" -- "$@"
}
# tests_except <base name>... — TEST_FILES less the named files, in KEPT_TESTS.
tests_except() {
  local f g keep
  KEPT_TESTS=()
  for f in "${TEST_FILES[@]}"; do
    keep=1
    for g in "$@"; do [ "$g" = "${f##*/}" ] && keep=0; done
    [ "$keep" -eq 0 ] || KEPT_TESTS+=("$f")
  done
}
assert_invariant "no counter assignment outside the library" \
  '_TES''TS=$((_TES''TS + 1))' '(^|[^A-Za-z0-9_])_(TEST[S]|FAIL[S])=' "${TEST_FILES[@]}"
assert_invariant "no present/gone encoding" \
  '[ -f x ] && ec''ho present || ec''ho absent' 'echo (presen[t]|gon[e]|missin[g]|absen[t])|&& echo [a-z]+ [|][|] echo [a-z]+' "${TEST_FILES[@]}"
assert_invariant "no literal assert_eq pair" \
  'assert_e''q "valid" "valid" "msg"' 'assert_e[q] "([^"]+)" "\1"' "${TEST_FILES[@]}"
assert_invariant "no temp directory made outside the library" \
  'BOX="$(mkt''emp -d)"' 'mktem[p] -d' "${TEST_FILES[@]}"
assert_invariant "no PATH exported by a test file" \
  'ex''port PATH="$d/bin:$PATH"' '[e]xport PATH=' "${TEST_FILES[@]}"
assert_invariant "no covers header (under_test declares the artefact)" \
  '# cove''rs: scripts/x.sh' '# cover[s]:' "${TEST_FILES[@]}"

# Initialising a repository belongs to the library's fixture_repo. The four files
# below are tests OF git behaviour, so each keeps the repository it creates itself:
GIT_SUBJECT_TESTS=(
  test-codex-install.sh      # the installer scaffolds a project from a checkout
  test-install-sh.sh         # the scaffold fixtures whose paths contain spaces
  test-publish-evidence.sh   # a bare remote the evidence is published to
  test-session-stop.sh       # a bare remote the unpushed-commit warning reads
)
GIT_INIT='(git|GIT")( -C [^ ]+)? ini[t]'
tests_except "${GIT_SUBJECT_TESTS[@]}"
assert_invariant "a repository is initialised only inside a test of git behaviour" \
  'git -C "$d" ini''t -q' "$GIT_INIT" "${KEPT_TESTS[@]}"
for g in "${GIT_SUBJECT_TESTS[@]}"; do
  assert_true "invariant: $g still initialises a repository itself, so its allowlist entry is needed" -- \
    grep -qE -e "$GIT_INIT" "$REPO/tests/$g"
done

# The interpreter environment (PYTHONDONTWRITEBYTECODE, PYTHONUTF8, LC_ALL) is
# exported once, by the library. The two files below talk about it on purpose:
ENV_SUBJECT_TESTS=(
  test-lib.sh                # asserts the environment the library exports
  test-publish-evidence.sh   # the push under test pins LC_ALL=C itself
)
ENV_PATTERN='PYTHONDONTWRITEBYT[E]CODE|PYTHONUTF[8]=|LC_AL[L]='
tests_except "${ENV_SUBJECT_TESTS[@]}"
assert_invariant "no per-file bytecode or locale environment" \
  'PYTHONDONTWRITE''BYTECODE=1 python3 x' "$ENV_PATTERN" "${KEPT_TESTS[@]}"
for g in "${ENV_SUBJECT_TESTS[@]}"; do
  assert_true "invariant: $g still names the interpreter environment, so its allowlist entry is needed" -- \
    grep -qE -e "$ENV_PATTERN" "$REPO/tests/$g"
done

# The counters are written in exactly two places: pass and _fail_count, the one
# recorder behind fail and the library's own failures. Every other line of the
# library that names them only reads.
WRITERS="$(awk '
  /^(pass|_fail_count)\(\)/ { inside = 1 }
  inside && /^}/ { inside = 0; next }
  !inside && /_(TESTS|FAILS)=/ && !/^_(TESTS|FAILS)=0$/ { print FILENAME ":" FNR ": " $0 }' "$LIB")"
assert_eq "" "$WRITERS" "counters: _TESTS and _FAILS are assigned only inside pass and _fail_count"
assert_file_matches "$LIB" '^pass\(\)' "counters: pass exists"
assert_file_matches "$LIB" '^fail\(\)' "counters: fail exists"
assert_file_matches "$LIB" '^_fail_count\(\)' "counters: the failure recorder exists"

finish
