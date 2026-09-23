#!/bin/bash
# tests/test-run-sh.sh — the runner's contract and the interpreter resolution
# in tests/lib.sh (#136): per-file timing, stdin closed for every file,
# `--jobs N` with the same RESULT and exit status as a serial run, and
# TEST_PYTHON resolved once, away from the Windows Store launcher.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT

# A miniature repo: the real runner and library plus three one-line test files.
mkdir -p "$BOX/tests"
cp "$REPO/tests/run.sh" "$REPO/tests/lib.sh" "$BOX/tests/"
printf '%s\n' '. "$(dirname "$0")/lib.sh"' 'assert_eq a a "alpha holds"' 'finish' > "$BOX/tests/test-alpha.sh"
printf '%s\n' '. "$(dirname "$0")/lib.sh"' 'assert_eq a b "beta breaks"' 'finish' > "$BOX/tests/test-beta.sh"
printf '%s\n' '. "$(dirname "$0")/lib.sh"' 'payload="$(cat)"' \
  'assert_eq "" "$payload" "stdin is closed for the file [$payload]"' 'finish' > "$BOX/tests/test-stdin.sh"

# --- serial run: streaming output, a trailer per file, one summary ------------
# stdin is a pipe that stays open for a while and then delivers a token: a
# runner that leaks its stdin into the files lets test-stdin.sh read the token.
OUT="$(TEST_JOBS=1 bash "$BOX/tests/run.sh" < <(sleep 2; echo leaked) 2>&1)"; STATUS=$?
assert_eq "1" "$STATUS" "serial: exit 1 when a file fails"
assert_contains "$OUT" "RESULT: 1/3 test files FAILED" "serial: RESULT line unchanged"
assert_contains "$OUT" "=== tests/test-alpha.sh ===" "serial: header per file is kept"
assert_eq "3" "$(printf '%s\n' "$OUT" | grep -c -E '^--- tests/test-[a-z]+\.sh: [0-9]+ s ---$')" \
  "serial: an elapsed-seconds trailer follows every file"
assert_contains "$OUT" "TOTAL: 3 files, wall " "serial: total wall time is summarised"
assert_contains "$OUT" "(jobs=1)" "serial: summary names the job count"
assert_contains "$OUT" "SLOWEST:" "serial: the slowest files are listed"
assert_contains "$OUT" "ok   stdin is closed for the file []" "serial: each file runs with stdin closed"
assert_eq "tests/test-alpha.sh" "$(printf '%s\n' "$OUT" | grep -m1 '^=== ' | cut -d' ' -f2)" \
  "serial: files run in discovery order"

# --- --jobs N: same verdict, whole blocks, no interleaving -------------------
POUT="$(bash "$BOX/tests/run.sh" --jobs 3 < <(sleep 2; echo leaked) 2>&1)"; PSTATUS=$?
assert_eq "1" "$PSTATUS" "jobs: exit 1 when a file fails"
assert_contains "$POUT" "RESULT: 1/3 test files FAILED" "jobs: RESULT line identical to serial"
assert_contains "$POUT" "(jobs=3)" "jobs: summary names the job count"
assert_eq "3" "$(printf '%s\n' "$POUT" | grep -c '^=== tests/test-')" "jobs: every file gets one header"
assert_eq "3" "$(printf '%s\n' "$POUT" | grep -c -E '^--- tests/test-[a-z]+\.sh: [0-9]+ s ---$')" \
  "jobs: every file gets one trailer"
# A block is header, body, trailer for the same file; a header inside another
# file's block would mean two files' output interleaved.
BLOCKS_OK="$(printf '%s\n' "$POUT" | awk '
  /^=== tests\// { if (open != "") bad = 1; open = $2; next }
  /^--- tests\// { name = $2; sub(/:$/, "", name); if (name != open) bad = 1; open = ""; next }
  END { print (bad ? "interleaved" : "whole") }')"
assert_eq "whole" "$BLOCKS_OK" "jobs: each file's output is printed as one block"
assert_contains "$POUT" "ok   stdin is closed for the file []" "jobs: files still run with stdin closed"

ENV_OUT="$(TEST_JOBS=2 bash "$BOX/tests/run.sh" </dev/null 2>&1)"
assert_contains "$ENV_OUT" "(jobs=2)" "TEST_JOBS: the environment sets the job count"

rm -f "$BOX/tests/test-beta.sh"
GREEN="$(bash "$BOX/tests/run.sh" --jobs 2 </dev/null 2>&1)"; GSTATUS=$?
assert_eq "0" "$GSTATUS" "jobs: exit 0 when every file passes"
assert_contains "$GREEN" "RESULT: all 2 test files passed" "jobs: green RESULT line unchanged"

for bad_jobs in 0 abc ""; do
  bash "$BOX/tests/run.sh" --jobs "$bad_jobs" </dev/null >"$BOX/bad.out" 2>&1; BAD=$?
  assert_eq "2" "$BAD" "usage: --jobs '$bad_jobs' is refused with exit 2"
  assert_file_contains "$BOX/bad.out" "positive integer" "usage: --jobs '$bad_jobs' names the rule"
done
TEST_JOBS=1 bash "$BOX/tests/run.sh" --frobnicate </dev/null >"$BOX/bad.out" 2>&1
assert_eq "2" "$?" "usage: an unknown flag exits 2"

# --- named files: only those run; a missing one is a usage error --------------
NAMED="$(bash "$BOX/tests/run.sh" tests/test-alpha.sh </dev/null 2>&1)"; NSTATUS=$?
assert_eq "0" "$NSTATUS" "named: exit 0 when the named file passes"
assert_contains "$NAMED" "=== tests/test-alpha.sh ===" "named: the named file runs"
assert_not_contains "$NAMED" "test-stdin.sh" "named: an unnamed file does not run"
assert_contains "$NAMED" "RESULT: all 1 test files passed" "named: the RESULT counts only named files"
NAMED="$(bash "$BOX/tests/run.sh" --jobs 2 tests/test-alpha.sh tests/test-stdin.sh </dev/null 2>&1)"
assert_contains "$NAMED" "RESULT: all 2 test files passed" "named: --jobs combines with named files"
bash "$BOX/tests/run.sh" tests/test-missing.sh </dev/null >"$BOX/bad.out" 2>&1
assert_eq "2" "$?" "named: a missing named path exits 2"
assert_file_contains "$BOX/bad.out" "tests/test-missing.sh" "named: the missing path is named"

# --- TEST_PYTHON resolution ---------------------------------------------------
LIB="$REPO/tests/lib.sh"
assert_eq "/preset/python" "$(TEST_PYTHON=/preset/python "$BASH" -c '. "$1"; printf %s "$TEST_PYTHON"' _ "$LIB")" \
  "TEST_PYTHON: a preset value wins"
assert_eq "42" "$(env -u TEST_PYTHON "$BASH" -c '. "$1"; "$TEST_PYTHON" -c "print(42)"' _ "$LIB" 2>&1)" \
  "TEST_PYTHON: resolves to a working interpreter on this machine"
assert_eq "yes" "$(env -u TEST_PYTHON "$BASH" -c 'set -eu; . "$1"; [ -n "$TEST_PYTHON" ] && echo yes' _ "$LIB")" \
  "TEST_PYTHON: the library loads under set -eu"

# A fake Windows layout: the Store alias first on PATH, two real CPython builds
# under LOCALAPPDATA, handed over with backslashes as Git Bash does.
FAKE="$BOX/fake"
mkdir -p "$FAKE/WindowsApps" "$FAKE/local/Programs/Python/Python39" "$FAKE/local/Programs/Python/Python312" "$FAKE/bin"
printf '#!/bin/sh\nexit 99\n' > "$FAKE/WindowsApps/python3"
printf '#!/bin/sh\necho 3.9\n' > "$FAKE/local/Programs/Python/Python39/python.exe"
printf '#!/bin/sh\necho 3.12\n' > "$FAKE/local/Programs/Python/Python312/python.exe"
printf '#!/bin/sh\necho on-path\n' > "$FAKE/bin/python3"
chmod +x "$FAKE/WindowsApps/python3" "$FAKE/local/Programs/Python/Python39/python.exe" \
  "$FAKE/local/Programs/Python/Python312/python.exe" "$FAKE/bin/python3"
BACKSLASHED="$FAKE/local"; BACKSLASHED=${BACKSLASHED//\//\\}

resolve_with() {  # <PATH> <LOCALAPPDATA>; the all-users install root is pointed nowhere
  env -u TEST_PYTHON PATH="$1" LOCALAPPDATA="$2" TEST_PYTHON_SYSTEM_ROOT="$BOX/nowhere" \
    "$BASH" -c '. "$1"; printf %s "$TEST_PYTHON"' _ "$LIB"
}
assert_eq "$FAKE/local/Programs/Python/Python312/python.exe" "$(resolve_with "$FAKE/WindowsApps" "$BACKSLASHED")" \
  "TEST_PYTHON: skips the Store launcher and picks the newest real CPython"
assert_eq "python3" "$(resolve_with "$FAKE/bin:$FAKE/WindowsApps" "$BACKSLASHED")" \
  "TEST_PYTHON: a python3 that is not the Store launcher wins over the install scan"
assert_eq "python3" "$(resolve_with "$FAKE/WindowsApps" "$BOX/nowhere")" \
  "TEST_PYTHON: with only the launcher available, the name stays python3 as before"
printf '#!/bin/sh
echo py
' > "$FAKE/bin/py"; chmod +x "$FAKE/bin/py"; rm -f "$FAKE/bin/python3"
assert_eq "py" "$(resolve_with "$FAKE/bin:$FAKE/WindowsApps" "$BOX/nowhere")" \
  "TEST_PYTHON: the py launcher is the last resort before the plain name"
case "$(now_ms)" in ''|*[!0-9]*) assert_eq "digits" "$(now_ms)" "now_ms: returns milliseconds as digits" ;;
  *) assert_eq "digits" "digits" "now_ms: returns milliseconds as digits" ;; esac

finish
