# tests/test-install-sh.sh — install.sh must never destroy user skills, and must
# not write invalid keys into ~/.claude/settings.json.
#
# The functional cases run install.sh for real against a throwaway $HOME and a
# throwaway CWD, so nothing touches the developer's own ~/.claude.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

INSTALL="$REPO/install.sh"
USER_SKILL="my-personal-skill"

# ── Static checks ────────────────────────────────────────────────────────────
src="$(cat "$INSTALL")"

# Match live commands only — prose mentioning the old bug must not trip these.
count_matching() { grep -c -E "$1" "$INSTALL" 2>/dev/null || true; }

assert_eq "0" "$(count_matching '^[[:space:]]*rm -rf "\$CLAUDE_HOME/skills"[[:space:]]*$')" \
  "install.sh: no live 'rm -rf ~/.claude/skills' command"
assert_contains "$src" 'cp -r "$REPO_DIR/.claude/skills/." "$CLAUDE_HOME/skills/"' \
  "install.sh: copies skills INTO the dir (non-destructive)"
assert_contains "$src" "--prune-skills" \
  "install.sh: pruning is behind an explicit --prune-skills flag"

# The invalid key is a Claude Code concern only. Pi has its own schema where a
# `skills` array IS valid, so that write must survive.
assert_eq "0" "$(count_matching 'jq .*\.skills.*\$SETTINGS_FILE')" \
  "install.sh: never writes a 'skills' key into ~/.claude/settings.json"
assert_eq "0" "$(count_matching 'jq .*\.skills.*> /tmp/settings_tmp.json')" \
  "install.sh: no leftover Claude-side skills-path jq write"
assert_contains "$src" '$PI_SETTINGS' \
  "install.sh: Pi skill-path configuration retained"

# Git has no post-init hook (see `git help githooks`): a file under
# ~/.git-templates/hooks/post-init is copied into every new repo and never run.
# Bootstrap must be an explicit, supported entry point — a global `git scaffold`
# alias backed by a template copy that lives next to the script (#99–#102).
assert_eq "0" "$(count_matching 'hooks/post-init" <<')" \
  "install.sh: writes no post-init hook — git never dispatches one"
assert_eq "0" "$(count_matching 'runs on every git init')" \
  "install.sh: no longer claims anything runs on git init"
assert_contains "$src" 'scripts/scaffold-project.sh' \
  "install.sh: installs the checked-in scaffold script"
assert_contains "$src" 'alias.scaffold' \
  "install.sh: registers the git scaffold alias"
assert_not_contains "$src" 'coding-agent-workflow/project-template' \
  "install.sh: no hardcoded clone path for the template"
assert_contains "$src" 'git scaffold' \
  "install.sh: newproject and existing-repo guidance call git scaffold"
assert_eq "present" "$([ -x scripts/scaffold-project.sh ] && echo present || echo missing)" \
  "scripts/scaffold-project.sh: exists and is executable"
assert_file_not_matches scripts/scaffold-project.sh '\$HOME/coding-agent-workflow' \
  "scaffold-project.sh: resolves the template relative to itself, not a clone path"
assert_file_not_matches README.md 'post-init.? hook (fires|runs|triggers)' \
  "README: no longer advertises a post-init hook firing on git init"
assert_file_contains README.md 'git scaffold' \
  "README: advertises git scaffold for new and existing repos"
assert_eq "0" "$(sed -n '/^## Adding to an Existing Project/,/^---/p' README.md | grep -c '^cp ' || true)" \
  "README: existing-project instructions use no overwriting cp commands"

# M3/M4: the typed store and glossary are seeded through the template inventory.
for seed in tasks/solutions/README.md tasks/history.md tasks/concepts.md tasks/todo.md \
            CLAUDE.md AGENTS.md .ignore .gitignore .gitattributes; do
  assert_eq "present" "$([ -e "project-template/$seed" ] && echo present || echo missing)" \
    "project-template: carries $seed"
done
assert_eq "missing" "$([ -e "project-template/tasks/lessons.md" ] && echo present || echo missing)" \
  "project-template: lessons.md seed retired"
assert_eq "missing" "$([ -e "project-template/tasks/bugs.md" ] && echo present || echo missing)" \
  "project-template: bugs.md seed retired"

# ── Functional harness ───────────────────────────────────────────────────────
# Run install.sh with an isolated HOME. Plants a user-owned skill first so we can
# prove it survives. Echoes the temp HOME path; caller inspects it.
run_install() {
  local confirm="$1"; shift
  local sandbox home
  sandbox="$(mktemp -d)"
  home="$sandbox/home"
  mkdir -p "$home/.claude/skills/$USER_SKILL"
  printf 'name: %s\n' "$USER_SKILL" > "$home/.claude/skills/$USER_SKILL/SKILL.md"
  # Empty confirm means a closed stdin (true EOF), not a blank line.
  local stdin=/dev/null
  if [ -n "$confirm" ]; then
    stdin="$sandbox/stdin.txt"
    printf '%s\n' "$confirm" > "$stdin"
  fi
  # Run from inside the sandbox: install.sh's optional graphify step writes to CWD.
  ( cd "$sandbox" && HOME="$home" bash "$INSTALL" "$@" ) > "$sandbox/out.log" 2>&1 < "$stdin"
  printf '%s\n' "$sandbox"
}

exists() { [ -e "$1" ] && echo present || echo missing; }

# ── Case 1: default run is additive ──────────────────────────────────────────
box="$(run_install "")"
h="$box/home"

assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL/SKILL.md")" \
  "default run: user's own skill survives installation"
assert_eq "present" "$(exists "$h/.claude/skills/build/SKILL.md")" \
  "default run: template skills are installed"
assert_eq "present" "$(exists "$h/.claude/settings.json")" \
  "default run: settings.json created"
assert_not_contains "$(cat "$h/.claude/settings.json")" '"skills"' \
  "default run: settings.json contains no invalid 'skills' key"
assert_file_contains "$h/.claude/settings.json" "session-start.sh" \
  "default run: SessionStart hook still registered"
rm -rf "$box"

# ── Case 2: retired template skills also survive a default run ───────────────
# A skill the template dropped (e.g. deslop) is indistinguishable from a personal
# skill, so the additive default must keep it too.
box="$(run_install "")"
h="$box/home"
mkdir -p "$h/.claude/skills/retired-skill"
touch "$h/.claude/skills/retired-skill/SKILL.md"
( cd "$box" && HOME="$h" bash "$INSTALL" ) > "$box/out2.log" 2>&1 < /dev/null
assert_eq "present" "$(exists "$h/.claude/skills/retired-skill/SKILL.md")" \
  "re-run: retired template skill is not silently removed"
assert_contains "$(cat "$box/out2.log")" "--prune-skills" \
  "re-run: reports kept non-template entries and how to prune them"
rm -rf "$box"

# ── Case 3: --prune-skills refuses without confirmation ──────────────────────
box="$(run_install "" --prune-skills)"
h="$box/home"
assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL/SKILL.md")" \
  "--prune-skills with no confirmation (EOF): nothing deleted"
assert_contains "$(cat "$box/out.log")" "$USER_SKILL" \
  "--prune-skills: lists what it would delete before asking"
rm -rf "$box"

box="$(run_install "no" --prune-skills)"
h="$box/home"
assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL/SKILL.md")" \
  "--prune-skills answered 'no': nothing deleted"
rm -rf "$box"

# ── Case 4: --prune-skills deletes only on explicit confirmation ─────────────
box="$(run_install "delete" --prune-skills)"
h="$box/home"
assert_eq "missing" "$(exists "$h/.claude/skills/$USER_SKILL")" \
  "--prune-skills confirmed: non-template entry deleted"
assert_eq "present" "$(exists "$h/.claude/skills/build/SKILL.md")" \
  "--prune-skills confirmed: template skills untouched"
rm -rf "$box"

# ── Case 5: unknown flags are rejected, not ignored ──────────────────────────
box="$(mktemp -d)"
( cd "$box" && HOME="$box/home" bash "$INSTALL" --bogus ) > "$box/out.log" 2>&1 < /dev/null
assert_eq "1" "$?" "unknown flag: exits non-zero instead of installing"
rm -rf "$box"

# ── Case 6: scaffold works from a checkout path with spaces, anywhere on disk ─
# Install via a symlinked checkout whose path contains spaces, with an isolated
# HOME. Nothing may depend on the clone living at ~/coding-agent-workflow.
box="$(mktemp -d)"
h="$box/home"
mkdir -p "$h"
ln -s "$REPO" "$box/src with spaces"
( cd "$box" && HOME="$h" bash "$box/src with spaces/install.sh" ) > "$box/out.log" 2>&1 < /dev/null
assert_eq "0" "$?" "spaced checkout: install.sh succeeds"
assert_eq "present" "$(exists "$h/.agents/project-template/.gitattributes")" \
  "spaced checkout: template copied to ~/.agents/project-template (dotfiles included)"
assert_eq "present" "$(exists "$h/.agents/bin/scaffold-project.sh")" \
  "spaced checkout: scaffold script installed to ~/.agents/bin"
assert_contains "$(HOME="$h" git config --global --get alias.scaffold)" "scaffold-project.sh" \
  "spaced checkout: git scaffold alias registered globally"
assert_not_contains "$(cat "$box/out.log")" "runs on every git init" \
  "spaced checkout: installer no longer claims a hook runs on git init"
assert_eq "missing" "$(exists "$h/.git-templates/hooks/post-init")" \
  "spaced checkout: no dead post-init hook is written into the template dir"

# Re-install over an earlier install: the installer-owned copy is replaced wholesale
# and a dead hook left by an earlier version is removed (the upgrade path).
touch "$h/.agents/project-template/STALE.md" "$h/.git-templates/hooks/post-init"
( cd "$box" && HOME="$h" bash "$box/src with spaces/install.sh" ) > "$box/out2.log" 2>&1 < /dev/null
assert_eq "0" "$?" "re-install: succeeds over an existing install"
assert_eq "missing" "$(exists "$h/.agents/project-template/STALE.md")" \
  "re-install: stale file in the installed template is gone"
assert_eq "missing" "$(exists "$h/.git-templates/hooks/post-init")" \
  "re-install: dead post-init hook from an earlier version is removed"

# A fresh repo whose path also contains spaces; bootstrap through the alias only.
repo="$box/new repo"
git init -q "$repo"
( cd "$repo" && HOME="$h" git scaffold ) > "$box/scaffold.log" 2>&1
assert_eq "0" "$?" "git scaffold: exits 0 in a fresh repo"
inventory="$(cd "$REPO/project-template" && find . -type f | sed 's|^\./||' | sort)"
count="$(printf '%s\n' "$inventory" | wc -l | tr -d ' ')"
while IFS= read -r rel; do
  assert_files_identical "$REPO/project-template/$rel" "$repo/$rel" \
    "git scaffold: $rel matches the checked-in template"
done <<< "$inventory"
assert_contains "$(cat "$box/scaffold.log")" "scaffold: $count created, 0 kept" \
  "git scaffold: summary line counts every template file as created"
assert_eq "$inventory" "$(cd "$repo" && find . -type f -not -path './.git/*' | sed 's|^\./||' | sort)" \
  "git scaffold: generated output equals the template inventory exactly"
assert_eq "present" "$([ -d "$repo/specs" ] && echo present || echo missing)" \
  "git scaffold: creates specs/"

# From a subdirectory the scaffold still lands at the repository root.
nested="$box/nested"
git init -q "$nested"
mkdir -p "$nested/deep/er"
( cd "$nested/deep/er" && HOME="$h" git scaffold ) > /dev/null 2>&1
assert_eq "0" "$?" "git scaffold from a subdirectory: exits 0"
assert_eq "present" "$(exists "$nested/CLAUDE.md")" \
  "git scaffold from a subdirectory: files land at the repo root"
assert_eq "missing" "$(exists "$nested/deep/er/CLAUDE.md")" \
  "git scaffold from a subdirectory: nothing is written into the cwd"

# ── Case 7: existing files are preserved byte-for-byte; re-runs are no-ops ────
repo2="$box/existing"
git init -q "$repo2"
printf '# mine, do not touch\n' > "$repo2/CLAUDE.md"
ln -s /nonexistent/target "$repo2/.ignore"     # dangling symlink: still the user's file
mkdir "$repo2/AGENTS.md"                        # a directory where the template has a file
( cd "$repo2" && HOME="$h" git scaffold ) > "$box/scaffold2.log" 2>&1
assert_eq "0" "$?" "git scaffold: exits 0 when files already exist"
assert_eq "present" "$([ -L "$repo2/.ignore" ] && echo present || echo missing)" \
  "git scaffold: a dangling symlink at a template path is kept, not written through"
assert_eq "present" "$([ -d "$repo2/AGENTS.md" ] && echo present || echo missing)" \
  "git scaffold: a directory at a template path is kept"
assert_eq "# mine, do not touch" "$(cat "$repo2/CLAUDE.md")" \
  "git scaffold: existing CLAUDE.md is byte-identical after bootstrap"
assert_eq "present" "$(exists "$repo2/tasks/todo.md")" \
  "git scaffold: missing files are still added around the preserved ones"
assert_contains "$(cat "$box/scaffold2.log")" "kept" \
  "git scaffold: reports preserved files"
before="$(cd "$repo2" && find . -type f -not -path './.git/*' -exec md5sum {} + | sort)"
( cd "$repo2" && HOME="$h" git scaffold ) > "$box/scaffold3.log" 2>&1
after="$(cd "$repo2" && find . -type f -not -path './.git/*' -exec md5sum {} + | sort)"
assert_eq "$before" "$after" "git scaffold: second run changes nothing"
assert_contains "$(cat "$box/scaffold3.log")" "scaffold: 0 created, $count kept" \
  "git scaffold: second run reports every template file as kept"

# ── Case 8: failures are loud ─────────────────────────────────────────────────
plain="$box/not a repo"
mkdir -p "$plain"
( cd "$plain" && HOME="$h" bash "$h/.agents/bin/scaffold-project.sh" ) > "$box/norepo.log" 2>&1
assert_eq "1" "$?" "scaffold outside a git repo: exits non-zero"
assert_contains "$(cat "$box/norepo.log")" "git init" \
  "scaffold outside a git repo: tells the user what to do"

rm -rf "$h/.agents/project-template"
mkdir -p "$h/.agents/project-template"
empty="$box/empty template"
git init -q "$empty"
( cd "$empty" && HOME="$h" git scaffold ) > "$box/empty.log" 2>&1
assert_eq "1" "$?" "git scaffold with an empty template: exits non-zero"
assert_contains "$(cat "$box/empty.log")" "holds no files" \
  "git scaffold with an empty template: says the template is empty"
assert_eq "missing" "$(exists "$empty/specs")" \
  "git scaffold with an empty template: writes nothing"

rm -rf "$h/.agents/project-template"
repo3="$box/orphan"
git init -q "$repo3"
( cd "$repo3" && HOME="$h" git scaffold ) > "$box/missing.log" 2>&1
assert_eq "1" "$?" "git scaffold with the template missing: exits non-zero"
assert_contains "$(cat "$box/missing.log")" "$h/.agents/project-template" \
  "git scaffold with the template missing: names the expected path"
assert_contains "$(cat "$box/missing.log")" "install.sh" \
  "git scaffold with the template missing: names the fix"
assert_eq "missing" "$(exists "$repo3/CLAUDE.md")" \
  "git scaffold with the template missing: writes nothing"
rm -rf "$box"

# ── Case 9: the printed newproject function does what the docs say ───────────
# Eval the function exactly as install.sh printed it, so the documented path is
# the tested path. Only the global alias installed above is available to it.
box="$(run_install "")"
h="$box/home"
fn="$(sed -n '/^newproject() {/,/^}/p' "$box/out.log")"
assert_contains "$fn" "git scaffold" "newproject: printed function bootstraps via git scaffold"
(
  cd "$box" || exit 1
  export HOME="$h"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  eval "$fn"
  newproject "my app" > "$box/newproject.log" 2>&1
)
assert_eq "0" "$?" "newproject: succeeds"
assert_eq "present" "$(exists "$box/my app/AGENTS.md")" "newproject: AGENTS.md scaffolded"
assert_eq "present" "$(exists "$box/my app/tasks/todo.md")" "newproject: tasks/todo.md scaffolded"
assert_eq "present" "$(exists "$box/my app/.gitattributes")" "newproject: .gitattributes scaffolded"
assert_contains "$(cd "$box/my app" && HOME="$h" git log --oneline -1)" "scaffold" \
  "newproject: initial commit made"
assert_contains "$(cd "$box/my app" && HOME="$h" git ls-files)" "CLAUDE.md" \
  "newproject: scaffold is part of the initial commit"

# When bootstrap fails, newproject stops before committing a bare README.
rm -rf "$h/.agents/project-template"
(
  cd "$box" || exit 1
  export HOME="$h"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  eval "$fn"
  newproject "broken app" > "$box/broken.log" 2>&1
)
assert_eq "1" "$?" "newproject: fails loudly when git scaffold fails"
assert_contains "$(cat "$box/broken.log")" "install.sh" \
  "newproject: failure names the fix"
assert_eq "missing" "$(cd "$box/broken app" && HOME="$h" git rev-parse --verify -q HEAD >/dev/null 2>&1 && echo present || echo missing)" \
  "newproject: no commit is made when bootstrap fails"
rm -rf "$box"

finish
