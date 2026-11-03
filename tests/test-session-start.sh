# tests/test-session-start.sh — P1 compaction-aware SessionStart restore branch.
#
# Every hook invocation runs inside a fixture repo (fixture_repo, or a clone of
# one) — never in the live checkout, whose tasks/, remotes and plugin records
# would otherwise decide the banner.
. "$(dirname "$0")/lib.sh"

HOOK="$(under_test .agents/hooks/session-start.sh)"
STARTUP='{"source":"startup"}'
ERR="$(fixture_dir)/hook.stderr"

# fixture_only <dir> — the hook runs only in a git repository outside the live
# checkout; anything else is a failed assertion and no hook runs.
LIVE_CHECKOUT="${HOOK%/.agents/hooks/session-start.sh}"
fixture_only() {
  case "$1/" in "$LIVE_CHECKOUT"/*) fail "the hook ran against the live checkout" "$1"; return 1 ;; esac
  [ -e "$1/.git" ] || { fail "the hook ran outside a fixture repo" "$1"; return 1; }
}

# hook_in <dir> <payload> [VAR=val...] — run the hook with <dir> as cwd and
# <payload> on stdin. Stdout lands in `output`, stderr in $ERR.
hook_in() {
  local dir="$1" payload="$2"; shift 2
  fixture_only "$dir" || return 0
  run bash -c 'cd "$1" || exit 1; payload=$2; hook=$3; err=$4; shift 4
    for assignment in "$@"; do export "$assignment"; done
    printf "%s" "$payload" | bash "$hook" 2>"$err"' _ "$dir" "$payload" "$HOOK" "$ERR" "$@"
}

# startup <dir> [VAR=val...] — a startup banner with the double-invocation
# guard off. Most blocks below run several banners back-to-back in one repo,
# which is indistinguishable from the double registration the guard exists to
# collapse; the guard has its own block further down.
startup() {
  local dir="$1"; shift
  hook_in "$dir" "$STARTUP" CCW_SESSION_GUARD=0 "$@"
}

# count_lines <text> <regex> — how many lines of <text> match <regex>.
count_lines() { printf '%s\n' "$1" | grep -cE -- "$2" || true; }

# --- source=compact -> lightweight restore, NO full banner ---
R0="$(fixture_repo)"
hook_in "$R0" '{"source":"compact"}' CCW_SESSION_GUARD=0
assert_contains "$output" "Context was just compacted" "P1: compact source prints restore block"
assert_not_contains "$output" "SESSION START" "P1: compact source skips the full banner"
assert_not_contains "$output" "tasks/memory.md" "M3: compact restore no longer points at memory.md"
assert_contains "$output" "tasks/solutions" "M3: compact restore points at the typed store"

# --- source=startup -> full banner ---
startup "$R0"
assert_contains "$output" "SESSION START" "P1: startup source prints full banner"

# --- empty/absent stdin -> defaults to full banner (no regression) ---
hook_in "$R0" '' CCW_SESSION_GUARD=0
assert_contains "$output" "SESSION START" "P1: empty stdin defaults to full banner"

# --- M3 store cutover: one-line counts, no bodies, no retired files ---------
S="$(fixture_repo)"
mkdir -p "$S/tasks/solutions/patterns"
cat > "$S/tasks/solutions/patterns/doc-one.md" <<'EOF'
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
cat > "$S/tasks/solutions/patterns/doc-two.md" <<'EOF'
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
startup "$S"
assert_contains "$output" "tasks/solutions" "M3: banner names the store"
assert_contains "$output" "2 document" "M3: banner reports document count"
assert_contains "$output" "1 needs_review" "M3: banner reports needs_review count"
assert_not_contains "$output" "SECRET-BODY-MARKER" "M3: banner dumps no document bodies"
assert_not_contains "$output" "tasks/memory.md" "M3: banner no longer references tasks/memory.md"
assert_not_contains "$output" "tasks/lessons.md" "M3: banner no longer references tasks/lessons.md"
assert_file_absent "$S/tasks/memory.md" "M3: hook no longer bootstraps tasks/memory.md"

# --- M3 regression: a store with ZERO needs_review docs must not kill the ---
# banner (grep exits 1 on no match; under set -eo pipefail that aborted the
# hook). Also: the store README's own literal mention of the flag must not be
# counted as a flagged document.
Z="$(fixture_repo)"
mkdir -p "$Z/tasks/solutions/patterns" "$Z/tasks/solutions/bugs"
printf '`needs_review: true` is documentation, not a flag\n' > "$Z/tasks/solutions/README.md"
cat > "$Z/tasks/solutions/patterns/clean-doc.md" <<'EOF'
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
cat > "$Z/tasks/solutions/bugs/quotes-the-flag.md" <<'EOF'
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
startup "$Z"
assert_exit 0 "M3: zero-flag store does not abort the hook"
assert_contains "$output" "SESSION START" "M3: zero-flag store still prints the full banner"
assert_contains "$output" "2 documents, 0 needs_review" \
  "M3: neither the README nor a document quoting the flag is counted as flagged"
assert_not_contains "$output" "Partially migrated" \
  "M3: fully-migrated store gets no partial-migration warning"

# --- Recurrence of the same defect one directory deeper ----------------------
# Narrowing the glob to skip the store README fixed the symptom, not the cause:
# an UNANCHORED grep counts every *mention* of the flag, and a category document
# may mention it too. The store now contains exactly such a document -- the bug
# report about this counter -- which quotes `needs_review: true` in its prose and
# was therefore counted as flagged. The flag is frontmatter, so the match must be
# anchored to the start of a line.
M="$(fixture_repo)"
mkdir -p "$M/tasks/solutions/bugs"
printf 'store\n' > "$M/tasks/solutions/README.md"
cat > "$M/tasks/solutions/bugs/mentions-the-flag.md" <<'EOF'
---
title: A document that discusses the flag without carrying it
date: 2026-09-05
problem_type: bug
module: tests
tags: [fixture]
symptoms: none
root_cause: none
resolution: none
---
The counter matched every document containing `needs_review: true` in prose,
including this sentence and the line below.

    REVIEW_COUNT=$(grep -rl 'needs_review: true' tasks/solutions/*/ | wc -l)
EOF
startup "$M"
assert_contains "$output" "1 documents, 0 needs_review" \
  "M3: a document that MENTIONS the flag in prose is not counted as flagged"

# --- M3: unmigrated-store branch — old files present, no tasks/solutions/ ---
U="$(fixture_repo)"
mkdir -p "$U/tasks"
printf '# Memory\n' > "$U/tasks/memory.md"
startup "$U"
assert_contains "$output" "Unmigrated learning store" \
  "M3: old-store repo gets the migration pointer"
assert_contains "$output" "migrate-learning-store.py" \
  "M3: migration pointer names the script"

# --- M3: half-migrated repo — store AND old files both present --------------
P="$(fixture_repo)"
mkdir -p "$P/tasks/solutions/patterns"
printf '# Memory\n' > "$P/tasks/memory.md"
startup "$P"
assert_contains "$output" "LEARNING STORE" \
  "M3: half-migrated repo still prints store counts"
assert_contains "$output" "Partially migrated" \
  "M3: half-migrated repo warns about orphaned old-store files"

# --- M3: no-store branch — neither old files nor tasks/solutions/ -----------
N="$(fixture_repo)"
startup "$N"
assert_contains "$output" "No learning store yet" \
  "M3: storeless repo gets the bootstrap line"

# --- Maintenance counts both session heading formats found in history ------
# assert_maintenance_notice <repo> <expected-count|''> <label>
assert_maintenance_notice() {
  local dir="$1" expected="$2" label="$3"
  startup "$dir" CLAUDE_SESSION_SENTINEL="$dir/session-active"
  assert_exit 0 "$label: hook succeeds"
  assert_contains "$output" "SESSION START" "$label: full banner runs"
  if [ -n "$expected" ]; then
    assert_contains "$output" "MEMORY MAINTENANCE DUE ($expected sessions)" "$label: reminder counts sessions"
  else
    assert_not_contains "$output" "MEMORY MAINTENANCE DUE" "$label: no reminder"
  fi
}

H="$(fixture_repo)"
HIST="$H/tasks/history.md"
mkdir -p "$H/tasks/solutions/patterns"
for d in 01 02 03 04 05; do
  printf '### [2026-08-%s] — session %s\n- Key changes: x\n\n' "$d" "$d" >> "$HIST"
done
assert_maintenance_notice "$H" 5 "five canonical entries"
printf '### [2026-08-06] — session 06\n- Key changes: x\n\n' >> "$HIST"
assert_maintenance_notice "$H" '' "six canonical entries"

for format in alternate mixed; do
  : > "$HIST"
  for d in 01 02 03 04 05; do
    if [ "$format" = mixed ] && [ "$d" != 05 ]; then
      printf '### [2026-08-%s] — session\n' "$d" >> "$HIST"
    else
      printf '## 2026-08-%s — session\n' "$d" >> "$HIST"
    fi
  done
  assert_maintenance_notice "$H" 5 "five $format entries"
done

head -n 4 "$HIST" > "$H/four-sessions.md"
cp "$H/four-sessions.md" "$HIST"
assert_maintenance_notice "$H" '' "four sessions"
for heading in \
  '### Round 2 review (2026-08-05)' \
  'A prose date: 2026-08-05' \
  '#### [2026-08-05] — nested heading' \
  '### [2026-08-05 — missing bracket' \
  '### [2026-08-05]suffix — missing separator' \
  '## 2026-08-05suffix — missing separator' \
  '## 2026-8-05 — short month' \
  '### [2026-08-5] — short day'; do
  cp "$H/four-sessions.md" "$HIST"
  printf '%s\n' "$heading" >> "$HIST"
  assert_maintenance_notice "$H" '' "four sessions plus $heading"
done

: > "$HIST"
assert_maintenance_notice "$H" '' "empty history"
rm "$HIST"
assert_maintenance_notice "$H" '' "missing history"
for ((session=0; session<10; session++)); do
  printf '## 2026-08-05 — session %s\n' "$session" >> "$HIST"
done
assert_maintenance_notice "$H" 10 "ten sessions on the same date"

# --- Double-invocation guard: key stable per session, distinct across them ---
# The guard exists because the hook is registered twice per session. Its key has
# to be narrow enough to still collapse those two, and wide enough that a
# *different* session never inherits the sentinel — a key that is too broad eats
# the second session's banner entirely.
#
# The $PPID fallback failed the second half on Windows: bash spawned from a
# native Windows parent (node, python) reports PPID=1, so every session in every
# repo keyed to one constant sentinel and the second repo's banner vanished.
G="$(fixture_dir)"
mkdir -p "$G/tmp"
REPO_A="$(fixture_repo)"; REPO_B="$(fixture_repo)"; REPO_C="$(fixture_repo)"; REPO_D="$(fixture_repo)"

# The hook is run directly from this shell with its output redirected to a
# file, never through run or $(...) — that detail is load-bearing. A command
# substitution forks a fresh subshell per call, so each invocation would see a
# *different* $PPID and the old key would look session-distinct here even on
# Windows, where it is not. Redirected, every invocation shares this script's
# shell as its parent, reproducing the collision Windows produces for real on
# every platform. (This is why the old guard was inert under test and the
# defect went uncaught.)
#
# TMPDIR/CLAUDE_SESSION_SENTINEL are set per-invocation, never exported, so the
# fixture's sentinels stay out of the ones a live session is using AND the
# environment cannot leak into whatever test is appended after this block.
# guard_run <cwd> <hook-json> <outfile> [VAR=val...] — judged by assert_exit
# and `output`, as run is.
guard_run() {
  local cwd="$1" json="$2" out="$3"; shift 3
  fixture_only "$cwd" || return 0
  status=0
  pushd "$cwd" >/dev/null || return 1
  printf '%s' "$json" \
    | env TMPDIR="$G/tmp" CLAUDE_SESSION_SENTINEL="$G/tmp/active" "$@" \
      bash "$HOOK" > "$out" 2> "$out.err" || status=$?
  popd >/dev/null
  output="$(<"$out")"
}

# "Silent" must mean exited 0 having printed nothing — not "produced no stdout".
# A hook that dies before printing also produces no stdout, so asserting stdout
# alone lets a crash pass as correct suppression. That is exactly how a fatal
# `set -e` abort in the guard's own fallback once shipped under a green suite.
assert_guard_silent() {  # assert_guard_silent <outfile> <message>
  assert_exit 0 "$2 — exited 0 rather than crashing"
  assert_eq "" "$output" "$2"
  assert_eq "" "$(<"$1.err")" "$2 — nothing on stderr"
}

# Two repos, no session_id in the payload -> each gets its own banner.
guard_run "$REPO_A" "$STARTUP" "$G/a.out"
assert_contains "$output" "SESSION START" "guard: first repo prints the banner"
guard_run "$REPO_B" "$STARTUP" "$G/b.out"
assert_contains "$output" "SESSION START" \
  "guard: a second repo inside the freshness window still gets its own banner"

# Same repo, no session_id -> the second registration is de-duplicated. This
# also pins the accepted residual: the cwd key cannot tell this from a genuinely
# new session in the same repo, so that one is suppressed too until the window
# expires (asserted below).
guard_run "$REPO_A" "$STARTUP" "$G/a2.out"
assert_guard_silent "$G/a2.out" "guard: the repo's second registration stays silent"

# An absent payload (tty / empty stdin) must take the same cwd branch, not crash.
guard_run "$REPO_C" '' "$G/e.out"
assert_contains "$output" "SESSION START" \
  "guard: an empty payload still keys on cwd and prints"

# The freshness window is the ONLY escape from a per-checkout key, so pin it.
# -t with a fixed old stamp is the portable form (GNU and BSD both take it).
touch -t 200101010000 "$G/tmp"/.ccw-session-start-* 2>/dev/null || true
guard_run "$REPO_A" "$STARTUP" "$G/a3.out"
assert_contains "$output" "SESSION START" \
  "guard: a stale sentinel expires rather than wedging the hook permanently"

# session_id is the primary key. Running the pair from DIFFERENT cwds is what
# makes this discriminating: the cwd fallback alone cannot explain the collapse,
# so only an actually-parsed session_id can — and it is parsed without jq.
guard_run "$REPO_B" '{"source":"startup","session_id":"aaaa-1111"}' "$G/s1.out"
assert_contains "$output" "SESSION START" "guard: session_id's first registration prints"
guard_run "$REPO_D" '{"source":"startup","session_id":"aaaa-1111"}' "$G/s2.out"
assert_guard_silent "$G/s2.out" \
  "guard: one session_id collapses across two cwds (so it was really parsed, without jq)"

# A different session_id in the SAME repo is a different session -> prints.
guard_run "$REPO_B" '{"source":"startup","session_id":"bbbb-2222"}' "$G/s3.out"
assert_contains "$output" "SESSION START" \
  "guard: a new session in the same repo is not swallowed by the previous one"

# Ids are not restricted to [A-Za-z0-9_-]; a rejected id would fall back to the
# cwd key and silently collapse two distinct sessions in one repo.
guard_run "$REPO_B" '{"source":"startup","session_id":"sess.1/2+3="}' "$G/s5.out"
assert_contains "$output" "SESSION START" \
  "guard: a punctuation-bearing session_id is accepted, not dropped to the cwd key"
guard_run "$REPO_B" '{"source":"startup","session_id":"sess.9/8+7="}' "$G/s6.out"
assert_contains "$output" "SESSION START" \
  "guard: a second punctuation-bearing id is still a distinct session"

# A later source under one session_id must not inherit the startup sentinel.
guard_run "$REPO_B" '{"source":"compact","session_id":"aaaa-1111"}' "$G/s4.out"
assert_contains "$output" "Context was just compacted" \
  "guard: compact is keyed apart from startup within one session"

# cksum absent: the documented raw-path degradation must actually happen. Under
# `set -eo pipefail` an unguarded pipeline here killed the hook outright (exit
# 127, zero output) — a total banner loss worse than the bug this file fixes.
SHIM="$(fixture_dir)"
printf '#!/bin/bash\nexit 127\n' > "$SHIM/cksum"
chmod +x "$SHIM/cksum"
guard_run "$REPO_D" "$STARTUP" "$G/nock.out" PATH="$SHIM:$PATH" TMPDIR="$G/tmp2"
assert_exit 0 "guard: a missing cksum degrades rather than killing the hook"
assert_contains "$output" "SESSION START" \
  "guard: the banner still prints when cksum is unavailable"

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
W="$(fixture_repo)"
ORIGIN="$(fixture_dir)/origin.git"
printf 'one\n' > "$W/f.txt"
git -C "$W" add f.txt && git -C "$W" commit -qm one
printf 'two\n' > "$W/f.txt"
git -C "$W" commit -qam two
git clone -q --bare "$W" "$ORIGIN"
git -C "$W" remote add origin "$ORIGIN"
git -C "$W" fetch -q origin
git -C "$W" branch --set-upstream-to="origin/$(git -C "$W" branch --show-current)" >/dev/null

# current clone -> silent about divergence (Observability Discipline)
startup "$W"
assert_contains "$output" "SESSION START" "upstream: banner still prints when current"
assert_not_contains "$output" "BEHIND UPSTREAM" "upstream: silent when the clone is current"

# behind by one -> loud, with the count
git -C "$W" reset -q --hard HEAD~1
startup "$W"
assert_contains "$output" "BEHIND UPSTREAM" "upstream: reports a stale clone"
assert_contains "$output" "1 commit" "upstream: names how many commits behind"
assert_contains "$output" "git pull" "upstream: names the remedy"

# no upstream configured -> silent, not an error
git -C "$W" branch --unset-upstream >/dev/null 2>&1
startup "$W"
assert_exit 0 "upstream: no configured upstream is not an error"
assert_not_contains "$output" "BEHIND UPSTREAM" "upstream: silent with no upstream configured"

# --- plugin declared but not installed: one line, only on that state --------
# specs/claude-plugin-manifest.md § /sync: a synced project enables
# jplugin@jplugin-agentic-development in .claude/settings.json. A user who
# declined the marketplace prompt has no jplugin: skills in that project and
# nothing else says so. Silent when installed, and when nothing is declared.
PROJ="$(fixture_repo)"
HOMED="$(fixture_dir)"
PROBE=(HOME="$HOMED" CLAUDE_CONFIG_DIR="$HOMED/.claude")
mkdir -p "$PROJ/.claude" "$HOMED/.claude/plugins"
printf '{"enabledPlugins": {"jplugin@jplugin-agentic-development": true}}\n' > "$PROJ/.claude/settings.json"
startup "$PROJ" "${PROBE[@]}"
assert_contains "$output" "PLUGIN NOT INSTALLED" \
  "Plugin: enabled in settings but absent from installed_plugins.json prints the line"
assert_contains "$output" "jplugin@jplugin-agentic-development" \
  "Plugin: the line names the plugin id"
assert_eq "1" "$(count_lines "$output" 'PLUGIN NOT INSTALLED')" \
  "Plugin: exactly one headline"
printf '{"version": 2, "plugins": {"jplugin@jplugin-agentic-development": [{"scope": "user"}]}}\n' \
  > "$HOMED/.claude/plugins/installed_plugins.json"
startup "$PROJ" "${PROBE[@]}"
assert_not_contains "$output" "PLUGIN NOT INSTALLED" \
  "Plugin: silent once installed_plugins.json records the plugin"
# A settings-driven install (Claude Code caching the plugin when the folder is
# trusted) writes no installed_plugins.json record at all -- only the versioned
# cache directory exists. Spike S4 measured it; without this branch every
# synced project warns while the plugin works.
rm -f "$HOMED/.claude/plugins/installed_plugins.json"
mkdir -p "$HOMED/.claude/plugins/cache/jplugin-agentic-development/jplugin/1.0.0"
startup "$PROJ" "${PROBE[@]}"
assert_not_contains "$output" "PLUGIN NOT INSTALLED" \
  "Plugin: silent when only the versioned cache directory records the install"
# An empty plugin directory (interrupted fetch, uninstall) records nothing.
rm -rf "$HOMED/.claude/plugins/cache/jplugin-agentic-development/jplugin/1.0.0"
startup "$PROJ" "${PROBE[@]}"
assert_contains "$output" "PLUGIN NOT INSTALLED" \
  "Plugin: a cache directory with no version under it does not count as installed"
rm -rf "$HOMED/.claude/plugins/cache"
# A project that set the plugin to false has declined it: no line.
printf '{"enabledPlugins": {"jplugin@jplugin-agentic-development": false}}\n' > "$PROJ/.claude/settings.json"
startup "$PROJ" "${PROBE[@]}"
assert_not_contains "$output" "PLUGIN NOT INSTALLED" \
  "Plugin: silent when the project disables the plugin"
# Pre-plugin copies under ~/.claude/skills/ that shadow a skill this project
# carries are named; the user's own skills there are not.
mkdir -p "$PROJ/.agents/skills/plan" "$HOMED/.claude/skills/plan" "$HOMED/.claude/skills/my-own"
startup "$PROJ" "${PROBE[@]}"
assert_contains "$output" "STALE SKILL COPIES" \
  "Stale copies: a template skill copied under ~/.claude/skills/ prints the line"
assert_contains "$output" " plan" \
  "Stale copies: the line names the shadowed skill"
assert_not_contains "$output" "my-own" \
  "Stale copies: the user's own skill is not named"
rm -rf "$HOMED/.claude/skills/plan"
startup "$PROJ" "${PROBE[@]}"
assert_not_contains "$output" "STALE SKILL COPIES" \
  "Stale copies: silent once the copy is gone"
rm -rf "$PROJ/.agents" "$HOMED/.claude/skills"
printf '{}\n' > "$PROJ/.claude/settings.json"
rm -f "$HOMED/.claude/plugins/installed_plugins.json"
startup "$PROJ" "${PROBE[@]}"
assert_not_contains "$output" "PLUGIN NOT INSTALLED" \
  "Plugin: silent when the project declares no plugin"

# --- Deployment Targets: AGENTS.md first, .claude/project.md second with a notice ---
# specs/single-instruction-file.md § Readers of project configuration (D3): the
# table moved below the managed block's end marker in AGENTS.md; a project that
# declined the migration keeps its table in .claude/project.md and must keep
# working — loudly, so the state is visible and not permanent by accident.
D="$(fixture_repo)"
mkdir -p "$D/.claude"
printf '{}\n' > "$D/railway.json"
targets_table='## Deployment Targets

| Service | Runbook | Triggers on branch | Project ID |
|---------|---------|--------------------|------------|
| Railway | .claude/deployments/railway.md | main | demo |
'
printf '# Project Instructions\n\n%s' "$targets_table" > "$D/AGENTS.md"
startup "$D"
assert_not_contains "$output" "no Deployment Targets" \
  "Targets: a table in AGENTS.md satisfies the deploy-signal nudge"
assert_not_contains "$output" "found in .claude/project.md" \
  "Targets: no notice when the table is where it belongs"
printf '# Project Instructions\n' > "$D/AGENTS.md"
printf '# Project-Specific Configuration\n\n%s' "$targets_table" > "$D/.claude/project.md"
startup "$D"
assert_not_contains "$output" "no Deployment Targets" \
  "Targets: a table still in .claude/project.md still counts — a declined migration breaks nothing"
assert_contains "$output" "Deployment Targets found in .claude/project.md — /sync will move them to AGENTS.md" \
  "Targets: the pre-single-file location prints the one-line notice"
rm "$D/.claude/project.md"
startup "$D"
assert_contains "$output" "no Deployment Targets in AGENTS.md" \
  "Targets: a deploy signal with no table anywhere nudges toward AGENTS.md"
assert_not_contains "$output" "found in .claude/project.md" \
  "Targets: no notice when there is nothing in the old location"

# --- Failure-only banner (specs/single-instruction-file.md § Invariants, D18) ---
# Nothing wrong -> header, counts, tasks, git and nothing else: no ⚠ line, no
# skills list, no footer, at most 12 lines. Each conditional line is pinned
# below with the fixture that trips it. CLAUDE_CONFIG_DIR and a private PATH
# prefix isolate the runs from this machine's plugin records and graphify.
B="$(fixture_dir)"
mkdir -p "$B/cfg" "$B/bin"
BANNER=(CLAUDE_CONFIG_DIR="$B/cfg" PATH="$B/bin:$PATH")
block_agents='# Demo

<!-- jplugin-agentic-development:begin -->
## Session Start Checklist
<!-- jplugin-agentic-development:end -->
'
# Adopting (.agents/skills/ exists), block present, graph newer than HEAD, no
# upstream, no debt, no deploy signal.
CLEAN="$(fixture_repo)"
mkdir -p "$CLEAN/.agents/skills/zz-fixture" "$CLEAN/tasks" "$CLEAN/graphify-out"
printf '%s' "$block_agents" > "$CLEAN/AGENTS.md"
printf '[ ] TDD: pending -> later\n' > "$CLEAN/tasks/todo.md"
git -C "$CLEAN" add -A && git -C "$CLEAN" commit -qm init
printf '{}' > "$CLEAN/graphify-out/graph.json"   # written after HEAD: current
startup "$CLEAN" "${BANNER[@]}"
assert_contains "$output" "SESSION START" \
  "Banner: the clean fixture prints the full banner (non-vacuity)"
assert_not_contains "$output" "⚠" \
  "Banner: nothing wrong -> no ⚠ line"
assert_not_contains "$output" "SKILLS AVAILABLE" \
  "Banner: no skills list — the README table is the one catalog"
assert_not_contains "$output" "Ready." \
  "Banner: no footer"
assert_not_contains "$output" "managed block" \
  "Banner: a present block prints no missing-block line"
clean_lines="$(printf '%s\n' "$output" | grep -c '' || true)"
assert_true "Banner: nothing wrong -> at most 12 lines (got $clean_lines)" -- [ "$clean_lines" -le 12 ]

# Graph older than HEAD -> the stale line. graphify is a stub on the private PATH.
printf '#!/bin/bash\nexit 0\n' > "$B/bin/graphify"; chmod +x "$B/bin/graphify"
touch -t 202001010000 "$CLEAN/graphify-out/graph.json"
startup "$CLEAN" "${BANNER[@]}"
assert_contains "$output" "⚠  code graph stale: graphify-out/graph.json is older than HEAD — run graphify" \
  "Banner: a graph older than HEAD prints the stale line"
# No graph: silent in a tree without code files, loud once a code file is tracked.
rm -rf "$CLEAN/graphify-out"
startup "$CLEAN" "${BANNER[@]}"
assert_not_contains "$output" "graphify installed but no graph" \
  "Banner: no graph in a tree without code files prints nothing — there is nothing to build"
printf 'print(1)\n' > "$CLEAN/main.py"
git -C "$CLEAN" add main.py && git -C "$CLEAN" commit -qm code
startup "$CLEAN" "${BANNER[@]}"
assert_contains "$output" "⚠  graphify installed but no graph — run graphify" \
  "Banner: graphify installed, code files tracked, no graph -> the missing-graph line"
rm -f "$B/bin/graphify"

# Missing block: printed only in an adopting repository (D18).
ADOPT_SKILLS="$(fixture_repo)"
mkdir -p "$ADOPT_SKILLS/.agents/skills/zz-fixture"
printf '# Project Instructions\n' > "$ADOPT_SKILLS/AGENTS.md"
startup "$ADOPT_SKILLS" "${BANNER[@]}"
assert_contains "$output" "⚠  AGENTS.md has no jplugin-agentic-development managed block — run /sync" \
  "Banner: adopting (.agents/skills/ present) without a block -> the missing-block line"
ADOPT_PLUGIN="$(fixture_repo)"
mkdir -p "$ADOPT_PLUGIN/.claude"
printf '{"enabledPlugins": {"jplugin@jplugin-agentic-development": true}}\n' > "$ADOPT_PLUGIN/.claude/settings.json"
startup "$ADOPT_PLUGIN" "${BANNER[@]}"
assert_contains "$output" "has no jplugin-agentic-development managed block" \
  "Banner: adopting (plugin enabled) with no AGENTS.md at all -> the missing-block line"
# Orphaned project.md: CLAUDE.md is the pointer, so nothing imports it (a CI-only
# sync leaves exactly this state); the line is printed until /sync moves it.
ORPHAN="$(fixture_repo)"
mkdir -p "$ORPHAN/.claude"
printf '@AGENTS.md\n' > "$ORPHAN/CLAUDE.md"
printf '<!-- jplugin-agentic-development:begin -->\nrules\n<!-- jplugin-agentic-development:end -->\n' > "$ORPHAN/AGENTS.md"
printf '## Team Rules\n\nours\n' > "$ORPHAN/.claude/project.md"
startup "$ORPHAN" "${BANNER[@]}"
assert_contains "$output" "⚠  .claude/project.md is loaded by nothing — run /sync to move it into AGENTS.md" \
  "Banner: .claude/project.md beside a pointer CLAUDE.md -> the orphaned-file line"
printf '@.claude/project.md\n' > "$ORPHAN/CLAUDE.md"
startup "$ORPHAN" "${BANNER[@]}"
assert_not_contains "$output" "loaded by nothing" \
  "Banner: a CLAUDE.md that still imports .claude/project.md prints no orphan line"
printf '@AGENTS.md\n' > "$ORPHAN/CLAUDE.md"; rm -f "$ORPHAN/.claude/project.md"
startup "$ORPHAN" "${BANNER[@]}"
assert_not_contains "$output" "loaded by nothing" \
  "Banner: no .claude/project.md -> no orphan line"
OTHER="$(fixture_repo)"
mkdir -p "$OTHER/.claude"
printf '{"enabledPlugins": {"someone-else@market": true}}\n' > "$OTHER/.claude/settings.json"
startup "$OTHER" "${BANNER[@]}"
assert_contains "$output" "SESSION START" \
  "Banner: a non-adopting repository still gets the banner (non-vacuity)"
assert_not_contains "$output" "⚠" \
  "Banner: a non-adopting repository prints no ⚠ line — the missing-block nudge is gated on adoption"

# --- Template drift compares the managed block, not the AGENTS.md path (D6) ---
# AGENTS.md is MANAGED: the template's own rules below its end marker differ
# from every project's by design, so a path diff would report drift on every
# template commit that touched only that text. Fixture: a template repository
# on disk as the `workflow` remote, and a project synced from it.
DCFG="$(fixture_dir)"
# drift_banner <project> -> a banner with a fresh drift cache
drift_banner() {
  rm -f "$1/.claude/.sync-check-cache"
  startup "$1" CLAUDE_CONFIG_DIR="$DCFG"
}
write_agents() {  # write_agents <file> <block-line> <below-line>
  printf '# Title\n\n<!-- jplugin-agentic-development:begin -->\n%s\n<!-- jplugin-agentic-development:end -->\n\n%s\n' "$2" "$3" > "$1"
}
TEMPLATE="$(fixture_repo)"
PROJECT="$(fixture_repo)"
mkdir -p "$PROJECT/.claude"
write_agents "$TEMPLATE/AGENTS.md" "RULE v1" "template's own rules"; printf '@AGENTS.md\n' > "$TEMPLATE/CLAUDE.md"
git -C "$TEMPLATE" add -A && git -C "$TEMPLATE" commit -qm init
write_agents "$PROJECT/AGENTS.md" "RULE v1" "this project's rules"; printf '@AGENTS.md\n' > "$PROJECT/CLAUDE.md"
git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm init
git -C "$PROJECT" remote add workflow "$TEMPLATE"
drift_banner "$PROJECT"
assert_contains "$output" "SESSION START" "Drift: the fixture prints the banner (non-vacuity)"
assert_not_contains "$output" "TEMPLATE DRIFT" \
  "Drift: same block, different project text -> no drift line"
write_agents "$TEMPLATE/AGENTS.md" "RULE v1" "template's own rules, edited"
git -C "$TEMPLATE" commit -qam below-marker
drift_banner "$PROJECT"
assert_not_contains "$output" "TEMPLATE DRIFT" \
  "Drift: a template commit touching only text below the end marker produces no drift line"
write_agents "$TEMPLATE/AGENTS.md" "RULE v2" "template's own rules, edited"
git -C "$TEMPLATE" commit -qam block
drift_banner "$PROJECT"
assert_contains "$output" "TEMPLATE DRIFT" \
  "Drift: a template commit changing the block produces the drift line"
assert_contains "$output" "1 item(s) differ" \
  "Drift: the block counts as one item"

# --- Stale plugin install: warn with the exact commands, never run them ------
# specs/plugin-staleness-check.md. On 2026-09-29 the installed record sat at an
# old sha while master had moved on, and nothing said so. Fixture: a template
# repository named like the real one, three commits (A at 1.0.0; B bumps to
# 1.0.1; C changes a skill and does not bump), a marketplace clone checked out
# at a chosen commit, and installed_plugins.json records written per case.
KROOT="$(fixture_dir)"
KCFG="$KROOT/cfg"
TPL="$KROOT/jplugin-agentic-development"
MKT="$KCFG/plugins/marketplaces/jplugin-agentic-development"
RECORDS="$KCFG/plugins/installed_plugins.json"
mv "$(fixture_repo)" "$TPL"
tpl_commit() {  # tpl_commit <version> <skill-text> -> commits to the template
  printf '{\n  "name": "jplugin",\n  "version": "%s"\n}\n' "$1" > "$TPL/.claude-plugin/plugin.json"
  printf '%s\n' "$2" > "$TPL/.agents/skills/x/SKILL.md"
  git -C "$TPL" add -A && git -C "$TPL" commit -qm "$2"
}
PLAIN="$(fixture_repo)"
FOREIGN="$(fixture_repo)"
mkdir -p "$TPL/.claude-plugin" "$TPL/.agents/skills/x" "$KCFG/plugins/marketplaces" "$PLAIN/.agents/skills"
tpl_commit 1.0.0 v1 >/dev/null && tpl_commit 1.0.1 v2 >/dev/null && tpl_commit 1.0.1 v3 >/dev/null
SHA_A=$(git -C "$TPL" rev-parse HEAD~2); SHA_B=$(git -C "$TPL" rev-parse HEAD~1); SHA_C=$(git -C "$TPL" rev-parse HEAD)
git clone -q "$TPL" "$MKT" 2>/dev/null
SYNCED="$KROOT/synced"
git clone -q "$TPL" "$SYNCED" 2>/dev/null
mkt_at() { git -C "$MKT" checkout -q --detach "$1" 2>/dev/null; }
json_path() {  # json_path <dir> -> the dir as installed_plugins.json writes it
  ( cd "$1" && { pwd -W 2>/dev/null || pwd; } ) | sed 's#/#\\\\#g'
}
record() {  # record <scope> <version> <sha> [projectPath] -> one JSON record
  local extra=""
  [ -n "${4:-}" ] && extra="\"projectPath\": \"$4\", "
  printf '{"scope": "%s", %s"installPath": "cache/%s", "version": "%s", "gitCommitSha": "%s"}' \
    "$1" "$extra" "$2" "$2" "$3"
}
write_records() {  # write_records <record>... -> installed_plugins.json
  local IFS=,
  printf '{\n  "version": 2,\n  "plugins": {\n    "other@market": [{"scope": "user", "version": "9.9.9", "gitCommitSha": "%s"}],\n    "jplugin@jplugin-agentic-development": [%s]\n  }\n}\n' \
    "$SHA_A" "$*" > "$RECORDS"
}
UPDATE_USER='^    claude plugin update jplugin@jplugin-agentic-development$'
UPDATE_PROJECT='^    claude plugin update jplugin@jplugin-agentic-development --scope project$'
MKT_UPDATE='^    claude plugin marketplace update jplugin-agentic-development$'

# AC 1 — user record at A, marketplace clone at its descendant B.
mkt_at "$SHA_B"; write_records "$(record user 1.0.0 "$SHA_A")"
startup "$PLAIN" CLAUDE_CONFIG_DIR="$KCFG"
assert_eq "1" "$(count_lines "$output" 'PLUGIN UPDATE AVAILABLE')" "Stale plugin: exactly one headline for one stale user record"
assert_contains "$output" "user install is at 1.0.0 (${SHA_A:0:7}); the template is at 1.0.1 (${SHA_B:0:7})" \
  "Stale plugin: the headline names both versions and short shas"
assert_eq "1" "$(count_lines "$output" "$MKT_UPDATE")" "Stale plugin: exactly one marketplace update line"
assert_eq "1" "$(count_lines "$output" "$UPDATE_USER")" "Stale plugin: exactly one user-scope plugin update line"
assert_contains "$output" "Restart Claude Code afterwards" "Stale plugin: the block says a restart follows"
assert_not_contains "$output" "--scope" "Stale plugin: a user-scope update carries no --scope"

# AC 2 — project records: this directory's prints --scope project, another path's nothing.
HERE_JSON="$(json_path "$PLAIN")"
OTHER_JSON="$(json_path "$KROOT")\\\\elsewhere"
write_records "$(record user 1.0.1 "$SHA_B")" "$(record project 1.0.0 "$SHA_A" "$HERE_JSON\\\\")" \
  "$(record project 1.0.0 "$SHA_A" "$OTHER_JSON")"
startup "$PLAIN" CLAUDE_CONFIG_DIR="$KCFG"
assert_eq "1" "$(count_lines "$output" "$UPDATE_PROJECT")" "Stale plugin: a stale project record for this path prints --scope project once"
assert_eq "1" "$(count_lines "$output" 'PLUGIN UPDATE AVAILABLE')" "Stale plugin: only this path's project record gets a headline"
assert_contains "$output" "project install is at 1.0.0" "Stale plugin: the headline names the project scope"
assert_eq "0" "$(count_lines "$output" "$UPDATE_USER")" "Stale plugin: the current user record prints no update line"
write_records "$(record project 1.0.0 "$SHA_A" "$OTHER_JSON")"
startup "$PLAIN" CLAUDE_CONFIG_DIR="$KCFG"
assert_not_contains "$output" "PLUGIN UPDATE" "Stale plugin: another path's project record prints nothing"

# AC 3 — the incident: the clone agrees with the record, the repository's remote ref is ahead.
mkt_at "$SHA_A"; write_records "$(record user 1.0.0 "$SHA_A")"
startup "$PLAIN" CLAUDE_CONFIG_DIR="$KCFG"
assert_not_contains "$output" "PLUGIN UPDATE" "Stale plugin: record equal to the clone and no matching remote is silent"
startup "$SYNCED" CLAUDE_CONFIG_DIR="$KCFG"
assert_contains "$output" "PLUGIN UPDATE AVAILABLE" "Stale plugin: a matching remote ref ahead of the record prints the block (2026-09-29)"
assert_contains "$output" "the template is at 1.0.1 (${SHA_C:0:7})" "Stale plugin: the remote ref is the template the headline names"
mkt_at "$SHA_C"; write_records "$(record user 1.0.1 "$SHA_C")"
git -C "$SYNCED" update-ref refs/remotes/origin/master "$SHA_B"
startup "$SYNCED" CLAUDE_CONFIG_DIR="$KCFG"
assert_not_contains "$output" "PLUGIN UPDATE" "Stale plugin: a record ahead of the remote ref is not stale"
git -C "$SYNCED" update-ref refs/remotes/origin/master "$SHA_C"
mkt_at "$SHA_A"; write_records "$(record user 1.0.0 0123456789abcdef0123456789abcdef01234567)"
startup "$SYNCED" CLAUDE_CONFIG_DIR="$KCFG"
assert_contains "$output" "PLUGIN UPDATE AVAILABLE" "Stale plugin: a sha unknown to the repository still falls to the clone"
assert_contains "$output" "the template is at 1.0.0 (${SHA_A:0:7})" "Stale plugin: ... and the clone is the template named"

# AC 4, 5 — silent states, and the banner always completes.
mkt_at "$SHA_C"
assert_silent_stale() {  # assert_silent_stale <project> <message>
  startup "$1" CLAUDE_CONFIG_DIR="$KCFG"
  assert_not_contains "$output" "PLUGIN UPDATE" "$2"
  assert_exit 0 "$2 (banner completes: exit 0)"
  assert_contains "$output" "🌿  GIT" "$2 (banner completes: git section printed)"
}
write_records "$(record user 1.0.1 "$SHA_C")"
assert_silent_stale "$SYNCED" "Stale plugin: record equal to every known template sha is silent"
write_records '{"scope": "user", "installPath": "C:\\x", "version": "1.0.0"}'
assert_silent_stale "$PLAIN" "Stale plugin: a record with no gitCommitSha is silent"
write_records "$(record user 1.0.0 --output=x)"
assert_silent_stale "$PLAIN" "Stale plugin: a non-hex gitCommitSha never reaches git argv"
rm -f "$RECORDS"
assert_silent_stale "$PLAIN" "Stale plugin: no installed_plugins.json is silent"
printf '{"version": 2, "plugins": {"jplugin@jplugin-agentic-development": [{"scope": "user", "gitCommitSha": "%s"' "$SHA_A" > "$RECORDS"
assert_silent_stale "$PLAIN" "Stale plugin: a malformed installed_plugins.json is silent"
write_records "$(record user 1.0.0 "$SHA_A")"
assert_silent_stale "$FOREIGN" "Stale plugin: a non-adopting repository is silent"
startup "$PLAIN" CLAUDE_CONFIG_DIR="$KCFG"
assert_contains "$output" "PLUGIN UPDATE AVAILABLE" "Stale plugin: the same record in an adopting repository prints (non-vacuity)"

# AC 6 — the newer template kept the record's version: 'plugin update' is a no-op.
mkt_at "$SHA_C"; write_records "$(record user 1.0.1 "$SHA_B")" "$(record project 1.0.1 "$SHA_B" "$HERE_JSON")"
startup "$PLAIN" CLAUDE_CONFIG_DIR="$KCFG"
assert_contains "$output" "plugin.json version 1.0.1 was not bumped — 'claude plugin update' is a no-op (README § Releasing skills)." \
  "Stale plugin: an unbumped template prints the not-bumped note"
assert_eq "1" "$(count_lines "$output" 'was not bumped')" "Stale plugin: the note prints once for two records"
assert_eq "1" "$(count_lines "$output" '^    User scope: claude plugin uninstall jplugin@jplugin-agentic-development && claude plugin install jplugin@jplugin-agentic-development$')" \
  "Stale plugin: the user record gets the user-scope reinstall line"
assert_eq "0" "$(count_lines "$output" '^    claude plugin update')" "Stale plugin: no plugin update line for an unbumped template"
assert_not_contains "$output" "uninstall jplugin@jplugin-agentic-development --scope" "Stale plugin: never a project-scope uninstall (D8)"
assert_eq "1" "$(count_lines "$output" "$MKT_UPDATE")" "Stale plugin: the marketplace update line still prints"

# AC 7 — the block reads only what the last fetch recorded.
SWEEP="$(fixture_dir)"
awk '/^# ── Stale Plugin Install Check/ { p = 1; next } p && /^# ── / { exit } p' "$HOOK" > "$SWEEP/block.sh"
assert_file_contains "$SWEEP/block.sh" "gitCommitSha" "Stale plugin: the block is found in the hook (non-vacuity)"
grep -vE '^[[:space:]]*#' "$SWEEP/block.sh" > "$SWEEP/code.sh" || true
sed 's/"[^"]*"//g' "$SWEEP/code.sh" > "$SWEEP/code-unquoted.sh"
# One control file holds a line each sweep pattern is written to catch, so an
# empty sweep means the block is clean and not that the pattern went blind.
printf 'git fetch origin\nthen claude plugin update x\nfoo | jq .\n' > "$SWEEP/control.sh"
assert_sweep_empty "Stale plugin: the block makes no network call (D4)" "$SWEEP/control.sh" -- \
  grep -E 'fetch|ls-remote|curl|wget' -- "$SWEEP/code.sh"
assert_sweep_empty "Stale plugin: the block never invokes claude, only prints its commands (D1)" "$SWEEP/control.sh" -- \
  grep -E '(^|[;&|(]|then|do)[[:space:]]*claude[[:space:]]' -- "$SWEEP/code-unquoted.sh"
assert_sweep_empty "Stale plugin: the block parses JSON without jq or python (D9)" "$SWEEP/control.sh" -- \
  grep -E '(^|[^A-Za-z_])(jq|python3?)([^A-Za-z_]|$)' -- "$SWEEP/code.sh"

finish
