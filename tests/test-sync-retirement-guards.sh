#!/bin/bash
# tests/test-sync-retirement-guards.sh — behavioural contract for deterministic retirement in /sync
# (specs/sync-deterministic-retirement.md): review-driven contracts and the guards that keep a hostile or empty template from deleting.
#
# One of the files split from the former tests/test-sync-retirement.sh at its
# section seams (specs/test-suite-aposd.md D4). Every piece declares the same
# artefact, so tests/affected.sh selects all of them on a change to sync-retire.py.
# Each section is a case: TEST_CASE='<glob>' bash tests/test-sync-retirement-guards.sh runs only the
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

# ================================================= 11. review-driven contracts
if begin_case "11. review-driven contracts"; then
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
assert_exit 0 "F1: first bootstrap --apply writes the candidate"
printf '%s\n' "# reviewed by a human" ".agents/skills/mine/SKILL.md" > "$P11/.claude/sync-keep.candidate"
run_retire --repo "$P11" --from-dir "$T11" --apply
assert_exit 1 "F1: a second bootstrap --apply refuses rather than overwriting"
assert_contains "$output" "sync-keep.candidate" "F1: the refusal names the file"
assert_file_contains "$P11/.claude/sync-keep.candidate" "# reviewed by a human" \
  "F1: the human's edits survive the second run"

# F7 — the dry run is what SKILL.md Step 3 shows during the change summary, so
# it is where an unconfigured project has to be told what to do. It named the
# file and stopped, and carried no mode line at all.
rm -f "$P11/.claude/sync-keep.candidate"
run_retire --repo "$P11" --from-dir "$T11"
assert_contains "$output" "next:" "F7: the bootstrap dry run says what to do next"
assert_contains "$output" "--apply" "F7: the instruction names the flag that writes the candidate"
assert_contains "$output" "mode:   dry-run" "F7: bootstrap reports the same mode line as every other path"

# F2 — the mode line was printed before any deletion ran, so a mid-loop failure
# left stdout asserting N files were deleted when fewer were. For a tool whose
# report is the record of what was destroyed, the record must follow the act.
P11B="$FIXTURE_ROOT/p11b"; T11B="$FIXTURE_ROOT/t11b"
make_project "$P11B"; make_template "$T11B"
_f "$P11B/.agents/skills/gone-a/SKILL.md" "retired"; _f "$P11B/.agents/skills/gone-b/SKILL.md" "retired"
commit_all "$P11B"; write_keep "$P11B"
run_retire --repo "$P11B" --from-dir "$T11B" --apply
assert_contains "$output" "mode:   applied (2 deleted)" "F2: the count reports what was actually removed"
# The list still precedes the act; only the outcome line follows it.
assert_eq "0" "$(printf '%s\n' "$output" | grep -n 'mode:' | cut -d: -f1 | \
  { read -r m; printf '%s\n' "$output" | grep -n 'retire:' | cut -d: -f1 | \
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
assert_exit 0 "F3: a pattern whose glob reaches into a root is accepted"
assert_contains "$output" "kept:   .claude/hooks/mine.sh (matched .claude/**)" \
  "F3: and it actually protects the path it reaches"
# The check still rejects a pattern that reaches no root at all.
write_keep "$P11C" "tasks/**"
run_retire --repo "$P11C" --from-dir "$T11C"
assert_exit 1 "F3: a pattern reaching no root is still rejected"

# F5 — the project inventory is the tracked set and --from-ref is the committed
# tree, but --from-dir walked the filesystem, so gitignored residue counted as
# template content. assert_roots_present could then be satisfied by a root that
# the committed tree does not contain.
P11D="$FIXTURE_ROOT/p11d"; T11D="$FIXTURE_ROOT/t11d"
make_project "$P11D"; write_keep "$P11D"
make_template "$T11D"
git_here "$T11D"
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
assert_exit 0 "F5: a git template checkout is read the same way as a ref"
assert_not_contains "$output" ".pyc" \
  "F5: gitignored residue is not template content, and is not project content either"

# F6 — a trailing slash in a Markdown table decides whether a root is scanned by
# a destructive tool, and two hand-written parsers of that block must agree on
# which entries are directories.
AWK_DIRS="$(awk '/^## Syncable Paths/ { b = 1; next }
                 b && /^## / { exit }
                 b && /→/ { print $1 }' .agents/skills/sync/SKILL.md | grep '/$' | sort)"
PY_DIRS="$("$TEST_PYTHON" - <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sr", ".agents/skills/sync/scripts/sync-retire.py")
m = importlib.util.module_from_spec(spec); sys.modules["sr"] = m; spec.loader.exec_module(m)
live, retired = m.parse_syncable_roots(open(".agents/skills/sync/SKILL.md").read(), "SKILL.md")
print("\n".join(sorted(live + retired)))
PYX
)"
assert_contains "$AWK_DIRS" ".agents/skills/" "F6: the awk extractor found the block (non-vacuity)"
assert_eq "$AWK_DIRS" "$PY_DIRS" \
  "F6: the script's root list equals the drift test's directory subset"
assert_prose_contains ".agents/skills/sync/SKILL.md" "machine-parsed" \
  "F6: the block warns an editor that it is parsed by a script"
fi
end_case

# ========================================= 12. hostile template cannot escape
if begin_case "12. hostile template cannot escape"; then
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
assert_exit 1 "a traversing root the template cannot vouch for is refused"
assert_contains "$output" "../victim-outside/" "the refusal names the traversing root"

# Layer 2 — even when the template DOES carry files under that root, so a
# contents check would be satisfied, the root is still refused on its shape.
mkdir -p "$FIXTURE_ROOT/victim-outside"; printf 'decoy\n' > "$T12/../victim-outside/decoy.txt"
run_retire --repo "$P12" --from-dir "$T12" --apply
assert_exit 1 "a traversing root backed by real template files is still refused"
assert_file_contains "$OUTSIDE/secret.txt" "precious" \
  "a file outside the project is never touched"

# An absolute root is refused the same way, and deletes nothing.
P12A="$FIXTURE_ROOT/p12a"; T12A="$FIXTURE_ROOT/t12a"
make_project "$P12A"; write_keep "$P12A"
make_template "$T12A" "/etc/                → absolute"
run_retire --repo "$P12A" --from-dir "$T12A" --apply
assert_exit 1 "an absolute root in the doc block is refused"
assert_file_exists "$P12A/.agents/skills/build/SKILL.md" \
  "the refused run deleted nothing"
fi
end_case

# ================================== 13. the template cannot widen the blast radius
if begin_case "13. the template cannot widen the blast radius"; then
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
assert_exit 1 "a root outside the harness directories is refused"
assert_contains "$output" "src/" "the refusal names the offending root"
assert_file_contains "$P13/src/app.py" "production code" "project source is untouched"

# `.claude/` itself — one segment — would sweep in the never-sync files,
# including the allowlist this whole mechanism depends on.
P13B="$FIXTURE_ROOT/p13b"; T13B="$FIXTURE_ROOT/t13b"
make_project "$P13B"; _f "$P13B/.claude/project.md" "project config"; commit_all "$P13B"
write_keep "$P13B"
make_template "$T13B" ".claude/              → hostile"
_f "$T13B/.claude/decoy.md" "decoy"
run_retire --repo "$P13B" --from-dir "$T13B" --apply
assert_exit 1 "a bare top-level harness directory is refused as a root"
assert_file_contains "$P13B/.claude/project.md" "project config" \
  "the project's never-sync config is untouched"
assert_file_exists "$P13B/.claude/sync-keep" \
  "the allowlist itself survives"

# The nine real roots (seven live, two retired — .claude/skills/ and .claude/hooks/) still parse — the constraint must not break the tool.
run_retire --repo "$P13B" --from-dir "$T13B" >/dev/null 2>&1
REAL_ROOTS="$("$TEST_PYTHON" - <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sr", ".agents/skills/sync/scripts/sync-retire.py")
m = importlib.util.module_from_spec(spec); sys.modules["sr"] = m; spec.loader.exec_module(m)
live, retired = m.parse_syncable_roots(open(".agents/skills/sync/SKILL.md").read(), "real")
print(len(live) + len(retired))
PYX
)"
assert_eq "9" "$REAL_ROOTS" "all nine real syncable roots still pass the constraint"
fi
end_case

# ============================== 14. allowlist entries that protect nothing
if begin_case "14. allowlist entries that protect nothing"; then
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
assert_exit 1 "a trailing-slash directory pattern is refused"
assert_contains "$output" ".agents/skills/mine/**" "the refusal names the pattern that would work"
assert_file_exists "$P14/.agents/skills/mine/SKILL.md" \
  "nothing is deleted when a pattern is refused"

# A pattern that is well-formed but matched nothing this run is reported, not
# silently ignored — a stale allowlist entry is how a path starts being deleted.
write_keep "$P14" ".agents/skills/mine/**" ".agents/skills/typo-never-matches/**"
run_retire --repo "$P14" --from-dir "$T14"
assert_exit 0 "a pattern matching nothing is a warning, not a failure"
assert_contains "$output" "unmatched: .agents/skills/typo-never-matches/**" \
  "the unmatched pattern is named"
assert_not_contains "$output" "unmatched: .agents/skills/mine/**" \
  "a pattern that did match is not reported as unmatched"
fi
end_case

# ================================ 15. candidates must be patterns, not paths
if begin_case "15. candidates must be patterns, not paths"; then
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
assert_exit 0 "bootstrap succeeds even with an unexpressible path"
assert_file_contains "$P15/.claude/sync-keep.candidate" ".agents/skills/plain.md" \
  "an ordinary path is emitted as a usable pattern"
assert_file_contains "$P15/.claude/sync-keep.candidate" "# UNEXPRESSIBLE" \
  "a path with glob metacharacters is commented out, not emitted as a pattern"

# The promoted candidate must be a valid allowlist — the failure this prevents
# is a sync that exits 1 on a line the tool itself wrote.
cp "$P15/.claude/sync-keep.candidate" "$P15/.claude/sync-keep"
run_retire --repo "$P15" --from-dir "$T15"
assert_exit 0 "the promoted candidate validates"
assert_contains "$output" "kept:   .agents/skills/plain.md" "and protects what it names"
fi
end_case

# ============================== 16. a deletion that fails part-way still reports
if begin_case "16. a deletion that fails part-way still reports"; then
#
# The uncovered branch on the destructive path, and the one where files are lost
# without a record. `apply_plan` built a list of what it removed, but a
# propagating OSError threw that list away: the operator saw a plan of N, an
# errno, and had to run `git status` to learn which files were already gone.

printf '\n-- 16. partial deletion leaves a record --\n'

if [ "$(id -u)" -eq 0 ]; then
  printf '  skip  16 needs an unprivileged user (root ignores permission bits)\n'
else
  P16="$FIXTURE_ROOT/p16"; T16="$FIXTURE_ROOT/t16"
  make_project "$P16"; make_template "$T16"
  _f "$P16/.agents/skills/a-first/SKILL.md"  "retired, deletable"
  _f "$P16/.agents/skills/z-locked/SKILL.md" "retired, in a directory made read-only"
  commit_all "$P16"; write_keep "$P16"
  chmod a-w "$P16/.agents/skills/z-locked"

  run_retire --repo "$P16" --from-dir "$T16" --apply
  chmod u+w "$P16/.agents/skills/z-locked"

  assert_exit 1 "a deletion failure exits non-zero"
  assert_contains "$output" "mode:   applied (1 deleted, 1 failed)" \
    "the outcome counts what happened, not what was planned"
  assert_contains "$output" "FAILED: .agents/skills/z-locked/SKILL.md" \
    "the path that could not be deleted is named"
  assert_file_absent "$P16/.agents/skills/a-first/SKILL.md" \
    "the deletable path really was deleted"
  assert_file_exists "$P16/.agents/skills/z-locked/SKILL.md" \
    "the undeletable path really did survive"
  # The record must match the disk: exactly the paths reported deleted are gone.
  assert_contains "$output" "retire: .agents/skills/a-first/SKILL.md" \
    "the full plan is still printed before the outcome"
fi
fi
end_case

finish
