#!/bin/bash
# Shared design sources are installed once per user, then read offline.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
box="$(fixture_dir)"
mkdir -p "$box/home" "$box/project" "$box/upstreams"

make_source() {
  local name="$1" marker="$2" path="$box/upstreams/$1"
  mkdir -p "$path/$(dirname "$marker")"
  printf 'fixture %s\n' "$name" > "$path/$marker"
  cp -a "$(fixture_repo)/.git" "$path/"
  git -C "$path" add .
  git -C "$path" commit -qm initial
}

make_source taste skills/taste/SKILL.md
make_source impeccable .agent/skills/impeccable/SKILL.md
make_source references design-md/example/DESIGN.md
make_source three SKILL.md
make_source hyperframes skills/hyperframes/SKILL.md

export HOME="$box/home" DESIGN_STACK_HOME="$box/home/.local/share/jplugin/design-stack"
export DESIGN_STACK_TASTE_URL="$box/upstreams/taste"
export DESIGN_STACK_IMPECCABLE_URL="$box/upstreams/impeccable"
export DESIGN_STACK_REFERENCES_URL="$box/upstreams/references"
export DESIGN_STACK_THREE_URL="$box/upstreams/three"
export DESIGN_STACK_HYPERFRAMES_URL="$box/upstreams/hyperframes"
export DESIGN_STACK_INSTALL_LOG="$box/install.log"
cat > "$box/npx" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$DESIGN_STACK_INSTALL_LOG"
[ "$HOME" != "$DESIGN_STACK_HOME" ] || exit 40
if [ -n "${DESIGN_STACK_INSTALL_SLEEP:-}" ]; then sleep "$DESIGN_STACK_INSTALL_SLEEP"; fi
[ -z "${DESIGN_STACK_NO_INSTALL_OUTPUT:-}" ] || exit 0
case "$*" in
  *'skills add'*) target="$HOME/.agents/skills/taste/SKILL.md" ;;
  *'impeccable install'*) target="$HOME/.agent/skills/impeccable/SKILL.md" ;;
  *) exit 41 ;;
esac
mkdir -p "$(dirname "$target")"
printf 'installed\n' > "$target"
SH
chmod +x "$box/npx"
export DESIGN_STACK_NPX="$box/npx"
CLI="$(under_test .agents/skills/design-stack/scripts)/design_stack.py"

in_project() { ( cd "$box/project" && "$@" ); }
current() { "$TEST_PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["current"])' "$DESIGN_STACK_HOME/manifest.json"; }

# A post-checkout hook from a template dir records the environment each clone ran
# under; GIT_TRACE records its arguments (a local clone ignores --depth on disk).
mkdir -p "$box/template/hooks"
cat > "$box/template/hooks/post-checkout" <<'SH'
#!/bin/sh
printf '%s lfs=%s\n' "$(basename "$PWD")" "${GIT_LFS_SKIP_SMUDGE:-unset}" >> "$DESIGN_STACK_CLONE_LOG"
SH
chmod +x "$box/template/hooks/post-checkout"
export GIT_TEMPLATE_DIR="$box/template" DESIGN_STACK_CLONE_LOG="$box/clone.log" GIT_TRACE="$box/git-trace.log"

printf '\n--- first setup and offline reuse ---\n'
run in_project "$TEST_PYTHON" "$CLI" setup
assert_exit 0 "setup succeeds from five local official-source fixtures"
assert_contains "$output" 'Ready' "setup reports readiness"
assert_file_contains "$DESIGN_STACK_HOME/manifest.json" '"schema_version": 1' "manifest is versioned"
assert_file_contains "$DESIGN_STACK_INSTALL_LOG" 'skills add' "Taste official installer was invoked"
assert_file_contains "$DESIGN_STACK_INSTALL_LOG" 'impeccable install' "Impeccable official installer was invoked"
assert_file_absent "$box/project/.agents" "installers write no project payload"
unset GIT_TEMPLATE_DIR GIT_TRACE
printf '\n--- hyperframes source ---\n'
clones="$(grep 'built-in: git clone' "$box/git-trace.log")"
assert_eq 5 "$(printf '%s\n' "$clones" | wc -l | tr -d ' ')" "setup clones five sources"
assert_eq 1 "$(printf '%s\n' "$clones" | grep -c -- '--depth 1')" "exactly one clone is shallow"
assert_contains "$(printf '%s\n' "$clones" | grep -- '--depth 1')" 'upstreams/hyperframes' "the shallow clone is hyperframes"
assert_eq 1 "$(grep -c 'lfs=1' "$box/clone.log")" "exactly one clone skips the LFS smudge"
assert_file_contains "$box/clone.log" 'hyperframes lfs=1' "the hyperframes clone skips the LFS smudge"
assert_file_contains "$box/clone.log" 'taste lfs=unset' "the other clones keep the inherited environment"
assert_file_contains "$DESIGN_STACK_HOME/manifest.json" '"hyperframes"' "hyperframes revision recorded in the manifest"
calls_before="$(wc -l < "$DESIGN_STACK_INSTALL_LOG")"
export DESIGN_STACK_TASTE_URL="$box/missing-taste"
run in_project "$TEST_PYTHON" "$CLI" status
assert_exit 0 "status reads verified release offline"
assert_eq "$calls_before" "$(wc -l < "$DESIGN_STACK_INSTALL_LOG")" "status invokes no installer"
release="$DESIGN_STACK_HOME/releases/$(current)"
for name in taste impeccable references three hyperframes; do
  assert_file_contains "$DESIGN_STACK_HOME/manifest.json" "\"$name\"" "$name revision recorded"
  assert_true "$name is available in the verified release" -- test -d "$release/sources/$name"
done
assert_eq 0 "$(find "$box/project" -mindepth 1 | wc -l | tr -d ' ')" "project receives no upstream repository"

# A second normal run has no reason to contact any source.
export DESIGN_STACK_TASTE_URL="$box/missing-taste"
run in_project "$TEST_PYTHON" "$CLI" setup
assert_exit 0 "second setup works offline"
assert_eq "$(basename "$release")" "$(current)" "offline setup retains the release"

printf '\n--- explicit update, failure rollback, and no-op ---\n'
export DESIGN_STACK_TASTE_URL="$box/upstreams/taste"
before="$(current)"
calls_before="$(wc -l < "$DESIGN_STACK_INSTALL_LOG")"
run "$TEST_PYTHON" "$CLI" update
assert_exit 0 "same-revision update succeeds"
assert_contains "$output" 'unchanged' "same-revision update is a no-op"
assert_eq "$before" "$(current)" "same-revision update preserves the pointer"
assert_eq "$calls_before" "$(wc -l < "$DESIGN_STACK_INSTALL_LOG")" "same-revision update skips installers"

printf 'changed\n' >> "$box/upstreams/taste/skills/taste/SKILL.md"
git -C "$box/upstreams/taste" add .
git -C "$box/upstreams/taste" -c user.name=Test -c user.email=test@example.invalid commit -qm second
export DESIGN_STACK_TASTE_URL="$box/missing-taste"
run "$TEST_PYTHON" "$CLI" update
assert_exit 1 "failed update is reported"
assert_contains "$output" 'UpdateRejected' "failed update has a named outcome"
assert_eq "$before" "$(current)" "failed update preserves the pointer"
assert_file_contains "$release/sources/taste/skills/taste/SKILL.md" 'fixture taste' "old command remains readable"

export DESIGN_STACK_TASTE_URL="$box/upstreams/taste"
mv "$box/upstreams/references/design-md/example/DESIGN.md" "$box/upstreams/references/design-md/example/GONE.md"
git -C "$box/upstreams/references" add -A
git -C "$box/upstreams/references" -c user.name=Test -c user.email=test@example.invalid commit -qm invalid
run "$TEST_PYTHON" "$CLI" update
assert_exit 1 "invalid staged catalog is rejected"
assert_contains "$output" 'UpdateRejected' "validation failure is named"
assert_eq "$before" "$(current)" "validation failure preserves prior release"
mv "$box/upstreams/references/design-md/example/GONE.md" "$box/upstreams/references/design-md/example/DESIGN.md"
git -C "$box/upstreams/references" add -A
git -C "$box/upstreams/references" -c user.name=Test -c user.email=test@example.invalid commit -qm repaired

export DESIGN_STACK_NO_INSTALL_OUTPUT=1
run "$TEST_PYTHON" "$CLI" update
assert_exit 1 "no-op installer rejects the candidate"
assert_contains "$output" 'UpdateRejected' "missing installed entrypoint is named"
assert_eq "$before" "$(current)" "no-op installer preserves prior release"
unset DESIGN_STACK_NO_INSTALL_OUTPUT

export DESIGN_STACK_INSTALL_SLEEP=1 DESIGN_STACK_TIMEOUT=0.2
run "$TEST_PYTHON" "$CLI" update
assert_exit 1 "installer timeout rejects update"
assert_contains "$output" 'UpdateRejected' "timeout has a named outcome"
assert_eq "$before" "$(current)" "timeout preserves prior release"
unset DESIGN_STACK_INSTALL_SLEEP DESIGN_STACK_TIMEOUT

run "$TEST_PYTHON" "$CLI" update
assert_exit 0 "valid update succeeds"
assert_contains "$output" 'Ready' "successful update reports readiness"
assert_true "successful update switches release" -- test "$before" != "$(current)"
assert_file_contains "$DESIGN_STACK_HOME/releases/$(current)/sources/taste/skills/taste/SKILL.md" 'changed' "new content is available"

printf '\n--- executable resolution ---\n'
# Windows resolves `npx` to npx.cmd only through PATHEXT, which subprocess
# without a shell ignores; run() must hand subprocess the which() result.
executable_resolution() {
"$TEST_PYTHON" - "$(dirname "$CLI")" <<'PY'
import shutil, subprocess, sys
sys.path.insert(0, sys.argv[1])
import design_stack
shutil.which = lambda name: {"npx": "C:/nodejs/npx.cmd"}.get(name)
seen = []
subprocess.run = lambda command, **_: seen.append(command) or subprocess.CompletedProcess(command, 0, "")
design_stack.run("npx", "--yes")
design_stack.run("unresolvable", "--yes")
print(seen)
PY
}
run executable_resolution
assert_contains "$output" "('C:/nodejs/npx.cmd', '--yes')" "run resolves a bare command through PATH and PATHEXT"
assert_contains "$output" "('unresolvable', '--yes')" "an unresolvable command keeps its name so the error stays explicit"

printf '\n--- distribution ---\n'
assert_file_contains "$REPO/README.md" '/design-stack' "README names the adapter"
assert_eq 0 "$(find "$REPO/.agents/skills/design-stack" -type d -name .git | wc -l | tr -d ' ')" "adapter does not vendor upstream repositories"
assert_eq 0 "$(git -C "$REPO" diff --name-only HEAD -- .agents/skills/visual-plan .agents/skills/visual-recap | wc -l | tr -d ' ')" "visual renderer diff stays empty"
finish
