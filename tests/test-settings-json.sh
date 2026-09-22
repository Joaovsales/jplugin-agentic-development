# tests/test-settings-json.sh — .claude/settings.json registers none of the
# three lifecycle events; hooks/hooks.json is their only registration.
#
# Before specs/single-instruction-file.md slice 3, this file registered Stop and
# PreCompact per project while the plugin was about to register them too. Hooks
# from every source merge and all run, so a project carrying both would flush
# its checkpoint twice per compaction. The template's file is pinned clean here;
# a downstream copy still carrying `bash .claude/hooks/<name>.sh` entries is
# cleaned by the /sync Step 5 settings merge (D16, pinned by
# tests/test-sync-settings-merge.sh).
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$REPO/.claude/settings.json"

report="$(PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" - "$SETTINGS" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except ValueError as exc:
    print(f"invalid: {exc}")
    sys.exit(0)
print("valid")
hooks = data.get("hooks", {})
for event in ("SessionStart", "PreCompact", "Stop"):
    print(f"{event}: {'registered' if event in hooks else 'absent'}")
print("hooks-key:", "present" if "hooks" in data else "absent")
print("env:", "present" if isinstance(data.get("env"), dict) and data["env"] else "absent")
print("plugin:", data.get("enabledPlugins", {}).get("jplugin@jplugin-agentic-development"))
PY
)"
assert_contains "$report" "valid" "settings.json: is valid JSON"
for event in SessionStart PreCompact Stop; do
  assert_contains "$report" "$event: absent" \
    "settings.json: registers no $event — hooks/hooks.json is the only registration"
done
# No empty `hooks: {}` left behind either: a key with nothing in it invites the
# next contributor to put something back.
assert_contains "$report" "hooks-key: absent" \
  "settings.json: carries no hooks key at all"
# Non-vacuity: the file still carries what it is for.
assert_contains "$report" "env: present" \
  "settings.json: the env block survives"
assert_contains "$report" "plugin: True" \
  "settings.json: the plugin declaration survives"

finish
