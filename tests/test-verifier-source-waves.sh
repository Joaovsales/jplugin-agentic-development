#!/bin/bash
# tests/test-verifier-source-waves.sh — issue #103: the full verifier audit's
# source wave must run under bounded concurrency without weakening coverage.
#
# The old contract read "one read-only subagent per feature concurrently",
# which a nine-feature verifier could not satisfy with three worker slots even
# though every feature was independently reviewed in batches. The contract now
# permits waves sized to available slots, keeps exactly one independent
# read-only review per feature, requires a complete summary for every feature,
# and discloses per feature where independence was unavailable.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

TREES=".agents .claude"

for tree in $TREES; do
  mvs="$tree/skills/maintain-verification-skill/SKILL.md"

  # AC1 — bounded concurrent waves sized to available slots
  assert_prose_contains "$mvs" "bounded waves" \
    "AC1: $tree source wave runs in bounded waves"
  assert_prose_contains "$mvs" "worker slots" \
    "AC1: $tree waves are sized to available worker slots"
  assert_file_not_matches "$mvs" 'one read-only subagent per feature concurrently' \
    "AC1: $tree no longer demands every feature be reviewed at once"

  # AC2 — exactly one independent read-only review per feature
  assert_prose_contains "$mvs" "exactly one independent read-only review" \
    "AC2: $tree keeps exactly one independent review per feature"
  assert_prose_contains "$mvs" "never split across reviewers" \
    "AC2: $tree forbids splitting a feature across reviewers"

  # AC3 — complete per-feature summaries, disclosure of lost independence
  assert_prose_contains "$mvs" "complete summary for every feature" \
    "AC3: $tree requires a complete summary for every feature"
  assert_prose_contains "$mvs" "re-dispatched, not marked reviewed" \
    "AC3: $tree treats a missing summary as a gap, not coverage"
  assert_prose_contains "$mvs" "name each feature" \
    "AC3: $tree discloses lost independence per feature"
  assert_prose_contains "$mvs" "lost corroboration" \
    "AC3: $tree still states the lost corroboration on the inline path"

  # AC4 — worked example: nine features, three slots, coverage intact
  assert_prose_contains "$mvs" "nine features" \
    "AC4: $tree carries the nine-feature example"
  assert_prose_contains "$mvs" "three worker slots" \
    "AC4: $tree sizes the example to three worker slots"
  assert_prose_contains "$mvs" "could not be fully parallelised" \
    "AC4: $tree reserves blocked for unreadable source, not a partial wave"

  # the janitor lens describes the same engine
  lens="$tree/skills/sweep/references/lens-janitor.md"
  assert_prose_contains "$lens" "bounded" \
    "Lens: $tree janitor names the bounded source wave"
done

assert_files_identical \
  ".agents/skills/maintain-verification-skill/SKILL.md" \
  ".claude/skills/maintain-verification-skill/SKILL.md" \
  "Parity: maintain-verification-skill mirrored byte-identically"

finish
