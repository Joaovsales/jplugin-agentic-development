#!/bin/bash
# tests/test-gh-pr.sh — gh_pr.py, the wrap-up's pull-request operations over REST.
#
# specs/github-rest-in-sandboxes.md AC10. Claude Code's cloud sandbox reaches
# GitHub through a proxy that accepts REST and refuses GraphQL, and every `gh pr`
# subcommand is GraphQL-backed, so the wrap-up's PR path -- create, view, edit,
# ready, checks, mergeable -- moved into one script over `gh api`. The script
# runs against the `gh` mock first on PATH (tests/fixtures/task-registry/gh), so
# the method, path and stdin body of every call are the real ones, read back
# from the mock's log.
#
# Two distinctions are load-bearing and each pinned here:
#   * `view` exits 1 for "no pull request" and 2 for "could not ask", because
#     the terminal PR assertion reads the first as a loud failure and the second
#     as UNKNOWN -- conflating them mutes a nightly check;
#   * `ready` takes the sandbox proxy's `ccr` route and falls back to
#     `gh pr ready [--undo]` only on a 404 from it (Decision 9), reporting which
#     path it took.
#
# On Windows the mock is unreachable from Python (#129: PATHEXT finds the real
# gh.exe), so these assertions are proven on Linux CI.
. "$(dirname "$0")/lib.sh"

GH_PR="$(under_test .agents/skills/wrap-up-session/scripts/gh_pr.py)"
PY="$TEST_PYTHON"

T="$(fixture_dir)"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

HERE="fixture-owner/fixture-repo"
mkdir -p "$T/bin" "$T/shim" "$T/ghdata"
fixture_copy task-registry/gh "$T/bin/gh"; chmod +x "$T/bin/gh"
# Outside the sandbox the GraphQL CLI works: this shim answers `gh pr ...` and
# hands everything else to the mock, so the fallback's success path is provable.
cat > "$T/shim/gh" <<EOF
#!/bin/bash
if [ "\$1" = pr ]; then printf '%s\n' "\$*" >> "\$GH_MOCK_LOG"; exit 0; fi
exec "$T/bin/gh" "\$@"
EOF
chmod +x "$T/shim/gh"

# A clone on `feature/x` whose origin is the fixture repository on GitHub.
WORK="$(fixture_repo)"
git -C "$WORK" checkout -q -b feature/x
git -C "$WORK" remote add origin "https://github.com/$HERE.git"

cat > "$T/ghdata/pulls.json" <<EOF
[
  {"number": 7, "html_url": "https://github.com/$HERE/pull/7", "state": "open", "merged": false,
   "draft": false, "title": "Seven", "body": "Closes #91\n\n## Closure\n",
   "head": {"ref": "feature/x", "sha": "abc123"}, "base": {"ref": "master"}, "mergeable": true},
  {"number": 8, "html_url": "https://github.com/$HERE/pull/8", "state": "open", "merged": false,
   "draft": true, "title": "Eight", "body": "",
   "head": {"ref": "routine/plan/9-x", "sha": "def456"}, "base": {"ref": "develop"}, "mergeable": false},
  {"number": 9, "html_url": "https://github.com/$HERE/pull/9", "state": "closed", "merged": true,
   "draft": false, "title": "Nine", "body": "",
   "head": {"ref": "feature/x", "sha": "0a0a0a"}, "base": {"ref": "master"}, "mergeable": null}
]
EOF
printf '100\n' > "$T/ghdata/next-number"
cat > "$T/ghdata/check-runs-abc123.json" <<'EOF'
{"total_count": 2, "check_runs": [
  {"name": "tests", "status": "completed", "conclusion": "success"},
  {"name": "lint", "status": "completed", "conclusion": "failure"}
]}
EOF
cat > "$T/ghdata/status-abc123.json" <<'EOF'
{"state": "success", "statuses": [{"context": "ci/legacy", "state": "success"}]}
EOF
cat > "$T/ghdata/check-runs-def456.json" <<'EOF'
{"total_count": 1, "check_runs": [{"name": "tests", "status": "in_progress", "conclusion": null}]}
EOF
cat > "$T/ghdata/protection-master.json" <<'EOF'
{"contexts": ["tests"], "checks": [{"context": "tests", "app_id": null}]}
EOF
printf 'Closes #91\n' > "$T/body.md"
printf 'Closes #91\n\n## Closure\nci: pass\n' > "$T/redraft.md"

# in_work <cmd...> — <cmd> with the fixture clone as cwd.
in_work() { ( cd "$WORK" && "$@" ); }

# ghpr <log-name> <args...> — gh_pr.py in the fixture clone with the gh mock
# first on PATH; every gh call lands in $T/<log-name>.log. Polls never sleep
# here. Judged by assert_exit and `output`, as run leaves them.
ghpr() {
  local log="$T/$1.log"; shift
  : > "$log"
  PATH="$T/bin:$PATH" GH_MOCK_DIR="$T/ghdata" GH_MOCK_LOG="$log" \
    GH_PR_POLL_SECONDS=0 GH_PR_WATCH_SECONDS=0 run in_work "$PY" "$GH_PR" "$@"
}

# --- create: POST /pulls with head = the current branch, the body on stdin ----
ghpr create create --base master --title "Seven again" --body-file "$T/body.md" --draft
assert_exit 0 "create: a created pull request exits 0"
assert_contains "$output" "https://github.com/$HERE/pull/100" "create: the pull request URL is printed"
assert_file_contains "$T/create.log" \
  'api --method POST repos/'"$HERE"'/pulls --input - {"base": "master", "body": "Closes #91\n", "draft": true, "head": "feature/x", "title": "Seven again"}' \
  "create (AC10): POST /pulls carries head, base, title, body and draft on stdin"
ghpr create2 create --base master --title "Ready" --body-file "$T/body.md"
assert_file_contains "$T/create2.log" '"draft": false' "create: without --draft the pull request is ready for review"
assert_eq "0" "$(grep -c '^pr ' "$T/create.log" "$T/create2.log" | awk -F: '{s+=$2} END {print s}')" \
  "create: no gh pr subcommand runs"

# --- view: by number and by branch, the fields the prose reads ---------------
ghpr view view 7 --json number,url,body,mergeable,headSha
assert_exit 0 "view: an existing pull request exits 0"
assert_contains "$output" '"number": 7' "view: number is read"
assert_contains "$output" '"url": "https://github.com/'"$HERE"'/pull/7"' "view: url is html_url"
assert_contains "$output" '"body": "Closes #91\n\n## Closure\n"' "view: body is the pull request body verbatim"
assert_contains "$output" '"mergeable": "MERGEABLE"' "view: REST true reads MERGEABLE, the word the closure prose uses"
assert_contains "$output" '"headSha": "abc123"' "view: headSha is head.sha"
assert_file_contains "$T/view.log" "api repos/$HERE/pulls/7" "view (AC10): a number is GET /pulls/{n}"

ghpr view-q view 7 --json number,url -q .url
assert_eq "https://github.com/$HERE/pull/7
exit=0" "$output
exit=$status" "view: -q .field prints the bare value and nothing else"

ghpr view-branch view feature/x --json number -q .number
assert_eq "7
exit=0" "$output
exit=$status" "view: a branch resolves to its newest pull request, open or closed"
assert_file_contains "$T/view-branch.log" "api repos/$HERE/pulls?head=fixture-owner:feature/x&state=all&per_page=1" \
  "view (AC10): a branch is GET /pulls?head=owner:branch&state=all"

ghpr view-unknown view 7 --json number,title
assert_exit 2 "view: an unknown field is refused"
assert_contains "$output" "unknown field(s) title" "view: the refusal names the field"

# --- view: "no pull request" (1) is not "could not ask" (2) -----------------
ghpr view-none view nobody/branch --json number
assert_exit 1 "view (AC10): a branch with no pull request exits 1"
assert_contains "$output" "no pull request for nobody/branch" "view: the no-PR message names the branch"
ghpr view-404 view 55 --json number
assert_exit 1 "view (AC10): a 404 on a number exits 1"
assert_contains "$output" "no pull request #55" "view: the no-PR message names the number"
GH_MOCK_FAIL_READS=1 ghpr view-502 view feature/x --json number
assert_exit 2 "view (AC10): a failed ask exits 2, never 1"
assert_contains "$output" "HTTP 502" "view: gh's stderr is quoted so the caller reports UNKNOWN"
assert_not_contains "$output" "no pull request" "view: a failed ask is never reported as a missing pull request"
mkdir -p "$T/badgh"; printf '#!/bin/sh
echo "not json"
' > "$T/badgh/gh"; chmod +x "$T/badgh/gh"
PATH="$T/badgh:$PATH" run in_work "$PY" "$GH_PR" view 7 --json number
assert_exit 2 "view: a gh that answers something other than JSON is could-not-ask, exit 2"
assert_contains "$output" "other than JSON" "view: the non-JSON answer is named"

# --- the number and the branch never reach gh unchecked ----------------------
ghpr badnum mergeable '../issues/7'
assert_exit 2 "guard: a non-numeric pull request number is refused"
assert_contains "$output" "is not a pull request number" "guard: the refusal names the value"
assert_eq "0" "$(grep -c . "$T/badnum.log")" "guard: a refused number reaches no gh call"
ghpr hashnum view '#7' --json number -q .number
assert_eq "7
exit=0" "$output
exit=$status" "guard: a leading # on the number is accepted, the way gh takes it"
ghpr ampersand view 'fix/a&b' --json number
assert_file_contains "$T/ampersand.log" 'pulls?head=fixture-owner:fix/a%26b&state=all' \
  "guard: a branch name is URL-quoted into the head query, slashes kept"

# --- edit: PATCH /pulls/{n} with the body on stdin ---------------------------
ghpr edit edit 7 --body-file "$T/redraft.md"
assert_exit 0 "edit: a redrafted body exits 0"
assert_file_contains "$T/edit.log" \
  'api --method PATCH repos/'"$HERE"'/pulls/7 --input - {"body": "Closes #91\n\n## Closure\nci: pass\n"}' \
  "edit (AC10): PATCH /pulls/{n} carries the body on stdin"
ghpr edit-read view 7 --json body -q .body
assert_contains "$output" "ci: pass" "edit: the mock persisted the new body, so a later view reads it"

# --- ready: the ccr route, and gh pr ready only on its 404 (Decision 9) ------
ghpr ready ready 8
assert_exit 0 "ready: marking ready exits 0"
assert_file_contains "$T/ready.log" "api --method POST repos/$HERE/pulls/8/ccr/ready_for_review" \
  "ready (AC10): ready posts to pulls/{n}/ccr/ready_for_review"
assert_contains "$output" "through the ccr route" "ready: the path taken is reported"
ghpr undo ready 7 --undo
assert_file_contains "$T/undo.log" "api --method POST repos/$HERE/pulls/7/ccr/convert_to_draft" \
  "ready (AC10): --undo posts to pulls/{n}/ccr/convert_to_draft"
assert_eq "0" "$(grep -c '^pr ready' "$T/ready.log" "$T/undo.log" | awk -F: '{s+=$2} END {print s}')" \
  "ready: with the ccr route answering, gh pr ready never runs"

GH_MOCK_NO_CCR=1 ghpr noccr ready 7 --undo
assert_exit 2 "ready: outside the sandbox, a gh pr ready that fails is could-not-ask"
assert_file_contains "$T/noccr.log" "pr ready 7 --undo" \
  "ready (Decision 9): a 404 from the ccr route falls back to gh pr ready --undo"
assert_contains "$output" "gh pr ready 7 --undo" "ready: the failed fallback names the command it ran"
PATH="$T/shim:$T/bin:$PATH" GH_MOCK_DIR="$T/ghdata" GH_MOCK_LOG="$T/shim.log" GH_MOCK_NO_CCR=1 \
  run in_work "$PY" "$GH_PR" ready 7 --undo
assert_exit 0 "ready: a successful gh pr ready fallback exits 0"
assert_contains "$output" "through gh pr ready (no ccr route)" "ready: the fallback path is reported"
GH_MOCK_FAIL=1 ghpr ready-fail ready 8
assert_exit 2 "ready: a refused write is could-not-ask, exit 2"
assert_not_contains "$(<"$T/ready-fail.log")" "pr ready" \
  "ready: a 403 is not a 404 -- no fallback to GraphQL on a refused write"

# --- checks: check runs plus commit statuses on the head sha -----------------
ghpr checks checks 7
assert_exit 1 "checks: a failed check exits 1"
assert_contains "$output" $'success\ttests' "checks: each check run is listed with its conclusion"
assert_contains "$output" $'failure\tlint' "checks: the failing run is listed"
assert_contains "$output" $'success\tci/legacy' "checks: commit statuses are listed beside check runs"
assert_contains "$output" "checks: fail — lint" "checks: the summary names what failed"
assert_file_contains "$T/checks.log" "api repos/$HERE/commits/abc123/check-runs?per_page=100" \
  "checks (AC10): check runs are GET /commits/{sha}/check-runs"
assert_file_contains "$T/checks.log" "api repos/$HERE/commits/abc123/status" \
  "checks (AC10): statuses are GET /commits/{sha}/status"

ghpr required checks 7 --required
assert_exit 0 "checks --required: only the required checks decide"
assert_file_contains "$T/required.log" "api repos/$HERE/branches/master/protection/required_status_checks" \
  "checks (AC10): --required reads the base branch's required status checks"
assert_contains "$output" "checks: pass — 1 check(s)" "checks --required: lint is not required, so it does not fail the watch"
assert_not_contains "$output" "lint" "checks --required: checks that are not required are not listed"

ghpr unprotected checks 8 --required
assert_contains "$output" "declares no required checks (branch not protected) — watching all checks" \
  "checks --required: a 404 Branch not protected falls back to all checks and says so"
assert_contains "$output" $'pending\ttests' "checks: an in-progress run is pending"
assert_contains "$output" "checks: pending — tests still running" "checks: pending without --watch is reported and exits 1"
assert_exit 1 "checks: a pending check exits 1"
ghpr watch checks 8 --watch
assert_contains "$output" "checks: timeout — tests still running" "checks --watch: past the budget the summary is timeout"
ghpr nochecks checks 9
assert_contains "$output" "checks: none" "checks: a commit with no checks says none"
assert_exit 0 "checks: no checks is not a failure"

# --- mergeable: true, false and the null GitHub is still computing -----------
ghpr clean mergeable 7
assert_eq "mergeable: clean
exit=0" "$output
exit=$status" "mergeable: true is clean, exit 0"
ghpr conflicting mergeable 8
assert_eq "mergeable: conflicting with develop
exit=1" "$output
exit=$status" "mergeable: false is conflicting with the base branch, exit 1"
ghpr unknown mergeable 9
assert_eq "mergeable: unknown
exit=0" "$output
exit=$status" "mergeable: null is unknown"
assert_eq "4" "$(grep -c "api repos/$HERE/pulls/9" "$T/unknown.log")" \
  "mergeable: a null is re-read three times before it is reported unknown"

# --- the mock refuses GraphQL-backed subcommands outright --------------------
PATH="$T/bin:$PATH" GH_MOCK_LOG="$T/refused.log" run in_work gh pr view 7 --json url
assert_exit 1 "mock: gh pr is refused -- the sandbox has no GraphQL"
assert_file_contains "$T/refused.log" "pr view 7 --json url" "mock: the refused call is still logged"

# --- coupling: the script talks to pull requests only ------------------------
assert_file_not_matches "$GH_PR" "gh issue" "gh_pr.py never calls a tracker's task API (coupling guard)"
assert_eq "1" "$(grep -c '"pr", "ready"' "$GH_PR")" \
  "gh_pr.py: the one gh pr argv it builds is the ready fallback"

finish
