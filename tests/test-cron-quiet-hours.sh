# tests/test-cron-quiet-hours.sh — sentinel staleness in cron-quiet-hours.sh.
#
# session-stop.sh is the only thing that removes the active-session sentinel.
# A crashed session (or a harness that never fires SessionStop) leaves it
# behind forever, which would permanently suppress cron failure reporting if
# cron_should_suppress() trusted the sentinel's mere existence. These cases
# check that a stale sentinel is ignored, while a fresh one still suppresses.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO/.claude/hooks/cron-quiet-hours.sh"

tmp=$(mktemp -d)
export CLAUDE_SESSION_SENTINEL="$tmp/sentinel"
export CLAUDE_METRICS_DIR="$tmp/metrics"

# --- Case 1: no sentinel at all -> not suppressed ---
(
  . "$LIB"
  if cron_should_suppress; then exit 1; else exit 0; fi
)
assert_eq "0" "$?" "no sentinel: cron_should_suppress is false"

# --- Case 2: fresh sentinel -> suppressed ---
touch "$CLAUDE_SESSION_SENTINEL"
(
  . "$LIB"
  if cron_should_suppress; then exit 0; else exit 1; fi
)
assert_eq "0" "$?" "fresh sentinel: cron_should_suppress is true"

# --- Case 3: stale sentinel (older than max age) -> not suppressed ---
touch -d "@1" "$CLAUDE_SESSION_SENTINEL" 2>/dev/null || touch -t 197001010000 "$CLAUDE_SESSION_SENTINEL"
(
  . "$LIB"
  if cron_should_suppress; then exit 1; else exit 0; fi
)
assert_eq "0" "$?" "stale sentinel: cron_should_suppress is false (self-heals without SessionStop)"

# --- Case 4: stale sentinel -> report_failure_only logs noisily, not to metrics ---
rm -f "$CLAUDE_METRICS_DIR/cron.tsv" 2>/dev/null
(
  . "$LIB"
  report_failure_only 1 "boom" 2>"$tmp/stderr"
)
assert_file_contains "$tmp/stderr" "FAIL: boom" "stale sentinel: failure goes to stderr, not suppressed"
assert_eq "false" "$([ -f "$CLAUDE_METRICS_DIR/cron.tsv" ] && echo true || echo false)" "stale sentinel: no metrics-only sink used"

# --- Case 5: CRON_QUIET_OVERRIDE=1 always wins, even with a fresh sentinel ---
touch "$CLAUDE_SESSION_SENTINEL"
(
  . "$LIB"
  export CRON_QUIET_OVERRIDE=1
  if cron_should_suppress; then exit 1; else exit 0; fi
)
assert_eq "0" "$?" "override: CRON_QUIET_OVERRIDE=1 forces noisy reporting despite fresh sentinel"

rm -rf "$tmp"
finish
