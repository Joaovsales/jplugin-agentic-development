#!/bin/bash
# tests/test-cached-suite.sh — .agents/skills/build/scripts/cached-suite.sh
# (specs/fewer-full-suite-runs.md AC 1 and 2): a green run of a command on a
# working tree is recorded and reused; a red run, an edited or added file, or a
# different command runs again; a second invocation while one runs refuses
# with exit 3, and a lock left by a dead pid is reclaimed.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/.agents/skills/build/scripts/cached-suite.sh"
BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT
[ -n "$BOX" ] && [ -d "$BOX" ] || { printf 'mktemp -d failed\n' >&2; exit 1; }

# A fixture repository with one committed file and one ignored path. The
# command under test lives outside it, so running it never changes the tree.
FIX="$BOX/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
printf 'one\n' > "$FIX/file.txt"
printf 'ignored.txt\n' > "$FIX/.gitignore"
git -C "$FIX" add -A
git -C "$FIX" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init

RUNS="$BOX/runs"
: > "$RUNS"
cat > "$BOX/count.sh" <<'EOF'
printf 'x\n' >> "$RUNS"
printf 'ran %s\n' "${1:-}"
printf 'to stderr\n' >&2
case "${1:-}" in fail) exit 1 ;; seven) exit 7 ;; esac
exit 0
EOF
export RUNS
runs() { wc -l < "$RUNS" | tr -d ' '; }
cached() { (cd "$FIX" && bash "$SCRIPT" -- bash "$BOX/count.sh" "$@") 2>&1; }

# --- reuse (AC 1) ---------------------------------------------------------
OUT="$(cached)"; STATUS=$?
assert_eq "0" "$STATUS" "first run: exit status of the command passes through"
assert_contains "$OUT" "ran " "first run: the command's stdout passes through"
assert_contains "$OUT" "to stderr" "first run: the command's stderr passes through"
assert_eq "1" "$(runs)" "first run: the command ran once"

OUT="$(cached)"; STATUS=$?
assert_eq "0" "$STATUS" "second run: exits 0"
assert_contains "$OUT" "cached-suite: reused green run of bash $BOX/count.sh on tree " \
  "second run: names the reused green run"
assert_contains "$OUT" " UTC" "second run: names when the green run happened"
assert_not_contains "$OUT" "ran " "second run: the command did not run"
assert_eq "1" "$(runs)" "second run: the counter did not move"

OUT="$(cached seven)"; STATUS=$?
assert_eq "7" "$STATUS" "red run: a non-zero exit status passes through unchanged"
OUT="$(cached fail)"; STATUS=$?
assert_eq "1" "$STATUS" "red run: exit 1 passes through"
OUT="$(cached fail)"; STATUS=$?
assert_eq "4" "$(runs)" "red run: not recorded, so the same command runs again"

OUT="$(cached other)"
assert_contains "$OUT" "ran other" "different command on the same tree: runs"

printf 'two\n' >> "$FIX/file.txt"
OUT="$(cached)"
assert_contains "$OUT" "ran " "edited tracked file: runs again"
OUT="$(cached)"
assert_contains "$OUT" "cached-suite: reused green run" "edited tree, second time: reused"

printf 'new\n' > "$FIX/untracked.txt"
OUT="$(cached)"
assert_contains "$OUT" "ran " "added untracked file: runs again"

printf 'noise\n' > "$FIX/ignored.txt"
OUT="$(cached)"
assert_contains "$OUT" "cached-suite: reused green run" "ignored file only: the green record is reused"

assert_eq "" "$(git -C "$FIX" status --porcelain -- file.txt | grep -v '^ M' || true)" \
  "the real index is untouched (file.txt still unstaged)"
assert_eq "?? untracked.txt" "$(git -C "$FIX" status --porcelain -- untracked.txt)" \
  "the real index is untouched (untracked.txt still untracked)"
COMMON="$(git -C "$FIX" rev-parse --git-common-dir)"
case "$COMMON" in /*|?:*) ;; *) COMMON="$FIX/$COMMON" ;; esac
assert_eq "yes" "$([ -d "$COMMON/cached-suite" ] && echo yes)" \
  "records live under the git common dir"

NOREPO="$BOX/plain"
mkdir -p "$NOREPO"
OUT="$( (cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$BOX" bash "$SCRIPT" -- bash "$BOX/count.sh" plain) 2>&1)"; STATUS=$?
assert_contains "$OUT" "cached-suite: not a git repository, running uncached" "outside a repo: says so"
assert_contains "$OUT" "ran plain" "outside a repo: the command still runs"
assert_eq "0" "$STATUS" "outside a repo: the exit status passes through"

(cd "$FIX" && bash "$SCRIPT" </dev/null >"$BOX/usage.out" 2>&1)
assert_eq "2" "$?" "usage: no -- and no command exits 2"

# --- lock (AC 2) ----------------------------------------------------------
cat > "$BOX/slow.sh" <<'EOF'
: > "$BOX/started"
i=0
while [ ! -f "$BOX/release" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
EOF
export BOX
(cd "$FIX" && bash "$SCRIPT" -- bash "$BOX/slow.sh" >/dev/null 2>&1) &
SLOW=$!
i=0
while [ ! -f "$BOX/started" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
BEFORE="$(runs)"
OUT="$(cached locked)"; STATUS=$?
assert_eq "3" "$STATUS" "concurrent: a second invocation exits 3"
assert_contains "$OUT" "cached-suite: a suite is already running (pid " "concurrent: names the running suite"
assert_contains "$OUT" "since " "concurrent: names when it started"
assert_eq "$BEFORE" "$(runs)" "concurrent: the second command started nothing"
: > "$BOX/release"
wait "$SLOW"
assert_eq "no" "$([ -e "$COMMON/cached-suite/lock" ] && echo yes || echo no)" \
  "concurrent: the lock is removed when the run exits"

DEAD="$(bash -c 'printf %s $$')"
mkdir -p "$COMMON/cached-suite/lock"
printf '%s 2026-01-01T00:00:00Z\n' "$DEAD" > "$COMMON/cached-suite/lock/owner"
OUT="$(cached reclaimed)"; STATUS=$?
assert_eq "0" "$STATUS" "stale lock: a dead pid's lock is reclaimed"
assert_contains "$OUT" "ran reclaimed" "stale lock: the command runs"
assert_eq "no" "$([ -e "$COMMON/cached-suite/lock" ] && echo yes || echo no)" \
  "stale lock: the reclaimed lock is removed on exit"

finish
