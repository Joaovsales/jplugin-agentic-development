#!/bin/bash
# tests/test-sync-retirement-security.sh — behavioural contract for deterministic retirement in /sync
# (specs/sync-deterministic-retirement.md): security review regressions and retired roots.
#
# One of the files split from the former tests/test-sync-retirement.sh at its
# section seams (specs/test-suite-aposd.md D4). Every piece declares the same
# artefact, so tests/affected.sh selects all of them on a change to sync-retire.py.
# Each section is a case: TEST_CASE='<glob>' bash tests/test-sync-retirement-security.sh runs only the
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

# ==================================== 23. security review regressions (round 3)
if begin_case "23. security review regressions (round 3)"; then
#
# Every case below was found by a dispatched security review of the finished
# tool and reproduced before being fixed. They share a theme the earlier rounds
# missed: the deletion set and the *record* of the deletion are both attacker-
# influenceable surfaces, and neither had been tested as one.

printf '\n-- 23. security regressions --\n'

# --- 23.1 a symlinked directory component must not send os.remove outside ---
#
# `project_paths` reads the index and confirms the leaf with `os.path.isfile`,
# which follows every component. A symlinked *directory* inside a syncable root
# therefore aimed the delete anywhere on the filesystem — at files that were
# never in this repository, so `git restore` could not bring them back. It needs
# no hostile template: a developer sharing a skill tree across worktrees is enough.

P42="$FIXTURE_ROOT/p42"; T42="$FIXTURE_ROOT/t42"
OUTSIDE42="$FIXTURE_ROOT/outside42/nested"
make_project "$P42"; make_template "$T42"
mkdir -p "$P42/.agents/skills/sub"
_f "$P42/.agents/skills/sub/victim.sh" "tracked here first"
commit_all "$P42"
# Now the tracked path resolves through a symlink to somewhere else entirely.
mkdir -p "$OUTSIDE42"
_f "$OUTSIDE42/victim.sh" "precious file, never in the repository"
rm -rf "$P42/.agents/skills/sub"
ln -s "$OUTSIDE42" "$P42/.agents/skills/sub"
write_keep "$P42" ".agents/skills/nothing-at-all/**"

run_retire --repo "$P42" --from-dir "$T42" --apply
assert_file_exists "$OUTSIDE42/victim.sh" \
  "a file outside the repository is never deleted through a symlinked directory"
assert_exit 1 "and the refusal is a non-zero outcome"
assert_contains "$output" "resolves outside the repository" \
  "the report says why it refused, naming the mechanism"
assert_not_contains "$output" "deleted: .agents/skills/sub/victim.sh" \
  "and never claims to have deleted it"

# --- 23.2 a filename cannot forge a line in the record ----------------------
#
# The report is the only record of what a file-deleting tool destroyed, and
# SKILL.md tells the operator to read it in full and never abbreviate it. A path
# containing a newline emitted lines indistinguishable from real ones: the run
# below claimed to have *kept* a file it was deleting.

P43="$FIXTURE_ROOT/p43"; T43="$FIXTURE_ROOT/t43"
make_project "$P43"; make_template "$T43"
FORGED43=$'.claude/hooks/a.md\n  kept:   audit.sh (matched keepall)'
_f "$P43/$FORGED43" "the payload is in the name, not the content"
_f "$P43/.claude/hooks/audit.sh" "a real file the forged line lies about"
commit_all "$P43"
write_keep "$P43" ".claude/hooks/nothing-at-all/**"

run_retire --repo "$P43" --from-dir "$T43"
# The payload text still appears — inside the escaped path, on the retire line,
# which is the point. What must not exist is a *line* that reads as a kept entry.
assert_eq "0" "$(printf '%s\n' "$output" | grep -c '^  kept:' || true)" \
  "a newline in a filename cannot inject a kept: line into the record"
assert_contains "$output" "\\n  kept:" \
  "the newline is escaped into the path field rather than ending the line"
assert_eq "0" \
  "$(printf '%s\n' "$output" | tail -n +2 | grep -cv '^  ' || true)" \
  "every report line still starts as a report line"
assert_contains "$output" "retire: .claude/hooks/audit.sh" \
  "and the file the forgery lied about is correctly listed for retirement"

# --- 23.3 the template's git config must not steer the deletion set --------
#
# `git log --raw` C-quotes non-ASCII paths, and `core.quotePath` decides whether
# it does — read from the repository being inspected, which in --from-dir mode
# is the untrusted template checkout. One line in someone else's .git/config
# moved a file between "held for a human" and "deleted".

P44="$FIXTURE_ROOT/p44"; T44="$FIXTURE_ROOT/t44"
make_project "$P44"
git_here "$T44"
make_template "$T44"
_f "$T44/.claude/hooks/café.sh" "shipped once, retired later"
commit_all "$T44"
git -C "$T44" rm -q ".claude/hooks/café.sh"
commit_all "$T44"
_f "$P44/.claude/hooks/café.sh" "shipped once, retired later"
commit_all "$P44"
rm -f "$P44/.claude/sync-keep"

git -C "$T44" config core.quotePath true
run_retire --repo "$P44" --from-dir "$T44"
QUOTED44="$(printf '%s\n' "$output" | grep -c 'retire:' || true)"
git -C "$T44" config core.quotePath false
run_retire --repo "$P44" --from-dir "$T44"
UNQUOTED44="$(printf '%s\n' "$output" | grep -c 'retire:' || true)"
assert_eq "$QUOTED44" "$UNQUOTED44" \
  "the template's core.quotePath does not change what gets retired"
assert_eq "1" "$QUOTED44" \
  "and the non-ASCII path is retired in both, rather than neither (non-vacuity)"

# --- 23.4 a commit message is not a commit header --------------------------
#
# `cat-file commit` emits headers, a blank line, then free text. Grepping the
# whole object for `^parent ` read a *message* line as a shallow graft, so one
# upstream commit message could report `provenance: unavailable` — and so retire
# nothing — for every downstream project, forever.

P45="$FIXTURE_ROOT/p45"; T45="$FIXTURE_ROOT/t45"
make_project "$P45"
git_here "$T45"
make_template "$T45"
_f "$T45/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
git -C "$T45" add -A
git -C "$T45" commit -q -m "$(printf 'init\n\nparent 0000000000000000000000000000000000000000 was dropped\n')"
git -C "$T45" rm -q -r .agents/skills/legacy
commit_all "$T45"
_f "$P45/.agents/skills/legacy/SKILL.md" "shipped once, retired later"
commit_all "$P45"
rm -f "$P45/.claude/sync-keep"

run_retire --repo "$P45" --from-dir "$T45"
assert_not_contains "$output" "provenance: unavailable" \
  "a root commit whose message contains a 'parent ' line is not a graft"
assert_contains "$output" "retire: .agents/skills/legacy/SKILL.md" \
  "so provenance still resolves and the retired path is still retired"

# --- 23.5 option interpretation is refused at the sink, not only in main ----
#
# `main` rejects a --from-ref beginning with `-`, but the tests already import
# this module and call in directly, so that guard is one refactor from being
# bypassed. Without --end-of-options, `git show "--output=...:path"` is read as
# an option and git attempts the write.

# `git show --output=FILE` writes to FILE. The ref is interpolated as
# f"{ref}:{SKILL_DOC}", so the real target is `<ref-payload>:.agents/skills/
# sync/SKILL.md` -- create those directories, or git fails for the wrong reason
# and the test passes against the unfixed code.
INJECT45="$FIXTURE_ROOT/inj"
mkdir -p "$INJECT45:.agents/skills/sync"
rm -f "$INJECT45:.agents/skills/sync/SKILL.md"

INJECT_OUT="$("$TEST_PYTHON" - "$RETIRE" "$P45" "$INJECT45" <<'PYX' 2>&1 || true
import importlib.util, sys
script, repo, victim = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("sr", script)
module = importlib.util.module_from_spec(spec)
sys.modules["sr"] = module
spec.loader.exec_module(module)
try:
    module.read_template_doc(repo, f"--output={victim}", None)
except Exception as exc:
    print(type(exc).__name__)
PYX
)"
assert_file_absent "$INJECT45:.agents/skills/sync/SKILL.md" \
  "a ref that looks like an option never becomes one at the git show sink"
assert_contains "$INJECT_OUT" "RetireError" \
  "it is refused as a bad revision, through the module's own error type"
fi
end_case

# ================================ 24. retired roots (specs/claude-plugin-manifest.md)
if begin_case "24. retired roots (specs/claude-plugin-manifest.md)"; then
#
# `.claude/skills/` stops being checked out: the jplugin plugin reads
# `.agents/skills/` directly. The root stays in the doc block, marked RETIRED in
# its right-hand column, so /sync can still delete the copies earlier syncs left
# downstream -- and only those. Three properties are pinned: the parser splits
# the two kinds of root, a retired root never counts toward the one-empty-root
# budget, and nothing under it enters the plan unless the project's own
# settings enable the plugin that replaces the copies.

printf '\n-- 24. retired roots: history-matched, never counted, plugin-guarded --\n'

JPLUGIN_ID="jplugin@jplugin-agentic-development"

# The fixture doc block with the `.claude/skills/` row marked RETIRED. Same
# two-column shape and trailing slash as the live rows: the marker is the only
# thing the parser may key on.
write_retired_skill_md() {
  fixture_copy sync/syncable-paths-retired.md "$1/.agents/skills/sync/SKILL.md"
}

# A template that shipped `plan` and `build` under .claude/skills/ and later
# dropped the whole root, and whose .claude/hooks/ root is empty. Two roots the
# template has nothing under: one live (skipped, as ever) and one retired. If
# the retired root were counted, this template would be refused as incomplete.
make_retired_template() {
  _dir="$1"
  # No .claude/hooks here: the template's hooks root is deliberately absent.
  mkdir -p "$_dir/.agents/skills/sync" "$_dir/.agents/skills/build" "$_dir/.agents/agents" "$_dir/.claude/skills/build" "$_dir/.claude/skills/plan"
  git_here "$_dir"
  write_retired_skill_md "$_dir"
  _f "$_dir/.agents/skills/build/SKILL.md"  "build skill"
  _f "$_dir/.agents/agents/planner.md"      "planner"
  _f "$_dir/.claude/skills/build/SKILL.md"  "build skill"
  _f "$_dir/.claude/skills/plan/SKILL.md"   "plan skill"
  _f "$_dir/CLAUDE.md"                      "rules"
  _f "$_dir/.claude/settings.json"          "{}"
  commit_all "$_dir"
  git -C "$_dir" rm -q -r .claude/skills
  commit_all "$_dir"
}

P50="$FIXTURE_ROOT/p50"; T50="$FIXTURE_ROOT/t50"
make_project "$P50"; make_retired_template "$T50"
# `build` came from make_project and is byte-identical to what the template
# shipped; `plan` likewise; `verify-myapp` the template never carried.
_f "$P50/.claude/skills/plan/SKILL.md"         "plan skill"
_f "$P50/.claude/skills/verify-myapp/SKILL.md" "this project's own verification recipe"
_f "$P50/.agents/skills/mine/SKILL.md"         "project specific"
_f "$P50/.agents/skills/stale/SKILL.md"        "project-only under a live root, no keep pattern"
commit_all "$P50"
write_keep "$P50" ".agents/skills/mine/**"

# --- 24.1 the parser splits live from retired -------------------------------
PARSED="$("$TEST_PYTHON" - "$RETIRE" "$T50/.agents/skills/sync/SKILL.md" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
m = importlib.util.module_from_spec(spec); sys.modules["sr"] = m; spec.loader.exec_module(m)
live, retired = m.parse_syncable_roots(open(sys.argv[2], encoding="utf-8").read(), "fixture")
print("live=" + ",".join(live))
print("retired=" + ",".join(retired))
PYX
)"
assert_contains "$PARSED" "live=.agents/agents/,.agents/skills/,.claude/hooks/" \
  "24.1: live_roots holds every directory row without the marker, sorted"
assert_contains "$PARSED" "retired=.claude/skills/" \
  "24.1: the RETIRED marker puts a root in retired_roots"
assert_not_contains "$(printf '%s\n' "$PARSED" | grep '^live=')" ".claude/skills/" \
  "24.1: ... and in retired_roots only"

# --- 24.2 the project guard ---------------------------------------------------
# `{}` is what make_project writes: a project that never accepted the plugin.
# Deleting its .claude/skills/ copies would leave it with no skills at all. The
# guard is a plan state, not a refusal: /sync Step 3 previews this plan before
# Step 5 has written the declaration, so a refusal would exit 1 on every
# downstream project's first sync and drop the live-root list from the summary.
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 0 \
  "24.2: settings without enabledPlugins still produce a plan -- Step 3 previews before Step 5 writes them"
assert_contains "$output" ".claude/settings.json" \
  "24.2: the report names the file that must enable the plugin"
assert_contains "$output" "$JPLUGIN_ID" \
  "24.2: ... and the plugin id it must enable"
assert_contains "$output" "Step 5" \
  "24.2: ... and the /sync step that writes it"
assert_not_contains "$output" "retire: .claude/skills/" \
  "24.2: nothing under the retired root enters the plan without the declaration"
assert_contains "$output" "retire: .agents/skills/stale/SKILL.md" \
  "24.2: live-root retirement is unaffected, so the preview the user approves is complete"

_f "$P50/.claude/settings.json" "{ not json"
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 1 "24.3: unreadable settings JSON is a refusal, not a traceback"
assert_contains "$output" "cannot parse .claude/settings.json" \
  "24.3: the error names the file"
assert_not_contains "$output" "Traceback" "24.3: ... through RetireError"

# --- 24.3b a shape Claude Code cannot read is a refusal too; absent and false hold back ---
_f "$P50/.claude/settings.json" '{"enabledPlugins": []}'
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 1 "24.3b: enabledPlugins that is not an object is refused, not read as empty"
assert_contains "$output" "enabledPlugins" "24.3b: the error names the key"
_f "$P50/.claude/settings.json" '{"enabledPlugins": {"jplugin@jplugin-agentic-development": false}}'
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 0 "24.3b: a project that set the plugin to false still gets a plan"
assert_contains "$output" "does not enable" "24.3b: ... held back with the same reason"
assert_not_contains "$output" "retire: .claude/skills/" "24.3b: ... and nothing under the retired root enters it"
rm -f "$P50/.claude/settings.json"
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 0 "24.3b: a project with no settings file at all still gets a plan"
assert_contains "$output" "does not enable" "24.3b: ... held back the same way"

# --- 24.4 with the plugin enabled, history decides ----------------------------
_f "$P50/.claude/settings.json" '{"enabledPlugins": {"jplugin@jplugin-agentic-development": true}}'
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 0 "24.4: with the plugin enabled the plan is produced"
assert_contains "$output" "retired root: .claude/skills/" \
  "24.4: the report names the retired root"
assert_contains "$output" "skipped: .claude/hooks/" \
  "24.4: the one empty LIVE root is skipped as before"
assert_contains "$output" "roots: 2" \
  "24.4: the retired root is not counted among the scanned roots"
assert_contains "$output" "retire: .claude/skills/plan/SKILL.md" \
  "24.4: a byte-identical copy of a file the template once shipped there is retired"
assert_contains "$output" "retire: .claude/skills/build/SKILL.md" \
  "24.4: so is a copy of one the template still ships under its live root"
assert_not_contains "$output" "verify-myapp" \
  "24.4: a project-local skill under the retired root is listed under nothing"

# --- 24.5 sync-keep still reaches a retired root -----------------------------
# /create-verification-skill used to mirror into .claude/skills/, and downstream
# sync-keep files already name paths there. A pattern under a retired root must
# stay a valid pattern, or every such project's allowlist becomes a usage error.
write_keep "$P50" ".agents/skills/mine/**" ".claude/skills/build/**"
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 0 "24.5: a sync-keep pattern under a retired root is still valid"
assert_contains "$output" "kept:   .claude/skills/build/SKILL.md" \
  "24.5: and it protects the copy it names"
assert_contains "$output" "retire: .claude/skills/plan/SKILL.md" \
  "24.5: without protecting its neighbour"

# --- 24.5b ... and a pattern guarding a project-local file there is not stale ---
# History cannot see verify-myapp, so nothing matches the pattern; reporting it as
# `unmatched` would tell the operator it is about to stop protecting something.
write_keep "$P50" ".agents/skills/mine/**" ".claude/skills/verify-myapp/**"
run_retire --repo "$P50" --from-dir "$T50"
assert_exit 0 "24.5b: a sync-keep pattern for a project-local skill under the retired root is valid"
assert_not_contains "$output" "unmatched: .claude/skills/verify-myapp" \
  "24.5b: it is not reported as matching nothing"
write_keep "$P50" ".agents/skills/mine/**" ".claude/skills/build/**"

# --- 24.6 --apply deletes only the history-matched, unprotected copies -------
run_retire --repo "$P50" --from-dir "$T50" --apply
assert_exit 0 "24.6: --apply succeeds"
assert_file_absent "$P50/.claude/skills/plan/SKILL.md" \
  "24.6: the history-matched copy is deleted"
assert_file_absent "$P50/.claude/skills/plan" \
  "24.6: its emptied directory is pruned"
assert_file_exists "$P50/.claude/skills" \
  "24.6: the retired root itself is the prune boundary"
assert_file_contains "$P50/.claude/skills/verify-myapp/SKILL.md" "own verification" \
  "24.6: the project-local skill is untouched"
assert_file_contains "$P50/.claude/skills/build/SKILL.md" "build skill" \
  "24.6: the kept copy is untouched"

# --- 24.7 bootstrap retires retired-root copies too -------------------------
# They are proven by history, which is the same proof bootstrap already accepts
# for a live root -- a project that never promoted a candidate must not keep
# its shadow copies forever.
P51="$FIXTURE_ROOT/p51"
make_project "$P51"
_f "$P51/.claude/skills/plan/SKILL.md" "plan skill"
commit_all "$P51"
rm -f "$P51/.claude/sync-keep"
_f "$P51/.claude/settings.json" '{"enabledPlugins": {"jplugin@jplugin-agentic-development": true}}'
run_retire --repo "$P51" --from-dir "$T50"
assert_exit 0 "24.7: bootstrap against a template with a retired root produces a plan"
assert_contains "$output" "retire: .claude/skills/plan/SKILL.md" \
  "24.7: bootstrap retires the history-proven copy under the retired root"
assert_not_contains "$output" "candidate: .claude/skills" \
  "24.7: nothing under a retired root is sent to the human -- history already answered"
fi
end_case

finish
