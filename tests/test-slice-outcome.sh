#!/bin/bash
# tests/test-slice-outcome.sh — .agents/skills/build/scripts/slice_outcome.py
# (specs/slice-three-outcomes.md AC1, AC2): Slice Close records the sub-agent's
# claim, the orchestrator's own verification run and the slice result as three
# True/False/Unknown values; only SUCCEEDED (exit 0) closes a slice, and the
# verification result can come from nowhere but a command the script ran.
. "$(dirname "$0")/lib.sh"

PY="$TEST_PYTHON"   # resolved once in tests/lib.sh
SCRIPT="$(under_test .agents/skills/build/scripts/slice_outcome.py)"
BOX="$(fixture_dir)"

# A stand-in verification command: exits with its first argument and, for the
# refusal case, prints cached-suite's refusal line on stderr.
cat > "$BOX/check.sh" <<'EOF'
printf 'check ran\n'
[ "${2:-}" = "refuse" ] && printf 'cached-suite: a suite is already running (pid 1, since x)\n' >&2
exit "$1"
EOF
outcome() { run "$PY" "$SCRIPT" "$@"; }

begin_case "derivation table"
outcome --agent true -- bash "$BOX/check.sh" 0
assert_exit 0 "SUCCEEDED: agent true and verification exit 0 closes the slice"
assert_contains "$output" "slice-outcome: agent_result=True verification_result=True slice_result=True SUCCEEDED" \
  "SUCCEEDED: the outcome line carries all three results"
assert_contains "$output" "check ran" "the verification command's own output passes through"

outcome --agent true -- bash "$BOX/check.sh" 1
assert_exit 1 "VERIFICATION_FAILED: a green claim over a red run exits 1, so the slice stays open"
assert_contains "$output" "agent_result=True verification_result=False slice_result=False VERIFICATION_FAILED" \
  "VERIFICATION_FAILED: the agent's green claim does not override the orchestrator's red run"
assert_contains "$output" "slice-outcome: verification: \`bash $BOX/check.sh 1\` exited 1" \
  "VERIFICATION_FAILED: the detail line names the command and its status"

outcome --agent false -- bash "$BOX/check.sh" 1
assert_exit 1 "a red run is VERIFICATION_FAILED whatever the agent claimed"
assert_contains "$output" "slice_result=False VERIFICATION_FAILED" "agent false, verification false"

outcome --agent false -- bash "$BOX/check.sh" 0
assert_exit 1 "AGENT_FAILED: an unfinished criterion keeps the slice open over a green run"
assert_contains "$output" "agent_result=False verification_result=True slice_result=False AGENT_FAILED" \
  "AGENT_FAILED: the outcome line"

outcome --agent unknown -- bash "$BOX/check.sh" 0
assert_exit 3 "AGENT_UNKNOWN: no usable report from the sub-agent is Unknown, exit 3"
assert_contains "$output" "agent_result=Unknown verification_result=True slice_result=Unknown AGENT_UNKNOWN" \
  "AGENT_UNKNOWN: the outcome line"
end_case

begin_case "verification comes only from a run"
outcome --agent true
assert_exit 3 "no command: verification is Unknown and the slice stays open"
assert_contains "$output" "agent_result=True verification_result=Unknown slice_result=Unknown NOT_VERIFIED" \
  "no command: a green claim alone is NOT_VERIFIED"
assert_contains "$output" "slice-outcome: not checked: verification — no verification command was given" \
  "no command: the skip carries a reason"

outcome --agent true -- bash "$BOX/check.sh" 3 refuse
assert_exit 3 "a cached-suite refusal is Unknown, never False"
assert_contains "$output" "verification_result=Unknown slice_result=Unknown NOT_VERIFIED" \
  "refusal: nothing ran, so NOT_VERIFIED"
assert_contains "$output" "not checked: verification — cached-suite: a suite is already running" \
  "refusal: the reason is the refusal line"

outcome --agent true -- bash "$BOX/check.sh" 3
assert_exit 1 "exit 3 without the cached-suite line is a failure, not a refusal"
assert_contains "$output" "slice_result=False VERIFICATION_FAILED" "exit 3 alone: VERIFICATION_FAILED"

outcome --agent true -- "$BOX/no-such-command"
assert_exit 1 "a command that cannot start is a failed verification"
assert_contains "$output" "slice_result=False VERIFICATION_FAILED" "missing command: VERIFICATION_FAILED"

for flag in --verification --verification-result --tests --quoted-output; do
  outcome --agent true "$flag" true -- bash "$BOX/check.sh" 0
  assert_exit 2 "no option accepts a verification claim: $flag is refused"
done
end_case

begin_case "usage"
outcome --agent maybe -- bash "$BOX/check.sh" 0
assert_exit 2 "an --agent value other than true, false or unknown is refused"
outcome -- bash "$BOX/check.sh" 0
assert_exit 2 "--agent is required"
end_case

finish
