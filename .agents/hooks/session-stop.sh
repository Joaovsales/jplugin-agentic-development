#!/bin/bash
# Session Stop hook — runs when a Claude Code session ends.
# Responsibilities:
#   1. Remove the session-active sentinel so cron jobs resume normal reporting.
#   2. Warn if the session ends with local commits not pushed to upstream.
#
# Kill switch: SKIP_SESSION_STOP=1

set -uo pipefail
[ "${SKIP_SESSION_STOP:-0}" = "1" ] && exit 0

SENTINEL="${CLAUDE_SESSION_SENTINEL:-/tmp/claude-code-session-active}"

# ── 1. Clear sentinel ────────────────────────────────────────────────────────
[ -f "$SENTINEL" ] && rm -f "$SENTINEL"

# ── 2. Unpushed-commit warning ───────────────────────────────────────────────
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [ -n "$BRANCH" ]; then
    UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")
    if [ -n "$UPSTREAM" ]; then
      AHEAD=$(git rev-list --count "$UPSTREAM"..HEAD 2>/dev/null || echo 0)
      if [ "${AHEAD:-0}" -gt 0 ]; then
        echo ""
        echo "⚠  SESSION END: $AHEAD unpushed commit(s) on $BRANCH → $UPSTREAM"
        echo "   Run: git push -u origin $BRANCH"
      fi
    else
      DIRTY=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
      LOCAL_COMMITS=$(git log --oneline 2>/dev/null | wc -l | tr -d ' ')
      if [ "${LOCAL_COMMITS:-0}" -gt 0 ] && [ "${DIRTY:-0}" -eq 0 ]; then
        echo ""
        echo "⚠  SESSION END: branch $BRANCH has no upstream."
        echo "   Run: git push -u origin $BRANCH"
      fi
    fi
  fi
fi

exit 0
