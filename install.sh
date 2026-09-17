#!/usr/bin/env bash
# install.sh — One-time setup to enforce Claude workflow across all projects.
#
# What this does:
#   1. Copies CLAUDE.md into ~/.claude/ (global Claude Code config)
#   2. Registers this checkout as a Claude Code plugin marketplace and installs
#      the `jplugin` plugin at user scope; offers to delete the pre-plugin skill
#      copies from ~/.claude/skills/ (one y/N; nothing is deleted on N or EOF)
#   3. Copies .agents/ into ~/.agents/ (harness-neutral skills, read by Pi and Codex)
#   4. Copies agents into ~/.claude/agents/
#   5. Installs a global SessionStart hook that orients Claude in any project
#   6. Configures Pi (~/.pi/agent/settings.json) if installed
#   7. Wires graphify into this project if the CLI is present (optional)
#   8. Sets up a git template dir so new repos receive the pre-push hook
#   9. Installs project-template/ + a global `git scaffold` alias that copies it
#      into any repo (git has no post-init hook, so bootstrap is explicit)
#  10. Prints a `newproject` shell function to add to your .bashrc / .zshrc
#
# Usage:
#   git clone <this-repo> ~/jplugin-agentic-development
#   cd ~/jplugin-agentic-development && bash install.sh
#
# Skill delivery is the plugin, not a copy: nothing is ever written into
# ~/.claude/skills/. The only deletion this script can perform is of entries
# there whose name the template ships now or once shipped, and only after you
# answer y to a list of them. Anything else in ~/.claude/skills/ is never touched.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
GIT_TEMPLATE_DIR="$HOME/.git-templates"

GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

step() { echo -e "\n${BOLD}▶ $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $2"; }

usage() {
  echo "Usage: bash install.sh"
  echo ""
  echo "  -h, --help      Show this message."
  echo ""
  echo "  Pre-plugin copies under ~/.claude/skills/ are listed during the run and"
  echo "  deleted only after a typed y. There is no flag for it any more."
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

MARKETPLACE_NAME="jplugin-agentic-development"
PLUGIN_ID="jplugin@$MARKETPLACE_NAME"
PLUGIN_OUTCOME=""   # Installed | Already | Skipped
LEGACY_OUTCOME=""   # Clean | Kept(n) | Removed(n)

# install_claude_plugin REPO_DIR — sets PLUGIN_OUTCOME.
# Registers the checkout as a directory marketplace and installs the plugin at
# user scope. Both writes are idempotent, so a crash between them is recovered by
# the next run. A CLI exit code other than 0 aborts the script (set -e) with the
# CLI's own output — never silently continues.
# register_marketplace REPO_DIR — idempotent; PLUGIN_OUTCOME=Installed when it wrote.
register_marketplace() {
  local repo_dir="$1"
  if claude plugin marketplace list 2>/dev/null \
       | grep -qE "(^|[[:space:]])$MARKETPLACE_NAME([[:space:]]|\$)"; then
    ok "already" "marketplace $MARKETPLACE_NAME already registered"
    return 0
  fi
  claude plugin marketplace add "$repo_dir" \
    || { echo "  ERROR: 'claude plugin marketplace add' failed — see output above" >&2; exit 1; }
  ok "registered" "directory marketplace $MARKETPLACE_NAME → $repo_dir"
  PLUGIN_OUTCOME="Installed"
}

# install_plugin_user_scope — idempotent; PLUGIN_OUTCOME=Installed when it wrote.
install_plugin_user_scope() {
  if grep -qF "\"$PLUGIN_ID\"" "$CLAUDE_HOME/plugins/installed_plugins.json" 2>/dev/null; then
    ok "already" "$PLUGIN_ID already installed"
    return 0
  fi
  claude plugin install "$PLUGIN_ID" --scope user \
    || { echo "  ERROR: 'claude plugin install $PLUGIN_ID' failed — see output above" >&2; exit 1; }
  ok "installed" "$PLUGIN_ID (user scope)"
  PLUGIN_OUTCOME="Installed"
}

install_claude_plugin() {
  local repo_dir="$1"
  PLUGIN_OUTCOME="Already"
  if ! command -v claude >/dev/null 2>&1; then
    echo "  NOTE: claude CLI not found on PATH — plugin registration skipped."
    echo "  Install Claude Code, then re-run install.sh, or run by hand:"
    echo "    claude plugin marketplace add \"$repo_dir\""
    echo "    claude plugin install $PLUGIN_ID --scope user"
    PLUGIN_OUTCOME="Skipped"
    return 0
  fi
  register_marketplace "$repo_dir"
  install_plugin_user_scope
  # One marketplace per name (verified 2026-09-17): a project whose
  # .claude/settings.json declares the github source under this name replaces
  # this directory registration when opened. The installed record keeps its
  # installPath, so skills keep loading from this checkout until `plugin update`.
  echo "  (opening a project that declares the github marketplace replaces this directory"
  echo "   registration; re-run install.sh to point it back at the checkout)"
}

# retired_template_skill_names REPO_DIR — skill names the template once shipped
# and later deleted, computed from history over both trees the way /tidy does.
# A shallow clone cannot answer, and says so rather than guessing.
retired_template_skill_names() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if [ "$(git -C "$1" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    echo "  NOTE: shallow clone — retired template names are unknown; only current names are candidates" >&2
    return 0
  fi
  git -C "$1" log --diff-filter=D --name-only --format= \
      -- '.agents/skills/*/SKILL.md' '.claude/skills/*/SKILL.md' 2>/dev/null \
    | awk -F/ 'NF >= 3 { print $(NF-1) }' | sort -u
}

# legacy_skill_candidates REPO_DIR — entries under ~/.claude/skills/ whose name
# the template ships now or once shipped. Everything else there is the user's
# own and is never a candidate (lesson #52: the old "not in the template"
# predicate is exactly the protected set).
legacy_skill_candidates() {
  local repo_dir="$1" known entry name
  known="$(ls "$repo_dir/.agents/skills" 2>/dev/null; retired_template_skill_names "$repo_dir")"
  for entry in "$CLAUDE_HOME/skills"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    if printf '%s\n' "$known" | grep -qxF -- "$name"; then
      printf '%s\n' "$name"
    fi
  done
  return 0
}

# remove_legacy_skill_copies REPO_DIR — sets LEGACY_OUTCOME.
# Lists the candidates and asks once. y deletes them; N, EOF or a
# non-interactive run deletes nothing and prints the manual command.
remove_legacy_skill_copies() {
  local candidates count reply=""
  candidates="$(legacy_skill_candidates "$1")"
  if [ -z "$candidates" ]; then
    ok "clean" "~/.claude/skills/ holds no pre-plugin template copies"
    LEGACY_OUTCOME="Clean"
    return 0
  fi
  count="$(printf '%s\n' "$candidates" | wc -l | tr -d ' ')"
  echo ""
  echo "  ~/.claude/skills/ still holds $count pre-plugin copies of template skills:"
  printf '%s\n' "$candidates" | sed 's/^/    - /'
  echo "  While they exist, /<name> runs the stale copy instead of the plugin's skill."
  printf '  Delete them? [y/N] '
  read -r reply || reply=""
  if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
    echo "  Kept. Remove them later with:"
    echo "    (cd \"$CLAUDE_HOME/skills\" && rm -rf $(printf '%s ' $candidates))"
    LEGACY_OUTCOME="Kept($count)"
    return 0
  fi
  printf '%s\n' "$candidates" | while IFS= read -r name; do
    [ -n "$name" ] && rm -rf "$CLAUDE_HOME/skills/$name"
  done
  ok "removed" "$count pre-plugin copies deleted"
  LEGACY_OUTCOME="Removed($count)"
}

# report_skills_source PLUGIN_OUTCOME LEGACY_OUTCOME — the derived machine state
# (spec § Data models). Every pair the two steps can produce is named; anything
# else is a bug in this script and is reported as one, never guessed at.
report_skills_source() {
  case "$1/$2" in
    Skipped/)            echo "  skills source: legacy-copy (plugin not registered)" ;;
    */Clean|*/Removed*)  echo "  skills source: plugin" ;;
    */Kept*)             echo "  skills source: both (plugin installed; pre-plugin copies kept)" ;;
    *)                   echo "  ERROR: unrecognised install outcome '$1/$2'" >&2; return 1 ;;
  esac
}

# ── 1. Global CLAUDE.md ───────────────────────────────────────────────────────
step "Installing global CLAUDE.md"
mkdir -p "$CLAUDE_HOME"
cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
ok "copied" "~/.claude/CLAUDE.md"

# ── 2. Claude Code plugin ─────────────────────────────────────────────────────
# Skills reach Claude Code through the jplugin plugin, whose manifest points at
# .agents/skills/. Nothing is copied into ~/.claude/skills/ any more; the
# pre-plugin copies an earlier install left there are offered for removal, and
# only when the plugin actually got registered — a machine without the CLI keeps
# them, because they are all it has.
step "Registering the jplugin plugin"
install_claude_plugin "$REPO_DIR"
if [ "$PLUGIN_OUTCOME" != "Skipped" ]; then
  remove_legacy_skill_copies "$REPO_DIR"
fi
report_skills_source "$PLUGIN_OUTCOME" "$LEGACY_OUTCOME"

# ── 3. Shared workflow → ~/.agents/ ──────────────────────────────────────────
step "Installing shared workflow → ~/.agents/"
mkdir -p "$HOME/.agents"
cp -r "$REPO_DIR/.agents/"* "$HOME/.agents/"
ok "copied" "~/.agents/ ($(find "$HOME/.agents/skills" -name 'SKILL.md' | wc -l | tr -d ' ') skills)"

# ── 4. Global agents ─────────────────────────────────────────────────────────
step "Installing global agents → ~/.claude/agents/"
mkdir -p "$CLAUDE_HOME/agents"
cp "$REPO_DIR/.claude/agents/"*.md "$CLAUDE_HOME/agents/"
ok "copied" "$(ls "$CLAUDE_HOME/agents/"*.md | wc -l | tr -d ' ') agents"

# ── 5. Global SessionStart hook ───────────────────────────────────────────────
step "Installing global SessionStart hook"
mkdir -p "$CLAUDE_HOME/hooks"
cp "$REPO_DIR/.claude/hooks/session-start.sh" "$CLAUDE_HOME/hooks/session-start.sh"
chmod +x "$CLAUDE_HOME/hooks/session-start.sh"
ok "copied" "~/.claude/hooks/session-start.sh"

# Merge SessionStart into ~/.claude/settings.json (preserves existing settings).
# NOTE: this is the ONLY place the SessionStart hook is registered. Deliberately
# user-level only — the repo's .claude/settings.json must NOT register it too, or
# /sync would copy that into every project and the hook would fire twice per session.
SETTINGS_FILE="$CLAUDE_HOME/settings.json"
SESSION_HOOK_CMD="bash $CLAUDE_HOME/hooks/session-start.sh"

if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$SESSION_HOOK_CMD"
          }
        ]
      }
    ]
  }
}
EOF
  ok "created" "~/.claude/settings.json"
else
  # Check if SessionStart hook is already present
  if ! grep -q "session-start.sh" "$SETTINGS_FILE" 2>/dev/null; then
    echo ""
    echo "  NOTE: ~/.claude/settings.json already exists."
    echo "  Add this SessionStart hook manually if it's missing:"
    echo ""
    echo '    "SessionStart": [{"hooks": [{"type": "command", "command": "'"$SESSION_HOOK_CMD"'"}]}]'
    echo ""
  else
    ok "already present" "SessionStart hook in ~/.claude/settings.json"
  fi
fi

# NOTE: there is deliberately no step here writing a top-level `skills` key into
# ~/.claude/settings.json. Claude Code's settings schema is strict and has no such
# field (verified against the CLI's own schema: it exposes `skillOverrides` and
# `disableBundledSkills`, but no skill-path array), so writing one makes the CLI
# report `Unrecognized field: skills`. It is also unnecessary — Claude Code loads
# the skills through the plugin step 2 registers. Pi is a separate schema and
# is still configured below.

# ── 6. Configure Pi if installed ─────────────────────────────────────────────
PI_SETTINGS="$HOME/.pi/agent/settings.json"
if [ -f "$PI_SETTINGS" ]; then
  step "Configuring Pi skill paths"
  if command -v jq > /dev/null 2>&1; then
    if jq -e '.skills | index("~/.agents/skills")' "$PI_SETTINGS" > /dev/null 2>&1; then
      ok "already" "~/.agents/skills already in Pi settings"
    else
      jq '.skills = ((.skills // []) + ["~/.agents/skills"])' "$PI_SETTINGS" > /tmp/pi_settings_tmp.json && mv /tmp/pi_settings_tmp.json "$PI_SETTINGS"
      ok "updated" "added ~/.agents/skills to Pi settings"
    fi
  else
    echo "  NOTE: jq not found — Pi skill path not automatically added."
  fi
fi

# ── 7. Wire graphify into this project (optional) ────────────────────────────
# graphify is a per-machine CLI with per-project state (./graphify-out/graph.json),
# so it has to be wired per repo. Entirely optional — never block the install.
step "Wiring graphify (optional)"
if command -v graphify > /dev/null 2>&1; then
  graphify claude install > /dev/null 2>&1 || true
  graphify hook install > /dev/null 2>&1 || true

  # `graphify claude install` writes its `## graphify` rules into CLAUDE.md, which /sync
  # overwrites wholesale — so the rules vanish silently on the next sync while the
  # PreToolUse hook and the skill both survive, leaving graphify looking wired but
  # rule-less. Relocate the section to .claude/project.md, which /sync never touches.
  if [ -f CLAUDE.md ] && grep -q '^## graphify$' CLAUDE.md; then
    mkdir -p .claude
    [ -f .claude/project.md ] || printf '# Project-Specific Configuration\n\n> Imported by CLAUDE.md. Safe to edit — /sync never touches this file.\n' > .claude/project.md
    if ! grep -q '^## graphify$' .claude/project.md; then
      {
        printf '\n'
        awk '/^## graphify$/{f=1} f' CLAUDE.md
      } >> .claude/project.md
    fi
    # Drop the section from CLAUDE.md. It is emitted last, so truncating at its
    # header is sufficient and leaves the template content untouched.
    awk '/^## graphify$/{exit} {print}' CLAUDE.md > CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md
    ok "moved" "graphify rules: CLAUDE.md -> .claude/project.md (survives /sync)"
  fi

  # graphify-out/ is ~13 MB of generated artefacts that sit in the working tree.
  # Two separate protections are needed, and neither is created by graphify itself:
  #
  #   .gitignore — without it the directory shows as untracked and is one
  #                `git add .` away from being committed.
  #   .ignore    — graph.json indexes the source, so it matches ordinary
  #                identifiers, and graph.html holds a SINGLE ~1.4 MB line. An
  #                unscoped `rg <identifier>` returns that line and can exhaust an
  #                agent's context window in one tool call. Observed 2026-07-29:
  #                three subagents died this way before the cause was found.
  #
  # Both writes are idempotent.
  if ! grep -qx "graphify-out/" .gitignore 2> /dev/null; then
    printf '\n# graphify knowledge graph — machine-local, rebuilt by post-commit hook\ngraphify-out/\n' >> .gitignore
  fi
  if ! grep -qx "graphify-out/" .ignore 2> /dev/null; then
    printf '# Search-tool exclusions (ripgrep, fd — plain `grep -r` does NOT honour this).\ngraphify-out/\nnode_modules/\n' >> .ignore
  fi

  ok "wired" "graphify: CLAUDE.md + PreToolUse hook + git hooks + .gitignore/.ignore"
else
  echo "  NOTE: graphify not found — optional code-graph indexing skipped."
  echo "  Install with: pip install graphify   (then re-run this installer)"
fi

# ── 8. Git template directory ─────────────────────────────────────────────────
step "Setting up git template dir → $GIT_TEMPLATE_DIR"
mkdir -p "$GIT_TEMPLATE_DIR/hooks"

# pre-push hook: typecheck + lint before every git push (harness-agnostic)
cp "$REPO_DIR/.agents/git-hooks/pre-push" "$GIT_TEMPLATE_DIR/hooks/pre-push"
chmod +x "$GIT_TEMPLATE_DIR/hooks/pre-push"
ok "installed" "pre-push hook (typecheck + lint + wrap-up gate)"

# A git template applies only to repositories created *after* installation, so
# every already-cloned repo — including this one — would never receive the hook.
# That is how the previous pre-push guard ended up dormant: present in the tree,
# wired nowhere. Install into the current repo too when there is one. Worktrees
# share --git-common-dir, so one copy covers all of them.
if CURRENT_GIT_DIR="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  mkdir -p "$CURRENT_GIT_DIR/hooks"
  cp "$REPO_DIR/.agents/git-hooks/pre-push" "$CURRENT_GIT_DIR/hooks/pre-push"
  chmod +x "$CURRENT_GIT_DIR/hooks/pre-push"
  ok "installed" "pre-push hook → $CURRENT_GIT_DIR/hooks (existing repo)"
fi

git config --global init.templateDir "$GIT_TEMPLATE_DIR"
ok "set" "git config --global init.templateDir $GIT_TEMPLATE_DIR"

# ── 9. Project scaffold → ~/.agents/project-template + `git scaffold` ────────
# Git has no post-init hook: a template dir only seeds .git/, it never runs
# anything on `git init`. The hooks/post-init this step used to write was copied
# into every new repo and executed nowhere. Bootstrap is now an explicit,
# supported entry point — a global git alias — backed by a template copy that
# lives next to the script, so it resolves whatever path this checkout sits at.
step "Installing project scaffold → ~/.agents/project-template + git scaffold"
[ -d "$REPO_DIR/project-template" ] \
  || { echo "install.sh: project-template/ missing from $REPO_DIR — refusing to remove the installed copy" >&2; exit 1; }
rm -f "$GIT_TEMPLATE_DIR/hooks/post-init"   # dead hook left by earlier installs
rm -rf "$HOME/.agents/project-template"     # installer-owned copy; replaced wholesale
cp -r "$REPO_DIR/project-template" "$HOME/.agents/project-template"
mkdir -p "$HOME/.agents/bin"
cp "$REPO_DIR/scripts/scaffold-project.sh" "$HOME/.agents/bin/scaffold-project.sh"
chmod +x "$HOME/.agents/bin/scaffold-project.sh"
git config --global alias.scaffold '!bash "$HOME/.agents/bin/scaffold-project.sh"'
ok "copied" "~/.agents/project-template ($(find "$REPO_DIR/project-template" -type f | wc -l | tr -d ' ') files)"
ok "set" "git alias: git scaffold → ~/.agents/bin/scaffold-project.sh"

# ── 10. Print newproject shell function ───────────────────────────────────────
step "Shell function — add this to your ~/.bashrc or ~/.zshrc"
cat <<'SHELLCONFIG'

# ── Claude Workflow: new project bootstrapper ─────────────────────────────────
newproject() {
  local name="${1:?Usage: newproject <project-name>}"
  mkdir -p "$name" && cd "$name" || return 1
  git init -q && git scaffold || return 1   # explicit bootstrap: git has no post-init hook
  echo "# $name" > README.md
  git add . && git commit -q -m "chore: init project with coding-agent scaffold" || return 1
  echo ""
  echo "Project '$name' ready. Open with: claude"
}
# ─────────────────────────────────────────────────────────────────────────────

SHELLCONFIG

echo ""
echo -e "${BOLD}Done.${RESET}"
echo ""
echo "  Reload your shell:  source ~/.bashrc  (or ~/.zshrc)"
echo "  Start a new project: newproject my-app"
echo "  Or in an existing repo: git scaffold   (adds missing files, never overwrites)"
echo "  Pasted newproject before this version? Replace it — the old one relied on a"
echo "  post-init hook git never runs, so it committed unscaffolded repos."
echo ""
echo "  Claude will now orient itself at session start in every project"
echo "  (learning-store counts, active tasks, git branch) via the global SessionStart hook."
echo ""
