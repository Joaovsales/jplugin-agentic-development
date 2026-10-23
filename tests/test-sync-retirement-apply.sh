#!/bin/bash
# tests/test-sync-retirement-apply.sh — behavioural contract for deterministic retirement in /sync
# (specs/sync-deterministic-retirement.md): --apply, the allowlist, bootstrap, idempotency, branch independence and the documentation.
#
# One of the files split from the former tests/test-sync-retirement.sh at its
# section seams (specs/test-suite-aposd.md D4). Every piece declares the same
# artefact, so tests/affected.sh selects all of them on a change to sync-retire.py.
# Each section is a case: TEST_CASE='<glob>' bash tests/test-sync-retirement-apply.sh runs only the
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

# ================================================================= 5. --apply
if begin_case "5. --apply"; then
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
assert_exit 0 "--apply succeeds"

# The same full list is printed before deleting, so the record of what was
# destroyed survives in the transcript.
assert_contains "$output" "retire: .agents/skills/retired/SKILL.md" "--apply prints the list it deletes"
assert_contains "$output" "retire: .agents/skills/retired/scripts/helper.sh" "--apply lists nested paths"
assert_contains "$output" "retire: .claude/hooks/retired-hook.sh" "--apply lists every root's paths"
assert_contains "$output" "mode:   applied" "--apply reports itself as applied, not dry-run"

assert_file_absent "$P5/.agents/skills/retired/SKILL.md" \
  "--apply deleted the retired skill file"
assert_file_absent "$P5/.claude/hooks/retired-hook.sh" \
  "--apply deleted the retired hook"

# Directories emptied by the deletions are pruned, so a sync does not leave a
# tree full of empty husks that later reads as "the skill is still installed".
assert_file_absent "$P5/.agents/skills/retired" \
  "--apply pruned the directory its deletions emptied"
assert_file_absent "$P5/.agents/skills/retired/scripts" \
  "--apply pruned nested emptied directories"

# The syncable root itself survives even when everything under it went, because
# an absent root and an empty one are different states to every other reader.
assert_file_exists "$P5/.agents/skills" \
  "--apply keeps the syncable root directory itself"

# Nothing outside the retirement set is touched.
assert_file_exists "$P5/.agents/skills/keepme/SKILL.md" \
  "--apply left the allowlisted path alone"
assert_file_exists "$P5/.agents/skills/build/SKILL.md" \
  "--apply left a path the template still ships alone"
assert_file_exists "$P5/CLAUDE.md" \
  "--apply left the file roots alone"
assert_file_exists "$P5/.claude/sync-keep" \
  "--apply left the allowlist itself alone"

# Untracked files under a root were never synced in, so they are not this
# program's to delete — the project inventory is the tracked set.
_f "$P5/.claude/hooks/scratch.sh" "untracked local scratch"
run_retire --repo "$P5" --from-dir "$T5" --apply
assert_file_exists "$P5/.claude/hooks/scratch.sh" \
  "--apply never deletes an untracked file"
assert_not_contains "$output" "scratch.sh" "an untracked file is not even reported"

# A second --apply before the deletions are staged must not re-list them. The
# project inventory reads the git *index*, which still names a file this script
# deleted a moment ago; an unfiltered read would compute it as project-only
# again and fail on the missing file, turning a no-op re-run into a crash.
run_retire --repo "$P5" --from-dir "$T5" --apply
assert_exit 0 "a second --apply with the deletions unstaged succeeds"
assert_not_contains "$output" "retire: .agents/skills/retired/SKILL.md" \
  "an already-deleted path is not re-listed from the index"
assert_not_contains "$output" "deletion failed" "the re-run does not fail on a missing file"
fi
end_case

# =============================================================== 6. allowlist
if begin_case "6. allowlist"; then
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
assert_exit 0 "allowlisted run succeeds"
assert_contains "$output" "kept:   .agents/skills/mine/SKILL.md (matched .agents/skills/mine/**)" \
  "a kept path names the pattern that matched it"
assert_contains "$output" "kept:   .agents/skills/mine/scripts/deep.sh (matched .agents/skills/mine/**)" \
  "** matches across directory separators"
assert_contains "$output" "kept:   .claude/hooks/one.sh (matched .claude/hooks/*.sh)" \
  "* matches within a single path segment"
assert_contains "$output" "retire: .agents/agents/unprotected.md" \
  "a path no pattern matches is still retired"

# `*` must not cross a separator: a pattern written for one directory level
# must not silently protect everything beneath it.
write_keep "$P6" ".agents/skills/*"
run_retire --repo "$P6" --from-dir "$T6"
assert_contains "$output" "retire: .agents/skills/mine/SKILL.md" \
  "* does not cross a directory separator"

# `?` is exactly one character, also non-crossing.
write_keep "$P6" ".claude/hooks/???.sh"
run_retire --repo "$P6" --from-dir "$T6"
assert_contains "$output" "kept:   .claude/hooks/one.sh (matched .claude/hooks/???.sh)" \
  "? matches exactly one character"
assert_contains "$output" "kept:   .claude/hooks/two.sh (matched .claude/hooks/???.sh)" \
  "? applies to every path of the right shape"
# Non-crossing, the same property `*` is pinned for above: widening `?` to `.`
# would silently widen every allowlist entry containing one.
write_keep "$P6" ".agents/skills/mine?SKILL.md"
run_retire --repo "$P6" --from-dir "$T6"
assert_contains "$output" "retire: .agents/skills/mine/SKILL.md" \
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
assert_exit 0 "an empty sync-keep is a valid recorded intent"
assert_not_contains "$output" "bootstrap" "an empty sync-keep is not bootstrap"
assert_file_absent "$P6E/.agents/skills/retired/SKILL.md" \
  "an empty sync-keep permits deletion"
fi
end_case

# =============================================================== 7. bootstrap
if begin_case "7. bootstrap"; then
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
assert_exit 0 "bootstrap is a normal outcome, not a failure"
assert_contains "$output" "bootstrap: required" "bootstrap is announced"
assert_contains "$output" ".claude/sync-keep" "the report names the file to create"
assert_contains "$output" "candidate: .agents/skills/mine/SKILL.md" "every project-only path is a candidate"
assert_contains "$output" "candidate: .claude/hooks/retired-hook.sh" "candidates span every root"
assert_not_contains "$output" "retire:" "bootstrap proposes no retirements"

run_retire --repo "$P7" --from-dir "$T7" --apply
assert_exit 0 "bootstrap under --apply still succeeds"
assert_file_exists "$P7/.agents/skills/mine/SKILL.md" \
  "bootstrap --apply deletes nothing"
assert_file_exists "$P7/.claude/hooks/retired-hook.sh" \
  "bootstrap --apply deletes nothing, not even an upstream-retired path"

# The candidate file is written; the real allowlist is not.
assert_file_exists "$P7/.claude/sync-keep.candidate" \
  "bootstrap --apply writes the candidate allowlist"
assert_file_absent "$P7/.claude/sync-keep" \
  "bootstrap --apply never writes .claude/sync-keep itself"
assert_file_contains "$P7/.claude/sync-keep.candidate" ".agents/skills/mine/SKILL.md" \
  "the candidate lists the project-only paths"

# The candidate is a working allowlist once promoted: reviewed, renamed, and
# the next run keeps exactly what it names.
cp "$P7/.claude/sync-keep.candidate" "$P7/.claude/sync-keep"
run_retire --repo "$P7" --from-dir "$T7"
assert_not_contains "$output" "bootstrap" "promoting the candidate leaves bootstrap"
assert_contains "$output" "retire: (none)" \
  "a promoted candidate keeps every path it named"

# A dry run must not write the candidate either — a dry run writes nothing.
P7D="$FIXTURE_ROOT/p7d"; T7D="$FIXTURE_ROOT/t7d"
make_project "$P7D"; make_template "$T7D"
_f "$P7D/.agents/skills/mine/SKILL.md" "project specific"; commit_all "$P7D"
run_retire --repo "$P7D" --from-dir "$T7D"
assert_file_absent "$P7D/.claude/sync-keep.candidate" \
  "a dry run writes no candidate file"
fi
end_case

# ============================================================= 8. idempotency
if begin_case "8. idempotency"; then
#
# The headline claim: running /sync twice against an unchanged template leaves
# a byte-identical tree, and the second run reports nothing to do. This is the
# property that was false before — two runs against one template commit could
# produce different trees because a model re-derived the answer each time.

printf '\n-- 8. two runs converge --\n'

# Hash every file under the syncable roots, path and content, so a difference
# in either shows up. .git is excluded: index and log churn are not tree state.
tree_hash() {
  # One sha256sum over every file (paths relative to the root, sorted) instead
  # of a process per file; only equality between two calls matters.
  ( cd "$1" && find . -name .git -prune -o -type f -print0 | sort -z | xargs -0 -r sha256sum ) \
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
assert_exit 0 "first --apply succeeds"
FIRST_COUNT="$(printf '%s\n' "$output" | grep -c '^  retire:')"
assert_eq "3" "$FIRST_COUNT" "first run retires the three upstream-retired paths"
HASH_AFTER_FIRST="$(tree_hash "$P8")"

run_retire --repo "$P8" --from-dir "$T8" --apply
assert_exit 0 "second --apply succeeds"
assert_contains "$output" "retire: (none)" "the second run reports zero retirements"
assert_eq "$HASH_AFTER_FIRST" "$(tree_hash "$P8")" \
  "the second run leaves a byte-identical tree"

# And once the deletions are committed, which is what a real /sync ends with.
commit_all "$P8"
HASH_COMMITTED="$(tree_hash "$P8")"
run_retire --repo "$P8" --from-dir "$T8" --apply
assert_contains "$output" "retire: (none)" "a third run after committing still reports zero"
assert_eq "$HASH_COMMITTED" "$(tree_hash "$P8")" "a third run leaves the tree untouched"

# Non-vacuity: the hash must actually respond to a change, or every comparison
# above is comparing two constants.
_f "$P8/.agents/skills/retired-a/SKILL.md" "resurrected"
assert_true "tree_hash detects a change (guards against a constant-hash pass)" -- \
  test "$HASH_COMMITTED" != "$(tree_hash "$P8")"
fi
end_case

# ====================================================== 9. branch independence
if begin_case "9. branch independence"; then
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
    -type f 2>/dev/null | sed "s|^$1/||" | sort
}

# The allowlist is the project's, not the branch's: written once, honoured from
# either branch.
write_keep "$P9" ".agents/agents/shared-project-agent.md"

run_retire --repo "$P9" --from-dir "$T9" --apply
assert_exit 0 "sync from the feature branch succeeds"
FEATURE_PATHS="$(harness_paths "$P9")"

git -C "$P9" checkout -q main
run_retire --repo "$P9" --from-dir "$T9" --apply
assert_exit 0 "sync from main succeeds"
MAIN_PATHS="$(harness_paths "$P9")"

assert_contains "$MAIN_PATHS" ".agents/agents/shared-project-agent.md" \
  "the allowlisted project path survives on both branches (non-vacuity)"
assert_eq "$FEATURE_PATHS" "$MAIN_PATHS" \
  "both branches converge on the same set of harness paths"
assert_not_contains "$MAIN_PATHS" "stale-on-main" \
  "a skill the template dropped is retired even when only this branch had it"
assert_not_contains "$FEATURE_PATHS" "stale-on-feature" \
  "the same holds for the other branch's stale skill"
fi
end_case

# ========================================================== 10. documentation
if begin_case "10. documentation"; then
#
# The mechanism is only reachable if /sync runs it. These assertions pin the
# procedure to the script and pin the one property that makes the allowlist
# safe: .claude/sync-keep is never synced, so a template update cannot
# overwrite a project's record of its own intent.
#
# Asserted against the canonical tree, which Claude Code loads through the
# jplugin plugin and Pi and Codex read directly.

printf '\n-- 10. SKILL.md documents the retirement pass --\n'

for tree in .agents; do
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
fi
end_case

finish
