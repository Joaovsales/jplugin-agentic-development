# tests/lib.sh — minimal zero-dependency assertion helpers.
# Source this from a test-*.sh script, call assertions, then call `finish`.
# No external deps: pure bash + coreutils (grep). Works in any POSIX-ish shell.

_TESTS=0
_FAILS=0

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
