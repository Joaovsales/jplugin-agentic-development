#!/bin/bash
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

for tree in .agents .claude; do
  debug="$tree/skills/debug/SKILL.md"
  build="$tree/skills/build/SKILL.md"
  verify="$tree/skills/verify/SKILL.md"
  wrap="$tree/skills/wrap-up-session/SKILL.md"
  prompt="$tree/skills/wrap-up-session/references/routine-prompts/fix.md"

  assert_file_matches "$debug" '^### Canonical unattended escalation owner' \
    "AC2: $tree/debug defines one escalation owner"
  assert_eq "1" "$(grep -c 'task-registry.py escalate' "$debug" || true)" \
    "AC2: $tree/debug states the escalation command once"
  assert_eq "4" "$(grep -c 'Canonical unattended escalation owner' "$debug" || true)" \
    "AC2: $tree/debug routes all four reproduction stop sites to the owner"
  assert_prose_contains "$debug" "Reproduction confirmed" \
    "AC1: $tree/debug retains the reproduced path"
  assert_prose_contains "$debug" "continue to Phase 2" \
    "AC1: $tree/debug continues when work is progressable"

  assert_prose_contains "$build" "practical obstacle" \
    "AC2: $tree/build distinguishes an execution blocker from a regression"
  assert_prose_contains "$build" "Canonical unattended escalation owner" \
    "AC2: $tree/build hands fix-routine blockers to debug's owner"
  assert_prose_contains "$build" 'verification-blocked` with `reproduction-state=reproduced' \
    "AC2: $tree/build preserves confirmed reproduction in a valid escalation pair"
  assert_prose_contains "$verify" "structured blocked outcome" \
    "AC2: $tree/verify returns blocked evidence to its caller"
  assert_prose_contains "$verify" "must not invoke" \
    "AC9: $tree/verify does not create a second escalation"
  assert_prose_contains "$wrap" "investigation escalation" \
    "AC9: $tree/wrap-up recognizes the no-PR escalation terminal"
  assert_prose_contains "$wrap" "Do not run Step 8.5" \
    "AC9: $tree/wrap-up does not replace the escalation result with a PR assertion"
  assert_prose_contains "$wrap" "structured blocked outcome" \
    "AC9: $tree/wrap-up routes its own blocked E2E result to the canonical owner"
  assert_prose_contains "$wrap" "do not offer acknowledgement" \
    "AC9: $tree/wrap-up cannot acknowledge past a fix-routine verification blocker"

  assert_contains "$(cat "$prompt")" "task-registry escalate" \
    "AC2: $tree/fix prompt names the canonical escalation command"
  lines="$(wc -l < "$prompt" | tr -d ' ')"
  [ "$lines" -lt 25 ]; assert_eq "0" "$?" \
    "AC13: $tree/fix prompt remains under 25 lines"
done

assert_files_identical .agents/skills/debug/SKILL.md .claude/skills/debug/SKILL.md \
  "AC13: debug mirrors are byte-identical"
assert_files_identical .agents/skills/build/SKILL.md .claude/skills/build/SKILL.md \
  "AC13: build mirrors are byte-identical"
assert_files_identical .agents/skills/verify/SKILL.md .claude/skills/verify/SKILL.md \
  "AC13: verify mirrors are byte-identical"
assert_files_identical .agents/skills/wrap-up-session/SKILL.md .claude/skills/wrap-up-session/SKILL.md \
  "AC13: wrap-up mirrors are byte-identical"

contract=.agents/skills/wrap-up-session/references/routines.md
assert_prose_contains "$contract" "investigation escalation" \
  "AC9: routine contract records the fix-only no-PR terminal"
assert_prose_contains "$contract" "exactly once" \
  "AC9: routine contract assigns one escalation owner"
assert_prose_contains .agents/skills/sweep/SKILL.md "human re-triage clears the hold" \
  "AC13: producers retain held tasks instead of replacing them"

for spec in specs/sweep-routines.md specs/category-routines.md specs/workflow-routing.md; do
  assert_prose_contains "$spec" "needs-investigation" \
    "AC13: $spec reflects the rollout hold"
done

finish
