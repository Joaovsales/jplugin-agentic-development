# tests/test-session-start.sh — P1 compaction-aware SessionStart restore branch.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/.claude/hooks/session-start.sh"
cd "$REPO"

# These three exercise `source` parsing, not the double-invocation guard, and
# run back-to-back in one repo — which is indistinguishable from the double
# registration the guard exists to collapse. CCW_SESSION_GUARD=0 isolates them,
# as every store test below already does; the guard has its own block at the end.

# --- source=compact -> lightweight restore, NO full banner ---
out_compact=$(printf '{"source":"compact"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_compact" "Context was just compacted" "P1: compact source prints restore block"
assert_not_contains "$out_compact" "SKILLS AVAILABLE" "P1: compact source skips full skills banner"
assert_not_contains "$out_compact" "tasks/memory.md" "M3: compact restore no longer points at memory.md"
assert_contains "$out_compact" "tasks/solutions" "M3: compact restore points at the typed store"

# --- source=startup -> full banner ---
out_startup=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_startup" "SKILLS AVAILABLE" "P1: startup source prints full banner"

# --- empty/absent stdin -> defaults to full banner (no regression) ---
out_empty=$(printf '' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_empty" "SKILLS AVAILABLE" "P1: empty stdin defaults to full banner"

# --- M3 store cutover: one-line counts, no bodies, no retired files ---------
tmpS=$(mktemp -d)
cd "$tmpS"
mkdir -p tasks/solutions/patterns
cat > tasks/solutions/patterns/doc-one.md <<'EOF'
---
title: Doc one
date: 2026-08-11
problem_type: pattern
module: tests
tags: [fixture]
applies_when: testing the session-start store line
needs_review: true
---
SECRET-BODY-MARKER-ONE
EOF
cat > tasks/solutions/patterns/doc-two.md <<'EOF'
---
title: Doc two
date: 2026-08-11
problem_type: pattern
module: tests
tags: [fixture]
applies_when: testing the session-start store line
---
SECRET-BODY-MARKER-TWO
EOF
out_store=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_store" "tasks/solutions" "M3: banner names the store"
assert_contains "$out_store" "2 document" "M3: banner reports document count"
assert_contains "$out_store" "1 needs_review" "M3: banner reports needs_review count"
assert_not_contains "$out_store" "SECRET-BODY-MARKER" "M3: banner dumps no document bodies"
assert_not_contains "$out_store" "tasks/memory.md" "M3: banner no longer references tasks/memory.md"
assert_not_contains "$out_store" "tasks/lessons.md" "M3: banner no longer references tasks/lessons.md"
assert_eq "false" "$([ -f tasks/memory.md ] && echo true || echo false)" \
  "M3: hook no longer bootstraps tasks/memory.md"
cd "$REPO"
rm -rf "$tmpS"

# --- M3 regression: a store with ZERO needs_review docs must not kill the ---
# banner (grep exits 1 on no match; under set -eo pipefail that aborted the
# hook). Also: the store README's own literal mention of the flag must not be
# counted as a flagged document.
tmpZ=$(mktemp -d)
cd "$tmpZ"
mkdir -p tasks/solutions/patterns tasks/solutions/bugs
printf '`needs_review: true` is documentation, not a flag\n' > tasks/solutions/README.md
cat > tasks/solutions/patterns/clean-doc.md <<'EOF'
---
title: Clean doc
date: 2026-08-13
problem_type: pattern
module: tests
tags: [fixture]
applies_when: testing the zero-flag store path
---
Body.
EOF
# A *document* that quotes the flag in its prose. Scoping the search to category
# directories excludes the store README but not this, and a store of documents
# about this system will inevitably quote its markers — one in the real store
# does, which made the banner report a flag that no document carried.
cat > tasks/solutions/bugs/quotes-the-flag.md <<'EOF'
---
title: Quotes the flag in prose
date: 2026-08-13
problem_type: bug
module: tests
tags: [fixture]
symptoms: none, this is a fixture
root_cause: none
resolution: none
---
This document explains that `needs_review: true` in frontmatter marks a document
for review. The mention is prose, not a flag:

    needs_review: true
EOF
out_zero=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
ec_zero=$?
assert_eq "0" "$ec_zero" "M3: zero-flag store does not abort the hook"
assert_contains "$out_zero" "SKILLS AVAILABLE" "M3: zero-flag store still prints the full banner"
assert_contains "$out_zero" "2 documents, 0 needs_review" \
  "M3: neither the README nor a document quoting the flag is counted as flagged"
assert_not_contains "$out_zero" "Partially migrated" \
  "M3: fully-migrated store gets no partial-migration warning"
cd "$REPO"
rm -rf "$tmpZ"

# --- M3: unmigrated-store branch — old files present, no tasks/solutions/ ---
tmpU=$(mktemp -d)
cd "$tmpU"
mkdir -p tasks
printf '# Memory\n' > tasks/memory.md
out_unmig=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_unmig" "Unmigrated learning store" \
  "M3: old-store repo gets the migration pointer"
assert_contains "$out_unmig" "migrate-learning-store.py" \
  "M3: migration pointer names the script"
cd "$REPO"
rm -rf "$tmpU"

# --- M3: half-migrated repo — store AND old files both present --------------
tmpP=$(mktemp -d)
cd "$tmpP"
mkdir -p tasks/solutions/patterns
printf '# Memory\n' > tasks/memory.md
out_partial=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_partial" "LEARNING STORE" \
  "M3: half-migrated repo still prints store counts"
assert_contains "$out_partial" "Partially migrated" \
  "M3: half-migrated repo warns about orphaned old-store files"
cd "$REPO"
rm -rf "$tmpP"

# --- M3: no-store branch — neither old files nor tasks/solutions/ -----------
tmpN=$(mktemp -d)
cd "$tmpN"
out_none=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_none" "No learning store yet" \
  "M3: storeless repo gets the bootstrap line"
cd "$REPO"
rm -rf "$tmpN"

# --- M3: maintenance nudge fires on a multiple of 5 history entries ---------
tmpM=$(mktemp -d)
cd "$tmpM"
mkdir -p tasks/solutions/patterns
for d in 01 02 03 04 05; do
  printf '### [2026-08-%s] — session %s\n- Key changes: x\n\n' "$d" "$d" >> tasks/history.md
done
out_five=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_contains "$out_five" "MEMORY MAINTENANCE DUE (5 sessions)" \
  "M3: nudge fires at 5 bracketed-date history entries"
printf '### [2026-08-06] — session 06\n- Key changes: x\n\n' >> tasks/history.md
out_six=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
assert_not_contains "$out_six" "MEMORY MAINTENANCE DUE" \
  "M3: nudge stays silent off the multiple of 5"
cd "$REPO"
rm -rf "$tmpM"

# --- Double-invocation guard: key stable per session, distinct across them ---
# The guard exists because the hook is registered twice per session. Its key has
# to be narrow enough to still collapse those two, and wide enough that a
# *different* session never inherits the sentinel — a key that is too broad eats
# the second session's banner entirely.
#
# The $PPID fallback failed the second half on Windows: bash spawned from a
# native Windows parent (node, python) reports PPID=1, so every session in every
# repo keyed to one constant sentinel and the second repo's banner vanished.
tmpG=$(mktemp -d)
mkdir -p "$tmpG"/repo-{a,b,c,d} "$tmpG/tmp"

# Output is redirected to a file rather than captured with $(...) — that detail
# is load-bearing. A command substitution forks a fresh subshell per call, so
# each invocation would see a *different* $PPID and the old key would look
# session-distinct here even on Windows, where it is not. Redirected, every
# invocation shares this script's shell as its parent, reproducing the collision
# Windows produces for real on every platform. (This is why the old guard was
# inert under test and the defect went uncaught.)
#
# TMPDIR/CLAUDE_SESSION_SENTINEL are set per-invocation, never exported, so the
# fixture's sentinels stay out of the ones a live session is using AND the
# environment cannot leak into whatever test is appended after this block.
guard_rc=0
guard_run() {  # guard_run <cwd> <hook-json> <outfile>
  cd "$1"
  printf '%s' "$2" \
    | TMPDIR="$tmpG/tmp" CLAUDE_SESSION_SENTINEL="$tmpG/tmp/active" \
      bash "$HOOK" > "$3" 2> "$3.err"
  guard_rc=$?
  cd "$REPO"
}

# "Silent" must mean exited 0 having printed nothing — not "produced no stdout".
# A hook that dies before printing also produces no stdout, so asserting stdout
# alone lets a crash pass as correct suppression. That is exactly how a fatal
# `set -e` abort in the guard's own fallback once shipped under a green suite.
assert_guard_silent() {  # assert_guard_silent <outfile> <message>
  assert_eq "0" "$guard_rc" "$2 — exited 0 rather than crashing"
  assert_eq "" "$(cat "$1")" "$2"
  assert_eq "" "$(cat "$1.err")" "$2 — nothing on stderr"
}

# Two repos, no session_id in the payload -> each gets its own banner.
guard_run "$tmpG/repo-a" '{"source":"startup"}' "$tmpG/a.out"
guard_run "$tmpG/repo-b" '{"source":"startup"}' "$tmpG/b.out"
assert_contains "$(cat "$tmpG/a.out")" "SKILLS AVAILABLE" "guard: first repo prints the banner"
assert_contains "$(cat "$tmpG/b.out")" "SKILLS AVAILABLE" \
  "guard: a second repo inside the freshness window still gets its own banner"

# Same repo, no session_id -> the second registration is de-duplicated. This
# also pins the accepted residual: the cwd key cannot tell this from a genuinely
# new session in the same repo, so that one is suppressed too until the window
# expires (asserted below).
guard_run "$tmpG/repo-a" '{"source":"startup"}' "$tmpG/a2.out"
assert_guard_silent "$tmpG/a2.out" "guard: the repo's second registration stays silent"

# An absent payload (tty / empty stdin) must take the same cwd branch, not crash.
guard_run "$tmpG/repo-c" '' "$tmpG/e.out"
assert_contains "$(cat "$tmpG/e.out")" "SKILLS AVAILABLE" \
  "guard: an empty payload still keys on cwd and prints"

# The freshness window is the ONLY escape from a per-checkout key, so pin it.
# -t with a fixed old stamp is the portable form (GNU and BSD both take it).
touch -t 200101010000 "$tmpG/tmp"/.ccw-session-start-* 2>/dev/null || true
guard_run "$tmpG/repo-a" '{"source":"startup"}' "$tmpG/a3.out"
assert_contains "$(cat "$tmpG/a3.out")" "SKILLS AVAILABLE" \
  "guard: a stale sentinel expires rather than wedging the hook permanently"

# session_id is the primary key. Running the pair from DIFFERENT cwds is what
# makes this discriminating: the cwd fallback alone cannot explain the collapse,
# so only an actually-parsed session_id can — and it is parsed without jq.
guard_run "$tmpG/repo-b" '{"source":"startup","session_id":"aaaa-1111"}' "$tmpG/s1.out"
guard_run "$tmpG/repo-d" '{"source":"startup","session_id":"aaaa-1111"}' "$tmpG/s2.out"
assert_contains "$(cat "$tmpG/s1.out")" "SKILLS AVAILABLE" "guard: session_id's first registration prints"
assert_guard_silent "$tmpG/s2.out" \
  "guard: one session_id collapses across two cwds (so it was really parsed, without jq)"

# A different session_id in the SAME repo is a different session -> prints.
guard_run "$tmpG/repo-b" '{"source":"startup","session_id":"bbbb-2222"}' "$tmpG/s3.out"
assert_contains "$(cat "$tmpG/s3.out")" "SKILLS AVAILABLE" \
  "guard: a new session in the same repo is not swallowed by the previous one"

# Ids are not restricted to [A-Za-z0-9_-]; a rejected id would fall back to the
# cwd key and silently collapse two distinct sessions in one repo.
guard_run "$tmpG/repo-b" '{"source":"startup","session_id":"sess.1/2+3="}' "$tmpG/s5.out"
guard_run "$tmpG/repo-b" '{"source":"startup","session_id":"sess.9/8+7="}' "$tmpG/s6.out"
assert_contains "$(cat "$tmpG/s5.out")" "SKILLS AVAILABLE" \
  "guard: a punctuation-bearing session_id is accepted, not dropped to the cwd key"
assert_contains "$(cat "$tmpG/s6.out")" "SKILLS AVAILABLE" \
  "guard: a second punctuation-bearing id is still a distinct session"

# A later source under one session_id must not inherit the startup sentinel.
guard_run "$tmpG/repo-b" '{"source":"compact","session_id":"aaaa-1111"}' "$tmpG/s4.out"
assert_contains "$(cat "$tmpG/s4.out")" "Context was just compacted" \
  "guard: compact is keyed apart from startup within one session"

# cksum absent: the documented raw-path degradation must actually happen. Under
# `set -eo pipefail` an unguarded pipeline here killed the hook outright (exit
# 127, zero output) — a total banner loss worse than the bug this file fixes.
shimG=$(mktemp -d)
printf '#!/bin/bash\nexit 127\n' > "$shimG/cksum"
chmod +x "$shimG/cksum"
cd "$tmpG/repo-d"
printf '{"source":"startup"}' \
  | PATH="$shimG:$PATH" TMPDIR="$tmpG/tmp2" CLAUDE_SESSION_SENTINEL="$tmpG/tmp/active" \
    bash "$HOOK" > "$tmpG/nock.out" 2>/dev/null
nock_rc=$?
cd "$REPO"
assert_eq "0" "$nock_rc" "guard: a missing cksum degrades rather than killing the hook"
assert_contains "$(cat "$tmpG/nock.out")" "SKILLS AVAILABLE" \
  "guard: the banner still prints when cksum is unavailable"
rm -rf "$shimG"

cd "$REPO"
rm -rf "$tmpG"

# --- UPSTREAM STALENESS: the banner must say when the clone is behind ---------
# A clone that is behind its upstream shows an incomplete picture of the repo,
# and every read the agent makes is silently wrong. This was diagnosed after a
# session planned a feature against a tree 9 commits stale, re-specifying a
# capability that had already merged. The banner reported "branch: master |
# uncommitted changes: 9" and said nothing about the divergence.
#
# The check must not fetch: it reports what git already knows from the last
# fetch. The /sync drift check owns the (capped, cached) network call; making
# this one hit the network too would put a timeout in every session start.
tmpU=$(mktemp -d)
git init -q --bare "$tmpU/origin.git"
git clone -q "$tmpU/origin.git" "$tmpU/work" 2>/dev/null
git -C "$tmpU/work" config user.name fixture
git -C "$tmpU/work" config user.email fixture@example.test
printf 'one\n' > "$tmpU/work/f.txt"
git -C "$tmpU/work" add f.txt && git -C "$tmpU/work" commit -qm one
printf 'two\n' > "$tmpU/work/f.txt"
git -C "$tmpU/work" commit -qam two
git -C "$tmpU/work" push -q origin HEAD 2>/dev/null
git -C "$tmpU/work" branch --set-upstream-to=origin/master &>/dev/null \
  || git -C "$tmpU/work" branch --set-upstream-to=origin/main &>/dev/null

# current clone -> silent about divergence (Observability Discipline)
cd "$tmpU/work"
out_current=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
cd "$REPO"
assert_contains "$out_current" "SKILLS AVAILABLE" "upstream: banner still prints when current"
assert_not_contains "$out_current" "BEHIND UPSTREAM" "upstream: silent when the clone is current"

# behind by one -> loud, with the count
git -C "$tmpU/work" reset -q --hard HEAD~1
cd "$tmpU/work"
out_behind=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
cd "$REPO"
assert_contains "$out_behind" "BEHIND UPSTREAM" "upstream: reports a stale clone"
assert_contains "$out_behind" "1 commit" "upstream: names how many commits behind"
assert_contains "$out_behind" "git pull" "upstream: names the remedy"

# no upstream configured -> silent, not an error
git -C "$tmpU/work" branch --unset-upstream &>/dev/null
cd "$tmpU/work"
out_noup=$(printf '{"source":"startup"}' | CCW_SESSION_GUARD=0 bash "$HOOK" 2>/dev/null)
noup_rc=$?
cd "$REPO"
assert_eq "0" "$noup_rc" "upstream: no configured upstream is not an error"
assert_not_contains "$out_noup" "BEHIND UPSTREAM" "upstream: silent with no upstream configured"

rm -rf "$tmpU"


finish
