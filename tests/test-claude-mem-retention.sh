#!/usr/bin/env bash
# Exercise the retained policy and failure-only semantic detector in CI.
. "$(dirname "$0")/lib.sh"

DOCS="$(under_test docs/claude-mem-retention)"

run "$TEST_PYTHON" "$DOCS/test_retention.py"
assert_exit 0 "retention: age boundaries, verified archives and failure rollback"
assert_contains "$output" "PASS: expiry boundaries" "retention: the policy fixtures actually ran"

run "$TEST_PYTHON" "$DOCS/test_semantic_health.py"
assert_exit 0 "semantic detector: silence, failure signals, privacy and checkpoint tests"
assert_contains "$output" "OK" "semantic detector: unittest executed successfully"

finish
