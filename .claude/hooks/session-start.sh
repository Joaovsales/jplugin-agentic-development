#!/bin/bash
# Claude Code Session Start Hook
# Orients the agent at the beginning of every session by surfacing the learning
# store counts and active tasks without requiring manual reads.

set -eo pipefail

# Kill switch: skip hook if SKIP_SESSION_START=1
[ "${SKIP_SESSION_START:-0}" = "1" ] && exit 0

# ── Active-session sentinel ──────────────────────────────────────────────────
# Written here, removed by session-stop.sh. Cron jobs that source
# cron-quiet-hours.sh use its presence to suppress human-readable reporting
# during active sessions (failure-only path in observability discipline).
SENTINEL="${CLAUDE_SESSION_SENTINEL:-/tmp/claude-code-session-active}"
printf 'pid=%s\nstarted=%s\nrepo=%s\n' "$$" "$(date -u +%FT%TZ)" "$(pwd)" > "$SENTINEL" 2>/dev/null || true

DIVIDER="════════════════════════════════════════"

# ── Compaction-aware restore ─────────────────────────────────────────────────
# Claude Code passes a `source` field (startup|resume|compact|clear) as JSON on
# stdin. After a compaction we skip the heavy first-run banner and instead point
# the agent at the state flushed to disk by the PreCompact hook. Parsed with sed
# rather than jq: re-orientation matters most at exactly this moment, so the
# branch must not vanish on a machine that lacks an optional binary. Older CLIs
# omit the field — source stays startup, preserving the full banner, no
# regression. The tty guard keeps a manual run from blocking on empty stdin.
# Extracts one top-level JSON string field, or empty when absent. `|| true` on
# every stage: under `set -eo pipefail` a no-match sed plus an empty head would
# otherwise abort the hook, which is the silent-no-banner failure this file
# exists to avoid. The capture takes anything up to the closing quote — the
# caller's key is sanitised at GUARD_FILE below, so a narrower class would only
# reject legitimate ids without buying safety.
json_string_field() {  # json_string_field <field-name> <json>
  printf '%s' "$2" \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | head -1 || true
}

HOOK_SOURCE="startup"
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat 2>/dev/null || true)
  HOOK_SOURCE=$(json_string_field source "$HOOK_INPUT")
  HOOK_SOURCE="${HOOK_SOURCE:-startup}"
fi

# ── Double-invocation guard ──────────────────────────────────────────────────
# This hook is registered TWICE: globally by install.sh (~/.claude/settings.json)
# and per-project by .claude/settings.json, which /sync copies into every repo.
# Both registrations fire for the same session, so the banner prints twice. The
# first invocation drops a session-scoped sentinel; the second exits silently.
# Escape hatch: CCW_SESSION_GUARD=0 (same convention as SKIP_SESSION_START).
# Reuses HOOK_INPUT above — stdin can only be consumed once.
#
# The key must be stable within one session and distinct across sessions. Both
# halves matter: too broad and a second session inherits the first's sentinel and
# gets no banner at all.
if [ "${CCW_SESSION_GUARD:-1}" != "0" ]; then
  # session_id is exactly that key, and Claude Code puts it in the payload.
  # Parsed with sed for the same reason `source` above is: jq is optional, and a
  # guard that reaches for its fallback whenever an optional binary is missing is
  # a guard that mostly runs on the fallback.
  GUARD_KEY=""
  if [ -n "${HOOK_INPUT:-}" ]; then
    GUARD_KEY=$(json_string_field session_id "$HOOK_INPUT")
  fi
  # No session_id (older CLI, manual run): key on the working directory, not
  # $PPID. Both registrations fire in the same repo, so cwd still collapses them
  # — and unlike $PPID it stays distinct across repos on Windows, where bash
  # spawned from a native Windows parent (node, python) reports PPID=1 for every
  # session. That collapsed the key to one constant, so starting a session in
  # repo B within the freshness window below silently ate B's whole banner.
  #
  # Residual limit, accepted: cwd cannot tell one session's second registration
  # from a genuinely new session in the same repo, so a second session started
  # here inside the freshness window is also suppressed. That is strictly
  # narrower than the every-repo collapse it replaces, it is bounded by the
  # window, and it is unreachable whenever the payload carries a session_id.
  #
  # `|| true` is load-bearing: under `set -eo pipefail` a missing cksum would
  # otherwise propagate 127 and kill the hook outright — a worse silent banner
  # loss than the one being fixed, and it would make the raw-path degradation
  # below unreachable. Hashed because a deep worktree path would crowd the
  # filename limit; the raw fallback is tail-trimmed for the same reason.
  if [ -z "$GUARD_KEY" ]; then
    GUARD_KEY=$(printf '%s' "$PWD" | cksum 2>/dev/null | cut -d' ' -f1 || true)
    if [ -z "$GUARD_KEY" ]; then
      GUARD_KEY=$(printf '%s' "$PWD" | tail -c 80 || true)
    fi
    GUARD_KEY="cwd-${GUARD_KEY}"
  fi
  # Key on source as well. One session emits startup and, later, compact/resume/
  # clear. Keying on session_id alone would let the startup sentinel swallow the
  # compaction banner — the one moment re-orientation matters most.
  GUARD_KEY="${GUARD_KEY}-${HOOK_SOURCE}"
  GUARD_FILE="${TMPDIR:-/tmp}/.ccw-session-start-$(printf '%s' "$GUARD_KEY" | tr -c 'A-Za-z0-9_.-' '_')"
  GUARD_MAX_AGE=300  # 5 minutes — a stale sentinel must never wedge the hook
  if [ -f "$GUARD_FILE" ]; then
    GUARD_MTIME=$(stat -c %Y "$GUARD_FILE" 2>/dev/null \
                  || stat -f %m "$GUARD_FILE" 2>/dev/null \
                  || echo 0)
    if [ $(( $(date +%s) - GUARD_MTIME )) -lt "$GUARD_MAX_AGE" ]; then
      exit 0
    fi
  fi
  touch "$GUARD_FILE" 2>/dev/null || true
fi

if [ "$HOOK_SOURCE" = "compact" ]; then
  echo ""
  echo "$DIVIDER"
  echo "  RESUMING AFTER COMPACTION"
  echo "$DIVIDER"
  echo ""
  echo "Context was just compacted. Re-orient from disk before continuing:"
  if [ -f "tasks/checkpoint.md" ]; then
    echo "  • tasks/checkpoint.md (state flushed by PreCompact hook):"
    head -1 tasks/checkpoint.md | sed 's/^/      /'
  fi
  if [ -f "tasks/todo.md" ]; then
    ACTIVE=$(grep -E '^[[:space:]]*\[~\]' tasks/todo.md 2>/dev/null | head -1 || true)
    [ -z "$ACTIVE" ] && ACTIVE=$(grep -E '^[[:space:]]*\[ \]' tasks/todo.md 2>/dev/null | head -1 || true)
    echo "  • Active task: ${ACTIVE:-<none pending>}"
  fi
  echo "  • tasks/solutions/ — grep frontmatter (problem_type, module, tags) for relevant learnings"
  echo ""
  echo "$DIVIDER"
  exit 0
fi

echo ""
echo "$DIVIDER"
echo "  SESSION START — Coding Agent Workflow"
echo "$DIVIDER"

# ── Learning Store ───────────────────────────────────────────────────────────
# One line of counts, never document bodies — the store is grep-retrieved on
# demand (see tasks/solutions/README.md). An old-store project gets pointed at
# the migration script instead.
# Old-store detection constructs the retired paths rather than naming them
# literally, so the repo-wide retired-reference sweep stays strict. Checked
# unconditionally: old files alongside tasks/solutions/ mean a HALF-migrated
# repo (e.g. /learn bootstrapped the store before the migration ran), which
# must warn too — orphaned learnings are invisible to the grep-first checklist.
UNMIGRATED=0
for OLD_STORE in memory lessons bugs; do
  [ -f "tasks/${OLD_STORE}.md" ] && UNMIGRATED=1
done
if [ -d "tasks/solutions" ]; then
  # `|| true`: find exits non-zero on traversal errors (unreadable subdir) and
  # pipefail would turn that into a dead banner, same hazard as REVIEW_COUNT.
  DOC_COUNT=$(find tasks/solutions -mindepth 2 -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || true)
  # Category docs only (the store README mentions the flag as documentation),
  # and `|| true` because grep exits 1 on zero matches — under `set -eo
  # pipefail` that would kill the whole banner.
  REVIEW_COUNT=$(grep -rl 'needs_review: true' tasks/solutions/*/ 2>/dev/null | wc -l | tr -d ' ' || true)
  echo ""
  echo "📚  LEARNING STORE  tasks/solutions — ${DOC_COUNT:-0} documents, ${REVIEW_COUNT:-0} needs_review (grep frontmatter to retrieve)"
  if [ "$UNMIGRATED" = "1" ]; then
    echo "⚠️   Partially migrated — old store files remain in tasks/; run the template repo's scripts/migrate-learning-store.py (dry-run first) to fold them in."
  fi
else
  echo ""
  if [ "$UNMIGRATED" = "1" ]; then
    echo "📚  Unmigrated learning store — run the template repo's scripts/migrate-learning-store.py (dry-run first) to convert to tasks/solutions/."
  else
    echo "📚  No learning store yet — /learn creates tasks/solutions/ on first write."
  fi
fi

# ── Memory Maintenance Check ─────────────────────────────────────────────────
# Count session history entries. Nudge when maintenance is due (every 5 sessions).
# The /memory-maintain skill is also called every session start via CLAUDE.md
# step 4 — the skill self-gates, so this nudge is a belt-and-suspenders signal.
if [ -f "tasks/history.md" ]; then
  SESSION_COUNT=$(grep -c '^### \[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' tasks/history.md 2>/dev/null || true)
  if [ "${SESSION_COUNT:-0}" -gt 0 ] && [ $(( SESSION_COUNT % 5 )) -eq 0 ]; then
    echo ""
    echo "🔧  MEMORY MAINTENANCE DUE ($SESSION_COUNT sessions) — /memory-maintain will run at session start."
  fi
fi

# ── Active Tasks ─────────────────────────────────────────────────────────────
TODO_FILE="tasks/todo.md"
if [ -f "$TODO_FILE" ]; then
  PENDING=$(grep -c '^\s*\[ \]' "$TODO_FILE" 2>/dev/null || true)
  IN_PROGRESS=$(grep -c '^\s*\[~\]' "$TODO_FILE" 2>/dev/null || true)
  echo ""
  echo "📋  ACTIVE TASKS  (tasks/todo.md) — $PENDING pending, $IN_PROGRESS in-progress"
  echo "────────────────────────────────"
  grep -E '^\s*\[([ ~])\]' "$TODO_FILE" | head -10 || echo "  None."
else
  echo ""
  echo "📋  No tasks/todo.md found."
fi

# ── Git Status ───────────────────────────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  echo "🌿  GIT  branch: $BRANCH | uncommitted changes: $UNCOMMITTED"
fi

# ── Deployment Signal Nudge ──────────────────────────────────────────────────
# If neither .claude/project.md nor CLAUDE.md has a "## Deployment Targets"
# section AND any known deployment signal file exists at the project root,
# print a one-line nudge. Non-blocking. Suppressed by creating
# .claude/deploy-nudge-dismissed.
#
# Lookup order: .claude/project.md (primary) → CLAUDE.md (legacy fallback).
# If the section is found in the legacy CLAUDE.md location, print a
# deprecation hint prompting the user to run /sync to migrate.
if [ ! -f ".claude/deploy-nudge-dismissed" ]; then
  # Match ONLY a literal "## Deployment Targets" heading line — not headings with
  # extra text like "## Deployment Targets (placeholder — run /setup-deployment)".
  # This lets the template repo document the schema without activating verification.
  TARGETS_REGEX='^## Deployment Targets[[:space:]]*$'

  TARGETS_IN_PROJECT=0
  TARGETS_IN_CLAUDE=0
  [ -f ".claude/project.md" ] && grep -qE "$TARGETS_REGEX" .claude/project.md 2>/dev/null && TARGETS_IN_PROJECT=1
  [ -f "CLAUDE.md" ] && grep -qE "$TARGETS_REGEX" CLAUDE.md 2>/dev/null && TARGETS_IN_CLAUDE=1

  # Legacy migration reminder: section in CLAUDE.md means the project hasn't
  # migrated yet. Still functional (thanks to fallback reads), but flag it.
  if [ "$TARGETS_IN_PROJECT" = "0" ] && [ "$TARGETS_IN_CLAUDE" = "1" ]; then
    echo ""
    echo "⚠  Deployment Targets still in CLAUDE.md (legacy location)."
    echo "   Run /sync to auto-migrate to .claude/project.md — CLAUDE.md is"
    echo "   template-managed and its project-specific content will be wiped"
    echo "   the next time /sync overwrites it."
  fi

  # Nudge: signal files present but section absent from BOTH locations
  if [ "$TARGETS_IN_PROJECT" = "0" ] && [ "$TARGETS_IN_CLAUDE" = "0" ]; then
    DEPLOY_SIGNAL=""
    for signal in railway.json railway.toml .railway vercel.json .vercel .vercelignore netlify.toml fly.toml render.yaml; do
      if [ -e "$signal" ]; then
        DEPLOY_SIGNAL="$signal"
        break
      fi
    done
    if [ -n "$DEPLOY_SIGNAL" ]; then
      echo ""
      echo "⚠  Deploy signals detected ($DEPLOY_SIGNAL) but no Deployment Targets in .claude/project.md."
      echo "   Run /setup-deployment to enable automatic build verification."
    fi
  fi
fi

# ── Workflow Template Drift Check ────────────────────────────────────────────
# Notifies if the coding-agent-workflow template has new commits affecting
# syncable paths (.claude/skills, .claude/agents, .claude/hooks, .claude/browsers,
# settings.json).
# Silent when in sync (observability discipline: loud only on actionable state).
#
# Preconditions:
#   - A git remote named 'workflow' must exist (skipped otherwise)
#   - Not dismissed via .claude/sync-check-dismissed
#
# Behaviour:
#   - Fetches at most once per 24h (cached in .claude/.sync-check-cache)
#   - 5s network timeout — never hangs the session if offline
#   - Reports drift count; user runs /sync to review & apply
WORKFLOW_CHECK_CACHE=".claude/.sync-check-cache"
WORKFLOW_CHECK_MAX_AGE=86400  # 24 hours

if [ ! -f ".claude/sync-check-dismissed" ] \
   && git rev-parse --is-inside-work-tree &>/dev/null \
   && git remote get-url workflow &>/dev/null; then

  NEED_FETCH=1
  if [ -f "$WORKFLOW_CHECK_CACHE" ]; then
    CACHE_MTIME=$(stat -c %Y "$WORKFLOW_CHECK_CACHE" 2>/dev/null \
                  || stat -f %m "$WORKFLOW_CHECK_CACHE" 2>/dev/null \
                  || echo 0)
    CACHE_AGE=$(( $(date +%s) - CACHE_MTIME ))
    [ "$CACHE_AGE" -lt "$WORKFLOW_CHECK_MAX_AGE" ] && NEED_FETCH=0
  fi

  DRIFT_COUNT=0
  WORKFLOW_BRANCH=""

  if [ "$NEED_FETCH" = "1" ]; then
    WORKFLOW_BRANCH=$(git ls-remote --symref workflow HEAD 2>/dev/null \
      | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}')
    WORKFLOW_BRANCH=${WORKFLOW_BRANCH:-main}

    if timeout 5 git fetch workflow "$WORKFLOW_BRANCH" &>/dev/null; then
      DRIFT_COUNT=$(git diff --name-only "workflow/$WORKFLOW_BRANCH" -- \
        .agents/skills .agents/agents .claude/skills .claude/agents .claude/hooks .claude/browsers .claude/settings.json CLAUDE.md 2>/dev/null \
        | wc -l | tr -d ' ')
      printf '%s\n%s\n' "$DRIFT_COUNT" "$WORKFLOW_BRANCH" > "$WORKFLOW_CHECK_CACHE"
    fi
  else
    DRIFT_COUNT=$(sed -n '1p' "$WORKFLOW_CHECK_CACHE" 2>/dev/null || echo 0)
    WORKFLOW_BRANCH=$(sed -n '2p' "$WORKFLOW_CHECK_CACHE" 2>/dev/null)
    WORKFLOW_BRANCH=${WORKFLOW_BRANCH:-main}
  fi

  if [ "${DRIFT_COUNT:-0}" -gt 0 ]; then
    echo ""
    echo "🔄  TEMPLATE DRIFT — $DRIFT_COUNT file(s) differ from workflow/$WORKFLOW_BRANCH"
    echo "    Run /sync to review and apply updates (or 'touch .claude/sync-check-dismissed' to silence)."
  fi
fi

# ── Code Graph Staleness Check ───────────────────────────────────────────────
# graphify indexes the repo into graphify-out/graph.json and answers queries from
# that snapshot, so an out-of-date graph silently reports outdated structure.
# Silent when graphify isn't installed and when the graph is fresh
# (observability discipline: loud only on actionable state).
if command -v graphify >/dev/null 2>&1; then
  GRAPH_FILE="graphify-out/graph.json"
  GRAPH_MAX_AGE=1209600  # 14 days — fallback when mtime comparison is unavailable

  if [ ! -f "$GRAPH_FILE" ]; then
    echo ""
    echo "🕸  NO CODE GRAPH — graphify-out/graph.json is missing"
    echo "    Run graphify to index this project, then 'graphify claude install' to wire it in."
  else
    GRAPH_MTIME=$(stat -c %Y "$GRAPH_FILE" 2>/dev/null \
                  || stat -f %m "$GRAPH_FILE" 2>/dev/null \
                  || echo 0)
    GRAPH_AGE=$(( $(date +%s) - GRAPH_MTIME ))

    # Any TRACKED source file touched after the graph was written makes it stale.
    # Tracked-only keeps build output, logs and scratch files from crying wolf.
    # Outside a git repo (or with nothing tracked) the age fallback below applies.
    NEWER_SOURCE=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
      while IFS= read -r TRACKED_FILE; do
        if [ -f "$TRACKED_FILE" ] && [ "$TRACKED_FILE" -nt "$GRAPH_FILE" ]; then
          NEWER_SOURCE="$TRACKED_FILE"
          break
        fi
      done < <(git ls-files 2>/dev/null || true)
    fi

    if [ -n "$NEWER_SOURCE" ] || [ "$GRAPH_AGE" -gt "$GRAPH_MAX_AGE" ]; then
      echo ""
      echo "🕸  CODE GRAPH STALE — source files changed since graphify-out/graph.json was built"
      echo "    Queries will answer from an outdated snapshot. Re-index, or run"
      echo "    'graphify hook install' to refresh it on every commit and checkout."
    fi
  fi
fi

# ── Available Skills ────────────────────────────────────────────────────────
echo ""
echo "SKILLS AVAILABLE"
echo "────────────────────────────────"
echo "  /prd         — Greenfield project: interview → PRD + backlog"
echo "  /brainstorm  — Divergent design exploration before /plan"
echo "  /plan        — Write spec + task breakdown (uses opus)"
echo "  /build       — Autonomous TDD execution with sub-agents"
echo "  /auto-push   — /plan (approved) → /build → /wrap-up autonomously"
echo "  /yolo        — Full-auto loop: /plan → /build → /wrap-up until backlog empty"
echo "  /auto-improve — Unattended discover→fix→PR loop (daily cloud runs)"
echo "  /tdd         — Manual TDD loop with user checkpoints"
echo "  /debug       — Root cause analysis + bug-track store docs"
echo "  /verify      — Evidence-based verification (--scope e2e|deployment)"
echo "  /quality-gate — 3-phase post-build review: structural, anti-patterns, APOSD"
echo "  /software-design-expert-review — APOSD design audit (GO/HOLD/STOP)"
echo "  /software-design-expert-learn  — APOSD design tutorial (end-of-session)"
echo "  /receive-review  — Process code review feedback"
echo "  /security-scan   — OWASP audit on changed files"
echo "  /learn       — Extract learnings to tasks/solutions/"
echo "  /memory-maintain — Sweep the typed learning store (resolve, merge, prune)"
echo "  /checkpoint  — Snapshot progress for handoff"
echo "  /refresh     — Context reset: snapshot to disk, rebuild clean context"
echo "  /wrap-up-session — Close session: review, test, push"
echo "  /writing-skills  — Author new skills"
echo "  /task-registry — Sync todo.md with GitHub/Jira/local tasks; frontier"
echo "  /sync        — Pull latest from template repo"

echo ""
echo "$DIVIDER"
echo "  Ready. Use /brainstorm or /plan to start, or continue from tasks/todo.md."
echo "$DIVIDER"
echo ""
