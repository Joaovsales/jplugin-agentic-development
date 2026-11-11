# tests/lib.sh — the test harness as a deep module (specs/test-suite-aposd.md).
# Source this from a test-*.sh script, declare what the file covers, assert,
# then call `finish`. Pure bash plus coreutils and git; nothing else.
#
# A test file states WHAT it checks; this library owns HOW — fixtures and
# their cleanup, capture, verdicts, counting, failure output and the string
# tests/affected.sh selects on. The interface, in the order a file uses it:
#
#   under_test <repo-relative path>    the artefact this file covers; prints
#                                      the absolute path and is the literal
#                                      affected.sh prefix-matches
#   py_module <repo-relative dir> [var]  a Python package under test: declared
#                                      like under_test, printed like it (or
#                                      assigned to var) and put on PYTHONPATH
#   fixture_dir / fixture_repo         a scratch directory / git repository,
#                                      removed when the file exits
#   fixture_copy <area/seed> <dest>    shared seed content from tests/fixtures/
#   run <cmd...>                       capture: sets output (stdout+stderr)
#                                      and status, stdin closed
#   assert_exit <n> <msg> [-- cmd...]  status of the last run, or of cmd
#   assert_refused <n> <reason> [<msg>] -- cmd...
#                                      exit code AND reason fragment, one call
#   assert_true / assert_false <msg> -- cmd...
#   assert_eq, assert_contains, assert_not_contains, assert_file_contains,
#   assert_file_matches, assert_file_not_matches, assert_prose_contains,
#   assert_files_identical, assert_files_differ, assert_file_exists,
#   assert_file_absent, assert_precedes
#   assert_sweep_empty <label> <control> -- grep-args... -- <root>...
#                                      an absence sweep with a positive control
#   pass <msg> / fail <msg> [actual]   a verdict reached by hand
#   skip <reason>                      the file cannot run here; counted
#   begin_case <name> / end_case       a named run of assertions: a header, a
#                                      count, and TEST_CASE=<glob> to keep only
#                                      the matching cases
#   finish                             trailer and exit status
#
# Every failure prints the assertion's file:line and the actual value, the
# first 20 lines with a pointer to the rest. A setup primitive that cannot do
# its job (a missing artefact, seed or scratch directory) stops the file at
# once, even from inside a command substitution: it signals the file's shell.

_TESTS=0
_FAILS=0
_XFAIL=0
_SKIPPED=0
# Case state (begin_case below): the open case's name, how many cases
# TEST_CASE kept out or selected in this file, and the counters at the case's
# start.
_CASE=""
_CASE_OUT=0
_CASE_IN=0
_CASE_BASE=(0 0 0 0)

case "${BASH_SOURCE[0]}" in
  */*) _LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _LIB_DIR="$(pwd)" ;;
esac
_LIB_REPO="${_LIB_DIR%/*}"

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
# One environment for every file, set once here rather than per file: a repo
# module imported by a test must not write __pycache__ under .agents/ (the
# byte-parity test reads that tree), and `sort`, `[[:space:]]` and glob order
# must not vary with the host's locale.
export PYTHONDONTWRITEBYTECODE=1
export LC_ALL=C

# ---------------------------------------------------------------------------
# Verdicts and counting. pass and fail are the only writers of _TESTS and
# _FAILS; every assertion below reaches a verdict through one of them.

# _where — file:line of the assertion in the test file: the first call frame
# whose source is not this library, so a helper defined in the test file is
# reported at its own line and a library-internal frame never is.
_where() {
  local i
  for ((i = 1; i < ${#BASH_SOURCE[@]}; i++)); do
    [ "${BASH_SOURCE[$i]}" = "${BASH_SOURCE[0]}" ] && continue
    printf '%s:%s' "${BASH_SOURCE[$i]}" "${BASH_LINENO[$((i - 1))]}"
    return
  done
  printf '%s:%s' "$0" "${BASH_LINENO[0]}"
}

# _print_actual <label> <value> — the first 20 lines of a value under a label,
# with a pointer to the rest (AGENTS.md § Large-Artifact Handoff). A line over
# 300 characters is cut with an ellipsis so a flattened file stays readable.
# Builtins only: a failure must print even where nothing can be spawned.
_print_actual() {
  local label="$1" value="$2" newlines total shown=0 line
  [ -n "$value" ] || { printf '       %s (empty)\n' "$label"; return; }
  newlines="${value//[!$'\n']/}"; total=$(( ${#newlines} + 1 ))
  if [ "$total" -gt 20 ]; then
    printf '       %s (%d lines, first 20)\n' "$label" "$total"
  elif [ "$total" -gt 1 ]; then
    printf '       %s\n' "$label"
  else
    printf '       %s %s\n' "$label" "$(_clip "$value")"
    return
  fi
  while IFS= read -r line; do
    printf '       %s\n' "$(_clip "$line")"
    shown=$((shown + 1))
    [ "$shown" -lt 20 ] || break
  done <<<"$value"
  [ "$total" -le 20 ] || printf '       … %d more lines\n' "$((total - 20))"
}
_clip() { if [ "${#1}" -gt 300 ]; then printf '%s…' "${1:0:300}"; else printf '%s' "$1"; fi; }

# The platform baseline (specs/test-suite-aposd.md D2). tests/expected-failures.txt
# lists `<file> <platform-glob> <message-glob>` rows; the rows for this file
# whose platform glob matches $OSTYPE (TEST_PLATFORM overrides it) load here.
# A listed failure prints XFAIL and is not counted as failed; a listed message
# that passes is an XPASS and fails the file, so the list can only shrink.
# Linux CI matches no row and runs exactly as without the file.
_XFAIL_ROWS=()
_load_expected_failures() {
  local file="${TEST_EXPECTED_FAILURES:-$_LIB_DIR/expected-failures.txt}" me="${0##*/}"
  local line f rest p
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    f="${line%% *}"; rest="${line#* }"; p="${rest%% *}"
    [ "${f##*/}" = "$me" ] || continue
    # shellcheck disable=SC2254 — the platform column is a glob by contract.
    case "${TEST_PLATFORM:-$OSTYPE}" in $p) _XFAIL_ROWS+=("${rest#* }") ;; esac
  done < "$file"
}
_load_expected_failures
# _expected_failure <message> — listed for this file, literally or by glob.
_expected_failure() {
  local r
  for r in ${_XFAIL_ROWS[@]+"${_XFAIL_ROWS[@]}"}; do
    [ "$r" = "$1" ] && return 0
    # shellcheck disable=SC2254
    case "$1" in $r) return 0 ;; esac
  done
  return 1
}

# pass <message>
pass() {
  _TESTS=$((_TESTS + 1))
  if _expected_failure "$1"; then
    _FAILS=$((_FAILS + 1))
    printf '  XPASS %s\n       listed in tests/expected-failures.txt but passed here — remove its row\n' "$1"
    return 0
  fi
  printf '  ok   %s\n' "$1"
  return 0
}

# _fail_count <message> — the one recorder of a failure: counts it and prints
# the message and the assertion's file:line. Returns 1 for a failure listed in
# the baseline (printed as XFAIL, nothing more to say), 0 for a real one.
_fail_count() {
  _TESTS=$((_TESTS + 1))
  if _expected_failure "$1"; then
    _XFAIL=$((_XFAIL + 1))
    printf '  XFAIL %s\n' "$1"
    return 1
  fi
  _FAILS=$((_FAILS + 1))
  printf '  FAIL %s\n       at %s%s\n' "$1" "$(_where)" "${_CASE:+  [case: $_CASE]}"
}

# _fail_detail <message> <detail line> — a failure with a line of explanation
# and no value (an empty detail prints no line).
_fail_detail() {
  _fail_count "$1" || return 0
  [ -z "$2" ] || printf '       %s\n' "$2"
}

# _fail_value <message> <label> <value> [<detail line>] — a failure with the
# actual value under its label, after the detail line when one is given.
_fail_value() {
  _fail_count "$1" || return 0
  [ -z "${4:-}" ] || printf '       %s\n' "$4"
  _print_actual "$2" "$3"
}

# fail <message> [<actual value>] — a verdict reached by hand. Prints the
# message, the assertion's file:line and, when given (an empty value counts),
# the value under "actual:". Anything more stops the file: labels and detail
# lines belong to the library's own assertions (_fail_detail, _fail_value).
fail() {
  { [ $# -ge 1 ] && [ $# -le 2 ]; } || _abort "fail takes <message> [<actual>], not $# arguments"
  if [ $# -eq 2 ]; then _fail_value "$1" "actual:" "$2"; else _fail_detail "$1" ""; fi
}

# skip <reason> — this file cannot run here. Counted, printed as SKIP, and a
# failure of the file under REQUIRE_ALL=1 (CI sets it), so a skipped check is
# visible there and never silently green.
skip() {
  _SKIPPED=$((_SKIPPED + 1))
  printf '  SKIP %s\n' "$1"
}

# ---------------------------------------------------------------------------
# Cases (specs/test-suite-aposd.md D4). A case is a named run of assertions
# inside one file: begin_case prints a header and starts a count, end_case
# prints the count. TEST_CASE=<glob> keeps only the cases whose name matches the
# glob. The one supported form wraps the case's body:
#   if begin_case "name"; then ...; fi; end_case
# begin_case returns 1 for a filtered case, prints its filtered-out line and
# opens NO case, so the body's work is skipped and nothing is muted: the
# file's own assertions after the fi count whatever the filter. end_case may sit
# after the fi or inside the body; with no case open it does nothing. A case
# that was never ended is closed by the next begin_case and by finish. A case
# owns no setup or teardown and no counter of its own: it reads the file's,
# which pass and the failure recorder alone write.

# end_case — print the open case's count and return to the file's own level.
end_case() {
  [ -n "$_CASE" ] || return 0
  local line tests=$((_TESTS - _CASE_BASE[0])) failed=$((_FAILS - _CASE_BASE[1])) xfail=$((_XFAIL - _CASE_BASE[2])) skipped=$((_SKIPPED - _CASE_BASE[3]))
  line="$((tests - failed - xfail)) passed, $failed failed"
  [ "$xfail" -eq 0 ] || line="$line, $xfail xfail"
  [ "$skipped" -eq 0 ] || line="$line, $skipped skipped"
  printf '  == %s: %s\n' "$_CASE" "$line"
  _CASE=""
}

# begin_case <name> — returns 0 when the case runs, 1 when TEST_CASE filters it.
begin_case() {
  [ -n "${1:-}" ] || _abort "begin_case: a case needs a name"
  end_case
  if [ -n "${TEST_CASE:-}" ]; then
    # shellcheck disable=SC2254 — TEST_CASE is a glob by contract.
    case "$1" in
      $TEST_CASE) ;;
      *)
        _CASE_OUT=$((_CASE_OUT + 1))
        printf '  == %s: filtered out by TEST_CASE=%s\n' "$1" "$TEST_CASE"
        return 1 ;;
    esac
  fi
  _CASE="$1"
  _CASE_IN=$((_CASE_IN + 1))
  _CASE_BASE=("$_TESTS" "$_FAILS" "$_XFAIL" "$_SKIPPED")
  printf '  == case: %s\n' "$1"
}

# ---------------------------------------------------------------------------
# Setup primitives. These stop the file when they cannot do their job: a
# renamed artefact, a missing seed or a failed mktemp is never a passing run.
# `exit` inside `$(...)` leaves only the subshell, so the stop is a signal to
# the file's own shell, whose TERM handler cleans up and exits 143.

# One fixture root per test file, named from the file's pid so a command
# substitution can create it and the EXIT handler still finds it.
_FIXTURE_ROOT="${TMPDIR:-/tmp}/jplugin-test-$$"
_cleanup_fixtures() { [ -d "$_FIXTURE_ROOT" ] && rm -rf "$_FIXTURE_ROOT"; return 0; }
trap _cleanup_fixtures EXIT
trap '_cleanup_fixtures; exit 143' TERM

_abort() {
  printf '  ABORT %s\n       at %s\n' "$1" "$(_where)" >&2
  if [ "$BASHPID" = "$$" ]; then _cleanup_fixtures; exit 143; fi
  kill -s TERM "$$"
  exit 143
}

# fixture_dir — a fresh scratch directory, removed when the file exits.
fixture_dir() {
  local d
  mkdir -p "$_FIXTURE_ROOT" || _abort "fixture_dir: cannot create $_FIXTURE_ROOT"
  d="$(mktemp -d "$_FIXTURE_ROOT/f.XXXXXX")" && [ -d "$d" ] || _abort "fixture_dir: mktemp -d failed under $_FIXTURE_ROOT"
  printf '%s\n' "$d"
}

# fixture_repo — fixture_dir with `git init`; identity, `commit.gpgsign` and
# `core.autocrlf` written straight into .git/config (one spawn, not four).
fixture_repo() {
  local d
  d="$(fixture_dir)" || exit 143
  git -C "$d" init -q >/dev/null 2>&1 || _abort "fixture_repo: git init failed in $d"
  printf '[user]\n\tname = test\n\temail = test@example.com\n[commit]\n\tgpgsign = false\n[core]\n\tautocrlf = false\n' \
    >> "$d/.git/config"
  printf '%s\n' "$d"
}

# fixture_copy <area/seed> <dest> — copy tests/fixtures/<area>/<seed> (a file
# or a directory) to <dest>, creating the parent.
fixture_copy() {
  local src="$_LIB_DIR/fixtures/$1"
  [ -e "$src" ] || _abort "fixture_copy: no seed tests/fixtures/$1"
  case "$2" in */*) mkdir -p "${2%/*}" ;; esac
  cp -r "$src" "$2" || _abort "fixture_copy: cannot copy tests/fixtures/$1 to $2"
}

# under_test <repo-relative path> — the artefact this file covers. Prints the
# absolute path; the literal argument is what tests/affected.sh prefix-matches,
# so one mention serves selection and the test. A path that does not exist
# stops the file: a renamed script cannot silently drop a test from selection.
under_test() {
  [ -e "$_LIB_REPO/$1" ] || _abort "under_test: no such path $1 — the artefact this file covers has moved"
  printf '%s\n' "$_LIB_REPO/$1"
}

# py_module <repo-relative dir> [<variable>] — a Python package under test:
# declared like under_test, which it matches in printing the absolute path, and
# prepended to PYTHONPATH for every "$TEST_PYTHON" the file runs. A command
# substitution would lose that export, so a file that also needs the path names
# a variable: it is assigned here, in the file's own shell, and nothing prints.
py_module() {
  [ -d "$_LIB_REPO/$1" ] || _abort "py_module: no such directory $1"
  export PYTHONPATH="$_LIB_REPO/$1${PYTHONPATH:+:$PYTHONPATH}"
  if [ -n "${2:-}" ]; then printf -v "$2" '%s' "$_LIB_REPO/$1"; else printf '%s\n' "$_LIB_REPO/$1"; fi
}

# ---------------------------------------------------------------------------
# Capture and exit-code verdicts.

# run <cmd...> — run with stdin closed; stdout and stderr land in `output`,
# the exit code in `status`. Never a verdict by itself.
run() {
  status=0
  output="$("$@" </dev/null 2>&1)" || status=$?
}

# assert_exit <expected> <message> [-- cmd...]
# With a command: run it and judge its exit code. Without: judge the last run.
assert_exit() {
  local want="$1" msg="$2"; shift 2
  if [ "${1:-}" = "--" ]; then shift; run "$@"; fi
  if [ -z "${status-}" ]; then _fail_detail "$msg" "assert_exit before any run"; return; fi
  if [ "$status" -eq "$want" ]; then pass "$msg"; else _fail_value "$msg" "output:" "$output" "exit $status, expected $want"; fi
}

# assert_refused <exit> <reason-fragment> [<message>] -- cmd...
# A refusal is one verdict that owns both halves: the exit code AND the reason
# the command printed, so a different guard refusing the same input cannot
# satisfy it. A fragment under 6 characters is too short to name a guard and
# is itself a failure.
assert_refused() {
  local want="$1" frag="$2" msg; shift 2
  if [ "${1:-}" = "--" ]; then msg=""; else msg="$1"; shift; fi
  [ "${1:-}" = "--" ] && shift
  [ -n "$msg" ] || msg="refused with exit $want naming \"$frag\": ${1:-}${2:+ $2}${3:+ $3}"
  if [ "${#frag}" -lt 6 ]; then
    _fail_detail "$msg" "reason fragment \"$frag\" is under 6 characters — too short to pin which guard refused"
    return
  fi
  run "$@"
  if [ "$status" -ne "$want" ]; then
    _fail_value "$msg" "output:" "$output" "exit $status, expected $want"
  else
    case "$output" in
      *"$frag"*) pass "$msg" ;;
      *) _fail_value "$msg" "output:" "$output" "output lacks \"$frag\"" ;;
    esac
  fi
}

# assert_true <message> -- cmd... / assert_false <message> -- cmd...
# A boolean verdict on any command, for the checks no string assertion fits.
assert_true() {
  local msg="$1"; shift; [ "${1:-}" = "--" ] && shift
  if "$@"; then pass "$msg"; else _fail_value "$msg" "command:" "$*"; fi
}
assert_false() {
  local msg="$1"; shift; [ "${1:-}" = "--" ] && shift
  if "$@"; then _fail_value "$msg" "command (succeeded):" "$*"; else pass "$msg"; fi
}

# ---------------------------------------------------------------------------
# String and file assertions.

# assert_contains <haystack> <needle> <message>
assert_contains() {
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) _fail_value "$3" "actual:" "$1" "expected to contain: $2" ;;
  esac
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
  # An empty haystack fails rather than passing. Absence-of-needle is trivially
  # true of the empty string, so a grep or sed extraction that matched nothing
  # would otherwise report "ok" and turn a load-bearing check into a silent pass.
  # (assert_contains needs no such guard — an empty haystack cannot contain a
  # non-empty needle, so it already fails.)
  if [ -z "$1" ]; then
    _fail_detail "$3" "haystack empty — the extraction found nothing to check"
    return
  fi
  case "$1" in
    *"$2"*) _fail_value "$3" "actual:" "$1" "expected NOT to contain: $2" ;;
    *) pass "$3" ;;
  esac
}

# assert_file_contains <file> <literal-needle> <message>
# Reads the file once into the shell and matches with builtins: no grep spawn
# at the 600 sites that call this on Windows.
assert_file_contains() {
  local content
  if [ ! -f "$1" ]; then _fail_detail "$3" "file $1 is missing"; return; fi
  content="$(<"$1")"
  case "$content" in
    *"$2"*) pass "$3" ;;
    *) _fail_value "$3" "file:" "$content" "file $1 lacks: $2" ;;
  esac
}

# assert_prose_contains <file> <phrase> <message>
# Matches a phrase across line wraps. Markdown prose here is hard-wrapped, so a
# literal grep for a phrase that happens to straddle a newline fails for a reason
# unrelated to the assertion's intent -- and picking a needle that fits on one
# line just defers the problem to the next reflow. Collapses all whitespace in
# both haystack and needle to single spaces before comparing.
assert_prose_contains() {
  if [ ! -f "$1" ]; then _fail_detail "$3" "file $1 is missing"; return; fi
  _hay="$(tr -s '[:space:]' ' ' < "$1")"
  _need="$(printf '%s' "$2" | tr -s '[:space:]' ' ')"
  case "$_hay" in
    *"$_need"*) pass "$3" ;;
    *) _fail_value "$3" "file (flattened):" "$_hay" "file $1 lacks prose: $2" ;;
  esac
}

# assert_file_matches <file> <regex> <message>
# Regex counterpart to assert_file_contains, which is literal-only.
assert_file_matches() {
  if [ -f "$1" ] && grep -qE -- "$2" "$1"; then
    pass "$3"
  elif [ ! -f "$1" ]; then
    _fail_detail "$3" "file $1 is missing"
  else
    _fail_value "$3" "file:" "$(<"$1")" "file $1 lacks pattern: $2"
  fi
}

# assert_file_not_matches <file> <regex> <message>
# A missing file fails: absence of the pattern is not a pass when there was
# nothing to search, for the same reason assert_not_contains rejects empty input.
assert_file_not_matches() {
  if [ ! -f "$1" ]; then
    _fail_detail "$3" "file $1 is missing"
  elif grep -qE -- "$2" "$1"; then
    _fail_value "$3" "matching lines:" "$(grep -nE -- "$2" "$1")" "file $1 unexpectedly matches: $2"
  else
    pass "$3"
  fi
}

# assert_eq <expected> <actual> <message>
assert_eq() {
  if [ "$1" = "$2" ]; then
    pass "$3"
  else
    _fail_value "$3" "actual:  " "$2" "expected: $(_clip "$1")"
  fi
}

# assert_file_exists <path> <message> / assert_file_absent <path> <message>
assert_file_exists() {
  if [ -e "$1" ]; then pass "$2"; else _fail_value "$2" "missing:" "$1"; fi
}
assert_file_absent() {
  if [ -e "$1" ]; then _fail_value "$2" "exists:" "$1"; else pass "$2"; fi
}

# assert_files_identical <file-a> <file-b> <message>
assert_files_identical() {
  if [ -f "$1" ] && [ -f "$2" ] && diff -q "$1" "$2" >/dev/null 2>&1; then
    pass "$3"
  else
    _fail_value "$3" "diff:" "$(diff "$1" "$2" 2>&1)" "files differ or missing: $1 vs $2"
  fi
}

# assert_files_differ <file-a> <file-b> <message>
assert_files_differ() {
  if [ -f "$1" ] && [ -f "$2" ] && ! diff -q "$1" "$2" >/dev/null 2>&1; then
    pass "$3"
  else
    _fail_detail "$3" "files are identical or missing: $1 vs $2"
  fi
}

# assert_sweep_empty <label> <control-file> -- grep-args... -- <root>...
# An absence sweep that cannot pass vacuously: every swept root must exist and
# the pattern must match the control file (a positive control proving the
# pattern still finds what it is for); only then is an empty sweep a pass.
# Everything between the two `--` goes to grep verbatim, pattern included; the
# roots follow the second `--`, and a call without it or without a root fails.
# A leading `grep` word is accepted so the call reads like the other `-- cmd...`
# forms.
assert_sweep_empty() {
  local label="$1" control="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  [ "${1:-}" = "grep" ] && shift
  local -a args=() roots=()
  local root hits st=0
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do args+=("$1"); shift; done
  [ "${1:-}" = "--" ] || { _fail_detail "$label" "sweep has no -- before the roots"; return; }
  shift; roots=("$@")
  [ ${#args[@]} -gt 0 ] || { _fail_detail "$label" "sweep has no grep arguments"; return; }
  [ ${#roots[@]} -gt 0 ] || { _fail_detail "$label" "sweep names no root to search"; return; }
  for root in "${roots[@]}"; do
    [ -e "$root" ] || { _fail_value "$label" "root:" "$root" "swept root is missing"; return; }
  done
  [ -f "$control" ] || { _fail_value "$label" "control:" "$control" "positive control file is missing"; return; }
  if ! grep "${args[@]}" "$control" >/dev/null 2>&1; then
    _fail_value "$label" "control:" "$control" "positive control does not match the pattern, so an empty sweep would prove nothing"
    return
  fi
  hits="$(grep "${args[@]}" "${roots[@]}" 2>&1)" || st=$?
  case "$st" in
    0) _fail_value "$label" "hits:" "$hits" ;;
    1) pass "$label" ;;
    *) _fail_value "$label" "grep:" "$hits" "grep failed with exit $st" ;;
  esac
}

# flatten <file>
# One line of whitespace-collapsed text for whole-file ORDER checks. `tr -d '\r'`
# first: files are checked out with CRLF on Windows, and a needle that straddles
# a wrapped line never matches "word\r word" otherwise.
flatten() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; }

# section_body <file> <heading-prefix> [<stop-regex>]
# The body under the first line that starts with <heading-prefix>, up to the
# next line matching <stop-regex> (default: the next `## ` heading), flattened
# the same way `flatten` does so a wrapped phrase still matches.
section_body() {
  tr -d '\r' < "$1" | awk -v h="$2" -v stop="${3:-^## }" \
    'index($0, h) == 1 { p = 1; next } p && $0 ~ stop { exit } p' | tr '\n' ' ' | tr -s ' '
}

# first_pos <flattened-text> <literal>
# Byte offset of the first occurrence, or empty when absent. `-F`: the needle is
# a literal, so `[ROUTE]` or `**Scope**` is matched as written, not as a regex.
first_pos() { printf '%s' "$1" | grep -boF -- "$2" | head -1 | cut -d: -f1; }

# assert_precedes <flattened-text> <needle-a> <needle-b> <message>
# A must appear before B in the flattened text. The failure reports both
# offsets, `missing` for an absent needle, so it names which side is wrong.
assert_precedes() {
  local pos_a pos_b
  pos_a="$(first_pos "$1" "$2")"; pos_b="$(first_pos "$1" "$3")"
  if [ -n "$pos_a" ] && [ -n "$pos_b" ] && [ "$pos_a" -lt "$pos_b" ]; then
    pass "$4"
  else
    _fail_value "$4" "offsets:" "$2 ${pos_a:+at }${pos_a:-missing}, $3 ${pos_b:+at }${pos_b:-missing}"
  fi
}

# finish — the trailer and the file's exit status. Fails on any failed
# assertion, on a file that asserted nothing without calling skip (a loop that
# iterated zero times is not a pass), and on a skip under REQUIRE_ALL=1.
finish() {
  local rc=0
  end_case
  if [ "$_CASE_OUT" -gt 0 ] && [ "$_CASE_IN" -eq 0 ]; then
    printf '  TEST_CASE=%s matched no case in this file\n' "$TEST_CASE"
  elif [ "$_TESTS" -eq 0 ] && [ "$_SKIPPED" -eq 0 ]; then
    printf '  FAIL no assertions ran — a file that checks nothing cannot pass (call skip <reason> to skip on purpose)\n'
    rc=1
  fi
  if [ "${REQUIRE_ALL:-0}" = "1" ] && [ "$_SKIPPED" -gt 0 ]; then
    printf '  FAIL REQUIRE_ALL=1 and %d skipped: every check must run here\n' "$_SKIPPED"
    rc=1
  fi
  [ "$_FAILS" -eq 0 ] || rc=1
  printf '  -> %d passed, %d failed, %d xfail, %d skipped\n' \
    "$((_TESTS - _FAILS - _XFAIL))" "$_FAILS" "$_XFAIL" "$_SKIPPED"
  _cleanup_fixtures
  exit "$rc"
}
