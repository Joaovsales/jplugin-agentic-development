#!/usr/bin/env bash
# scaffold-project.sh — copy the coding-agent project scaffold into the current
# git repository, preserving every file that already exists.
#
# install.sh installs this next to a copy of project-template/ under ~/.agents/
# and registers it as the global alias `git scaffold`. The template is resolved
# relative to this file, so it works from the checkout and from the installed
# copy alike — never from a hardcoded clone path. Git has no post-init hook, so
# this is the explicit bootstrap step `newproject` runs after `git init`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../project-template"

fail() { printf 'scaffold: %s\n' "$1" >&2; exit 1; }

[ -d "$TEMPLATE_DIR" ] \
  || fail "project template not found at $(cd "$SCRIPT_DIR/.." && pwd)/project-template — re-run install.sh from the coding-agent-workflow checkout"
TEMPLATE_DIR="$(cd "$TEMPLATE_DIR" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)" \
  || fail "needs a git work tree — run 'git init' first, then 'git scaffold'"

created=0
kept=0
while IFS= read -r -d '' src; do
  rel="${src#"$TEMPLATE_DIR"/}"
  dst="$REPO_ROOT/$rel"
  if [ -e "$dst" ] || [ -L "$dst" ]; then   # -L: a dangling symlink is still the user's file
    kept=$((kept + 1))
    printf '  kept    %s\n' "$rel"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    created=$((created + 1))
    printf '  created %s\n' "$rel"
  fi
done < <(find "$TEMPLATE_DIR" -type f -print0 | sort -z)

[ $((created + kept)) -gt 0 ] || fail "project template at $TEMPLATE_DIR holds no files — re-run install.sh"
mkdir -p "$REPO_ROOT/specs"
printf 'scaffold: %d created, %d kept in %s\n' "$created" "$kept" "$REPO_ROOT"
