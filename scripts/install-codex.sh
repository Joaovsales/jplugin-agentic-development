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
Usage: bash scripts/install-codex.sh [--preview | --adopt-legacy]

Installs the workflow's harness-neutral skills, agents and optional lifecycle
hooks for the current user. The shared rules are not rendered globally: each
project reads them from the managed block of its own AGENTS.md, written by
/sync (a block an earlier adapter rendered into ~/.codex/AGENTS.md is offered
for removal by install.sh). Set CODEX_HOME or AGENTS_HOME to test or use a
non-default configuration directory.
Use --preview to inspect changes without writing. Use --adopt-legacy after a
preview to back up and replace exact old generated agent files.
EOF
}

die() {
  printf 'install-codex: %s\n' "$1" >&2
  exit 1
}

MODE=""
if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --preview|--adopt-legacy) MODE="$1" ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  [ "$#" -eq 1 ] || die "accepts one option at a time"
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  die "Python 3 is required to render Codex agents and hooks"
fi
"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
  || die "Python 3.11 or newer is required before installing Codex files"

[ -f "$RENDERER" ] || die "missing renderer: $RENDERER"
[ -d "$REPO_DIR/.agents/skills" ] || die "missing canonical skills: $REPO_DIR/.agents/skills"
[ -d "$REPO_DIR/.agents/agents" ] || die "missing canonical agents: $REPO_DIR/.agents/agents"

RENDER_ARGS=(--agents "$REPO_DIR/.agents/agents" "$CODEX_HOME/agents" --config "$CODEX_HOME/config.toml")
if [ -n "$MODE" ]; then RENDER_ARGS+=("$MODE"); fi
"$PYTHON_BIN" "$RENDERER" "${RENDER_ARGS[@]}"
if [ "$MODE" = --preview ]; then exit 0; fi

mkdir -p "$AGENTS_HOME/skills" "$CODEX_HOME/hooks"
cp -r "$REPO_DIR/.agents/skills/." "$AGENTS_HOME/skills/"
printf 'installed canonical skills in %s\n' "$AGENTS_HOME/skills"
printf 'rendered canonical agents in %s\n' "$CODEX_HOME/agents"

cp "$REPO_DIR/.agents/hooks/session-start.sh" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.sh"
cp "$REPO_DIR/.agents/hooks/pre-compact.sh" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-pre-compact.sh"
cp "$REPO_DIR/.agents/hooks/session-stop.sh" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-end.sh"
cp "$REPO_DIR/codex/hooks/session_start.py" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.py"
chmod +x \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.sh" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-pre-compact.sh" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-end.sh" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.py"

printf -v start_hook '%q %q' "$PYTHON_BIN" \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-start.py"
printf -v compact_hook 'bash %q' \
  "$CODEX_HOME/hooks/jplugin-agentic-development-pre-compact.sh"
printf -v end_hook 'bash %q' \
  "$CODEX_HOME/hooks/jplugin-agentic-development-session-end.sh"
"$PYTHON_BIN" "$RENDERER" --merge-hooks "$CODEX_HOME/hooks.json" \
  "$start_hook" "$compact_hook" "$end_hook"

printf 'merged lifecycle hooks in %s\n' "$CODEX_HOME/hooks.json"
printf 'Review installed hooks with /hooks before enabling them.\n'
