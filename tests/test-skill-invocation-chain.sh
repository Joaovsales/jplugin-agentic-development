#!/usr/bin/env bash
# tests/test-skill-invocation-chain.sh
#
# Pins the pipeline chain: which skills invoke which other skills.
#
# Why this exists. A triggerability audit (2026-08-28) found that several
# load-bearing skills never fire from an organic user request -- /quality-gate,
# /verify, /learn and /security-scan are reached because an *upstream skill
# invokes them*, not because a user phrases a request that routes to them. That
# makes the chain the actual delivery mechanism for those gates, and it lives
# only in prose. Prose behavior is not mechanically enforced, so a reflow, a
# rewrite, or a well-meaning trim can silently sever a gate and no existing test
# notices: the suite already greps these files for Finding Model fields and doc
# conventions, but nothing asserts that /build still hands off to /quality-gate.
#
# Scope and honest limits. This asserts the handoff is still *written down*, in
# both skill trees. It cannot assert an agent obeys it -- the same limit
# tests/test-model-tiers.sh carries for the model-tier rules, and the same
# reason: a static check is as far as a prose contract can be pinned. A green
# run here means the chain is documented, not that it executed.

set -uo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tests/lib.sh
. tests/lib.sh

# Every assertion runs against both trees. `.agents/` is canonical and `.claude/`
# is the byte-identical copy Claude Code actually reads, so a chain present in
# only one of them is a real defect: the harness in use might be reading the
# copy that lost the handoff.
TREES=".agents .claude"

# ── /build -> /quality-gate ───────────────────────────────────────────────────
# The post-build review gate. /build is the only caller in the normal flow.
for tree in $TREES; do
  f="$tree/skills/build/SKILL.md"
  assert_file_contains "$f" "/quality-gate" \
    "Chain: $tree/build invokes /quality-gate"
done

# ── /build -> software-design-expert-review (quality-gate Phase 3) ────────────
for tree in $TREES; do
  f="$tree/skills/quality-gate/SKILL.md"
  assert_file_contains "$f" "software-design-expert-review" \
    "Chain: $tree/quality-gate dispatches software-design-expert-review"
done

# ── /wrap-up-session -> /learn ───────────────────────────────────────────────
# The learning store's only automatic writer. If this handoff is lost, the store
# silently stops accreting and nothing fails.
for tree in $TREES; do
  f="$tree/skills/wrap-up-session/SKILL.md"
  assert_file_contains "$f" "/learn" \
    "Chain: $tree/wrap-up-session invokes /learn"
done

# ── /wrap-up-session -> /verify --scope e2e ──────────────────────────────────
# CLAUDE.md's Quality Gate requires an e2e walkthrough per user-facing AC. The
# enforcement point is wrap-up-session, not /verify itself.
for tree in $TREES; do
  f="$tree/skills/wrap-up-session/SKILL.md"
  assert_file_contains "$f" "/maintain-verification-skill --scope changed" \
    "Chain: $tree/wrap-up-session reconciles the feature map"
  assert_file_contains "$f" "/verify --scope e2e" \
    "Chain: $tree/wrap-up-session invokes /verify --scope e2e"
  assert_file_contains "$f" "tasks/e2e-log.md" \
    "Chain: $tree/wrap-up-session checks the e2e evidence log"
done


# ── user-facing build/wrap-up -> changed map -> e2e --------------------------
# Maintenance must precede live verification so the walkthrough reads the map
# produced for the current session, not yesterday's behavior.
for tree in $TREES; do
  for skill in build wrap-up-session; do
    f="$tree/skills/$skill/SKILL.md"
    maintain_line=$(grep -nF "/maintain-verification-skill --scope changed" "$f" | head -1 | cut -d: -f1)
    verify_line=$(grep -niF 'invoke `/verify --scope e2e`' "$f" | head -1 | cut -d: -f1)
    review_line=$(grep -nE '^## (Phase 3|Step 4) .*Quality Gate|^## Step 4 .*Code Review' "$f" | head -1 | cut -d: -f1)
    full_test_line=$(grep -nE '^## Phase 2 .*Full Suite|^## Step 6 .*Run Tests' "$f" | head -1 | cut -d: -f1)
    assert_file_contains "$f" "/maintain-verification-skill --scope changed" \
      "Chain: $tree/$skill names changed-scope maintenance"
    assert_file_matches "$f" '`blocked`.*STOP' \
      "Chain: $tree/$skill stops when maintenance is blocked"
    if [ -n "${maintain_line:-}" ] && [ -n "${verify_line:-}" ] && [ "$maintain_line" -lt "$verify_line" ]; then
      assert_eq "before" "before" "Chain: $tree/$skill maintains before e2e"
    else
      assert_eq "maintenance before e2e" "${maintain_line:-missing} / ${verify_line:-missing}" \
        "Chain: $tree/$skill maintains before e2e"
    fi
    if [ -n "${maintain_line:-}" ] && [ -n "${full_test_line:-}" ] && [ "$maintain_line" -lt "$full_test_line" ]; then
      assert_eq "before" "before" "Chain: $tree/$skill maintains before full tests"
    else
      assert_eq "maintenance before full tests" "${maintain_line:-missing} / ${full_test_line:-missing}" \
        "Chain: $tree/$skill maintains before full tests"
    fi
    if [ -n "${maintain_line:-}" ] && [ -n "${review_line:-}" ] && [ "$maintain_line" -lt "$review_line" ]; then
      assert_eq "before" "before" "Chain: $tree/$skill maintains before review"
    else
      assert_eq "maintenance before review" "${maintain_line:-missing} / ${review_line:-missing}" \
        "Chain: $tree/$skill maintains before review"
    fi
  done
done

# Stop is a shell cleanup/warning hook, not an agentic editing lifecycle.
for hook in .claude/hooks/*stop*.sh; do
  assert_file_not_matches "$hook" 'maintain-verification-skill|create-verification-skill' \
    "Chain: $hook does not invoke verification-skill maintenance"
done

# ── discoverability and two-speed maintenance --------------------------------
for doc in README.md CLAUDE.md; do
  assert_file_contains "$doc" "/create-verification-skill" \
    "Docs: $doc lists the verification-skill creator"
  assert_file_contains "$doc" "/maintain-verification-skill" \
    "Docs: $doc lists verification-skill maintenance"
  assert_file_contains "$doc" "--scope changed" \
    "Docs: $doc explains changed-scope maintenance"
  assert_file_contains "$doc" "full audit" \
    "Docs: $doc distinguishes full maintenance"
done

assert_file_contains .claude/hooks/session-start.sh "/create-verification-skill" \
  "Banner: lists the verification-skill creator"
assert_file_contains .claude/hooks/session-start.sh "/maintain-verification-skill" \
  "Banner: lists verification-skill maintenance"
assert_file_contains .claude/hooks/session-start.sh "--scope changed" \
  "Banner: identifies incremental maintenance"

# ── /auto-push and /yolo -> the phases they promise ──────────────────────────
# Both advertise an autonomous pipeline in their own descriptions. If a stage
# name is dropped, the skill silently stops doing what it claims.
for tree in $TREES; do
  for skill in auto-push yolo; do
    f="$tree/skills/$skill/SKILL.md"
    assert_file_contains "$f" "/plan" \
      "Chain: $tree/$skill runs /plan"
    assert_file_contains "$f" "/build" \
      "Chain: $tree/$skill runs /build"
    assert_file_contains "$f" "/wrap-up-session" \
      "Chain: $tree/$skill runs /wrap-up-session"
  done
done

# ── /wrap-up-session -> /task-registry reconcile ─────────────────────────────
# Reconciliation is only reached because wrap-up runs it; nothing else in the
# normal flow does. Sever this handoff and the index silently drifts from the
# tracker again, which is the exact failure the registry was built to end.
for tree in $TREES; do
  f="$tree/skills/wrap-up-session/SKILL.md"
  assert_file_contains "$f" "task-registry.py reconcile" \
    "Chain: $tree/wrap-up-session reconciles the task index"
done

# ── /plan -> /task-registry, after approval and never before ────────────────
for tree in $TREES; do
  f="$tree/skills/plan/SKILL.md"
  assert_file_contains "$f" "/task-registry" \
    "Chain: $tree/plan registers tasks through the registry"
  assert_file_contains "$f" "never creates an external issue implicitly" \
    "Chain: $tree/plan states that planning creates no external issue on its own"
done

# ── /auto-improve -> TDD + PR, its two advertised guarantees ─────────────────
for tree in $TREES; do
  f="$tree/skills/auto-improve/SKILL.md"
  assert_file_contains "$f" "route_issue.py" \
    "Chain: $tree/auto-improve chooses its workflow through the shared route engine"
done

finish
