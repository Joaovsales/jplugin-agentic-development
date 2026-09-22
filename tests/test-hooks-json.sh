#!/bin/bash
# tests/test-hooks-json.sh — the plugin registers the three lifecycle hooks, and
# the registered command strings actually run.
#
# WHY THIS EXISTS
#
# Before hooks/hooks.json the three events were registered in two places at once:
# SessionStart at user level by install.sh, Stop and PreCompact per project by
# .claude/settings.json, which /sync copied into every repository. Each event
# fired once per registration — the checkpoint flush ran twice, and the banner
# needed a session_id guard to print once (specs/single-instruction-file.md
# § Invariants, "Each hook event fires once"). The plugin's hooks.json is now the
# only registration, and .claude/settings.json carries none of the three events
# (tests/test-settings-json.sh pins that half).
#
# The command string is tested, not only the scripts (D20). The scripts' own
# tests run them by path and would never exercise the registration: a quoting
# fault in `bash "${CLAUDE_PLUGIN_ROOT}/…"` shows up only when the root contains
# a space — or, on Windows, backslashes — which is exactly where Claude Code
# installs the plugin cache. Each command runs here through `bash -c`, the way
# Claude Code runs it, with such a root.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

HOOKS_JSON="hooks/hooks.json"

# --- shape ------------------------------------------------------------------
assert_eq "present" "$([ -f "$HOOKS_JSON" ] && echo present || echo missing)" \
  "hooks.json: exists at the plugin root (Claude Code reads hooks/hooks.json beside .claude-plugin/)"

# One Python read answers every structural question; bash then asserts on lines.
shape="$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$HOOKS_JSON" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except ValueError as exc:
    print(f"invalid: {exc}")
    sys.exit(0)
print("valid")
hooks = data.get("hooks")
print("events:", " ".join(sorted(hooks)) if isinstance(hooks, dict) else "<not an object>")
for event in sorted(hooks or {}):
    groups = hooks[event]
    commands = [h.get("command", "") for g in groups for h in g.get("hooks", [])]
    kinds = {h.get("type") for g in groups for h in g.get("hooks", [])}
    print(f"{event}: n={len(commands)} type={','.join(sorted(k or '?' for k in kinds))} command={commands[0] if commands else ''}")
print("top-level:", " ".join(sorted(data)))
PY
)"
assert_contains "$shape" "valid" "hooks.json: is valid JSON"
assert_contains "$shape" "events: PreCompact SessionStart Stop" \
  "hooks.json: registers exactly the three events — SessionStart, PreCompact, Stop"
assert_contains "$shape" "top-level: hooks" \
  "hooks.json: the only top-level key is hooks"

for event in SessionStart PreCompact Stop; do
  line="$(printf '%s\n' "$shape" | grep "^$event: ")"
  assert_contains "$line" "n=1 type=command" \
    "hooks.json: $event registers exactly one command hook"
  assert_contains "$line" 'command=bash "${CLAUDE_PLUGIN_ROOT}/.agents/hooks/' \
    "hooks.json: the $event command starts bash \"\${CLAUDE_PLUGIN_ROOT}/.agents/hooks/"
done

# Each command names a script that exists in the tree it will be resolved from.
# Extracted from the JSON, not retyped: a renamed script must fail here, not in
# every user's next session.
commands="$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$HOOKS_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for event in ("SessionStart", "PreCompact", "Stop"):
    for group in data["hooks"][event]:
        for hook in group["hooks"]:
            print(event + "\t" + hook["command"])
PY
)"
while IFS=$'\t' read -r event command; do
  script="${command#*\$\{CLAUDE_PLUGIN_ROOT\}/}"
  script="${script%\"*}"
  assert_eq "present" "$([ -f "$script" ] && echo present || echo "missing ($script)")" \
    "hooks.json: the $event script exists at $script"
done <<< "$commands"

# --- the command string runs under a spaced, backslashed plugin root (D20) ----
# Claude Code substitutes CLAUDE_PLUGIN_ROOT with the plugin's cache directory
# and hands the string to a shell. The fixture reproduces that: a copy of the
# hook tree under a path with a space, the environment variable set to it, and
# the registered string run through `bash -c` from a project directory.
box="$(mktemp -d)"
plugin_root="$box/plugin root"
mkdir -p "$plugin_root/.agents"
cp -r .agents/hooks "$plugin_root/.agents/hooks"
project="$box/project"
mkdir -p "$project/tasks"
( cd "$project" && git init -q && git config user.email t@t && git config user.name t \
  && printf '[ ] TDD: pending -> later\n' > tasks/todo.md && git add -A && git commit -qm init ) >/dev/null 2>&1

# On Windows the path Claude Code substitutes carries backslashes; Git Bash
# accepts both separators, so the fixture uses them where it can and stays a
# forward-slash path elsewhere.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) root_for_env="$(cygpath -w "$plugin_root" 2>/dev/null || printf '%s' "$plugin_root")" ;;
  *) root_for_env="$plugin_root" ;;
esac
assert_contains "$root_for_env" " " \
  "hooks.json fixture: the plugin root used for the run contains a space (non-vacuity)"

while IFS=$'\t' read -r event command; do
  out="$( cd "$project" \
    && printf '{"session_id":"hooks-json-%s","source":"startup","cwd":"%s"}' "$event" "$project" \
       | CLAUDE_PLUGIN_ROOT="$root_for_env" CCW_SESSION_GUARD=0 SKIP_PRE_COMPACT=0 \
         bash -c "$command" 2>&1 )"
  ec=$?
  assert_eq "0" "$ec" \
    "hooks.json: the $event command exits 0 under a spaced plugin root (output: $(printf '%s' "$out" | head -c 200 | tr '\n' ' '))"
  assert_not_contains "ok:$out" "No such file" \
    "hooks.json: the $event command found its script through the quoted root"
done <<< "$commands"
assert_eq "present" "$([ -f "$project/tasks/checkpoint.md" ] && echo present || echo missing)" \
  "hooks.json: the PreCompact command really ran pre-compact.sh (checkpoint written)"
rm -rf "$box"

# --- the manifest keeps no hooks key: hooks/hooks.json is the registration ----
assert_eq "<missing>" "$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" -c \
  'import json,sys; print(json.load(open(".claude-plugin/plugin.json")).get("hooks", "<missing>"))')" \
  "plugin.json: declares no hooks key — Claude Code discovers hooks/hooks.json by convention"
# A hooks change is a plugin change: the version is what refreshes a project's
# cached copy (specs/single-instruction-file.md § hooks/hooks.json, Versioning).
assert_not_contains "$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" -c \
  'import json; print(json.load(open(".claude-plugin/plugin.json"))["version"])')" "1.0.0" \
  "plugin.json: version bumped past 1.0.0 with the hooks registration"

finish
