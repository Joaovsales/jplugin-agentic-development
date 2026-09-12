#!/usr/bin/env bash
# Install the harness-neutral workflow for Codex at user scope.
#
# This adapter is intentionally separate from install.sh: existing Claude Code,
# Pi, and git-template installs keep their current behavior unless a user
# explicitly runs this script.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
RENDERER="$REPO_DIR/scripts/render-codex.py"

usage() {
  cat <<'EOF'
Usage: bash scripts/install-codex.sh

Installs the workflow's harness-neutral skills, agents, shared rules, and
optional lifecycle hooks for the current user. Set CODEX_HOME or AGENTS_HOME
to test or use a non-default configuration directory.
EOF
}

die() {
  printf 'install-codex: %s\n' "$1" >&2
  exit 1
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  die "Python 3 is required to render Codex agents and hooks"
fi

[ -f "$RENDERER" ] || die "missing renderer: $RENDERER"
[ -d "$REPO_DIR/.agents/skills" ] || die "missing canonical skills: $REPO_DIR/.agents/skills"
[ -d "$REPO_DIR/.agents/agents" ] || die "missing canonical agents: $REPO_DIR/.agents/agents"

# PI_SETUP.md § Sub-Agent Routing is the single source of concrete model IDs.
# The Codex Scout-tier ID is the Codex column of the Scout row in its tier
# table; read it there rather than repeating it in code, so a model release
# still updates one file. An unreadable row is a broken install, not a silent
# unpinned agent.
CODEX_SCOUT_MODEL="$(awk -F'|' '
  /^\| Tier \|/ && !column { for (i = 1; i <= NF; i++) if ($i ~ /^ *Codex *$/) column = i }
  column && /^\| Scout / { gsub(/[` ]/, "", $column); print $column; exit }
' "$REPO_DIR/PI_SETUP.md")"
[ -n "$CODEX_SCOUT_MODEL" ] || die "cannot read the Codex Scout-tier model from PI_SETUP.md (Scout row, Codex column)"

mkdir -p "$AGENTS_HOME/skills" "$CODEX_HOME/agents" "$CODEX_HOME/hooks"
cp -r "$REPO_DIR/.agents/skills/." "$AGENTS_HOME/skills/"
printf 'installed canonical skills in %s\n' "$AGENTS_HOME/skills"

"$PYTHON_BIN" "$RENDERER" --global \
  "$REPO_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md"
printf 'rendered shared workflow rules in %s\n' "$CODEX_HOME/AGENTS.md"

"$PYTHON_BIN" "$RENDERER" --agents \
  "$REPO_DIR/.agents/agents" "$CODEX_HOME/agents" --scout-model "$CODEX_SCOUT_MODEL"
printf 'rendered canonical agents in %s (Scout tier: %s)\n' "$CODEX_HOME/agents" "$CODEX_SCOUT_MODEL"

cp "$REPO_DIR/.claude/hooks/session-start.sh" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-start.sh"
cp "$REPO_DIR/.claude/hooks/pre-compact.sh" \
  "$CODEX_HOME/hooks/coding-agent-workflow-pre-compact.sh"
cp "$REPO_DIR/.claude/hooks/session-stop.sh" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-end.sh"
cp "$REPO_DIR/codex/hooks/session_start.py" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-start.py"
# The bulk-read gate is shared byte-identical with Claude Code (specs/bulk-read-gate.md).
cp "$REPO_DIR/.claude/hooks/bulk-read-gate.py" \
  "$CODEX_HOME/hooks/coding-agent-workflow-bulk-read-gate.py"
chmod +x \
  "$CODEX_HOME/hooks/coding-agent-workflow-bulk-read-gate.py" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-start.sh" \
  "$CODEX_HOME/hooks/coding-agent-workflow-pre-compact.sh" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-end.sh" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-start.py"

printf -v start_hook '%q %q' "$PYTHON_BIN" \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-start.py"
printf -v compact_hook 'bash %q' \
  "$CODEX_HOME/hooks/coding-agent-workflow-pre-compact.sh"
printf -v end_hook 'bash %q' \
  "$CODEX_HOME/hooks/coding-agent-workflow-session-end.sh"
printf -v gate_hook '%q %q' "$PYTHON_BIN" \
  "$CODEX_HOME/hooks/coding-agent-workflow-bulk-read-gate.py"
# EVENT=COMMAND pairs: the binding travels with the argument, so no positional
# order has to be kept in step between this script and the renderer.
"$PYTHON_BIN" "$RENDERER" --merge-hooks "$CODEX_HOME/hooks.json" \
  "SessionStart=$start_hook" \
  "PreCompact=$compact_hook" \
  "SessionEnd=$end_hook" \
  "PreToolUse=$gate_hook"

printf 'merged lifecycle hooks in %s\n' "$CODEX_HOME/hooks.json"
printf 'Review installed hooks with /hooks before enabling them.\n'
