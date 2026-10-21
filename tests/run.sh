#!/bin/bash
# tests/run.sh — discover and run every tests/test-*.sh from the repo root.
# Each test file is a standalone script that sources tests/lib.sh and calls
# `finish`. Exit non-zero if any test file fails. No external dependencies.
#
#   bash tests/run.sh [--jobs N] [file ...]   # or TEST_JOBS=N
#
# With file arguments (paths from the repo root) only those files run —
# tests/affected.sh --run passes its list here; with none, every
# tests/test-*.sh runs. A named path that does not exist is a usage error.
#
# Every file runs with stdin closed: a hook under test that slurps its payload
# from stdin must not inherit an agent shell's open pipe
# (tasks/solutions/bugs/test-suite-hangs-when-stdin-is-an-open-pipe.md).
#
# Every file also runs under `timeout "${TEST_FILE_TIMEOUT:-300}"` (coreutils): a
# hung file is killed with its whole process group and reported as
# `FAIL <file> timed out after N s`, counted as failed, so one hang cannot
# consume the CI job (PR #177).
#
# Elapsed seconds are printed after each file and summarised at the end. On
# Windows every process spawn costs a large fraction of a second, so the suite
# is process-bound and a slow file has to be visible, not inferred (#136).
#
# `--jobs N` runs up to N files at once. The files are independent — each
# builds its own mktemp fixture — and on a platform where the spawn itself is
# the cost, concurrency is the one lever that reaches every file. With N > 1 a
# file's output is held and printed as one block when it finishes, so blocks
# never interleave; the RESULT line and exit status are the same as a serial
# run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  printf 'usage: bash tests/run.sh [--jobs N] [file ...]\n' >&2
  exit 2
}

jobs="${TEST_JOBS:-1}"
named=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) [ $# -ge 2 ] || usage; jobs="$2"; shift 2 ;;
    --jobs=*) jobs="${1#--jobs=}"; shift ;;
    -*) usage ;;
    *) named+=("$1"); shift ;;
  esac
done
for test_file in ${named[@]+"${named[@]}"}; do
  [ -f "$test_file" ] || { printf 'tests/run.sh: no such test file: %s\n' "$test_file" >&2; exit 2; }
done
case "$jobs" in
  ''|*[!0-9]*|0)
    printf 'tests/run.sh: --jobs wants a positive integer, got %s\n' "${jobs:-nothing}" >&2
    exit 2 ;;
esac
file_timeout="${TEST_FILE_TIMEOUT:-300}"
case "$file_timeout" in
  ''|*[!0-9]*|0)
    printf 'tests/run.sh: TEST_FILE_TIMEOUT wants a positive integer of seconds, got %s\n' "${file_timeout:-nothing}" >&2
    exit 2 ;;
esac
command -v timeout >/dev/null 2>&1 || { printf 'tests/run.sh: needs coreutils timeout on PATH (macOS: brew install coreutils)\n' >&2; exit 2; }
if [ "$jobs" -gt 1 ] && { [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; }; then
  printf 'tests/run.sh: --jobs needs bash 4.3+ (wait -n); this is %s\n' "$BASH_VERSION" >&2
  exit 2
fi

# Resolve the interpreter once here; every file sourcing tests/lib.sh then
# inherits TEST_PYTHON instead of repeating the probe.
. tests/lib.sh

SCRATCH="$(mktemp -d)"
[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] || { printf 'tests/run.sh: mktemp -d failed\n' >&2; exit 2; }
trap 'rm -rf "$SCRATCH"' EXIT

total=0
failed=0
timings=""
pending=""
running=0
sum_passed=0; sum_failed=0; sum_xfail=0; sum_skipped=0

# run_file <file> <output-path>: run one test file with stdin closed, output
# to <output-path> and, when <stream> is 1, to the terminal as it is produced.
# A file over TEST_FILE_TIMEOUT is killed (timeout's exit 124) and a FAIL line
# naming the limit is appended to its output. Sets status and elapsed.
run_file() {
  started="$(now_ms)"
  if [ "${3:-0}" -eq 1 ]; then
    timeout "$file_timeout" bash "$1" </dev/null 2>&1 | tee "$2"
  else
    timeout "$file_timeout" bash "$1" </dev/null >"$2" 2>&1
  fi
  status=$?
  elapsed=$(( ($(now_ms) - started + 500) / 1000 ))
  if [ "$status" -eq 124 ]; then
    printf '  FAIL %s timed out after %s s\n' "$1" "$file_timeout" >>"$2"
    [ "${3:-0}" -eq 1 ] && printf '  FAIL %s timed out after %s s\n' "$1" "$file_timeout"
  fi
}

# tally <output-path>: add the file's trailer to the suite-wide assertion
# counts. tests/lib.sh prints `-> P passed, F failed, X xfail, S skipped`; the
# two in-process Python files print the older `-> N assertions passed` or
# `-> F/N assertions FAILED`, read the same way so the sum is whole.
tally() {
  local trailer p f x s
  trailer="$(grep -E '^  -> ' "$1" | tail -1)"
  case "$trailer" in
    *" passed, "*" failed, "*" xfail, "*" skipped")
      read -r _ p _ f _ x _ s _ <<<"$trailer" ;;
    *"/"*" assertions FAILED")
      f="${trailer#  -> }"; f="${f%%/*}"; p="${trailer#*/}"; p="${p%% *}"; p=$((p - f)); x=0; s=0 ;;
    *" assertions passed")
      p="${trailer#  -> }"; p="${p%% *}"; f=0; x=0; s=0 ;;
    *) return ;;
  esac
  sum_passed=$((sum_passed + p)); sum_failed=$((sum_failed + f))
  sum_xfail=$((sum_xfail + x)); sum_skipped=$((sum_skipped + s))
}

# record <file> <status> <elapsed-seconds> <output-path>: print the trailer
# and count.
record() {
  [ "$2" -eq 0 ] || failed=$((failed + 1))
  printf -- '--- %s: %d s ---\n' "$1" "$3"
  timings="$timings$3 $1"$'\n'
  [ -f "$4" ] && tally "$4"
}

launch() {
  pending="$pending $1"
  (
    run_file "$1" "$SCRATCH/${1##*/}.out"
    printf '%s %s\n' "$status" "$elapsed" >"$SCRATCH/${1##*/}.meta.tmp"
    mv "$SCRATCH/${1##*/}.meta.tmp" "$SCRATCH/${1##*/}.meta"
  ) &
  running=$((running + 1))
}

# collect: print every pending file whose run has finished, in finish order.
collect() {
  still=""
  for f in $pending; do
    if [ -f "$SCRATCH/${f##*/}.meta" ]; then
      read -r status elapsed <"$SCRATCH/${f##*/}.meta"
      printf '\n=== %s ===\n' "$f"
      cat "$SCRATCH/${f##*/}.out"
      record "$f" "$status" "$elapsed" "$SCRATCH/${f##*/}.out"
    else
      still="$still $f"
    fi
  done
  pending="$still"
}

wall_started="$(now_ms)"
shopt -s nullglob
[ ${#named[@]} -gt 0 ] || named=(tests/test-*.sh)
for test_file in ${named[@]+"${named[@]}"}; do
  total=$((total + 1))
  if [ "$jobs" -eq 1 ]; then
    printf '\n=== %s ===\n' "$test_file"
    run_file "$test_file" "$SCRATCH/${test_file##*/}.out" 1
    record "$test_file" "$status" "$elapsed" "$SCRATCH/${test_file##*/}.out"
    continue
  fi
  if [ "$running" -ge "$jobs" ]; then
    wait -n
    running=$((running - 1))
    collect
  fi
  launch "$test_file"
done
while [ "$running" -gt 0 ]; do
  wait -n
  running=$((running - 1))
  collect
done
# A file whose runner died before it could report is a failure, never a pass.
for f in $pending; do
  printf '\n=== %s ===\n  FAIL the runner for this file exited without a result\n' "$f"
  record "$f" 1 0 ""
done
wall=$(( ($(now_ms) - wall_started + 500) / 1000 ))

printf '\n========================================\n'
if [ "$total" -eq 0 ]; then
  printf 'RESULT: no test files found (tests/test-*.sh)\n'
  exit 1
fi
printf 'TOTAL: %d files, wall %d s (jobs=%d)\n' "$total" "$wall" "$jobs"
printf 'ASSERTIONS: %d passed, %d failed, %d xfail, %d skipped\n' \
  "$sum_passed" "$sum_failed" "$sum_xfail" "$sum_skipped"
printf 'SLOWEST:\n'
printf '%s' "$timings" | sort -nr | head -5 | while read -r seconds file; do
  printf '  %5d s  %s\n' "$seconds" "$file"
done
if [ "$failed" -gt 0 ]; then
  printf 'RESULT: %d/%d test files FAILED\n' "$failed" "$total"
  exit 1
fi
printf 'RESULT: all %d test files passed\n' "$total"
exit 0
