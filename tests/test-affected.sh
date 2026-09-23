#!/bin/bash
# tests/test-affected.sh — tests/affected.sh (specs/fewer-full-suite-runs.md
# AC 3): the test files a change since <base> touches — changed or added test
# files and test files naming a changed path verbatim — sorted and unique;
# every file when a runner file changed; `affected: none` with no change;
# `--run` hands the list to tests/run.sh.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT
[ -n "$BOX" ] && [ -d "$BOX" ] || { printf 'mktemp -d failed\n' >&2; exit 1; }

FIX="$BOX/repo"
mkdir -p "$FIX/tests" "$FIX/src"
cp "$REPO/tests/run.sh" "$REPO/tests/lib.sh" "$REPO/tests/affected.sh" "$FIX/tests/" 2>/dev/null
passing_test() { printf '%s\n' ". \"\$(dirname \"\$0\")/lib.sh\"" "# $1" 'assert_eq a a "holds"' 'finish' > "$FIX/tests/$2"; }
passing_test "covers src/foo.txt" test-a.sh
passing_test "covers nothing in particular" test-b.sh
passing_test "covers src/baz.txt" test-c.sh
printf 'foo\n' > "$FIX/src/foo.txt"
printf 'bar\n' > "$FIX/src/bar.txt"
git -C "$FIX" init -q
git -C "$FIX" add -A
commit() { git -C "$FIX" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "$1"; }
commit init
BASE="$(git -C "$FIX" rev-parse HEAD)"
affected() { (cd "$FIX" && bash tests/affected.sh "$@") 2>&1; }

OUT="$(affected "$BASE")"; STATUS=$?
assert_eq "affected: none" "$OUT" "no change: prints affected: none"
assert_eq "0" "$STATUS" "no change: exits 0"
OUT="$(affected --run "$BASE")"
assert_eq "affected: none" "$OUT" "no change, --run: runs nothing"

printf 'more\n' >> "$FIX/src/foo.txt"
OUT="$(affected "$BASE")"
assert_eq "tests/test-a.sh" "$OUT" "unstaged edit: the test naming the path verbatim is listed"

passing_test "covers src/baz.txt, edited" test-c.sh
git -C "$FIX" add tests/test-c.sh
commit "edit c"
passing_test "a new test" test-d.sh
OUT="$(affected "$BASE")"
assert_eq "tests/test-a.sh
tests/test-c.sh
tests/test-d.sh" "$OUT" "committed test, untracked test and verbatim match: listed sorted and unique"
assert_not_contains "$OUT" "test-b.sh" "an unrelated test is not listed"

RUN="$(affected "$BASE" --run)"; RSTATUS=$?
assert_eq "0" "$RSTATUS" "--run: exit status of tests/run.sh passes through"
assert_contains "$RUN" "=== tests/test-a.sh ===" "--run: a listed file runs"
assert_not_contains "$RUN" "=== tests/test-b.sh ===" "--run: an unlisted file does not run"
assert_contains "$RUN" "RESULT: all 3 test files passed" "--run: exactly the listed files run"

for runner in lib.sh run.sh affected.sh; do
  cp "$FIX/tests/$runner" "$BOX/$runner.orig"
  printf '# touched\n' >> "$FIX/tests/$runner"
  OUT="$(affected "$BASE")"
  assert_eq "4" "$(printf '%s\n' "$OUT" | grep -c '^tests/test-.*\.sh$')" \
    "runner change ($runner): every test file is listed"
  cp "$BOX/$runner.orig" "$FIX/tests/$runner"
done

(cd "$FIX" && bash tests/affected.sh </dev/null >"$BOX/usage.out" 2>&1)
assert_eq "2" "$?" "usage: no base exits 2"
(cd "$FIX" && bash tests/affected.sh no-such-ref </dev/null >"$BOX/usage.out" 2>&1)
assert_eq "2" "$?" "usage: an unknown base exits 2"

finish
