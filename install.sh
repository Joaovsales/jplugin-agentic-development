#!/usr/bin/env bash
# install.sh — One-time setup to enforce Claude workflow across all projects.
#
# What this does:
#   1. Copies skills and agents into ~/.claude/ (global Claude Code config)
#   2. Copies .agents/ into ~/.agents/ (harness-neutral skills)
#   3. Installs a global SessionStart hook that orients Claude in any project
#   4. Sets up a git template dir so `git init` auto-installs a post-init hook
#   5. Configures Pi (~/.pi/agent/settings.json) if installed
#   6. Wires graphify into this project if the CLI is present (optional)
#   7. Prints a `newproject` shell function to add to your .bashrc / .zshrc
#
# Usage:
#   git clone <this-repo> ~/coding-agent-workflow
#   cd ~/coding-agent-workflow && bash install.sh [--prune-skills]
#
# Skill installation is additive: nothing already in ~/.claude/skills/ is deleted
# unless you pass --prune-skills, which lists every non-template entry and waits
# for a typed confirmation first.

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
  echo "Usage: bash install.sh [--prune-skills]"
  echo ""
  echo "  --prune-skills  Offer to delete entries in ~/.claude/skills/ that this"
  echo "                  template no longer ships. Lists them and requires a typed"
  echo "                  confirmation. Without this flag nothing is ever deleted."
  echo "  -h, --help      Show this message."
}

PRUNE_SKILLS=0
for arg in "$@"; do
  case "$arg" in
    --prune-skills) PRUNE_SKILLS=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

# Entries in ~/.claude/skills/ that this template does not ship — the user's own
# skills, plus template skills retired since their last install. One per line;
# empty output means the two trees agree.
extra_global_skills() {
  local entry name
  for entry in "$CLAUDE_HOME/skills"/*; do
    [ -e "$entry" ] || continue
    name="$(basename "$entry")"
    [ -e "$REPO_DIR/.claude/skills/$name" ] || printf '%s\n' "$name"
  done
}

# Delete those entries — but only after listing them and reading back the literal
# word "delete". EOF or any other answer aborts, leaving everything in place.
prune_extra_skills() {
  local extras reply=""
  extras="$(extra_global_skills)"
  if [ -z "$extras" ]; then
    ok "nothing to prune" "~/.claude/skills/ holds no non-template entries"
    return 0
  fi
  echo ""
  echo "  --prune-skills will PERMANENTLY DELETE these non-template entries from"
  echo "  $CLAUDE_HOME/skills/ :"
  printf '%s\n' "$extras" | sed 's/^/    - /'
  echo ""
  printf '  Type "delete" to confirm (anything else aborts): '
  read -r reply || reply=""
  if [ "$reply" != "delete" ]; then
    echo "  Aborted — nothing deleted."
    return 0
  fi
  printf '%s\n' "$extras" | while IFS= read -r name; do
    [ -n "$name" ] && rm -rf "$CLAUDE_HOME/skills/$name"
  done
  ok "pruned" "$(printf '%s\n' "$extras" | wc -l | tr -d ' ') non-template entries deleted"
}

# ── 1. Global CLAUDE.md ───────────────────────────────────────────────────────
step "Installing global CLAUDE.md"
mkdir -p "$CLAUDE_HOME"
cp "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
ok "copied" "~/.claude/CLAUDE.md"

# ── 2. Global skills (backwards-compat copy) ─────────────────────────────────
# Copy INTO the directory (note the trailing /.) instead of replacing it. This
# step used to run `rm -rf "$CLAUDE_HOME/skills"` first, which silently destroyed
# every skill the user kept there that the template does not ship — personal
# skills, and template skills retired since their last install. Overwriting the
# template entries while leaving everything else alone is the safe default;
# removing retired entries is opt-in via --prune-skills.
step "Installing global skills → ~/.claude/skills/"
mkdir -p "$CLAUDE_HOME/skills"
cp -r "$REPO_DIR/.claude/skills/." "$CLAUDE_HOME/skills/"
ok "copied" "$(find "$REPO_DIR/.claude/skills" -name 'SKILL.md' | wc -l | tr -d ' ') skills (backwards-compat)"

EXTRA_SKILLS="$(extra_global_skills)"
if [ -n "$EXTRA_SKILLS" ]; then
  echo "  kept $(printf '%s\n' "$EXTRA_SKILLS" | wc -l | tr -d ' ') non-template entries: $(printf '%s\n' "$EXTRA_SKILLS" | tr '\n' ' ')"
  echo "  (re-run with --prune-skills to review and delete them)"
fi

if [ "$PRUNE_SKILLS" -eq 1 ]; then
  prune_extra_skills
fi

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
# report `Unrecognized field: skills`. It is also unnecessary — Claude Code reads
# ~/.claude/skills/ natively, which step 2 populates. Pi is a separate schema and
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

# post-init hook: copies Claude project scaffold into newly init'd repos
cat > "$GIT_TEMPLATE_DIR/hooks/post-init" <<'HOOK'
#!/usr/bin/env bash
# Auto-installed by coding-agent-workflow/install.sh
# Copies minimal Claude project scaffold after every `git init`.
# Safe: only runs if the files don't already exist.

PROJECT_TEMPLATE="$HOME/coding-agent-workflow/project-template"

if [ ! -d "$PROJECT_TEMPLATE" ]; then
  exit 0  # template not found — skip silently
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

copy_if_missing() {
  local src="$PROJECT_TEMPLATE/$1"
  local dst="$REPO_ROOT/$1"
  if [ -f "$src" ] && [ ! -f "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  [claude] created $1"
  fi
}

copy_if_missing "CLAUDE.md"
copy_if_missing "AGENTS.md"
copy_if_missing ".ignore"
copy_if_missing "tasks/todo.md"
copy_if_missing "tasks/solutions/README.md"
copy_if_missing "tasks/history.md"
copy_if_missing "tasks/concepts.md"

if [ ! -d "$REPO_ROOT/specs" ]; then
  mkdir -p "$REPO_ROOT/specs"
  echo "  [claude] created specs/"
fi
HOOK
chmod +x "$GIT_TEMPLATE_DIR/hooks/post-init"

git config --global init.templateDir "$GIT_TEMPLATE_DIR"
ok "set" "git config --global init.templateDir $GIT_TEMPLATE_DIR"
ok "installed" "post-init hook (runs on every git init)"

# ── 9. Print newproject shell function ───────────────────────────────────────
step "Shell function — add this to your ~/.bashrc or ~/.zshrc"
cat <<'SHELLCONFIG'

# ── Claude Workflow: new project bootstrapper ─────────────────────────────────
newproject() {
  local name="${1:?Usage: newproject <project-name>}"
  mkdir -p "$name" && cd "$name"
  git init                        # triggers post-init hook → copies Claude scaffold
  echo "# $name" > README.md
  git add . && git commit -m "chore: init project with Claude workflow scaffold"
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
echo "  Or in an existing repo: copy project-template/ files in manually."
echo ""
echo "  Claude will now orient itself at session start in every project"
echo "  (learning-store counts, active tasks, git branch) via the global SessionStart hook."
echo ""
