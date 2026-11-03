# tests/test-cron-quiet-hours.sh — cron-quiet-hours.sh decides whether a cron job
# reports loudly or writes metrics only. The "quiet window" is the lifetime of
# the active-session sentinel (created at session start, removed by the Stop
# hook), not a clock range: cron_should_suppress answers on both sides of it.
# report_failure_only is the helper that acts on the answer.
#
# The library is sourced in a child shell with CLAUDE_SESSION_SENTINEL and
# CLAUDE_METRICS_DIR pointed into a fixture, so /tmp is never read or written.
. "$(dirname "$0")/lib.sh"

LIB="$(under_test .agents/hooks/cron-quiet-hours.sh)"

BOX="$(fixture_dir)"
SENT="$BOX/session-active"
METRICS="$BOX/metrics"

# in_lib <ENV=VAL...> -- <shell snippet> — run the snippet with the library sourced.
in_lib() {
  local -a envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  run env CLAUDE_SESSION_SENTINEL="$SENT" CLAUDE_METRICS_DIR="$METRICS" "${envs[@]}" \
    bash -c 'source "$1"; shift; eval "$1"' _ "$LIB" "$1"
}

# ── cron_should_suppress: both sides of the window ───────────────────────────
rm -f "$SENT"
in_lib -- 'cron_should_suppress'
assert_exit 1 "Window closed (no sentinel): cron is not suppressed"

: > "$SENT"
in_lib -- 'cron_should_suppress'
assert_exit 0 "Window open (sentinel present): cron is suppressed"

in_lib CRON_QUIET_OVERRIDE=1 -- 'cron_should_suppress'
assert_exit 1 "Window open, CRON_QUIET_OVERRIDE=1: suppression is overridden"

in_lib CRON_QUIET_OVERRIDE=0 -- 'cron_should_suppress'
assert_exit 0 "Window open, CRON_QUIET_OVERRIDE=0: still suppressed"

rm -f "$SENT"
in_lib CRON_QUIET_OVERRIDE=1 -- 'cron_should_suppress'
assert_exit 1 "Window closed, CRON_QUIET_OVERRIDE=1: not suppressed"

# The sentinel is read per call: removing it closes the window mid-shell.
: > "$SENT"
in_lib -- 'cron_should_suppress && rm -f "$CLAUDE_SESSION_SENTINEL" && ! cron_should_suppress'
assert_exit 0 "The sentinel is re-read on every call: removing it ends suppression"

# ── report_failure_only: success is silent ───────────────────────────────────
: > "$SENT"
in_lib -- 'report_failure_only 0 "all good"'
assert_exit 0 "Success: returns 0"
assert_eq "" "$output" "Success: prints nothing"
assert_file_absent "$METRICS" "Success: writes no metrics"

# ── report_failure_only: failure outside the window is loud ──────────────────
rm -f "$SENT"
in_lib -- 'report_failure_only 3 "smoke test red"'
assert_exit 3 "Failure, window closed: returns the failing code"
assert_eq "FAIL: smoke test red" "$output" "Failure, window closed: stderr carries FAIL: <message>"
assert_file_absent "$METRICS" "Failure, window closed: writes no metrics"

# ── report_failure_only: failure inside the window writes the metric line ────
: > "$SENT"
in_lib -- 'report_failure_only 2 "smoke" "test" "red"'
assert_exit 2 "Failure, window open: returns the failing code"
assert_eq "" "$output" "Failure, window open: nothing on stdout or stderr"
assert_file_exists "$METRICS/cron.tsv" "Failure, window open: the metrics file is created"
TAB=$'\t'
assert_file_matches "$METRICS/cron.tsv" \
  "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z${TAB}FAIL${TAB}smoke test red\$" \
  "Failure, window open: one line <UTC timestamp><TAB>FAIL<TAB><joined message>"
assert_eq "1" "$(wc -l < "$METRICS/cron.tsv" | tr -d ' ')" "Failure, window open: exactly one line"

in_lib -- 'report_failure_only 1 "second"'
assert_eq "2" "$(wc -l < "$METRICS/cron.tsv" | tr -d ' ')" "A second failure appends rather than overwrites"
assert_file_contains "$METRICS/cron.tsv" "${TAB}FAIL${TAB}second" "The appended line carries the second message"

# ── Override sends the failure back to stderr even inside the window ─────────
rm -rf "$METRICS"
in_lib CRON_QUIET_OVERRIDE=1 -- 'report_failure_only 4 "on-call"'
assert_exit 4 "Failure, window open, override: returns the failing code"
assert_eq "FAIL: on-call" "$output" "Failure, window open, override: loud on stderr"
assert_file_absent "$METRICS" "Failure, window open, override: writes no metrics"

finish
