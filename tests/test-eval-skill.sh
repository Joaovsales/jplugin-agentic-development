#!/bin/bash
# tests/test-eval-skill.sh — /eval ships runnable, and its grader cannot lie.
#
# WHY THIS EXISTS
#
# /eval was authored twice and deployed neither time. The first attempt shipped
# the canonical copy without the `.claude/` copy, so the skill Claude Code
# actually reads did not exist and the parity guard went red; the follow-up
# stacked a fix on top of the broken branch instead of replacing it. Prose about
# how to run an eval is not an eval that runs.
#
# Two classes of invariant, matching the two ways this skill dies:
#
#   1. DISTRIBUTION — both trees carry SKILL.md, the grader, and the recipe, and
#      the grader is tracked executable. A skill whose script did not ship is
#      what `test-syncable-paths.sh` was written for; this pins the same property
#      for the one asset /eval executes.
#
#   2. GRADER HONESTY — the grader's whole job is refusing to count a load that
#      did not happen. The eval that motivated this skill mis-scored 11 of 14
#      skills as "never fired", so the failure mode is not hypothetical: a
#      grader that says NONE when it cannot read the transcript, or FIRED
#      because the candidate printed a filename, produces confident garbage.
#      Every case below is a way that grader could be wrong and stay silent.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

GRADER_REL=".agents/skills/eval/scripts/grade-skill-loads.sh"

# --- 1. distribution --------------------------------------------------------
for tree in .agents .claude; do
  assert_eq "present" "$([ -f "$tree/skills/eval/SKILL.md" ] && echo present || echo missing)" \
    "$tree/skills/eval/SKILL.md exists"
  assert_eq "present" "$([ -f "$tree/skills/eval/references/probe-recipe.md" ] && echo present || echo missing)" \
    "$tree/skills/eval: probe recipe ships"
  # Two independent failures. Mode is read from the git index, not the
  # filesystem — Windows checkouts do not carry the executable bit and would
  # fail for an unrelated reason — but an index-only check passes on a tree
  # where the script itself was deleted, so on-disk presence is asserted too.
  assert_eq "present" "$([ -f "$tree/skills/eval/scripts/grade-skill-loads.sh" ] && echo present || echo missing)" \
    "$tree/skills/eval: grader is on disk"
  assert_eq "100755" "$(git ls-files -s "$tree/skills/eval/scripts/grade-skill-loads.sh" | awk '{print $1}')" \
    "$tree/skills/eval: grader is tracked executable"
done

# --- 2. doc invariants ------------------------------------------------------
# The scope table is the one section a future editor is most likely to "helpfully"
# complete by re-adding presence/absence as a third mode. It is not measurable
# where a global install exists, and a run designed against it reports noise.
for tree in .agents .claude; do
  md="$tree/skills/eval/SKILL.md"
  assert_file_contains "$md" "THE CANDIDATE NEVER KNOWS IT IS BEING EVALUATED" \
    "$md: the Iron Law survives"
  assert_file_contains "$md" "presence/absence" \
    "$md: names the unavailable mode instead of omitting it"
  assert_prose_contains "$md" "the roster is a spawn-time snapshot" \
    "$md: states why ablation cannot work here"
  assert_prose_contains "$md" "Carry the precondition **in the prompt**" \
    "$md: fixture state goes in the prompt, not the repo"
  assert_file_contains "$md" "scripts/grade-skill-loads.sh" \
    "$md: grading routes through the grader"
  assert_prose_contains "$tree/skills/eval/references/probe-recipe.md" \
    "don't push anything or open a PR" \
    "$tree/skills/eval: recipe carries the no-push clause"
done

# --- 3. grader honesty ------------------------------------------------------
TMP="$(mktemp -d)"
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf '  FAIL could not create fixture dir\n'; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# A genuine load: the tool-use shape observed in real transcripts.
printf '%s\n' '{"type":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"debug"}}]}' \
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

out="$(bash "$GRADER_REL" "$TMP" debug)"; rc=$?
assert_eq "0" "$rc" "grader: exits 0 on a readable run"
assert_contains "$out" "FIRED      agent-aaa" "grader: counts a real Skill tool-use block"
assert_contains "$out" "NONE       agent-bbb" "grader: prose naming a SKILL.md path is not a load"
assert_contains "$out" "MISROUTED  agent-ccc" "grader: a different skill loaded reads as MISROUTED"
assert_contains "$out" "loaded: verify" "grader: names what was loaded instead of the target"
assert_contains "$out" "-> debug: 1/3 FIRED, 1 MISROUTED, 1 NONE" "grader: summary counts every run"

# Listing mode: no target skill, so every load is reported and nothing is graded.
listing="$(bash "$GRADER_REL" "$TMP")"
assert_contains "$listing" "agent-aaa  debug" "grader: listing mode reports loads per candidate"
assert_contains "$listing" "agent-bbb  -" "grader: listing mode marks an empty candidate"
assert_not_contains "$listing" "FIRED" "grader: listing mode does not grade"

# --- the three ways a silent zero could be reported as a result -------------
bash "$GRADER_REL" "$TMP/nope" debug >/dev/null 2>&1
assert_eq "2" "$?" "grader: a bad transcript path is an error, not zero loads"

EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
bash "$GRADER_REL" "$EMPTY" debug >/dev/null 2>&1
assert_eq "2" "$?" "grader: a directory with no transcripts is an error, not zero loads"

# Transcript format drift: a Skill block the extractor cannot parse must be
# loud. Reporting NONE here is the false negative that scored 11 skills wrong.
MOVED="$TMP/moved"; mkdir -p "$MOVED"
printf '%s\n' '{"content":[{"name":"Skill","parameters":{"skillName":"debug"}}]}' \
  > "$MOVED/agent-ddd.jsonl"
err="$(bash "$GRADER_REL" "$MOVED" debug 2>&1)"; rc=$?
assert_eq "2" "$rc" "grader: an unreadable Skill block is an error, not NONE"
assert_contains "$err" "transcript format changed" "grader: says what broke"

assert_eq "" "$(bash -n "$GRADER_REL" 2>&1)" "grader: parses under bash -n"

finish
