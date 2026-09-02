# tests/test-pre-push-gate.sh — the wrap-up coverage gate in .agents/git-hooks/pre-push.
#
# The gate warns and records; it never blocks. Every case therefore asserts
# exit 0, and the real signal is stderr plus the tasks/wrap-up-debt.md ledger.
#
# Fixtures are throwaway git repos under a temp dir. The hook is copied in and
# driven exactly as git drives it: argv is `<remote-name> <remote-url>` and the
# refs arrive on stdin as `<local-ref> <local-sha> <remote-ref> <remote-sha>`.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/.agents/git-hooks/pre-push"
ZERO="0000000000000000000000000000000000000000"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# new_repo <name> — an initialised repo with one base commit on master.
# Ships a tracked tasks/todo.md carrying no session summary: this is a repo that
# uses the workflow and simply has not wrapped up. A repo that does *not* use the
# workflow is modelled by deleting that file (see the noworkflow fixture), which
# is the signal the gate keys on.
new_repo() {
  d="$WORK/$1"
  mkdir -p "$d/tasks"
  git -C "$d" init -q -b master
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  echo base > "$d/base.txt"
  printf '# Tasks\n\n## Plan: something\n' > "$d/tasks/todo.md"
  git -C "$d" add -A
  git -C "$d" commit -qm base
  printf '%s' "$d"
}

# commit_code <dir> <file> — one commit touching a non-doc file.
commit_code() {
  echo "change $(date +%s%N)" > "$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -qm "code: $2"
}

# commit_docs <dir> <file>
commit_docs() {
  echo "doc $(date +%s%N)" > "$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -qm "docs: $2"
}

# run_hook <dir> <local-sha> <remote-sha> — drive the hook.
# Sets OUT (stderr) and HOOK_RC. Deliberately not used inside a command
# substitution: that runs the function in a subshell and the exit code never
# reaches the caller, which silently turns every rc assertion into a no-op.
run_hook() {
  cp "$HOOK" "$1/hook"
  chmod +x "$1/hook"
  err="$1/.stderr"
  ( cd "$1" && printf 'refs/heads/master %s refs/heads/master %s\n' "$2" "$3" \
      | ./hook origin "https://example.invalid/r.git" >/dev/null 2>"$err" )
  HOOK_RC=$?
  OUT="$(cat "$err")"
}

sha() { git -C "$1" rev-parse "${2:-HEAD}"; }
short() { git -C "$1" rev-parse --short "${2:-HEAD}"; }

# ── Uncovered code push: exits 0, warns, records ─────────────────────────────
D="$(new_repo uncovered)"
BASE="$(sha "$D")"
commit_code "$D" src.py
TIP="$(sha "$D")"
run_hook "$D" "$TIP" "$BASE"

assert_eq "0" "$HOOK_RC" "Uncovered: never blocks the push"
assert_contains "$OUT" "$(short "$D")" "Uncovered: names the uncovered short-SHA"
assert_contains "$OUT" "/wrap-up-session" "Uncovered: names the fix"
assert_contains "$OUT" "SKIP_WRAPUP_GATE" "Uncovered: names the kill switch"
assert_file_contains "$D/tasks/wrap-up-debt.md" "$(short "$D")" \
  "Uncovered: records a ledger entry"

# ── Repeat push of the same range updates in place ───────────────────────────
run_hook "$D" "$TIP" "$BASE"
COUNT="$(grep -c "$(short "$D")" "$D/tasks/wrap-up-debt.md" 2>/dev/null || echo 0)"
assert_eq "1" "$COUNT" "Repeat: same range recorded once, not duplicated"

# ── Covered code push: exits 0, silent ───────────────────────────────────────
D="$(new_repo covered)"
BASE="$(sha "$D")"
commit_code "$D" src.py
CODE="$(sha "$D")"
{
  echo "## Session Summary — 2026-09-02 [$(git -C "$D" rev-parse --short "$BASE")..$(git -C "$D" rev-parse --short "$CODE")]"
  echo "- Completed: 1 task"
} > "$D/tasks/todo.md"
git -C "$D" add -A
git -C "$D" commit -qm "chore: wrap up"
TIP="$(sha "$D")"
run_hook "$D" "$TIP" "$BASE"

assert_eq "0" "$HOOK_RC" "Covered: exits zero"
assert_eq "" "$OUT" "Covered: prints nothing"
if [ -f "$D/tasks/wrap-up-debt.md" ]; then
  assert_eq "absent" "present" "Covered: writes no ledger entry"
else
  assert_eq "absent" "absent" "Covered: writes no ledger entry"
fi

# ── The wrap-up commit itself is covered (Contract clause 2) ─────────────────
# TIP above is the commit that *introduced* the session-summary line; it is not
# inside the range it records. It must not be reported.
assert_not_contains "not-empty:$OUT" "$(short "$D" "$TIP")" \
  "Wrap-up commit: not reported as uncovered"

# ── Docs-only push: silent, no ledger ────────────────────────────────────────
D="$(new_repo docsonly)"
BASE="$(sha "$D")"
commit_docs "$D" NOTES.md
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Docs-only: exits zero"
assert_eq "" "$OUT" "Docs-only: prints nothing"
if [ -f "$D/tasks/wrap-up-debt.md" ]; then
  assert_eq "absent" "present" "Docs-only: writes no ledger entry"
else
  assert_eq "absent" "absent" "Docs-only: writes no ledger entry"
fi

# ── Repo not using the workflow (no tasks/todo.md): silent ───────────────────
D="$(new_repo noworkflow)"
git -C "$D" rm -q -r --cached tasks >/dev/null
rm -rf "$D/tasks"
git -C "$D" commit -qm "drop workflow files"
BASE="$(sha "$D")"
commit_code "$D" src.py
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "No todo.md: exits zero"
assert_eq "" "$OUT" "No todo.md: prints nothing"

# ── Branch deletion (zero local sha): silent ─────────────────────────────────
D="$(new_repo deletion)"
run_hook "$D" "$ZERO" "$(sha "$D")"
assert_eq "0" "$HOOK_RC" "Deletion: exits zero"
assert_eq "" "$OUT" "Deletion: prints nothing"

# ── New branch (zero remote sha): resolves from merge-base ───────────────────
D="$(new_repo newbranch)"
git -C "$D" checkout -qb feature
commit_code "$D" src.py
run_hook "$D" "$(sha "$D")" "$ZERO"
assert_eq "0" "$HOOK_RC" "New branch: exits zero"
assert_contains "$OUT" "$(short "$D")" "New branch: reports the uncovered commit"

# ── Merge commits are exempt ─────────────────────────────────────────────────
D="$(new_repo merges)"
BASE="$(sha "$D")"
git -C "$D" checkout -qb side
commit_code "$D" side.py
git -C "$D" checkout -q master
git -C "$D" merge -q --no-ff -m "merge side" side
MERGE="$(short "$D")"
run_hook "$D" "$(sha "$D")" "$BASE"
assert_not_contains "not-empty:$OUT" "$MERGE" "Merge commit: exempt from coverage"

# ── Kill switch ──────────────────────────────────────────────────────────────
D="$(new_repo killswitch)"
BASE="$(sha "$D")"
commit_code "$D" src.py
cp "$HOOK" "$D/hook"; chmod +x "$D/hook"
OUT="$( cd "$D" && printf 'refs/heads/master %s refs/heads/master %s\n' "$(sha "$D")" "$BASE" \
        | SKIP_WRAPUP_GATE=1 ./hook origin url 2>&1 )"
assert_eq "" "$OUT" "SKIP_WRAPUP_GATE=1: gate silent"
OUT="$( cd "$D" && printf 'refs/heads/master %s refs/heads/master %s\n' "$(sha "$D")" "$BASE" \
        | SKIP_PREPUSH=1 ./hook origin url 2>&1 )"
assert_eq "" "$OUT" "SKIP_PREPUSH=1: whole hook silent"

# ── Malformed fingerprint: reported, neither widens nor suppresses ───────────
D="$(new_repo malformed)"
BASE="$(sha "$D")"
commit_code "$D" src.py
CODE="$(short "$D")"
echo "## Session Summary — 2026-09-01 [907ac6d..worktree]" > "$D/tasks/todo.md"
git -C "$D" add -A
git -C "$D" commit -qm "chore: malformed summary"
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Malformed: exits zero"
assert_contains "$OUT" "worktree" "Malformed: names the bad fingerprint"
assert_contains "$OUT" "$CODE" "Malformed: does not widen — code commit still reported"

# ── The hook reaches no tracker and no network ───────────────────────────────
# Behavioural, not a source grep: the ledger header legitimately *documents* the
# `/task-registry publish` command as guidance text, and grepping source cannot
# tell a mention from an invocation. Shim the binaries and prove none are run.
D="$(new_repo nonetwork)"
BASE="$(sha "$D")"
commit_code "$D" src.py
mkdir -p "$D/shims"
for prog in curl wget gh nc ssh; do
  printf '#!/bin/sh\necho "$0" >> "%s/.invoked"\n' "$D" > "$D/shims/$prog"
  chmod +x "$D/shims/$prog"
done
cp "$HOOK" "$D/hook"; chmod +x "$D/hook"
( cd "$D" && printf 'refs/heads/master %s refs/heads/master %s\n' "$(sha "$D")" "$BASE" \
    | PATH="$D/shims:$PATH" ./hook origin url >/dev/null 2>&1 )
if [ -f "$D/.invoked" ]; then
  assert_eq "none" "$(tr '\n' ' ' < "$D/.invoked")" "Hook: no network or tracker command invoked"
else
  assert_eq "none" "none" "Hook: no network or tracker command invoked"
fi

# ── session-start surfaces the ledger for a human to file ────────────────────
# The gate cannot create the issue itself (approval floor + no network in a
# hook), so the banner is the handoff point. Silent when there is no debt.
BANNER="$REPO/.claude/hooks/session-start.sh"
D="$(new_repo banner)"
cp "$BANNER" "$D/session-start.sh"
BAN_OUT="$( cd "$D" && CCW_SESSION_GUARD=0 bash ./session-start.sh 2>/dev/null )"
assert_not_contains "not-empty:$BAN_OUT" "WRAP-UP DEBT" \
  "Banner: silent when no ledger exists"

printf '# Wrap-Up Debt\n\n## master abc1234..def5678\n- Recorded: 2026-09-02\n' \
  > "$D/tasks/wrap-up-debt.md"
BAN_OUT="$( cd "$D" && CCW_SESSION_GUARD=0 bash ./session-start.sh 2>/dev/null )"
assert_contains "$BAN_OUT" "WRAP-UP DEBT" "Banner: reports outstanding debt"
assert_contains "$BAN_OUT" "master abc1234..def5678" "Banner: names the range"
assert_contains "$BAN_OUT" "/task-registry publish" "Banner: names how to file it"

# ── Deployment: the gate must actually reach existing repos ──────────────────
# A git template dir applies only to repos created afterwards, which is exactly
# how the previous pre-push guard stayed dormant. Both install paths are pinned.
assert_file_contains "$REPO/install.sh" 'git rev-parse --git-common-dir' \
  "install.sh: installs into the current repo, not only the template dir"
assert_file_contains "$REPO/.agents/skills/sync/SKILL.md" \
  'cp .agents/git-hooks/pre-push' \
  "sync: refreshes the hook in an already-cloned repo"
assert_files_identical "$REPO/.agents/skills/sync/SKILL.md" \
  "$REPO/.claude/skills/sync/SKILL.md" "sync: both skill trees stay in parity"

# The deprecated second pre-push script is gone: two pre-push scripts in one
# tree is an invitation to edit the dormant one.
if [ -f "$REPO/.claude/hooks/pre-push-guard.sh" ]; then
  assert_eq "removed" "present" "Deprecated pre-push-guard.sh removed"
else
  assert_eq "removed" "removed" "Deprecated pre-push-guard.sh removed"
fi

# ── Hostile fingerprint: option-shaped endpoint never reaches git ────────────
# tasks/todo.md is attacker-controllable in a cloned repo. An endpoint starting
# with `-` would arrive at git as an option rather than a rev, so endpoints are
# validated as bare hex at the trust boundary before any git call.
D="$(new_repo hostile)"
BASE="$(sha "$D")"
commit_code "$D" src.py
CODE="$(short "$D")"
echo "## Session Summary — 2026-09-02 [--upload-pack=touch /tmp/pwned..HEAD]" > "$D/tasks/todo.md"
git -C "$D" add -A
git -C "$D" commit -qm "chore: hostile summary"
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Hostile fingerprint: exits zero"
assert_contains "$OUT" "unparseable" "Hostile fingerprint: rejected as unparseable"
assert_contains "$OUT" "$CODE" "Hostile fingerprint: does not widen coverage"

finish
