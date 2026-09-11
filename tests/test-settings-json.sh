# tests/test-settings-json.sh — P1 settings.json registers the PreCompact hook.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$REPO/.claude/settings.json"

# Valid JSON.
if command -v jq >/dev/null 2>&1; then
  jq . "$SETTINGS" >/dev/null 2>&1
  assert_eq "0" "$?" "P1: settings.json is valid JSON"
  cmd=$(jq -r '.hooks.PreCompact[0].hooks[0].command // ""' "$SETTINGS" 2>/dev/null)
  assert_eq "bash .claude/hooks/pre-compact.sh" "$cmd" "P1: PreCompact hook wired to pre-compact.sh"
else
  assert_file_contains "$SETTINGS" "PreCompact" "P1: settings.json references PreCompact (jq absent)"
  assert_file_contains "$SETTINGS" "pre-compact.sh" "P1: settings.json references pre-compact.sh (jq absent)"
fi

# --- Bulk-read gate: PreToolUse on every read surface, project-level only ----
# Spec: specs/bulk-read-gate.md AC2. The gate must cover the Read tool and both
# shells, and it must run the one shared script — a matcher that misses a shell
# leaves `cat big-file` as an ungated bulk read on that harness. Registered here
# and NOT in ~/.claude/settings.json (install.sh), following the Stop/PreCompact
# precedent: a hook registered at both levels fires twice per call.
if command -v jq >/dev/null 2>&1; then
  for tool in Read Bash PowerShell; do
    cmds=$(jq -r --arg t "$tool" \
      '[.hooks.PreToolUse[]? | select((.matcher // "") | split("|") | index($t)) | .hooks[].command] | .[]' \
      "$SETTINGS" 2>/dev/null)
    assert_contains "$cmds" "bash .claude/hooks/bulk-read-gate.sh" \
      "BulkReadGate: PreToolUse matcher covers $tool and runs the bulk-read-gate.sh shim"
  done
  # The shim, not the .py, is registered: it resolves python3-then-python the way
  # install-codex.sh does, so a python-only host still runs the gate instead of
  # a non-blocking hook error that degrades to allow.
  assert_file_contains "$REPO/.claude/hooks/bulk-read-gate.sh" 'bulk-read-gate.py' \
    "BulkReadGate: the shim runs bulk-read-gate.py"
  assert_file_contains "$REPO/.claude/hooks/bulk-read-gate.sh" 'command -v python3' \
    "BulkReadGate: the shim resolves python3 first"
  assert_file_contains "$REPO/.claude/hooks/bulk-read-gate.sh" 'command -v python ' \
    "BulkReadGate: the shim falls back to python"
  stop_cmd=$(jq -r '.hooks.Stop[0].hooks[0].command // ""' "$SETTINGS" 2>/dev/null)
  assert_eq "bash .claude/hooks/session-stop.sh" "$stop_cmd" "BulkReadGate: Stop hook untouched"
else
  assert_file_contains "$SETTINGS" "PreToolUse" "BulkReadGate: settings.json registers PreToolUse (jq absent)"
  assert_file_contains "$SETTINGS" "bulk-read-gate.sh" "BulkReadGate: settings.json runs the bulk-read-gate.sh shim (jq absent)"
fi
# A registration would appear as a jq path or a JSON key; prose mentioning the
# event (install.sh's graphify note does) is not one.
assert_file_not_matches "$REPO/install.sh" '[.]hooks[.]PreToolUse|"PreToolUse"' \
  "BulkReadGate: install.sh registers no PreToolUse hook user-level (would double-fire)"

finish
