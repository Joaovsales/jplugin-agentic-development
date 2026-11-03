#!/bin/bash
# Local-only contract tests for the general-purpose upstream drift checker.
. "$(dirname "$0")/lib.sh"

CHECKER="$(under_test scripts/check-upstream-drift.py)"
# The repo-relative pins below (.github/, install.sh, README.md) resolve from
# the repository the checker lives in.
REPO="${CHECKER%/scripts/check-upstream-drift.py}"
cd "$REPO" || exit 1
FX="$(fixture_dir)"
OUT_FILE="$FX/stdout"
ERR_FILE="$FX/stderr"

# upstream_repo — a fixture repo whose branch is `main`, the ref the registries
# below track.
upstream_repo() {
  local repo
  repo="$(fixture_repo)" || exit 143
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  printf '%s\n' "$repo"
}

commit_file() {
  local repo="$1" path="$2" content="$3"
  mkdir -p "$repo/$(dirname "$path")"
  printf '%s\n' "$content" > "$repo/$path"
  git -C "$repo" add "$path"
  git -C "$repo" commit -qm "update $path"
}

# check <registry> [checker args...] — run the checker. The status is judged by
# assert_exit; `output` is stdout then stderr, and the two streams stay apart in
# $OUT_FILE / $ERR_FILE for the checks that need them separately.
check() {
  local registry="$1"; shift
  run bash -c 'out=$1; err=$2; shift 2; "$@" >"$out" 2>"$err"' _ "$OUT_FILE" "$ERR_FILE" \
    "$TEST_PYTHON" "$CHECKER" --registry "$registry" "$@"
  output="$(<"$OUT_FILE")$(<"$ERR_FILE")"
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
SCOPED_REPO="$(upstream_repo)"
WHOLE_REPO="$(upstream_repo)"
commit_file "$SCOPED_REPO" "tracked/skill.md" "reviewed"
SCOPED_BASELINE="$(git -C "$SCOPED_REPO" rev-parse HEAD)"
commit_file "$SCOPED_REPO" "unrelated/readme.md" "monorepo churn"

commit_file "$WHOLE_REPO" "notice.txt" "reviewed"
WHOLE_BASELINE="$(git -C "$WHOLE_REPO" rev-parse HEAD)"

CLEAN_REGISTRY="$FX/clean.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"scoped\",\"url\":\"$SCOPED_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$SCOPED_BASELINE\",\"paths\":[\"tracked\"],\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}," \
  "{\"id\":\"whole\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$CLEAN_REGISTRY"

check "$CLEAN_REGISTRY"
assert_exit 0 "clean: multiple sources succeed"
assert_eq "" "$(<"$OUT_FILE")" "clean: stdout is silent"
assert_eq "" "$(<"$ERR_FILE")" "clean: stderr is silent"

# A failing remote helper can be noisy, but its bounded diagnostic remains actionable.
NOISY_BIN="$FX/noisy-bin"
mkdir -p "$NOISY_BIN"
printf '#!/bin/sh\nprintf "distinctive remote failure\\n" >&2\ni=0; while [ "$i" -lt 2000 ]; do printf "noise-%04d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\\n" "$i" >&2; i=$((i + 1)); done\nexit 1\n' \
  > "$NOISY_BIN/git-remote-noisy"
chmod +x "$NOISY_BIN/git-remote-noisy"
NOISY_REGISTRY="$FX/noisy.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"noisy\",\"url\":\"noisy::target\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$NOISY_REGISTRY"
NOISY_STARTED_MS="$(now_ms)"
PATH="$NOISY_BIN:$PATH" check "$NOISY_REGISTRY"
NOISY_ELAPSED_MS="$(( $(now_ms) - NOISY_STARTED_MS ))"
assert_exit 1 "bounded diagnostic: failing helper is unavailable"
assert_contains "$output" "distinctive remote failure" \
  "bounded diagnostic: useful fetch evidence survives"
assert_true "bounded diagnostic: noisy helper cannot flood output" -- \
  [ "$(wc -c < "$ERR_FILE")" -le 1000 ]

# A remote helper that outlives Git must not keep the stderr reader past the deadline.
# The helper sleeps far longer than any plausible spawn latency: a killed helper
# costs nothing extra, and one that outlives the kill must still be alive when
# the liveness check below runs, not exited on its own.
printf '#!/bin/sh\nprintf "%s" "$$" > "%s"\nsleep 30\nexit 1\n' '%s' "$FX/hanging-helper.pid" \
  > "$NOISY_BIN/git-remote-hanging"
chmod +x "$NOISY_BIN/git-remote-hanging"
HANGING_REGISTRY="$FX/hanging.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"hanging\",\"url\":\"hanging::target\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$HANGING_REGISTRY"
HANGING_STARTED_MS="$(now_ms)"
PATH="$NOISY_BIN:$PATH" check "$HANGING_REGISTRY" --deadline-seconds 0.1
HANGING_ELAPSED_MS="$(( $(now_ms) - HANGING_STARTED_MS ))"
assert_exit 1 "process tree: hanging helper is unavailable"

# The wall-clock bound is relative, not absolute. The noisy run above walked the
# same python + git path with a helper that exits at once, so it measures this
# machine's spawn cost; a killed helper adds only the 0.1 s deadline to that,
# while one that outlives the kill holds the stderr pipe open and adds the
# checker's one-second reader join. On Windows a single spawn can cost a
# second, so the old absolute "under 2 s" read as a failure there (#136).
HANGING_BUDGET_MS="$(( NOISY_ELAPSED_MS + 1500 ))"
assert_true "process tree: helper cannot outlive the checker deadline" -- \
  [ "$HANGING_ELAPSED_MS" -le "$HANGING_BUDGET_MS" ]

# The direct evidence: a helper that started recorded its pid, and it must be
# gone once the checker has returned. When the 0.1 s deadline expires before Git
# even spawns the helper -- the case on a machine where one spawn costs more
# than that -- there is no pid to check, and the timing bound above is the only
# evidence; say so instead of passing in silence.
# A killed helper is dead the moment the signal lands, but it stays in the
# process table as a zombie until its new parent reaps it — and a container's
# PID 1 may take half a second or longer to do that, while `kill -0` on a zombie
# still succeeds. Read the state too: `Z` is dead, only a running state counts.
helper_running() {
  kill -0 "$1" 2>/dev/null || return 1
  [ "$(ps -o stat= -p "$1" 2>/dev/null | cut -c1)" != "Z" ]
}
if [ -f "$FX/hanging-helper.pid" ]; then
  HELPER_PID="$(<"$FX/hanging-helper.pid")"
  waited=0
  while helper_running "$HELPER_PID" && [ "$waited" -lt 20 ]; do
    sleep 0.05; waited=$((waited + 1))
  done
  assert_false "process tree: the helper is dead once the checker returns" -- helper_running "$HELPER_PID"
else
  printf '  note process tree: the deadline expired before Git spawned the helper; timing bound only\n'
fi

# Relevant scoped drift and an unavailable ref are both reported in one run.
commit_file "$SCOPED_REPO" "tracked/skill.md" "changed upstream"
AGGREGATE_REGISTRY="$FX/aggregate.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"scoped\",\"url\":\"$SCOPED_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$SCOPED_BASELINE\",\"paths\":[\"tracked\"],\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}," \
  "{\"id\":\"missing-ref\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/absent\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}," \
  "{\"id\":\"missing-remote\",\"url\":\"$FX/absent-repo\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$AGGREGATE_REGISTRY"

check "$AGGREGATE_REGISTRY"
assert_exit 1 "aggregate: any non-clean source fails"
assert_contains "$output" "drift: scoped" "aggregate: reports scoped drift"
assert_contains "$output" "tracked/skill.md" "drift: reports the changed registered path"
assert_contains "$output" "$SCOPED_BASELINE" "drift: reports the reviewed baseline"
assert_contains "$output" "unavailable: missing-ref" "aggregate: later source failure is not hidden"
assert_contains "$output" "unavailable: missing-remote" "aggregate: reports an unavailable remote"
assert_not_contains "$output" "unrelated/readme.md" "drift: omits monorepo churn outside the scope"

# Omitting paths makes any repository change load-bearing.
WHOLE_DRIFT_REGISTRY="$FX/whole-drift.json"
commit_file "$WHOLE_REPO" "anywhere.txt" "whole repository drift"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"whole\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$WHOLE_DRIFT_REGISTRY"
check "$WHOLE_DRIFT_REGISTRY"
assert_exit 1 "whole repository: drift fails"
assert_contains "$output" "anywhere.txt" "whole repository: reports changes with paths omitted"

# Large diffs remain actionable without flooding CI logs or the workflow summary.
for number in $(seq 1 25); do
  mkdir -p "$SCOPED_REPO/tracked"
  printf 'change %s\n' "$number" > "$SCOPED_REPO/tracked/change-$number.txt"
done
git -C "$SCOPED_REPO" add tracked
git -C "$SCOPED_REPO" commit -qm "many upstream changes"
check "$AGGREGATE_REGISTRY"
CHANGED_LINES="$(grep -c '^  changed:' "$ERR_FILE")"
assert_eq "21" "$CHANGED_LINES" "bounded report: caps paths and adds one omission line"
assert_contains "$output" "more path(s) omitted" "bounded report: explains truncated evidence"

# Both commits remain fetchable, but the tracked ref no longer descends from the baseline.
DIVERGED_REPO="$(upstream_repo)"
commit_file "$DIVERGED_REPO" "old.txt" "old history"
DIVERGED_BASELINE="$(git -C "$DIVERGED_REPO" rev-parse HEAD)"
git -C "$DIVERGED_REPO" checkout -q --orphan rewritten
git -C "$DIVERGED_REPO" rm -q -rf .
commit_file "$DIVERGED_REPO" "new.txt" "rewritten history"
git -C "$DIVERGED_REPO" branch -M main
DIVERGED_REGISTRY="$FX/diverged.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"rewritten\",\"url\":\"$DIVERGED_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$DIVERGED_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$DIVERGED_REGISTRY"
check "$DIVERGED_REGISTRY"
assert_exit 1 "rewritten history: fails"
assert_contains "$output" "history-diverged: rewritten" "rewritten history: requires manual review"

# The entire registry is rejected before the first Git invocation.
INVALID_REGISTRY="$FX/invalid.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"duplicate\",\"url\":\"never-contact-one\",\"ref\":\"main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"NOTICE.md\"}," \
  "{\"id\":\"duplicate\",\"url\":\"never-contact-two\",\"ref\":\"main\",\"baseline\":\"not-a-commit\",\"paths\":[\"../escape\"],\"source_notice\":\"/absolute\"}" \
  ']}' > "$INVALID_REGISTRY"

FAKE_BIN="$FX/bin"
GIT_MARKER="$FX/git-was-called"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nprintf called > "%s"\nexit 99\n' "$GIT_MARKER" > "$FAKE_BIN/git"
chmod +x "$FAKE_BIN/git"
PATH="$FAKE_BIN:$PATH" check "$INVALID_REGISTRY"
assert_exit 2 "invalid registry: uses configuration-error status"
assert_contains "$output" "invalid registry" "invalid registry: labels the failure"
assert_contains "$output" "duplicate" "invalid registry: names the duplicate ID"
assert_contains "$output" "baseline" "invalid registry: names malformed fields"
assert_file_absent "$GIT_MARKER" "invalid registry: validates everything before Git/network"

INVALID_REF_REGISTRY="$FX/invalid-ref.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"invalid-ref\",\"url\":\"never-contact\",\"ref\":\"refs/heads/bad ref\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$INVALID_REF_REGISTRY"
rm -f "$GIT_MARKER"
PATH="$FAKE_BIN:$PATH" check "$INVALID_REF_REGISTRY"
assert_exit 2 "invalid ref: uses configuration-error status"
assert_contains "$output" "ref" "invalid ref: names the malformed field"
assert_file_absent "$GIT_MARKER" "invalid ref: rejected before Git/network"

# Control characters fail validation instead of reaching subprocess as invalid arguments.
CONTROL_REGISTRY="$FX/control.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"control\",\"url\":\"bad\\u0000url\",\"ref\":\"main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
  ']}' > "$CONTROL_REGISTRY"
check "$CONTROL_REGISTRY"
assert_exit 2 "control character: invalid registry status"
assert_contains "$output" "bounded string" "control character: actionable field error"
assert_not_contains "$output" "Traceback" "control character: no uncaught subprocess error"

# Attribution paths are part of registry validity, not passive metadata.
MISSING_NOTICE_REGISTRY="$FX/missing-notice.json"
printf '%s\n' \
  '{"version":1,"sources":[' \
  "{\"id\":\"missing-notice\",\"url\":\"$WHOLE_REPO\",\"ref\":\"refs/heads/main\",\"baseline\":\"$WHOLE_BASELINE\",\"source_notice\":\"missing-notice.md\"}" \
  ']}' > "$MISSING_NOTICE_REGISTRY"
check "$MISSING_NOTICE_REGISTRY"
assert_exit 2 "missing notice: invalid registry status"
assert_contains "$output" "existing file" "missing notice: actionable path error"

# A standard absolute registry path resolves repository-relative notices even outside the repo.
run bash -c 'cd "$1" && shift && exec "$@"' _ "$FX" \
  "$TEST_PYTHON" "$CHECKER" --registry "$REPO/.github/upstreams.json" --deadline-seconds 0.000001
assert_exit 1 "repository root: absolute standard registry validates outside repo"
assert_not_contains "$output" "existing file" "repository root: notice resolves against registry repo"

# An exhausted total deadline still reports every source instead of timing out in CI.
check "$AGGREGATE_REGISTRY" --deadline-seconds 0.000001
assert_exit 1 "deadline: non-clean status"
assert_contains "$output" "unavailable: scoped" "deadline: reports first source"
assert_contains "$output" "unavailable: missing-remote" "deadline: reports later sources"

for invalid_deadline in nan inf; do
  check "$CLEAN_REGISTRY" --deadline-seconds "$invalid_deadline"
  assert_exit 2 "deadline: rejects $invalid_deadline"
done

# An installed source is a tool pinned at a tag, never a vendored copy: it has no `paths`.
# The real registry carries the Archify entry; --validate proves it without Git or network.
# The registry is the oracle for the pin: tag and commit are read from its
# archify entry, so a bump edits the consumer files and never a test literal.
ARCHIFY_COMMIT="$("$TEST_PYTHON" -c 'import json; s=[x for x in json.load(open(".github/upstreams.json"))["sources"] if x["id"]=="archify"][0]; print(s["baseline"])')"
ARCHIFY_TAG="$("$TEST_PYTHON" -c 'import json; s=[x for x in json.load(open(".github/upstreams.json"))["sources"] if x["id"]=="archify"][0]; print(s["ref"].rsplit("/", 1)[-1])')"
assert_eq "40" "${#ARCHIFY_COMMIT}" "installed: the registry baseline is a full commit (oracle is not empty)"
assert_eq "v" "${ARCHIFY_TAG:0:1}" "installed: the registry ref is a version tag (oracle is not empty)"
assert_file_contains ".github/upstreams.json" '"id": "archify"' \
  "installed: the registry identifies the Archify tool"
assert_file_contains ".github/upstreams.json" '"kind": "installed"' \
  "installed: the Archify entry is marked installed, not vendored"
assert_file_contains ".github/upstreams.json" "\"ref\": \"refs/tags/$ARCHIFY_TAG\"" \
  "installed: the Archify entry tracks its pinned tag"
assert_file_contains ".github/upstreams.json" "$ARCHIFY_COMMIT" \
  "installed: the baseline is the tag's dereferenced commit"
check "$REPO/.github/upstreams.json" --validate
assert_exit 0 "installed: --validate passes on the real registry"
assert_eq "" "$output" "installed: --validate is silent on success"
# One pin, three homes (D16): the registry baseline is the commit install.sh
# verifies the clone against, and the tag install.sh and the /diagram resolver
# clone is the tag the registry tracks. A bump that moves one and not the others
# would install one version and report drift on another.
assert_file_contains "install.sh" "ARCHIFY_COMMIT=\"$ARCHIFY_COMMIT\"" \
  "installed: install.sh verifies the clone against the registry baseline"
assert_file_contains "install.sh" "ARCHIFY_TAG=\"$ARCHIFY_TAG\"" \
  "installed: install.sh clones the tag the registry tracks"
assert_file_contains ".agents/skills/diagram/scripts/archify.sh" "ARCHIFY_TAG=\"$ARCHIFY_TAG\"" \
  "installed: the /diagram resolver prints the install command for the same tag"

# Installed fixture: a local upstream with a commit tagged v3.2.0.
TOOL_REPO="$(upstream_repo)"
commit_file "$TOOL_REPO" "tool.txt" "pinned"
git -C "$TOOL_REPO" tag v3.2.0
TOOL_BASELINE="$(git -C "$TOOL_REPO" rev-parse HEAD)"
write_tool_registry() {
  printf '%s\n' \
    '{"version":1,"sources":[' \
    "{\"id\":\"tool\",$1\"url\":\"$TOOL_REPO\",\"ref\":\"refs/tags/v3.2.0\",\"baseline\":\"$TOOL_BASELINE\",\"source_notice\":\"THIRD_PARTY_NOTICES.md\"}" \
    ']}' > "$2"
}
TOOL_REGISTRY="$FX/tool.json"
write_tool_registry '"kind":"installed",' "$TOOL_REGISTRY"
check "$TOOL_REGISTRY"
assert_exit 0 "installed: an unmoved tag is clean"
assert_eq "" "$output" "installed: a clean check is silent"

# --validate never contacts Git, even when the upstream is unreachable.
rm -f "$GIT_MARKER"
PATH="$FAKE_BIN:$PATH" check "$TOOL_REGISTRY" --validate
assert_exit 0 "installed: --validate accepts a well-formed entry"
assert_file_absent "$GIT_MARKER" "installed: --validate never reaches Git/network"

# Moving the tag is drift, reported exactly like a vendored source without paths.
commit_file "$TOOL_REPO" "tool.txt" "retagged"
git -C "$TOOL_REPO" tag -f v3.2.0 >/dev/null
check "$TOOL_REGISTRY"
assert_exit 1 "installed: a moved tag fails"
assert_contains "$output" "drift: tool" "installed: a moved tag is reported as drift"

# An installed tool is not path-scoped: `paths` is rejected before Git/network.
TOOL_PATHS_REGISTRY="$FX/tool-paths.json"
write_tool_registry '"kind":"installed","paths":["x"],' "$TOOL_PATHS_REGISTRY"
rm -f "$GIT_MARKER"
PATH="$FAKE_BIN:$PATH" check "$TOOL_PATHS_REGISTRY"
assert_exit 2 "installed with paths: invalid registry status"
assert_contains "$output" "invalid registry" "installed with paths: labels the failure"
assert_contains "$output" "paths" "installed with paths: names the forbidden field"
assert_file_absent "$GIT_MARKER" "installed with paths: rejected before Git/network"

TOOL_BOGUS_REGISTRY="$FX/tool-bogus.json"
write_tool_registry '"kind":"bogus",' "$TOOL_BOGUS_REGISTRY"
check "$TOOL_BOGUS_REGISTRY"
assert_exit 2 "unknown kind: invalid registry status"
assert_contains "$output" "kind" "unknown kind: names the field"

# Omitting `kind` keeps today's vendored semantics, where `paths` stays valid.
TOOL_VENDORED_REGISTRY="$FX/tool-vendored.json"
write_tool_registry '"paths":["tool.txt"],' "$TOOL_VENDORED_REGISTRY"
check "$TOOL_VENDORED_REGISTRY" --validate
assert_exit 0 "vendored default: an entry without kind keeps paths valid"

# Provenance reaches the distribution surfaces: ignore rule, MIT notice, Sources entry.
assert_file_contains ".gitignore" '.archify/' \
  "notices: Archify's working folder (receipts, captures) is never committed"
assert_file_contains "THIRD_PARTY_NOTICES.md" '## Archify (installed tool)' \
  "notices: Archify has its own section"
assert_file_contains "THIRD_PARTY_NOTICES.md" "$ARCHIFY_COMMIT" \
  "notices: the section pins the tag's commit"
assert_file_contains "THIRD_PARTY_NOTICES.md" 'Copyright (c) 2026 tt-a1i (Archify)' \
  "notices: the upstream copyright line is carried"
assert_file_contains "THIRD_PARTY_NOTICES.md" 'Permission is hereby granted, free of charge' \
  "notices: the MIT text is carried"
SOURCES_BODY="$(section_body README.md "## Sources")"
assert_contains "$SOURCES_BODY" 'tt-a1i/archify' "notices: README Sources names Archify"
assert_contains "$SOURCES_BODY" "tree/$ARCHIFY_TAG" "notices: README Sources links the pinned tag"
assert_contains "$SOURCES_BODY" "$ARCHIFY_COMMIT" "notices: README Sources names the pinned commit"

finish
