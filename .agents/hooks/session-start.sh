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
# This hook is registered once, by the plugin's hooks/hooks.json. A machine that
# ran an older install.sh still registers it at user level, and a project synced
# before .claude/hooks/ was retired may still carry an entry in its own
# .claude/settings.json — until install.sh and /sync remove those, one session can
# fire it twice and the banner would print twice. The first invocation drops a
# session-scoped sentinel; the second exits silently.
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
echo "  SESSION START — jplugin for agentic development"
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
  # Anchored: the flag is a frontmatter field, so it only counts at column 0.
  # Scoping to category dirs excluded the store README but not a *document* that
  # quotes the flag in its prose -- and one does, the bug doc about this very
  # count. Matching the structure instead of the location is what makes it right.
  REVIEW_COUNT=$(grep -rlE '^needs_review: true' tasks/solutions/*/ 2>/dev/null | wc -l | tr -d ' ' || true)
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
# The /memory-maintain skill is also called every session start via the
# AGENTS.md Session Start Checklist — the skill self-gates, so this nudge is a
# belt-and-suspenders signal.
if [ -f "tasks/history.md" ]; then
  SESSION_COUNT=$(grep -Ec '^(### \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]|## [0-9]{4}-[0-9]{2}-[0-9]{2})([[:space:]]|$)' tasks/history.md 2>/dev/null || true)
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

# ── Wrap-Up Debt ─────────────────────────────────────────────────────────────
# Written by the pre-push wrap-up gate, which warns rather than blocks and has
# no way to file an issue itself: external task creation carries an approval
# floor that a git hook cannot satisfy, and a hook must not do network I/O.
# This is where the debt reaches a human who can authorize filing it.
DEBT_FILE="tasks/wrap-up-debt.md"
if [ -f "$DEBT_FILE" ]; then
  DEBT_COUNT=$(grep -c '^## ' "$DEBT_FILE" 2>/dev/null || true)
  if [ "${DEBT_COUNT:-0}" -gt 0 ]; then
    echo ""
    echo "⚠  WRAP-UP DEBT  ($DEBT_FILE) — $DEBT_COUNT push(es) with no /wrap-up-session"
    echo "────────────────────────────────"
    # Print the id rather than asking for one. `upsert` is idempotent only if two
    # runs mint the same id, and a hand-typed one is exactly how they stop doing
    # that -- silently, and only on the second run. The heading is already stable
    # (`<branch> <first-sha>..<last-sha>`), so slugifying it derives the id.
    grep '^## ' "$DEBT_FILE" | head -5 | while IFS= read -r entry; do
      heading="${entry#\#\# }"
      # Must agree with registry.model.slugify_id: lowercase, collapse every run
      # of non-alphanumerics to one dash, strip *all* leading/trailing dashes,
      # fall back to "task" when nothing survives. Two normalizers that disagree
      # mint two ids for one entry, which is the idempotence this block exists to
      # protect. Reimplemented rather than called because a session-start hook
      # must not depend on the skill's scripts being installed; the agreement is
      # pinned by tests/test-pre-push-gate.sh.
      # `tr -cs` and BRE `*` are POSIX -- `\+` would be a GNU-only extension and
      # would silently leave the slug unchanged on BSD sed.
      slug=$(printf '%s' "$heading" | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')
      [ -n "$slug" ] || slug=task
      # The heading is repo-controlled text going into a single-quoted argument,
      # and git permits `'` in a branch name.
      heading_q=$(printf '%s' "$heading" | sed "s/'/'\\\\''/g")
      echo "  $heading"
      echo "    /task-registry upsert 'wrap-up-debt.$slug' --title '$heading_q' --apply --approve"
    done
  fi
fi

# ── Git Status ───────────────────────────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  echo "🌿  GIT  branch: $BRANCH | uncommitted changes: $UNCOMMITTED"

  # Upstream staleness. A clone that is behind shows an incomplete picture of the
  # repo, so every read the agent makes is silently wrong -- a session once
  # re-specified a capability that had already merged, because nothing said the
  # tree was 9 commits stale.
  #
  # Reports only what the LAST FETCH already recorded: no network call, so an
  # offline session pays nothing and no timeout lands in the startup path. The
  # /sync template-drift check below owns the (capped, cached) fetch.
  #
  # Silent when current, per Observability Discipline.
  if UPSTREAM_REF=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
    BEHIND=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)
    if [ "${BEHIND:-0}" -gt 0 ]; then
      if [ "$BEHIND" -eq 1 ]; then COMMIT_WORD="commit"; else COMMIT_WORD="commits"; fi
      echo ""
      echo "⚠  BEHIND UPSTREAM — $BEHIND $COMMIT_WORD behind $UPSTREAM_REF."
      echo "    Your view of this repo is incomplete. Run 'git pull' before planning,"
      echo "    or you may re-specify work that has already merged."
    fi
  fi
fi

# ── Deployment Signal Nudge ──────────────────────────────────────────────────
# If AGENTS.md has no "## Deployment Targets" section AND any known deployment
# signal file exists at the project root, print a one-line nudge. Non-blocking.
# Suppressed by creating .claude/deploy-nudge-dismissed. A section still in
# .claude/project.md (where it lived before the single instruction file) counts,
# with a one-line notice, until /sync moves it. CLAUDE.md is the @AGENTS.md
# pointer and is never read for the section.
if [ ! -f ".claude/deploy-nudge-dismissed" ]; then
  # Match ONLY a literal "## Deployment Targets" heading line — not headings with
  # extra text like "## Deployment Targets (placeholder — run /setup-deployment)".
  # This lets the template repo document the schema without activating verification.
  TARGETS_REGEX='^## Deployment Targets[[:space:]]*$'

  TARGETS_IN_PROJECT=0
  [ -f "AGENTS.md" ] && grep -qE "$TARGETS_REGEX" AGENTS.md 2>/dev/null && TARGETS_IN_PROJECT=1
  if [ "$TARGETS_IN_PROJECT" = "0" ] && [ -f ".claude/project.md" ] \
     && grep -qE "$TARGETS_REGEX" .claude/project.md 2>/dev/null; then
    TARGETS_IN_PROJECT=1
    echo "ℹ  Deployment Targets found in .claude/project.md — /sync will move them to AGENTS.md."
  fi

  # Nudge: signal files present but the section is absent
  if [ "$TARGETS_IN_PROJECT" = "0" ]; then
    DEPLOY_SIGNAL=""
    for signal in railway.json railway.toml .railway vercel.json .vercel .vercelignore netlify.toml fly.toml render.yaml; do
      if [ -e "$signal" ]; then
        DEPLOY_SIGNAL="$signal"
        break
      fi
    done
    if [ -n "$DEPLOY_SIGNAL" ]; then
      echo ""
      echo "⚠  Deploy signals detected ($DEPLOY_SIGNAL) but no Deployment Targets in AGENTS.md."
      echo "   Run /setup-deployment to enable automatic build verification."
    fi
  fi
fi

# ── Managed Block Check ──────────────────────────────────────────────────────
# The shared rules reach a project only through the managed block /sync writes
# into AGENTS.md; without it every harness runs on the project's own rules and
# nothing else says so. Printed only in a repository that has adopted the
# workflow — .agents/skills/ exists, or .claude/settings.json enables the plugin —
# because the plugin is installed at user scope and this hook runs in every
# repository the user opens (specs/single-instruction-file.md, D18).
JPLUGIN_ID="jplugin@jplugin-agentic-development"
BLOCK_BEGIN="<!-- jplugin-agentic-development:begin -->"
BLOCK_END="<!-- jplugin-agentic-development:end -->"
ADOPTING=0
[ -d .agents/skills ] && ADOPTING=1
# plugin_enabled_here — .claude/settings.json enables the plugin in this project.
# The one reading of enabledPlugins; the Plugin Declaration Check below uses it too.
plugin_enabled_here() {
  [ -f ".claude/settings.json" ] \
    && tr -d '[:space:]' < .claude/settings.json | grep -o '"enabledPlugins":{[^}]*}' | grep -q "\"$JPLUGIN_ID\":true"
}
if [ "$ADOPTING" = "0" ] && plugin_enabled_here; then
  ADOPTING=1
fi
if [ "$ADOPTING" = "1" ] && ! grep -qF -- "$BLOCK_BEGIN" AGENTS.md 2>/dev/null; then
  echo ""
  echo "⚠  AGENTS.md has no jplugin-agentic-development managed block — run /sync"
fi
# Once CLAUDE.md is the pointer nothing imports .claude/project.md any more. A sync
# through the CI mirror writes the pointer without migrating, so the file sits
# there loaded by nothing until a hand-run /sync (Step 6.6) moves it.
if [ -f ".claude/project.md" ] && [ "$(tr -d '\r' < CLAUDE.md 2>/dev/null)" = "@AGENTS.md" ]; then
  echo ""
  echo "⚠  .claude/project.md is loaded by nothing — run /sync to move it into AGENTS.md"
fi

# ── Workflow Template Drift Check ────────────────────────────────────────────
# Notifies if the jplugin-agentic-development template has new commits affecting
# syncable paths (.agents/skills, .agents/agents, .agents/references, .agents/hooks,
# .agents/git-hooks, .claude/agents, .claude/browsers, settings.json, CLAUDE.md).
# `.claude/skills` and `.claude/hooks` are RETIRED roots: never checked out, so
# never drift.
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
#   - AGENTS.md is MANAGED, not checked out: only its block is the template's,
#     so the block's text is compared, never the path — a template commit
#     touching its own rules below the end marker is not drift here (D6)
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
        .agents/skills .agents/agents .agents/references .agents/hooks .agents/git-hooks .claude/agents .claude/browsers .claude/settings.json CLAUDE.md 2>/dev/null \
        | wc -l | tr -d ' ')
      managed_block() { tr -d '\r' | awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '$0 == b { p = 1; next } $0 == e { p = 0 } p'; }
      TEMPLATE_BLOCK=$(git show "workflow/$WORKFLOW_BRANCH:AGENTS.md" 2>/dev/null | managed_block || true)
      LOCAL_BLOCK=$(managed_block < AGENTS.md 2>/dev/null || true)
      if [ -n "$TEMPLATE_BLOCK" ] && [ "$TEMPLATE_BLOCK" != "$LOCAL_BLOCK" ]; then
        DRIFT_COUNT=$(( DRIFT_COUNT + 1 ))
      fi
      printf '%s\n%s\n' "$DRIFT_COUNT" "$WORKFLOW_BRANCH" > "$WORKFLOW_CHECK_CACHE"
    fi
  else
    DRIFT_COUNT=$(sed -n '1p' "$WORKFLOW_CHECK_CACHE" 2>/dev/null || echo 0)
    WORKFLOW_BRANCH=$(sed -n '2p' "$WORKFLOW_CHECK_CACHE" 2>/dev/null)
    WORKFLOW_BRANCH=${WORKFLOW_BRANCH:-main}
  fi

  if [ "${DRIFT_COUNT:-0}" -gt 0 ]; then
    echo ""
    echo "🔄  TEMPLATE DRIFT — $DRIFT_COUNT item(s) differ from workflow/$WORKFLOW_BRANCH (syncable files, or the AGENTS.md managed block)"
    echo "    Run /sync to review and apply updates (or 'touch .claude/sync-check-dismissed' to silence)."
  fi
fi

# ── Plugin Declaration Check ─────────────────────────────────────────────────
# /sync writes the jplugin plugin declaration into the project's
# .claude/settings.json (enabledPlugins). Claude Code caches the plugin when the
# folder is trusted and records that only in the versioned cache directory;
# install.sh's user-scope install is recorded in installed_plugins.json instead
# (Spike S4, specs/claude-plugin-manifest.md). A user whose trust dialog ran
# before the declaration existed has no jplugin: skills in this project and
# nothing else says so. Silent when either record exists and when nothing is
# declared.
PLUGINS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"
INSTALLED_PLUGINS="$PLUGINS_DIR/installed_plugins.json"
PLUGIN_CACHE="$PLUGINS_DIR/cache/jplugin-agentic-development/jplugin"
if plugin_enabled_here \
   && ! grep -qF "\"$JPLUGIN_ID\"" "$INSTALLED_PLUGINS" 2>/dev/null \
   && [ -z "$(ls -A "$PLUGIN_CACHE" 2>/dev/null)" ]; then
  echo ""
  echo "🔌  PLUGIN NOT INSTALLED — .claude/settings.json enables $JPLUGIN_ID, but neither $INSTALLED_PLUGINS nor a version under $PLUGIN_CACHE/ records it"
  echo "    Run '/plugin' and install it for this project, or run 'bash install.sh' from the template checkout."
fi

# Pre-plugin copies under ~/.claude/skills/ shadow the plugin's skills for bare
# /<name> calls in every project, and only install.sh (run from the template
# checkout) offers to delete them. Names are matched against this project's
# .agents/skills/, so a user's own skills are never named.
LEGACY_SKILLS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
if [ -d .agents/skills ] && [ -d "$LEGACY_SKILLS_DIR" ]; then
  STALE_COPIES=""
  for skill_dir in .agents/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    if [ -d "$LEGACY_SKILLS_DIR/$skill_name" ]; then STALE_COPIES="$STALE_COPIES $skill_name"; fi
  done
  if [ -n "$STALE_COPIES" ]; then
    echo ""
    echo "🪞  STALE SKILL COPIES — $LEGACY_SKILLS_DIR holds pre-plugin copies of:$STALE_COPIES"
    echo "    Bare /<name> runs the copy, not the plugin's skill. Run 'bash install.sh' from the template checkout (it offers to delete them) or remove them by hand."
  fi
fi

# ── Code Graph Check ─────────────────────────────────────────────────────────
# graphify answers queries from graphify-out/graph.json, so a graph older than
# HEAD reports structure the last commit already changed. Silent when graphify is
# not installed and when the graph is current. The missing-graph line is printed
# only when the tree has files in graphify's code-extension set — a shell-and-
# markdown repository has no graph to build (observability discipline: loud only
# on actionable state).
if command -v graphify >/dev/null 2>&1 && git rev-parse --is-inside-work-tree &>/dev/null; then
  GRAPH_FILE="graphify-out/graph.json"
  CODE_EXTENSIONS='\.(py|js|jsx|ts|tsx|go|rs|java|kt|c|h|cc|cpp|hpp|cs|rb|php|swift|scala)$'
  if [ -f "$GRAPH_FILE" ]; then
    GRAPH_MTIME=$(stat -c %Y "$GRAPH_FILE" 2>/dev/null \
                  || stat -f %m "$GRAPH_FILE" 2>/dev/null \
                  || echo 0)
    HEAD_TIME=$(git log -1 --format=%ct 2>/dev/null || echo 0)
    if [ "${HEAD_TIME:-0}" -gt "${GRAPH_MTIME:-0}" ]; then
      echo ""
      echo "⚠  code graph stale: graphify-out/graph.json is older than HEAD — run graphify"
    fi
  else
    # `|| true`: grep -c exits 1 on zero matches, and pipefail would end the banner.
    CODE_FILES=$(git ls-files 2>/dev/null | grep -ciE "$CODE_EXTENSIONS" || true)
    if [ "${CODE_FILES:-0}" -gt 0 ]; then
      echo ""
      echo "⚠  graphify installed but no graph — run graphify"
    fi
  fi
fi
