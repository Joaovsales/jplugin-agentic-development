# tests/test-session-stop.sh — the Stop hook: it clears the session-active
# sentinel and warns when the session ends with commits not pushed.
#
# Every run happens inside a fixture repo, with CLAUDE_SESSION_SENTINEL pointed
# at a file in the fixture so the live /tmp sentinel is never touched.
. "$(dirname "$0")/lib.sh"

HOOK="$(under_test .agents/hooks/session-stop.sh)"

# stop_hook <repo> <sentinel> [ENV=VAL...] — run the hook with <repo> as cwd.
stop_hook() {
  local repo="$1" sentinel="$2"; shift 2
  run env CLAUDE_SESSION_SENTINEL="$sentinel" "$@" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" "$HOOK"
}

# commit <repo> <name> — one commit touching <name>.
commit() {
  echo "$2" > "$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -qm "add $2"
}

# repo_with_origin — a fixture repo with one commit, pushed to a bare origin.
repo_with_origin() {
  local repo bare
  repo="$(fixture_repo)" || exit 143
  bare="$(fixture_dir)" || exit 143
  git -C "$bare" init -q --bare
  commit "$repo" a.txt
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q -u origin HEAD >/dev/null 2>&1
  printf '%s\n' "$repo"
}

# ── § sentinel: removed when present, harmless when absent ───────────────────
REPO="$(repo_with_origin)"
BRANCH="$(git -C "$REPO" branch --show-current)"
SENT="$(fixture_dir)/session-active"
: > "$SENT"
assert_file_exists "$SENT" "Sentinel: the fixture sentinel exists before the hook runs (non-vacuity)"
stop_hook "$REPO" "$SENT"
assert_exit 0 "Sentinel present: the hook exits 0"
assert_file_absent "$SENT" "Sentinel present: the hook removes it"

stop_hook "$REPO" "$SENT"
assert_exit 0 "Sentinel absent: the hook exits 0"
assert_eq "" "$output" "Sentinel absent: no output and no error"

# ── § unpushed: the documented warning, only when commits are ahead ──────────
stop_hook "$REPO" "$SENT"
assert_not_contains "ok:$output" "unpushed" "Everything pushed: no warning"
assert_eq "" "$output" "Everything pushed: silent"

commit "$REPO" b.txt
: > "$SENT"
stop_hook "$REPO" "$SENT"
assert_exit 0 "Unpushed commit: the hook still exits 0"
assert_contains "$output" "SESSION END: 1 unpushed commit(s) on $BRANCH" \
  "Unpushed commit: the warning counts the commit and names the branch"
assert_contains "$output" "origin/$BRANCH" "Unpushed commit: the warning names the upstream"
assert_contains "$output" "Run: git push -u origin $BRANCH" "Unpushed commit: the warning names the fix"
assert_file_absent "$SENT" "Unpushed commit: the sentinel is cleared as well"

commit "$REPO" c.txt
stop_hook "$REPO" "$SENT"
assert_contains "$output" "SESSION END: 2 unpushed commit(s)" "Two commits ahead: the count is 2"

# ── No upstream: warns only for a clean tree with commits ────────────────────
LOCAL="$(fixture_repo)"
stop_hook "$LOCAL" "$SENT"
assert_eq "" "$output" "No upstream, no commits: silent"

commit "$LOCAL" a.txt
stop_hook "$LOCAL" "$SENT"
assert_contains "$output" "has no upstream" "No upstream, clean tree with commits: warns"
assert_contains "$output" "Run: git push -u origin" "No upstream: names the fix"

echo dirty > "$LOCAL/dirty.txt"
stop_hook "$LOCAL" "$SENT"
assert_eq "" "$output" "No upstream, dirty tree: silent"

# ── Not a repository: the sentinel is still cleared, nothing is printed ──────
: > "$SENT"
stop_hook "$(fixture_dir)" "$SENT"
assert_exit 0 "Outside a repository: exits 0"
assert_eq "" "$output" "Outside a repository: silent"
assert_file_absent "$SENT" "Outside a repository: the sentinel is cleared"

# ── Kill switch ──────────────────────────────────────────────────────────────
: > "$SENT"
stop_hook "$REPO" "$SENT" SKIP_SESSION_STOP=1
assert_exit 0 "SKIP_SESSION_STOP=1: exits 0"
assert_eq "" "$output" "SKIP_SESSION_STOP=1: no warning although commits are unpushed"
assert_file_exists "$SENT" "SKIP_SESSION_STOP=1: the sentinel is left in place"

finish
