# tests/lib.sh — minimal zero-dependency assertion helpers.
# Source this from a test-*.sh script, call assertions, then call `finish`.
# No external deps: pure bash + coreutils (grep). Works in any POSIX-ish shell.

_TESTS=0
_FAILS=0

# now_ms — wall-clock milliseconds, for elapsed-time reporting. Bash 5 exposes
# EPOCHREALTIME as a shell variable (no process); older shells fall back to
# whole seconds from date. Callers must only ever compare two readings.
now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    # bash prints EPOCHREALTIME with the locale's decimal mark; keep the digits only.
    printf '%s\n' "$(( ${EPOCHREALTIME//[!0-9]/} / 1000 ))"
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

# TEST_PYTHON — the one interpreter every test invokes (`"$TEST_PYTHON" script`).
#
# On Windows the `python3` first on PATH is usually the Microsoft Store
# execution alias under WindowsApps: a launcher that adds roughly half a second
# to every start, on top of the second-per-spawn the platform already charges.
# Sixty call sites, several inside per-assertion loops, turned that into most
# of the suite's Python cost (#136). Resolution order:
#   1. a preset TEST_PYTHON wins — tests/run.sh resolves once and exports, so
#      the 42 files sourcing this library do not each repeat the probe;
#   2. `python3`, then `python`, when neither resolves under WindowsApps;
#   3. the newest CPython under $LOCALAPPDATA/Programs/Python or
#      /c/Program Files (a real python.exe, not the launcher);
#   4. the `py` launcher, the fallback two files used to carry themselves;
#   5. plain `python3`, so a machine with only the Store build (or none)
#      behaves exactly as before: the same interpreter, or the same error at
#      the first use.
# TEST_PYTHON_SYSTEM_ROOT overrides the all-users root (the runner test points
# it at an empty directory so the host's own installs cannot change a verdict).
# Only builtins and one `command -v` per candidate run here; nothing is spawned.
_store_launcher() { case "$1" in */WindowsApps/*) return 0 ;; esac; return 1; }

_newest_cpython() {
  # Git Bash hands LOCALAPPDATA over as C:\Users\..., which bash cannot glob;
  # convert a private copy rather than the variable the code under test inherits.
  _local="${LOCALAPPDATA:-}"; _local=${_local//\\//}
  _best="" _best_minor=-1
  for _exe in "${_local:-/nonexistent}"/Programs/Python/Python3*/python.exe \
              "${TEST_PYTHON_SYSTEM_ROOT:-/c/Program Files}/Python3"*/python.exe; do
    [ -x "$_exe" ] || continue
    _minor="${_exe%/python.exe}"; _minor="${_minor##*/Python3}"
    case "$_minor" in ''|*[!0-9]*) continue ;; esac
    if [ "$_minor" -gt "$_best_minor" ]; then _best="$_exe"; _best_minor="$_minor"; fi
  done
  printf '%s\n' "$_best"
}

resolve_test_python() {
  if [ -n "${TEST_PYTHON:-}" ]; then return 0; fi
  for _name in python3 python; do
    _found="$(command -v "$_name" 2>/dev/null || true)"
    if [ -n "$_found" ] && ! _store_launcher "$_found"; then
      TEST_PYTHON="$_name"; return 0
    fi
  done
  _found="$(_newest_cpython)"
  if [ -n "$_found" ]; then TEST_PYTHON="$_found"; return 0; fi
  if command -v py >/dev/null 2>&1; then TEST_PYTHON=py; return 0; fi
  TEST_PYTHON=python3
}

resolve_test_python
export TEST_PYTHON
# Windows CPython writes stdout in the console code page (cp1252) unless told
# otherwise, so every em dash a script prints reaches the assertion as one
# 0x97 byte and never matches the UTF-8 needle in the test. The suite compares
# text, not bytes-as-rendered: force UTF-8 so a local Windows run gives the
# verdict Linux CI gives.
export PYTHONUTF8=1

# assert_contains <haystack> <needle> <message>
assert_contains() {
  _TESTS=$((_TESTS + 1))
  case "$1" in
    *"$2"*) printf '  ok   %s\n' "$3" ;;
    *) _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       expected to contain: %s\n' "$3" "$2" ;;
  esac
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
  _TESTS=$((_TESTS + 1))
  # An empty haystack fails rather than passing. Absence-of-needle is trivially
  # true of the empty string, so a grep or sed extraction that matched nothing
  # would otherwise report "ok" and turn a load-bearing check into a silent pass.
  # Closed here because the hazard is structural: leaving it to each caller to
  # check its own extraction is the discipline whose absence causes the bug.
  # (assert_contains needs no such guard — an empty haystack cannot contain a
  # non-empty needle, so it already fails.)
  if [ -z "$1" ]; then
    _FAILS=$((_FAILS + 1))
    printf '  FAIL %s\n       haystack empty — the extraction found nothing to check\n' "$3"
    return
  fi
  case "$1" in
    *"$2"*) _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       expected NOT to contain: %s\n' "$3" "$2" ;;
    *) printf '  ok   %s\n' "$3" ;;
  esac
}

# assert_file_contains <file> <literal-needle> <message>
assert_file_contains() {
  _TESTS=$((_TESTS + 1))
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
    printf '  ok   %s\n' "$3"
  else
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       file %s missing or lacks: %s\n' "$3" "$1" "$2"
  fi
}

# assert_prose_contains <file> <phrase> <message>
# Matches a phrase across line wraps. Markdown prose here is hard-wrapped, so a
# literal grep for a phrase that happens to straddle a newline fails for a reason
# unrelated to the assertion's intent -- and picking a needle that fits on one
# line just defers the problem to the next reflow. Collapses all whitespace in
# both haystack and needle to single spaces before comparing.
assert_prose_contains() {
  _TESTS=$((_TESTS + 1))
  if [ ! -f "$1" ]; then
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       file %s is missing\n' "$3" "$1"
    return
  fi
  _hay="$(tr -s '[:space:]' ' ' < "$1")"
  _need="$(printf '%s' "$2" | tr -s '[:space:]' ' ')"
  case "$_hay" in
    *"$_need"*) printf '  ok   %s\n' "$3" ;;
    *) _FAILS=$((_FAILS + 1))
       printf '  FAIL %s\n       file %s lacks prose: %s\n' "$3" "$1" "$2" ;;
  esac
}

# assert_file_matches <file> <regex> <message>
# Regex counterpart to assert_file_contains, which is literal-only (grep -qF).
# Without it, a caller needing an anchored pattern such as '^model:' hand-rolls
# grep plus raw _TESTS/_FAILS arithmetic — duplicating the counting logic and
# reaching past this file's function interface.
assert_file_matches() {
  _TESTS=$((_TESTS + 1))
  if [ -f "$1" ] && grep -qE -- "$2" "$1"; then
    printf '  ok   %s\n' "$3"
  else
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       file %s missing or lacks pattern: %s\n' "$3" "$1" "$2"
  fi
}

# assert_file_not_matches <file> <regex> <message>
# A missing file fails: absence of the pattern is not a pass when there was
# nothing to search, for the same reason assert_not_contains rejects empty input.
assert_file_not_matches() {
  _TESTS=$((_TESTS + 1))
  if [ ! -f "$1" ]; then
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       file %s is missing\n' "$3" "$1"
  elif grep -qE -- "$2" "$1"; then
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       file %s unexpectedly matches: %s\n' "$3" "$1" "$2"
  else
    printf '  ok   %s\n' "$3"
  fi
}

# assert_eq <expected> <actual> <message>
assert_eq() {
  _TESTS=$((_TESTS + 1))
  if [ "$1" = "$2" ]; then
    printf '  ok   %s\n' "$3"
  else
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$3" "$1" "$2"
  fi
}

# assert_files_identical <file-a> <file-b> <message>
assert_files_identical() {
  _TESTS=$((_TESTS + 1))
  if [ -f "$1" ] && [ -f "$2" ] && diff -q "$1" "$2" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$3"
  else
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       files differ or missing: %s vs %s\n' "$3" "$1" "$2"
  fi
}

# assert_files_differ <file-a> <file-b> <message>
assert_files_differ() {
  _TESTS=$((_TESTS + 1))
  if [ -f "$1" ] && [ -f "$2" ] && ! diff -q "$1" "$2" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$3"
  else
    _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n       files are identical or missing: %s vs %s\n' "$3" "$1" "$2"
  fi
}

# finish — report and exit non-zero if any assertion failed.
finish() {
  if [ "$_FAILS" -gt 0 ]; then
    printf '  -> %d/%d assertions FAILED\n' "$_FAILS" "$_TESTS"
    exit 1
  fi
  printf '  -> %d assertions passed\n' "$_TESTS"
  exit 0
}
