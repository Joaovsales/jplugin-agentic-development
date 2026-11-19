#!/bin/bash
# tests/test-run-ledger.sh — .agents/skills/build/scripts/run_ledger.py
# (specs/run-ledger.md AC1–AC4): one JSON record per run under tasks/runs/,
# totals derived from the records only, idempotent by run id, a final human
# decision never overwritten, and missing tokens or cost shown as unknown.
. "$(dirname "$0")/lib.sh"

PY="$TEST_PYTHON"   # resolved once in tests/lib.sh
SCRIPT="$(under_test .agents/skills/build/scripts/run_ledger.py)"
BOX="$(fixture_dir)"
OK="agent_result=True verification_result=True slice_result=True SUCCEEDED"
ledger() { run "$PY" "$SCRIPT" "$@"; }

begin_case "record"
L="$BOX/record"
ledger record --ledger "$L" --branch feat/x --base 0123456789abcdef --spec specs/x.md --pr 7 \
  --model builder=sonnet --model reviewer=sonnet --slice "1 attempts=2 $OK" \
  --tokens 1200 --cost 0.42
assert_exit 0 "a run records"
assert_contains "$output" "record: recorded feat-x-0123456789ab" "the default run id is the branch slug and 12 base chars"
F="$L/feat-x-0123456789ab.json"
assert_file_exists "$F" "the record lands at <ledger>/<run-id>.json"
fields="$("$PY" -c 'import json,sys; r=json.load(open(sys.argv[1])); s=r["slices"][0]
print(r["schema"], r["run_id"], r["base_sha"], r["spec"], r["pr"], r["models"]["builder"], r["tokens"], r["cost_usd"], r["human_result"], s["id"], s["attempts"], s["agent_result"], s["slice_result"], s["label"])' "$F")"
assert_eq "run-ledger/1 feat-x-0123456789ab 0123456789abcdef specs/x.md 7 sonnet 1200 0.42 None 1 2 True True SUCCEEDED" \
  "$fields" "the record carries spec, base, pr, models, slice attempts, the three outcomes, tokens and cost"

assert_refused 2 "does not follow from" "a slice label inconsistent with slice_outcome.derive is refused" -- \
  "$PY" "$SCRIPT" record --ledger "$L" --branch feat/x --base 0123456789abcdef \
  --slice "1 attempts=1 agent_result=True verification_result=True slice_result=True AGENT_FAILED"
assert_refused 2 "attempts" "attempts below 1 is refused" -- \
  "$PY" "$SCRIPT" record --ledger "$L" --branch feat/x --base 0123456789abcdef --slice "1 attempts=0 $OK"
assert_refused 2 "--tokens" "a negative token count is refused" -- \
  "$PY" "$SCRIPT" record --ledger "$L" --branch feat/x --base 0123456789abcdef --tokens -5
assert_refused 2 "run id" "a run id that is not a safe file name is refused" -- \
  "$PY" "$SCRIPT" record --ledger "$L" --branch feat/x --base 0123456789abcdef --run-id ../escape
assert_refused 2 "its own parent" "a run cannot be its own parent" -- \
  "$PY" "$SCRIPT" record --ledger "$L" --branch feat/x --base 0123456789abcdef --parent feat-x-0123456789ab
end_case

begin_case "idempotent"
L="$BOX/idem"
rec() { ledger record --ledger "$L" --branch b --base aaaaaaaaaaaa1 --pr 1 --slice "1 attempts=1 $OK" --cost 1; }
rec; ledger decide --ledger "$L" --run-id b-aaaaaaaaaaaa --result merged
cp "$L/b-aaaaaaaaaaaa.json" "$BOX/first.json"
ledger stats --ledger "$L"; first_stats="$output"
rec
assert_exit 0 "recording the same run again succeeds"
assert_files_identical "$BOX/first.json" "$L/b-aaaaaaaaaaaa.json" "the second record leaves the file byte-identical"
ledger stats --ledger "$L"
assert_eq "$first_stats" "$output" "recording the same run twice changes no count"
assert_contains "$output" "runs=1 prs=1 merged=1" "one run, one PR"
ledger decide --ledger "$L" --run-id b-aaaaaaaaaaaa --result merged
assert_exit 0 "deciding the same result again is accepted"
assert_contains "$output" "decide: unchanged b-aaaaaaaaaaaa merged" "and reported unchanged"
assert_files_identical "$BOX/first.json" "$L/b-aaaaaaaaaaaa.json" "a repeated decision appends nothing"
end_case

begin_case "human decision"
L="$BOX/human"
ledger record --ledger "$L" --branch h --base bbbbbbbbbbbb --cost 1
ledger decide --ledger "$L" --run-id h-bbbbbbbbbbbb --result changes_requested
assert_exit 0 "changes_requested is recorded"
ledger decide --ledger "$L" --run-id h-bbbbbbbbbbbb --result merged
assert_exit 0 "changes_requested can still become merged"
assert_refused 1 "a final human decision is never overwritten" "merged is final: closed is refused" -- \
  "$PY" "$SCRIPT" decide --ledger "$L" --run-id h-bbbbbbbbbbbb --result closed
assert_refused 1 "already merged" "merged is final: changes_requested is refused" -- \
  "$PY" "$SCRIPT" decide --ledger "$L" --run-id h-bbbbbbbbbbbb --result changes_requested
ledger record --ledger "$L" --branch h --base bbbbbbbbbbbb --cost 2 --tokens 10
assert_exit 0 "a later record of the same run succeeds"
kept="$("$PY" -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["human_result"], ",".join(r["decisions"]), r["cost_usd"])' "$L/h-bbbbbbbbbbbb.json")"
assert_eq "merged changes_requested,merged 2.0" "$kept" "a later record updates its facts and keeps the human decision"
for flag in --human-result --result --decision --merged; do
  ledger record --ledger "$L" --branch h --base bbbbbbbbbbbb "$flag" closed
  assert_exit 2 "record accepts no human-result option: $flag is refused"
done
assert_refused 1 "no run" "deciding a run with no record is refused" -- \
  "$PY" "$SCRIPT" decide --ledger "$L" --run-id nope --result merged
ledger decide --ledger "$L" --run-id h-bbbbbbbbbbbb --result approved
assert_exit 2 "a result outside merged, changes_requested and closed is a usage error"
end_case

begin_case "last"
L="$BOX/last"
ledger record --ledger "$L" --branch r --base 111111111111 --run-id r-first
ledger record --ledger "$L" --branch r --base 222222222222 --run-id r-second --parent r-first
ledger record --ledger "$L" --branch other --base 333333333333
ledger last --ledger "$L" --branch r
assert_exit 0 "last finds the branch's newest run"
assert_eq "r-second" "$output" "last prints the newest run id on the branch"
ledger last --ledger "$L" --branch absent
assert_exit 1 "a branch with no run exits 1"
end_case

begin_case "stats"
L="$BOX/stats"
# PR A: one run, merged first time (first pass), cost 2.
ledger record --ledger "$L" --branch a --base aaaaaaaaaaaa --run-id A1 --cost 2 --tokens 100
ledger decide --ledger "$L" --run-id A1 --result merged
# PR B: changes requested, then a rework run that merged; cost 1 + 3.
ledger record --ledger "$L" --branch b --base bbbbbbbbbbbb --run-id B1 --cost 1 --tokens 50
ledger decide --ledger "$L" --run-id B1 --result changes_requested
ledger record --ledger "$L" --branch b --base cccccccccccc --run-id B2 --parent B1 --cost 3 --tokens 150
ledger decide --ledger "$L" --run-id B2 --result merged
# PR C: closed. PR D: open, undecided.
ledger record --ledger "$L" --branch c --base dddddddddddd --run-id C1 --cost 5 --tokens 5
ledger decide --ledger "$L" --run-id C1 --result closed
ledger record --ledger "$L" --branch d --base eeeeeeeeeeee --run-id D1 --cost 9 --tokens 9
ledger stats --ledger "$L"
assert_exit 0 "stats reports"
assert_contains "$output" "run-ledger: runs=5 prs=4 merged=2 closed=1 open=1" "runs are grouped into PRs by parent_run_id"
assert_contains "$output" "run-ledger: first_pass_rate=1/3 (33%)" "first pass: merged in one run with no changes requested, over merged plus closed"
assert_contains "$output" "run-ledger: attempts_per_merged_pr=1.50" "attempts: runs per merged PR"
assert_contains "$output" "run-ledger: cost_per_merged_pr=3.00" "cost: every run in the merged PRs, per merged PR"
assert_contains "$output" "run-ledger: tokens_per_merged_pr=150" "tokens: per merged PR"
rm "$L/A1.json"
ledger stats --ledger "$L"
assert_contains "$output" "first_pass_rate=0/2 (0%)" "removing a record changes the report: nothing is a stored total"
assert_contains "$output" "attempts_per_merged_pr=2.00" "attempts follow the records"

ledger stats --ledger "$BOX/empty-ledger"
assert_exit 0 "an empty ledger reports"
assert_contains "$output" "first_pass_rate=unknown — no decided PRs" "no decided PR: the rate is unknown, never 0%"
assert_contains "$output" "cost_per_merged_pr=unknown — no merged PRs" "no merged PR: the cost is unknown"

printf '{"schema": "run-ledger/9", "run_id": "bad"}\n' > "$L/bad.json"
assert_refused 1 "bad.json" "a record with an unknown schema stops stats, naming the file" -- \
  "$PY" "$SCRIPT" stats --ledger "$L"
printf 'not json' > "$L/bad.json"
assert_refused 1 "bad.json" "an unreadable record stops stats, naming the file" -- \
  "$PY" "$SCRIPT" stats --ledger "$L"
rm "$L/bad.json"
sed 's/"run_id": "D1"/"run_id": "D9"/' "$L/D1.json" > "$L/D2.json"
assert_refused 1 "D2.json" "a record whose run id differs from its file name is refused" -- \
  "$PY" "$SCRIPT" stats --ledger "$L"
rm "$L/D2.json"
printf '{"sch' > "$L/.tmp-crashed.json"
ledger stats --ledger "$L"
assert_exit 0 "a temp file a crashed write left behind is not a record"
rm "$L/.tmp-crashed.json"

L="$BOX/cycle"
ledger record --ledger "$L" --branch x --base 111111111111 --run-id X1 --parent X2
ledger record --ledger "$L" --branch x --base 222222222222 --run-id X2 --parent X1
assert_refused 1 "parent cycle through" "a parent cycle is refused, naming the runs" -- "$PY" "$SCRIPT" stats --ledger "$L"
end_case

begin_case "unknown"
L="$BOX/unknown"
ledger record --ledger "$L" --branch u --base aaaaaaaaaaaa --run-id U1
unk="$("$PY" -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["tokens"], r["cost_usd"])' "$L/U1.json")"
assert_eq "unknown unknown" "$unk" "a run recorded without tokens or cost stores unknown for each"
ledger decide --ledger "$L" --run-id U1 --result merged
ledger record --ledger "$L" --branch v --base bbbbbbbbbbbb --run-id V1 --cost 4 --tokens 40
ledger decide --ledger "$L" --run-id V1 --result merged
ledger stats --ledger "$L"
assert_contains "$output" "cost_per_merged_pr=unknown — cost missing on 1 of 2 merged PRs" "an unknown cost makes the aggregate unknown with a count"
assert_contains "$output" "tokens_per_merged_pr=unknown — tokens missing on 1 of 2 merged PRs" "an unknown token count does too"
assert_not_contains "$output" "cost_per_merged_pr=0" "unknown is never shown as zero"
ledger record --ledger "$L" --branch w --base cccccccccccc --run-id W1 --cost unknown --tokens unknown
assert_exit 0 "unknown is an accepted explicit value"
end_case

finish
