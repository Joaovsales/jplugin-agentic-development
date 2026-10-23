#!/bin/bash
# tests/test-sync-retirement-records.sh — behavioural contract for deterministic retirement in /sync
# (specs/sync-deterministic-retirement.md): wrap-up review regressions: record loss, the prescribed invocations and provenance.
#
# One of the files split from the former tests/test-sync-retirement.sh at its
# section seams (specs/test-suite-aposd.md D4). Every piece declares the same
# artefact, so tests/affected.sh selects all of them on a change to sync-retire.py.
# Each section is a case: TEST_CASE='<glob>' bash tests/test-sync-retirement-records.sh runs only the
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

# A template repository that once shipped `legacy` and later retired it. Shared
# by 20.1-20.3, which all need real history to read.
make_history_template() {
  _dir="$1"
  mkdir -p "$_dir/.agents/skills/sync" "$_dir/.agents/skills/build" "$_dir/.agents/agents" "$_dir/.claude/skills/build" "$_dir/.claude/hooks" "$_dir/.agents/skills/legacy"
  git_here "$_dir"
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

# =========================================== 20. wrap-up review regressions
if begin_case "20. wrap-up review regressions"; then
#
# Each case below is a defect the review passes found in the code this session
# wrote, reproduced before it was fixed. They share one shape: the program had
# already destroyed something, and then lost the record of having done it. The
# record is the only thing standing between an operator and `git status`
# archaeology, so every path that deletes is pinned here separately -- fixing
# this per call site is exactly what let it recur four times.

printf '\n-- 20. record-loss and provenance regressions --\n'


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
assert_exit 1 "bootstrap --apply refuses an existing candidate"
assert_contains "$output" "sync-keep.candidate already exists" \
  "and says which file it will not overwrite"
assert_file_exists "$P31/.agents/skills/legacy/SKILL.md" \
  "the refusal happens before any deletion, not after it"
assert_not_contains "$output" "deleted:" \
  "so there is no destruction to report"
assert_file_contains "$P31/.claude/sync-keep.candidate" "not yet promoted" \
  "and the human's file is left exactly as they left it"

# Promoting the candidate unblocks the same run: the guard is a precondition,
# not a permanent refusal. Without this the assertion above would also pass
# against a program that had simply stopped retiring in bootstrap.
rm -f "$P31/.claude/sync-keep.candidate"
run_retire --repo "$P31" --from-dir "$T31" --apply
assert_exit 0 "with no stale candidate the same run succeeds"
assert_contains "$output" "retire: .agents/skills/legacy/SKILL.md" \
  "and the same run names the path it is about to destroy"
assert_contains "$output" "applied (1 deleted)" \
  "and reports having destroyed it"
assert_file_absent "$P31/.agents/skills/legacy/SKILL.md" \
  "so the guard was a precondition, not a permanent refusal to retire"

# --- 20.2 every git failure is not "the clone was shallow" ------------------
#
# The probe swallowed its exception and reported one hardcoded cause, so a
# missing ref and an unreadable object both told the operator to deepen a clone
# that was already complete. The reason must be the one git gave.

P32="$FIXTURE_ROOT/p32"; T32="$FIXTURE_ROOT/t32"
make_project "$P32"
git_here "$T32"
make_template "$T32"
commit_all "$T32"                          # one commit: no history to read
_f "$P32/.agents/skills/legacy/SKILL.md" "unclassifiable without provenance"
commit_all "$P32"
rm -f "$P32/.claude/sync-keep"

run_retire --repo "$P32" --from-dir "$T32"
assert_not_contains "$output" "provenance: unavailable" \
  "one commit is a complete history, not an unreadable one"
assert_contains "$output" "candidate: .agents/skills/legacy/SKILL.md" \
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
assert_exit 0 "a shallow-but-not-single-commit template produces a plan"
assert_contains "$output" "provenance: unavailable" \
  "a clone truncated below the retirement is detected at any depth"
assert_contains "$output" "truncated history" \
  "and named as truncation rather than as a missing ref"
assert_not_contains "$output" "retire: .agents/skills/legacy/SKILL.md" \
  "so it never concludes a retirement from history it cannot see"

# The other way this probe fails is a git error, and it used to be reported with
# the same shallow-clone wording -- telling the operator to deepen a clone whose
# depth was never the problem. A template repo with a staged but uncommitted
# tree reaches it: the doc block and the index both read fine, and only the
# revision does not exist.

P32B="$FIXTURE_ROOT/p32b"; T32B="$FIXTURE_ROOT/t32b"
make_project "$P32B"
make_template "$T32B"
git_here "$T32B"
git -C "$T32B" add -A                      # staged, never committed: no HEAD
_f "$P32B/.agents/skills/legacy/SKILL.md" "unclassifiable without provenance"
commit_all "$P32B"
rm -f "$P32B/.claude/sync-keep"

run_retire --repo "$P32B" --from-dir "$T32B"
assert_exit 0 "an unreadable revision still produces a plan"
assert_contains "$output" "unknown revision" \
  "and the reason is the one git gave, carried out of the probe"
assert_not_contains "$output" "single commit" \
  "not the shallow-clone wording every failure used to borrow"
# git's fatals run to three lines with a usage hint. The report is read one
# item per line, so the reason has to arrive as one item.
assert_eq "0" \
  "$(printf '%s\n' "$output" | tail -n +2 | grep -cv '^  ' || true)" \
  "and it stays a single report line, however many lines git used to say it"
assert_contains "$output" "candidate: .agents/skills/legacy/SKILL.md" \
  "unknown provenance holds the path for a human rather than deleting it"
assert_not_contains "$output" "a full clone" \
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
assert_exit 0 "a shallow project reads the template ref's history"
assert_not_contains "$output" "provenance: unavailable" \
  "the project's own clone depth does not suppress the template's provenance"
assert_contains "$output" "retire: .agents/skills/legacy/SKILL.md" \
  "so retirement still happens in the mode SKILL.md prescribes"
assert_contains "$output" "candidate: .agents/skills/ours/SKILL.md" \
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
  assert_exit 1 "an unprunable directory is a non-zero outcome"
  assert_contains "$output" "deleted: .agents/skills/gone/SKILL.md" \
    "but the file it destroyed is still reported by path"
  assert_contains "$output" "UNPRUNED: .agents/skills/gone" \
    "and the directory it could not remove is named separately"
  assert_contains "$output" "mode:   applied" \
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
assert_exit 0 \
  "a sync-keep entry under an emptied root does not abort the run"
assert_contains "$output" "skipped: .claude/hooks/" \
  "the emptied root is skipped and said so"
assert_contains "$output" "retire: .agents/skills/gone/SKILL.md" \
  "and retirement under every other root still proceeds"

assert_contains "$output" "dormant: .claude/hooks/local.sh" \
  "the pattern is reported as dormant, not as one that matched nothing"
assert_not_contains "$output" "unmatched: .claude/hooks/local.sh" \
  "because unmatched reads as an invitation to delete the only protection"

run_retire --repo "$P35" --from-dir "$T35" --apply
assert_file_exists "$P35/.claude/hooks/local.sh" \
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
"$TEST_PYTHON" - "$T36/.agents/skills/sync/SKILL.md" <<'EOF_PY'
import io, sys
path = sys.argv[1]
text = io.open(path, encoding="utf-8").read()
io.open(path, "w", encoding="utf-8").write(
    text.replace("## Next Section", "####### Deep heading\n\n/etc/ → not a root\n\n## Next Section")
)
EOF_PY

run_retire --repo "$P36" --from-dir "$T36"
assert_exit 0 "a 7-hash heading after the fence is not a parse error"
assert_contains "$output" "roots: 4" \
  "it closes the block, so the line beneath it is not read as a root"
assert_not_contains "$output" "/etc/" \
  "and the absolute path below it never reaches the root validator"
fi
end_case

# ======================================= 21. the invocations SKILL.md prescribes
if begin_case "21. the invocations SKILL.md prescribes"; then
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
  | "$TEST_PYTHON" - --from-ref "workflow/main" 2>&1)"
PIPED_STATUS=$?
assert_eq "0" "$PIPED_STATUS" "the piped dry run exits zero"
assert_contains "$PIPED_OUT" "retire: .agents/skills/legacy/SKILL.md" \
  "and reaches the same conclusion as the on-disk invocation"
assert_contains "$PIPED_OUT" "dry-run (no changes written)" \
  "reading the program from stdin does not imply --apply"
assert_file_exists "$P37/.agents/skills/legacy/SKILL.md" \
  "and the dry run deletes nothing"

# --- 21.2 pipefail is load-bearing, not decoration --------------------------
#
# SKILL.md claims a failed `git show` feeds python3 an empty program that exits
# 0, silently skipping the retirement gate. If that claim is wrong the warning
# is noise; if it is right, `set -o pipefail` is the only thing catching it.

EMPTY_OUT="$(cd "$P37" && git show "workflow/main:no/such/script.py" 2>/dev/null \
  | "$TEST_PYTHON" - --from-ref "workflow/main" 2>&1)"
EMPTY_STATUS=$?
assert_eq "0" "$EMPTY_STATUS" \
  "without pipefail an empty program really does exit zero, as SKILL.md warns"
assert_eq "" "$EMPTY_OUT" "having printed nothing at all"

( cd "$P37" && set -o pipefail && git show "workflow/main:no/such/script.py" 2>/dev/null \
  | "$TEST_PYTHON" - --from-ref "workflow/main" >/dev/null 2>&1 )
assert_eq "128" "$?" "with pipefail the failed git show is what the caller sees"

# --- 21.3 the --apply form, verbatim from Step 6.4 --------------------------

APPLY_OUT="$(cd "$P37" && set -o pipefail && \
  git show "workflow/main:.agents/skills/sync/scripts/sync-retire.py" \
  | "$TEST_PYTHON" - --from-ref "workflow/main" --apply 2>&1)"
APPLY_STATUS=$?
assert_eq "0" "$APPLY_STATUS" "the piped --apply exits zero"
assert_file_absent "$P37/.agents/skills/legacy/SKILL.md" \
  "the retired path is deleted through the prescribed pipeline"
assert_file_exists "$P37/.agents/skills/ours/SKILL.md" \
  "and the project's own file survives it"
assert_contains "$APPLY_OUT" "wrote:  .claude/sync-keep.candidate" \
  "the candidate is written for the human to promote"
fi
end_case

# ================================ 22. provenance is content, not a path name
if begin_case "22. provenance is content, not a path name"; then
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
assert_exit 0 "the mixed bootstrap produces a plan"
assert_contains "$output" "retire: .agents/skills/legacy/SKILL.md" \
  "a byte-identical copy of retired template content is retired"
assert_not_contains "$output" "retire: .claude/skills/legacy/SKILL.md" \
  "a copy this project edited after syncing is not"
assert_contains "$output" "candidate: .claude/skills/legacy/SKILL.md" \
  "it goes to the human, because the edit is what makes it theirs"
assert_not_contains "$output" "retire: .claude/hooks/session-start.sh" \
  "a file this project wrote at a path the template once used is never retired"
assert_contains "$output" "candidate: .claude/hooks/session-start.sh" \
  "a shared filename is a collision, not provenance"

run_retire --repo "$P38" --from-dir "$T38" --apply
assert_file_absent "$P38/.agents/skills/legacy/SKILL.md" \
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
assert_file_exists "$P39/.agents/skills/legacy/SKILL.md" \
  "a file with uncommitted edits is never deleted"
assert_file_contains "$P39/.agents/skills/legacy/SKILL.md" "local edit not yet committed" \
  "and the edit git could not restore is still there"
assert_contains "$output" "candidate: .agents/skills/legacy/SKILL.md" \
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
  assert_exit 1 "an unwritable candidate is a non-zero outcome"
  assert_contains "$output" "deleted: .agents/skills/legacy/SKILL.md" \
    "and the file it destroyed is still reported by path"
  assert_contains "$output" "FAILED: cannot write .claude/sync-keep.candidate" \
    "alongside what it could not write, named separately"
  assert_not_contains "$output" "Traceback" \
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
assert_exit 1 "a dangling symlink at the candidate path is refused"
assert_file_absent "$VICTIM41" \
  "and the tool never writes through it to create the target"
assert_contains "$output" "sync-keep.candidate already exists" \
  "the refusal names the path it will not write"
fi
end_case

finish
