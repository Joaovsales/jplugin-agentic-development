#!/bin/bash
# Local-only contract tests for the general-purpose upstream drift checker.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO/scripts/check-upstream-drift.py"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

new_repo() {
  _repo="$1"
  git init -q --initial-branch=main "$_repo"
  git -C "$_repo" config user.name fixture
  git -C "$_repo" config user.email fixture@example.test
}

commit_file() {
  _repo="$1" _path="$2" _content="$3"
  mkdir -p "$_repo/$(dirname "$_path")"
  printf '%s\n' "$_content" > "$_repo/$_path"
  git -C "$_repo" add "$_path"
  git -C "$_repo" commit -qm "update $_path"
}

run_checker() {
  _registry="$1"
  shift
  CHECK_STDOUT="$FIXTURE_ROOT/stdout"
  CHECK_STDERR="$FIXTURE_ROOT/stderr"
  python3 "$CHECKER" --registry "$_registry" "$@" >"$CHECK_STDOUT" 2>"$CHECK_STDERR"
  CHECK_STATUS=$?
  CHECK_OUTPUT="$(cat "$CHECK_STDOUT"; cat "$CHECK_STDERR")"
}

# Static distribution and least-privilege workflow contract.
assert_file_contains ".github/upstreams.json" '"id": "pstack-verification-skills"' \
  "registry: identifies the pstack import"
assert_file_contains ".github/upstreams.json" '68836ddaf5697224520f1847d90cdb90ca8babaa' \
  "registry: pins the reviewed pstack baseline"
assert_file_contains ".github/upstreams.json" 'pstack/skills/create-verification-skill' \
  "registry: scopes creator provenance"
assert_file_contains ".github/upstreams.json" 'pstack/skills/maintain-verification-skill' \
  "registry: scopes maintainer provenance"
assert_file_contains ".github/upstreams.json" 'pstack/LICENSE' \
  "registry: scopes the upstream license"

WORKFLOW=".github/workflows/check-upstream-drift.yml"
assert_file_contains "$WORKFLOW" "workflow_dispatch:" "workflow: supports manual runs"
assert_file_contains "$WORKFLOW" "cron:" "workflow: runs on a schedule"
assert_file_contains "$WORKFLOW" "contents: read" "workflow: grants only read access"
assert_file_contains "$WORKFLOW" 'GITHUB_STEP_SUMMARY' "workflow: publishes failure evidence"
assert_file_contains "$WORKFLOW" 'python3 scripts/check-upstream-drift.py' \
  "workflow: invokes the registered-source checker"
assert_file_contains "$WORKFLOW" 'status=$?' "workflow: captures the checker status"
assert_file_contains "$WORKFLOW" 'if [ "$status" -ne 0 ]; then' \
  "workflow: only non-clean checker status enters the failure branch"
assert_file_contains "$WORKFLOW" 'exit "$status"' "workflow: propagates checker failures"
assert_file_matches "$WORKFLOW" 'uses: actions/checkout@[0-9a-f]{40}([[:space:]]|$)' \
  "workflow: third-party action is pinned to an immutable commit"
assert_file_contains "$WORKFLOW" "sed 's/^/    /' upstream-drift-report.txt" \
  "workflow: untrusted diagnostics are rendered as indented code"
assert_file_contains "$WORKFLOW" 'timeout-minutes: 15' "workflow: has a bounded outer deadline"
assert_file_contains "$CHECKER" 'CHECK_DEADLINE_SECONDS = 600' \
  "checker: leaves time to publish evidence before workflow timeout"
assert_file_contains "$CHECKER" 'RLIMIT_FSIZE' \
  "checker: Git children have a file-size resource ceiling"
assert_file_contains "$CHECKER" 'RLIMIT_AS' \
  "checker: Git children have a memory resource ceiling"
assert_file_contains "$CHECKER" 'return subprocess.DEVNULL, subprocess.DEVNULL' \
  "checker: fetch output cannot accumulate in parent memory"
assert_file_contains "$CHECKER" '"--filter=blob:none"' \
  "checker: fetch excludes unneeded blob payloads"
assert_file_not_matches "$WORKFLOW" 'issues:[[:space:]]*write|pull-requests:[[:space:]]*write' \
  "workflow: cannot open issues or pull requests"
assert_file_not_matches "$WORKFLOW" 'checkout.*upstream|git[[:space:]]+checkout|git[[:space:]]+merge|git[[:space:]]+cherry-pick' \
  "workflow: does not apply upstream content"

# Build two local upstreams. One is path-scoped; one monitors the whole repo.
SCOPED_REPO="$FIXTURE_ROOT/scoped"
WHOLE_REPO="$FIXTURE_ROOT/whole"
new_repo "$SCOPED_REPO"
commit_file "$SCOPED_REPO" "tracked/skill.md" "reviewed"
SCOPED_BASELINE="$(git -C "$SCOPED_REPO" rev-parse HEAD)"
commit_file "$SCOPED_REPO" "unrelated/readme.md" "monorepo churn"

new_repo "$WHOLE_REPO"
commit_file "$WHOLE_REPO" "notice.txt" "reviewed"
WHOLE_BASELINE="$(git -C "$WHOLE_REPO" rev-parse HEAD)"

CLEAN_REGISTRY="$FIXTURE_ROOT/clean.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"scoped\",\"url\":\"$SCOPED_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$SCOPED_BASELINE\",\"paths\":[\"tracked\"],\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}," \
  "{\"id\":\"whole\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$CLEAN_REGISTRY"

run_checker "$CLEAN_REGISTRY"
assert_eq "0" "$CHECK_STATUS" "clean: multiple sources succeed"
assert_eq "" "$(cat "$CHECK_STDOUT")" "clean: stdout is silent"
assert_eq "" "$(cat "$CHECK_STDERR")" "clean: stderr is silent"

# A failing remote helper can be noisy, but its bounded diagnostic remains actionable.
NOISY_BIN="$FIXTURE_ROOT/noisy-bin"
mkdir -p "$NOISY_BIN"
printf '#!/bin/sh\nprintf "distinctive remote failure\\n" >&2\ni=0; while [ "$i" -lt 2000 ]; do printf "noise-%04d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\\n" "$i" >&2; i=$((i + 1)); done\nexit 1\n' \
  > "$NOISY_BIN/git-remote-noisy"
chmod +x "$NOISY_BIN/git-remote-noisy"
NOISY_REGISTRY="$FIXTURE_ROOT/noisy.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"noisy\",\"url\":\"noisy::target\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$NOISY_REGISTRY"
PATH="$NOISY_BIN:$PATH" run_checker "$NOISY_REGISTRY"
assert_eq "1" "$CHECK_STATUS" "bounded diagnostic: failing helper is unavailable"
assert_contains "$CHECK_OUTPUT" "distinctive remote failure" \
  "bounded diagnostic: useful fetch evidence survives"
if [ "$(wc -c < "$CHECK_STDERR")" -le 1000 ]; then
  assert_eq "bounded" "bounded" "bounded diagnostic: noisy helper cannot flood output"
else
  assert_eq "at-most-1000" "$(wc -c < "$CHECK_STDERR")" \
    "bounded diagnostic: noisy helper cannot flood output"
fi

# A remote helper that outlives Git must not keep the stderr reader past the deadline.
printf '#!/bin/sh\nprintf "%s" "$$" > "%s"\nsleep 3\nexit 1\n' '%s' "$FIXTURE_ROOT/hanging-helper.pid" \
  > "$NOISY_BIN/git-remote-hanging"
chmod +x "$NOISY_BIN/git-remote-hanging"
HANGING_REGISTRY="$FIXTURE_ROOT/hanging.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"hanging\",\"url\":\"hanging::target\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$HANGING_REGISTRY"
HANGING_STARTED="$(date +%s)"
PATH="$NOISY_BIN:$PATH" run_checker "$HANGING_REGISTRY" --deadline-seconds 0.1
HANGING_ELAPSED="$(( $(date +%s) - HANGING_STARTED ))"
assert_eq "1" "$CHECK_STATUS" "process tree: hanging helper is unavailable"
if [ "$HANGING_ELAPSED" -lt 2 ]; then
  assert_eq "bounded" "bounded" "process tree: helper cannot outlive the checker deadline"
else
  assert_eq "under-2-seconds" "$HANGING_ELAPSED" \
    "process tree: helper cannot outlive the checker deadline"
fi

# Relevant scoped drift and an unavailable ref are both reported in one run.
commit_file "$SCOPED_REPO" "tracked/skill.md" "changed upstream"
AGGREGATE_REGISTRY="$FIXTURE_ROOT/aggregate.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"scoped\",\"url\":\"$SCOPED_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$SCOPED_BASELINE\",\"paths\":[\"tracked\"],\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}," \
  "{\"id\":\"missing-ref\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/absent\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}," \
  "{\"id\":\"missing-remote\",\"url\":\"$FIXTURE_ROOT/absent-repo\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$AGGREGATE_REGISTRY"

run_checker "$AGGREGATE_REGISTRY"
assert_eq "1" "$CHECK_STATUS" "aggregate: any non-clean source fails"
assert_contains "$CHECK_OUTPUT" "drift: scoped" "aggregate: reports scoped drift"
assert_contains "$CHECK_OUTPUT" "tracked/skill.md" "drift: reports the changed registered path"
assert_contains "$CHECK_OUTPUT" "$SCOPED_BASELINE" "drift: reports the reviewed baseline"
assert_contains "$CHECK_OUTPUT" "unavailable: missing-ref" "aggregate: later source failure is not hidden"
assert_contains "$CHECK_OUTPUT" "unavailable: missing-remote" "aggregate: reports an unavailable remote"
assert_not_contains "$CHECK_OUTPUT" "unrelated/readme.md" "drift: omits monorepo churn outside the scope"

# Omitting paths makes any repository change load-bearing.
WHOLE_DRIFT_REGISTRY="$FIXTURE_ROOT/whole-drift.json"
commit_file "$WHOLE_REPO" "anywhere.txt" "whole repository drift"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"whole\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$WHOLE_DRIFT_REGISTRY"
run_checker "$WHOLE_DRIFT_REGISTRY"
assert_eq "1" "$CHECK_STATUS" "whole repository: drift fails"
assert_contains "$CHECK_OUTPUT" "anywhere.txt" "whole repository: reports changes with paths omitted"

# Large diffs remain actionable without flooding CI logs or the workflow summary.
for number in $(seq 1 25); do
  mkdir -p "$SCOPED_REPO/tracked"
  printf 'change %s\n' "$number" > "$SCOPED_REPO/tracked/change-$number.txt"
done
git -C "$SCOPED_REPO" add tracked
git -C "$SCOPED_REPO" commit -qm "many upstream changes"
run_checker "$AGGREGATE_REGISTRY"
CHANGED_LINES="$(grep -c '^  changed:' "$CHECK_STDERR")"
assert_eq "21" "$CHANGED_LINES" "bounded report: caps paths and adds one omission line"
assert_contains "$CHECK_OUTPUT" "more path(s) omitted" "bounded report: explains truncated evidence"

# Both commits remain fetchable, but the tracked ref no longer descends from the baseline.
DIVERGED_REPO="$FIXTURE_ROOT/diverged"
new_repo "$DIVERGED_REPO"
commit_file "$DIVERGED_REPO" "old.txt" "old history"
DIVERGED_BASELINE="$(git -C "$DIVERGED_REPO" rev-parse HEAD)"
git -C "$DIVERGED_REPO" checkout -q --orphan rewritten
git -C "$DIVERGED_REPO" rm -q -rf .
commit_file "$DIVERGED_REPO" "new.txt" "rewritten history"
git -C "$DIVERGED_REPO" branch -M main
DIVERGED_REGISTRY="$FIXTURE_ROOT/diverged.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"rewritten\",\"url\":\"$DIVERGED_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$DIVERGED_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$DIVERGED_REGISTRY"
run_checker "$DIVERGED_REGISTRY"
assert_eq "1" "$CHECK_STATUS" "rewritten history: fails"
assert_contains "$CHECK_OUTPUT" "history-diverged: rewritten" "rewritten history: requires manual review"

# The entire registry is rejected before the first Git invocation.
INVALID_REGISTRY="$FIXTURE_ROOT/invalid.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"duplicate\",\"url\":\"never-contact-one\",\"ref\":\"main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"NOTICE.md\"}," \
  "{\"id\":\"duplicate\",\"url\":\"never-contact-two\",\"ref\":\"main\",\"baseline\":\"not-a-commit\",\"paths\":[\"../escape\"],\"source_notice\":\"/absolute\"}" \
  ']}' > "$INVALID_REGISTRY"

FAKE_BIN="$FIXTURE_ROOT/bin"
GIT_MARKER="$FIXTURE_ROOT/git-was-called"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nprintf called > "%s"\nexit 99\n' "$GIT_MARKER" > "$FAKE_BIN/git"
chmod +x "$FAKE_BIN/git"
CHECK_STDOUT="$FIXTURE_ROOT/invalid-stdout"
CHECK_STDERR="$FIXTURE_ROOT/invalid-stderr"
PATH="$FAKE_BIN:$PATH" python3 "$CHECKER" --registry "$INVALID_REGISTRY" >"$CHECK_STDOUT" 2>"$CHECK_STDERR"
CHECK_STATUS=$?
CHECK_OUTPUT="$(cat "$CHECK_STDOUT"; cat "$CHECK_STDERR")"
assert_eq "2" "$CHECK_STATUS" "invalid registry: uses configuration-error status"
assert_contains "$CHECK_OUTPUT" "invalid registry" "invalid registry: labels the failure"
assert_contains "$CHECK_OUTPUT" "duplicate" "invalid registry: names the duplicate ID"
assert_contains "$CHECK_OUTPUT" "baseline" "invalid registry: names malformed fields"
if [ -e "$GIT_MARKER" ]; then
  assert_eq "not-called" "called" "invalid registry: validates everything before Git/network"
else
  assert_eq "not-called" "not-called" "invalid registry: validates everything before Git/network"
fi

INVALID_REF_REGISTRY="$FIXTURE_ROOT/invalid-ref.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"invalid-ref\",\"url\":\"never-contact\",\"ref\":\"refs/heads/bad ref\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$INVALID_REF_REGISTRY"
rm -f "$GIT_MARKER"
PATH="$FAKE_BIN:$PATH" run_checker "$INVALID_REF_REGISTRY"
assert_eq "2" "$CHECK_STATUS" "invalid ref: uses configuration-error status"
assert_contains "$CHECK_OUTPUT" "ref" "invalid ref: names the malformed field"
if [ -e "$GIT_MARKER" ]; then
  assert_eq "not-called" "called" "invalid ref: rejected before Git/network"
else
  assert_eq "not-called" "not-called" "invalid ref: rejected before Git/network"
fi

# Control characters fail validation instead of reaching subprocess as invalid arguments.
CONTROL_REGISTRY="$FIXTURE_ROOT/control.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"control\",\"url\":\"bad\\u0000url\",\"ref\":\"main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$CONTROL_REGISTRY"
run_checker "$CONTROL_REGISTRY"
assert_eq "2" "$CHECK_STATUS" "control character: invalid registry status"
assert_contains "$CHECK_OUTPUT" "bounded string" "control character: actionable field error"
assert_not_contains "$CHECK_OUTPUT" "Traceback" "control character: no uncaught subprocess error"

# Attribution paths are part of registry validity, not passive metadata.
MISSING_NOTICE_REGISTRY="$FIXTURE_ROOT/missing-notice.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"missing-notice\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"missing-notice.md\"}" \
  ']}' > "$MISSING_NOTICE_REGISTRY"
run_checker "$MISSING_NOTICE_REGISTRY"
assert_eq "2" "$CHECK_STATUS" "missing notice: invalid registry status"
assert_contains "$CHECK_OUTPUT" "existing file" "missing notice: actionable path error"

# A standard absolute registry path resolves repository-relative notices even outside the repo.
OUTSIDE_STDOUT="$FIXTURE_ROOT/outside-stdout"
OUTSIDE_STDERR="$FIXTURE_ROOT/outside-stderr"
(cd "$FIXTURE_ROOT" && python3 "$CHECKER" \
  --registry "$REPO/.github/upstreams.json" --deadline-seconds 0.000001 \
  >"$OUTSIDE_STDOUT" 2>"$OUTSIDE_STDERR")
OUTSIDE_STATUS=$?
OUTSIDE_OUTPUT="$(cat "$OUTSIDE_STDOUT"; cat "$OUTSIDE_STDERR")"
assert_eq "1" "$OUTSIDE_STATUS" "repository root: absolute standard registry validates outside repo"
assert_not_contains "$OUTSIDE_OUTPUT" "existing file" "repository root: notice resolves against registry repo"

# An exhausted total deadline still reports every source instead of timing out in CI.
run_checker "$AGGREGATE_REGISTRY" --deadline-seconds 0.000001
assert_eq "1" "$CHECK_STATUS" "deadline: non-clean status"
assert_contains "$CHECK_OUTPUT" "unavailable: scoped" "deadline: reports first source"
assert_contains "$CHECK_OUTPUT" "unavailable: missing-remote" "deadline: reports later sources"

for invalid_deadline in nan inf; do
  run_checker "$CLEAN_REGISTRY" --deadline-seconds "$invalid_deadline"
  assert_eq "2" "$CHECK_STATUS" "deadline: rejects $invalid_deadline"
done

finish
