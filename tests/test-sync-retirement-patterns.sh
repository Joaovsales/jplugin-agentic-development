#!/bin/bash
# tests/test-sync-retirement-patterns.sh — behavioural contract for deterministic
# retirement in /sync (specs/sync-deterministic-retirement.md).
#
# WHY THIS EXISTS
#
# `/sync` copies files in and never deletes. A path present in a project but
# absent from the template is either retired upstream or project-specific, and
# nothing recorded which — so the answer was re-derived by a model on every run
# and two runs against one template commit could produce different trees.
#
# The mechanism under test replaces that judgement with set arithmetic:
#
#   retire = project paths under syncable roots
#          - template paths under the same roots
#          - paths matching a .claude/sync-keep pattern
#
# Every assertion below exists to pin one half of that sentence: that the inputs
# are read the same way twice, and that nothing outside the difference is ever
# deleted.
#
# One of the files split from the former tests/test-sync-retirement.sh at its
# section seams (specs/test-suite-aposd.md D4). Every piece declares the same
# artefact, so tests/affected.sh selects all of them on a change to sync-retire.py.
# Each section is a case: TEST_CASE='<glob>' bash tests/test-sync-retirement-patterns.sh runs only the
# cases whose name matches. The fixture builders below are the few lines every
# piece needs; they build one template and one project, once, and each scenario
# copies them (61 identical repositories at three spawns each was a third of the
# original file's Windows runtime, specs/test-suite-aposd.md F14).
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

RETIRE="$(under_test .agents/skills/sync/scripts/sync-retire.py)"

FIXTURE_ROOT="$(fixture_dir)"

# Write one fixture file, creating its directory when needed. The builders
# below pre-create every directory in one mkdir, so the common path here is two
# builtins and no process; a path outside those directories still gets its own.
# On Windows a process costs 100-500 ms and this file writes ~900 fixture files,
# so `mkdir -p "$(dirname ...)"` per file was a third of its runtime (#136).
_f() {
  case "$1" in */*) [ -d "${1%/*}" ] || mkdir -p "${1%/*}" ;; esac
  printf '%s\n' "$2" > "$1"
}

# The doc block the script parses for its root list: the seed under
# tests/fixtures/sync/, in the same shape as the real § Syncable Paths fence
# (`path   → description`) so a fixture cannot pass against a parser that the
# real block would defeat. $2, when given, is an extra root line appended inside
# the fence.
write_skill_md() {
  _dir="$1" _extra="${2:-}"
  fixture_copy sync/syncable-paths.md "$_dir/.agents/skills/sync/SKILL.md"
  [ -z "$_extra" ] || add_root_row "$_dir/.agents/skills/sync/SKILL.md" "$_extra"
}

# add_root_row <skill-md> <row> — the row goes before the fence's closing line.
add_root_row() {
  EXTRA_ROW="$2" awk '/^```/ && ++_fences == 2 { print ENVIRON["EXTRA_ROW"] } { print }' "$1" > "$1.new" \
    && mv "$1.new" "$1"
}

# The one template checkout: the doc block plus one file under every directory
# root, so no root is "absent from the template" unless a test says so.
BASE_TEMPLATE="$(fixture_dir)"
write_skill_md "$BASE_TEMPLATE"
mkdir -p "$BASE_TEMPLATE/.agents/skills/build" "$BASE_TEMPLATE/.agents/agents" "$BASE_TEMPLATE/.claude/skills/build" "$BASE_TEMPLATE/.claude/hooks"
_f "$BASE_TEMPLATE/.agents/skills/build/SKILL.md"   "build skill"
_f "$BASE_TEMPLATE/.agents/agents/planner.md"       "planner"
_f "$BASE_TEMPLATE/.claude/skills/build/SKILL.md"   "build skill"
_f "$BASE_TEMPLATE/.claude/hooks/session-start.sh"  "hook"
_f "$BASE_TEMPLATE/CLAUDE.md"                       "rules"
_f "$BASE_TEMPLATE/.claude/settings.json"           "{}"

# make_template <dir> [extra-root-row]
make_template() {
  _dir="$1" _extra="${2:-}"
  mkdir -p "$_dir"
  cp -R "$BASE_TEMPLATE/." "$_dir/"
  [ -z "$_extra" ] || add_root_row "$_dir/.agents/skills/sync/SKILL.md" "$_extra"
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "state" 2>/dev/null || true
}

# A project: a git repo, because the project inventory is the set of *tracked*
# files. Untracked build residue was never synced in, so it is never retired.
# It starts as the template's tree, committed once.
BASE_PROJECT="$(fixture_repo)"
git -C "$BASE_PROJECT" symbolic-ref HEAD refs/heads/main
cp -R "$BASE_TEMPLATE/." "$BASE_PROJECT/"
commit_all "$BASE_PROJECT"

make_project() {
  _dir="$1"
  mkdir -p "$_dir"
  cp -R "$BASE_PROJECT/." "$_dir/"
}

# Run the script through the library's `run`: stdout and stderr land in `output`,
# the exit code in `status`.
run_retire() {
  run "$TEST_PYTHON" "$RETIRE" "$@"
}

# Write a .claude/sync-keep from the remaining arguments, one pattern per line.
write_keep() {
  _dir="$1"; shift
  mkdir -p "$_dir/.claude"
  : > "$_dir/.claude/sync-keep"
  for _line in "$@"; do printf '%s\n' "$_line" >> "$_dir/.claude/sync-keep"; done
}

# ============================================================== 1. patterns
if begin_case "1. patterns"; then
#
# A sync-keep pattern is the only thing standing between a project-specific
# file and deletion. Every rejection below is a pattern that would otherwise
# fail *silently* — recorded intent that protects nothing — so the run must
# stop rather than proceed with an allowlist that does less than it appears to.

printf '\n-- 1. sync-keep pattern parsing and validation --\n'

P1="$FIXTURE_ROOT/p1"; T1="$FIXTURE_ROOT/t1"
make_project "$P1"; make_template "$T1"
# A project-only path exists, so a run that ignored its allowlist would delete
# something — every invalid-pattern case below has real stakes.
_f "$P1/.agents/skills/local-only/SKILL.md" "project specific"
commit_all "$P1"

# Blank lines and comments are ignored, not treated as patterns.
write_keep "$P1" "# a comment" "" "   " ".agents/skills/local-only/**"
run_retire --repo "$P1" --from-dir "$T1"
assert_exit 0 "comments and blank lines in sync-keep are ignored"
assert_contains "$output" "kept:" "the surviving path is reported as kept"

# Each invalid pattern: exits 1, names the guard that refused it (the reason
# fragment), the offending pattern AND its line, and deletes nothing. The
# fragment is what keeps a later guard from satisfying the row: with the
# absolute-path check removed, `_reaches_a_root` still refuses "/etc/passwd"
# by naming the same pattern and line. The line number matters -- an allowlist
# is edited by hand and "some pattern is bad" is not an actionable message.
assert_invalid_pattern() {
  _pattern="$1" _reason="$2" _label="$3"
  write_keep "$P1" "# leading comment" "$_pattern"
  assert_refused 1 "$_reason" "invalid pattern ($_label): exits 1 naming the guard that refused it" \
    -- "$TEST_PYTHON" "$RETIRE" --repo "$P1" --from-dir "$T1" --apply
  assert_contains "$output" "$_pattern" "invalid pattern ($_label): names the pattern"
  assert_contains "$output" "line 2" "invalid pattern ($_label): names the line"
  assert_file_exists "$P1/.agents/skills/local-only/SKILL.md" \
    "invalid pattern ($_label): --apply deleted nothing"
}

assert_invalid_pattern "/etc/passwd"                      "absolute path not allowed"      "absolute"
assert_invalid_pattern ".agents/skills/../../etc"         "traversal not allowed"          "parent traversal"
assert_invalid_pattern '.agents\skills\x'                 "use POSIX separators"           "backslash separators"
assert_invalid_pattern '.agents/skills/[ab]/SKILL.md'     "unsupported glob syntax"        "unsupported [] glob"
assert_invalid_pattern '.agents/skills/{a,b}/SKILL.md'    "unsupported glob syntax"        "unsupported {} brace expansion"
assert_invalid_pattern '.agents/skills/!a/SKILL.md'       "unsupported glob syntax"        "unsupported ! negation"
assert_invalid_pattern 'C:/agents/skills/x.md'            "absolute path not allowed"      "windows drive letter is absolute"
assert_invalid_pattern 'tasks/**'                         "outside every syncable root"    "outside every syncable root"

# An empty pattern cannot be written as a bare line (it would be a blank line,
# which is ignored), so it arrives as whitespace that survives a comment strip.
write_keep "$P1" '"'
run_retire --repo "$P1" --from-dir "$T1" --apply
assert_exit 1 "a pattern matching no syncable root is rejected"
fi
end_case

# ========================================================== 2. syncable roots
if begin_case "2. syncable roots"; then
#
# The root list is parsed from the § Syncable Paths doc block rather than
# copied into this script, so the block stays the single source
# tests/test-syncable-paths.sh already pins. The block is read from the
# *template*, never the project: the template is the authority on what the
# roots contain, and reading the project's stale copy is the non-determinism
# this feature exists to remove.

printf '\n-- 2. syncable roots come from the doc block --\n'

P2="$FIXTURE_ROOT/p2"; T2="$FIXTURE_ROOT/t2"; T2X="$FIXTURE_ROOT/t2x"
make_project "$P2"
_f "$P2/.claude/browsers/local.md" "project-only browser runbook"
commit_all "$P2"
write_keep "$P2"   # empty: recorded "nothing here is project-specific"

# Template A does not declare .claude/browsers/ as a root.
make_template "$T2"
# Template B declares it, and carries a file under it.
make_template "$T2X" ".claude/browsers/     → Browser runbooks"
_f "$T2X/.claude/browsers/chrome.md" "chrome runbook"

run_retire --repo "$P2" --from-dir "$T2"
assert_exit 0 "undeclared root: run succeeds"
assert_not_contains "$output" ".claude/browsers/local.md" \
  "a path under a root the doc block does not declare is never scanned"

run_retire --repo "$P2" --from-dir "$T2X"
assert_exit 0 "declared root: run succeeds"
assert_contains "$output" "retire: .claude/browsers/local.md" \
  "adding a root to the doc block puts its project-only paths in scope"

# Root counts track the block, so the header cannot silently disagree with it.
run_retire --repo "$P2" --from-dir "$T2"
assert_contains "$output" "roots: 4" "header reports the 4 directory roots in the block"
run_retire --repo "$P2" --from-dir "$T2X"
assert_contains "$output" "roots: 5" "header reports 5 once a root is added"

# File roots are excluded. Retirement is undefined for a file — it has no
# project-only paths inside it — and CLAUDE.md is already handled by the
# checkout step. A template missing CLAUDE.md must not retire the project's.
P2F="$FIXTURE_ROOT/p2f"; T2F="$FIXTURE_ROOT/t2f"
make_project "$P2F"; write_keep "$P2F"
make_template "$T2F"; rm -f "$T2F/CLAUDE.md" "$T2F/.claude/settings.json"
run_retire --repo "$P2F" --from-dir "$T2F" --apply
assert_exit 0 "file roots absent from the template are not an error"
assert_not_contains "$output" "retire: CLAUDE.md" "CLAUDE.md is excluded from retirement"
assert_file_exists "$P2F/CLAUDE.md" \
  "--apply leaves the CLAUDE.md file root on disk"
assert_file_exists "$P2F/.claude/settings.json" \
  "--apply leaves the .claude/settings.json file root on disk"

# A root absent from the PROJECT is empty, not an error: a project that never
# received .claude/skills/ has nothing to retire there.
P2E="$FIXTURE_ROOT/p2e"; T2E="$FIXTURE_ROOT/t2e"
make_project "$P2E"; write_keep "$P2E"
git -C "$P2E" rm -rq .claude/skills; commit_all "$P2E"
make_template "$T2E"
run_retire --repo "$P2E" --from-dir "$T2E"
assert_exit 0 "a syncable root absent from the project is treated as empty"

# A root absent from the TEMPLATE is not scanned. Retiring from it would compute
# "everything the project has" minus "nothing" and delete the project's whole
# copy — the one mistake this script must never make quietly.
#
# Scoped to the root rather than aborting the run: two roots in the real template
# hold a single file each, so one upstream commit removing that file used to exit
# 1 for every downstream project and retire nothing at all. An ordinary upstream
# deletion must not disable retirement everywhere.
P2M="$FIXTURE_ROOT/p2m"; T2M="$FIXTURE_ROOT/t2m"
make_project "$P2M"; write_keep "$P2M"
_f "$P2M/.agents/skills/gone/SKILL.md" "retired upstream, under a root that IS vouched for"
commit_all "$P2M"
make_template "$T2M"; rm -rf "$T2M/.claude/hooks"
run_retire --repo "$P2M" --from-dir "$T2M" --apply
assert_exit 0 "one empty template root does not abort the run"
assert_contains "$output" "skipped: .claude/hooks/" "the unvouched root is named"
assert_file_exists "$P2M/.claude/hooks/session-start.sh" \
  "and nothing under it is deleted"
# The point of scoping: unrelated roots still work.
assert_file_absent "$P2M/.agents/skills/gone/SKILL.md" \
  "while a root the template does vouch for still retires normally"

# SEVERAL empty roots is a different claim: a truncated checkout, not an upstream
# edit. It stays a hard stop, and that threshold is what preserves the
# catastrophe guard -- the doc block lives under .agents/skills/, so that root is
# non-empty in any readable template and an all-empty test could never fire.
# Without the threshold, a clone carrying only the sync skill would skip every
# other root and retire the project's entire copy of each.
P2Z="$FIXTURE_ROOT/p2z"; T2Z="$FIXTURE_ROOT/t2z"
make_project "$P2Z"; write_keep "$P2Z"
_f "$P2Z/.agents/skills/victim/SKILL.md" "would be retired if a partial source were trusted"
commit_all "$P2Z"
make_template "$T2Z"
# A truncated checkout: only the sync skill survived.
rm -rf "$T2Z/.agents/agents" "$T2Z/.claude/skills" "$T2Z/.claude/hooks"
rm -rf "$T2Z/.agents/skills/build"
run_retire --repo "$P2Z" --from-dir "$T2Z" --apply
assert_exit 1 "a source missing several roots exits non-zero"
assert_contains "$output" "refusing a source this incomplete" \
  "and says the source is too incomplete to retire against"
assert_file_exists "$P2Z/.agents/skills/victim/SKILL.md" \
  "deleting nothing -- including under the root the doc block itself lives in"
fi
end_case

# ======================================================== 3. template sources
if begin_case "3. template sources"; then
#
# Two ways to name the same template: a git ref (the git-remote mode) and a
# checkout on disk (the manual-diff mode). They must agree, or "deterministic"
# holds only for whichever mode the operator happened to pick — and the two
# modes are chosen by connection method, not by intent.

printf '\n-- 3. --from-ref and --from-dir agree --\n'

P3="$FIXTURE_ROOT/p3"; T3="$FIXTURE_ROOT/t3"
make_project "$P3"
_f "$P3/.agents/skills/local-only/SKILL.md" "project specific"
_f "$P3/.claude/hooks/local-hook.sh"        "project specific"
_f "$P3/.agents/agents/local-agent.md"      "project specific"
commit_all "$P3"

# The same template content, reachable both ways: built once on disk, then
# committed to an orphan ref in the project repo (which is how /sync sees it —
# workflow/$BRANCH is a remote-tracking ref inside the project's own clone).
make_template "$T3"
git -C "$P3" checkout -q --orphan template
git -C "$P3" rm -rq --cached . >/dev/null 2>&1
find "$P3" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$T3/." "$P3/"
git -C "$P3" add -A
git -C "$P3" commit -qm template
git -C "$P3" checkout -q main

# Written after the branch dance: sync-keep is untracked by design (it is the
# project's own record, never synced), so a checkout would not restore it.
write_keep "$P3" ".agents/agents/local-agent.md"

retire_lines() { printf '%s\n' "$output" | grep '^  retire:' | sort; }

run_retire --repo "$P3" --from-ref template
assert_exit 0 "--from-ref succeeds"
FROM_REF="$(retire_lines)"

run_retire --repo "$P3" --from-dir "$T3"
assert_exit 0 "--from-dir succeeds"
FROM_DIR="$(retire_lines)"

assert_contains "$FROM_REF" ".agents/skills/local-only/SKILL.md" \
  "--from-ref found the project-only paths (guards against a vacuous '' = '' pass)"
assert_eq "$FROM_REF" "$FROM_DIR" \
  "--from-ref and --from-dir yield the identical retirement set"

# The allowlist is read once, from the project, so it applies to both modes.
run_retire --repo "$P3" --from-ref template
assert_contains "$output" "kept:   .agents/agents/local-agent.md" \
  "--from-ref honours the project's sync-keep"

# Usage errors are exit 2, distinct from the exit 1 of a real failure: one means
# the operator typed the command wrong, the other means the run found a problem.
run_retire --repo "$P3"
assert_exit 2 "neither --from-ref nor --from-dir is a usage error"
run_retire --repo "$P3" --from-ref template --from-dir "$T3"
assert_exit 2 "supplying both sources is a usage error"
run_retire --repo "$FIXTURE_ROOT/does-not-exist" --from-dir "$T3"
assert_exit 2 "a --repo that is not a directory is a usage error"
# --from-ref reaches `git ls-tree <ref>` and `git show <ref>:<path>`, so a value
# that looks like an option is argument injection, not a bad ref.
run_retire --repo "$P3" --from-ref "--upload-pack=touch $FIXTURE_ROOT/OWNED"
assert_exit 2 "a --from-ref beginning with - is a usage error"
assert_file_absent "$FIXTURE_ROOT/OWNED" \
  "and it never reached git"
# An option supplied but empty means the caller's variable was unset. Treating it
# as absent is what let an empty --from-dir read roots from the project tree.
run_retire --repo "$P3" --from-ref template --from-dir ""
assert_exit 2 "an empty --from-dir is a usage error, not an absent one"
run_retire --repo "$P3" --from-dir "   "
assert_exit 2 "a whitespace-only source is likewise refused"

# An unreadable ref is a failure, not a usage error, and retires nothing.
run_retire --repo "$P3" --from-ref no-such-ref --apply
assert_exit 1 "an unreadable ref exits 1"
assert_file_exists "$P3/.agents/skills/local-only/SKILL.md" \
  "an unreadable ref deletes nothing"
fi
end_case

# ====================================================== 4. the retirement set
if begin_case "4. the retirement set"; then
#
# retire = project - template - allowlist, and nothing else. The two most
# expensive ways to get this wrong are retiring a path the template still
# ships (data loss on every sync) and truncating the report (the operator
# approves a list that is not the list).

printf '\n-- 4. set arithmetic and the full report --\n'

P4="$FIXTURE_ROOT/p4"; T4="$FIXTURE_ROOT/t4"
make_project "$P4"; make_template "$T4"

# A path present in BOTH, with different content. Modification is the checkout
# step's job; retirement must not touch it.
_f "$P4/.agents/skills/build/SKILL.md" "project's older build skill"

# Enough project-only paths to exceed any plausible progressive-disclosure cap.
# The list IS the record of what is about to be destroyed, so it is never
# abbreviated — a cap here would hide exactly what the report exists to show.
i=1
while [ "$i" -le 25 ]; do
  _f "$P4/.agents/skills/retired-$i/SKILL.md" "retired upstream"
  i=$((i + 1))
done
commit_all "$P4"
write_keep "$P4"

run_retire --repo "$P4" --from-dir "$T4"
assert_exit 0 "default run succeeds"

RETIRE_COUNT="$(printf '%s\n' "$output" | grep -c '^  retire:')"
assert_eq "25" "$RETIRE_COUNT" "every project-only path is listed — no truncation"
assert_contains "$output" "retire: .agents/skills/retired-1/SKILL.md" "first path listed"
assert_contains "$output" "retire: .agents/skills/retired-25/SKILL.md" "last path listed"
assert_not_contains "$output" "retire: .agents/skills/build/SKILL.md" \
  "a path the template still ships is never retired, even when it differs"
assert_not_contains "$output" "..." "the report carries no truncation marker"

# The default run is a dry run. Reporting and destroying are separate acts, and
# the operator sees the list before either.
assert_contains "$output" "mode:   dry-run (no changes written)" "default run reports itself as a dry run"
SURVIVORS="$(find "$P4/.agents/skills" -name 'SKILL.md' | wc -l | tr -d ' ')"
assert_eq "27" "$SURVIVORS" "the default run deleted nothing (25 retired + build + sync)"

# The header names the source, so a report pasted into a review says which
# template revision produced it.
assert_contains "$output" "sync retirement — source: $T4" "the header names the template source"
fi
end_case

finish
