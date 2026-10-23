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
assert_contains "$out" "| control | task-a | run-1 | 2 | 2 | 8340 | 2847 | 41200 | 1 | - | - | 330 | 1 | 1 | - | - |" \
  "grader: control/task-a/run-1 — whole-file large, routing-around, bytes, largest, context, compactions, unknown sub-agent totals, wall, re-read rate, outcome, no hook log"
assert_contains "$out" "| control | task-a | run-2 | 1 | 0 | 2847 | 2847 | 30000 | 0 | 0 | 0 | 60 | - | 0 | - | - |" \
  "grader: a run with no Agent dispatch has no re-read rate and pass:false is outcome 0"
# A ranged read of the large file is not whole-file; a windowed sed of a file
# known large in the run is a routing-around attempt; score 0.5 passes through.
assert_contains "$out" "| control | task-b | run-1 | 0 | 1 | 1317 | 717 | 20000 | 0 | 0 | 0 | 90 | - | 0.5 | - | - |" \
  "grader: a ranged read is not whole-file and a sed window on the large file is routing-around"
# shunt/task-a/run-1: the parent windows big.py twice (717 + 362) around a
# completed Agent whose result (36 bytes) names big.py:120-160; the second
# window follows it, and the sub-agent's own read of big.py names the path for
# both windows — two re-reads over one named file; sub-agent totals come from
# the Agent result; the shunt log holds one annotate and one deny issued twice
# with an identical input.
assert_contains "$out" "| shunt | task-a | run-1 | 0 | 0 | 1115 | 717 | 15000 | 0 | 12000 | 7 | 120 | 2 | 1 | annotate:1 deny:2 | 1 |" \
  "grader: shunt/task-a/run-1 — sub-agent tokens and tool uses from the Agent result, hook decisions and one repeated deny"
assert_contains "$out" "| shunt | task-b | run-1 | 0 | 0 | 277 | 277 | 9000 | 0 | 0 | 0 | 45 | - | 1 | allow:1 | 0 |" \
  "grader: a control-sized run under the gate shows allow:1 and no repeated deny"
assert_eq "5" "$(printf '%s\n' "$out" | grep -c '^| \(control\|shunt\) | task-[ab] | run-')" "grader: five runs, five rows"

assert_contains "$out" "## Paired per-task means" "grader: two arms produce paired per-task means"
assert_contains "$out" "| control | task-a | 2 | 1.5 | 1 | 5593.5 | 2847 | 35600 | 0.5 | 0 | 0 | 195 | 1 | 0.5 | - |" \
  "grader: control/task-a means average the two runs and skip missing values"
assert_contains "$out" "| shunt | task-a | 1 | 0 | 0 | 1115 | 717 | 15000 | 0 | 12000 | 7 | 120 | 2 | 1 | 1 |" \
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
assert_contains "$keys" "run 0 0 1115 12000 7 2.0 1.0 {'annotate': 1, 'deny': 2} 1" "grader: --json carries the per-run metrics, hook decisions as counts"
assert_contains "$keys" "counts 5 4" "grader: --json carries five runs and four paired means"
# control/task-a/run-1 dispatched an Agent that never answered and left no
# transcript (unknown, `-`); run-2 delegated nothing (a true 0): the mean averages the 0.
assert_contains "$keys" "mean 2 1.5 0.5 0.0" "grader: --json means skip an unknown and average a true zero"

printf '\n--- rows: a run knows whether a shunt log sits beside its transcript ---\n'
out="$("$TEST_PYTHON" - "$GRADER" "$RESULTS" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("grade_read_shunt", sys.argv[1])
grader = importlib.util.module_from_spec(spec)
sys.modules["grade_read_shunt"] = grader
spec.loader.exec_module(grader)
print("has-log", [(r.arm, r.task, r.run, r.has_shunt_log) for r in grader.discover(sys.argv[2])])
PY
)"
assert_eq "0" "$(grep -c '"decision"' "$GRADER")" \
  "grader: the shunt log's shape is the parser's — the grader counts ShuntDecision records, it reads no field"
assert_contains "$out" "has-log [('control', 'task-a', 'run-1', False), ('control', 'task-a', 'run-2', False), ('control', 'task-b', 'run-1', False), ('shunt', 'task-a', 'run-1', True), ('shunt', 'task-b', 'run-1', True)]" \
  "grader: discover() flags the runs that have a shunt log"
assert_eq "0" "$(grep -c 'repeated_denies is not None' "$GRADER")" \
  "grader: the hook columns key on the run's shunt log, not on a sentinel in its row"

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
assert_contains "$err" "grade-read-shunt: " "grader: an error names the CLI that raised it"

# A shunt log with no decisions is an empty count in JSON and `none` in the table.
NODEC="$TMP/nodec/arm/task/run"; mkdir -p "$NODEC"
cp "$RESULTS/shunt/task-b/run-1/transcript.jsonl" "$NODEC/"
: > "$NODEC/shunt.jsonl"
assert_contains "$("$TEST_PYTHON" "$GRADER" "$TMP/nodec" 2>&1)" "| none | 0 |" "grader: a shunt log with no decisions renders none"
assert_contains "$("$TEST_PYTHON" "$GRADER" "$TMP/nodec" --json 2>&1 | "$TEST_PYTHON" -c 'import json, sys; print("hooks", json.load(sys.stdin)["runs"][0]["hook_decisions"])')" \
  "hooks {}" "grader: --json carries an empty count when the log had no decisions"

printf '\n--- rows: sub-agent totals are summed per Agent call ---\n'
# An async-launched Agent result carries no counters, so the call's totals are
# its own transcript's — the one its agentId names (s1's call is agent a1). A
# transcript no call names is attributed to nothing.
ASYNC="$TMP/async/arm/task/run"; mkdir -p "$ASYNC/subagents"
cp tests/fixtures/transcripts/root/proj-a/s1.jsonl "$ASYNC/transcript.jsonl"
"$TEST_PYTHON" - "$ASYNC/subagents" <<'PY'
import json, os, sys
for name, uses in (("agent-a1.jsonl", 3), ("agent-x2.jsonl", 4)):
    with open(os.path.join(sys.argv[1], name), "w", encoding="utf-8") as fh:
        for i in range(uses):
            block = {"type": "tool_use", "id": f"{name}-{i}", "name": "Bash", "input": {"command": "ls"}}
            msg = {"id": f"msg-{name}-{i}", "content": [block], "usage": {"input_tokens": 100, "output_tokens": 10}}
            fh.write(json.dumps({"type": "assistant", "isSidechain": True, "message": msg}) + "\n")
PY
out="$("$TEST_PYTHON" "$GRADER" "$TMP/async" --json 2>&1)"; rc=$?
assert_eq "0" "$rc" "grader: an async-launched run with two sub-agent transcripts grades with exit 0"
assert_contains "$(printf '%s\n' "$out" | "$TEST_PYTHON" -c 'import json, sys; r = json.load(sys.stdin)["runs"][0]; print("uses", r["subagent_tool_uses"], r["subagent_tokens"])')" \
  "uses 3 330" "grader: with no Agent counters the call's totals are the transcript its agentId names, and an unnamed transcript counts for nothing"

printf '\n--- rows: bytes into the parent leave out an inline sidechain result ---\n'
INLINE="$TMP/inline/arm/task/run"; mkdir -p "$INLINE"
cp tests/fixtures/transcripts/root/proj-b/s3.jsonl "$INLINE/transcript.jsonl"
out="$("$TEST_PYTHON" "$GRADER" "$TMP/inline" --json 2>&1)"; rc=$?
assert_eq "0" "$rc" "grader: a transcript with an inline sidechain grades with exit 0"
assert_contains "$(printf '%s\n' "$out" | "$TEST_PYTHON" -c 'import json, sys; print("bytes", json.load(sys.stdin)["runs"][0]["parent_bytes"])')" \
  "bytes 1613" "grader: the sidechain's 1487-byte result is not the parent's"

printf '\n--- rows: a sub-agent'"'"'s read names its path before the parent reads it ---\n'
# The sub-agent reads helper.py; no Agent text names it. The parent's later read
# of helper.py is the one re-read of the one path a sub-agent result named.
SIDENAMED="$TMP/sidenamed/arm/task/run"; mkdir -p "$SIDENAMED/subagents"
"$TEST_PYTHON" - "$SIDENAMED" <<'PY'
import json, os, sys
def use(uid, name, inp, sidechain):
    rec = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": uid, "name": name, "input": inp}]}}
    return {**rec, "isSidechain": True} if sidechain else rec
def result(uid, structured, text, sidechain):
    rec = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": uid, "content": text}]},
           "toolUseResult": structured}
    return {**rec, "isSidechain": True} if sidechain else rec
def read(uid, sidechain):
    block = {"type": "text", "file": {"filePath": "/work/app/helper.py", "content": "x = 1", "numLines": 1,
                                      "startLine": 1, "totalLines": 1}}
    return [use(uid, "Read", {"file_path": "/work/app/helper.py"}, sidechain), result(uid, block, "     1\tx = 1", sidechain)]
agent = {"status": "completed", "content": [{"type": "text", "text": "done"}], "totalTokens": 10, "totalToolUseCount": 1}
parent = [use("a1", "Agent", {"prompt": "go look around"}, False), result("a1", agent, "done", False), *read("r1", False)]
write = lambda path, recs: open(path, "w", encoding="utf-8").write("".join(json.dumps(r) + "\n" for r in recs))
write(os.path.join(sys.argv[1], "transcript.jsonl"), parent)
write(os.path.join(sys.argv[1], "subagents", "agent-h1.jsonl"), read("r2", True))
PY
out="$("$TEST_PYTHON" "$GRADER" "$TMP/sidenamed" --json 2>&1)"; rc=$?
assert_eq "0" "$rc" "grader: a run whose sub-agent read a file the parent then read grades with exit 0"
assert_contains "$(printf '%s\n' "$out" | "$TEST_PYTHON" -c 'import json, sys; print("rate", json.load(sys.stdin)["runs"][0]["reread_rate"])')" \
  "rate 1.0" "grader: a sub-agent's read names its path, so the parent's read of it is one re-read of one named path"

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
# The gate's hook writes tasks/.shunt/<session>.jsonl under the project the case ran in (specs/read-shunt.md § Tier 0).
mkdir -p "$KEPT/claude-eval-AAA/workspace/tasks/.shunt"
printf '%s\n' '{"decision":"deny","tool":"Read","input":{"file_path":"big.py"}}' \
               '{"decision":"deny","tool":"Read","input":{"file_path":"big.py"}}' > "$KEPT/claude-eval-AAA/workspace/tasks/.shunt/sess1.jsonl"
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
assert_eq "present" "$([ -f "$ARRANGED/gated/task-a/run-1/shunt.jsonl" ] && echo present || echo missing)" \
  "arrange: the hook's tasks/.shunt/<session>.jsonl under the home's project lands as shunt.jsonl beside the transcript"
assert_eq "missing" "$([ -e "$ARRANGED/gated/task-a/run-2/shunt.jsonl" ] && echo present || echo missing)" \
  "arrange: a session whose home holds no hook log gets no shunt.jsonl"
assert_eq '{"score": 1}' "$(cat "$ARRANGED/gated/task-a/run-1/outcome.json")" "arrange: outcome.json carries the runner's score"
assert_eq '{"pass": false}' "$(cat "$ARRANGED/gated/task-a/run-2/outcome.json")" \
  "arrange: a run with no score carries the runner's pass verdict"
graded="$("$TEST_PYTHON" "$GRADER" "$ARRANGED" 2>&1)"; rc=$?
assert_eq "0" "$rc" "arrange: the grader reads the arranged directory"
assert_contains "$graded" "| gated | task-a | run-1 | 0 | 0 | 1115 | 717 | 15000 | 0 | 12000 | 7 | 120 | 2 | 1 | deny:2 | 1 |" \
  "arrange: run 1 grades to the row its transcript gives, hook columns from the arranged log"
assert_contains "$graded" "| gated | task-a | run-2 | 0 | 1 | 1317 | 717 | 20000 | 0 | 0 | 0 | 90 | - | 0 |" \
  "arrange: run 2 grades with the pass verdict as outcome 0"

# Where a session's sub-agents live is the parser's rule, used by the reader and the copier alike.
assert_eq "0" "$(grep -c 'splitext' "$ARRANGE")" "arrange: finds a session's sub-agent directory through the parser, not by its own path rule"

# The outcome is validated once, in plan, and the record it made is what write stores.
out="$("$TEST_PYTHON" - "$ARRANGE" "$SCRIPTS" "$TMP" <<'PY'
import importlib.util, json, os, sys
from dataclasses import fields
sys.path.insert(0, sys.argv[2])
import read_transcript as rt
spec = importlib.util.spec_from_file_location("arrange_results", sys.argv[1])
arrange = importlib.util.module_from_spec(spec)
sys.modules["arrange_results"] = arrange
spec.loader.exec_module(arrange)
print("fields", [f.name for f in fields(arrange.ArrangedRun)])
dest = os.path.join(sys.argv[3], "outcome-probe")
os.makedirs(dest)
rt.write_outcome(dest, {"pass": False})
print("written", open(os.path.join(dest, rt.OUTCOME_FILE), encoding="utf-8").read())
PY
)"
assert_contains "$out" "fields ['case', 'number', 'transcript', 'shunt_log', 'outcome']" \
  "arrange: an arranged run carries the outcome record plan validated, not the raw score and passed, and the hook log plan found"
assert_contains "$out" 'written {"pass": false}' "arrange: write_outcome stores the record it is given"

err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$AGG" --arm gated --out "$ARRANGED" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: arranging over an existing run directory exits 2"
assert_contains "$err" "run-1" "arrange: the message names the run directory it would overwrite"

"$TEST_PYTHON" - "$TMP/aggregate-escape.json" <<'PY'
import json, sys
run = {"score": 1, "passed": True, "tracePath": "/tmp/claude-eval-AAA/out/trace.jsonl"}
json.dump({"cases": [{"name": "../escape", "arms": {"with": [run]}}]}, open(sys.argv[1], "w"))
PY
err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$TMP/aggregate-escape.json" --arm other --out "$TMP/arranged-3" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: a case name that is not a plain directory name exits 2"
assert_contains "$err" "../escape" "arrange: the message names the offending case"
assert_eq "missing" "$([ -e "$TMP/arranged-3" ] && echo present || echo missing)" \
  "arrange: nothing is written under --out for it"

# `<keep-temp>` may be one home. It is taken as that run's home only when it is
# the home the run's tracePath names.
"$TEST_PYTHON" - "$TMP/aggregate-one.json" <<'PY'
import json, sys
run = {"score": 1, "passed": True, "tracePath": "/tmp/claude-eval-AAA/out/trace.jsonl"}
json.dump({"cases": [{"name": "task-a", "arms": {"with": [run]}}]}, open(sys.argv[1], "w"))
PY
one="$("$TEST_PYTHON" "$ARRANGE" "$KEPT/claude-eval-AAA" "$TMP/aggregate-one.json" --arm solo --out "$TMP/arranged-one" 2>&1)"; rc=$?
assert_eq "0" "$rc" "arrange: <keep-temp> naming the one home a single-run aggregate points at arranges with exit 0"
[ "$rc" = "0" ] || printf '%s\n' "$one" | head -5
assert_eq '{"score": 1}' "$(cat "$TMP/arranged-one/solo/task-a/run-1/outcome.json" 2>/dev/null)" \
  "arrange: the one-home form writes the run's outcome from its own record"
assert_eq "$(cat "$KEPT/claude-eval-AAA/config/projects/-enc-cwd/sess1.jsonl")" \
  "$(cat "$TMP/arranged-one/solo/task-a/run-1/transcript.jsonl" 2>/dev/null)" \
  "arrange: the one-home form copies that home's own transcript"

# A shunt log beside the session transcript is not a second session: the
# parser's own definition of a session skips it.
LOGHOME="$TMP/kept-log/claude-eval-AAA"
mkdir -p "$LOGHOME/out" "$LOGHOME/config/projects/-enc-cwd"
cp "$KEPT/claude-eval-AAA/out/trace.jsonl" "$LOGHOME/out/"
cp "$KEPT/claude-eval-AAA/config/projects/-enc-cwd/sess1.jsonl" "$LOGHOME/config/projects/-enc-cwd/"
printf '%s\n' '{"decision":"deny","tool":"Read","input":{}}' > "$LOGHOME/config/projects/-enc-cwd/shunt.jsonl"
err="$("$TEST_PYTHON" "$ARRANGE" "$TMP/kept-log" "$TMP/aggregate-one.json" --arm logged --out "$TMP/arranged-log" 2>&1)"; rc=$?
assert_eq "0" "$rc" "arrange: a shunt.jsonl beside the session transcript is not a second session"
assert_eq "present" "$([ -f "$TMP/arranged-log/logged/task-a/run-1/transcript.jsonl" ] && echo present || echo missing)" \
  "arrange: the session transcript is still arranged beside a shunt log"

err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT/claude-eval-AAA" "$AGG" --arm mixed --out "$TMP/arranged-mixed" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: a two-run aggregate pointed at one home exits 2 instead of reading that home twice"
assert_contains "$err" "claude-eval-BBB" "arrange: the message names the home the second run needs"
assert_eq "missing" "$([ -e "$TMP/arranged-mixed" ] && echo present || echo missing)" \
  "arrange: nothing is written for a mismatched home"

# A runner score that is a bool is not a score — here and in the grader.
"$TEST_PYTHON" - "$TMP/aggregate-boolscore.json" <<'PY'
import json, sys
run = {"score": True, "passed": None, "tracePath": "/tmp/claude-eval-AAA/out/trace.jsonl"}
json.dump({"cases": [{"name": "task-a", "arms": {"with": [run]}}]}, open(sys.argv[1], "w"))
PY
err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$TMP/aggregate-boolscore.json" --arm bool --out "$TMP/arranged-bool" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: a run whose score is a bool and which has no pass verdict exits 2"
BOOLRUN="$TMP/boolscore/arm/task/run"; mkdir -p "$BOOLRUN"
cp "$RESULTS/shunt/task-b/run-1/transcript.jsonl" "$BOOLRUN/"
printf '%s' '{"score": true}' > "$BOOLRUN/outcome.json"
err="$("$TEST_PYTHON" "$GRADER" "$TMP/boolscore" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "grader: an outcome.json whose score is a bool exits 2, as arrange refuses to write it"
assert_contains "$err" "outcome.json:1" "grader: the message names the outcome file and line"

printf '%s' '{"cases": []}' > "$TMP/aggregate-empty.json"
err="$("$TEST_PYTHON" "$ARRANGE" "$KEPT" "$TMP/aggregate-empty.json" --arm none --out "$TMP/arranged-none" 2>&1 >/dev/null)"; rc=$?
assert_eq "2" "$rc" "arrange: an aggregate with no runs exits 2"
assert_contains "$err" "aggregate-empty.json: no runs on side 'with'" "arrange: the message names the aggregate and the side, not a transcript root"
assert_contains "$err" "arrange-plugin-eval-results: " "arrange: an error names the CLI that raised it"

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
