#!/bin/bash
# cron-quiet-hours.sh — library for cron-driven smoke tests / health checks.
#
# Usage in your cron script:
#
#   #!/bin/bash
#   source "$(dirname "$0")/../.agents/hooks/cron-quiet-hours.sh"
#   if cron_should_suppress; then
#     # Active Claude session — write metrics only, no human-readable log.
#     record_metric "smoke_test_result" "$result"
#     exit 0
#   fi
#   # Normal noisy path (e.g., post to Slack on failure, echo to log on success).
#
# The active-session sentinel is created by session-start.sh and removed by
# session-stop.sh. Missing sentinel → no active session → cron runs normally.
#
# Honors CRON_QUIET_OVERRIDE=1 to force noisy reporting (useful for on-call
# triage when you WANT notifications even during an active session).

SENTINEL="${CLAUDE_SESSION_SENTINEL:-/tmp/claude-code-session-active}"

cron_should_suppress() {
  [ "${CRON_QUIET_OVERRIDE:-0}" = "1" ] && return 1
  [ -f "$SENTINEL" ]
}

# Failure-only reporting helper per the project's Observability Discipline.
# Pass exit code + message. Success = silent. Failure = stderr + non-zero exit.
report_failure_only() {
  local code="$1"; shift
  local msg="$*"
  if [ "$code" -ne 0 ]; then
    if cron_should_suppress; then
      # Session is active — write to metrics sink only.
      metric_dir="${CLAUDE_METRICS_DIR:-/tmp/claude-metrics}"
      mkdir -p "$metric_dir"
      printf '%s\tFAIL\t%s\n' "$(date -u +%FT%TZ)" "$msg" >> "$metric_dir/cron.tsv"
    else
      echo "FAIL: $msg" >&2
    fi
    return "$code"
  fi
  # Success: silent. Never log "all good" every iteration.
  return 0
}
