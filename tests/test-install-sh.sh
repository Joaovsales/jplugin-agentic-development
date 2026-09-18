# tests/test-install-sh.sh — install.sh registers the checkout as the jplugin
# plugin, never destroys user skills, and never writes invalid keys into
# ~/.claude/settings.json (specs/claude-plugin-manifest.md § install.sh).
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
assert_eq "0" "$(count_matching 'cp -r "\$REPO_DIR/.claude/skills')" \
  "install.sh: no longer copies skills into ~/.claude/skills/ — the plugin serves them"
assert_not_contains "$src" "--prune-skills" \
  "install.sh: the --prune-skills flag is gone (removal is the default, behind one y/N)"
assert_contains "$src" 'plugin marketplace add' \
  "install.sh: registers the checkout as a directory marketplace"
assert_contains "$src" 'plugin install "$PLUGIN_ID" --scope user' \
  "install.sh: installs the plugin at user scope"

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
assert_not_contains "$src" 'jplugin-agentic-development/project-template' \
  "install.sh: no hardcoded clone path for the template"
assert_contains "$src" 'git scaffold' \
  "install.sh: newproject and existing-repo guidance call git scaffold"
assert_eq "present" "$([ -x scripts/scaffold-project.sh ] && echo present || echo missing)" \
  "scripts/scaffold-project.sh: exists and is executable"
assert_file_not_matches scripts/scaffold-project.sh '\$HOME/jplugin-agentic-development' \
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
# Run install.sh with an isolated HOME and a PATH that cannot reach the real
# `claude` binary: every functional case either supplies a stub or proves the
# no-CLI path, so nothing here ever registers a marketplace on the developer's
# machine. Plants a user-owned skill first so we can prove it survives.
GIT_BIN_DIR="$(dirname "$(command -v git)")"
SAFE_PATH="/usr/bin:/bin:$GIT_BIN_DIR"

# make_claude_stub <dir>: a `claude` that logs argv and mimics the two calls
# install.sh makes. `marketplace add` records the name; `marketplace list`
# prints it back in the CLI's shape once recorded; `plugin install` writes the
# installed_plugins.json entry the real CLI writes.
make_claude_stub() {
  cat > "$1/claude" <<'STUB'
#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf '%s\n' "$*" >> "$here/claude.log"
# CLAUDE_STUB_FAIL=install makes `plugin install` fail the way a real CLI error would.
if [ "${CLAUDE_STUB_FAIL:-}" = "install" ] && [ "${1:-} ${2:-}" = "plugin install" ]; then echo "stub: install failed" >&2; exit 7; fi
case "$*" in
  "plugin marketplace add "*)
    touch "$here/marketplace-known"; echo "Successfully added marketplace: jplugin-agentic-development" ;;
  "plugin marketplace list"*)
    if [ -e "$here/marketplace-known" ]; then
      printf '  %s jplugin-agentic-development\n    Source: Directory (%s)\n' "$(printf '\342\235\257')" "$here"
    fi ;;
  "plugin install "*)
    mkdir -p "$HOME/.claude/plugins"
    printf '{"version": 2, "plugins": {"jplugin@jplugin-agentic-development": [{"scope": "user"}]}}\n' \
      > "$HOME/.claude/plugins/installed_plugins.json"
    echo "Successfully installed plugin: jplugin@jplugin-agentic-development" ;;
esac
STUB
  chmod +x "$1/claude"
}

# run_install <confirm> [--with-claude] [install.sh args...]
# Echoes the sandbox path; caller inspects $sandbox/home and $sandbox/out.log.
run_install() {
  local confirm="$1"; shift
  local with_claude=0
  if [ "${1:-}" = "--with-claude" ]; then with_claude=1; shift; fi
  local sandbox home
  sandbox="$(mktemp -d)"
  home="$sandbox/home"
  mkdir -p "$home/.claude/skills/$USER_SKILL" "$sandbox/bin"
  printf 'name: %s\n' "$USER_SKILL" > "$home/.claude/skills/$USER_SKILL/SKILL.md"
  [ "$with_claude" = "1" ] && make_claude_stub "$sandbox/bin"
  # Empty confirm means a closed stdin (true EOF), not a blank line.
  local stdin=/dev/null
  if [ -n "$confirm" ]; then
    stdin="$sandbox/stdin.txt"
    printf '%s\n' "$confirm" > "$stdin"
  fi
  # Run from inside the sandbox: install.sh's optional graphify step writes to CWD.
  ( cd "$sandbox" && HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" PATH="$sandbox/bin:$SAFE_PATH" bash "$INSTALL" "$@" ) \
    > "$sandbox/out.log" 2>&1 < "$stdin"
  echo "exit=$?" >> "$sandbox/out.log"
  printf '%s\n' "$sandbox"
}

# rerun_install <sandbox> <confirm> <logname>: a second run in the same sandbox.
rerun_install() {
  local stdin=/dev/null
  if [ -n "$2" ]; then stdin="$1/stdin2.txt"; printf '%s\n' "$2" > "$stdin"; fi
  ( cd "$1" && HOME="$1/home" CLAUDE_CONFIG_DIR="$1/home/.claude" PATH="$1/bin:$SAFE_PATH" bash "$INSTALL" ) \
    > "$1/$3" 2>&1 < "$stdin"
  echo "exit=$?" >> "$1/$3"
}

exists() { [ -e "$1" ] && echo present || echo missing; }

# ── Case 1: no `claude` on PATH — the plugin step is skipped, nothing touched ─
box="$(run_install "")"
h="$box/home"
assert_contains "$(cat "$box/out.log")" "exit=0" \
  "no claude: install.sh still exits 0"
assert_contains "$(cat "$box/out.log")" "claude CLI not found" \
  "no claude: the skipped plugin step prints a NOTE naming the missing CLI"
assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL/SKILL.md")" \
  "no claude: user's own skill survives installation"
assert_eq "missing" "$(exists "$h/.claude/skills/build/SKILL.md")" \
  "no claude: template skills are no longer copied into ~/.claude/skills/"
assert_eq "missing" "$(exists "$h/.claude/plugins")" \
  "no claude: no plugin state is written without the CLI"
assert_eq "present" "$(exists "$h/.claude/settings.json")" \
  "no claude: settings.json created"
assert_not_contains "$(cat "$h/.claude/settings.json")" '"skills"' \
  "no claude: settings.json contains no invalid 'skills' key"
assert_file_contains "$h/.claude/settings.json" "session-start.sh" \
  "no claude: SessionStart hook still registered"
assert_eq "present" "$(exists "$h/.agents/skills/build/SKILL.md")" \
  "no claude: step 3 still delivers ~/.agents/skills/ for Pi and Codex"
rm -rf "$box"

# ── Case 2: with `claude` — one marketplace add, one install, then `already` ─
box="$(run_install "" --with-claude)"
h="$box/home"
log="$(cat "$box/bin/claude.log")"
assert_eq "1" "$(grep -c "^plugin marketplace add " <<< "$log")" \
  "first run: exactly one 'plugin marketplace add'"
assert_contains "$log" "plugin marketplace add $REPO" \
  "first run: the marketplace source is the checkout directory"
assert_eq "1" "$(grep -c "^plugin install jplugin@jplugin-agentic-development --scope user$" <<< "$log")" \
  "first run: exactly one user-scope plugin install"
assert_eq "missing" "$(exists "$h/.claude/skills/build/SKILL.md")" \
  "first run: no skill copy lands in ~/.claude/skills/"
assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL/SKILL.md")" \
  "first run: user's own skill survives"
assert_contains "$(cat "$box/out.log")" "skills source: plugin" \
  "first run: reports the derived machine state"

: > "$box/bin/claude.log"
rerun_install "$box" "" out2.log
log="$(cat "$box/bin/claude.log")"
assert_eq "0" "$(grep -c "^plugin marketplace add " <<< "$log")" \
  "second run: no second marketplace add"
assert_eq "0" "$(grep -c "^plugin install " <<< "$log")" \
  "second run: no second plugin install"
assert_contains "$(cat "$box/out2.log")" "already" \
  "second run: reports the marketplace and plugin as already present"
rm -rf "$box"

# ── Case 1b: no `claude`, copies present — kept, not even listed, state reported ─
box="$(run_install "")"; h="$box/home"
mkdir -p "$h/.claude/skills/plan" "$h/.claude/skills/tdd"; touch "$h/.claude/skills/plan/SKILL.md" "$h/.claude/skills/tdd/SKILL.md"
rerun_install "$box" "" nocli.log
assert_contains "$(cat "$box/nocli.log")" "skills source: legacy-copy" \
  "no claude, copies present: the derived state is legacy-copy"
assert_not_contains "$(cat "$box/nocli.log")" "Delete them?" \
  "no claude, copies present: the removal prompt is not offered — the copies are all this machine has"
assert_eq "present" "$(exists "$h/.claude/skills/plan")" "no claude, copies present: current template name kept"
assert_eq "present" "$(exists "$h/.claude/skills/tdd")" "no claude, copies present: retired template name kept"
rm -rf "$box"

# ── Case 2b: the CLI failing aborts the run loudly and touches no skill copy ──
box="$(CLAUDE_STUB_FAIL=install run_install "" --with-claude)"; h="$box/home"
assert_contains "$(cat "$box/out.log")" "exit=1" "cli failure: install.sh exits 1"
assert_contains "$(cat "$box/out.log")" "ERROR: 'claude plugin install" "cli failure: the ERROR line names the failed command"
assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL/SKILL.md")" "cli failure: user's own skill untouched"
rm -rf "$box"

# ── Case 3: legacy ~/.claude/skills/ copies — listed, deleted only on y ──────
# Three entries: a name the template never carried, a current template skill and
# a skill retired in template history. Only the last two are candidates (#52).
plant_legacy() {
  mkdir -p "$1/.claude/skills/aws-saml2aws-auth" "$1/.claude/skills/plan" "$1/.claude/skills/tdd"
  touch "$1/.claude/skills/aws-saml2aws-auth/SKILL.md" "$1/.claude/skills/plan/SKILL.md" "$1/.claude/skills/tdd/SKILL.md"
}
for answer in "" "N"; do
  box="$(run_install "" --with-claude)"; h="$box/home"; plant_legacy "$h"
  rerun_install "$box" "$answer" legacy.log
  label="answered '${answer:-EOF}'"
  assert_contains "$(cat "$box/legacy.log")" "plan" \
    "legacy copies ($label): current template name is listed"
  assert_contains "$(cat "$box/legacy.log")" "tdd" \
    "legacy copies ($label): retired template name is listed"
  assert_eq "present" "$(exists "$h/.claude/skills/plan")" \
    "legacy copies ($label): current template name kept"
  assert_eq "present" "$(exists "$h/.claude/skills/tdd")" \
    "legacy copies ($label): retired template name kept"
  assert_eq "present" "$(exists "$h/.claude/skills/aws-saml2aws-auth")" \
    "legacy copies ($label): never-carried name kept"
  assert_contains "$(cat "$box/legacy.log")" "rm -rf" \
    "legacy copies ($label): the manual removal command is printed"
  rm -rf "$box"
done

box="$(run_install "" --with-claude)"; h="$box/home"; plant_legacy "$h"
# A retired template skill copied into ~/.agents/skills/ by an earlier install
# stays beside its replacement for Pi and Codex: named, never deleted.
mkdir -p "$h/.agents/skills/tdd"; touch "$h/.agents/skills/tdd/SKILL.md"
rerun_install "$box" "y" legacy.log
assert_contains "$(cat "$box/legacy.log")" "retired template skills: tdd" \
  "~/.agents/skills/: a retired template skill left there is named"
assert_eq "present" "$(exists "$h/.agents/skills/tdd")" \
  "~/.agents/skills/: ... and never deleted"
assert_eq "missing" "$(exists "$h/.claude/skills/plan")" \
  "legacy copies (answered y): current template name deleted"
assert_eq "missing" "$(exists "$h/.claude/skills/tdd")" \
  "legacy copies (answered y): retired template name deleted"
assert_eq "present" "$(exists "$h/.claude/skills/aws-saml2aws-auth")" \
  "legacy copies (answered y): never-carried name is never a candidate"
assert_eq "present" "$(exists "$h/.claude/skills/$USER_SKILL")" \
  "legacy copies (answered y): user's own skill is never a candidate"
assert_contains "$(cat "$box/legacy.log")" "skills source: plugin" \
  "legacy copies (answered y): state reported as plugin"
rm -rf "$box"

# ── Case 3b: a shallow checkout cannot name retired skills, and says so ───────
box="$(run_install "" --with-claude)"; h="$box/home"; plant_legacy "$h"
git clone -q --depth 1 "file://$REPO" "$box/shallow" 2>/dev/null
( cd "$box" && HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" PATH="$box/bin:$SAFE_PATH" bash "$box/shallow/install.sh" ) \
  > "$box/shallow.log" 2>&1 < /dev/null
assert_contains "$(cat "$box/shallow.log")" "shallow clone" \
  "shallow checkout: the NOTE says retired names are unknown"
assert_contains "$(cat "$box/shallow.log")" "    - plan" \
  "shallow checkout: current template names are still candidates"
assert_not_contains "$(cat "$box/shallow.log")" "    - tdd" \
  "shallow checkout: a retired name is not guessed"
rm -rf "$box"

# ── Case 4: the removed flag is a usage error, not a silent no-op ─────────────
box="$(run_install "" --prune-skills)"
assert_contains "$(cat "$box/out.log")" "exit=1" \
  "--prune-skills: exits 1 now that the flag is gone"
assert_contains "$(cat "$box/out.log")" "Usage:" \
  "--prune-skills: prints the usage text"
rm -rf "$box"

# ── Case 5: unknown flags are rejected, not ignored ──────────────────────────
box="$(mktemp -d)"
( cd "$box" && HOME="$box/home" CLAUDE_CONFIG_DIR="$box/home/.claude" PATH="$SAFE_PATH" bash "$INSTALL" --bogus ) > "$box/out.log" 2>&1 < /dev/null
assert_eq "1" "$?" "unknown flag: exits non-zero instead of installing"
rm -rf "$box"

# ── Case 6: scaffold works from a checkout path with spaces, anywhere on disk ─
# Install via a symlinked checkout whose path contains spaces, with an isolated
# HOME. Nothing may depend on the clone living at ~/jplugin-agentic-development.
box="$(mktemp -d)"
h="$box/home"
mkdir -p "$h"
ln -s "$REPO" "$box/src with spaces"
( cd "$box" && HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" PATH="$SAFE_PATH" bash "$box/src with spaces/install.sh" ) > "$box/out.log" 2>&1 < /dev/null
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
( cd "$box" && HOME="$h" PATH="$SAFE_PATH" bash "$box/src with spaces/install.sh" ) > "$box/out2.log" 2>&1 < /dev/null
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
