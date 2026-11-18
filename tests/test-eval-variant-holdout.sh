#!/bin/bash
# variant-holdout.py: /eval Mode B splits its prompts into a tuning set and a
# never-tuned holdout, and promotes a variant only when its holdout mean beats
# both the unchanged skill and the variant's previous version
# (specs/eval-holdout.md, issue #443).
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
SCRIPTS="$(under_test .agents/skills/eval/scripts)"
TOOL="$SCRIPTS/variant-holdout.py"
SKILL="$(under_test .agents/skills/eval/SKILL.md)"
assert_file_exists "$TOOL" "variant-holdout: the script is on disk"
if [ ! -f "$TOOL" ]; then finish; exit $?; fi

TMP="$(fixture_dir)"

# prompts <file> <prompt>... — a prompts.json the author hands `split`.
prompts() {
  local out="$1"; shift
  "$TEST_PYTHON" -c 'import json, sys; json.dump(sys.argv[2:], open(sys.argv[1], "w"))' "$out" "$@"
}

# scores <prompts.json> <out> <tuning u,p,c> <holdout u,p,c> [skip-cost-arm] [drop-arm]
# One graded run per prompt and arm, scored by the set `split` put the prompt
# in; two runs per prompt for the candidate, so per-prompt averaging is used.
# skip-cost-arm leaves cost out of that arm's first run only, so one silent
# run among reported ones is what must read unknown.
scores() {
  "$TEST_PYTHON" - "$TOOL" "$@" <<'PY'
import json, subprocess, sys
tool, prompts, out, tuning, holdout = sys.argv[1:6]
skip_cost = sys.argv[6] if len(sys.argv) > 6 else ""
drop = sys.argv[7] if len(sys.argv) > 7 else ""
split = json.loads(subprocess.run([sys.executable, tool, "split", prompts, "--json"],
                                  check=True, capture_output=True, text=True).stdout)
means = {"tuning": [float(x) for x in tuning.split(",")],
         "holdout": [float(x) for x in holdout.split(",")]}
skip_cost_done = False
with open(out, "w") as fh:
    for name in ("tuning", "holdout"):
        for prompt in split[name]:
            for arm, score in zip(("unchanged", "previous", "candidate"), means[name]):
                if arm == drop and name == "holdout":
                    continue
                runs = [score + 0.1, score - 0.1] if arm == "candidate" else [score]
                for value in runs:
                    record = {"prompt": prompt, "arm": arm, "score": round(value, 6)}
                    if arm != skip_cost or skip_cost_done:
                        record["cost_usd"] = 0.25
                    elif arm == skip_cost:
                        skip_cost_done = True
                    fh.write(json.dumps(record) + "\n")
PY
}

SIX=(
  "the login test fails on CI but passes locally, can you find out why"
  "add a --dry-run flag to the release script"
  "rename the billing module to invoicing everywhere"
  "the export endpoint is slow on large accounts"
  "write a migration that backfills the created_at column"
  "why does the cache invalidate on every deploy"
)
prompts "$TMP/six.json" "${SIX[@]}"

# --- AC1: fewer than four distinct prompts refuses to run --------------------
prompts "$TMP/three.json" "${SIX[@]:0:3}"
assert_refused 2 "at least 4 distinct prompts" "split: three prompts are refused" -- "$TEST_PYTHON" "$TOOL" split "$TMP/three.json"
assert_not_contains "$output" "tuning:" "split: a refused run prints no split"

# Copies of one prompt, or the same prompt re-spaced, count once.
prompts "$TMP/dupes.json" "${SIX[0]}" "${SIX[1]}" "${SIX[2]}" "  ${SIX[0]}  " "${SIX[1]/ / 	}"
assert_refused 2 "at least 4 distinct prompts" "split: duplicates do not count as distinct prompts" -- "$TEST_PYTHON" "$TOOL" split "$TMP/dupes.json"

"$TEST_PYTHON" - "$TMP/three.jsonl" "${SIX[@]:0:3}" <<'PY'
import json, sys
with open(sys.argv[1], "w") as fh:
    for prompt in sys.argv[2:]:
        for arm in ("unchanged", "previous", "candidate"):
            fh.write(json.dumps({"prompt": prompt, "arm": arm, "score": 0.9 if arm == "candidate" else 0.1}) + "\n")
PY
assert_refused 2 "at least 4 distinct prompts" "verdict: a scored run over three prompts is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/three.jsonl"
assert_not_contains "$output" "Verdict:" "verdict: a refused run prints no verdict"

# --- the split: half held out, fixed by the prompt text alone ----------------
run "$TEST_PYTHON" "$TOOL" split "$TMP/six.json" --json
assert_exit 0 "split: six prompts split"
assert_eq "3 3" "$(printf '%s' "$output" | "$TEST_PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(len(d["tuning"]), len(d["holdout"]))')" \
  "split: six prompts give three tuning and three holdout"
first="$output"
prompts "$TMP/six-reordered.json" "${SIX[5]}" "${SIX[2]}" "${SIX[0]}" "${SIX[4]}" "${SIX[1]}" "${SIX[3]}"
run "$TEST_PYTHON" "$TOOL" split "$TMP/six-reordered.json" --json
assert_eq "$first" "$output" "split: the input order does not move a prompt between sets"
prompts "$TMP/four.json" "${SIX[@]:0:4}"
run "$TEST_PYTHON" "$TOOL" split "$TMP/four.json"
assert_exit 0 "split: four distinct prompts are enough"
assert_contains "$output" "holdout:" "split: the text form lists the holdout"
assert_contains "$output" "tuning:" "split: the text form lists the tuning set"

# --- AC3: a variant that wins only on the tuning set is rejected -------------
scores "$TMP/six.json" "$TMP/tuning-win.jsonl" 0.6,0.55,0.9 0.6,0.55,0.5
run "$TEST_PYTHON" "$TOOL" verdict "$TMP/tuning-win.jsonl"
assert_exit 0 "verdict: a reject is a measurement, not an error"
assert_contains "$output" "Verdict: reject" "verdict: a tuning-only win is rejected"
assert_contains "$output" "does not beat unchanged" "verdict: the reject names the baseline it lost to"
assert_contains "$output" "| candidate | 0.9000 | 0.5000 |" "verdict: the report shows the tuning win beside the holdout loss"
tuning_win="$output"

scores "$TMP/six.json" "$TMP/holdout-win.jsonl" 0.6,0.55,0.5 0.6,0.55,0.8
run "$TEST_PYTHON" "$TOOL" verdict "$TMP/holdout-win.jsonl"
assert_contains "$output" "Verdict: promote" "verdict: beating both baselines on the holdout promotes"

scores "$TMP/six.json" "$TMP/one-baseline.jsonl" 0.6,0.55,0.9 0.6,0.75,0.7
run "$TEST_PYTHON" "$TOOL" verdict "$TMP/one-baseline.jsonl"
assert_contains "$output" "Verdict: reject" "verdict: beating only the unchanged skill is rejected"
assert_contains "$output" "does not beat previous" "verdict: names the previous version as the baseline not beaten"

# 0.3 is the tie whose candidate mean, (0.4 + 0.2) / 2, lands a float ulp above 0.3.
scores "$TMP/six.json" "$TMP/tie.jsonl" 0.6,0.55,0.9 0.25,0.3,0.3
run "$TEST_PYTHON" "$TOOL" verdict "$TMP/tie.jsonl"
assert_contains "$output" "Verdict: reject" "verdict: a tie with a baseline is not a win"

# --- AC2: the report shows both baselines on the holdout, and the split ------
assert_contains "$tuning_win" "| unchanged | 0.6000 | 0.6000 |" "report: the unchanged baseline's holdout mean"
assert_contains "$tuning_win" "| previous | 0.5500 | 0.5500 |" "report: the previous version's holdout mean"
assert_contains "$tuning_win" "3 tuning, 3 holdout" "report: states the split"
assert_contains "$tuning_win" "${SIX[0]}" "report: lists the prompts it split"

# --- AC4: unreported cost is unknown, never zero -----------------------------
scores "$TMP/six.json" "$TMP/no-cost.jsonl" 0.6,0.55,0.5 0.6,0.55,0.8 candidate
run "$TEST_PYTHON" "$TOOL" verdict "$TMP/no-cost.jsonl"
assert_contains "$output" "| candidate | 0.5000 | 0.8000 | unknown |" "cost: an arm with an unreported run costs unknown"
assert_contains "$output" "| unchanged | 0.6000 | 0.6000 | 1.5000 |" "cost: a fully reported arm sums its runs"
run "$TEST_PYTHON" "$TOOL" verdict "$TMP/no-cost.jsonl" --json
assert_contains "$output" '"candidate": "unknown"' "cost: --json carries unknown too"

# --- refusals: what the report cannot show is never guessed ------------------
scores "$TMP/six.json" "$TMP/no-previous.jsonl" 0.6,0.55,0.5 0.6,0.55,0.8 "" previous
assert_refused 2 "has no previous run" "verdict: a holdout prompt missing a baseline is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/no-previous.jsonl"

cp "$TMP/holdout-win.jsonl" "$TMP/bad-arm.jsonl"
printf '%s\n' '{"prompt": "x", "arm": "variant-b", "score": 1}' >> "$TMP/bad-arm.jsonl"
assert_refused 2 "unknown arm" "verdict: an arm outside the three is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/bad-arm.jsonl"
assert_contains "$output" "bad-arm.jsonl:25" "verdict: the refusal names the line"

cp "$TMP/holdout-win.jsonl" "$TMP/bad-score.jsonl"
printf '%s\n' '{"prompt": "x", "arm": "candidate", "score": "high"}' >> "$TMP/bad-score.jsonl"
assert_refused 2 "finite number" "verdict: a non-numeric score is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/bad-score.jsonl"

cp "$TMP/holdout-win.jsonl" "$TMP/bad-cost.jsonl"
printf '%s\n' '{"prompt": "x", "arm": "candidate", "score": 1, "cost_usd": -1}' >> "$TMP/bad-cost.jsonl"
assert_refused 2 "cost_usd" "verdict: a negative cost is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/bad-cost.jsonl"

printf '%s\n' '[1, 2]' > "$TMP/not-object.jsonl"
assert_refused 2 "JSON object" "verdict: a line that is not an object is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/not-object.jsonl"

printf '%s\n' '["a", 3, "c", "d"]' > "$TMP/bad-prompts.json"
assert_refused 2 "non-empty strings" "split: a prompt that is not a string is refused" -- "$TEST_PYTHON" "$TOOL" split "$TMP/bad-prompts.json"

assert_refused 2 "variant-holdout:" "split: a missing prompts file is an error" -- "$TEST_PYTHON" "$TOOL" split "$TMP/nope.json"

# --- AC5: Mode B routes through the script ----------------------------------
assert_file_contains "$SKILL" "scripts/variant-holdout.py split" "SKILL.md: Mode B splits before spawning"
assert_file_contains "$SKILL" "scripts/variant-holdout.py verdict" "SKILL.md: Mode B judges through the verdict"
assert_prose_contains "$SKILL" "never tune on the holdout" "SKILL.md: Mode B forbids tuning on the holdout"
assert_prose_contains "$SKILL" '`unchanged`, `previous` and `candidate`' "SKILL.md: Mode B names the three arms"
assert_file_contains "$SKILL" "Verdict: promote" "SKILL.md: Mode B promotes only on a promote verdict"

finish
