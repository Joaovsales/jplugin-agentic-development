#!/bin/bash
# tests/test-sync-retirement.sh — behavioural contract for deterministic
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
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

RETIRE="$REPO/.agents/skills/sync/scripts/sync-retire.py"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

# ---------------------------------------------------------------- fixtures

# The doc block the script parses for its root list. Kept in the same shape as
# the real § Syncable Paths fence (`path   → description`) so a fixture cannot
# pass against a parser that the real block would defeat. $1, when given, is an
# extra root line appended inside the fence.
write_skill_md() {
  _dir="$1" _extra="${2:-}"
  mkdir -p "$_dir/.agents/skills/sync"
  {
    printf '## Syncable Paths\n\n```\n'
    printf 'CLAUDE.md             → Shared rules\n'
    printf '.agents/skills/       → Canonical skills\n'
    printf '.agents/agents/       → Canonical personas\n'
    printf '.claude/skills/       → Compat copy\n'
    printf '.claude/hooks/        → Lifecycle hooks\n'
    printf '.claude/settings.json → Hook configuration\n'
    [ -n "$_extra" ] && printf '%s\n' "$_extra"
    printf '```\n\n## Next Section\n'
  } > "$_dir/.agents/skills/sync/SKILL.md"
}

# A template checkout: the doc block plus one file under every directory root,
# so no root is "absent from the template" unless a test says so.
make_template() {
  _dir="$1" _extra="${2:-}"
  mkdir -p "$_dir"
  write_skill_md "$_dir" "$_extra"
  _f "$_dir/.agents/skills/build/SKILL.md"   "build skill"
  _f "$_dir/.agents/agents/planner.md"       "planner"
  _f "$_dir/.claude/skills/build/SKILL.md"   "build skill"
  _f "$_dir/.claude/hooks/session-start.sh"  "hook"
  _f "$_dir/CLAUDE.md"                       "rules"
  _f "$_dir/.claude/settings.json"           "{}"
}

_f() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# A project: a git repo, because the project inventory is the set of *tracked*
# files. Untracked build residue was never synced in, so it is never retired.
make_project() {
  _dir="$1"
  mkdir -p "$_dir"
  git init -q --initial-branch=main "$_dir"
  git -C "$_dir" config user.name fixture
  git -C "$_dir" config user.email fixture@example.test
  write_skill_md "$_dir"
  _f "$_dir/.agents/skills/build/SKILL.md"   "build skill"
  _f "$_dir/.agents/agents/planner.md"       "planner"
  _f "$_dir/.claude/skills/build/SKILL.md"   "build skill"
  _f "$_dir/.claude/hooks/session-start.sh"  "hook"
  _f "$_dir/CLAUDE.md"                       "rules"
  _f "$_dir/.claude/settings.json"           "{}"
  commit_all "$_dir"
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "state" 2>/dev/null || true
}

# Run the script; capture stdout+stderr and status into RUN_OUTPUT/RUN_STATUS.
run_retire() {
  python3 "$RETIRE" "$@" >"$FIXTURE_ROOT/out" 2>"$FIXTURE_ROOT/err"
  RUN_STATUS=$?
  RUN_OUTPUT="$(cat "$FIXTURE_ROOT/out"; cat "$FIXTURE_ROOT/err")"
}

# Write a .claude/sync-keep from the remaining arguments, one pattern per line.
write_keep() {
  _dir="$1"; shift
  mkdir -p "$_dir/.claude"
  : > "$_dir/.claude/sync-keep"
  for _line in "$@"; do printf '%s\n' "$_line" >> "$_dir/.claude/sync-keep"; done
}

# ============================================================== 1. patterns
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
assert_eq "0" "$RUN_STATUS" "comments and blank lines in sync-keep are ignored"
assert_contains "$RUN_OUTPUT" "kept:" "the surviving path is reported as kept"

# Each invalid pattern: non-zero, names the offending pattern AND its line, and
# deletes nothing. The line number matters — an allowlist is edited by hand and
# "some pattern is bad" is not an actionable message.
assert_invalid_pattern() {
  _pattern="$1" _label="$2"
  write_keep "$P1" "# leading comment" "$_pattern"
  run_retire --repo "$P1" --from-dir "$T1" --apply
  assert_eq "1" "$RUN_STATUS" "invalid pattern ($_label): exits non-zero"
  assert_contains "$RUN_OUTPUT" "$_pattern" "invalid pattern ($_label): names the pattern"
  assert_contains "$RUN_OUTPUT" "line 2" "invalid pattern ($_label): names the line"
  assert_eq "present" \
    "$([ -f "$P1/.agents/skills/local-only/SKILL.md" ] && echo present || echo gone)" \
    "invalid pattern ($_label): --apply deleted nothing"
}

assert_invalid_pattern "/etc/passwd"                      "absolute"
assert_invalid_pattern ".agents/skills/../../etc"         "parent traversal"
assert_invalid_pattern '.agents\skills\x'                 "backslash separators"
assert_invalid_pattern '.agents/skills/[ab]/SKILL.md'     "unsupported [] glob"
assert_invalid_pattern '.agents/skills/{a,b}/SKILL.md'    "unsupported {} brace expansion"
assert_invalid_pattern '.agents/skills/!a/SKILL.md'       "unsupported ! negation"
assert_invalid_pattern 'C:/agents/skills/x.md'            "windows drive letter is absolute"
assert_invalid_pattern 'tasks/**'                         "outside every syncable root"

# An empty pattern cannot be written as a bare line (it would be a blank line,
# which is ignored), so it arrives as whitespace that survives a comment strip.
write_keep "$P1" '"'
run_retire --repo "$P1" --from-dir "$T1" --apply
assert_eq "1" "$RUN_STATUS" "a pattern matching no syncable root is rejected"

# ========================================================== 2. syncable roots
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
assert_eq "0" "$RUN_STATUS" "undeclared root: run succeeds"
assert_not_contains "$RUN_OUTPUT" ".claude/browsers/local.md" \
  "a path under a root the doc block does not declare is never scanned"

run_retire --repo "$P2" --from-dir "$T2X"
assert_eq "0" "$RUN_STATUS" "declared root: run succeeds"
assert_contains "$RUN_OUTPUT" "retire: .claude/browsers/local.md" \
  "adding a root to the doc block puts its project-only paths in scope"

# Root counts track the block, so the header cannot silently disagree with it.
run_retire --repo "$P2" --from-dir "$T2"
assert_contains "$RUN_OUTPUT" "roots: 4" "header reports the 4 directory roots in the block"
run_retire --repo "$P2" --from-dir "$T2X"
assert_contains "$RUN_OUTPUT" "roots: 5" "header reports 5 once a root is added"

# File roots are excluded. Retirement is undefined for a file — it has no
# project-only paths inside it — and CLAUDE.md is already handled by the
# checkout step. A template missing CLAUDE.md must not retire the project's.
P2F="$FIXTURE_ROOT/p2f"; T2F="$FIXTURE_ROOT/t2f"
make_project "$P2F"; write_keep "$P2F"
make_template "$T2F"; rm -f "$T2F/CLAUDE.md" "$T2F/.claude/settings.json"
run_retire --repo "$P2F" --from-dir "$T2F" --apply
assert_eq "0" "$RUN_STATUS" "file roots absent from the template are not an error"
assert_not_contains "$RUN_OUTPUT" "retire: CLAUDE.md" "CLAUDE.md is excluded from retirement"
assert_eq "present" "$([ -f "$P2F/CLAUDE.md" ] && echo present || echo gone)" \
  "--apply leaves the CLAUDE.md file root on disk"
assert_eq "present" "$([ -f "$P2F/.claude/settings.json" ] && echo present || echo gone)" \
  "--apply leaves the .claude/settings.json file root on disk"

# A root absent from the PROJECT is empty, not an error: a project that never
# received .claude/skills/ has nothing to retire there.
P2E="$FIXTURE_ROOT/p2e"; T2E="$FIXTURE_ROOT/t2e"
make_project "$P2E"; write_keep "$P2E"
git -C "$P2E" rm -rq .claude/skills; commit_all "$P2E"
make_template "$T2E"
run_retire --repo "$P2E" --from-dir "$T2E"
assert_eq "0" "$RUN_STATUS" "a syncable root absent from the project is treated as empty"

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
assert_eq "0" "$RUN_STATUS" "one empty template root does not abort the run"
assert_contains "$RUN_OUTPUT" "skipped: .claude/hooks/" "the unvouched root is named"
assert_eq "present" "$([ -f "$P2M/.claude/hooks/session-start.sh" ] && echo present || echo gone)" \
  "and nothing under it is deleted"
# The point of scoping: unrelated roots still work.
assert_eq "gone" "$([ -e "$P2M/.agents/skills/gone/SKILL.md" ] && echo present || echo gone)" \
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
assert_eq "1" "$RUN_STATUS" "a source missing several roots exits non-zero"
assert_contains "$RUN_OUTPUT" "refusing a source this incomplete" \
  "and says the source is too incomplete to retire against"
assert_eq "present" "$([ -f "$P2Z/.agents/skills/victim/SKILL.md" ] && echo present || echo gone)" \
  "deleting nothing -- including under the root the doc block itself lives in"

# ======================================================== 3. template sources
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

retire_lines() { printf '%s\n' "$RUN_OUTPUT" | grep '^  retire:' | sort; }

run_retire --repo "$P3" --from-ref template
assert_eq "0" "$RUN_STATUS" "--from-ref succeeds"
FROM_REF="$(retire_lines)"

run_retire --repo "$P3" --from-dir "$T3"
assert_eq "0" "$RUN_STATUS" "--from-dir succeeds"
FROM_DIR="$(retire_lines)"

assert_contains "$FROM_REF" ".agents/skills/local-only/SKILL.md" \
  "--from-ref found the project-only paths (guards against a vacuous '' = '' pass)"
assert_eq "$FROM_REF" "$FROM_DIR" \
  "--from-ref and --from-dir yield the identical retirement set"

# The allowlist is read once, from the project, so it applies to both modes.
run_retire --repo "$P3" --from-ref template
assert_contains "$RUN_OUTPUT" "kept:   .agents/agents/local-agent.md" \
  "--from-ref honours the project's sync-keep"

# Usage errors are exit 2, distinct from the exit 1 of a real failure: one means
# the operator typed the command wrong, the other means the run found a problem.
run_retire --repo "$P3"
assert_eq "2" "$RUN_STATUS" "neither --from-ref nor --from-dir is a usage error"
run_retire --repo "$P3" --from-ref template --from-dir "$T3"
assert_eq "2" "$RUN_STATUS" "supplying both sources is a usage error"
run_retire --repo "$FIXTURE_ROOT/does-not-exist" --from-dir "$T3"
assert_eq "2" "$RUN_STATUS" "a --repo that is not a directory is a usage error"
# --from-ref reaches `git ls-tree <ref>` and `git show <ref>:<path>`, so a value
# that looks like an option is argument injection, not a bad ref.
run_retire --repo "$P3" --from-ref "--upload-pack=touch $FIXTURE_ROOT/OWNED"
assert_eq "2" "$RUN_STATUS" "a --from-ref beginning with - is a usage error"
assert_eq "absent" "$([ -e "$FIXTURE_ROOT/OWNED" ] && echo present || echo absent)" \
  "and it never reached git"
# An option supplied but empty means the caller's variable was unset. Treating it
# as absent is what let an empty --from-dir read roots from the project tree.
run_retire --repo "$P3" --from-ref template --from-dir ""
assert_eq "2" "$RUN_STATUS" "an empty --from-dir is a usage error, not an absent one"
run_retire --repo "$P3" --from-dir "   "
assert_eq "2" "$RUN_STATUS" "a whitespace-only source is likewise refused"

# An unreadable ref is a failure, not a usage error, and retires nothing.
run_retire --repo "$P3" --from-ref no-such-ref --apply
assert_eq "1" "$RUN_STATUS" "an unreadable ref exits 1"
assert_eq "present" "$([ -f "$P3/.agents/skills/local-only/SKILL.md" ] && echo present || echo gone)" \
  "an unreadable ref deletes nothing"

# ====================================================== 4. the retirement set
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
assert_eq "0" "$RUN_STATUS" "default run succeeds"

RETIRE_COUNT="$(printf '%s\n' "$RUN_OUTPUT" | grep -c '^  retire:')"
assert_eq "25" "$RETIRE_COUNT" "every project-only path is listed — no truncation"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/retired-1/SKILL.md" "first path listed"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/retired-25/SKILL.md" "last path listed"
assert_not_contains "$RUN_OUTPUT" "retire: .agents/skills/build/SKILL.md" \
  "a path the template still ships is never retired, even when it differs"
assert_not_contains "$RUN_OUTPUT" "..." "the report carries no truncation marker"

# The default run is a dry run. Reporting and destroying are separate acts, and
# the operator sees the list before either.
assert_contains "$RUN_OUTPUT" "mode:   dry-run (no changes written)" "default run reports itself as a dry run"
SURVIVORS="$(find "$P4/.agents/skills" -name 'SKILL.md' | wc -l | tr -d ' ')"
assert_eq "27" "$SURVIVORS" "the default run deleted nothing (25 retired + build + sync)"

# The header names the source, so a report pasted into a review says which
# template revision produced it.
assert_contains "$RUN_OUTPUT" "sync retirement — source: $T4" "the header names the template source"

# ================================================================= 5. --apply
#
# The only step that destroys anything. It must delete the retirement set
# exactly — no more (a deleted project file is unrecoverable from the template)
# and no less (a survivor is the stale copy this feature exists to remove).

printf '\n-- 5. --apply deletes exactly the retirement set --\n'

P5="$FIXTURE_ROOT/p5"; T5="$FIXTURE_ROOT/t5"
make_project "$P5"; make_template "$T5"
_f "$P5/.agents/skills/retired/SKILL.md"           "retired upstream"
_f "$P5/.agents/skills/retired/scripts/helper.sh"  "retired upstream"
_f "$P5/.claude/hooks/retired-hook.sh"             "retired upstream"
_f "$P5/.agents/skills/keepme/SKILL.md"            "project specific"
commit_all "$P5"
write_keep "$P5" ".agents/skills/keepme/**"

run_retire --repo "$P5" --from-dir "$T5" --apply
assert_eq "0" "$RUN_STATUS" "--apply succeeds"

# The same full list is printed before deleting, so the record of what was
# destroyed survives in the transcript.
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/retired/SKILL.md" "--apply prints the list it deletes"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/retired/scripts/helper.sh" "--apply lists nested paths"
assert_contains "$RUN_OUTPUT" "retire: .claude/hooks/retired-hook.sh" "--apply lists every root's paths"
assert_contains "$RUN_OUTPUT" "mode:   applied" "--apply reports itself as applied, not dry-run"

assert_eq "gone" "$([ -e "$P5/.agents/skills/retired/SKILL.md" ] && echo present || echo gone)" \
  "--apply deleted the retired skill file"
assert_eq "gone" "$([ -e "$P5/.claude/hooks/retired-hook.sh" ] && echo present || echo gone)" \
  "--apply deleted the retired hook"

# Directories emptied by the deletions are pruned, so a sync does not leave a
# tree full of empty husks that later reads as "the skill is still installed".
assert_eq "gone" "$([ -d "$P5/.agents/skills/retired" ] && echo present || echo gone)" \
  "--apply pruned the directory its deletions emptied"
assert_eq "gone" "$([ -d "$P5/.agents/skills/retired/scripts" ] && echo present || echo gone)" \
  "--apply pruned nested emptied directories"

# The syncable root itself survives even when everything under it went, because
# an absent root and an empty one are different states to every other reader.
assert_eq "present" "$([ -d "$P5/.agents/skills" ] && echo present || echo gone)" \
  "--apply keeps the syncable root directory itself"

# Nothing outside the retirement set is touched.
assert_eq "present" "$([ -f "$P5/.agents/skills/keepme/SKILL.md" ] && echo present || echo gone)" \
  "--apply left the allowlisted path alone"
assert_eq "present" "$([ -f "$P5/.agents/skills/build/SKILL.md" ] && echo present || echo gone)" \
  "--apply left a path the template still ships alone"
assert_eq "present" "$([ -f "$P5/CLAUDE.md" ] && echo present || echo gone)" \
  "--apply left the file roots alone"
assert_eq "present" "$([ -f "$P5/.claude/sync-keep" ] && echo present || echo gone)" \
  "--apply left the allowlist itself alone"

# Untracked files under a root were never synced in, so they are not this
# program's to delete — the project inventory is the tracked set.
_f "$P5/.claude/hooks/scratch.sh" "untracked local scratch"
run_retire --repo "$P5" --from-dir "$T5" --apply
assert_eq "present" "$([ -f "$P5/.claude/hooks/scratch.sh" ] && echo present || echo gone)" \
  "--apply never deletes an untracked file"
assert_not_contains "$RUN_OUTPUT" "scratch.sh" "an untracked file is not even reported"

# A second --apply before the deletions are staged must not re-list them. The
# project inventory reads the git *index*, which still names a file this script
# deleted a moment ago; an unfiltered read would compute it as project-only
# again and fail on the missing file, turning a no-op re-run into a crash.
run_retire --repo "$P5" --from-dir "$T5" --apply
assert_eq "0" "$RUN_STATUS" "a second --apply with the deletions unstaged succeeds"
assert_not_contains "$RUN_OUTPUT" "retire: .agents/skills/retired/SKILL.md" \
  "an already-deleted path is not re-listed from the index"
assert_not_contains "$RUN_OUTPUT" "deletion failed" "the re-run does not fail on a missing file"

# =============================================================== 6. allowlist
#
# A surviving path must be traceable to the line that saved it. "Kept" without
# the pattern tells an operator that something was protected but not by what,
# so a sync-keep entry that silently stopped matching looks identical to one
# still doing its job.

printf '\n-- 6. sync-keep matching and reporting --\n'

P6="$FIXTURE_ROOT/p6"; T6="$FIXTURE_ROOT/t6"
make_project "$P6"; make_template "$T6"
_f "$P6/.agents/skills/mine/SKILL.md"            "project specific"
_f "$P6/.agents/skills/mine/scripts/deep.sh"     "project specific, nested"
_f "$P6/.claude/hooks/one.sh"                    "project specific"
_f "$P6/.claude/hooks/two.sh"                    "project specific"
_f "$P6/.agents/agents/unprotected.md"           "retired upstream"
commit_all "$P6"

# `**` crosses `/`; `*` does not. Borrowing fnmatch semantics, whose `*` spans
# separators, would silently widen every entry written here.
write_keep "$P6" ".agents/skills/mine/**" ".claude/hooks/*.sh"
run_retire --repo "$P6" --from-dir "$T6"
assert_eq "0" "$RUN_STATUS" "allowlisted run succeeds"
assert_contains "$RUN_OUTPUT" "kept:   .agents/skills/mine/SKILL.md (matched .agents/skills/mine/**)" \
  "a kept path names the pattern that matched it"
assert_contains "$RUN_OUTPUT" "kept:   .agents/skills/mine/scripts/deep.sh (matched .agents/skills/mine/**)" \
  "** matches across directory separators"
assert_contains "$RUN_OUTPUT" "kept:   .claude/hooks/one.sh (matched .claude/hooks/*.sh)" \
  "* matches within a single path segment"
assert_contains "$RUN_OUTPUT" "retire: .agents/agents/unprotected.md" \
  "a path no pattern matches is still retired"

# `*` must not cross a separator: a pattern written for one directory level
# must not silently protect everything beneath it.
write_keep "$P6" ".agents/skills/*"
run_retire --repo "$P6" --from-dir "$T6"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/mine/SKILL.md" \
  "* does not cross a directory separator"

# `?` is exactly one character, also non-crossing.
write_keep "$P6" ".claude/hooks/???.sh"
run_retire --repo "$P6" --from-dir "$T6"
assert_contains "$RUN_OUTPUT" "kept:   .claude/hooks/one.sh (matched .claude/hooks/???.sh)" \
  "? matches exactly one character"
assert_contains "$RUN_OUTPUT" "kept:   .claude/hooks/two.sh (matched .claude/hooks/???.sh)" \
  "? applies to every path of the right shape"
# Non-crossing, the same property `*` is pinned for above: widening `?` to `.`
# would silently widen every allowlist entry containing one.
write_keep "$P6" ".agents/skills/mine?SKILL.md"
run_retire --repo "$P6" --from-dir "$T6"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/mine/SKILL.md" \
  "? does not cross a directory separator either"

# An EMPTY sync-keep is a recorded, deliberate "nothing here is
# project-specific". It permits deletion; only an ABSENT file withholds it.
# Collapsing the two would make an unconfigured project look like one that had
# opted in — the difference between silence and consent.
P6E="$FIXTURE_ROOT/p6e"; T6E="$FIXTURE_ROOT/t6e"
make_project "$P6E"; make_template "$T6E"
_f "$P6E/.agents/skills/retired/SKILL.md" "retired upstream"
commit_all "$P6E"
write_keep "$P6E"
run_retire --repo "$P6E" --from-dir "$T6E" --apply
assert_eq "0" "$RUN_STATUS" "an empty sync-keep is a valid recorded intent"
assert_not_contains "$RUN_OUTPUT" "bootstrap" "an empty sync-keep is not bootstrap"
assert_eq "gone" "$([ -e "$P6E/.agents/skills/retired/SKILL.md" ] && echo present || echo gone)" \
  "an empty sync-keep permits deletion"

# =============================================================== 7. bootstrap
#
# Until a project records its intent, nothing is deleted. A project with no
# sync-keep has never been asked which of its paths are project-specific, and
# guessing on its behalf is precisely the run-time classification this feature
# removes. So bootstrap retires nothing and hands a human a candidate list.
#
# The candidate is written to a .candidate file, never to sync-keep itself:
# promoting it is the human's confirming act, and a script that wrote the real
# file would be recording an intent nobody expressed.

printf '\n-- 7. bootstrap when no sync-keep exists --\n'

P7="$FIXTURE_ROOT/p7"; T7="$FIXTURE_ROOT/t7"
make_project "$P7"; make_template "$T7"
_f "$P7/.agents/skills/mine/SKILL.md"   "project specific"
_f "$P7/.claude/hooks/retired-hook.sh"  "retired upstream"
commit_all "$P7"
# Deliberately NO write_keep: this is the unconfigured state.

run_retire --repo "$P7" --from-dir "$T7"
assert_eq "0" "$RUN_STATUS" "bootstrap is a normal outcome, not a failure"
assert_contains "$RUN_OUTPUT" "bootstrap: required" "bootstrap is announced"
assert_contains "$RUN_OUTPUT" ".claude/sync-keep" "the report names the file to create"
assert_contains "$RUN_OUTPUT" "candidate: .agents/skills/mine/SKILL.md" "every project-only path is a candidate"
assert_contains "$RUN_OUTPUT" "candidate: .claude/hooks/retired-hook.sh" "candidates span every root"
assert_not_contains "$RUN_OUTPUT" "retire:" "bootstrap proposes no retirements"

run_retire --repo "$P7" --from-dir "$T7" --apply
assert_eq "0" "$RUN_STATUS" "bootstrap under --apply still succeeds"
assert_eq "present" "$([ -f "$P7/.agents/skills/mine/SKILL.md" ] && echo present || echo gone)" \
  "bootstrap --apply deletes nothing"
assert_eq "present" "$([ -f "$P7/.claude/hooks/retired-hook.sh" ] && echo present || echo gone)" \
  "bootstrap --apply deletes nothing, not even an upstream-retired path"

# The candidate file is written; the real allowlist is not.
assert_eq "present" "$([ -f "$P7/.claude/sync-keep.candidate" ] && echo present || echo gone)" \
  "bootstrap --apply writes the candidate allowlist"
assert_eq "gone" "$([ -f "$P7/.claude/sync-keep" ] && echo present || echo gone)" \
  "bootstrap --apply never writes .claude/sync-keep itself"
assert_file_contains "$P7/.claude/sync-keep.candidate" ".agents/skills/mine/SKILL.md" \
  "the candidate lists the project-only paths"

# The candidate is a working allowlist once promoted: reviewed, renamed, and
# the next run keeps exactly what it names.
cp "$P7/.claude/sync-keep.candidate" "$P7/.claude/sync-keep"
run_retire --repo "$P7" --from-dir "$T7"
assert_not_contains "$RUN_OUTPUT" "bootstrap" "promoting the candidate leaves bootstrap"
assert_contains "$RUN_OUTPUT" "retire: (none)" \
  "a promoted candidate keeps every path it named"

# A dry run must not write the candidate either — a dry run writes nothing.
P7D="$FIXTURE_ROOT/p7d"; T7D="$FIXTURE_ROOT/t7d"
make_project "$P7D"; make_template "$T7D"
_f "$P7D/.agents/skills/mine/SKILL.md" "project specific"; commit_all "$P7D"
run_retire --repo "$P7D" --from-dir "$T7D"
assert_eq "gone" "$([ -f "$P7D/.claude/sync-keep.candidate" ] && echo present || echo gone)" \
  "a dry run writes no candidate file"

# ============================================================= 8. idempotency
#
# The headline claim: running /sync twice against an unchanged template leaves
# a byte-identical tree, and the second run reports nothing to do. This is the
# property that was false before — two runs against one template commit could
# produce different trees because a model re-derived the answer each time.

printf '\n-- 8. two runs converge --\n'

# Hash every file under the syncable roots, path and content, so a difference
# in either shows up. .git is excluded: index and log churn are not tree state.
tree_hash() {
  find "$1" -name .git -prune -o -type f -print \
    | sed "s|^$1/||" | LC_ALL=C sort \
    | while IFS= read -r f; do printf '%s %s\n' "$f" "$(sha256sum "$1/$f" | cut -d' ' -f1)"; done \
    | sha256sum | cut -d' ' -f1
}

P8="$FIXTURE_ROOT/p8"; T8="$FIXTURE_ROOT/t8"
make_project "$P8"; make_template "$T8"
_f "$P8/.agents/skills/retired-a/SKILL.md" "retired upstream"
_f "$P8/.agents/skills/retired-b/SKILL.md" "retired upstream"
_f "$P8/.claude/hooks/old.sh"              "retired upstream"
_f "$P8/.agents/agents/mine.md"            "project specific"
commit_all "$P8"
write_keep "$P8" ".agents/agents/mine.md"

run_retire --repo "$P8" --from-dir "$T8" --apply
assert_eq "0" "$RUN_STATUS" "first --apply succeeds"
FIRST_COUNT="$(printf '%s\n' "$RUN_OUTPUT" | grep -c '^  retire:')"
assert_eq "3" "$FIRST_COUNT" "first run retires the three upstream-retired paths"
HASH_AFTER_FIRST="$(tree_hash "$P8")"

run_retire --repo "$P8" --from-dir "$T8" --apply
assert_eq "0" "$RUN_STATUS" "second --apply succeeds"
assert_contains "$RUN_OUTPUT" "retire: (none)" "the second run reports zero retirements"
assert_eq "$HASH_AFTER_FIRST" "$(tree_hash "$P8")" \
  "the second run leaves a byte-identical tree"

# And once the deletions are committed, which is what a real /sync ends with.
commit_all "$P8"
HASH_COMMITTED="$(tree_hash "$P8")"
run_retire --repo "$P8" --from-dir "$T8" --apply
assert_contains "$RUN_OUTPUT" "retire: (none)" "a third run after committing still reports zero"
assert_eq "$HASH_COMMITTED" "$(tree_hash "$P8")" "a third run leaves the tree untouched"

# Non-vacuity: the hash must actually respond to a change, or every comparison
# above is comparing two constants.
_f "$P8/.agents/skills/retired-a/SKILL.md" "resurrected"
assert_eq "changed" \
  "$([ "$HASH_COMMITTED" = "$(tree_hash "$P8")" ] && echo same || echo changed)" \
  "tree_hash detects a change (guards against a constant-hash pass)"

# ====================================================== 9. branch independence
#
# Syncing the same project from two different branches must yield the same set
# of harness paths. A branch carrying skills the project's main already dropped
# retires them like any other project-only path: the template, not the project
# branch, is the authority. Without this, "deterministic" would hold only per
# branch, and the tree you got would depend on where you happened to be stood.

printf '\n-- 9. two branches converge on one template --\n'

P9="$FIXTURE_ROOT/p9"; T9="$FIXTURE_ROOT/t9"
make_project "$P9"; make_template "$T9"
_f "$P9/.agents/agents/shared-project-agent.md" "project specific, on both branches"
commit_all "$P9"

# main carries one stale skill; the feature branch carries a different one plus
# a leftover hook. Neither set exists in the template.
_f "$P9/.agents/skills/stale-on-main/SKILL.md" "retired upstream"
commit_all "$P9"

git -C "$P9" checkout -qb feature
git -C "$P9" rm -rq .agents/skills/stale-on-main
_f "$P9/.agents/skills/stale-on-feature/SKILL.md" "retired upstream"
_f "$P9/.claude/hooks/stale-hook.sh"              "retired upstream"
commit_all "$P9"

harness_paths() {
  find "$1/.agents/skills" "$1/.agents/agents" "$1/.claude/skills" "$1/.claude/hooks" \
    -type f 2>/dev/null | sed "s|^$1/||" | LC_ALL=C sort
}

# The allowlist is the project's, not the branch's: written once, honoured from
# either branch.
write_keep "$P9" ".agents/agents/shared-project-agent.md"

run_retire --repo "$P9" --from-dir "$T9" --apply
assert_eq "0" "$RUN_STATUS" "sync from the feature branch succeeds"
FEATURE_PATHS="$(harness_paths "$P9")"

git -C "$P9" checkout -q main
run_retire --repo "$P9" --from-dir "$T9" --apply
assert_eq "0" "$RUN_STATUS" "sync from main succeeds"
MAIN_PATHS="$(harness_paths "$P9")"

assert_contains "$MAIN_PATHS" ".agents/agents/shared-project-agent.md" \
  "the allowlisted project path survives on both branches (non-vacuity)"
assert_eq "$FEATURE_PATHS" "$MAIN_PATHS" \
  "both branches converge on the same set of harness paths"
assert_not_contains "$MAIN_PATHS" "stale-on-main" \
  "a skill the template dropped is retired even when only this branch had it"
assert_not_contains "$FEATURE_PATHS" "stale-on-feature" \
  "the same holds for the other branch's stale skill"

# ========================================================== 10. documentation
#
# The mechanism is only reachable if /sync runs it. These assertions pin the
# procedure to the script and pin the one property that makes the allowlist
# safe: .claude/sync-keep is never synced, so a template update cannot
# overwrite a project's record of its own intent.
#
# Asserted against BOTH trees. .claude/skills/ is the copy Claude Code actually
# reads, so a canonical-only edit ships the feature to no one.

printf '\n-- 10. SKILL.md documents the retirement pass --\n'

for tree in .agents .claude; do
  MD="$tree/skills/sync/SKILL.md"

  assert_file_contains "$MD" "sync-keep" \
    "$tree: SKILL.md documents .claude/sync-keep"
  assert_file_contains "$MD" "scripts/sync-retire.py" \
    "$tree: SKILL.md names the script that performs retirement"

  # The never-sync list is where a reader checks whether /sync will clobber a
  # file. sync-keep must be named there explicitly, even though it is already
  # outside every root, because "outside the roots" is a property you have to
  # derive and this list is where people look.
  NEVER="$(awk '/^\*\*Never sync\*\*/ { inlist = 1; next }
                inlist && /^## / { exit }
                inlist { print }' "$MD")"
  assert_contains "$NEVER" ".claude/sync-keep" \
    "$tree: sync-keep appears in the Never sync list"

  # The pass runs in dry-run during the change summary, so its output is
  # visible before any write, and applies for options 1 and 2 only.
  assert_prose_contains "$MD" "dry run" \
    "$tree: the summary-time run is documented as a dry run"
done

# The retirement pass must be wired into the procedure, not merely described.
assert_file_matches ".agents/skills/sync/SKILL.md" "^### Step 6\.4" \
  "canonical: the retirement step exists in the procedure"

# ================================================= 11. review-driven contracts
#
# Each block below pins a defect found in APOSD review of the first
# implementation. They are grouped here, one block per finding, so a later
# reader can see what the review bought.

printf '\n-- 11. defects found in design review --\n'

# F1 — the candidate allowlist is the one artifact a human edits by hand. It was
# opened with "w", so a second bootstrap --apply silently destroyed a
# half-finished review, and re-running /sync is routine.
P11="$FIXTURE_ROOT/p11"; T11="$FIXTURE_ROOT/t11"
make_project "$P11"; make_template "$T11"
_f "$P11/.agents/skills/mine/SKILL.md" "project specific"; commit_all "$P11"

run_retire --repo "$P11" --from-dir "$T11" --apply
assert_eq "0" "$RUN_STATUS" "F1: first bootstrap --apply writes the candidate"
printf '%s\n' "# reviewed by a human" ".agents/skills/mine/SKILL.md" > "$P11/.claude/sync-keep.candidate"
run_retire --repo "$P11" --from-dir "$T11" --apply
assert_eq "1" "$RUN_STATUS" "F1: a second bootstrap --apply refuses rather than overwriting"
assert_contains "$RUN_OUTPUT" "sync-keep.candidate" "F1: the refusal names the file"
assert_file_contains "$P11/.claude/sync-keep.candidate" "# reviewed by a human" \
  "F1: the human's edits survive the second run"

# F7 — the dry run is what SKILL.md Step 3 shows during the change summary, so
# it is where an unconfigured project has to be told what to do. It named the
# file and stopped, and carried no mode line at all.
rm -f "$P11/.claude/sync-keep.candidate"
run_retire --repo "$P11" --from-dir "$T11"
assert_contains "$RUN_OUTPUT" "next:" "F7: the bootstrap dry run says what to do next"
assert_contains "$RUN_OUTPUT" "--apply" "F7: the instruction names the flag that writes the candidate"
assert_contains "$RUN_OUTPUT" "mode:   dry-run" "F7: bootstrap reports the same mode line as every other path"

# F2 — the mode line was printed before any deletion ran, so a mid-loop failure
# left stdout asserting N files were deleted when fewer were. For a tool whose
# report is the record of what was destroyed, the record must follow the act.
P11B="$FIXTURE_ROOT/p11b"; T11B="$FIXTURE_ROOT/t11b"
make_project "$P11B"; make_template "$T11B"
_f "$P11B/.agents/skills/gone-a/SKILL.md" "retired"; _f "$P11B/.agents/skills/gone-b/SKILL.md" "retired"
commit_all "$P11B"; write_keep "$P11B"
run_retire --repo "$P11B" --from-dir "$T11B" --apply
assert_contains "$RUN_OUTPUT" "mode:   applied (2 deleted)" "F2: the count reports what was actually removed"
# The list still precedes the act; only the outcome line follows it.
assert_eq "0" "$(printf '%s\n' "$RUN_OUTPUT" | grep -n 'mode:' | cut -d: -f1 | \
  { read -r m; printf '%s\n' "$RUN_OUTPUT" | grep -n 'retire:' | cut -d: -f1 | \
    while read -r r; do [ "$r" -lt "$m" ] || echo late; done; } | grep -c late)" \
  "F2: every retire line is printed before the outcome line"

# F3 — validate_pattern tested a literal string prefix while match_path is a
# glob matcher, so `.claude/**` was rejected with a message asserting it could
# never protect anything, which is the opposite of true.
P11C="$FIXTURE_ROOT/p11c"; T11C="$FIXTURE_ROOT/t11c"
make_project "$P11C"; make_template "$T11C"
_f "$P11C/.claude/hooks/mine.sh" "project specific"; commit_all "$P11C"
write_keep "$P11C" ".claude/**"
run_retire --repo "$P11C" --from-dir "$T11C"
assert_eq "0" "$RUN_STATUS" "F3: a pattern whose glob reaches into a root is accepted"
assert_contains "$RUN_OUTPUT" "kept:   .claude/hooks/mine.sh (matched .claude/**)" \
  "F3: and it actually protects the path it reaches"
# The check still rejects a pattern that reaches no root at all.
write_keep "$P11C" "tasks/**"
run_retire --repo "$P11C" --from-dir "$T11C"
assert_eq "1" "$RUN_STATUS" "F3: a pattern reaching no root is still rejected"

# F5 — the project inventory is the tracked set and --from-ref is the committed
# tree, but --from-dir walked the filesystem, so gitignored residue counted as
# template content. assert_roots_present could then be satisfied by a root that
# the committed tree does not contain.
P11D="$FIXTURE_ROOT/p11d"; T11D="$FIXTURE_ROOT/t11d"
make_project "$P11D"; write_keep "$P11D"
make_template "$T11D"
git init -q --initial-branch=main "$T11D"
git -C "$T11D" config user.name fixture; git -C "$T11D" config user.email fixture@example.test
printf '__pycache__/\n' > "$T11D/.gitignore"
git -C "$T11D" add -A >/dev/null 2>&1; git -C "$T11D" commit -qm template
# Residue that exists on disk but was never committed.
_f "$T11D/.agents/skills/residue/__pycache__/x.pyc" "build residue"
_f "$P11D/.agents/skills/residue/__pycache__/x.pyc" "matching residue in the project"
# Commit it: untracked residue can never appear in any output under any
# implementation, so without this the assertion below passes vacuously and the
# git branch of template_paths_from_dir has no load-bearing test at all.
printf '__pycache__/\n' > "$P11D/.gitignore"
_f "$P11D/.agents/skills/residue/x.md" "project-only, tracked, under a real root"
commit_all "$P11D"
run_retire --repo "$P11D" --from-dir "$T11D"
assert_eq "0" "$RUN_STATUS" "F5: a git template checkout is read the same way as a ref"
assert_not_contains "$RUN_OUTPUT" ".pyc" \
  "F5: gitignored residue is not template content, and is not project content either"

# F6 — a trailing slash in a Markdown table decides whether a root is scanned by
# a destructive tool, and two hand-written parsers of that block must agree on
# which entries are directories.
AWK_DIRS="$(awk '/^## Syncable Paths/ { b = 1; next }
                 b && /^## / { exit }
                 b && /→/ { print $1 }' .agents/skills/sync/SKILL.md | grep '/$' | LC_ALL=C sort)"
PY_DIRS="$(python3 - <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sr", ".agents/skills/sync/scripts/sync-retire.py")
m = importlib.util.module_from_spec(spec); sys.modules["sr"] = m; spec.loader.exec_module(m)
print("\n".join(m.parse_syncable_roots(open(".agents/skills/sync/SKILL.md").read(), "SKILL.md")))
PYX
)"
assert_contains "$AWK_DIRS" ".agents/skills/" "F6: the awk extractor found the block (non-vacuity)"
assert_eq "$AWK_DIRS" "$PY_DIRS" \
  "F6: the script's root list equals the drift test's directory subset"
assert_prose_contains ".agents/skills/sync/SKILL.md" "machine-parsed" \
  "F6: the block warns an editor that it is parsed by a script"

# ========================================= 12. hostile template cannot escape
#
# The doc block that decides which roots get scanned is read from the TEMPLATE,
# which is a remote repository. So the template chooses what a destructive tool
# is pointed at. Two independent layers keep that choice inside the project, and
# both are pinned here because both are currently incidental: a future refactor
# of `project_paths` to a filesystem walk — the obvious "simplification" — would
# silently remove the second one.

printf '\n-- 12. a hostile template cannot reach outside the project --\n'

OUTSIDE="$FIXTURE_ROOT/victim-outside"
mkdir -p "$OUTSIDE"; printf 'precious\n' > "$OUTSIDE/secret.txt"
P12="$FIXTURE_ROOT/p12"; T12="$FIXTURE_ROOT/t12"
make_project "$P12"; write_keep "$P12"

# Layer 1 — a root the template declares but cannot vouch for is refused.
make_template "$T12" "../victim-outside/   → traversal"
run_retire --repo "$P12" --from-dir "$T12" --apply
assert_eq "1" "$RUN_STATUS" "a traversing root the template cannot vouch for is refused"
assert_contains "$RUN_OUTPUT" "../victim-outside/" "the refusal names the traversing root"

# Layer 2 — even when the template DOES carry files under that root, so a
# contents check would be satisfied, the root is still refused on its shape.
mkdir -p "$FIXTURE_ROOT/victim-outside"; printf 'decoy\n' > "$T12/../victim-outside/decoy.txt"
run_retire --repo "$P12" --from-dir "$T12" --apply
assert_eq "1" "$RUN_STATUS" "a traversing root backed by real template files is still refused"
assert_file_contains "$OUTSIDE/secret.txt" "precious" \
  "a file outside the project is never touched"

# An absolute root is refused the same way, and deletes nothing.
P12A="$FIXTURE_ROOT/p12a"; T12A="$FIXTURE_ROOT/t12a"
make_project "$P12A"; write_keep "$P12A"
make_template "$T12A" "/etc/                → absolute"
run_retire --repo "$P12A" --from-dir "$T12A" --apply
assert_eq "1" "$RUN_STATUS" "an absolute root in the doc block is refused"
assert_eq "present" "$([ -f "$P12A/.agents/skills/build/SKILL.md" ] && echo present || echo gone)" \
  "the refused run deleted nothing"

# ================================== 13. the template cannot widen the blast radius
#
# Found by security review, reproduced before fixing: the doc block that decides
# which roots are scanned is read from the TEMPLATE — a remote repository, or in
# manual-diff mode a directory under /tmp. Nothing constrained what a root could
# be, so a hostile or mistaken template could name `src/` or `.claude/` and this
# tool would delete the project's source and its own never-sync config.
#
# Staying inside the repository is not sufficient: the earlier traversal tests
# passed while this hole was wide open, because every path here IS inside the
# repository. A root must additionally be one of the directories /sync manages.

printf '\n-- 13. a hostile doc block cannot widen the scan --\n'

P13="$FIXTURE_ROOT/p13"; T13="$FIXTURE_ROOT/t13"
make_project "$P13"
mkdir -p "$P13/src"
_f "$P13/src/app.py" "production code"
_f "$P13/.claude/project.md" "project config, never synced"
commit_all "$P13"; write_keep "$P13"

# An ordinary project directory named as a root.
make_template "$T13" "src/                  → hostile"
_f "$T13/src/decoy.py" "decoy so a contents check would pass"
run_retire --repo "$P13" --from-dir "$T13" --apply
assert_eq "1" "$RUN_STATUS" "a root outside the harness directories is refused"
assert_contains "$RUN_OUTPUT" "src/" "the refusal names the offending root"
assert_file_contains "$P13/src/app.py" "production code" "project source is untouched"

# `.claude/` itself — one segment — would sweep in the never-sync files,
# including the allowlist this whole mechanism depends on.
P13B="$FIXTURE_ROOT/p13b"; T13B="$FIXTURE_ROOT/t13b"
make_project "$P13B"; _f "$P13B/.claude/project.md" "project config"; commit_all "$P13B"
write_keep "$P13B"
make_template "$T13B" ".claude/              → hostile"
_f "$T13B/.claude/decoy.md" "decoy"
run_retire --repo "$P13B" --from-dir "$T13B" --apply
assert_eq "1" "$RUN_STATUS" "a bare top-level harness directory is refused as a root"
assert_file_contains "$P13B/.claude/project.md" "project config" \
  "the project's never-sync config is untouched"
assert_eq "present" "$([ -f "$P13B/.claude/sync-keep" ] && echo present || echo gone)" \
  "the allowlist itself survives"

# The seven real roots still parse — the constraint must not break the tool.
run_retire --repo "$P13B" --from-dir "$T13B" >/dev/null 2>&1
REAL_ROOTS="$(python3 - <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sr", ".agents/skills/sync/scripts/sync-retire.py")
m = importlib.util.module_from_spec(spec); sys.modules["sr"] = m; spec.loader.exec_module(m)
print(len(m.parse_syncable_roots(open(".agents/skills/sync/SKILL.md").read(), "real")))
PYX
)"
assert_eq "7" "$REAL_ROOTS" "all seven real syncable roots still pass the constraint"

# ============================== 14. allowlist entries that protect nothing
#
# The validator's docstring says it exists so a pattern cannot fail silently.
# Two shapes slipped through: a trailing-slash directory (the most natural thing
# a human writes) and a truncated prefix. Both reach a root, so the reachability
# check passed, but neither can ever fullmatch a FILE path — so every file they
# were written to save was retired, exit 0, no warning.

printf '\n-- 14. a sync-keep entry that can never match --\n'

P14="$FIXTURE_ROOT/p14"; T14="$FIXTURE_ROOT/t14"
make_project "$P14"; make_template "$T14"
_f "$P14/.agents/skills/mine/SKILL.md" "project specific"
_f "$P14/.agents/skills/mine/scripts/deep.sh" "project specific"
commit_all "$P14"

# A directory pattern is rejected outright, and the message names the fix.
write_keep "$P14" ".agents/skills/mine/"
run_retire --repo "$P14" --from-dir "$T14" --apply
assert_eq "1" "$RUN_STATUS" "a trailing-slash directory pattern is refused"
assert_contains "$RUN_OUTPUT" ".agents/skills/mine/**" "the refusal names the pattern that would work"
assert_eq "present" "$([ -f "$P14/.agents/skills/mine/SKILL.md" ] && echo present || echo gone)" \
  "nothing is deleted when a pattern is refused"

# A pattern that is well-formed but matched nothing this run is reported, not
# silently ignored — a stale allowlist entry is how a path starts being deleted.
write_keep "$P14" ".agents/skills/mine/**" ".agents/skills/typo-never-matches/**"
run_retire --repo "$P14" --from-dir "$T14"
assert_eq "0" "$RUN_STATUS" "a pattern matching nothing is a warning, not a failure"
assert_contains "$RUN_OUTPUT" "unmatched: .agents/skills/typo-never-matches/**" \
  "the unmatched pattern is named"
assert_not_contains "$RUN_OUTPUT" "unmatched: .agents/skills/mine/**" \
  "a pattern that did match is not reported as unmatched"

# ================================ 15. candidates must be patterns, not paths
#
# write_candidate emitted raw paths into a file whose lines are globs. A path
# containing `*` became an over-broad rule that protected unrelated siblings
# from retirement; a path containing `[` produced a candidate that, once
# promoted, made every later sync exit 1. Both reviewers found this
# independently.

printf '\n-- 15. glob metacharacters in candidate paths --\n'

P15="$FIXTURE_ROOT/p15"; T15="$FIXTURE_ROOT/t15"
make_project "$P15"; make_template "$T15"
_f "$P15/.agents/skills/note[1].md" "bracket in the filename"
_f "$P15/.agents/skills/plain.md"   "ordinary project-only path"
commit_all "$P15"

run_retire --repo "$P15" --from-dir "$T15" --apply
assert_eq "0" "$RUN_STATUS" "bootstrap succeeds even with an unexpressible path"
assert_file_contains "$P15/.claude/sync-keep.candidate" ".agents/skills/plain.md" \
  "an ordinary path is emitted as a usable pattern"
assert_file_contains "$P15/.claude/sync-keep.candidate" "# UNEXPRESSIBLE" \
  "a path with glob metacharacters is commented out, not emitted as a pattern"

# The promoted candidate must be a valid allowlist — the failure this prevents
# is a sync that exits 1 on a line the tool itself wrote.
cp "$P15/.claude/sync-keep.candidate" "$P15/.claude/sync-keep"
run_retire --repo "$P15" --from-dir "$T15"
assert_eq "0" "$RUN_STATUS" "the promoted candidate validates"
assert_contains "$RUN_OUTPUT" "kept:   .agents/skills/plain.md" "and protects what it names"

# ============================== 16. a deletion that fails part-way still reports
#
# The uncovered branch on the destructive path, and the one where files are lost
# without a record. `apply_plan` built a list of what it removed, but a
# propagating OSError threw that list away: the operator saw a plan of N, an
# errno, and had to run `git status` to learn which files were already gone.

printf '\n-- 16. partial deletion leaves a record --\n'

P16="$FIXTURE_ROOT/p16"; T16="$FIXTURE_ROOT/t16"
make_project "$P16"; make_template "$T16"
_f "$P16/.agents/skills/a-first/SKILL.md"  "retired, deletable"
_f "$P16/.agents/skills/z-locked/SKILL.md" "retired, in a directory made read-only"
commit_all "$P16"; write_keep "$P16"
chmod a-w "$P16/.agents/skills/z-locked"

run_retire --repo "$P16" --from-dir "$T16" --apply
chmod u+w "$P16/.agents/skills/z-locked"

assert_eq "1" "$RUN_STATUS" "a deletion failure exits non-zero"
assert_contains "$RUN_OUTPUT" "mode:   applied (1 deleted, 1 failed)" \
  "the outcome counts what happened, not what was planned"
assert_contains "$RUN_OUTPUT" "FAILED: .agents/skills/z-locked/SKILL.md" \
  "the path that could not be deleted is named"
assert_eq "gone" "$([ -e "$P16/.agents/skills/a-first/SKILL.md" ] && echo present || echo gone)" \
  "the deletable path really was deleted"
assert_eq "present" "$([ -f "$P16/.agents/skills/z-locked/SKILL.md" ] && echo present || echo gone)" \
  "the undeletable path really did survive"
# The record must match the disk: exactly the paths reported deleted are gone.
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/a-first/SKILL.md" \
  "the full plan is still printed before the outcome"

# ====================== 17. second-review defects: exec, records, round-trips
#
# Each block below reproduces a defect that two independently dispatched
# reviewers found in the shipped script. They are pinned here because every one
# of them was invisible to the sixteen sections above: the suite was green while
# the tool could execute a command from an untrusted checkout, and green while a
# failed prune discarded the list of files it had just destroyed.

# --- 17.1 a failed prune must not discard the record of what was deleted ------
#
# The deletion loop was already accounted for (section 16); the prune loop that
# follows it was not, so an OSError there propagated out and the operator was
# shown an errno instead of the list of files already gone.

P17="$FIXTURE_ROOT/p17"; T17="$FIXTURE_ROOT/t17"
make_project "$P17"; make_template "$T17"
# Nested deliberately: os.remove needs write on the file's own directory, so
# locking that would block the *deletion*. Locking the grandparent leaves the
# delete free and makes only the rmdir above it fail -- the prune path.
_f "$P17/.agents/skills/orphan/sub/SKILL.md" "retired; its grandparent resists rmdir"
commit_all "$P17"; write_keep "$P17"
chmod a-w "$P17/.agents/skills/orphan"

run_retire --repo "$P17" --from-dir "$T17" --apply
chmod u+w "$P17/.agents/skills/orphan"

assert_contains "$RUN_OUTPUT" "applied (1 deleted" \
  "a prune failure still reports the deletion that succeeded"
assert_contains "$RUN_OUTPUT" "1 not pruned" \
  "the unprunable directory is counted separately from a failed deletion"
assert_contains "$RUN_OUTPUT" "UNPRUNED: .agents/skills/orphan/sub" \
  "the directory that could not be pruned is named"
assert_eq "gone" "$([ -e "$P17/.agents/skills/orphan/sub/SKILL.md" ] && echo present || echo gone)" \
  "the file really was deleted, which is why the record must survive"

# --- 17.2 an untrusted template checkout cannot choose what git executes ------
#
# `--from-dir` runs git inside a tree the project did not write. git honours
# that repo's own config, and core.fsmonitor names a command git runs on
# ls-files -- reached during the *dry run*, before any approval.

P18="$FIXTURE_ROOT/p18"; T18="$FIXTURE_ROOT/t18"
make_project "$P18"; make_template "$T18"
git init -q --initial-branch=main "$T18"
git -C "$T18" config user.name fixture
git -C "$T18" config user.email fixture@example.test
commit_all "$T18"
write_keep "$P18"
git -C "$T18" config core.fsmonitor "touch $FIXTURE_ROOT/PWNED; false"
rm -f "$FIXTURE_ROOT/PWNED"

run_retire --repo "$P18" --from-dir "$T18"

assert_eq "absent" "$([ -e "$FIXTURE_ROOT/PWNED" ] && echo present || echo absent)" \
  "a template's core.fsmonitor is not executed during the dry run"

run_retire --repo "$P18" --from-dir "$T18" --apply
assert_eq "absent" "$([ -e "$FIXTURE_ROOT/PWNED" ] && echo present || echo absent)" \
  "nor under --apply"

# --- 17.3 a candidate the reader would strip is written as a comment ---------
#
# read_keep_patterns strips each line, so a path with surrounding whitespace
# round-trips into a pattern that cannot match it: the file the human
# allowlisted is deleted anyway, at exit 0. Same class as the `[` case that
# _as_pattern already guarded.

P19="$FIXTURE_ROOT/p19"; T19="$FIXTURE_ROOT/t19"
make_project "$P19"; make_template "$T19"
_f "$P19/.agents/skills/mine/trailing " "project-only, name ends in a space"
_f "$P19/.agents/skills/mine/plain.md"  "project-only, expressible"
commit_all "$P19"
rm -f "$P19/.claude/sync-keep"

run_retire --repo "$P19" --from-dir "$T19" --apply

assert_contains "$(cat "$P19/.claude/sync-keep.candidate")" "# UNEXPRESSIBLE" \
  "a path the reader would strip is commented out, not offered as a pattern"
assert_contains "$(cat "$P19/.claude/sync-keep.candidate")" ".agents/skills/mine/plain.md" \
  "an expressible sibling is still written as a live pattern"
# The live pattern must be the plain one only: a bare `trailing` line would look
# like protection and silently match nothing on the next run.
assert_eq "0" "$(grep -c '^\.agents/skills/mine/trailing $' "$P19/.claude/sync-keep.candidate" || true)" \
  "the unexpressible path is never emitted as an uncommented rule"

# --- 17.4 the root validator rejects a traversing or globbed segment ---------
#
# `[^/]+` matched `..`, `.` and `*`, so the guard whose stated job is refusing
# to point a file-deleting tool at the wrong place accepted `.claude/../`.
# assert_roots_present blocked it incidentally; the designated guard must too.

for _bad in '.claude/../' '.claude/./' '.claude/*/'; do
  P20="$FIXTURE_ROOT/p20"; T20="$FIXTURE_ROOT/t20"
  rm -rf "$P20" "$T20"
  make_project "$P20"; make_template "$T20" "$_bad          → hostile root"
  write_keep "$P20"
  run_retire --repo "$P20" --from-dir "$T20"
  assert_eq "1" "$RUN_STATUS" "a root segment of '$_bad' is refused"
  assert_contains "$RUN_OUTPUT" "$_bad" "the refusal names the offending root"
  # Which guard rejected it matters. assert_roots_present also refuses these,
  # incidentally, because git normalises its output -- so asserting only "exit 1"
  # stays green with the traversal hole wide open. Pin the *designated* guard by
  # its own message, or a later change to the reachability check silently
  # reopens whole-repo deletion.
  assert_contains "$RUN_OUTPUT" "is not a syncable root" \
    "the root-shape validator is what rejects '$_bad', not a downstream accident"
done

# --- 17.5 a sub-heading closes the doc block --------------------------------
#
# The terminator matched "## " only, so a `### Subsection` left the block open
# and any arrow line beneath it was read as a root. Matched at any heading depth
# now -- but a single `#` shell comment inside a fence must still NOT close it.

P21="$FIXTURE_ROOT/p21"; T21="$FIXTURE_ROOT/t21"
make_project "$P21"; make_template "$T21"
# Reopen the template's doc block with a sub-heading, then smuggle a root under it.
python3 - "$T21/.agents/skills/sync/SKILL.md" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
s = s.replace("## Next Section", "### Subsection\n.claude/smuggled/  → injected\n\n## Next Section")
io.open(p, "w", encoding="utf-8").write(s)
PY
_f "$P21/.claude/smuggled/x.md" "would be scanned if the block stayed open"
commit_all "$P21"; write_keep "$P21"

run_retire --repo "$P21" --from-dir "$T21"

assert_eq "0" "$RUN_STATUS" "a sub-heading closes the block rather than erroring"
# If the block had stayed open, .claude/smuggled/ would be a scanned root and
# its project-only file would appear as a retire candidate.
assert_not_contains "$RUN_OUTPUT" "smuggled" \
  "a root declared after a sub-heading is not read as a syncable root"

# ============== 18. third-review defects: seams, records and round-trips
#
# Round 2 fixed the script; round 3 found that most of what remained lived in
# the seam between the script and the procedure that drives it, and that several
# round-2 fixes were pinned by assertions that survived their own mutation.

# --- 18.1 a candidate line the tool wrote must never break the next run -------
#
# _as_pattern detected a newline but interpolated the raw path into the comment's
# last line, so everything after the break landed at column 0 as a live rule.
# Backslash was missing from the set outright, though validate_pattern rejects it.

P22="$FIXTURE_ROOT/p22"; T22="$FIXTURE_ROOT/t22"
make_project "$P22"; make_template "$T22"
_f "$P22/.agents/skills/mine/plain.md" "expressible"
_f "$P22/.agents/skills/mine/we\\ird.md" "backslash: validate_pattern refuses this"
_f "$P22/.agents/skills/mine/$(printf 'br\noken')" "a real newline inside the filename"
commit_all "$P22"
rm -f "$P22/.claude/sync-keep"

run_retire --repo "$P22" --from-dir "$T22" --apply
assert_eq "0" "$RUN_STATUS" "bootstrap writes a candidate"

# Promote the tool's own output verbatim: it must be readable by its own reader.
cp "$P22/.claude/sync-keep.candidate" "$P22/.claude/sync-keep"
run_retire --repo "$P22" --from-dir "$T22"
assert_eq "0" "$RUN_STATUS" \
  "the candidate this tool wrote is accepted verbatim by its own reader"
assert_not_contains "$RUN_OUTPUT" "use POSIX separators" \
  "a backslash path is commented out, not emitted as a rule that fails every later sync"
assert_not_contains "$RUN_OUTPUT" "is outside every syncable root" \
  "and a newline does not split into a second, live rule at column 0"
# Structural form of the same claim: every non-blank candidate line is either a
# comment or a pattern the reader accepts. A continuation line is neither.
assert_eq "0" "$(grep -vE '^#|^[[:space:]]*$' "$P22/.claude/sync-keep.candidate" \
  | grep -cvE '^\.(agents|claude)/' || true)" \
  "no candidate line is a bare fragment of a path"
assert_contains "$RUN_OUTPUT" "kept:   .agents/skills/mine/plain.md" \
  "while the expressible sibling still protects its file"

# --- 18.2 pruning stops at the syncable root even when the root empties -------
#
# The old fixture kept the root alive on leftover contents, so deleting the
# boundary check entirely left the suite green while a whole root was removed.

P23="$FIXTURE_ROOT/p23"; T23="$FIXTURE_ROOT/t23"
make_project "$P23"; make_template "$T23"
rm -f "$P23/.claude/hooks/session-start.sh"          # root's ONLY surviving file
_f "$P23/.claude/hooks/old-hook.sh" "retired upstream; the root's entire contents"
commit_all "$P23"; write_keep "$P23"

run_retire --repo "$P23" --from-dir "$T23" --apply
assert_eq "gone" "$([ -e "$P23/.claude/hooks/old-hook.sh" ] && echo present || echo gone)" \
  "the root's last file is retired"
assert_eq "present" "$([ -d "$P23/.claude/hooks" ] && echo present || echo gone)" \
  "but the syncable root itself survives being emptied"

# --- 18.3 a partial run reports what it destroyed, and names the right dir ----

P24="$FIXTURE_ROOT/p24"; T24="$FIXTURE_ROOT/t24"
make_project "$P24"; make_template "$T24"
_f "$P24/.agents/skills/gamma/deep/deeper/y.md" "retired; a parent will resist rmdir"
commit_all "$P24"; write_keep "$P24"
chmod a-w "$P24/.agents/skills/gamma"   # deeper prunes fine; gamma/deep cannot

run_retire --repo "$P24" --from-dir "$T24" --apply
chmod u+w "$P24/.agents/skills/gamma"

assert_contains "$RUN_OUTPUT" "deleted: .agents/skills/gamma/deep/deeper/y.md" \
  "a partial run prints the record of what it destroyed, not just a count"
# Pruning walks upward, so the directory it STARTED at is usually removed fine.
# Reporting that one names a path that no longer exists.
assert_contains "$RUN_OUTPUT" "UNPRUNED: .agents/skills/gamma/deep " \
  "the directory named is the one that actually failed"
assert_eq "present" "$([ -d "$P24/.agents/skills/gamma/deep" ] && echo present || echo gone)" \
  "and that directory is genuinely still on disk"

# --- 18.4 sync-keep states: absent, empty, and unusable are three things ------

P25="$FIXTURE_ROOT/p25"; T25="$FIXTURE_ROOT/t25"
make_project "$P25"; make_template "$T25"
_f "$P25/.agents/skills/mine/SKILL.md" "project-only"
commit_all "$P25"

rm -f "$P25/.claude/sync-keep"
ln -s /nonexistent-target "$P25/.claude/sync-keep"
run_retire --repo "$P25" --from-dir "$T25" --apply
assert_eq "1" "$RUN_STATUS" "a sync-keep that is not a regular file is an error"
assert_contains "$RUN_OUTPUT" "not a regular file" "and says so"
assert_eq "absent" "$([ -e "$P25/.claude/sync-keep.candidate" ] && echo present || echo absent)" \
  "it is not mistaken for bootstrap, so no candidate is written over it"

rm -f "$P25/.claude/sync-keep"
printf '.agents/skills/x\xff\xfe.md\n' > "$P25/.claude/sync-keep"
run_retire --repo "$P25" --from-dir "$T25" --apply
assert_eq "1" "$RUN_STATUS" "an undecodable sync-keep exits 1"
assert_contains "$RUN_OUTPUT" "sync-retire: cannot read" \
  "reported on the tool's own channel, not as a traceback"
assert_not_contains "$RUN_OUTPUT" "Traceback" "specifically, not as a traceback"

# --- 18.5 a .git FILE must not redirect the inventory to another repository ---
#
# read_template_doc reads SKILL.md from this directory's disk while the git
# branch read the file list from wherever the gitdir pointer led: one plan, two
# templates, exit 0.

P26="$FIXTURE_ROOT/p26"; T26="$FIXTURE_ROOT/t26"; OTHER="$FIXTURE_ROOT/other26"
make_project "$P26"; make_template "$T26"; make_project "$OTHER"
_f "$OTHER/.agents/skills/beta/SKILL.md" "only in the unrelated repo"
commit_all "$OTHER"
_f "$P26/.agents/skills/beta/SKILL.md" "project copy, retired unless the pointer is followed"
commit_all "$P26"; write_keep "$P26"
printf 'gitdir: %s/.git\n' "$OTHER" > "$T26/.git"

run_retire --repo "$P26" --from-dir "$T26"
assert_eq "0" "$RUN_STATUS" "a .git file is treated as a plain directory, not a repo"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/beta/SKILL.md" \
  "the inventory comes from the directory on disk, not from the repo its .git file names"

# --- 18.6 a template checkout without the doc block is an error --------------

P27="$FIXTURE_ROOT/p27"; T27="$FIXTURE_ROOT/t27"
make_project "$P27"; make_template "$T27"; write_keep "$P27"
rm -f "$T27/.agents/skills/sync/SKILL.md"

run_retire --repo "$P27" --from-dir "$T27" --apply
assert_eq "1" "$RUN_STATUS" "a template checkout with no SKILL.md exits 1"
assert_contains "$RUN_OUTPUT" "template checkout has no" "and names what is missing"

# --- 18.7 git config from outside the repo cannot choose what runs -----------
#
# 17.2 pinned the repo-config route only, so the GIT_CONFIG_GLOBAL suppression
# and the core.hooksPath pin could both be deleted with the suite green.

P28="$FIXTURE_ROOT/p28"; T28="$FIXTURE_ROOT/t28"
make_project "$P28"; make_template "$T28"; write_keep "$P28"
printf '[core]\n\tfsmonitor = "touch %s/PWNED_GLOBAL; false"\n' "$FIXTURE_ROOT" \
  > "$FIXTURE_ROOT/evil-global-config"
rm -f "$FIXTURE_ROOT/PWNED_GLOBAL"

GIT_CONFIG_GLOBAL="$FIXTURE_ROOT/evil-global-config" \
  python3 "$RETIRE" --repo "$P28" --from-dir "$T28" >/dev/null 2>&1
# NOTE: this assertion cannot distinguish the two guards. `-c core.fsmonitor=`
# outranks global config as well as repo config, so removing the
# GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL suppression leaves this green. The env
# hardening is defence-in-depth behind the `-c` pin, not an independently
# observable behaviour -- recorded here as a smoke test, not as proof of it.
assert_eq "absent" "$([ -e "$FIXTURE_ROOT/PWNED_GLOBAL" ] && echo present || echo absent)" \
  "git config from outside the repo does not name a command this tool executes"

# ================= 19. bootstrap still removes what the template retired
#
# The mechanism this feature replaced was a hardcoded `for retired in tdd deslop
# simplify verify-e2e` loop that deleted unconditionally. Making retirement
# depend on a recorded allowlist lost that for any project which never promotes
# a candidate -- the one case where the new design was strictly weaker.
#
# The record that answers it without a hand-maintained name list is the
# template's own history: a path the template once carried and no longer does
# was retired upstream, not written by this project.

P29="$FIXTURE_ROOT/p29"; T29="$FIXTURE_ROOT/t29"
make_project "$P29"
# A git template WITH history: it once shipped `legacy`, then retired it.
git init -q --initial-branch=main "$T29"
git -C "$T29" config user.name fixture
git -C "$T29" config user.email fixture@example.test
write_skill_md "$T29"
_f "$T29/.agents/skills/build/SKILL.md"  "build skill"
_f "$T29/.agents/agents/planner.md"      "planner"
_f "$T29/.claude/skills/build/SKILL.md"  "build skill"
_f "$T29/.claude/hooks/session-start.sh" "hook"
_f "$T29/CLAUDE.md"                      "rules"
_f "$T29/.claude/settings.json"          "{}"
_f "$T29/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
commit_all "$T29"
git -C "$T29" rm -q -r .agents/skills/legacy
commit_all "$T29"

# The project still carries the retired skill, and has its own local one.
_f "$P29/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
_f "$P29/.agents/skills/ours/SKILL.md"   "this project's own, never in the template"
commit_all "$P29"
rm -f "$P29/.claude/sync-keep"            # bootstrap: no allowlist recorded

run_retire --repo "$P29" --from-dir "$T29"
assert_eq "0" "$RUN_STATUS" "bootstrap with template history succeeds"
assert_contains "$RUN_OUTPUT" "bootstrap: required" "it is still bootstrap"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/legacy/SKILL.md (was template content" \
  "a path the template retired upstream is retired without a human classifying it"
assert_contains "$RUN_OUTPUT" "candidate: .agents/skills/ours/SKILL.md" \
  "while a path the template never carried stays a candidate for the human"
assert_not_contains "$RUN_OUTPUT" "retire: .agents/skills/ours/SKILL.md" \
  "project-specific paths are never retired on provenance alone"

run_retire --repo "$P29" --from-dir "$T29" --apply
assert_eq "gone" "$([ -e "$P29/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "--apply removes the retired-upstream path in bootstrap"
assert_eq "present" "$([ -f "$P29/.agents/skills/ours/SKILL.md" ] && echo present || echo gone)" \
  "and leaves the project's own file untouched"
assert_contains "$(cat "$P29/.claude/sync-keep.candidate")" ".agents/skills/ours/SKILL.md" \
  "the candidate offers only what provenance could not settle"
assert_not_contains "$(cat "$P29/.claude/sync-keep.candidate")" ".agents/skills/legacy/SKILL.md" \
  "and never offers to keep something the template already retired"

# --- 19.2 no history means no conclusion, said out loud ---------------------
#
# A shallow clone's "history" is its current state, which would classify every
# retired path as project-specific. Unknown provenance must not read as proof.

P30="$FIXTURE_ROOT/p30"; T30="$FIXTURE_ROOT/t30"
make_project "$P30"
git clone -q --depth 1 "file://$T29" "$T30" 2>/dev/null
_f "$P30/.agents/skills/legacy/SKILL.md" "stale copy; provenance unavailable here"
commit_all "$P30"
rm -f "$P30/.claude/sync-keep"

run_retire --repo "$P30" --from-dir "$T30" --apply
assert_eq "0" "$RUN_STATUS" "a shallow template still produces a plan"
assert_contains "$RUN_OUTPUT" "provenance: unavailable" \
  "and says provenance could not be established"
assert_eq "present" "$([ -f "$P30/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "retiring nothing rather than guessing"

# =========================================== 20. wrap-up review regressions
#
# Each case below is a defect the review passes found in the code this session
# wrote, reproduced before it was fixed. They share one shape: the program had
# already destroyed something, and then lost the record of having done it. The
# record is the only thing standing between an operator and `git status`
# archaeology, so every path that deletes is pinned here separately -- fixing
# this per call site is exactly what let it recur four times.

printf '\n-- 20. record-loss and provenance regressions --\n'

# A template repository that once shipped `legacy` and later retired it. Shared
# by 20.1-20.3, which all need real history to read.
make_history_template() {
  _dir="$1"
  git init -q --initial-branch=main "$_dir"
  git -C "$_dir" config user.name fixture
  git -C "$_dir" config user.email fixture@example.test
  write_skill_md "$_dir"
  _f "$_dir/.agents/skills/build/SKILL.md"  "build skill"
  _f "$_dir/.agents/agents/planner.md"      "planner"
  _f "$_dir/.claude/skills/build/SKILL.md"  "build skill"
  _f "$_dir/.claude/hooks/session-start.sh" "hook"
  _f "$_dir/CLAUDE.md"                      "rules"
  _f "$_dir/.claude/settings.json"          "{}"
  _f "$_dir/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
  commit_all "$_dir"
  git -C "$_dir" rm -q -r .agents/skills/legacy
  commit_all "$_dir"
}

# --- 20.1 a precondition may not fire after the deletion it guards ----------
#
# Bootstrap --apply deleted first and wrote the candidate second, and
# write_candidate refuses to overwrite an existing candidate. So the ordinary
# state "a candidate was generated but not yet promoted" -- which is every
# second bootstrap run -- deleted files, then raised, and the raise discarded
# `removed`. The operator saw an error about a *file it would not overwrite*,
# exit 1, and no mention of the skill that had just been destroyed.

P31="$FIXTURE_ROOT/p31"; T31="$FIXTURE_ROOT/t31"
make_project "$P31"; make_history_template "$T31"
_f "$P31/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
commit_all "$P31"
rm -f "$P31/.claude/sync-keep"
_f "$P31/.claude/sync-keep.candidate" "# generated earlier, not yet promoted"

run_retire --repo "$P31" --from-dir "$T31" --apply
assert_eq "1" "$RUN_STATUS" "bootstrap --apply refuses an existing candidate"
assert_contains "$RUN_OUTPUT" "sync-keep.candidate already exists" \
  "and says which file it will not overwrite"
assert_eq "present" \
  "$([ -f "$P31/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "the refusal happens before any deletion, not after it"
assert_not_contains "$RUN_OUTPUT" "deleted:" \
  "so there is no destruction to report"
assert_file_contains "$P31/.claude/sync-keep.candidate" "not yet promoted" \
  "and the human's file is left exactly as they left it"

# Promoting the candidate unblocks the same run: the guard is a precondition,
# not a permanent refusal. Without this the assertion above would also pass
# against a program that had simply stopped retiring in bootstrap.
rm -f "$P31/.claude/sync-keep.candidate"
run_retire --repo "$P31" --from-dir "$T31" --apply
assert_eq "0" "$RUN_STATUS" "with no stale candidate the same run succeeds"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/legacy/SKILL.md" \
  "and the same run names the path it is about to destroy"
assert_contains "$RUN_OUTPUT" "applied (1 deleted)" \
  "and reports having destroyed it"
assert_eq "gone" \
  "$([ -e "$P31/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "so the guard was a precondition, not a permanent refusal to retire"

# --- 20.2 every git failure is not "the clone was shallow" ------------------
#
# The probe swallowed its exception and reported one hardcoded cause, so a
# missing ref and an unreadable object both told the operator to deepen a clone
# that was already complete. The reason must be the one git gave.

P32="$FIXTURE_ROOT/p32"; T32="$FIXTURE_ROOT/t32"
make_project "$P32"
git init -q --initial-branch=main "$T32"
git -C "$T32" config user.name fixture
git -C "$T32" config user.email fixture@example.test
make_template "$T32"
commit_all "$T32"                          # one commit: no history to read
_f "$P32/.agents/skills/legacy/SKILL.md" "unclassifiable without provenance"
commit_all "$P32"
rm -f "$P32/.claude/sync-keep"

run_retire --repo "$P32" --from-dir "$T32"
assert_not_contains "$RUN_OUTPUT" "provenance: unavailable" \
  "one commit is a complete history, not an unreadable one"
assert_contains "$RUN_OUTPUT" "candidate: .agents/skills/legacy/SKILL.md" \
  "it simply never retired anything, so nothing has provenance to retire"

# The truncation that *does* hide a retirement is a clone shallower than it.
# Counting commits caught only depth 1, so every deeper shallow clone silently
# produced a different retirement set from the same commit SHA.

P32C="$FIXTURE_ROOT/p32c"; T32CSRC="$FIXTURE_ROOT/t32c-src"; T32C="$FIXTURE_ROOT/t32c"
make_project "$P32C"
make_history_template "$T32CSRC"
# Commits after the retirement, so a depth-2 clone lands entirely above it.
for i in 1 2 3; do
  _f "$T32CSRC/.agents/skills/build/SKILL.md" "build skill revision $i"
  commit_all "$T32CSRC"
done
git clone -q --depth 2 "file://$T32CSRC" "$T32C" 2>/dev/null
_f "$P32C/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
commit_all "$P32C"
rm -f "$P32C/.claude/sync-keep"

run_retire --repo "$P32C" --from-dir "$T32C"
assert_eq "0" "$RUN_STATUS" "a shallow-but-not-single-commit template produces a plan"
assert_contains "$RUN_OUTPUT" "provenance: unavailable" \
  "a clone truncated below the retirement is detected at any depth"
assert_contains "$RUN_OUTPUT" "truncated history" \
  "and named as truncation rather than as a missing ref"
assert_not_contains "$RUN_OUTPUT" "retire: .agents/skills/legacy/SKILL.md" \
  "so it never concludes a retirement from history it cannot see"

# The other way this probe fails is a git error, and it used to be reported with
# the same shallow-clone wording -- telling the operator to deepen a clone whose
# depth was never the problem. A template repo with a staged but uncommitted
# tree reaches it: the doc block and the index both read fine, and only the
# revision does not exist.

P32B="$FIXTURE_ROOT/p32b"; T32B="$FIXTURE_ROOT/t32b"
make_project "$P32B"
make_template "$T32B"
git init -q --initial-branch=main "$T32B"
git -C "$T32B" add -A                      # staged, never committed: no HEAD
_f "$P32B/.agents/skills/legacy/SKILL.md" "unclassifiable without provenance"
commit_all "$P32B"
rm -f "$P32B/.claude/sync-keep"

run_retire --repo "$P32B" --from-dir "$T32B"
assert_eq "0" "$RUN_STATUS" "an unreadable revision still produces a plan"
assert_contains "$RUN_OUTPUT" "unknown revision" \
  "and the reason is the one git gave, carried out of the probe"
assert_not_contains "$RUN_OUTPUT" "single commit" \
  "not the shallow-clone wording every failure used to borrow"
# git's fatals run to three lines with a usage hint. The report is read one
# item per line, so the reason has to arrive as one item.
assert_eq "0" \
  "$(printf '%s\n' "$RUN_OUTPUT" | tail -n +2 | grep -cv '^  ' || true)" \
  "and it stays a single report line, however many lines git used to say it"
assert_contains "$RUN_OUTPUT" "candidate: .agents/skills/legacy/SKILL.md" \
  "unknown provenance holds the path for a human rather than deleting it"
assert_not_contains "$RUN_OUTPUT" "a full clone" \
  "and it does not advise deepening a clone whose depth was never the problem"

# --- 20.3 shallowness is a property of the revision, not the repository -----
#
# `--from-ref` is the mode SKILL.md prescribes, and there the revision lives in
# the *project* repo. Probing `--is-shallow-repository` therefore asked whether
# the project was a shallow checkout -- which is what CI does by default -- and
# answered "no provenance" for every one of them, however complete the fetched
# template ref was. That silently no-ops retirement in the recommended mode.

PORIGIN="$FIXTURE_ROOT/p33-origin"; P33="$FIXTURE_ROOT/p33"
make_project "$PORIGIN"
_f "$PORIGIN/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
_f "$PORIGIN/.agents/skills/ours/SKILL.md"   "this project's own"
rm -f "$PORIGIN/.claude/sync-keep"
commit_all "$PORIGIN"

git clone -q --depth 1 "file://$PORIGIN" "$P33"
git -C "$P33" config user.name fixture
git -C "$P33" config user.email fixture@example.test
assert_eq "true" "$(git -C "$P33" rev-parse --is-shallow-repository)" \
  "the project itself is a shallow checkout"
git -C "$P33" remote add workflow "file://$T31"
git -C "$P33" fetch -q workflow main
git -C "$P33" tag -f workflow-main FETCH_HEAD >/dev/null 2>&1

run_retire --repo "$P33" --from-ref workflow-main
assert_eq "0" "$RUN_STATUS" "a shallow project reads the template ref's history"
assert_not_contains "$RUN_OUTPUT" "provenance: unavailable" \
  "the project's own clone depth does not suppress the template's provenance"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/legacy/SKILL.md" \
  "so retirement still happens in the mode SKILL.md prescribes"
assert_contains "$RUN_OUTPUT" "candidate: .agents/skills/ours/SKILL.md" \
  "and the project's own file is still only a candidate"

# --- 20.4 a directory it cannot read is reported, not raised ----------------
#
# _prune_upwards guarded os.rmdir and not os.listdir, so a directory the
# process may write but not read raised a bare OSError out of apply_plan --
# past the accounting, discarding `removed`. The file was already gone. This is
# the same defect as 20.1 at a different call site, which is why both are here.

if [ "$(id -u)" -eq 0 ]; then
  printf '  skip  20.4 needs an unprivileged user (root ignores permission bits)\n'
else
  P34="$FIXTURE_ROOT/p34"; T34="$FIXTURE_ROOT/t34"
  make_project "$P34"; make_template "$T34"
  _f "$P34/.agents/skills/gone/SKILL.md" "retired: no sync-keep pattern covers it"
  commit_all "$P34"
  write_keep "$P34" ".agents/skills/nothing-at-all/**"
  chmod 300 "$P34/.agents/skills/gone"     # writable and enterable, not readable

  run_retire --repo "$P34" --from-dir "$T34" --apply
  chmod 700 "$P34/.agents/skills/gone" 2>/dev/null || true
  assert_eq "1" "$RUN_STATUS" "an unprunable directory is a non-zero outcome"
  assert_contains "$RUN_OUTPUT" "deleted: .agents/skills/gone/SKILL.md" \
    "but the file it destroyed is still reported by path"
  assert_contains "$RUN_OUTPUT" "UNPRUNED: .agents/skills/gone" \
    "and the directory it could not remove is named separately"
  assert_contains "$RUN_OUTPUT" "mode:   applied" \
    "the accounting ran at all — the OSError did not escape past it"
fi

# --- 20.5 a pattern's legality is judged against the declared roots ---------
#
# read_keep_patterns was handed the *scanned* roots, so a sync-keep line naming
# a path under a root the template had just emptied was "outside every syncable
# root" -- exit 1, every unrelated retirement blocked. Skipping an emptied root
# exists precisely so one upstream commit cannot stop retirement everywhere;
# scoping the pattern check to the same list gave that back.

P35="$FIXTURE_ROOT/p35"; T35="$FIXTURE_ROOT/t35"
make_project "$P35"; make_template "$T35"
rm -rf "$T35/.claude/hooks"                # upstream emptied this root
_f "$P35/.claude/hooks/local.sh"      "project-specific, under the emptied root"
_f "$P35/.agents/skills/gone/SKILL.md" "retired: nothing keeps it"
commit_all "$P35"
write_keep "$P35" ".claude/hooks/local.sh"

run_retire --repo "$P35" --from-dir "$T35"
assert_eq "0" "$RUN_STATUS" \
  "a sync-keep entry under an emptied root does not abort the run"
assert_contains "$RUN_OUTPUT" "skipped: .claude/hooks/" \
  "the emptied root is skipped and said so"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/gone/SKILL.md" \
  "and retirement under every other root still proceeds"

assert_contains "$RUN_OUTPUT" "dormant: .claude/hooks/local.sh" \
  "the pattern is reported as dormant, not as one that matched nothing"
assert_not_contains "$RUN_OUTPUT" "unmatched: .claude/hooks/local.sh" \
  "because `unmatched` reads as an invitation to delete the only protection"

run_retire --repo "$P35" --from-dir "$T35" --apply
assert_eq "present" "$([ -f "$P35/.claude/hooks/local.sh" ] && echo present || echo gone)" \
  "nothing under a skipped root is deleted"

# --- 20.6 the two readers of the doc block agree at every heading depth -----
#
# tests/test-syncable-paths.sh terminates the block on awk's `^##+ `, which is
# unbounded. This parser used `^#{2,6} `, so a 7-hash heading closed the block
# for one reader and not the other -- and the arrow line beneath it became a
# seventh root here and nowhere else.

P36="$FIXTURE_ROOT/p36"; T36="$FIXTURE_ROOT/t36"
make_project "$P36"
make_template "$T36"
# Inside the block, before its real terminator -- appending after
# `## Next Section` would test nothing, since that heading already closed it.
python3 - "$T36/.agents/skills/sync/SKILL.md" <<'EOF_PY'
import io, sys
path = sys.argv[1]
text = io.open(path, encoding="utf-8").read()
io.open(path, "w", encoding="utf-8").write(
    text.replace("## Next Section", "####### Deep heading\n\n/etc/ → not a root\n\n## Next Section")
)
EOF_PY

run_retire --repo "$P36" --from-dir "$T36"
assert_eq "0" "$RUN_STATUS" "a 7-hash heading after the fence is not a parse error"
assert_contains "$RUN_OUTPUT" "roots: 4" \
  "it closes the block, so the line beneath it is not read as a root"
assert_not_contains "$RUN_OUTPUT" "/etc/" \
  "and the absolute path below it never reaches the root validator"

# ======================================= 21. the invocations SKILL.md prescribes
#
# Every section above calls the script as `python3 "$RETIRE"`. SKILL.md Step 3
# and Step 6.4 do not: they pipe the script out of the template ref into
# `python3 -`, so the *template's* copy runs against the project. Nothing tested
# that form, which is the only one a real /sync ever executes -- a script that
# works when imported from disk and fails when read from stdin would pass every
# assertion in this file.

printf '\n-- 21. the pipeline SKILL.md actually runs --\n'

# A project with the template as a `workflow` remote, exactly as Step 1 leaves
# it: the ref is fetched into the project, so `--from-ref` reads it from there.
P37="$FIXTURE_ROOT/p37"; T37="$FIXTURE_ROOT/t37"
make_project "$P37"; make_history_template "$T37"
# The template must carry the script itself: this pipeline runs the *template's*
# copy, not the one on disk here. That is the whole point -- a downstream /sync
# executes whatever the template ships, never the project's local version.
mkdir -p "$T37/.agents/skills/sync/scripts"
cp "$RETIRE" "$T37/.agents/skills/sync/scripts/sync-retire.py"
commit_all "$T37"
_f "$P37/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
_f "$P37/.agents/skills/ours/SKILL.md"   "this project's own"
commit_all "$P37"
rm -f "$P37/.claude/sync-keep"
git -C "$P37" remote add workflow "file://$T37"
git -C "$P37" fetch -q workflow main

# --- 21.1 the dry run, verbatim from Step 3 ---------------------------------

PIPED_OUT="$(cd "$P37" && set -o pipefail && \
  git show "workflow/main:.agents/skills/sync/scripts/sync-retire.py" \
  | python3 - --from-ref "workflow/main" 2>&1)"
PIPED_STATUS=$?
assert_eq "0" "$PIPED_STATUS" "the piped dry run exits zero"
assert_contains "$PIPED_OUT" "retire: .agents/skills/legacy/SKILL.md" \
  "and reaches the same conclusion as the on-disk invocation"
assert_contains "$PIPED_OUT" "dry-run (no changes written)" \
  "reading the program from stdin does not imply --apply"
assert_eq "present" "$([ -f "$P37/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "and the dry run deletes nothing"

# --- 21.2 pipefail is load-bearing, not decoration --------------------------
#
# SKILL.md claims a failed `git show` feeds python3 an empty program that exits
# 0, silently skipping the retirement gate. If that claim is wrong the warning
# is noise; if it is right, `set -o pipefail` is the only thing catching it.

EMPTY_OUT="$(cd "$P37" && git show "workflow/main:no/such/script.py" 2>/dev/null \
  | python3 - --from-ref "workflow/main" 2>&1)"
EMPTY_STATUS=$?
assert_eq "0" "$EMPTY_STATUS" \
  "without pipefail an empty program really does exit zero, as SKILL.md warns"
assert_eq "" "$EMPTY_OUT" "having printed nothing at all"

( cd "$P37" && set -o pipefail && git show "workflow/main:no/such/script.py" 2>/dev/null \
  | python3 - --from-ref "workflow/main" >/dev/null 2>&1 )
assert_eq "128" "$?" "with pipefail the failed git show is what the caller sees"

# --- 21.3 the --apply form, verbatim from Step 6.4 --------------------------

APPLY_OUT="$(cd "$P37" && set -o pipefail && \
  git show "workflow/main:.agents/skills/sync/scripts/sync-retire.py" \
  | python3 - --from-ref "workflow/main" --apply 2>&1)"
APPLY_STATUS=$?
assert_eq "0" "$APPLY_STATUS" "the piped --apply exits zero"
assert_eq "gone" "$([ -e "$P37/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "the retired path is deleted through the prescribed pipeline"
assert_eq "present" "$([ -f "$P37/.agents/skills/ours/SKILL.md" ] && echo present || echo gone)" \
  "and the project's own file survives it"
assert_contains "$APPLY_OUT" "wrote:  .claude/sync-keep.candidate" \
  "the candidate is written for the human to promote"

# ================================ 22. provenance is content, not a path name
#
# Bootstrap deletes without asking a human, so the thing it calls "proof" has to
# actually be proof. Path membership is not: `.claude/hooks/` is a syncable root
# and `pre-commit.sh` is a name a template and a project both reach for. These
# cases are the ones where deleting on the path alone destroys work that no
# `git checkout` can bring back.

printf '\n-- 22. bootstrap retires content, not names --\n'

P38="$FIXTURE_ROOT/p38"; T38="$FIXTURE_ROOT/t38"
make_project "$P38"; make_history_template "$T38"

# (a) a pristine synced copy — byte-identical to what the template shipped
_f "$P38/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
# (b) the same retired file, but this project customised it after syncing
_f "$P38/.claude/skills/legacy/SKILL.md" "shipped once, retired later

plus a paragraph this project added"
# (c) a path the template once used, with a file this project wrote itself.
# The root must keep another file, or emptying it makes the root *skipped* and
# nothing under it is examined at all.
_f "$T38/.claude/hooks/pre-push.sh" "another hook, still shipped"
commit_all "$T38"
git -C "$T38" rm -q .claude/hooks/session-start.sh 2>/dev/null
commit_all "$T38"
_f "$P38/.claude/hooks/session-start.sh" "this project's own hook, never synced"
commit_all "$P38"
rm -f "$P38/.claude/sync-keep"

# The template must have carried (b) at that path for the case to be real.
git -C "$T38" log --oneline >/dev/null 2>&1

run_retire --repo "$P38" --from-dir "$T38"
assert_eq "0" "$RUN_STATUS" "the mixed bootstrap produces a plan"
assert_contains "$RUN_OUTPUT" "retire: .agents/skills/legacy/SKILL.md" \
  "a byte-identical copy of retired template content is retired"
assert_not_contains "$RUN_OUTPUT" "retire: .claude/skills/legacy/SKILL.md" \
  "a copy this project edited after syncing is not"
assert_contains "$RUN_OUTPUT" "candidate: .claude/skills/legacy/SKILL.md" \
  "it goes to the human, because the edit is what makes it theirs"
assert_not_contains "$RUN_OUTPUT" "retire: .claude/hooks/session-start.sh" \
  "a file this project wrote at a path the template once used is never retired"
assert_contains "$RUN_OUTPUT" "candidate: .claude/hooks/session-start.sh" \
  "a shared filename is a collision, not provenance"

run_retire --repo "$P38" --from-dir "$T38" --apply
assert_eq "gone" "$([ -e "$P38/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "--apply removes only the pristine copy"
assert_file_contains "$P38/.claude/skills/legacy/SKILL.md" "this project added" \
  "the customised copy survives with its edit intact"
assert_file_contains "$P38/.claude/hooks/session-start.sh" "never synced" \
  "and so does the project's own file at the colliding path"

# --- 22.2 uncommitted work is not recoverable, so it is never deleted -------
#
# A tracked file whose *working tree* content was modified hashes to something
# no template commit produced. Comparing the index instead would delete it and
# `git checkout --` would restore only the committed version, silently losing
# the edit.

P39="$FIXTURE_ROOT/p39"; T39="$FIXTURE_ROOT/t39"
make_project "$P39"; make_history_template "$T39"
_f "$P39/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
commit_all "$P39"
rm -f "$P39/.claude/sync-keep"
printf 'shipped once, retired later\nlocal edit not yet committed\n' \
  > "$P39/.agents/skills/legacy/SKILL.md"

run_retire --repo "$P39" --from-dir "$T39" --apply
assert_eq "present" "$([ -f "$P39/.agents/skills/legacy/SKILL.md" ] && echo present || echo gone)" \
  "a file with uncommitted edits is never deleted"
assert_file_contains "$P39/.agents/skills/legacy/SKILL.md" "local edit not yet committed" \
  "and the edit git could not restore is still there"
assert_contains "$RUN_OUTPUT" "candidate: .agents/skills/legacy/SKILL.md" \
  "it is offered to the human instead"

# --- 22.3 a candidate write that fails after deleting still reports ---------
#
# `assert_candidate_writable` checks existence, which is the one failure it can
# see without trying. Every other one — unwritable dir, read-only mount, ENOSPC
# — is only discoverable by attempting the write, which is after the deletions.

if [ "$(id -u)" -eq 0 ]; then
  printf '  skip  22.3 needs an unprivileged user (root ignores permission bits)\n'
else
  P40="$FIXTURE_ROOT/p40"; T40="$FIXTURE_ROOT/t40"
  make_project "$P40"; make_history_template "$T40"
  _f "$P40/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
  _f "$P40/.agents/skills/ours/SKILL.md"   "this project's own"
  commit_all "$P40"
  rm -f "$P40/.claude/sync-keep"
  chmod 500 "$P40/.claude"                 # readable and enterable, not writable

  run_retire --repo "$P40" --from-dir "$T40" --apply
  chmod 700 "$P40/.claude" 2>/dev/null || true
  assert_eq "1" "$RUN_STATUS" "an unwritable candidate is a non-zero outcome"
  assert_contains "$RUN_OUTPUT" "deleted: .agents/skills/legacy/SKILL.md" \
    "and the file it destroyed is still reported by path"
  assert_contains "$RUN_OUTPUT" "FAILED: cannot write .claude/sync-keep.candidate" \
    "alongside what it could not write, named separately"
  assert_not_contains "$RUN_OUTPUT" "Traceback" \
    "the failure is reported, not raised through the accounting"
fi

# --- 22.4 the candidate is never written through a dangling symlink ---------

P41="$FIXTURE_ROOT/p41"; T41="$FIXTURE_ROOT/t41"
make_project "$P41"; make_history_template "$T41"
_f "$P41/.agents/skills/ours/SKILL.md" "this project's own"
commit_all "$P41"
rm -f "$P41/.claude/sync-keep"
# The target must NOT exist: `os.path.exists` follows the link and reports
# False for a dangling one, while `open(path, "w")` follows it and *creates*
# the target. A link to an existing file is refused by either check, so it
# would test nothing.
VICTIM41="$FIXTURE_ROOT/victim41-not-yet-there.txt"
rm -f "$VICTIM41"
ln -s "$VICTIM41" "$P41/.claude/sync-keep.candidate"

run_retire --repo "$P41" --from-dir "$T41" --apply
assert_eq "1" "$RUN_STATUS" "a dangling symlink at the candidate path is refused"
assert_eq "absent" "$([ -e "$VICTIM41" ] && echo created || echo absent)" \
  "and the tool never writes through it to create the target"
assert_contains "$RUN_OUTPUT" "sync-keep.candidate already exists" \
  "the refusal names the path it will not write"

finish
