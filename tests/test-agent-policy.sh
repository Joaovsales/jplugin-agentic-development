#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$REPO/scripts/agent-policy"
FIXTURES="$REPO/tests/fixtures/agent-policy"

assert_exit() {
  expected="$1"; label="$2"; shift 2
  output="$("$@" 2>&1)"; status=$?
  assert_eq "$expected" "$status" "$label: exit status"
}

assert_exit 0 "explorer route" "$TEST_PYTHON" "$POLICY" explain --harness codex --role explorer
assert_contains "$output" '"tier": "Scout"' "explorer: semantic tier"
assert_contains "$output" '"model": "gpt-6-luna"' "explorer: provider model"
assert_contains "$output" '"permission": "read-only"' "explorer: permission intent"
assert_contains "$output" '"max_children": 3' "explorer: supported child limit"
assert_contains "$output" '"trace"' "explorer: route explanation"

for agent_file in "$REPO"/.agents/agents/*.md; do
  [ "${agent_file##*/}" = README.md ] && continue
  agent="${agent_file##*/}"; agent="${agent%.md}"
  assert_exit 0 "$agent route" "$TEST_PYTHON" "$POLICY" explain --harness codex --role "$agent"
  assert_contains "$output" '"tier":' "$agent: tier explained"
  assert_contains "$output" '"permission":' "$agent: permission explained"
done

assert_exit 0 "critic inheritance" "$TEST_PYTHON" "$POLICY" explain --harness codex --role critic --parent-model gpt-6-astra
assert_contains "$output" '"inherit_model": true' "critic: inherits sufficient parent"
assert_contains "$output" '"model": "gpt-6-astra"' "critic: effective parent model"

for parent in gpt-6-luna gpt-6.1-sol; do
  assert_exit 0 "debug escalation from $parent" "$TEST_PYTHON" "$POLICY" explain --harness codex --lane debug-escalation --parent-model "$parent"
  assert_contains "$output" '"model": "gpt-6-astra"' "debug escalation: Planner mapping above $parent"
  assert_contains "$output" '"effort": "high"' "debug escalation: Planner effort above $parent"
  assert_contains "$output" '"inherit_model": false' "debug escalation: explicit stronger model above $parent"
done
assert_exit 0 "debug escalation above Builder" "$TEST_PYTHON" "$POLICY" explain --harness codex --lane debug-escalation --parent-model gpt-6-astra
assert_contains "$output" '"inherit_model": true' "debug escalation: stronger parent inherited"
assert_exit 0 "debug escalation unknown parent" "$TEST_PYTHON" "$POLICY" explain --harness codex --lane debug-escalation --parent-model unknown-model
assert_contains "$output" '"model": null' "debug escalation: unknown parent has no claimed model"
assert_contains "$output" '"unresolved": true' "debug escalation: unknown parent is unresolved"

assert_exit 0 "lane selection" "$TEST_PYTHON" "$POLICY" explain --harness codex --lane how-explore
assert_contains "$output" '"role": "explorer"' "lane: selected role"
assert_exit 2 "unknown lane" "$TEST_PYTHON" "$POLICY" explain --harness codex --lane missing
assert_contains "$output" 'unknown lane' "unknown lane: actionable error"
assert_exit 2 "mismatched lane and role" "$TEST_PYTHON" "$POLICY" explain --harness codex --lane how-explore --role scout
assert_contains "$output" 'selects role explorer' "lane conflict: actionable error"

BOX="$(mktemp -d)"
mkdir -p "$BOX/invalid-policy"
if ! "$TEST_PYTHON" - "$REPO/config/agent-policy.toml" "$BOX/invalid-policy" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
output = Path(sys.argv[2])
mutations = {
    "version": ('schema_version = 1', 'schema_version = 999'),
    "duplicate-role": ('escalate_to = "Planner"', 'escalate_to = "Planner"\n\n[[roles]]\nname = "explorer"\ntier = "Scout"\npermission = "read-only"'),
    "duplicate-lane": ('escalate_to = "Planner"', 'escalate_to = "Planner"\n\n[[lanes]]\nname = "how-explore"\nrole = "scout"'),
    "unsupported-effort": ('[tiers.Scout]\nmodel = "gpt-6-luna"\neffort = "low"', '[tiers.Scout]\nmodel = "gpt-6-luna"\neffort = "ultra"'),
    "unsupported-model": ('[tiers.Scout]\nmodel = "gpt-6-luna"', '[tiers.Scout]\nmodel = "unmapped-model"'),
    "invalid-cap": ('max_children = 3', 'max_children = 0'),
    "boolean-cap": ('max_children = 3', 'max_children = true'),
    "invalid-escalation": ('escalate_to = "Planner"', 'escalate_to = "Scout"'),
    "invalid-lane-floor": ('floor = "Builder"\nescalate_at_or_below = "Builder"', 'floor = "Unknown"\nescalate_at_or_below = "Builder"'),
}
for name, (before, after) in mutations.items():
    assert source.count(before) == 1, f"{name}: expected exactly one policy match"
    (output / f"{name}.toml").write_text(source.replace(before, after, 1))
PY
then
  printf '  FAIL invalid-policy fixture setup\n'
  exit 1
fi
for case in version duplicate-role duplicate-lane unsupported-effort unsupported-model invalid-cap boolean-cap invalid-escalation invalid-lane-floor; do
  assert_exit 2 "$case fixture" "$TEST_PYTHON" "$POLICY" explain --harness codex --role explorer --policy "$BOX/invalid-policy/$case.toml"
done
assert_contains "$output" 'unknown floor' "lane floor: diagnosed"

"$TEST_PYTHON" "$REPO/scripts/render-codex.py" --agents "$REPO/.agents/agents" "$BOX/agents" > "$BOX/render.log" 2>&1
assert_eq "0" "$?" "renderer: writes policy-backed agents"
if "$TEST_PYTHON" - "$REPO" "$BOX/agents" "$FIXTURES/effective-routes.json" <<'PY'
import json
import sys
import tomllib
from pathlib import Path

repo, output, fixture = map(Path, sys.argv[1:])
sys.path.insert(0, str(repo / "scripts"))
from agent_policy import effective_route, load_policy, resolve

policy = load_policy()
expected = {p.stem for p in (repo / ".agents/agents").glob("*.md") if p.stem != "README"}
expected.update({"explorer", "scout", "debug-escalation"})
assert {p.stem for p in output.glob("*.toml")} == expected
for name in expected:
    parsed = tomllib.loads((output / f"{name}.toml").read_text())
    route = resolve(policy, lane=name) if name == "debug-escalation" else resolve(policy, role=name)
    assert {"name", "description", "developer_instructions"} <= parsed.keys(), name
    if route["tier"] == "Ceiling":
        assert "model" not in parsed and "model_reasoning_effort" not in parsed, name
    else:
        assert (parsed["model"], parsed["model_reasoning_effort"]) == (route["model"], route["effort"]), name
    if route["permission"] == "mcp-read":
        assert "sandbox_mode" not in parsed, name
    else:
        assert parsed["sandbox_mode"] == route["permission"], name
assert tomllib.loads((output / "explorer.toml").read_text())["sandbox_mode"] == "read-only"
assert "sandbox_mode" not in tomllib.loads((output / "scout.toml").read_text())
for case in json.loads(fixture.read_text()):
    try:
        route = effective_route(policy, **case["input"])
    except ValueError as exc:
        assert case.get("error") in str(exc), case
    else:
        assert (route["model"], route["source"]) == tuple(case["expected"]), case
        if "profile" in case:
            assert route["profile"] == case["profile"], case
for role, lane, parent in (("critic", None, "gpt-6-luna"),
                           ("code-debugger", "debug-escalation", "gpt-6.1-sol")):
    route = effective_route(policy, role=role, lane=lane, parent_model=parent)
    assert route["model"] == parent, route
    assert route["source"] == "parent", route
    assert route["requires_spawn_override"], route
    assert route["required_model"] == "gpt-6-astra", route
try:
    effective_route(policy, role="code-reviewer", parent_model="gpt-6-astra",
                    default_subagent_effort="low")
except ValueError as exc:
    assert "agents.default_subagent_reasoning_effort" in str(exc), exc
else:
    raise AssertionError("Ceiling effort default went undetected")
try:
    effective_route(policy, role="critic", parent_model="gpt-6-luna",
                    spawn_model="gpt-6.1-sol")
except ValueError as exc:
    assert "does not meet required" in str(exc), exc
else:
    raise AssertionError("critic floor accepted a lower spawn model")
PY
then
  assert_eq "0" "0" "renderer and effective routes: fixture contract"
else
  assert_eq "0" "1" "renderer and effective routes: fixture contract"
fi

cp -r "$BOX/agents" "$BOX/first"
"$TEST_PYTHON" "$REPO/scripts/render-codex.py" --agents "$REPO/.agents/agents" "$BOX/agents" > "$BOX/repeat.log" 2>&1
assert_eq "0" "$?" "renderer: repeat invocation succeeds"
if diff -rq "$BOX/first" "$BOX/agents" > "$BOX/diff.log"; then
  assert_eq "0" "0" "renderer: deterministic bytes"
else
  assert_eq "0" "1" "renderer: deterministic bytes"
fi

DOCTOR_HOME="$BOX/doctor-home"
DOCTOR_PROJECT="$BOX/project/sub"
mkdir -p "$DOCTOR_HOME/agents" "$DOCTOR_PROJECT/.codex/agents" "$BOX/project/.codex"
cp -r "$BOX/agents/." "$DOCTOR_HOME/agents/"
cat > "$DOCTOR_HOME/config.toml" <<'TOML'
model = "gpt-6.1-sol"
[agents]
max_threads = 5
TOML
cat > "$DOCTOR_HOME/fast.config.toml" <<'TOML'
model = "gpt-6-luna"
[agents]
max_concurrent_threads_per_session = 4
TOML
printf 'model = "gpt-6-astra"\n[agents]\nmax_concurrent_threads_per_session = 2\n' > "$BOX/project/.codex/config.toml"
printf 'model = "gpt-6.1-sol"\n[agents]\nmax_concurrent_threads_per_session = 3\n' > "$DOCTOR_PROJECT/.codex/config.toml"
cat > "$DOCTOR_PROJECT/.codex/agents/explorer.toml" <<'TOML'
name = "explorer"
description = "project shadow"
developer_instructions = "Inspect project code."
model = "gpt-6-astra"
model_reasoning_effort = "high"
TOML
DOCTOR_ARGS=(doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$DOCTOR_PROJECT" --profile fast --parent-model gpt-6-astra)
assert_exit 0 "doctor unknown provenance" "$TEST_PYTHON" "$POLICY" "${DOCTOR_ARGS[@]}"
assert_contains "$output" '"status": "UnknownLayer"' "doctor: unavailable CLI/cloud/session layers are unknown"
assert_contains "$output" '"cli"' "doctor: CLI layer named unknown"

SHADOW_ONLY="$BOX/shadow-only"
mkdir -p "$SHADOW_ONLY/.codex/agents"
cp "$DOCTOR_PROJECT/.codex/agents/explorer.toml" "$SHADOW_ONLY/.codex/agents/explorer.toml"
assert_exit 0 "doctor unknown project trust with agent shadow" "$TEST_PYTHON" "$POLICY" \
  doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$SHADOW_ONLY" \
  --cli-known --cloud-known --session-known
assert_contains "$output" '"project_trust"' \
  "doctor: project agent alone makes unknown trust material"

KNOWN_ARGS=("${DOCTOR_ARGS[@]}" --trust trusted --cli-known --cloud-known --session-known)
assert_exit 0 "doctor trusted project" "$TEST_PYTHON" "$POLICY" "${KNOWN_ARGS[@]}"
assert_contains "$output" '"status": "Issue"' "doctor: project shadow is reported"
assert_contains "$output" '"model": "gpt-6.1-sol"' "doctor: closest project config model selected"
assert_contains "$output" '"value": 3' "doctor: closest project cap selected"
assert_contains "$output" '"inherited_expensive": true' "doctor: inherited expensive Ceiling role identified"
assert_contains "$output" '"file_layer": "project"' "doctor: project agent shadow named"
assert_contains "$output" '"model": "gpt-6-astra"' "doctor: project shadow model reported"

assert_exit 0 "doctor unmet floor" "$TEST_PYTHON" "$POLICY" \
  doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$BOX/empty-project" \
  --trust untrusted --parent-model gpt-6.1-sol --cli-known --cloud-known --session-known
if "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
for name in ("critic", "debug-escalation"):
    role = report["roles"][name]
    assert role["model"] == "gpt-6.1-sol", role
    assert role["model_source"] == "parent:explicit_argument", role
    assert role["requires_spawn_override"], role
    assert any(name in finding and "spawn override" in finding for finding in report["findings"]), report
PY
then
  assert_eq "0" "0" "doctor: unpinned floor is not claimed as effective"
else
  assert_eq "0" "1" "doctor: unpinned floor is not claimed as effective"
fi

NO_PARENT_ARGS=(doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$DOCTOR_PROJECT" --profile fast --trust trusted --cli-known --cloud-known --session-known)
assert_exit 0 "doctor derives visible parent" "$TEST_PYTHON" "$POLICY" "${NO_PARENT_ARGS[@]}"
if "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
role = report["roles"]["code-reviewer"]
assert role["model"] == "gpt-6.1-sol", role
assert role["model_source"].startswith("parent:project:"), role
PY
then
  assert_eq "0" "0" "doctor: Ceiling derives parent from closest project layer"
else
  assert_eq "0" "1" "doctor: Ceiling derives parent from closest project layer"
fi
cp "$DOCTOR_PROJECT/.codex/config.toml" "$BOX/project-config.before"
printf 'default_subagent_model = "gpt-6-luna"\n' >> "$DOCTOR_PROJECT/.codex/config.toml"
assert_exit 0 "doctor default child model" "$TEST_PYTHON" "$POLICY" "${NO_PARENT_ARGS[@]}"
if "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
role = report["roles"]["code-reviewer"]
assert report["status"] == "Issue", report["status"]
assert role["model"] == "gpt-6-luna", role
assert role["model_source"].startswith("agents.default_subagent_model:project:"), role
PY
then
  assert_eq "0" "0" "doctor: winning child default caps inherited Ceiling"
else
  assert_eq "0" "1" "doctor: winning child default caps inherited Ceiling"
fi
cp "$BOX/project-config.before" "$DOCTOR_PROJECT/.codex/config.toml"
printf 'default_subagent_reasoning_effort = "low"\n' >> "$DOCTOR_PROJECT/.codex/config.toml"
assert_exit 0 "doctor default child effort" "$TEST_PYTHON" "$POLICY" "${NO_PARENT_ARGS[@]}"
assert_contains "$output" 'agents.default_subagent_reasoning_effort' \
  "doctor: winning child effort default caps Ceiling inheritance"
if "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
role = json.loads(sys.argv[1])["roles"]["code-reviewer"]
assert role["effort"] == "low", role
assert role["effort_source"].startswith("agents.default_subagent_reasoning_effort:project:"), role
PY
then
  assert_eq "0" "0" "doctor: effective Ceiling effort names winning layer"
else
  assert_eq "0" "1" "doctor: effective Ceiling effort names winning layer"
fi
cp "$BOX/project-config.before" "$DOCTOR_PROJECT/.codex/config.toml"

assert_exit 0 "doctor CLI precedence" "$TEST_PYTHON" "$POLICY" "${KNOWN_ARGS[@]}" --cli-model gpt-6-astra --cli-max-threads 2
assert_contains "$output" '"model_source": "cli"' "doctor: CLI model wins"
assert_contains "$output" '"source": "cli"' "doctor: CLI child cap wins"

assert_exit 0 "doctor untrusted project" "$TEST_PYTHON" "$POLICY" "${DOCTOR_ARGS[@]}" --trust untrusted --cli-known --cloud-known --session-known
assert_contains "$output" '"model_source": "profile:fast"' "doctor: profile wins over user when project untrusted"
assert_contains "$output" '"file_layer": "user"' "doctor: untrusted project agent does not shadow"

cp "$DOCTOR_HOME/agents/planner.toml" "$BOX/planner.before"
"$TEST_PYTHON" - "$DOCTOR_HOME/agents/planner.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('model = "gpt-6-astra"', 'model = "gpt-6-luna"'))
PY
assert_exit 0 "doctor managed drift" "$TEST_PYTHON" "$POLICY" "${KNOWN_ARGS[@]}"
assert_contains "$output" '"file_status": "ManagedDrift"' "doctor: managed model drift identified"

cp "$DOCTOR_HOME/agents/explorer.toml" "$BOX/explorer.before"
"$TEST_PYTHON" - "$DOCTOR_HOME/agents/explorer.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('sandbox_mode = "read-only"', 'sandbox_mode = "danger-full-access"'))
PY
assert_exit 0 "doctor managed sandbox drift" "$TEST_PYTHON" "$POLICY" \
  doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$BOX/empty-project" \
  --trust untrusted --cli-known --cloud-known --session-known
if "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
assert json.loads(sys.argv[1])["roles"]["explorer"]["file_status"] == "ManagedDrift"
PY
then
  assert_eq "0" "0" "doctor: managed explorer sandbox drift identified"
else
  assert_eq "0" "1" "doctor: managed explorer sandbox drift identified"
fi
cp "$BOX/explorer.before" "$DOCTOR_HOME/agents/explorer.toml"

MISSING_HOME="$BOX/missing-home"
mkdir -p "$MISSING_HOME"
assert_exit 0 "doctor missing cap" "$TEST_PYTHON" "$POLICY" doctor --harness codex --codex-home "$MISSING_HOME" --project-dir "$BOX/empty-project" --trust untrusted --cli-known --cloud-known --session-known
assert_contains "$output" '"status": "missing"' "doctor: absent child cap diagnosed"

rm -r "$BOX"

finish
