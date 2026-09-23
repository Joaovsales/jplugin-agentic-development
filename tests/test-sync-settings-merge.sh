#!/bin/bash
# tests/test-sync-settings-merge.sh — the /sync Step 5 settings merge drops a
# downstream hook entry that points at a retired .claude/hooks/ script (D16).
#
# WHY THIS EXISTS
#
# Slice 3 of specs/single-instruction-file.md moved the lifecycle scripts to
# .agents/hooks/ and registered them once, in the plugin's hooks/hooks.json. A
# project synced before that still carries `bash .claude/hooks/session-stop.sh`
# and `bash .claude/hooks/pre-compact.sh` in its own .claude/settings.json. Hooks
# from every source merge and all run, so after the plugin refreshes such a
# project flushes its checkpoint twice per compaction — and once Step 6.4 retires
# the scripts, the entries run files that no longer exist on every Stop. The same
# /sync that retires the scripts has to remove the entries, in the same approved
# run, or the two states are never consistent.
#
# The merge is the Python snippet /sync's Step 5 documents inline, so the test
# extracts that snippet from the canonical SKILL.md and runs it: the documented
# command is the one under test, not a copy of it.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SYNC=".agents/skills/sync/SKILL.md"

# The heredoc body between `python3 - "$(git show …settings.json)" <<'PY'` and the
# closing `PY`, exactly as the skill prints it.
snippet="$(awk 'index($0, "settings.json") && index($0, "<<'"'"'PY'"'"'") { p = 1; next }
                p && $0 == "PY" { exit }
                p' "$SYNC")"
assert_contains "$snippet" 'settings = json.load(open(path, encoding="utf-8"))' \
  "Step 5 merge: the snippet was extracted from SKILL.md (non-vacuity)"
assert_contains "$snippet" '.claude/hooks/' \
  "Step 5 merge: the snippet names the retired hooks path it removes"

TEMPLATE_JSON='{"extraKnownMarketplaces": {"jplugin-agentic-development": {"source": {"source": "github", "repo": "Joaovsales/jplugin-agentic-development"}}}, "enabledPlugins": {"jplugin@jplugin-agentic-development": true}}'

box="$(mktemp -d)"
mkdir -p "$box/.claude"
# A downstream file as the pre-slice-3 /sync left it, plus the project's own
# additions: a SessionStart hook of its own, a permissions block, an env block.
PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$box/.claude/settings.json" <<'PY'
import json, sys
settings = {
    "permissions": {"allow": ["Bash(npm test:*)"]},
    "hooks": {
        "SessionStart": [{"hooks": [{"type": "command", "command": "bash scripts/own-session-hook.sh"}]}],
        "Stop": [
            {"hooks": [{"type": "command", "command": "bash .claude/hooks/session-stop.sh"}]},
            {"hooks": [{"type": "command", "command": "bash .claude/hooks/lint.sh"}]},
        ],
        "PreCompact": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/pre-compact.sh"}]}],
    },
    "env": {"CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000", "MY_FLAG": "1"},
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
cp "$box/.claude/settings.json" "$box/before.json"

run_merge() {  # run_merge -> exit code; runs the documented snippet in the fixture
  ( cd "$box" && printf '%s\n' "$snippet" | PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$TEMPLATE_JSON" )
}
run_merge
assert_eq "0" "$?" "Step 5 merge: the snippet exits 0 on the downstream fixture"

report="$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$box/before.json" "$box/.claude/settings.json" <<'PY'
import json, sys
before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))
hooks = after.get("hooks", {})
print("Stop:", ",".join(h["command"] for g in hooks.get("Stop", []) for h in g["hooks"]) or "absent")
print("PreCompact:", "present" if "PreCompact" in hooks else "absent")
own = [h["command"] for g in hooks.get("SessionStart", []) for h in g["hooks"]]
print("SessionStart:", ",".join(own) or "absent")
import re
print("retired-template:", "present" if re.search(r"\.claude/hooks/(session-start|pre-compact|session-stop)\.sh", json.dumps(after)) else "absent")
for key in before:
    if key == "hooks":
        continue
    same = json.dumps(before[key], indent=2, ensure_ascii=False) == json.dumps(after.get(key), indent=2, ensure_ascii=False)
    print(f"{key}: {'identical' if same else 'CHANGED'}")
print("plugin:", after.get("enabledPlugins", {}).get("jplugin@jplugin-agentic-development"))
print("order:", ",".join(after))
PY
)"
assert_contains "$report" "Stop: bash .claude/hooks/lint.sh" \
  "Step 5 merge: the Stop entry pointing at .claude/hooks/session-stop.sh is gone; the project's own .claude/hooks/lint.sh entry survives"
assert_contains "$report" "PreCompact: absent" \
  "Step 5 merge: the PreCompact entry pointing at .claude/hooks/pre-compact.sh is gone"
assert_contains "$report" "retired-template: absent" \
  "Step 5 merge: nothing in the file names one of the three retired template scripts any more"
assert_contains "$report" "SessionStart: bash scripts/own-session-hook.sh" \
  "Step 5 merge: the project's own hook entry survives — only retired-path entries are dropped"
assert_contains "$report" "permissions: identical" \
  "Step 5 merge: the permissions block is byte-identical"
assert_contains "$report" "env: identical" \
  "Step 5 merge: the env block is byte-identical"
assert_contains "$report" "plugin: True" \
  "Step 5 merge: the plugin declaration is merged in the same run"
assert_contains "$report" "order: permissions,hooks,env,extraKnownMarketplaces,enabledPlugins" \
  "Step 5 merge: existing keys keep their order; the declaration is appended"

# Idempotent: a second run changes nothing.
cp "$box/.claude/settings.json" "$box/once.json"
run_merge
assert_files_identical "$box/once.json" "$box/.claude/settings.json" \
  "Step 5 merge: a second run leaves the file byte-identical"

# A file whose only hooks were the retired ones ends with no hooks key at all.
PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$box/.claude/settings.json" <<'PY'
import json, sys
settings = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash .claude/hooks/session-stop.sh"}]}]}}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
run_merge
assert_eq "absent" "$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" -c \
  'import json,sys; print("present" if "hooks" in json.load(open(sys.argv[1])) else "absent")' "$box/.claude/settings.json")" \
  "Step 5 merge: no empty hooks object is left behind"

# A file with no hooks key at all is left without one — the merge adds nothing.
printf '{"env": {"A": "1"}}\n' > "$box/.claude/settings.json"
run_merge
assert_eq "absent" "$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" -c \
  'import json,sys; print("present" if "hooks" in json.load(open(sys.argv[1])) else "absent")' "$box/.claude/settings.json")" \
  "Step 5 merge: a file without hooks gains none"

rm -rf "$box"
finish
