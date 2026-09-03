#!/usr/bin/env bash
# Route issue-shaped prompts before model-level skill selection can skip them.

python3 -c '
import json
import re
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    print("route hook: expected a JSON object with a string prompt", file=sys.stderr)
    raise SystemExit(2)

if not isinstance(payload, dict) or not isinstance(payload.get("prompt"), str):
    print("route hook: expected a JSON object with a string prompt", file=sys.stderr)
    raise SystemExit(2)
prompt = payload["prompt"]

issue_url = re.search(r"https?://\S+/issues/\d+\b", prompt, re.IGNORECASE)
issue_number = re.search(r"(?<![\w#])#\d+\b", prompt)
next_backlog = re.search(r"\btake the next backlog item\b", prompt, re.IGNORECASE)
if not (issue_url or issue_number or next_backlog):
    raise SystemExit(0)

output = {
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": (
            "This is an issue-shaped request. The installed project workflow means "
            "the user requested routing: invoke /route before editing source files."
        ),
    }
}
print(json.dumps(output, separators=(",", ":")))
'
