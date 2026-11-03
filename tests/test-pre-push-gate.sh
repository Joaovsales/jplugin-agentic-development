# tests/test-pre-push-gate.sh — the wrap-up coverage gate in .agents/git-hooks/pre-push,
# and the hook's two blocking branches (typecheck and lint failures, § exit-branches).
#
# The wrap-up gate warns and records; it never blocks, so those cases assert
# exit 0 and the real signal is stderr plus the tasks/wrap-up-debt.md ledger.
#
# Fixtures are throwaway git repos under a temp dir. The hook is copied in and
# driven exactly as git drives it: argv is `<remote-name> <remote-url>` and the
# refs arrive on stdin as `<local-ref> <local-sha> <remote-ref> <remote-sha>`.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/.agents/git-hooks/pre-push"
ZERO="0000000000000000000000000000000000000000"

# new_repo <label> — an initialised repo with one base commit on master.
# Ships a tracked tasks/todo.md carrying no session summary: this is a repo that
# uses the workflow and simply has not wrapped up. A repo that does *not* use the
# workflow is modelled by deleting that file (see the noworkflow fixture), which
# is the signal the gate keys on.
new_repo() {
  d="$(fixture_repo)"
  mkdir -p "$d/tasks"
  git -C "$d" symbolic-ref HEAD refs/heads/master
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

# commit_wrapup <dir> <heading> [bullet...] — the wrap-up commit: tasks/todo.md
# replaced by one `## Session Summary` heading and its bullets.
commit_wrapup() {
  _d="$1"; shift
  printf '%s\n' "$@" > "$_d/tasks/todo.md"
  git -C "$_d" add -A
  git -C "$_d" commit -qm "chore: wrap up"
}

# assert_no_ledger <dir> <message> — the gate wrote no tasks/wrap-up-debt.md.
assert_no_ledger() {
  assert_file_absent "$1/tasks/wrap-up-debt.md" "$2"
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
commit_wrapup "$D" \
  "## Session Summary — 2026-09-02 [$(short "$D" "$BASE")..$(short "$D" "$CODE")]" \
  "- Completed: 1 task"
TIP="$(sha "$D")"
run_hook "$D" "$TIP" "$BASE"

assert_eq "0" "$HOOK_RC" "Covered: exits zero"
assert_eq "" "$OUT" "Covered: prints nothing"
assert_no_ledger "$D" "Covered: writes no ledger entry"

# ── The wrap-up commit itself is covered (Contract clause 2) ─────────────────
# TIP above is the commit that *introduced* the session-summary line; it is not
# inside the range it records. It must not be reported.
assert_not_contains "not-empty:$OUT" "$(short "$D" "$TIP")" \
  "Wrap-up commit: not reported as uncovered"

# ── Covered range of several commits: silent ─────────────────────────────────
# `git rev-list` prints one SHA per line. The one-commit range above never
# exercised that: a command substitution strips the single trailing newline.
# Two or more commits put newlines inside the covered list, and the
# space-delimited membership test must still find every one of them.
D="$(new_repo multicovered)"
BASE="$(sha "$D")"
commit_code "$D" a.py
commit_code "$D" b.py
commit_code "$D" c.py
CODE="$(sha "$D")"
commit_wrapup "$D" \
  "## Session Summary — 2026-10-20 [$(short "$D" "$BASE")..$(short "$D" "$CODE")]" \
  "- Completed: 3 tasks"
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Multi-commit range: exits zero"
assert_eq "" "$OUT" "Multi-commit range: every commit in the range is covered"
assert_no_ledger "$D" "Multi-commit range: writes no ledger entry"

# ── Bracketed date in the heading is not a fingerprint ───────────────────────
# /wrap-up-session documents the heading as `## Session Summary — [YYYY-MM-DD]
# [a..b]`. The date group is skipped, not named as an unparseable fingerprint
# on every push, and the range beside it still covers the commit.
D="$(new_repo bracketdate)"
BASE="$(sha "$D")"
commit_code "$D" src.py
CODE="$(sha "$D")"
commit_wrapup "$D" "## Session Summary — [2026-10-20] [$(short "$D" "$BASE")..$(short "$D" "$CODE")]"
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Bracketed date: exits zero"
assert_eq "" "$OUT" "Bracketed date: neither reported as unparseable nor a gap"

# ── Docs-only push: silent, no ledger ────────────────────────────────────────
D="$(new_repo docsonly)"
BASE="$(sha "$D")"
commit_docs "$D" NOTES.md
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Docs-only: exits zero"
assert_eq "" "$OUT" "Docs-only: prints nothing"
assert_no_ledger "$D" "Docs-only: writes no ledger entry"

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

# ── A stale local base does not inflate the range ────────────────────────────
# The base is resolved against origin/<base> first. A local `master` that has not
# been updated is not the target branch's tip, and every commit it wrongly adds to
# the range is recorded as uncovered debt. Observed 2026-10-25: a local master 192
# commits behind origin/master turned a 10-commit branch into a 76-commit debt
# entry and a 22-spec reconciliation candidate set.
#
# The fixture is a first push of a feature branch whose commit is already on
# origin/master (it was merged there), while local master still points at the base.
D="$(new_repo staleremote)"
BASE="$(sha "$D")"
git -C "$D" checkout -qb feature
git -C "$D" branch -q --set-upstream-to=master feature 2>/dev/null || true
commit_code "$D" src.py
CODE="$(sha "$D")"
git -C "$D" update-ref refs/remotes/origin/master "$CODE"
run_hook "$D" "$CODE" "$ZERO"

assert_eq "0" "$HOOK_RC" "Stale local base: exits zero"
assert_no_ledger "$D" "Stale local base: no debt for a commit already on origin/master"
assert_eq "" "$OUT" "Stale local base: gate silent"

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
commit_wrapup "$D" "## Session Summary — 2026-09-01 [907ac6d..worktree]"
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Malformed: exits zero"
assert_contains "$OUT" "worktree" "Malformed: names the bad fingerprint"
assert_contains "$OUT" "$CODE" "Malformed: does not widen — code commit still reported"

# ── The hook reaches no tracker and no network ───────────────────────────────
# Behavioural, not a source grep: the ledger header legitimately *documents* the
# `/task-registry upsert` command as guidance text, and grepping source cannot
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
  pass "Hook: no network or tracker command invoked"
fi

# ── session-start surfaces the ledger for a human to file ────────────────────
# The gate cannot create the issue itself (approval floor + no network in a
# hook), so the banner is the handoff point. Silent when there is no debt.
BANNER="$REPO/.agents/hooks/session-start.sh"
D="$(new_repo banner)"
cp "$BANNER" "$D/session-start.sh"
BAN_OUT="$( cd "$D" && CCW_SESSION_GUARD=0 bash ./session-start.sh </dev/null 2>/dev/null )"
assert_not_contains "not-empty:$BAN_OUT" "WRAP-UP DEBT" \
  "Banner: silent when no ledger exists"

printf '# Wrap-Up Debt\n\n## master abc1234..def5678\n- Recorded: 2026-09-02\n' \
  > "$D/tasks/wrap-up-debt.md"
BAN_OUT="$( cd "$D" && CCW_SESSION_GUARD=0 bash ./session-start.sh </dev/null 2>/dev/null )"
assert_contains "$BAN_OUT" "WRAP-UP DEBT" "Banner: reports outstanding debt"
assert_contains "$BAN_OUT" "master abc1234..def5678" "Banner: names the range"
assert_contains "$BAN_OUT" "/task-registry upsert" "Banner: names how to file it"
# A hand-typed id is how two runs mint different ids and `upsert` stops being
# idempotent. The banner must hand over a derived one, not a placeholder.
assert_contains "$BAN_OUT" "wrap-up-debt.master-abc1234-def5678" \
  "Banner: the filing id is derived from the entry, not left to be typed"
assert_not_contains "$BAN_OUT" "<id>" \
  "Banner: no placeholder id survives into the printed invocation"

# The banner reimplements registry.model.slugify_id in shell, because a
# session-start hook must not depend on the skill's scripts being installed. Two
# normalizers that disagree mint two ids for one debt entry -- silently, and only
# on the second run -- so the agreement is pinned rather than trusted. A branch
# name may contain `'`, so the emitted line must also survive being pasted.
SLUGGY="$REPO/.agents/skills/task-registry/scripts"
if [ -d "$SLUGGY" ]; then
  for heading in "master abc1234..def5678" "feat/o'brien 111..222" "---weird---" "FEAT/Caps 1..2" "!!!"; do
    bash_slug=$(printf '%s' "$heading" | tr '[:upper:]' '[:lower:]' \
      | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')
    [ -n "$bash_slug" ] || bash_slug=task
    py_slug=$(PYTHONPATH="$SLUGGY" "$TEST_PYTHON" -c \
      'import sys; from registry.model import slugify_id; print(slugify_id(sys.argv[1]))' "$heading")
    assert_eq "$py_slug" "$bash_slug" \
      "Banner slug agrees with slugify_id for: $heading"
    valid=$(PYTHONPATH="$SLUGGY" "$TEST_PYTHON" -c \
      'import sys; from registry.model import is_valid_id; print(is_valid_id("wrap-up-debt." + sys.argv[1]))' "$bash_slug")
    assert_eq "True" "$valid" \
      "Banner slug yields an id upsert accepts for: $heading"
  done
fi

# A heading carrying a single quote must not break the command the banner prints.
QD="$(fixture_dir)"; mkdir -p "$QD/tasks"
cp "$REPO/.agents/hooks/session-start.sh" "$QD/session-start.sh"
printf "# Wrap-Up Debt\n\n## feat/o'brien abc1234..def5678\n- Recorded: 2026-09-08\n" \
  > "$QD/tasks/wrap-up-debt.md"
Q_OUT="$( cd "$QD" && CCW_SESSION_GUARD=0 bash ./session-start.sh </dev/null 2>/dev/null )"
printf '%s\n' "$Q_OUT" | grep '/task-registry upsert' | sed 's/^ *//' > "$QD/emitted.sh"
if bash -n "$QD/emitted.sh" 2>/dev/null; then q_parses=yes; else q_parses=no; fi
assert_eq "yes" "$q_parses" \
  "Banner: a branch name containing a quote still yields a parseable command"
assert_contains "$Q_OUT" "wrap-up-debt.feat-o-brien-abc1234-def5678" \
  "Banner: the quote is normalized out of the id, not left to break it"
rm -rf "$QD"

# ── Deployment: the gate must actually reach existing repos ──────────────────
# A git template dir applies only to repos created afterwards, which is exactly
# how the previous pre-push guard stayed dormant. Both install paths are pinned.
assert_file_contains "$REPO/install.sh" 'git rev-parse --git-common-dir' \
  "install.sh: installs into the current repo, not only the template dir"
assert_file_contains "$REPO/.agents/skills/sync/SKILL.md" \
  'cp .agents/git-hooks/pre-push' \
  "sync: refreshes the hook in an already-cloned repo"

# The deprecated second pre-push script is gone: two pre-push scripts in one
# tree is an invitation to edit the dormant one.
assert_file_absent "$REPO/.agents/hooks/pre-push-guard.sh" "Deprecated pre-push-guard.sh removed"

# ── Hostile fingerprint: option-shaped endpoint never reaches git ────────────
# tasks/todo.md is attacker-controllable in a cloned repo. An endpoint starting
# with `-` would arrive at git as an option rather than a rev, so endpoints are
# validated as bare hex at the trust boundary before any git call.
D="$(new_repo hostile)"
BASE="$(sha "$D")"
commit_code "$D" src.py
CODE="$(short "$D")"
commit_wrapup "$D" "## Session Summary — 2026-09-02 [--upload-pack=touch /tmp/pwned..HEAD]"
run_hook "$D" "$(sha "$D")" "$BASE"

assert_eq "0" "$HOOK_RC" "Hostile fingerprint: exits zero"
assert_contains "$OUT" "unparseable" "Hostile fingerprint: rejected as unparseable"
assert_contains "$OUT" "$CODE" "Hostile fingerprint: does not widen coverage"

# ── § exit-branches: typecheck and lint failures block the push (exit 1) ─────
# The hook runs `npm run typecheck` then `npm run lint` when package.json
# declares them (it needs jq to read the scripts). A failing script is the one
# thing it blocks on, so both exit-1 branches are driven by a fixture
# package.json whose scripts print a marker and exit 1 or 0.
if command -v jq >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  # scripts_repo <name> <typecheck-script> <lint-script> — a repo declaring both scripts.
  scripts_repo() {
    _d="$(new_repo "$1")"
    printf '{"name":"fx","version":"1.0.0","scripts":{"typecheck":"%s","lint":"%s"}}\n' "$2" "$3" \
      > "$_d/package.json"
    printf '%s' "$_d"
  }

  D="$(scripts_repo typecheckfails "echo TYPE-ERR && exit 1" "exit 0")"
  run_hook "$D" "$(sha "$D")" "$(sha "$D")"
  assert_eq "1" "$HOOK_RC" "Typecheck fails: blocks the push with exit 1"
  assert_contains "$OUT" "BLOCKED: npm run typecheck failed" "Typecheck fails: names the failing script"
  assert_contains "$OUT" "TYPE-ERR" "Typecheck fails: shows the tail of the script's own output"
  assert_not_contains "$OUT" "npm run lint" "Typecheck fails: stops before lint runs"

  D="$(scripts_repo lintfails "exit 0" "echo LINT-ERR && exit 1")"
  run_hook "$D" "$(sha "$D")" "$(sha "$D")"
  assert_eq "1" "$HOOK_RC" "Lint fails: blocks the push with exit 1"
  assert_contains "$OUT" "BLOCKED: npm run lint failed" "Lint fails: names the failing script"
  assert_contains "$OUT" "LINT-ERR" "Lint fails: shows the tail of the script's own output"
  assert_not_contains "$OUT" "npm run typecheck" "Lint fails: typecheck had passed, so it is not blamed"

  D="$(scripts_repo bothfail "echo TYPE-ERR && exit 1" "echo LINT-ERR && exit 1")"
  run_hook "$D" "$(sha "$D")" "$(sha "$D")"
  assert_eq "1" "$HOOK_RC" "Both fail: blocks the push with exit 1"
  assert_contains "$OUT" "npm run typecheck failed" "Both fail: typecheck is reported first"
  assert_not_contains "$OUT" "npm run lint" "Both fail: lint is never reached"

  D="$(scripts_repo bothpass "exit 0" "exit 0")"
  run_hook "$D" "$(sha "$D")" "$(sha "$D")"
  assert_eq "0" "$HOOK_RC" "Both pass: the push is allowed"
  assert_eq "" "$OUT" "Both pass: nothing on stderr"

  D="$(scripts_repo killed "echo TYPE-ERR && exit 1" "exit 1")"
  cp "$HOOK" "$D/hook"; chmod +x "$D/hook"
  OUT="$( cd "$D" && printf 'refs/heads/master %s refs/heads/master %s\n' "$(sha "$D")" "$(sha "$D")" \
          | SKIP_PREPUSH=1 ./hook origin url 2>&1 )"
  assert_eq "" "$OUT" "SKIP_PREPUSH=1: failing scripts are not run"
else
  skip "typecheck/lint exit branches need jq and npm on PATH"
fi

finish
