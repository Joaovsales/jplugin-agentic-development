#!/bin/bash
# tests/test-pi-overrides-drift.sh — the live Pi settings carry every agent
# PI_SETUP.md pins in `subagents.agentOverrides`.
#
# On Pi, an agent missing from agentOverrides does not inherit: it falls through
# to `subagents.defaultModel`, the Scout tier. tests/test-model-tiers.sh § 11 and
# § 13 pin the documented block, but nothing compared it with the file Pi reads,
# so `test-engineer` ran two tiers below its Reviewer tier with every test green.
# The live file was repaired in the session that added this guard; the guard
# exists to stop the drift recurring. This file compares the two. Both sides are parsed as JSON; the documented side
# is the ```json fence in PI_SETUP.md that holds "agentOverrides".
#
# The live file is per-machine. When it is absent (CI, other machines) the live
# comparison is noted and left out, not `skip`ped — CI sets REQUIRE_ALL=1, which
# fails a file on any skip — and the fixture cases below still prove the guard
# bites. PI_AGENT_SETTINGS points the live case at another file.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
DOC="$(under_test PI_SETUP.md)"
LIVE="${PI_AGENT_SETTINGS:-$HOME/.pi/agent/settings.json}"

# The one reader of the documented block: the ```json fence in PI_SETUP.md that
# holds "agentOverrides", wrapped in braces to parse as an object.
#   check <doc> <settings>       prints each agent the doc pins that the
#                                settings file's subagents.agentOverrides lacks,
#                                one per line; exit 0 none missing, 1 some
#                                missing, 2 either side unparseable
#   fixtures <doc> <full> <bare> writes the documented block as a settings file
#                                to <full>, and without test-engineer to <bare>
PI_OVERRIDES_PY='
import json, re, sys

def documented_settings(doc_path):
    with open(doc_path, encoding="utf-8") as fh:
        text = fh.read()
    fences = [f for f in re.findall(r"```json\n(.*?)```", text, re.S) if "\"agentOverrides\"" in f]
    if len(fences) != 1:
        raise ValueError(f"expected one json fence with agentOverrides in {doc_path}, found {len(fences)}")
    return json.loads("{" + fences[0] + "}")

mode, doc_path = sys.argv[1], sys.argv[2]
try:
    settings = documented_settings(doc_path)
    documented = settings["subagents"]["agentOverrides"]
    if mode == "fixtures":
        for path, drop in ((sys.argv[3], None), (sys.argv[4], "test-engineer")):
            body = {k: v for k, v in documented.items() if k != drop}
            with open(path, "w", encoding="utf-8") as fh:
                json.dump({"subagents": {**settings["subagents"], "agentOverrides": body}}, fh)
        sys.exit(0)
    with open(sys.argv[3], encoding="utf-8") as fh:
        live = json.load(fh).get("subagents", {}).get("agentOverrides", {})
except (OSError, ValueError, KeyError, AttributeError) as exc:
    print(f"unparseable: {exc}")
    sys.exit(2)
missing = sorted(set(documented) - set(live))
print("\n".join(missing))
sys.exit(1 if missing else 0)
'
missing_overrides() { "$TEST_PYTHON" -I -c "$PI_OVERRIDES_PY" check "$1" "$2"; }

FIX="$(fixture_dir)"

# --- 1. The guard bites: a fixture without test-engineer is refused ----------
# The positive control is the documented block itself, written out as a settings
# file; the negative control is the same file with test-engineer removed — the
# exact drift this file exists for.
if begin_case "fixture"; then
  assert_exit 0 "PiDrift: the fixtures are written from the documented block" -- \
    "$TEST_PYTHON" -I -c "$PI_OVERRIDES_PY" fixtures "$DOC" "$FIX/full.json" "$FIX/no-test-engineer.json"
  run missing_overrides "$DOC" "$FIX/full.json"
  assert_exit 0 "PiDrift: the documented block satisfies itself"
  run missing_overrides "$DOC" "$FIX/no-test-engineer.json"
  assert_exit 1 "PiDrift: a settings file missing test-engineer is refused"
  assert_eq "test-engineer" "$output" "PiDrift: the refusal names test-engineer and nothing else"
fi; end_case

# --- 2. The live user-scope settings carry every documented override ---------
if begin_case "live"; then
  if [ -f "$LIVE" ]; then
    run missing_overrides "$DOC" "$LIVE"
    assert_exit 0 "PiDrift: $LIVE carries every agentOverrides entry PI_SETUP.md pins"
  else
    printf '  NOTE live check not run: %s absent (Pi not configured on this machine)\n' "$LIVE"
  fi
fi; end_case

finish
