#!/bin/bash
# Claude Code PreCompact hook — flush live working state to tasks/checkpoint.md
# before context is compacted (auto at ~75% utilisation, or manual /compact), so
# nothing critical is lost to a lossy summary. On the next turn the SessionStart
# hook (source=compact) re-orients the agent from this file.
#
# Observability discipline: silent on success, never blocks or delays compaction
# (always exits 0). The same flush is reused by /build task-boundary checkpoints
# (P2) and /refresh (P3).
#
# Kill switch: SKIP_PRE_COMPACT=1

set -uo pipefail
[ "${SKIP_PRE_COMPACT:-0}" = "1" ] && exit 0

# Claude Code passes hook input as JSON on stdin. Extract the compaction trigger
# (auto|manual) when jq is available; fall back to "unknown" otherwise.
INPUT=$(cat 2>/dev/null || true)
TRIGGER="unknown"
if command -v jq >/dev/null 2>&1; then
  TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo unknown)
fi

# write_checkpoint <trigger> — snapshot git + todo state to tasks/checkpoint.md.
# All failures are swallowed: this must never break compaction.
write_checkpoint() {
  local trigger="$1"
  mkdir -p tasks 2>/dev/null || return 0

  local timestamp branch status spec
  timestamp=$(date -u +%FT%TZ 2>/dev/null || echo "unknown")
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  status=$(git status --short 2>/dev/null || echo "")
  spec=$(grep -oE 'specs/[A-Za-z0-9._-]+\.md' tasks/todo.md 2>/dev/null | tail -1 || true)

  {
    echo "# Checkpoint — $timestamp"
    echo ""
    echo "> Auto-written by PreCompact hook (trigger: $trigger). Re-read on resume."
    echo ""
    echo "## Git"
    echo "- Branch: $branch"
    echo ""
    echo '```'
    if [ -n "$status" ]; then echo "$status"; else echo "(working tree clean)"; fi
    echo '```'
    echo ""
    echo "## In-Progress & Pending Tasks (tasks/todo.md)"
    if [ -f tasks/todo.md ]; then
      grep -E '^[[:space:]]*\[([ ~])\]' tasks/todo.md 2>/dev/null | head -30 || echo "(none)"
    else
      echo "(no tasks/todo.md)"
    fi
    echo ""
    echo "## Active Spec"
    if [ -n "$spec" ]; then echo "- $spec"; else echo "(none discovered)"; fi
    echo ""
    echo "## How to Resume"
    echo "1. Read this file and \`tasks/todo.md\`"
    echo "2. Grep \`tasks/solutions/\` frontmatter (problem_type, module, tags) for relevant learnings"
    echo "3. Continue from the first \`[~]\` (or \`[ ]\`) item in \`tasks/todo.md\`"
  } > tasks/checkpoint.md 2>/dev/null || return 0
}

write_checkpoint "$TRIGGER"
exit 0
