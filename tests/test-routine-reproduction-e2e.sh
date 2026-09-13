#!/bin/bash
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO/.agents/skills/task-registry/scripts/task-registry.py"
TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do rm -rf "$d"; done; }
trap cleanup EXIT

new_repo() {
  local target="$1" root
  root="$(mktemp -d)"; TMP_DIRS+=("$root")
  mkdir -p "$root/tasks"; printf '# Tasks\n' > "$root/tasks/todo.md"
  printf -v "$target" '%s' "$root"
}

create_parent() {
  python3 "$CLI" upsert parent.bug --repo "$1" --title 'Reproduce parent bug' \
    --kind bug --summary 'Isolated routine scenario' --label bug \
    --reproduction 'run focused reproduction' --proposed-fix 'repair root cause' \
    --criterion 'focused reproduction passes' --apply >/dev/null
}

# Reproduced and progressable: the real workflow/selector surface keeps the
# issue on the ordinary fix path, and no escalation artifact exists.
new_repo FIXABLE; create_parent "$FIXABLE"
workflow="$(python3 "$CLI" workflow parent.bug --repo "$FIXABLE" 2>&1)"; workflow_code=$?
selected="$(python3 "$CLI" select --routine fix --repo "$FIXABLE" 2>&1)"; select_code=$?
assert_eq "0" "$workflow_code" "AC14: reproduced/fixable parent resolves normally"
assert_contains "$workflow" "fix" "AC1: reproduced/fixable parent stays on the fix workflow"
assert_eq "0" "$select_code" "AC1: reproduced/fixable parent remains selectable"
assert_contains "$selected" "parent.bug" "AC1: selector returns the progressable parent"
assert_eq "absent" "$([ -d "$FIXABLE/tasks/routine-runs" ] && echo present || echo absent)" \
  "AC1: progressable work creates no escalation artifact"

# Inconclusive reproduction: apply a real escalation and prove subsequent
# selection excludes the held parent.
new_repo INCONCLUSIVE; create_parent "$INCONCLUSIVE"
inconclusive="$(python3 "$CLI" escalate parent.bug --repo "$INCONCLUSIVE" \
  --reason inconclusive --reproduction-state not-reproduced \
  --run-at 2026-09-12T12:00:00-03:00 --repro-command 'run focused reproduction' \
  --observed 'expected failure did not occur' --evidence-unavailable 'runner emitted no retained log' \
  --apply 2>&1)"; inconclusive_code=$?
held_select="$(python3 "$CLI" select --routine fix --repo "$INCONCLUSIVE" 2>&1)"; held_select_code=$?
assert_eq "1" "$inconclusive_code" "AC9: inconclusive escalation terminates non-zero"
assert_contains "$inconclusive" "hold: confirmed" "AC14: inconclusive run confirms its hold"
assert_eq "0" "$held_select_code" "AC14: an all-held candidate pool is an ordinary empty selection"
assert_not_contains "$held_select" "parent.bug" "AC14: selection skips the inconclusive parent"
assert_eq "1" "$(find "$INCONCLUSIVE/tasks/routine-runs" -type f | wc -l)" \
  "AC14: inconclusive run retains one artifact"

# The test cannot start: a valid routine blocker is created and remains eligible
# while the originating parent is held.
new_repo EXECUTION; create_parent "$EXECUTION"
cat > "$EXECUTION/blocker.json" <<'JSON'
{"version":1,"source":"tests/runner.sh","title":"Restore test runtime","summary":"The runtime executable is missing","handling":"routine","reproduction":["run focused reproduction"],"proposed_fix":["restore the declared runtime"],"criteria":["reproduction reaches its assertion"]}
JSON
execution="$(python3 "$CLI" escalate parent.bug --repo "$EXECUTION" \
  --reason execution-blocked --reproduction-state unverified \
  --run-at 2026-09-12T13:00:00-03:00 --repro-command 'run focused reproduction' \
  --observed 'runtime executable was not found' --evidence "$EXECUTION/blocker.json" \
  --blocker-file "$EXECUTION/blocker.json" --apply 2>&1)"; execution_code=$?
execution_select="$(python3 "$CLI" select --routine fix --repo "$EXECUTION" 2>&1)"; execution_select_code=$?
assert_eq "1" "$execution_code" "AC9: execution blocker escalation terminates non-zero"
assert_contains "$execution" "blocker: local" "AC14: execution block creates an actionable local blocker"
assert_eq "0" "$execution_select_code" "AC14: selector can choose the actionable blocker"
assert_contains "$execution_select" "routine-blocker." "AC14: actionable blocker remains routine-eligible"
assert_not_contains "$execution_select" "parent.bug" "AC14: execution-blocked parent is skipped"
execution_replay="$(python3 "$CLI" escalate parent.bug --repo "$EXECUTION" \
  --reason execution-blocked --reproduction-state unverified \
  --run-at 2026-09-12T13:05:00-03:00 --repro-command 'run focused reproduction' \
  --observed 'runtime executable was still not found' --evidence "$EXECUTION/blocker.json" \
  --blocker-file "$EXECUTION/blocker.json" --apply 2>&1)"; replay_code=$?
assert_eq "1" "$replay_code" "AC9: replayed escalation remains terminal"
assert_contains "$execution_replay" "blocker: local" "AC6: replay truthfully reports the reused local blocker"
assert_eq "1" "$(find "$EXECUTION/tasks/details" -name 'routine-blocker.*.md' | wc -l)" \
  "AC6: replay updates one stable blocker detail file"
assert_eq "1" "$(grep -c 'routine-blocker\.' "$EXECUTION/tasks/todo.md")" \
  "AC6: replay keeps one stable blocker index row"
assert_eq "1" "$(grep -c '^- labels: .*needs-investigation' "$EXECUTION/tasks/details/parent.bug.md")" \
  "AC5: replay never duplicates the parent hold label"

# Reproduction succeeded, then verification could not run: the request carries
# the reproduced state and the parent is held without inventing another defect.
new_repo VERIFY; create_parent "$VERIFY"
verification="$(python3 "$CLI" escalate parent.bug --repo "$VERIFY" \
  --reason verification-blocked --reproduction-state reproduced \
  --run-at 2026-09-12T14:00:00-03:00 --repro-command 'run full verification' \
  --observed 'verification service was unreachable' --evidence-unavailable 'service failed before log allocation' \
  --apply 2>&1)"; verification_code=$?
verification_select="$(python3 "$CLI" select --routine fix --repo "$VERIFY" 2>&1)"; verification_select_code=$?
assert_eq "1" "$verification_code" "AC9: post-reproduction verification block terminates non-zero"
assert_contains "$verification" "hold: confirmed" "AC14: verification-blocked run confirms its hold"
assert_eq "0" "$verification_select_code" "AC14: held verification parent leaves an empty eligible pool"
assert_not_contains "$verification_select" "parent.bug" "AC14: selection skips the verification-blocked parent"
assert_eq "1" "$(find "$VERIFY/tasks/routine-runs" -type f | wc -l)" \
  "AC14: verification-blocked run retains one artifact"

finish
