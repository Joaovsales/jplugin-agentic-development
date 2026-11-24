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
assert_eq "True" "$(field "$BOX/run.json" 'round(d["max"] - d["min"], 3) == d["spread"]')" "run: spread is max - min"
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

# ============================================================================
# AC4 — scan.py finds the planted waste, at its exact file:line, and nothing else
# ============================================================================
begin_case scan
SCAN="$(under_test .agents/skills/perf/scripts/scan.py)"
SHOP=tests/fixtures/perf/shop
# The expected set is read off the fixture's `planted:` comments, one
# "<file>:<line> <pattern>" per pattern the comment names.
expected="$(cd "$REPO" && grep -nE '(#|//) planted: ' "$SHOP"/shop.py "$SHOP"/client.js \
  | "$TEST_PYTHON" -c '
import re, sys
out = []
for row in sys.stdin:
    path, line, text = row.split(":", 2)
    for pattern in re.search(r"planted: (.*)$", text).group(1).split(","):
        out.append(f"{path}:{line} {pattern.strip()}")
print("\n".join(sorted(out)))')"
run bash -c "cd '$REPO' && '$TEST_PYTHON' '$SCAN' '$SHOP'"
assert_exit 0 "scan: exits 0 over the shop fixture"
printf '%s' "$output" > "$BOX/scan.json"
actual="$("$TEST_PYTHON" -c '
import json, sys
d = json.load(open(sys.argv[1]))
print("\n".join(sorted("%s:%s %s" % (c["file"], c["line"], c["pattern"]) for c in d["candidates"])))' "$BOX/scan.json")"
assert_eq "6" "$(printf '%s\n' "$expected" | grep -c .)" "scan: the fixture plants six candidates (three per language)"
assert_eq "$expected" "$actual" "scan: exactly the planted candidates, at their file:line — clean twins stay silent"
for lang in shop.py client.js; do
  for pattern in n-plus-one sequential-await await-waterfall; do
    assert_contains "$actual" "$lang:" "scan: $lang candidates reported"
    assert_eq "1" "$(printf '%s\n' "$actual" | grep -c "$lang:.* $pattern\$")" "scan: $lang has one $pattern"
  done
done
assert_eq "True" "$(field "$BOX/scan.json" 'all(c["evidence"] and c["why"] for c in d["candidates"])')" \
  "scan: every candidate carries its verbatim evidence and why"
assert_eq "True" "$(field "$BOX/scan.json" 'any("db.execute" in c["evidence"] for c in d["candidates"])')" \
  "scan: evidence is the source line"

run bash -c "cd '$REPO' && '$TEST_PYTHON' '$SCAN' --format findings '$SHOP/shop.py'"
assert_exit 0 "scan --format findings exits 0"
assert_contains "$output" "[SHOULD-FIX | confidence: 50 | autofix_class: manual | owner: agent] $SHOP/shop.py:" \
  "scan findings: four-axis lines at confidence 50 with file:line"
assert_contains "$output" "  evidence: " "scan findings: an evidence line"
assert_contains "$output" "  failure: " "scan findings: a failure line"

printf 'def broken(:\n' > "$BOX/broken.py"
run "$TEST_PYTHON" "$SCAN" "$BOX/broken.py"
assert_exit 0 "scan: an unparsable file does not stop the scan"
assert_contains "$output" '"skipped"' "scan: an unparsable file is listed under skipped"
assert_contains "$output" "broken.py" "scan: the skipped file is named"
assert_refused 2 "no such path" "scan: a missing path is refused" -- "$TEST_PYTHON" "$SCAN" "$BOX/missing"
mkdir -p "$BOX/tree/node_modules/x"
cp "$REPO/$SHOP/client.js" "$BOX/tree/node_modules/x/client.js"
run "$TEST_PYTHON" "$SCAN" "$BOX/tree"
assert_not_contains "$output" "client.js" "scan: node_modules is skipped"

# ============================================================================
# AC5 — audit.py validate: the perf-audit/1 schema refuses what is not evidence
# ============================================================================
begin_case audit-validate
AUDIT="$(under_test .agents/skills/perf/scripts/audit.py)"
GOOD="$REPO/tests/fixtures/perf/audit/shop-audit.json"
audit() { "$TEST_PYTHON" "$AUDIT" "$@"; }
# mutate <name> <python statement over d> — a copy of the fixture audit, edited.
mutate() {
  "$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); exec(sys.argv[2]); json.dump(d, open(sys.argv[3], "w"))' \
    "$GOOD" "$2" "$BOX/$1.json"
  printf '%s\n' "$BOX/$1.json"
}
assert_exit 0 "validate: the fixture audit is valid" -- audit validate "$GOOD" --repo "$REPO"
assert_refused 2 "not a measurement" "validate: a single-run measurement is refused" -- \
  audit validate "$(mutate single 'm=d["paths"][0]["measurement"]; m["samples"]=[41.2]; m["runs"]=1; m["min"]=m["median"]=m["max"]=41.2; m["spread"]=0')"
assert_refused 2 "does not match its samples" "validate: a typed median is refused" -- \
  audit validate "$(mutate typed 'd["paths"][0]["measurement"]["median"]=12.0')"
assert_refused 2 "expected" "validate: a path without an expected number is refused" -- \
  audit validate "$(mutate noexpect 'del d["paths"][1]["expected"]')"
assert_refused 2 "differs from the measured unit" "validate: an expected number in another unit is refused" -- \
  audit validate "$(mutate unit 'd["paths"][1]["expected"]["unit"]="s"')"
assert_refused 2 "lab block" "validate: a web path without a lab block is refused" -- \
  audit validate "$(mutate nolab 'del d["paths"][3]["lab"]')"
assert_refused 2 "lab data" "validate: lab numbers presented as field data are refused" -- \
  audit validate "$(mutate field 'd["paths"][3]["lab"]["data"]="field"')"
assert_refused 2 "inp_ms" "validate: a lab block without INP is refused" -- \
  audit validate "$(mutate noinp 'del d["paths"][3]["lab"]["inp_ms"]')"
assert_refused 2 "confidence" "validate: a finding below confidence 75 is refused" -- \
  audit validate "$(mutate lowconf 'd["findings"][0]["confidence"]=50')"
assert_refused 2 "file:line" "validate: a finding without a line is refused" -- \
  audit validate "$(mutate noline 'del d["findings"][0]["line"]')"
assert_refused 2 "suggested fix" "validate: a finding without a fix is refused" -- \
  audit validate "$(mutate nofix 'd["findings"][0]["fix"]=""')"
assert_refused 2 "unknown path" "validate: a finding on an unknown path is refused" -- \
  audit validate "$(mutate nopath 'd["findings"][0]["path"]="nowhere"')"
assert_refused 2 "impact" "validate: impact outside 1-3 is refused" -- \
  audit validate "$(mutate impact 'd["findings"][0]["impact"]=7')"
assert_refused 2 "schema" "validate: an unknown schema is refused" -- \
  audit validate "$(mutate schema 'd["schema"]="perf-audit/0"')"
assert_refused 2 "does not exist" "validate --repo: a file:line absent from the tree is refused" -- \
  audit validate "$(mutate farline 'd["findings"][0]["line"]=9999')" --repo "$REPO"

# ============================================================================
# AC6 — audit.py render: measured, expected, gap; lab vitals; ranked findings
# ============================================================================
begin_case audit-render
run audit render "$GOOD"
assert_exit 0 "render: exits 0"
REPORT="$output"
assert_contains "$REPORT" "| Path | Kind | Runs | Min | Median | Spread | Expected | Gap | Likely source |" \
  "render: critical paths table carries measured, expected and gap"
# orders: median 41.2 ms over 5 runs vs 8 ms expected -> 5.2x.
assert_contains "$REPORT" "| List orders (\`orders\`) | endpoint | 5 | 40.8 ms | 41.2 ms | 3.1 ms | 8 ms | 5.2× |" \
  "render: the orders row has min, median, spread, expected and gap"
assert_contains "$REPORT" "## Web vitals (lab data)" "render: web vitals are labelled lab data"
assert_contains "$REPORT" "not field data" "render: the lab caveat is stated"
assert_contains "$REPORT" "| Home page (\`home\`) | 1240 ms | 180 ms | 0.02 | 3 | 412000 B | playwright-cli 0.1.22 |" \
  "render: LCP, INP, CLS, long tasks, bundle and backend"
# score = impact x confidence/100 / effort: n+1 3x1.0/1=3.0, waterfall 2x0.75/1=1.5, cart 3x0.75/2=1.125.
assert_precedes "$REPORT" "shop.py:30" "shop.py:57" "render: the n+1 (score 3.0) ranks above the waterfall (1.5)"
assert_precedes "$REPORT" "shop.py:57" "shop.py:71" "render: the waterfall (1.5) ranks above the cart awaits (1.12)"
assert_contains "$REPORT" "| 1 | N+1 customer lookup in list_orders | \`tests/fixtures/perf/shop/shop.py:30\` |" \
  "render: rank 1 carries its file:line"
assert_contains "$REPORT" "## Coverage gaps" "render: coverage gaps section"
assert_contains "$REPORT" "## Unverified" "render: unverified section"
run audit render "$(mutate nofind 'd["findings"]=[]')"
assert_contains "$output" "Findings: none" "render: an audit with no finding says so"

# ============================================================================
# AC7 — audit.py file: one task per finding, idempotent
# ============================================================================
begin_case audit-file
REG="$(fixture_repo)"
mkdir -p "$REG/docs" "$REG/tasks"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$REG/docs/task-tracking.md"
printf '# Todo\n' > "$REG/tasks/todo.md"
# The registry root is the audited project, so its tree holds the finding's file.
fixture_copy perf/shop "$REG/tests/fixtures/perf/shop"
run env -u TASK_REGISTRY_TRUSTED_CONFIG "$TEST_PYTHON" "$AUDIT" file "$GOOD" --repo "$REG"
assert_exit 0 "file (dry-run): exits 0"
assert_eq "3" "$(printf '%s\n' "$output" | grep -c 'would create')" "file (dry-run): one would-create per finding"
assert_eq "0" "$(ls "$REG/tasks/details" 2>/dev/null | wc -l | tr -d ' ')" "file (dry-run): nothing written"
run env -u TASK_REGISTRY_TRUSTED_CONFIG "$TEST_PYTHON" "$AUDIT" file "$GOOD" --repo "$REG" --apply
assert_exit 0 "file --apply: exits 0"
assert_eq "3" "$(ls "$REG/tasks/details" | wc -l | tr -d ' ')" "file --apply: exactly one task per finding"
assert_eq "3" "$(grep -c 'task-id: perf\.' "$REG/tasks/todo.md")" "file --apply: three index rows under the perf namespace"
detail="$(cat "$REG"/tasks/details/*n-1-customer*.md)"
assert_contains "$detail" "performance" "file: the performance label"
assert_contains "$detail" "python3 tests/fixtures/perf/shop/shop.py orders 2000" "file: the measure command is the reproduction"
assert_contains "$detail" "expected: 8 ms" "file: the expected number travels"
assert_contains "$detail" "tests/fixtures/perf/shop/shop.py:30" "file: file:line travels"
assert_contains "$detail" "Join customers" "file: the suggested fix travels"
run env -u TASK_REGISTRY_TRUSTED_CONFIG "$TEST_PYTHON" "$AUDIT" file "$GOOD" --repo "$REG" --apply
assert_exit 0 "file --apply again: exits 0"
assert_eq "3" "$(ls "$REG/tasks/details" | wc -l | tr -d ' ')" "file --apply again: no new task"
assert_eq "3" "$(grep -c 'task-id: perf\.' "$REG/tasks/todo.md")" "file --apply again: no new index row"

# ============================================================================
# AC9 — the /perf skill: both modes, the noise rule, estimate, web backends
# ============================================================================
begin_case skill
SKILL="$(under_test .agents/skills/perf/SKILL.md)"
REFS="$REPO/.agents/skills/perf/references"
assert_file_matches "$SKILL" '^name: perf$' "skill: frontmatter names perf"
assert_file_matches "$SKILL" '^## Audit mode' "skill: an Audit mode section"
assert_file_matches "$SKILL" '^## Debug mode' "skill: a Debug mode section"
assert_prose_contains "$SKILL" "Fewer than **5 runs** is refused" "skill: the five-run floor"
assert_prose_contains "$SKILL" "\`improved\` only when the after median is below the baseline's minimum" "skill: the noise rule"
assert_prose_contains "$SKILL" "\`within-noise\` is never reported as an improvement" "skill: within-noise is not a win"
assert_prose_contains "$SKILL" "impact × confidence ÷ effort" "skill: the ranking formula"
for script in measure.py scan.py audit.py; do
  assert_file_contains "$SKILL" "scripts/$script" "skill: names scripts/$script"
done
for ref in estimate non-pessimization web-lab audit-schema; do
  assert_file_exists "$REFS/$ref.md" "skill: references/$ref.md exists"
  assert_file_contains "$SKILL" "references/$ref.md" "skill: cites references/$ref.md"
done
assert_prose_contains "$REFS/estimate.md" "measured median ÷ expected" "estimate: the gap definition"
for source in "waste" "cache misses" "waterfalls" "N+1 queries" "oversized payloads"; do
  assert_file_contains "$REFS/estimate.md" "$source" "estimate: names $source as a gap source"
done
assert_precedes "$(cat "$REFS/web-lab.md")" "Playwright CLI" "Chrome DevTools" "web-lab: Playwright CLI before Chrome, as verify-evidence orders"
assert_file_contains "$REFS/web-lab.md" "verify-evidence" "web-lab: cites verify-evidence's backend order"
assert_prose_contains "$REFS/web-lab.md" "lab data, never field data" "web-lab: lab traces are labelled lab data"
for metric in LCP INP CLS; do assert_file_contains "$REFS/web-lab.md" "$metric" "web-lab: $metric recipe"; done
for pattern in n-plus-one sequential-await await-waterfall; do
  assert_file_contains "$REFS/non-pessimization.md" "$pattern" "non-pessimization: documents $pattern"
done
assert_file_matches "$REPO/README.md" '^\| `/perf` \|' "README: a row for /perf"

# ============================================================================
# AC8 — /quality-gate Phase 3 runs the waste scan on the gate's file list
# ============================================================================
begin_case quality-gate
GATE="$(under_test .agents/skills/quality-gate/SKILL.md)"
phase3="$(awk '/^## Phase 3/{f=1} /^## Phase 4/{f=0} f' "$GATE")"
assert_contains "$phase3" "python3 .agents/skills/perf/scripts/scan.py --format findings" "quality-gate: Phase 3 runs scan.py"
assert_contains "$phase3" "the gate's own file list" "quality-gate: the scan covers the gate's own file list"
assert_contains "$(printf '%s' "$phase3" | tr '\n' ' ' | tr -s ' ')" "a scale finding at \`confidence: 50\`" \
  "quality-gate: each candidate starts at confidence 50"
assert_contains "$phase3" ".agents/skills/perf/references/non-pessimization.md" "quality-gate: cites the non-pessimization checklist"

finish
