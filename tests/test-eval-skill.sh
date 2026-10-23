#!/bin/bash
# tests/test-eval-skill.sh — /eval ships runnable, and its grader cannot lie.
#
# Three classes of invariant, matching the three ways this skill dies:
#
#   1. DISTRIBUTION — both trees carry SKILL.md, the grader, and the recipe, and
#      the grader is tracked executable. A skill that ships to one tree only is
#      not reachable from the harness that reads the other.
#
#   2. GRADER HONESTY — the grader's whole job is refusing to count a load that
#      did not happen. A grader that reports NONE when it cannot read the
#      transcript, or FIRED because the candidate printed a filename, produces
#      confident garbage. Every case below is a way it could be wrong and stay
#      silent.
#
#   3. PROVENANCE — the blinding rules are adapted from MIT-licensed pstack
#      material, so the notice travels with the skill in both trees and the
#      source stays registered for drift.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

GRADER="$(under_test .agents/skills/eval/scripts)/grade-skill-loads.sh"
REVIEW_EVAL="$(under_test tests/fixtures/review-eval)"

# --- 1. distribution --------------------------------------------------------
for tree in .agents; do
  assert_file_exists "$tree/skills/eval/SKILL.md" \
    "$tree/skills/eval/SKILL.md exists"
  assert_file_exists "$tree/skills/eval/references/probe-recipe.md" \
    "$tree/skills/eval: probe recipe ships"
  # Two independent failures. Mode is read from the git index, not the
  # filesystem — Windows checkouts do not carry the executable bit and would
  # fail for an unrelated reason — but an index-only check passes on a tree
  # where the script itself was deleted, so on-disk presence is asserted too.
  assert_file_exists "$tree/skills/eval/scripts/grade-skill-loads.sh" \
    "$tree/skills/eval: grader is on disk"
  assert_eq "100755" "$(git ls-files -s "$tree/skills/eval/scripts/grade-skill-loads.sh" | awk '{print $1}')" \
    "$tree/skills/eval: grader is tracked executable"
done

# --- 2. doc invariants ------------------------------------------------------
# The scope table is the one section a future editor is most likely to "helpfully"
# complete by re-adding presence/absence as a third mode. It is not measurable
# where a global install exists, and a run designed against it reports noise.
for tree in .agents; do
  md="$tree/skills/eval/SKILL.md"
  assert_file_contains "$md" "THE CANDIDATE NEVER KNOWS IT IS BEING EVALUATED" \
    "$md: the Iron Law survives"
  assert_file_contains "$md" "presence/absence" \
    "$md: names the unavailable mode instead of omitting it"
  assert_prose_contains "$md" "spawn-time snapshot" \
    "$md: states why ablation cannot work here"
  assert_prose_contains "$md" "**in the prompt**" \
    "$md: fixture state goes in the prompt, not the repo"
  assert_file_contains "$md" "scripts/grade-skill-loads.sh" \
    "$md: grading routes through the grader"
  assert_prose_contains "$tree/skills/eval/references/probe-recipe.md" \
    "don't push anything or open a PR" \
    "$tree/skills/eval: recipe carries the no-push clause"
done

# --- 3. grader honesty ------------------------------------------------------
TMP="$(fixture_dir)"

# A genuine load: the tool-use shape observed in real transcripts.
printf '%s\n' '{"type":"assistant","content":[{"type":"tool_use","id":"toolu_01x","name":"Skill","input":{"skill":"debug"}}]}' \
  > "$TMP/agent-aaa.jsonl"

# The false positive this grader exists to refuse: the candidate talks about the
# skill and prints its path, and loads nothing.
{
  printf '%s\n' '{"type":"text","text":"I will follow the debug process in .agents/skills/debug/SKILL.md"}'
  printf '%s\n' '{"type":"text","text":"ok tests/test-debug.sh -- printed SKILL.md again"}'
} > "$TMP/agent-bbb.jsonl"

# A misroute: something loaded, but not the skill under test.
printf '%s\n' '{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"verify","args":"x"}}]}' \
  > "$TMP/agent-ccc.jsonl"

run bash "$GRADER" "$TMP" debug
assert_exit 0 "grader: exits 0 on a readable run"
out="$output"
assert_contains "$out" "FIRED      agent-aaa" "grader: counts a real Skill tool-use block"
assert_contains "$out" "NONE       agent-bbb" "grader: prose naming a SKILL.md path is not a load"
assert_contains "$out" "MISROUTED  agent-ccc" "grader: a different skill loaded reads as MISROUTED"
assert_contains "$out" "loaded: verify" "grader: names what was loaded instead of the target"
assert_contains "$out" "-> debug: 1/3 FIRED, 1 MISROUTED, 1 NONE" "grader: summary counts every run"

# Listing mode: no target skill, so every load is reported and nothing is graded.
listing="$(bash "$GRADER" "$TMP")"
assert_contains "$listing" "agent-aaa  debug" "grader: listing mode reports loads per candidate"
assert_contains "$listing" "agent-bbb  -" "grader: listing mode marks an empty candidate"
assert_not_contains "$listing" "FIRED" "grader: listing mode does not grade"

# --- the three ways a silent zero could be reported as a result -------------
assert_refused 2 "grade-skill-loads:" "grader: a bad transcript path is an error, not zero loads" -- bash "$GRADER" "$TMP/nope" debug

EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
assert_refused 2 "grade-skill-loads:" "grader: a directory with no transcripts is an error, not zero loads" -- bash "$GRADER" "$EMPTY" debug

# Transcript format drift: a Skill tool-use block the extractor cannot parse
# must be loud. Reporting NONE here is the false negative that scored 11 skills
# wrong. The fixture is a tool_use block whose input key moved — the drift the
# guard is for — not a bare `"name":"Skill"`, which the schema fixture below
# shows is ordinary transcript content.
MOVED="$TMP/moved"; mkdir -p "$MOVED"
printf '%s\n' '{"content":[{"type":"tool_use","name":"Skill","parameters":{"skillName":"debug"}}]}' \
  > "$MOVED/agent-ddd.jsonl"
assert_refused 2 "transcript format changed" "grader: an unreadable Skill block is an error, not NONE" -- bash "$GRADER" "$MOVED" debug
err="$output"
assert_contains "$err" "transcript format changed" "grader: says what broke"

# The tool schema rides inline in every transcript as `{"name":"Skill",
# "description":...}`. That is not a load and not drift: a bare-name anchor
# made eight clean transcripts die as "format changed" on 2026-09-16, so a run
# in which nobody loaded anything produced zero measurements instead of 8 NONE.
SCHEMA="$TMP/schema"; mkdir -p "$SCHEMA"
printf '%s\n' '{"tools":[{"name":"Skill","description":"Invoke a skill.","schema":{"name":"Skill"}}]}' \
  > "$SCHEMA/agent-eee.jsonl"
run bash "$GRADER" "$SCHEMA" debug
assert_exit 0 "grader: the inline tool schema is not an unreadable block"
out="$output"
assert_contains "$out" "NONE       agent-eee" "grader: the inline tool schema grades as no load"

# A real tool-use block serialised name-before-type escapes the extractor. The
# drift guard must still catch it: an error, never a silent NONE.
REORDERED="$TMP/reordered"; mkdir -p "$REORDERED"
printf '%s\n' '{"content":[{"name":"Skill","type":"tool_use","input":{"skill":"debug"}}]}' \
  > "$REORDERED/agent-fff.jsonl"
assert_refused 2 "transcript format changed" "grader: a name-before-type Skill block is an error, not NONE" -- bash "$GRADER" "$REORDERED" debug
err="$output"
assert_contains "$err" "transcript format changed" "grader: reordered keys are reported as drift"

assert_true "grader: parses under bash -n" -- bash -n "$GRADER"

# --- 4. provenance ----------------------------------------------------------
for tree in .agents; do
  assert_file_exists "$tree/skills/eval/LICENSE.pstack" \
    "$tree/skills/eval: upstream MIT notice travels with the skill"
  assert_file_contains "$tree/skills/eval/LICENSE.pstack" "Copyright (c) 2026 Lauren Tan" \
    "$tree/skills/eval: notice names the upstream copyright holder"
  assert_file_contains "$tree/skills/eval/SKILL.md" "poteto-mode/playbooks/eval.md" \
    "$tree/skills/eval: SKILL.md names the upstream source file"
  assert_file_contains "$tree/skills/eval/SKILL.md" "68836ddaf5697224520f1847d90cdb90ca8babaa" \
    "$tree/skills/eval: SKILL.md pins the adapted revision"
done

assert_file_contains "THIRD_PARTY_NOTICES.md" "pstack/skills/poteto-mode/playbooks/eval.md" \
  "notices: repository-level provenance names the eval playbook"
assert_file_contains ".github/upstreams.json" '"id": "pstack-eval-playbook"' \
  "registry: the eval playbook is watched for upstream drift"
assert_file_contains ".github/upstreams.json" "pstack/skills/poteto-mode/playbooks/eval.md" \
  "registry: scopes eval provenance to the playbook path"

# --- 5. the seeded review fixture the Mode B A/B hands candidates -----------
# specs/review-load-and-failure-cases.md AC 8 and its pending slice 8: four
# seeded diffs and the answer key the /eval A/B is graded against. The key names
# lines by number, so a diff edited after the key was written would grade every
# reviewer against the wrong line. Pin each cited line to the diff's own text.
diff_line() { sed -n "${2}p" "$REVIEW_EVAL/$1" | tr -d '\r'; }
for diff in invite-redeem order-summary billing-cutoff settings-merge; do
  assert_file_exists "$REVIEW_EVAL/$diff.diff" "review fixture: $diff.diff is on disk"
  assert_file_contains "$REVIEW_EVAL/expected.md" "## $diff.diff" "review fixture: the key has a section for $diff.diff"
  assert_not_contains "$(<"$REVIEW_EVAL/$diff.diff")" "eval" "review fixture: $diff.diff gives a candidate no hint that it is an eval"
done
assert_eq '+    if invite.redeemed_at is not None:' "$(diff_line invite-redeem.diff 20)" "review fixture: invite-redeem diff line 20 is the check line the key names"
assert_eq '+    invite.redeemed_at = datetime.now(timezone.utc)' "$(diff_line invite-redeem.diff 25)" "review fixture: invite-redeem diff line 25 is the write line the key names"
assert_eq '+        customer = crm_client.get_customer(order.customer_id)' "$(diff_line order-summary.diff 24)" "review fixture: order-summary diff line 24 is the per-order call the key names"
assert_eq '+    today = now.date()' "$(diff_line billing-cutoff.diff 23)" "review fixture: billing-cutoff diff line 23 is the UTC date line the key names"
assert_eq '+    return today >= next_charge_date(sub)' "$(diff_line billing-cutoff.diff 24)" "review fixture: billing-cutoff diff line 24 is the related line the key names"
assert_eq '+        except KeyError:' "$(diff_line settings-merge.diff 35)" "review fixture: settings-merge diff line 35 is the suspicious line the key names"

finish
