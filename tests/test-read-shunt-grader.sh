#!/bin/bash
# tests/test-read-shunt-grader.sh — grade-read-shunt.py, the read-shunt eval's
# grader (specs/read-shunt-baseline.md § Behavior › Eval harness, AC6, AC7).
#
# The eval's verdict on a gate comes from these rows, so two things are pinned
# against a hand-made results directory under tests/fixtures/transcripts/results/
# (two arms, two tasks, five runs, one sub-agent transcript, one shunt log):
#
#   1. ROWS — every metric of § Behavior per run, from the transcript and never
#      from the candidate's own words; paired per-task means per arm, and no
#      means at all when one arm is present; the hook columns appear only when
#      a shunt log sits beside a transcript.
#
#   2. SHARED PARSER — both CLIs import read_transcript.py and neither
#      re-extracts a Read, Bash, Agent or usage block, so a transcript format
#      change is caught in one place and the two tools cannot drift apart.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

export PYTHONDONTWRITEBYTECODE=1

SCRIPTS=".agents/skills/eval/scripts"
GRADER="$SCRIPTS/grade-read-shunt.py"
INCIDENCE="$SCRIPTS/read-incidence.py"
RESULTS="tests/fixtures/transcripts/results"

TMP="$(mktemp -d)"
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf '  FAIL could not create fixture dir\n'; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# --- § rows ------------------------------------------------------------------
printf '\n--- rows: one row per run, every metric, paired means per arm ---\n'

out="$("$TEST_PYTHON" "$GRADER" "$RESULTS" 2>&1)"; rc=$?
assert_eq "0" "$rc" "grader: the two-arm fixture grades with exit 0"
[ "$rc" = "0" ] || printf '%s\n' "$out" | head -5

assert_contains "$out" "| Arm | Task | Run | Parent whole-file large | Routing-around | Bytes into parent | Largest result | Final context | Compactions | Sub-agent tokens | Sub-agent tool uses | Wall s | Re-read rate | Outcome | Hook decisions | Repeated denies |" \
  "grader: the run table carries every § Behavior metric, hook columns included when a shunt log exists"
# control/task-a/run-1: two whole-file large reads of big.py (2847 block bytes
# each); routing-around = Grep -C 60 on big.py + bare `cat big.py` (not the
# small cat); bytes = 2847*2 + 500 + 2000 + 100 + 46; the second Read follows
# an Agent prompt naming big.py, so one re-read over one named path; the
# outcome file says score 1; 10:00:00 -> 10:05:30 is 330 s.
assert_contains "$out" "| control | task-a | run-1 | 2 | 2 | 8340 | 2847 | 41200 | 1 | - | 0 | 330 | 1 | 1 | - | - |" \
  "grader: control/task-a/run-1 — whole-file large, routing-around, bytes, largest, context, compactions, no sub-agent, wall, re-read rate, outcome, no hook log"
assert_contains "$out" "| control | task-a | run-2 | 1 | 0 | 2847 | 2847 | 30000 | 0 | - | 0 | 60 | - | 0 | - | - |" \
  "grader: a run with no Agent dispatch has no re-read rate and pass:false is outcome 0"
# A ranged read of the large file is not whole-file; a windowed sed of a file
# known large in the run is a routing-around attempt; score 0.5 passes through.
assert_contains "$out" "| control | task-b | run-1 | 0 | 1 | 1317 | 717 | 20000 | 0 | - | 0 | 90 | - | 0.5 | - | - |" \
  "grader: a ranged read is not whole-file and a sed window on the large file is routing-around"
# shunt/task-a/run-1: the parent windows big.py twice (717 + 362) around a
# completed Agent whose result (36 bytes) names big.py:120-160; the second
# window follows it — one re-read over one named file; sub-agent totals come
# from the Agent result; the shunt log holds one annotate and one deny issued
# twice with an identical input.
assert_contains "$out" "| shunt | task-a | run-1 | 0 | 0 | 1115 | 717 | 15000 | 0 | 12000 | 7 | 120 | 1 | 1 | annotate:1 deny:2 | 1 |" \
  "grader: shunt/task-a/run-1 — sub-agent tokens and tool uses from the Agent result, hook decisions and one repeated deny"
assert_contains "$out" "| shunt | task-b | run-1 | 0 | 0 | 277 | 277 | 9000 | 0 | - | 0 | 45 | - | 1 | allow:1 | 0 |" \
  "grader: a control-sized run under the gate shows allow:1 and no repeated deny"
assert_eq "5" "$(printf '%s\n' "$out" | grep -c '^| \(control\|shunt\) | task-[ab] | run-')" "grader: five runs, five rows"

assert_contains "$out" "## Paired per-task means" "grader: two arms produce paired per-task means"
assert_contains "$out" "| control | task-a | 2 | 1.5 | 1 | 5593.5 | 2847 | 35600 | 0.5 | - | 0 | 195 | 1 | 0.5 | - |" \
  "grader: control/task-a means average the two runs and skip missing values"
assert_contains "$out" "| shunt | task-a | 1 | 0 | 0 | 1115 | 717 | 15000 | 0 | 12000 | 7 | 120 | 1 | 1 | 1 |" \
  "grader: shunt/task-a means sit beside control/task-a as a paired row"
assert_contains "$out" "| control | task-b | 1 |" "grader: task-b has a control mean row"
assert_contains "$out" "| shunt | task-b | 1 |" "grader: task-b has a shunt mean row"
assert_not_contains "$out" "xxxxxxxxxx" "grader: file contents never appear"

printf '\n--- rows: one arm prints rows and no means; no shunt log, no hook columns ---\n'
ONE="$TMP/one-arm"; mkdir -p "$ONE"
cp -r "$RESULTS/control" "$ONE/control"
one="$("$TEST_PYTHON" "$GRADER" "$ONE" 2>&1)"; rc=$?
assert_eq "0" "$rc" "grader: a one-arm results directory grades with exit 0"
assert_contains "$one" "| control | task-a | run-1 | 2 | 2 | 8340 |" "grader: one arm still prints its rows"
assert_not_contains "$one" "Paired per-task means" "grader: one arm prints no paired means"
assert_not_contains "$one" "Hook decisions" "grader: without a shunt log there are no hook columns"

printf '\n--- rows: --json carries the same rows and means ---\n'
js="$("$TEST_PYTHON" "$GRADER" "$RESULTS" --json 2>&1)"; rc=$?
assert_eq "0" "$rc" "grader: --json exits 0"
keys="$(printf '%s\n' "$js" | "$TEST_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
r = [x for x in d["runs"] if x["arm"] == "shunt" and x["task"] == "task-a"][0]
print("run", r["whole_large"], r["routing_around"], r["parent_bytes"], r["subagent_tokens"], r["subagent_tool_uses"], r["reread_rate"], r["outcome"], r["hook_decisions"], r["repeated_denies"])
print("counts", len(d["runs"]), len(d["paired_means"]))
m = [x for x in d["paired_means"] if x["arm"] == "control" and x["task"] == "task-a"][0]
print("mean", m["runs"], m["whole_large"], m["outcome"], m["subagent_tokens"])
')"
assert_contains "$keys" "run 0 0 1115 12000 7 1.0 1.0 annotate:1 deny:2 1" "grader: --json carries the per-run metrics"
assert_contains "$keys" "counts 5 4" "grader: --json carries five runs and four paired means"
assert_contains "$keys" "mean 2 1.5 0.5 None" "grader: --json means skip missing values"

printf '\n--- rows: thresholds and drift ---\n'
hi="$("$TEST_PYTHON" "$GRADER" "$RESULTS" --bytes 100000 --lines 100000 2>&1)"
assert_contains "$hi" "| control | task-a | run-1 | 0 | 0 | 8340 |" "grader: --bytes/--lines move the large threshold for reads and routing alike"

EMPTY="$TMP/empty"; mkdir -p "$EMPTY/control/task-a"
err="$("$TEST_PYTHON" "$GRADER" "$EMPTY" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "grader: a results directory with no runs exits 2"
assert_contains "$err" "$(basename "$EMPTY")" "grader: the message names the directory"

DRIFT="$TMP/drift/arm/task/run"; mkdir -p "$DRIFT"
cp tests/fixtures/transcripts/drift/proj-d/s9.jsonl "$DRIFT/transcript.jsonl"
err="$("$TEST_PYTHON" "$GRADER" "$TMP/drift" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "grader: a transcript the shared parser cannot read exits 2"
assert_contains "$err" "transcript.jsonl:3" "grader: the drift message names the file and line"

BADLOG="$TMP/badlog/arm/task/run"; mkdir -p "$BADLOG"
cp "$RESULTS/shunt/task-b/run-1/transcript.jsonl" "$BADLOG/"
printf '%s\n' '{"tool":"Read","input":{}}' > "$BADLOG/shunt.jsonl"
err="$("$TEST_PYTHON" "$GRADER" "$TMP/badlog" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "grader: a shunt log entry without a decision exits 2"
assert_contains "$err" "shunt.jsonl:1" "grader: the shunt-log message names the file and line"

# --- § arranging -------------------------------------------------------------
printf '\n--- arranging: a kept `claude plugin eval` temp tree becomes the grader layout ---\n'

ARRANGE="$SCRIPTS/arrange-plugin-eval-results.py"
assert_eq "present" "$([ -f "$ARRANGE" ] && echo present || echo missing)" "arrange: arrange-plugin-eval-results.py exists"

# What the runner leaves: <TEMP>/claude-eval-<id>/{out/trace.jsonl,config/projects/<cwd>/<session>.jsonl}
# beside an aggregate-result.json whose runs name their trace by absolute path.
KEPT="$TMP/kept"
mkdir -p "$KEPT/claude-eval-AAA/out" "$KEPT/claude-eval-AAA/config/projects/-enc-cwd/sess1/subagents" \
         "$KEPT/claude-eval-BBB/out" "$KEPT/claude-eval-BBB/config/projects/-enc-cwd"
printf '%s\n' '{"type":"result"}' > "$KEPT/claude-eval-AAA/out/trace.jsonl"
cp "$RESULTS/shunt/task-a/run-1/transcript.jsonl" "$KEPT/claude-eval-AAA/config/projects/-enc-cwd/sess1.jsonl"
cp "$RESULTS/shunt/task-a/run-1/subagents/agent-s1.jsonl" "$KEPT/claude-eval-AAA/config/projects/-enc-cwd/sess1/subagents/"
printf '%s\n' '{"type":"result"}' > "$KEPT/claude-eval-BBB/out/trace.jsonl"
cp "$RESULTS/control/task-b/run-1/transcript.jsonl" "$KEPT/claude-eval-BBB/config/projects/-enc-cwd/sess2.jsonl"
AGG="$TMP/aggregate-result.json"
"$TEST_PYTHON" - "$AGG" <<'PY'
import json, sys
def run(score, passed, trace):
    return {"score": score, "passed": passed, "turns": 3, "error": None, "tracePath": trace, "graders": []}
agg = {"schemaVersion": 1, "cases": [{"name": "task-a", "arms": {"with": [
    run(1, True, "C:\\Users\\dev\\AppData\\Local\\Temp\\claude-eval-AAA\\out\\trace.jsonl"),
    run(None, False, "/tmp/claude-eval-BBB/out/trace.jsonl"),
]}}]}
json.dump(agg, open(sys.argv[1], "w"))
PY
ARRANGED="$TMP/arranged"
arr="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$AGG" --arm gated --out "$ARRANGED" 2>&1)"; rc=$?
assert_eq "0" "$rc" "arrange: a kept temp tree and its aggregate arrange with exit 0"
[ "$rc" = "0" ] || printf '%s\n' "$arr" | head -5
assert_eq "present" "$([ -f "$ARRANGED/gated/task-a/run-1/transcript.jsonl" ] && echo present || echo missing)" \
  "arrange: run 1's session transcript lands at <arm>/<task>/run-1/transcript.jsonl"
assert_eq "present" "$([ -f "$ARRANGED/gated/task-a/run-1/subagents/agent-s1.jsonl" ] && echo present || echo missing)" \
  "arrange: the session's sub-agent transcripts travel with it"
assert_eq '{"score": 1}' "$(cat "$ARRANGED/gated/task-a/run-1/outcome.json")" "arrange: outcome.json carries the runner's score"
assert_eq '{"pass": false}' "$(cat "$ARRANGED/gated/task-a/run-2/outcome.json")" \
  "arrange: a run with no score carries the runner's pass verdict"
graded="$("$TEST_PYTHON" "$GRADER" "$ARRANGED" 2>&1)"; rc=$?
assert_eq "0" "$rc" "arrange: the grader reads the arranged directory"
assert_contains "$graded" "| gated | task-a | run-1 | 0 | 0 | 1115 | 717 | 15000 | 0 | 12000 | 7 | 120 | 1 | 1 |" \
  "arrange: run 1 grades to the row its transcript gives"
assert_contains "$graded" "| gated | task-a | run-2 | 0 | 1 | 1317 | 717 | 20000 | 0 | - | 0 | 90 | - | 0 |" \
  "arrange: run 2 grades with the pass verdict as outcome 0"

err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$AGG" --arm gated --out "$ARRANGED" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: arranging over an existing run directory exits 2"
assert_contains "$err" "run-1" "arrange: the message names the run directory it would overwrite"

rm -rf "$KEPT/claude-eval-BBB"
err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$AGG" --arm other --out "$TMP/arranged-2" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: a run whose temp home was not kept exits 2"
assert_contains "$err" "claude-eval-BBB" "arrange: the message names the missing temp home"
assert_contains "$err" "--keep-temp" "arrange: the message says how to keep it"
assert_eq "missing" "$([ -e "$TMP/arranged-2" ] && echo present || echo missing)" \
  "arrange: nothing is written when any run cannot be arranged"

# --- § shared parser ----------------------------------------------------------
printf '\n--- shared parser: both CLIs import read_transcript.py and extract nothing themselves ---\n'
for cli in "$GRADER" "$INCIDENCE"; do
  assert_eq "1" "$(grep -c '^import read_transcript as rt' "$cli")" "$cli: imports the shared parser once"
  for marker in 'toolUseResult' '"tool_use"' '"tool_result"' '"usage"' 'cache_read_input_tokens' 'isSidechain' 'compact_boundary' '"message"'; do
    assert_eq "0" "$(grep -cF "$marker" "$cli")" "$cli: never touches $marker — the parser owns that block"
  done
done
assert_eq "1" "$(grep -c 'def bare_shell_reads' "$SCRIPTS/read_transcript.py")" "parser: the bare-read classifier lives in the shared module"
assert_eq "0" "$(grep -c 'def bare_shell_reads' "$GRADER" "$INCIDENCE" | grep -vc ':0$')" "clis: neither CLI carries its own shell-read classifier"

finish
