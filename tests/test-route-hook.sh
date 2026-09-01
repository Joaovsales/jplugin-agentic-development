#!/usr/bin/env bash
# tests/test-route-hook.sh — issue-shaped prompts deterministically load /route.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/.claude/hooks/user-prompt-route.sh"
SETTINGS="$REPO/.claude/settings.json"

run_hook() {
  local prompt="$1"
  HOOK_OUTPUT=$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1]}))' "$prompt" |
    bash "$HOOK" 2>/dev/null)
  HOOK_STATUS=$?
}

assert_routes() {
  run_hook "$1"
  assert_eq "0" "$HOOK_STATUS" "$2 exits successfully"
  assert_contains "$HOOK_OUTPUT" '"hookEventName":"UserPromptSubmit"' "$2 emits hook context"
  assert_contains "$HOOK_OUTPUT" '/route' "$2 loads /route"
}

assert_routes "Please handle https://github.com/acme/widgets/issues/321" "issue URL"
assert_routes "fix #123" "fix-number shorthand"
assert_routes "#123" "bare issue number"
assert_routes "take the next backlog item" "backlog request"

run_hook "Explain how the release workflow works"
assert_eq "0" "$HOOK_STATUS" "ordinary prompt exits successfully"
assert_eq "" "$HOOK_OUTPUT" "ordinary prompt emits no stdout"

run_hook '{not JSON from the user'
assert_eq "0" "$HOOK_STATUS" "prompt punctuation exits successfully"
assert_eq "" "$HOOK_OUTPUT" "prompt punctuation emits no stdout"

malformed_err="$(mktemp)"
if malformed_out="$(printf '{not-json' | bash "$HOOK" 2>"$malformed_err")"; then
  malformed_status=0
else
  malformed_status=$?
fi
assert_eq "2" "$malformed_status" "malformed hook payload fails loudly"
assert_eq "" "$malformed_out" "malformed hook payload emits no stdout"
assert_contains "$(cat "$malformed_err")" "expected a JSON object with a string prompt" \
  "malformed hook payload names the schema contract"
rm -f "$malformed_err"

if python3 - "$SETTINGS" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))
hooks = settings.get("hooks", {}).get("UserPromptSubmit", [])
commands = [hook.get("command") for group in hooks for hook in group.get("hooks", [])]
raise SystemExit("bash .claude/hooks/user-prompt-route.sh" not in commands)
PY
then
  assert_eq "registered" "registered" "settings register the UserPromptSubmit hook"
else
  assert_eq "registered" "missing" "settings register the UserPromptSubmit hook"
fi

finish
