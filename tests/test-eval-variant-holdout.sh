#!/bin/bash
# variant-holdout.py: /eval Mode B splits its prompts into a tuning set and a
# never-tuned holdout, and promotes a variant only when its holdout mean beats
# both the unchanged skill and the variant's previous version. `split` writes a
# manifest before tuning and `verdict` is bound to it, so no prompt can be
# added or dropped between the split and the verdict
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

# scores <manifest.json> <out> <tuning u,p,c> <holdout u,p,c> [skip-cost-arm] [drop-arm]
# One graded run per prompt and arm, scored by the set `split` put the prompt
# in; two runs per prompt for the candidate, so per-prompt averaging is used.
# skip-cost-arm leaves cost out of that arm's first run only, so one silent
# run among reported ones is what must read unknown.
scores() {
  "$TEST_PYTHON" - "$@" <<'PY'
import json, sys
manifest, out, tuning, holdout = sys.argv[1:5]
skip_cost = sys.argv[5] if len(sys.argv) > 5 else ""
drop = sys.argv[6] if len(sys.argv) > 6 else ""
split = json.load(open(manifest))
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
SIXM="$TMP/six.manifest.json"

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
printf '{"tuning": ["%s", "%s"], "holdout": ["%s"]}\n' "${SIX[@]:0:3}" > "$TMP/three.manifest.json"
assert_refused 2 "at least 4 distinct prompts" "verdict: a scored run over three prompts is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/three.manifest.json" "$TMP/three.jsonl"
assert_not_contains "$output" "Verdict:" "verdict: a refused run prints no verdict"

# --- the split: half held out, deterministic over the prompt set -------------
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

# --- the manifest: the split, pinned before tuning --------------------------
run "$TEST_PYTHON" "$TOOL" split "$TMP/six.json" --manifest "$SIXM"
assert_exit 0 "split: --manifest writes the split"
assert_eq "$first" "$("$TEST_PYTHON" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({"tuning": d["tuning"], "holdout": d["holdout"]}, indent=2))' "$SIXM")" \
  "split: the manifest holds the same membership split prints"
assert_refused 2 "already exists" "split: an existing manifest is never overwritten" -- "$TEST_PYTHON" "$TOOL" split "$TMP/six.json" --manifest "$SIXM"
assert_refused 2 "arguments are required" "verdict: a run without a manifest is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/three.jsonl"

# --- AC3: a variant that wins only on the tuning set is rejected -------------
scores "$SIXM" "$TMP/tuning-win.jsonl" 0.6,0.55,0.9 0.6,0.55,0.5
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/tuning-win.jsonl"
assert_exit 0 "verdict: a reject is a measurement, not an error"
assert_contains "$output" "Verdict: reject" "verdict: a tuning-only win is rejected"
assert_contains "$output" "does not beat unchanged" "verdict: the reject names the baseline it lost to"
assert_contains "$output" "| candidate | 0.9000 | 0.5000 |" "verdict: the report shows the tuning win beside the holdout loss"
tuning_win="$output"

scores "$SIXM" "$TMP/holdout-win.jsonl" 0.6,0.55,0.5 0.6,0.55,0.8
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/holdout-win.jsonl"
assert_contains "$output" "Verdict: promote" "verdict: beating both baselines on the holdout promotes"

scores "$SIXM" "$TMP/one-baseline.jsonl" 0.6,0.55,0.9 0.6,0.75,0.7
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/one-baseline.jsonl"
assert_contains "$output" "Verdict: reject" "verdict: beating only the unchanged skill is rejected"
assert_contains "$output" "does not beat previous" "verdict: names the previous version as the baseline not beaten"

# 0.3 is the tie whose candidate mean, (0.4 + 0.2) / 2, lands a float ulp above 0.3.
scores "$SIXM" "$TMP/tie.jsonl" 0.6,0.55,0.9 0.25,0.3,0.3
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/tie.jsonl"
assert_contains "$output" "Verdict: reject" "verdict: a tie with a baseline is not a win"

# --- AC2: the report shows both baselines on the holdout, and the split ------
assert_contains "$tuning_win" "| unchanged | 0.6000 | 0.6000 |" "report: the unchanged baseline's holdout mean"
assert_contains "$tuning_win" "| previous | 0.5500 | 0.5500 |" "report: the previous version's holdout mean"
assert_contains "$tuning_win" "3 tuning, 3 holdout" "report: states the split"
assert_contains "$tuning_win" "${SIX[0]}" "report: lists the prompts it split"

# --- AC4: unreported cost is unknown, never zero -----------------------------
scores "$SIXM" "$TMP/no-cost.jsonl" 0.6,0.55,0.5 0.6,0.55,0.8 candidate
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/no-cost.jsonl"
assert_contains "$output" "| candidate | 0.5000 | 0.8000 | unknown |" "cost: an arm with an unreported run costs unknown"
assert_contains "$output" "| unchanged | 0.6000 | 0.6000 | 1.5000 |" "cost: a fully reported arm sums its runs"
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/no-cost.jsonl" --json
assert_contains "$output" '"candidate": "unknown"' "cost: --json carries unknown too"

# --- set drift: the verdict is bound to the split-time prompts --------------
# Growth: two prompts added after tuning would move a tuned-on prompt into a
# recomputed holdout; deletion of the holdout prompts would re-split the tuning
# set. Both promote a tuning-only win unless the manifest refuses them.
scores "$SIXM" "$TMP/grown.jsonl" 0.6,0.55,0.9 0.6,0.55,0.5
for extra in "a prompt added after tuning" "another prompt added after tuning"; do
  for arm in unchanged previous candidate; do
    printf '{"prompt": "%s", "arm": "%s", "score": 0.1}\n' "$extra" "$arm" >> "$TMP/grown.jsonl"
  done
done
assert_refused 2 "not in the manifest" "verdict: a prompt added after the split is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/grown.jsonl"
assert_not_contains "$output" "Verdict:" "verdict: a grown run prints no verdict"

"$TEST_PYTHON" - "$SIXM" "$TMP/tuning-win.jsonl" "$TMP/shrunk.jsonl" <<'PY'
import json, sys
holdout = set(json.load(open(sys.argv[1]))["holdout"])
with open(sys.argv[2]) as src, open(sys.argv[3], "w") as out:
    out.writelines(line for line in src if json.loads(line)["prompt"] not in holdout)
PY
assert_refused 2 "has no scored runs" "verdict: dropping the holdout prompts is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/shrunk.jsonl"
assert_not_contains "$output" "Verdict:" "verdict: a shrunk run prints no verdict"

"$TEST_PYTHON" - "$SIXM" "$TMP/swapped.manifest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["tuning"][0], d["holdout"][0] = d["holdout"][0], d["tuning"][0]
json.dump(d, open(sys.argv[2], "w"))
PY
assert_refused 2 "does not match the split rule" "verdict: a manifest edited to move a prompt is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$TMP/swapped.manifest.json" "$TMP/tuning-win.jsonl"

# --- weighting: each prompt weighs the same, however many runs it has --------
# One holdout prompt run ten times at 1.0, one once at 0.0 and one at 0.5:
# the per-prompt mean is 0.5 (reject against 0.6); a flat mean over runs is
# 0.875 and would promote.
"$TEST_PYTHON" - "$SIXM" "$TMP/weighting.jsonl" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
first, second = d["holdout"][:2]
with open(sys.argv[2], "w") as fh:
    def put(prompt, arm, score, times=1):
        for _ in range(times):
            fh.write(json.dumps({"prompt": prompt, "arm": arm, "score": score}) + "\n")
    for prompt in d["tuning"] + d["holdout"]:
        put(prompt, "unchanged", 0.6)
        put(prompt, "previous", 0.6)
    for prompt in d["tuning"]:
        put(prompt, "candidate", 0.9)
    put(first, "candidate", 1.0, times=10)
    put(second, "candidate", 0.0)
    for prompt in d["holdout"][2:]:
        put(prompt, "candidate", 0.5)
PY
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/weighting.jsonl"
assert_contains "$output" "| candidate | 0.9000 | 0.5000 |" "weighting: the holdout mean is the mean of per-prompt means"
assert_contains "$output" "Verdict: reject" "weighting: ten runs of one prompt cannot outvote the others"

run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/weighting.jsonl" --json
weighting="$output"
assert_eq "0.5" "$(printf '%s' "$output" | "$TEST_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["means"]["holdout"]["candidate"])')" \
  "weighting: the exact holdout mean is 0.5"
"$TEST_PYTHON" - "$SIXM" "$TMP/weighting.jsonl" "$TMP/duplicated.jsonl" <<'PYRUNS'
import json, sys
prompt = json.load(open(sys.argv[1]))["holdout"][0]
with open(sys.argv[2]) as src, open(sys.argv[3], "w") as out:
    for line in src:
        record = json.loads(line)
        out.write(line)
        if record["prompt"] == prompt and record["arm"] == "candidate":
            out.write(line)
PYRUNS
run "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/duplicated.jsonl" --json
assert_exit 0 "weighting: duplicating runs is accepted"
assert_eq "$weighting" "$output" "weighting: duplicating a prompt's runs changes neither means nor verdict"

# --- refusals: what the report cannot show is never guessed ------------------
scores "$SIXM" "$TMP/no-previous.jsonl" 0.6,0.55,0.5 0.6,0.55,0.8 "" previous
assert_refused 2 "has no previous run" "verdict: a holdout prompt missing a baseline is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/no-previous.jsonl"

cp "$TMP/holdout-win.jsonl" "$TMP/bad-arm.jsonl"
printf '%s\n' '{"prompt": "x", "arm": "variant-b", "score": 1}' >> "$TMP/bad-arm.jsonl"
assert_refused 2 "unknown arm" "verdict: an arm outside the three is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/bad-arm.jsonl"
assert_contains "$output" "bad-arm.jsonl:25" "verdict: the refusal names the line"

cp "$TMP/holdout-win.jsonl" "$TMP/bad-score.jsonl"
printf '%s\n' '{"prompt": "x", "arm": "candidate", "score": "high"}' >> "$TMP/bad-score.jsonl"
assert_refused 2 "finite number" "verdict: a non-numeric score is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/bad-score.jsonl"

cp "$TMP/holdout-win.jsonl" "$TMP/bad-cost.jsonl"
printf '%s\n' '{"prompt": "x", "arm": "candidate", "score": 1, "cost_usd": -1}' >> "$TMP/bad-cost.jsonl"
assert_refused 2 "cost_usd" "verdict: a negative cost is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/bad-cost.jsonl"

printf '%s\n' '[1, 2]' > "$TMP/not-object.jsonl"
assert_refused 2 "JSON object" "verdict: a line that is not an object is refused" -- "$TEST_PYTHON" "$TOOL" verdict "$SIXM" "$TMP/not-object.jsonl"

printf '%s\n' '["a", 3, "c", "d"]' > "$TMP/bad-prompts.json"
assert_refused 2 "non-empty strings" "split: a prompt that is not a string is refused" -- "$TEST_PYTHON" "$TOOL" split "$TMP/bad-prompts.json"

assert_refused 2 "variant-holdout:" "split: a missing prompts file is an error" -- "$TEST_PYTHON" "$TOOL" split "$TMP/nope.json"

# --- AC5: Mode B routes through the script ----------------------------------
assert_file_contains "$SKILL" "scripts/variant-holdout.py split" "SKILL.md: Mode B splits before spawning"
assert_file_contains "$SKILL" "scripts/variant-holdout.py verdict" "SKILL.md: Mode B judges through the verdict"
assert_file_contains "$SKILL" "split <prompts.json> --manifest <manifest.json>" "SKILL.md: Mode B pins the split in a manifest"
assert_file_contains "$SKILL" "verdict <manifest.json> <scores.jsonl>" "SKILL.md: Mode B binds the verdict to the manifest"
assert_prose_contains "$SKILL" "never tune on the holdout" "SKILL.md: Mode B forbids tuning on the holdout"
assert_prose_contains "$SKILL" '`unchanged`, `previous` and `candidate`' "SKILL.md: Mode B names the three arms"
assert_file_contains "$SKILL" "Verdict: promote" "SKILL.md: Mode B promotes only on a promote verdict"

finish
