#!/bin/bash
# Shared design sources are installed once per user, then read offline.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
mkdir -p "$box/home" "$box/project" "$box/upstreams"

make_source() {
  local name="$1" marker="$2" path="$box/upstreams/$1"
  mkdir -p "$path/$(dirname "$marker")"
  printf 'fixture %s\n' "$name" > "$path/$marker"
  git -C "$path" init -q
  git -C "$path" add .
  git -C "$path" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
}

make_source taste skills/taste/SKILL.md
make_source impeccable .agent/skills/impeccable/SKILL.md
make_source references design-md/example/DESIGN.md
make_source three SKILL.md

export HOME="$box/home" DESIGN_STACK_HOME="$box/home/.local/share/jplugin/design-stack"
export DESIGN_STACK_TASTE_URL="$box/upstreams/taste"
export DESIGN_STACK_IMPECCABLE_URL="$box/upstreams/impeccable"
export DESIGN_STACK_REFERENCES_URL="$box/upstreams/references"
export DESIGN_STACK_THREE_URL="$box/upstreams/three"
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
CLI="$REPO/.agents/skills/design-stack/scripts/design_stack.py"

run_cli() { "$TEST_PYTHON" "$CLI" "$@" 2>&1; }
current() { "$TEST_PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["current"])' "$DESIGN_STACK_HOME/manifest.json"; }

printf '\n--- first setup and offline reuse ---\n'
out="$(cd "$box/project" && run_cli setup)"; code=$?
assert_eq 0 "$code" "setup succeeds from four local official-source fixtures"
assert_contains "$out" 'Ready' "setup reports readiness"
assert_file_contains "$DESIGN_STACK_HOME/manifest.json" '"schema_version": 1' "manifest is versioned"
assert_file_contains "$DESIGN_STACK_INSTALL_LOG" 'skills add' "Taste official installer was invoked"
assert_file_contains "$DESIGN_STACK_INSTALL_LOG" 'impeccable install' "Impeccable official installer was invoked"
assert_eq 0 "$([ ! -d "$box/project/.agents" ]; echo $?)" "installers write no project payload"
calls_before="$(wc -l < "$DESIGN_STACK_INSTALL_LOG")"
export DESIGN_STACK_TASTE_URL="$box/missing-taste"
out="$(cd "$box/project" && run_cli status)"; code=$?
assert_eq 0 "$code" "status reads verified release offline"
assert_eq "$calls_before" "$(wc -l < "$DESIGN_STACK_INSTALL_LOG")" "status invokes no installer"
release="$DESIGN_STACK_HOME/releases/$(current)"
for name in taste impeccable references three; do
  assert_file_contains "$DESIGN_STACK_HOME/manifest.json" "\"$name\"" "$name revision recorded"
  [ -d "$release/sources/$name" ]
  assert_eq 0 "$?" "$name is available in the verified release"
done
assert_eq 0 "$(find "$box/project" -mindepth 1 | wc -l | tr -d ' ')" "project receives no upstream repository"

# A second normal run has no reason to contact any source.
export DESIGN_STACK_TASTE_URL="$box/missing-taste"
out="$(cd "$box/project" && run_cli setup)"; code=$?
assert_eq 0 "$code" "second setup works offline"
assert_eq "$(basename "$release")" "$(current)" "offline setup retains the release"

printf '\n--- explicit update, failure rollback, and no-op ---\n'
export DESIGN_STACK_TASTE_URL="$box/upstreams/taste"
before="$(current)"
calls_before="$(wc -l < "$DESIGN_STACK_INSTALL_LOG")"
out="$(run_cli update)"; code=$?
assert_eq 0 "$code" "same-revision update succeeds"
assert_contains "$out" 'unchanged' "same-revision update is a no-op"
assert_eq "$before" "$(current)" "same-revision update preserves the pointer"
assert_eq "$calls_before" "$(wc -l < "$DESIGN_STACK_INSTALL_LOG")" "same-revision update skips installers"

printf 'changed\n' >> "$box/upstreams/taste/skills/taste/SKILL.md"
git -C "$box/upstreams/taste" add .
git -C "$box/upstreams/taste" -c user.name=Test -c user.email=test@example.invalid commit -qm second
export DESIGN_STACK_TASTE_URL="$box/missing-taste"
out="$(run_cli update)"; code=$?
assert_eq 1 "$code" "failed update is reported"
assert_contains "$out" 'UpdateRejected' "failed update has a named outcome"
assert_eq "$before" "$(current)" "failed update preserves the pointer"
assert_file_contains "$release/sources/taste/skills/taste/SKILL.md" 'fixture taste' "old command remains readable"

export DESIGN_STACK_TASTE_URL="$box/upstreams/taste"
mv "$box/upstreams/references/design-md/example/DESIGN.md" "$box/upstreams/references/design-md/example/GONE.md"
git -C "$box/upstreams/references" add -A
git -C "$box/upstreams/references" -c user.name=Test -c user.email=test@example.invalid commit -qm invalid
out="$(run_cli update)"; code=$?
assert_eq 1 "$code" "invalid staged catalog is rejected"
assert_contains "$out" 'UpdateRejected' "validation failure is named"
assert_eq "$before" "$(current)" "validation failure preserves prior release"
mv "$box/upstreams/references/design-md/example/GONE.md" "$box/upstreams/references/design-md/example/DESIGN.md"
git -C "$box/upstreams/references" add -A
git -C "$box/upstreams/references" -c user.name=Test -c user.email=test@example.invalid commit -qm repaired

export DESIGN_STACK_NO_INSTALL_OUTPUT=1
out="$(run_cli update)"; code=$?
assert_eq 1 "$code" "no-op installer rejects the candidate"
assert_contains "$out" 'UpdateRejected' "missing installed entrypoint is named"
assert_eq "$before" "$(current)" "no-op installer preserves prior release"
unset DESIGN_STACK_NO_INSTALL_OUTPUT

export DESIGN_STACK_INSTALL_SLEEP=1 DESIGN_STACK_TIMEOUT=0.2
out="$(run_cli update)"; code=$?
assert_eq 1 "$code" "installer timeout rejects update"
assert_contains "$out" 'UpdateRejected' "timeout has a named outcome"
assert_eq "$before" "$(current)" "timeout preserves prior release"
unset DESIGN_STACK_INSTALL_SLEEP DESIGN_STACK_TIMEOUT

out="$(run_cli update)"; code=$?
assert_eq 0 "$code" "valid update succeeds"
assert_contains "$out" 'Ready' "successful update reports readiness"
assert_eq 0 "$([ "$before" != "$(current)" ]; echo $?)" "successful update switches release"
assert_file_contains "$DESIGN_STACK_HOME/releases/$(current)/sources/taste/skills/taste/SKILL.md" 'changed' "new content is available"

printf '\n--- executable resolution ---\n'
# Windows resolves `npx` to npx.cmd only through PATHEXT, which subprocess
# without a shell ignores; run() must hand subprocess the which() result.
out="$("$TEST_PYTHON" - "$(dirname "$CLI")" <<'PY' 2>&1
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
)"
assert_contains "$out" "('C:/nodejs/npx.cmd', '--yes')" "run resolves a bare command through PATH and PATHEXT"
assert_contains "$out" "('unresolvable', '--yes')" "an unresolvable command keeps its name so the error stays explicit"

printf '\n--- distribution ---\n'
assert_file_contains "$REPO/README.md" '/design-stack' "README names the adapter"
assert_eq 0 "$(find "$REPO/.agents/skills/design-stack" -type d -name .git | wc -l | tr -d ' ')" "adapter does not vendor upstream repositories"
assert_eq 0 "$(git -C "$REPO" diff --name-only HEAD -- .agents/skills/visual-plan .agents/skills/visual-recap | wc -l | tr -d ' ')" "visual renderer diff stays empty"
finish
