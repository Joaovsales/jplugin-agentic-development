#!/bin/bash
# tests/test-route-skill.sh — /route's visible workflow and safety contracts.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

A=.agents/skills/route/SKILL.md
C=.claude/skills/route/SKILL.md
PLAYBOOKS="autonomous gated-at-plan gated-at-plan-and-pre-push"

assert_file_contains "$A" "name: route" "Route: canonical skill has route frontmatter"
assert_file_matches "$A" '^description:.*issue.*ticket.*URL.*#123.*backlog' \
  "Route: description exposes every issue-shaped invocation"
assert_files_identical "$A" "$C" "Route: skill is byte-identical across trees"

for lane in $PLAYBOOKS; do
  a=".agents/skills/route/playbooks/$lane.md"
  c=".claude/skills/route/playbooks/$lane.md"
  assert_files_identical "$a" "$c" "Route: $lane playbook is byte-identical"
  assert_file_matches "$a" '^\[ \] prelude:' "Route: $lane keeps the prelude step"
  assert_file_matches "$a" '^\[ \] /plan' "Route: $lane keeps the plan step"
  assert_file_matches "$a" '^\[ \] /build' "Route: $lane keeps the build step"
  assert_file_matches "$a" '^\[ \] route radius tripwire: finalize_route' \
    "Route: $lane materializes the post-build tripwire"
  assert_file_matches "$a" '^\[ \] <verification_step>$' "Route: $lane keeps one supported verify step"
  assert_file_matches "$a" '^\[ \] reviewers:' "Route: $lane keeps the reviewers step"
  assert_file_matches "$a" '^\[ \] reviewers: <reviewers>$' \
    "Route: $lane takes reviewers only from the policy decision"
  reviewer_constants="$(grep -E 'reviewers:.*(code-reviewer|critic)' "$a" 2>/dev/null || true)"
  assert_eq "" "$reviewer_constants" "Route: $lane duplicates no reviewer policy"
  assert_file_matches "$a" '^\[ \] /wrap-up-session' "Route: $lane keeps the wrap-up step"
done

assert_prose_contains "$A" 'perception claim uses this required schema' \
  "Route: perception instructions define the claim boundary"
assert_prose_contains "$A" 'atomically writes `tasks/route-decision.md`' \
  "Route: public operation persists the decision record"
assert_prose_contains "$A" 'before returning' \
  "Route: materialization completes before a lane can execute"
assert_prose_contains "$A" 'lane, autonomy, human_verification, verification_method, and reviewers' \
  "Route: decision record names all five fields"
assert_prose_contains "$A" 'copies the selected playbook verbatim into `tasks/todo.md`' \
  "Route: selected playbook lands before implementation"
assert_prose_contains "$A" 'materialize_route' \
  "Route: one operation owns decision persistence and playbook materialization"
assert_prose_contains "$A" 'Callers never reconstruct a `Task` mapping' \
  "Route: task-registry owns structured task lookup"
assert_file_contains "$A" 'skip: <reason>' "Route: skipped steps require a reason"
assert_prose_contains "$A" 'interactive callers propose the decision and wait' \
  "Route: interactive routing waits for confirmation"
assert_prose_contains "$A" '/task-registry show <task-reference>' \
  "Route: named tasks resolve through task-registry show"
assert_prose_contains "$A" '/task-registry frontier' \
  "Route: next-backlog routing resolves through task-registry frontier"
provider_calls="$(grep -E 'gh |curl|urllib' "$A" 2>/dev/null || true)"
assert_eq "" "$provider_calls" "Route: skill contains no direct tracker client"
assert_prose_contains "$A" 'Refuse a task reported as `blocked` or `unknown-dependency`' \
  "Route: blocked or unknown-dependency tasks are refused"

assert_prose_contains "$A" 'A hung reviewer is reported, never counted as agreement' \
  "Route: hung reviewers cannot corroborate"
assert_prose_contains "$A" 'demotes the run to gated' \
  "Route: a hung reviewer removes autonomy"
assert_prose_contains "$A" '`finalize_reviewers`' \
  "Route: reviewer outcomes are persisted by the policy operation"
assert_prose_contains "$A" 'sole executable source for the inverted autonomous reviewer floor' \
  "Route: engine alone owns the autonomous reviewer floor"
assert_prose_contains "$A" 'Critic uses the planner floor' \
  "Route: critic dispatch preserves its planner floor"
assert_prose_contains "$A" '`check_actual_diff`' \
  "Route: post-build runtime radius tripwire is centralized"
assert_prose_contains "$A" '`finalize_route`' \
  "Route: post-build tripwire persists its safe next lane"
assert_prose_contains "$A" 'derives the real changed paths from the recorded Git baseline' \
  "Route: public finalization does not trust a caller-supplied path list"
assert_prose_contains "$A" 'Carry every unapplied finding into the /wrap-up-session output' \
  "Route: unapplied findings survive into wrap-up"
assert_prose_contains "$A" 'gated_auto and confidence >= 75' \
  "Route: auto-application obeys the Finding Model gate"
assert_prose_contains "$A" 'whether an agent obeys that context under a suppression directive is not observable from disk' \
  "Route: documentation names the residual observability limit"

finish
