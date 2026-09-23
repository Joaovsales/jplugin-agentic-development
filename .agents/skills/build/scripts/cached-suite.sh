#!/usr/bin/env bash
# Run a full-suite command at most once per working tree.
#
# A build session used to pay for the full suite five times on one tree
# (specs/fewer-full-suite-runs.md). This wraps any command: when a green run of
# the same command on the same working tree is on record, it says so and exits
# 0 without running anything; otherwise it runs the command, passes its output
# and exit status through, and records the run only when it was green.
#
# Usage:
#   .agents/skills/build/scripts/cached-suite.sh -- <command> [args...]
#
# The key is the working tree — tracked and untracked files, not ignored ones —
# hashed through a temporary index, plus the command. Records and the lock live
# under `$(git rev-parse --git-common-dir)/cached-suite/`, shared by every
# worktree of the repository and never committed.
#
# One suite at a time: while a run holds the lock, a second invocation prints
# `cached-suite: a suite is already running (pid <n>, since <UTC time>)` and
# exits 3. A lock whose pid is no longer alive is reclaimed.
#
# Exit status: the command's own; 3 when another suite holds the lock; 2 on
# usage or a working tree that cannot be hashed. The command may exit 2 or 3
# itself, so a caller tells a refusal apart by the `cached-suite:` line on
# stderr, never by the status alone. A green run whose tree changed while it
# ran is not recorded.
set -uo pipefail

die() { printf 'cached-suite: %s\n' "$1" >&2; exit 2; }

[ "${1:-}" = "--" ] || die "usage: cached-suite.sh -- <command> [args...]"
shift
[ $# -ge 1 ] || die "usage: cached-suite.sh -- <command> [args...]"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf 'cached-suite: not a git repository, running uncached\n' >&2
  "$@"
  exit $?
fi

STORE="$(git rev-parse --path-format=absolute --git-common-dir)/cached-suite"
LOCK="$STORE/lock"
mkdir -p "$STORE" || die "cannot create $STORE"
SCRATCH="$(mktemp -d "$STORE/tmp.XXXXXX")" || die "mktemp failed under $STORE"
OWNS_LOCK=0
cleanup() {
  rm -rf "$SCRATCH"
  # Only the lock this process wrote: a reclaimer that raced us may own it now.
  if [ "$OWNS_LOCK" -eq 1 ] && read -r owner _ < "$LOCK/owner" 2>/dev/null && [ "$owner" = "$$" ]; then
    rm -rf "$LOCK"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# working_tree_hash: the tree object `git add -A` would commit right now,
# written through a copy of the index so the real one is never touched.
working_tree_hash() {
  index="$(git rev-parse --path-format=absolute --git-path index)"
  # -p keeps the index's mtime, so git's racy-entry check still re-hashes
  # files modified in the same second the index was written.
  [ -f "$index" ] && cp -p "$index" "$SCRATCH/index"
  top="$(git rev-parse --show-toplevel)"
  # safecrlf off: a mixed-line-ending file must not make the tree unhashable.
  GIT_INDEX_FILE="$SCRATCH/index" git -c core.safecrlf=false -C "$top" add -A 2>"$SCRATCH/add.err" \
    || { cat "$SCRATCH/add.err" >&2; return 1; }
  GIT_INDEX_FILE="$SCRATCH/index" git -C "$top" write-tree
}

# lock_is_stale: the owner's pid is dead, or no owner was ever written and the
# lock is over a minute old (its creator died between mkdir and the write).
lock_is_stale() {
  if read -r pid since < "$LOCK/owner" 2>/dev/null && [ -n "$pid" ]; then
    ! kill -0 "$pid" 2>/dev/null
  else
    pid="unknown"; since="unknown"
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]
  fi
}

# take_lock: `mkdir` is the atomic test-and-set; a stale lock is reclaimed once.
take_lock() {
  for attempt in 1 2; do
    if mkdir "$LOCK" 2>/dev/null; then
      OWNS_LOCK=1
      printf '%s %s\n' "$$" "$(utc_now)" > "$LOCK/owner"
      return 0
    fi
    lock_is_stale || break
    # Re-read just before removing: a reclaimer that won the race has written
    # its own owner line, and that lock is live.
    read -r current _ < "$LOCK/owner" 2>/dev/null || current="unknown"
    [ "$current" = "$pid" ] || break
    rm -rf "$LOCK"
  done
  printf 'cached-suite: a suite is already running (pid %s, since %s)\n' "${pid:-unknown}" "${since:-unknown}" >&2
  exit 3
}

take_lock
TREE="$(working_tree_hash)" || die "could not hash the working tree"
COMMAND_HASH="$(printf '%s\0' "$@" | git hash-object --stdin)"
RECORD="$STORE/$TREE-$COMMAND_HASH"

if [ -f "$RECORD" ]; then
  printf 'cached-suite: reused green run of %s on tree %s from %s\n' "$*" "$TREE" "$(cat "$RECORD")"
  exit 0
fi

"$@"
status=$?
if [ "$status" -eq 0 ]; then
  # A tree edited during the run was not the tree that was tested.
  if [ "$(working_tree_hash)" = "$TREE" ]; then
    printf '%s UTC\n' "$(date -u '+%Y-%m-%d %H:%M:%S')" > "$SCRATCH/record" && mv "$SCRATCH/record" "$RECORD"
  else
    printf 'cached-suite: the working tree changed during the run, not recorded\n' >&2
  fi
fi
exit "$status"
