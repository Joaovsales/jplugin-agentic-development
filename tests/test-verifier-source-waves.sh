#!/bin/bash
# tests/test-verifier-source-waves.sh — issue #103: the full verifier audit's
# source wave runs under bounded concurrency without weakening coverage.
#
# tests/test-verification-skill-integration.sh pins the batching contract on
# the canonical tree. This file covers what it does not: the retired phrase
# stays retired in both trees, a feature is never split across reviewers, the
# janitor lens describes the same engine, and the compat mirror is byte-equal.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

TREES=".agents .claude"

for tree in $TREES; do
  mvs="$tree/skills/maintain-verification-skill/SKILL.md"
  assert_file_not_matches "$mvs" 'one read-only subagent per feature concurrently' \
    "AC1: $tree no longer demands every feature be reviewed at once"
  assert_prose_contains "$mvs" "worker slots" \
    "AC1: $tree sizes the wave to available worker slots"
  assert_prose_contains "$mvs" "no feature is split across reviewers" \
    "AC2: $tree forbids splitting a feature across reviewers"
  assert_prose_contains "$mvs" "lost corroboration" \
    "AC3: $tree states the lost corroboration on the inline path"
  assert_prose_contains "$mvs" "nine features on three slots" \
    "AC4: $tree carries the nine-feature, three-slot example"

  lens="$tree/skills/sweep/references/lens-janitor.md"
  assert_prose_contains "$lens" "bounded by the worker slots" \
    "Lens: $tree janitor names the bounded source wave"
done

assert_files_identical \
  ".agents/skills/maintain-verification-skill/SKILL.md" \
  ".claude/skills/maintain-verification-skill/SKILL.md" \
  "Parity: maintain-verification-skill mirrored byte-identically"

finish
