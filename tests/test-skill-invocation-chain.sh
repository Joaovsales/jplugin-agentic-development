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
  assert_file_contains "$f" "/verify --scope e2e" \
    "Chain: $tree/wrap-up-session invokes /verify --scope e2e"
  assert_file_contains "$f" "tasks/e2e-log.md" \
    "Chain: $tree/wrap-up-session checks the e2e evidence log"
done

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

# ── /auto-improve -> TDD + PR, its two advertised guarantees ─────────────────
for tree in $TREES; do
  f="$tree/skills/auto-improve/SKILL.md"
  assert_file_contains "$f" "/build" \
    "Chain: $tree/auto-improve implements via /build"
done

finish
