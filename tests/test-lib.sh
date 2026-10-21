#!/bin/bash
# tests/test-lib.sh — tests/lib.sh as a deep module (specs/test-suite-aposd.md
# AC 1, 2, 3): `finish` refuses a file with zero assertions unless it called
# `skip`; `skip` counts and fails the file under REQUIRE_ALL=1; the trailer
# prints passed, failed, xfail and skipped; every failure prints file:line and
# the actual value, truncated at 20 lines; the fixture, capture, verdict and
# declaration primitives behave as documented; the library exports LC_ALL=C,
# PYTHONDONTWRITEBYTECODE=1 and PYTHONUTF8=1 and writes its counters only
# through pass and fail.
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
# run_case <name> <line>... — write the file, run it, set out and st.
run_case() {
  local f; f="$(case_file "$@")"
  st=0; out="$(cd "$BOX" && bash "$f" </dev/null 2>&1)" || st=$?
}
# --- § finish: zero assertions, skip, REQUIRE_ALL, the trailer ---------------
run_case zero.sh 'finish'
assert_eq "1" "$st" "finish: a file with zero assertions and no skip exits 1"
assert_contains "$out" "no assertions" "finish: the zero-assertion failure says so"

run_case skipped.sh 'skip "playwright is not importable"' 'finish'
assert_eq "0" "$st" "skip: a skipped file exits 0 without REQUIRE_ALL"
assert_contains "$out" "SKIP playwright is not importable" "skip: prints SKIP and the reason"
assert_contains "$out" "0 passed, 0 failed, 0 xfail, 1 skipped" "skip: the trailer counts the skip"

REQUIRE_ALL=1 run_case required.sh 'skip "no browser"' 'assert_eq a a "still asserts"' 'finish'
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

# --- § primitives: sweeps ----------------------------------------------------
mkdir -p "$BOX/tree/sub"
printf 'clean line\n' > "$BOX/tree/a.md"
printf 'also clean\n' > "$BOX/tree/sub/b.md"
printf 'the needle is here\n' > "$BOX/control.md"
run_case sweep.sh "assert_sweep_empty 'no needles' '$BOX/control.md' -- grep -rn needle '$BOX/tree'" 'finish'
assert_eq "0" "$st" "assert_sweep_empty: a clean tree with a matching control passes"
printf 'a needle slipped in\n' > "$BOX/tree/sub/c.md"
run_case sweep-hit.sh "assert_sweep_empty 'no needles' '$BOX/control.md' -- grep -rn needle '$BOX/tree'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a hit fails"
assert_contains "$out" "sub/c.md:1:a needle slipped in" "assert_sweep_empty: the hits are the actual value"
rm "$BOX/tree/sub/c.md"
run_case sweep-control.sh "assert_sweep_empty 'no needles' '$BOX/tree/a.md' -- grep -rn needle '$BOX/tree'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a control the pattern does not match fails"
assert_contains "$out" "positive control" "assert_sweep_empty: the failed control is the stated reason"
run_case sweep-root.sh "assert_sweep_empty 'no needles' '$BOX/control.md' -- grep -rn needle '$BOX/tree' '$BOX/missing'" 'finish'
assert_eq "1" "$st" "assert_sweep_empty: a missing swept root fails"
assert_contains "$out" "$BOX/missing" "assert_sweep_empty: the missing root is named"
run_case sweep-opts.sh "assert_sweep_empty 'md only' '$BOX/control.md' -- grep -rnE --include='*.md' -e 'need.e' '$BOX/tree'" 'finish'
assert_eq "0" "$st" "assert_sweep_empty: -e and --include= are passed through"

# --- § primitives: declarations ----------------------------------------------
run_case under.sh 'p="$(under_test tests/lib.sh)"' 'assert_eq "'"$REPO"'/tests/lib.sh" "$p" "absolute path"' 'finish'
assert_eq "0" "$st" "under_test: prints the absolute path of an existing artefact"
run_case under-missing.sh 'p="$(under_test tests/no-such-file.sh)"' 'assert_eq a a "never reached"' 'finish'
assert_true "under_test: a missing path fails the file at source time" -- test "$st" -ne 0
assert_contains "$out" "tests/no-such-file.sh" "under_test: the missing path is named"
assert_not_contains "$out" "never reached" "under_test: no assertion after the failed declaration runs"

run_case pymod.sh 'py_module tests/fixtures/slice' 'case ":$PYTHONPATH:" in *":'"$REPO"'/tests/fixtures/slice:"*) pass "on PYTHONPATH" ;; *) fail "on PYTHONPATH" "$PYTHONPATH" ;; esac' 'finish'
assert_eq "0" "$st" "py_module: puts the absolute module directory on PYTHONPATH"
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

# The counters are written in exactly two places: pass and fail. Every other
# line of the library that names them only reads.
WRITERS="$(awk '
  /^(pass|fail)\(\)/ { inside = 1 }
  inside && /^}/ { inside = 0; next }
  !inside && /_(TESTS|FAILS)=/ && !/^_(TESTS|FAILS)=0$/ { print FILENAME ":" FNR ": " $0 }' "$LIB")"
assert_eq "" "$WRITERS" "counters: _TESTS and _FAILS are assigned only inside pass and fail"
assert_file_matches "$LIB" '^pass\(\)' "counters: pass exists"
assert_file_matches "$LIB" '^fail\(\)' "counters: fail exists"

finish
