#!/bin/bash
# tests/test-sync-retirement-defects.sh — behavioural contract for deterministic retirement in /sync
# (specs/sync-deterministic-retirement.md): second- and third-review defects, and bootstrap on what the template retired.
#
# One of the files split from the former tests/test-sync-retirement.sh at its
# section seams (specs/test-suite-aposd.md D4). Every piece declares the same
# artefact, so tests/affected.sh selects all of them on a change to sync-retire.py.
# Each section is a case: TEST_CASE='<glob>' bash tests/test-sync-retirement-defects.sh runs only the
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

# An empty repository with identity, for the scenarios whose template needs
# git history of its own: git_here <dir> makes <dir> a repository on `main`.
EMPTY_GIT="$(fixture_repo)"
git -C "$EMPTY_GIT" symbolic-ref HEAD refs/heads/main
git_here() {
  mkdir -p "$1"
  cp -R "$EMPTY_GIT/.git" "$1/.git"
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

# ====================== 17. second-review defects: exec, records, round-trips
if begin_case "17. second-review defects: exec, records, round-trips"; then
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

if [ "$(id -u)" -eq 0 ]; then
  printf '  skip  17.1 needs an unprivileged user (root ignores permission bits)\n'
else
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

  assert_contains "$output" "applied (1 deleted" \
    "a prune failure still reports the deletion that succeeded"
  assert_contains "$output" "1 not pruned" \
    "the unprunable directory is counted separately from a failed deletion"
  assert_contains "$output" "UNPRUNED: .agents/skills/orphan/sub" \
    "the directory that could not be pruned is named"
  assert_file_absent "$P17/.agents/skills/orphan/sub/SKILL.md" \
    "the file really was deleted, which is why the record must survive"
fi

# --- 17.2 an untrusted template checkout cannot choose what git executes ------
#
# `--from-dir` runs git inside a tree the project did not write. git honours
# that repo's own config, and core.fsmonitor names a command git runs on
# ls-files -- reached during the *dry run*, before any approval.

P18="$FIXTURE_ROOT/p18"; T18="$FIXTURE_ROOT/t18"
make_project "$P18"; make_template "$T18"
git_here "$T18"
commit_all "$T18"
write_keep "$P18"
git -C "$T18" config core.fsmonitor "touch $FIXTURE_ROOT/PWNED; false"
rm -f "$FIXTURE_ROOT/PWNED"

run_retire --repo "$P18" --from-dir "$T18"

assert_file_absent "$FIXTURE_ROOT/PWNED" \
  "a template's core.fsmonitor is not executed during the dry run"

run_retire --repo "$P18" --from-dir "$T18" --apply
assert_file_absent "$FIXTURE_ROOT/PWNED" \
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
  assert_exit 1 "a root segment of '$_bad' is refused"
  assert_contains "$output" "$_bad" "the refusal names the offending root"
  # Which guard rejected it matters. assert_roots_present also refuses these,
  # incidentally, because git normalises its output -- so asserting only "exit 1"
  # stays green with the traversal hole wide open. Pin the *designated* guard by
  # its own message, or a later change to the reachability check silently
  # reopens whole-repo deletion.
  assert_contains "$output" "is not a syncable root" \
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
"$TEST_PYTHON" - "$T21/.agents/skills/sync/SKILL.md" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
s = s.replace("## Next Section", "### Subsection\n.claude/smuggled/  → injected\n\n## Next Section")
io.open(p, "w", encoding="utf-8").write(s)
PY
_f "$P21/.claude/smuggled/x.md" "would be scanned if the block stayed open"
commit_all "$P21"; write_keep "$P21"

run_retire --repo "$P21" --from-dir "$T21"

assert_exit 0 "a sub-heading closes the block rather than erroring"
# If the block had stayed open, .claude/smuggled/ would be a scanned root and
# its project-only file would appear as a retire candidate.
assert_not_contains "$output" "smuggled" \
  "a root declared after a sub-heading is not read as a syncable root"
fi
end_case

# ============== 18. third-review defects: seams, records and round-trips
if begin_case "18. third-review defects: seams, records and round-trips"; then
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
assert_exit 0 "bootstrap writes a candidate"

# Promote the tool's own output verbatim: it must be readable by its own reader.
cp "$P22/.claude/sync-keep.candidate" "$P22/.claude/sync-keep"
run_retire --repo "$P22" --from-dir "$T22"
assert_exit 0 \
  "the candidate this tool wrote is accepted verbatim by its own reader"
assert_not_contains "$output" "use POSIX separators" \
  "a backslash path is commented out, not emitted as a rule that fails every later sync"
assert_not_contains "$output" "is outside every syncable root" \
  "and a newline does not split into a second, live rule at column 0"
# Structural form of the same claim: every non-blank candidate line is either a
# comment or a pattern the reader accepts. A continuation line is neither.
assert_eq "0" "$(grep -vE '^#|^[[:space:]]*$' "$P22/.claude/sync-keep.candidate" \
  | grep -cvE '^\.(agents|claude)/' || true)" \
  "no candidate line is a bare fragment of a path"
assert_contains "$output" "kept:   .agents/skills/mine/plain.md" \
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
assert_file_absent "$P23/.claude/hooks/old-hook.sh" \
  "the root's last file is retired"
assert_file_exists "$P23/.claude/hooks" \
  "but the syncable root itself survives being emptied"

# --- 18.3 a partial run reports what it destroyed, and names the right dir ----

if [ "$(id -u)" -eq 0 ]; then
  printf '  skip  18.3 needs an unprivileged user (root ignores permission bits)\n'
else
  P24="$FIXTURE_ROOT/p24"; T24="$FIXTURE_ROOT/t24"
  make_project "$P24"; make_template "$T24"
  _f "$P24/.agents/skills/gamma/deep/deeper/y.md" "retired; a parent will resist rmdir"
  commit_all "$P24"; write_keep "$P24"
  chmod a-w "$P24/.agents/skills/gamma"   # deeper prunes fine; gamma/deep cannot

  run_retire --repo "$P24" --from-dir "$T24" --apply
  chmod u+w "$P24/.agents/skills/gamma"

  assert_contains "$output" "deleted: .agents/skills/gamma/deep/deeper/y.md" \
    "a partial run prints the record of what it destroyed, not just a count"
  # Pruning walks upward, so the directory it STARTED at is usually removed fine.
  # Reporting that one names a path that no longer exists.
  assert_contains "$output" "UNPRUNED: .agents/skills/gamma/deep " \
    "the directory named is the one that actually failed"
  assert_file_exists "$P24/.agents/skills/gamma/deep" \
    "and that directory is genuinely still on disk"
fi

# --- 18.4 sync-keep states: absent, empty, and unusable are three things ------

P25="$FIXTURE_ROOT/p25"; T25="$FIXTURE_ROOT/t25"
make_project "$P25"; make_template "$T25"
_f "$P25/.agents/skills/mine/SKILL.md" "project-only"
commit_all "$P25"

rm -f "$P25/.claude/sync-keep"
ln -s /nonexistent-target "$P25/.claude/sync-keep"
run_retire --repo "$P25" --from-dir "$T25" --apply
assert_exit 1 "a sync-keep that is not a regular file is an error"
assert_contains "$output" "not a regular file" "and says so"
assert_file_absent "$P25/.claude/sync-keep.candidate" \
  "it is not mistaken for bootstrap, so no candidate is written over it"

rm -f "$P25/.claude/sync-keep"
printf '.agents/skills/x\xff\xfe.md\n' > "$P25/.claude/sync-keep"
run_retire --repo "$P25" --from-dir "$T25" --apply
assert_exit 1 "an undecodable sync-keep exits 1"
assert_contains "$output" "sync-retire: cannot read" \
  "reported on the tool's own channel, not as a traceback"
assert_not_contains "$output" "Traceback" "specifically, not as a traceback"

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
assert_exit 0 "a .git file is treated as a plain directory, not a repo"
assert_contains "$output" "retire: .agents/skills/beta/SKILL.md" \
  "the inventory comes from the directory on disk, not from the repo its .git file names"

# --- 18.6 a template checkout without the doc block is an error --------------

P27="$FIXTURE_ROOT/p27"; T27="$FIXTURE_ROOT/t27"
make_project "$P27"; make_template "$T27"; write_keep "$P27"
rm -f "$T27/.agents/skills/sync/SKILL.md"

run_retire --repo "$P27" --from-dir "$T27" --apply
assert_exit 1 "a template checkout with no SKILL.md exits 1"
assert_contains "$output" "template checkout has no" "and names what is missing"

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
  "$TEST_PYTHON" "$RETIRE" --repo "$P28" --from-dir "$T28" >/dev/null 2>&1
# NOTE: this assertion cannot distinguish the two guards. `-c core.fsmonitor=`
# outranks global config as well as repo config, so removing the
# GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL suppression leaves this green. The env
# hardening is defence-in-depth behind the `-c` pin, not an independently
# observable behaviour -- recorded here as a smoke test, not as proof of it.
assert_file_absent "$FIXTURE_ROOT/PWNED_GLOBAL" \
  "git config from outside the repo does not name a command this tool executes"
fi
end_case

# ================= 19. bootstrap still removes what the template retired
if begin_case "19. bootstrap still removes what the template retired"; then
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
git_here "$T29"
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
assert_exit 0 "bootstrap with template history succeeds"
assert_contains "$output" "bootstrap: required" "it is still bootstrap"
assert_contains "$output" "retire: .agents/skills/legacy/SKILL.md (was template content" \
  "a path the template retired upstream is retired without a human classifying it"
assert_contains "$output" "candidate: .agents/skills/ours/SKILL.md" \
  "while a path the template never carried stays a candidate for the human"
assert_not_contains "$output" "retire: .agents/skills/ours/SKILL.md" \
  "project-specific paths are never retired on provenance alone"

run_retire --repo "$P29" --from-dir "$T29" --apply
assert_file_absent "$P29/.agents/skills/legacy/SKILL.md" \
  "--apply removes the retired-upstream path in bootstrap"
assert_file_exists "$P29/.agents/skills/ours/SKILL.md" \
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
assert_exit 0 "a shallow template still produces a plan"
assert_contains "$output" "provenance: unavailable" \
  "and says provenance could not be established"
assert_file_exists "$P30/.agents/skills/legacy/SKILL.md" \
  "retiring nothing rather than guessing"
fi
end_case

finish
