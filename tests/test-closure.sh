#!/bin/bash
# tests/test-closure.sh — closure.py's transition engine: every row of the
# spec's § Transitions — closure `phase` table (specs/quality-receipt-closure.md),
# its bounds, and the seven AC-6 fixture scenarios.
#
# closure.py is a pure state machine with no `gh`, no `git`, no network, so
# every case here drives it directly through a temp state file -- no fixture
# repo, no subprocess mocking, no Windows gh-mock trap.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

PY="$TEST_PYTHON"
CLOSURE="$REPO/.agents/skills/wrap-up-session/scripts/closure.py"
SCENARIOS="$REPO/tests/fixtures/closure/scenarios.json"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# run_case <name> <state-json> <observe-json> <expected-line> [expected-exit]
# Writes <state-json> verbatim as the state file, calls `step`, and asserts
# both the exit code and the single printed line.
run_case() {
  _name="$1"; _state="$2"; _observe="$3"; _expect="$4"; _exit="${5:-0}"
  _state_file="$TMP/state_$_name.json"
  printf '%s' "$_state" > "$_state_file"
  _out="$("$PY" "$CLOSURE" step --state "$_state_file" --observe "$_observe" 2>&1)"
  _code=$?
  assert_eq "$_exit" "$_code" "$_name: exit code"
  assert_eq "$_expect" "$_out" "$_name: printed line"
}

D0='{"phase":"receipt","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}'

printf '\n--- transitions: receipt ---\n'
run_case "receipt-valid" \
  '{"phase":"receipt","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"receipt":"valid"}' "action run-suite"
run_case "receipt-stale-full-not-gated" \
  '{"phase":"receipt","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"receipt":"stale","scope":"full"}' "action quality-gate scope=full"
run_case "receipt-stale-delta-not-gated" \
  '{"phase":"receipt","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"receipt":"stale","scope":"delta"}' "action quality-gate scope=delta"
run_case "receipt-stale-gated-no-pr" \
  '{"phase":"receipt","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"receipt":"stale"}' "terminal stopped state=receipt reason=receipt not written after gate"
run_case "receipt-stale-gated-pr-open" \
  '{"phase":"receipt","pr_open":true,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"receipt":"stale"}' "action mark-draft reason=receipt not written after gate"

printf '\n--- transitions: gate ---\n'
run_case "gate-go" \
  '{"phase":"gate","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"gate":"GO"}' "action check-receipt"
run_case "gate-hold-approved" \
  '{"phase":"gate","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"gate":"HOLD-approved"}' "action check-receipt"
run_case "gate-hold" \
  '{"phase":"gate","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"gate":"HOLD"}' "terminal stopped state=gate reason=review HOLD"
run_case "gate-stop" \
  '{"phase":"gate","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"gate":"STOP"}' "terminal stopped state=gate reason=review STOP"
run_case "gate-none" \
  '{"phase":"gate","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"gate":"none"}' "terminal stopped state=gate reason=review none"

printf '\n--- transitions: suite ---\n'
run_case "suite-green" \
  '{"phase":"suite","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"suite":"green"}' "action commit-push"
run_case "suite-red" \
  '{"phase":"suite","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"suite":"red"}' "terminal stopped state=suite reason=tests"
run_case "suite-blocked" \
  '{"phase":"suite","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"suite":"blocked"}' "terminal stopped state=suite reason=suite lock held"

printf '\n--- transitions: push ---\n'
run_case "push-ok" \
  '{"phase":"push","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"push":"ok"}' "action pr-sync"
run_case "push-nonff-rounds-left" \
  '{"phase":"push","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"push":"non-ff","branch":"feat/163"}' "action merge-base ref=origin/feat/163"
run_case "push-nonff-no-rounds" \
  '{"phase":"push","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":1,"deploy_reentries":0}' \
  '{"push":"non-ff","branch":"feat/163"}' "terminal stopped state=push reason=push non-fast-forward"
run_case "push-denied" \
  '{"phase":"push","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"push":"denied"}' "terminal stopped state=push reason=push denied"

printf '\n--- transitions: pr ---\n'
run_case "pr-number" \
  '{"phase":"pr","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"pr":17}' "action mergeability"
run_case "pr-failed" \
  '{"phase":"pr","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"pr":"failed"}' "terminal stopped state=pr reason=pr-sync failed"

printf '\n--- transitions: mergeable ---\n'
run_case "mergeable-clean" \
  '{"phase":"mergeable","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"mergeable":"clean"}' "action watch-ci"
run_case "mergeable-conflicting-rounds-left" \
  '{"phase":"mergeable","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"mergeable":"conflicting","base":"master"}' "action merge-base ref=origin/master"
run_case "mergeable-conflicting-no-rounds" \
  '{"phase":"mergeable","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":1,"deploy_reentries":0}' \
  '{"mergeable":"conflicting","base":"master"}' "action mark-draft reason=mergeable conflicting"
run_case "mergeable-unknown" \
  '{"phase":"mergeable","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"mergeable":"unknown"}' "action mark-draft reason=mergeable unknown"

printf '\n--- transitions: merge ---\n'
run_case "merge-resolved" \
  '{"phase":"merge","pr_open":false,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"merge":"resolved"}' "action check-receipt"
_state_file="$TMP/state_merge-resolved.json"
assert_file_matches "$_state_file" '"conflict_rounds": 1' "merge-resolved: conflict_rounds incremented"
assert_file_matches "$_state_file" '"gated": false' "merge-resolved: gated reset on tree-changing return"
run_case "merge-unresolved" \
  '{"phase":"merge","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"merge":"unresolved"}' "action mark-draft reason=merge unresolved"

printf '\n--- transitions: ci ---\n'
run_case "ci-pass" \
  '{"phase":"ci","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"ci":"pass"}' "action verify-deploy"
run_case "ci-none" \
  '{"phase":"ci","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"ci":"none"}' "action verify-deploy"
run_case "ci-fail-rounds-left" \
  '{"phase":"ci","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"ci":"fail","checks":["tests"]}' "action debug-ci checks=tests"
run_case "ci-fail-no-rounds" \
  '{"phase":"ci","pr_open":true,"gated":false,"ci_rounds":2,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"ci":"fail","checks":["tests"]}' "action mark-draft reason=ci fail"
run_case "ci-timeout" \
  '{"phase":"ci","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"ci":"timeout"}' "action mark-draft reason=ci timeout"

printf '\n--- transitions: repair ---\n'
run_case "repair-fixed" \
  '{"phase":"repair","pr_open":true,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"debug":"fixed"}' "action check-receipt"
_state_file="$TMP/state_repair-fixed.json"
assert_file_matches "$_state_file" '"ci_rounds": 1' "repair-fixed: ci_rounds incremented"
assert_file_matches "$_state_file" '"gated": false' "repair-fixed: gated reset on tree-changing return"
run_case "repair-not-fixed" \
  '{"phase":"repair","pr_open":true,"gated":false,"ci_rounds":1,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"debug":"not-fixed"}' "action mark-draft reason=debug not-fixed"

printf '\n--- transitions: deploy ---\n'
run_case "deploy-pass-not-moved" \
  '{"phase":"deploy","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"deploy":"pass","head-moved":false}' "action record-closure"
run_case "deploy-pass-moved-reentry-left" \
  '{"phase":"deploy","pr_open":true,"gated":true,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"deploy":"pass","head-moved":true}' "action check-receipt"
_state_file="$TMP/state_deploy-pass-moved-reentry-left.json"
assert_file_matches "$_state_file" '"deploy_reentries": 1' "deploy re-entry: deploy_reentries incremented"
assert_file_matches "$_state_file" '"gated": false' "deploy re-entry: gated reset on tree-changing return"
run_case "deploy-pass-moved-no-reentry" \
  '{"phase":"deploy","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":1}' \
  '{"deploy":"pass","head-moved":true}' "action mark-draft reason=deployment re-entry exhausted"
run_case "deploy-na" \
  '{"phase":"deploy","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"deploy":"n/a","reason":"no targets"}' "action record-closure note=not applicable — no targets"
run_case "deploy-fail" \
  '{"phase":"deploy","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"deploy":"fail"}' "action mark-draft reason=deployment failed"

printf '\n--- transitions: record ---\n'
run_case "record-recorded" \
  '{"phase":"record","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"record":"recorded"}' "terminal complete state=record reason=closure recorded"
run_case "record-failed" \
  '{"phase":"record","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' \
  '{"record":"record-failed"}' "action mark-draft reason=record failed"

printf '\n--- transitions: partial ---\n'
run_case "partial-drafted" \
  '{"phase":"partial","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0,"reason":"tests","label":"suite"}' \
  '{"partial":"drafted"}' "terminal partial state=suite reason=tests draft=yes"
run_case "partial-draft-failed" \
  '{"phase":"partial","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0,"reason":"tests","label":"suite"}' \
  '{"partial":"draft-failed"}' "terminal partial state=suite reason=tests draft=failed"
run_case "partial-no-pr" \
  '{"phase":"partial","pr_open":true,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0,"reason":"tests","label":"suite"}' \
  '{"partial":"no-pr"}' "terminal partial state=suite reason=tests draft=none"

printf '\n--- rejected observations leave the state file byte-for-byte unchanged ---\n'
_state_file="$TMP/state_unknown.json"
printf '%s' "$D0" > "$_state_file"
cp "$_state_file" "$_state_file.before"
_out="$("$PY" "$CLOSURE" step --state "$_state_file" --observe '{"receipt":"bogus"}' 2>&1)"
_code=$?
assert_eq "2" "$_code" "unknown observation: exit 2"
assert_contains "$_out" "closure: observation" "unknown observation: names the error"
assert_contains "$_out" "not valid in phase receipt" "unknown observation: names the phase"
assert_files_identical "$_state_file.before" "$_state_file" "unknown observation: state file untouched"

_state_file2="$TMP/state_unknown2.json"
printf '%s' '{"phase":"suite","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}' > "$_state_file2"
cp "$_state_file2" "$_state_file2.before"
"$PY" "$CLOSURE" step --state "$_state_file2" --observe '{"suite":"unknown"}' >/dev/null 2>&1
_code=$?
assert_eq "2" "$_code" "unrecognized suite observation: exit 2"
assert_files_identical "$_state_file2.before" "$_state_file2" "unrecognized suite observation: state file untouched"

printf '\n--- cycle check: every cycle in the table consumes a counter (or gated) ---\n'
DRIVER="$TMP/driver.py"
cat > "$DRIVER" <<'PYEOF'
import json
import subprocess
import sys

py = sys.argv[1]
closure = sys.argv[2]
proc = subprocess.run([py, closure, "table"], capture_output=True, text=True)
if proc.returncode != 0:
    print("BAD table exited " + str(proc.returncode) + " " + proc.stderr)
    sys.exit(0)
rows = json.loads(proc.stdout)

graph = {}
for row in rows:
    graph.setdefault(row["phase"], []).append((row["to"], row["counter"]))

bad_cycles = []
stack = []
on_stack = set()


def dfs(node):
    if node == "TERMINAL":
        return
    if node in on_stack:
        start = stack.index(node)
        path = stack[start:] + [node]
        counters = []
        for a, b in zip(path, path[1:]):
            for to, counter in graph.get(a, []):
                if to == b:
                    counters.append(counter)
                    break
        if not any(counters):
            bad_cycles.append(path)
        return
    stack.append(node)
    on_stack.add(node)
    for to, _counter in graph.get(node, []):
        dfs(to)
    stack.pop()
    on_stack.discard(node)


for phase in list(graph):
    dfs(phase)

print("BAD " + json.dumps(bad_cycles) if bad_cycles else "OK")
PYEOF

_out="$("$PY" "$DRIVER" "$PY" "$CLOSURE" 2>&1)"
assert_eq "OK" "$_out" "table walk: no cycle without a counter"

printf '\n--- scenarios: fixture replay (AC 6) ---\n'
SCENARIO_DRIVER="$TMP/scenario_driver.py"
cat > "$SCENARIO_DRIVER" <<'PYEOF'
import json
import os
import subprocess
import sys

py = sys.argv[1]
closure = sys.argv[2]
scenarios_path = sys.argv[3]
tmp_dir = sys.argv[4]

with open(scenarios_path, "r", encoding="utf-8") as handle:
    scenarios = json.load(handle)

failures = []
for scenario in scenarios:
    name = scenario["name"]
    state_path = os.path.join(tmp_dir, "scenario_" + name + ".json")
    if os.path.exists(state_path):
        os.remove(state_path)
    for i, step in enumerate(scenario["steps"]):
        proc = subprocess.run(
            [py, closure, "step", "--state", state_path, "--observe", json.dumps(step["observe"])],
            capture_output=True,
            text=True,
        )
        actual = proc.stdout.strip() if proc.returncode == 0 else proc.stderr.strip()
        if actual != step["expect"]:
            failures.append(
                name + " step " + str(i) + ": expected [" + step["expect"] + "] got [" + actual + "]"
            )

if failures:
    print("BAD")
    for failure in failures:
        print(failure)
else:
    print("OK")
PYEOF

_out="$("$PY" "$SCENARIO_DRIVER" "$PY" "$CLOSURE" "$SCENARIOS" "$TMP" 2>&1)"
assert_eq "OK" "$(printf '%s\n' "$_out" | head -1)" "scenarios: every fixture replays to its expected trace"
if [ "$(printf '%s\n' "$_out" | head -1)" != "OK" ]; then
  printf '%s\n' "$_out"
fi

finish
