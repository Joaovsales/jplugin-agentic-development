#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$(under_test scripts/agent-policy)"
RENDER_CODEX="$(under_test scripts/render-codex.py)"
FIXTURES="$REPO/tests/fixtures/agent-policy"

assert_exit 0 "explorer route: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --role explorer
assert_contains "$output" '"tier": "Scout"' "explorer: semantic tier"
assert_contains "$output" '"model": "gpt-6-luna"' "explorer: provider model"
assert_contains "$output" '"permission": "read-only"' "explorer: permission intent"
assert_contains "$output" '"max_children": 3' "explorer: supported child limit"
assert_contains "$output" '"trace"' "explorer: route explanation"

for agent_file in "$REPO"/.agents/agents/*.md; do
  [ "${agent_file##*/}" = README.md ] && continue
  agent="${agent_file##*/}"; agent="${agent%.md}"
  assert_exit 0 "$agent route: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --role "$agent"
  assert_contains "$output" '"tier":' "$agent: tier explained"
  assert_contains "$output" '"permission":' "$agent: permission explained"
done

assert_exit 0 "critic inheritance: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --role critic --parent-model gpt-6-astra
assert_contains "$output" '"inherit_model": true' "critic: inherits sufficient parent"
assert_contains "$output" '"model": "gpt-6-astra"' "critic: effective parent model"

for parent in gpt-6-luna gpt-6.1-sol; do
  assert_exit 0 "debug escalation from $parent: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --lane debug-escalation --parent-model "$parent"
  assert_contains "$output" '"model": "gpt-6-astra"' "debug escalation: Planner mapping above $parent"
  assert_contains "$output" '"effort": "high"' "debug escalation: Planner effort above $parent"
  assert_contains "$output" '"inherit_model": false' "debug escalation: explicit stronger model above $parent"
done
assert_exit 0 "debug escalation above Builder: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --lane debug-escalation --parent-model gpt-6-astra
assert_contains "$output" '"inherit_model": true' "debug escalation: stronger parent inherited"
assert_exit 0 "debug escalation unknown parent: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --lane debug-escalation --parent-model unknown-model
assert_contains "$output" '"model": null' "debug escalation: unknown parent has no claimed model"
assert_contains "$output" '"unresolved": true' "debug escalation: unknown parent is unresolved"

assert_exit 0 "lane selection: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --lane how-explore
assert_contains "$output" '"role": "explorer"' "lane: selected role"
assert_exit 2 "unknown lane: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --lane missing
assert_contains "$output" 'unknown lane' "unknown lane: actionable error"
assert_exit 2 "mismatched lane and role: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --lane how-explore --role scout
assert_contains "$output" 'selects role explorer' "lane conflict: actionable error"

BOX="$(fixture_dir)"
mkdir -p "$BOX/invalid-policy"
assert_true "invalid-policy fixture setup" -- "$TEST_PYTHON" - "$REPO/config/agent-policy.toml" "$BOX/invalid-policy" <<'PY'
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
for case in version duplicate-role duplicate-lane unsupported-effort unsupported-model invalid-cap boolean-cap invalid-escalation invalid-lane-floor; do
  assert_exit 2 "$case fixture: exit status" -- "$TEST_PYTHON" "$POLICY" explain --harness codex --role explorer --policy "$BOX/invalid-policy/$case.toml"
done
assert_contains "$output" 'unknown floor' "lane floor: diagnosed"

assert_exit 0 "renderer: writes policy-backed agents" -- "$TEST_PYTHON" "$RENDER_CODEX" --agents "$REPO/.agents/agents" "$BOX/agents"
assert_true "renderer and effective routes: fixture contract" -- "$TEST_PYTHON" - "$REPO" "$BOX/agents" "$FIXTURES/effective-routes.json" <<'PY'
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

cp -r "$BOX/agents" "$BOX/first"
assert_exit 0 "renderer: repeat invocation succeeds" -- "$TEST_PYTHON" "$RENDER_CODEX" --agents "$REPO/.agents/agents" "$BOX/agents"
assert_true "renderer: deterministic bytes" -- diff -rq "$BOX/first" "$BOX/agents"

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
assert_exit 0 "doctor unknown provenance: exit status" -- "$TEST_PYTHON" "$POLICY" "${DOCTOR_ARGS[@]}"
assert_contains "$output" '"status": "UnknownLayer"' "doctor: unavailable CLI/cloud/session layers are unknown"
assert_contains "$output" '"cli"' "doctor: CLI layer named unknown"

SHADOW_ONLY="$BOX/shadow-only"
mkdir -p "$SHADOW_ONLY/.codex/agents"
cp "$DOCTOR_PROJECT/.codex/agents/explorer.toml" "$SHADOW_ONLY/.codex/agents/explorer.toml"
assert_exit 0 "doctor unknown project trust with agent shadow: exit status" -- "$TEST_PYTHON" "$POLICY" \
  doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$SHADOW_ONLY" \
  --cli-known --cloud-known --session-known
assert_contains "$output" '"project_trust"' \
  "doctor: project agent alone makes unknown trust material"

KNOWN_ARGS=("${DOCTOR_ARGS[@]}" --trust trusted --cli-known --cloud-known --session-known)
assert_exit 0 "doctor trusted project: exit status" -- "$TEST_PYTHON" "$POLICY" "${KNOWN_ARGS[@]}"
assert_contains "$output" '"status": "Issue"' "doctor: project shadow is reported"
assert_contains "$output" '"model": "gpt-6.1-sol"' "doctor: closest project config model selected"
assert_contains "$output" '"value": 3' "doctor: closest project cap selected"
assert_contains "$output" '"inherited_expensive": true' "doctor: inherited expensive Ceiling role identified"
assert_contains "$output" '"file_layer": "project"' "doctor: project agent shadow named"
assert_contains "$output" '"model": "gpt-6-astra"' "doctor: project shadow model reported"

assert_exit 0 "doctor unmet floor: exit status" -- "$TEST_PYTHON" "$POLICY" \
  doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$BOX/empty-project" \
  --trust untrusted --parent-model gpt-6.1-sol --cli-known --cloud-known --session-known
assert_true "doctor: unpinned floor is not claimed as effective" -- "$TEST_PYTHON" - "$output" <<'PY'
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

NO_PARENT_ARGS=(doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$DOCTOR_PROJECT" --profile fast --trust trusted --cli-known --cloud-known --session-known)
assert_exit 0 "doctor derives visible parent: exit status" -- "$TEST_PYTHON" "$POLICY" "${NO_PARENT_ARGS[@]}"
assert_true "doctor: Ceiling derives parent from closest project layer" -- "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
role = report["roles"]["code-reviewer"]
assert role["model"] == "gpt-6.1-sol", role
assert role["model_source"].startswith("parent:project:"), role
PY
cp "$DOCTOR_PROJECT/.codex/config.toml" "$BOX/project-config.before"
printf 'default_subagent_model = "gpt-6-luna"\n' >> "$DOCTOR_PROJECT/.codex/config.toml"
assert_exit 0 "doctor default child model: exit status" -- "$TEST_PYTHON" "$POLICY" "${NO_PARENT_ARGS[@]}"
assert_true "doctor: winning child default caps inherited Ceiling" -- "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
role = report["roles"]["code-reviewer"]
assert report["status"] == "Issue", report["status"]
assert role["model"] == "gpt-6-luna", role
assert role["model_source"].startswith("agents.default_subagent_model:project:"), role
PY
cp "$BOX/project-config.before" "$DOCTOR_PROJECT/.codex/config.toml"
printf 'default_subagent_reasoning_effort = "low"\n' >> "$DOCTOR_PROJECT/.codex/config.toml"
assert_exit 0 "doctor default child effort: exit status" -- "$TEST_PYTHON" "$POLICY" "${NO_PARENT_ARGS[@]}"
assert_contains "$output" 'agents.default_subagent_reasoning_effort' \
  "doctor: winning child effort default caps Ceiling inheritance"
assert_true "doctor: effective Ceiling effort names winning layer" -- "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
role = json.loads(sys.argv[1])["roles"]["code-reviewer"]
assert role["effort"] == "low", role
assert role["effort_source"].startswith("agents.default_subagent_reasoning_effort:project:"), role
PY
cp "$BOX/project-config.before" "$DOCTOR_PROJECT/.codex/config.toml"

assert_exit 0 "doctor CLI precedence: exit status" -- "$TEST_PYTHON" "$POLICY" "${KNOWN_ARGS[@]}" --cli-model gpt-6-astra --cli-max-threads 2
assert_contains "$output" '"model_source": "cli"' "doctor: CLI model wins"
assert_contains "$output" '"source": "cli"' "doctor: CLI child cap wins"

assert_exit 0 "doctor untrusted project: exit status" -- "$TEST_PYTHON" "$POLICY" "${DOCTOR_ARGS[@]}" --trust untrusted --cli-known --cloud-known --session-known
assert_contains "$output" '"model_source": "profile:fast"' "doctor: profile wins over user when project untrusted"
assert_contains "$output" '"file_layer": "user"' "doctor: untrusted project agent does not shadow"

cp "$DOCTOR_HOME/agents/planner.toml" "$BOX/planner.before"
"$TEST_PYTHON" - "$DOCTOR_HOME/agents/planner.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('model = "gpt-6-astra"', 'model = "gpt-6-luna"'))
PY
assert_exit 0 "doctor managed drift: exit status" -- "$TEST_PYTHON" "$POLICY" "${KNOWN_ARGS[@]}"
assert_contains "$output" '"file_status": "ManagedDrift"' "doctor: managed model drift identified"

cp "$DOCTOR_HOME/agents/explorer.toml" "$BOX/explorer.before"
"$TEST_PYTHON" - "$DOCTOR_HOME/agents/explorer.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('sandbox_mode = "read-only"', 'sandbox_mode = "danger-full-access"'))
PY
assert_exit 0 "doctor managed sandbox drift: exit status" -- "$TEST_PYTHON" "$POLICY" \
  doctor --harness codex --codex-home "$DOCTOR_HOME" --project-dir "$BOX/empty-project" \
  --trust untrusted --cli-known --cloud-known --session-known
assert_true "doctor: managed explorer sandbox drift identified" -- "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys
assert json.loads(sys.argv[1])["roles"]["explorer"]["file_status"] == "ManagedDrift"
PY
cp "$BOX/explorer.before" "$DOCTOR_HOME/agents/explorer.toml"

MISSING_HOME="$BOX/missing-home"
mkdir -p "$MISSING_HOME"
assert_exit 0 "doctor missing cap: exit status" -- "$TEST_PYTHON" "$POLICY" doctor --harness codex --codex-home "$MISSING_HOME" --project-dir "$BOX/empty-project" --trust untrusted --cli-known --cloud-known --session-known
assert_contains "$output" '"status": "missing"' "doctor: absent child cap diagnosed"

finish
