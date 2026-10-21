#!/bin/bash
# tests/test-affected.sh — tests/affected.sh (specs/fewer-full-suite-runs.md
# AC 3): the test files a change since <base> touches — changed or added test
# files and test files naming a changed path verbatim — sorted and unique;
# every file when a runner file changed; `affected: none` with no change;
# `--run` hands the list to tests/run.sh.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOX="$(fixture_dir)"

FIX="$(fixture_repo)"
mkdir -p "$FIX/tests" "$FIX/src"
cp "$REPO/tests/run.sh" "$REPO/tests/lib.sh" "$REPO/tests/affected.sh" "$FIX/tests/" 2>/dev/null
passing_test() { printf '%s\n' ". \"\$(dirname \"\$0\")/lib.sh\"" "# $1" 'assert_eq a a "holds"' 'finish' > "$FIX/tests/$2"; }
passing_test "covers src/foo.txt" test-a.sh
passing_test "covers nothing in particular" test-b.sh
passing_test "covers src/baz.txt" test-c.sh
printf 'foo\n' > "$FIX/src/foo.txt"
printf 'bar\n' > "$FIX/src/bar.txt"
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

# A rename lists the old path too, so a test naming it is still selected.
passing_test "covers src/bar.txt" test-e.sh
git -C "$FIX" add -A
commit "second base"
BASE2="$(git -C "$FIX" rev-parse HEAD)"
git -C "$FIX" mv src/bar.txt src/bar2.txt
OUT="$(affected "$BASE2")"
assert_eq "tests/test-e.sh" "$OUT" "rename: the test naming the old path is selected"

# A deleted test file is not listed, and --run still starts.
git -C "$FIX" rm -q tests/test-b.sh
OUT="$(affected "$BASE2")"
assert_not_contains "$OUT" "test-b.sh" "deleted test file: not listed"
RUN="$(affected --run "$BASE2")"; RSTATUS=$?
assert_eq "0" "$RSTATUS" "deleted test file: --run still exits 0"

# A red selected file makes --run exit non-zero.
printf '%s\n' ". \"\$(dirname \"\$0\")/lib.sh\"" "# covers src/bar.txt" 'assert_eq a b "breaks"' 'finish' \
  > "$FIX/tests/test-e.sh"
RUN="$(affected --run "$BASE2")"; RSTATUS=$?
assert_eq "1" "$RSTATUS" "--run: a failing selected file's status passes through"

# under-test: a test naming an artefact through under_test (or py_module) is
# selected by a change to that path or to anything under it; verbatim inference
# still selects beside it (spec test-suite-aposd D1, AC 4).
mkdir -p "$FIX/.agents/skills/x/scripts" "$FIX/.agents/skills/x/scripts-old" "$FIX/lib/pkg"
printf 'v1
' > "$FIX/.agents/skills/x/scripts/y.py"
printf 'v1
' > "$FIX/.agents/skills/x/scripts-old/z.py"
printf 'v1
' > "$FIX/.agents/skills/x/SKILL.md"
printf 'v1
' > "$FIX/lib/pkg/mod.py"
printf '%s
' ". \"\$(dirname \"\$0\")/lib.sh\"" 'S="$(under_test .agents/skills/x/scripts/)"' 'assert_eq a a "holds"' 'finish' > "$FIX/tests/test-f.sh"
printf '%s
' ". \"\$(dirname \"\$0\")/lib.sh\"" 'under_test ".agents/skills/x/SKILL.md"' 'py_module lib/pkg' 'assert_eq a a "holds"' 'finish' > "$FIX/tests/test-g.sh"
printf '%s
' ". \"\$(dirname \"\$0\")/lib.sh\"" 'assert_eq a a "holds"' 'finish' > "$FIX/tests/test-h.sh"
git -C "$FIX" add -A
commit "under_test fixtures"
BASE3="$(git -C "$FIX" rev-parse HEAD)"

printf 'v2
' > "$FIX/.agents/skills/x/scripts/y.py"
OUT="$(affected "$BASE3")"
assert_eq "tests/test-f.sh" "$OUT" "under_test: a directory literal selects the test for a change to a file under it"
git -C "$FIX" checkout -q -- .agents/skills/x/scripts/y.py

printf 'v2
' > "$FIX/.agents/skills/x/scripts-old/z.py"
OUT="$(affected "$BASE3")"
assert_eq "affected: none" "$OUT" "under_test: a sibling sharing the name prefix is not covered"
git -C "$FIX" checkout -q -- .agents/skills/x/scripts-old/z.py

printf 'v2
' > "$FIX/.agents/skills/x/SKILL.md"
OUT="$(affected "$BASE3")"
assert_eq "tests/test-g.sh" "$OUT" "under_test: a quoted file literal selects on equality"
git -C "$FIX" checkout -q -- .agents/skills/x/SKILL.md

printf 'v2
' > "$FIX/lib/pkg/mod.py"
OUT="$(affected "$BASE3")"
assert_eq "tests/test-g.sh" "$OUT" "py_module: its directory argument is declared like under_test"
git -C "$FIX" checkout -q -- lib/pkg/mod.py

printf 'v2
' > "$FIX/.agents/skills/x/scripts/y.py"
printf 'v2
' > "$FIX/src/foo.txt"
OUT="$(affected "$BASE3")"
assert_eq "tests/test-a.sh
tests/test-f.sh" "$OUT" "under_test and verbatim inference select as a union"
git -C "$FIX" checkout -q -- .agents/skills/x/scripts/y.py src/foo.txt

printf '# touched
' >> "$FIX/tests/lib.sh"
OUT="$(affected "$BASE3")"
assert_contains "$OUT" "tests/test-h.sh" "under_test: a runner change still selects a test that declares nothing"
git -C "$FIX" checkout -q -- tests/lib.sh

(cd "$FIX" && bash tests/affected.sh </dev/null >"$BOX/usage.out" 2>&1)
assert_eq "2" "$?" "usage: no base exits 2"
(cd "$FIX" && bash tests/affected.sh no-such-ref </dev/null >"$BOX/usage.out" 2>&1)
assert_eq "2" "$?" "usage: an unknown base exits 2"

finish
