#!/bin/bash
# tests/test-perf.sh — the /perf skill (specs/perf-audit-and-debug.md): noise
# control, the waste scanner, the audit report schema and the skill text.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MEASURE="$(under_test .agents/skills/perf/scripts/measure.py)"
BOX="$(fixture_dir)"

measure() { "$TEST_PYTHON" "$MEASURE" "$@"; }
# field <json-file> <python expression over d> — one value out of a JSON file.
field() { "$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

# ============================================================================
# AC2 — measure.py run / summarize: N runs, min / median / spread, floor of 5
# ============================================================================
begin_case measure-run
run measure run --runs 5 --warmup 1 -- "$TEST_PYTHON" -c pass
assert_exit 0 "run: five runs of a passing command exit 0"
printf '%s' "$output" > "$BOX/run.json"
assert_eq "5" "$(field "$BOX/run.json" 'd["runs"]')" "run: runs is 5"
assert_eq "5" "$(field "$BOX/run.json" 'len(d["samples"])')" "run: five samples recorded"
assert_eq "1" "$(field "$BOX/run.json" 'd["warmup"]')" "run: warmup recorded"
assert_eq "ms" "$(field "$BOX/run.json" 'd["unit"]')" "run: unit is ms"
assert_eq "True" "$(field "$BOX/run.json" 'd["min"] <= d["median"] <= d["max"]')" "run: min <= median <= max"
assert_eq "True" "$(field "$BOX/run.json" 'abs(d["spread"] - (d["max"] - d["min"])) < 1e-6')" "run: spread is max - min"
assert_eq "True" "$(field "$BOX/run.json" '"spread_pct" in d')" "run: spread_pct reported"
assert_contains "$(field "$BOX/run.json" 'd["command"]')" "-c pass" "run: the command is recorded"

assert_refused 2 "not a measurement" "run: --runs 1 is refused" -- measure run --runs 1 -- "$TEST_PYTHON" -c pass
assert_refused 2 "at least 5" "run: --runs 4 is refused naming the floor" -- measure run --runs 4 -- "$TEST_PYTHON" -c pass
assert_refused 2 "no command" "run: a missing command is refused" -- measure run --runs 5
assert_refused 1 "run 1 exited 3" "run: a failing command is refused naming the run" -- \
  measure run --runs 5 --warmup 0 -- "$TEST_PYTHON" -c 'import sys; sys.exit(3)'

run measure summarize --unit ms --command 'lab trace x5' 100 102 104 106 108
assert_exit 0 "summarize: five samples exit 0"
printf '%s' "$output" > "$BOX/base.json"
assert_eq "100.0 104.0 108.0 8.0" "$(field "$BOX/base.json" '" ".join(str(float(d[k])) for k in ("min","median","max","spread"))')" \
  "summarize: min, median, max and spread from the samples"
assert_eq "lab trace x5" "$(field "$BOX/base.json" 'd["command"]')" "summarize: the producing command is recorded"
assert_refused 2 "not a measurement" "summarize: one sample is refused" -- measure summarize --unit ms --command x 42
assert_refused 2 "not a number" "summarize: a non-numeric sample is refused" -- measure summarize --unit ms --command x 1 2 3 4 five

# ============================================================================
# AC3 — measure.py compare: the noise band
# ============================================================================
begin_case measure-compare
measure summarize --unit ms --command 'lab trace x5' 90 91 92 93 99 > "$BOX/better.json"
measure summarize --unit ms --command 'lab trace x5' 98 99 101 103 110 > "$BOX/noise.json"
measure summarize --unit ms --command 'lab trace x5' 109 110 112 115 120 > "$BOX/worse.json"
measure summarize --unit ms --command 'other command' 90 91 92 93 99 > "$BOX/othercmd.json"
measure summarize --unit s --command 'lab trace x5' 90 91 92 93 99 > "$BOX/otherunit.json"
measure summarize --unit ms --command 'lab trace x5' 90 91 92 93 99 94 > "$BOX/otherruns.json"

verdict() { measure compare "$@" | "$TEST_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["verdict"])'; }
assert_eq "improved" "$(verdict "$BOX/base.json" "$BOX/better.json")" "compare: after median below baseline min is improved"
assert_eq "within-noise" "$(verdict "$BOX/base.json" "$BOX/noise.json")" "compare: an overlapping change is within-noise"
assert_eq "regressed" "$(verdict "$BOX/base.json" "$BOX/worse.json")" "compare: after median above baseline max is regressed"
assert_refused 2 "same command" "compare: different commands are refused" -- measure compare "$BOX/base.json" "$BOX/othercmd.json"
assert_refused 2 "same unit" "compare: different units are refused" -- measure compare "$BOX/base.json" "$BOX/otherunit.json"
assert_refused 2 "same number of runs" "compare: different run counts are refused" -- measure compare "$BOX/base.json" "$BOX/otherruns.json"
printf '{"command":"x","runs":1,"samples":[5],"unit":"ms"}' > "$BOX/single.json"
assert_refused 2 "not a measurement" "compare: a single-run file is refused" -- measure compare "$BOX/single.json" "$BOX/single.json"

run measure compare "$BOX/base.json" "$BOX/noise.json" --expected 50 --format markdown
assert_exit 0 "compare --format markdown exits 0"
assert_contains "$output" "| Baseline | Expected | After | Verdict |" "compare markdown: baseline, expected and after columns"
assert_contains "$output" "within-noise" "compare markdown: the verdict is printed"
assert_contains "$output" "not an improvement" "compare markdown: within-noise says it is not an improvement"
assert_contains "$output" "lab trace x5" "compare markdown: the one command is quoted"
assert_contains "$output" "50" "compare markdown: the expected number is shown"

finish
