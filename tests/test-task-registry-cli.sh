#!/bin/bash
# tests/test-task-registry-cli.sh — contract tests for the provider-agnostic task registry:
# the one-shot migration and the CLI surface.
#
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-cli.sh runs only the cases whose name matches.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
py_module .agents/skills/task-registry/scripts SCRIPTS
CLI="$SCRIPTS/task-registry.py"

PY="$TEST_PYTHON"   # resolved once in tests/lib.sh

# A project directory with the layout every scenario expects; registry_repo
# is the same inside a git repository, for scenarios that resolve their
# repository from `origin`.
registry_project() {
  local d
  d="$(fixture_dir)"
  mkdir -p "$d/tasks" "$d/specs" "$d/docs"
  printf '%s' "$d"
}
registry_repo() {
  local d
  d="$(fixture_repo)"
  mkdir -p "$d/tasks" "$d/specs" "$d/docs"
  printf '%s' "$d"
}

# Run the CLI the way a skill does.
reg() { "$PY" "$CLI" "$@"; }

# --- shared fixture content --------------------------------------------------
# The seed lives under tests/fixtures/task-registry/; these helpers only place it.

write_index() {
  fixture_copy task-registry/todo.md "$1/tasks/todo.md"
}

# The shared GitHub config plus the `[status]` stanza this file adds to it.
write_github_config() {
  fixture_copy task-registry/task-tracking-status.md "$1/docs/task-tracking.md"
}

# The gh mock first on PATH, with the shared labels and issues. The issue list
# also returns pull requests, marked by a `pull_request` key -- #45 is one,
# carrying a managed block so that a provider that fails to drop it would
# surface a fourth task.
install_gh_mock() {
  local d="$1"
  mkdir -p "$d/bin" "$d/ghdata"
  fixture_copy task-registry/gh "$d/bin/gh"
  chmod +x "$d/bin/gh"
  fixture_copy task-registry/labels.json "$d/ghdata/labels.json"
  fixture_copy task-registry/issues.json "$d/ghdata/issues.json"
  fixture_copy task-registry/issue-42.json "$d/ghdata/issue-42.json"
  fixture_copy task-registry/next-number "$d/ghdata/next-number"
}

git_init_github_remote() {
  git -C "$1" remote add origin https://github.com/fixture-owner/fixture-repo.git
}

# The GitHub fixture of test-task-registry-providers.sh § 7: the index, the GitHub
# configuration, the gh mock and a remote.
F_GH="$(registry_repo)"
write_index "$F_GH"
write_github_config "$F_GH"
install_gh_mock "$F_GH"
git_init_github_remote "$F_GH"
# A local row deliberately sharing issue #44's title, with a different id and no
# link: if anything ever matches on title, this row silently disappears.
printf -- '- [ ] Decide on dither strategy <!-- task-id: local.dither-note --> — different task, same words\n' \
  >> "$F_GH/tasks/todo.md"

# =============================================================================
# 10. Migration — an ascii_video_pipeline-shaped repository
#
# The migration moved out of the skill in Cut 1 (specs/workflow-routing.md) and
# is now `scripts/migrate-task-registry.py`. These assertions are deliberately
# the same ones the subcommand had: a remedy that is documented but never
# exercised is not a remedy, and the one-shot has to keep behaving identically
# for the projects the retired command was the only answer for.
# =============================================================================
if begin_case "10. Migration"; then
MIGRATE="$REPO/scripts/migrate-task-registry.py"

# The subcommand is gone, and it fails as an unknown command rather than as a
# broken import — a project that scripted it learns that from the CLI.
mig_retired="$(reg migrate --repo "$REPO" 2>&1)"
mig_retired_code=$?
assert_eq "2" "$mig_retired_code" "Migrate: the retired subcommand exits 2 as unknown"
assert_contains "$mig_retired" "invalid choice: 'migrate'" \
  "Migrate: argparse refuses migrate by name"

# The Cut 2 precondition: `registry/index.py` and `registry/reconcile.py` are
# deleted one phase from now, so a one-shot that imported them would break the
# moment Cut 2 lands.
#
# Two guards, because neither alone is enough. The static one uses POSIX
# [[:space:]] rather than \s -- \s is a GNU extension that degrades to a literal
# 's' under BSD grep, which would make this pass by matching nothing, on exactly
# the runners least likely to be watched. The dynamic one is the real proof: a
# lazy importlib call inside a function body evades any import-line grep.
mig_import_lines="$(grep -cE "^[[:space:]]*(from|import)[[:space:]]" "$MIGRATE")"
if [ "$mig_import_lines" -gt 0 ]; then
  pass "Migrate: the import-line pattern matches this grep (found $mig_import_lines lines)"
else
  fail "Migrate: the import-line pattern matched nothing -- the guard below is vacuous here"
fi
mig_imports="$(grep -nE "^[[:space:]]*(from|import)[[:space:]]" "$MIGRATE" | grep -E "registry|skills" || true)"
assert_eq "" "$mig_imports" \
  "Migrate: the one-shot imports nothing from the skill (offenders: ${mig_imports:-none})"

# Execution beats inspection: run it against a tree with both Cut 2 casualties
# actually deleted. This is the assertion the todo row's wording claims.
F_CUT2="$(registry_project)"
mkdir -p "$F_CUT2/skillcopy"
cp -R "$SCRIPTS/." "$F_CUT2/skillcopy/"
rm -f "$F_CUT2/skillcopy/registry/index.py" "$F_CUT2/skillcopy/registry/reconcile.py" \
      "$F_CUT2/skillcopy/registry/upsert.py"
printf '# Plan\n\n- [ ] Survives the cut\n' > "$F_CUT2/tasks/todo.md"
cut2_out="$(PYTHONPATH="$F_CUT2/skillcopy" "$PY" "$MIGRATE" --repo "$F_CUT2" 2>&1)"
cut2_code=$?
assert_eq "0" "$cut2_code" \
  "Migrate: the one-shot still runs with index.py, reconcile.py and upsert.py deleted"
assert_contains "$cut2_out" "rows scanned:        1" \
  "Migrate: and still parses rows without the module it used to import them from"
F_MIG="$(registry_project)"
mkdir -p "$F_MIG/specs/pending" "$F_MIG/specs/completed"
cat > "$F_MIG/tasks/todo.md" <<'EOF'
# Task Plan

## Plan: Still-motion animation
> Spec: specs/completed/still-motion.md

[x] TDD: living texture flow -> impl
[x] TDD: zoom path agreement -> impl
[x] TDD: blur knob parameters -> impl
[ ] TDD: parametrize move intensity -> left open when the plan closed

## Session Summary — 2026-08-13
- Completed: 3 tasks
- Pending: 1

## Plan: Recipe morphs
> Spec: specs/pending/morph-recipes.md

- [ ] Morph live grid recipe — ship the live grid morph
    through the existing renderer
- [ ] Colour LUT loader — palette mapping for 8-bit sources
- [!] Verify nightly render deploy — smoke the rollout after each release
- [ ] Decide dither strategy — pick one before the next recipe lands

## Plan: Pre-convert effects
> Spec: specs/pending/pre-convert-effects.md

- [ ] Wire pre-convert effects — replaced by the stage pipeline
EOF
cat > "$F_MIG/tasks/backlog.md" <<'EOF'
# Backlog

- [ ] Phase 2 — colour management
- [ ] Phase 3 — batch renders
EOF
printf '# Morph recipes\n\nactive spec\n' > "$F_MIG/specs/pending/morph-recipes.md"
printf '# Pre-convert effects\n\n> Superseded by: specs/pending/stage-pipeline.md\n' \
  > "$F_MIG/specs/pending/pre-convert-effects.md"
printf '# Still motion\n\nshipped\n' > "$F_MIG/specs/completed/still-motion.md"
printf '# Orphaned plan\n\nnothing points here\n' > "$F_MIG/specs/pending/orphaned-plan.md"

mig_before="$(cd "$F_MIG" && find . -type f | sort)"
todo_before_mig="$(cat "$F_MIG/tasks/todo.md")"
mig_dry="$("$PY" "$MIGRATE" --repo "$F_MIG" 2>&1)"
mig_dry_code=$?
mig_after_dry="$(cd "$F_MIG" && find . -type f | sort)"
assert_eq "0" "$mig_dry_code" "Migrate: the dry run exits 0"
assert_contains "$mig_dry" "DRY RUN (nothing written)" "Migrate: dry-run is the default and says so"
assert_eq "$mig_before" "$mig_after_dry" "Migrate: the dry run writes nothing"
assert_eq "$todo_before_mig" "$(cat "$F_MIG/tasks/todo.md")" \
  "Migrate: dry-run preserves every physical continuation line byte-for-byte"
assert_contains "$mig_dry" "completed (history, no external task): 3" \
  "Migrate: the three ticked rows are classified as history"
assert_contains "$mig_dry" "stale (open in a closed plan): 1" \
  "Migrate: a row left open in a closed plan block is stale, not active"
assert_contains "$mig_dry" "superseded:          1" \
  "Migrate: a row whose spec declares itself superseded is classified superseded"
assert_contains "$mig_dry" "proposed external tasks: 2 group(s) covering 5 row(s)" \
  "Migrate: nine checkboxes propose two grouped external tasks, not nine issues"
assert_contains "$mig_dry" "operational" "Migrate: verification work keeps its own kind"
assert_contains "$mig_dry" "recipe-morphs.verify-nightly-render-deploy" \
  "Migrate: the operational row gets a stable id derived from its plan and title"
assert_contains "$mig_dry" "decision" "Migrate: a 'decide ...' row is classified as a decision"
assert_contains "$mig_dry" "spec=specs/pending/morph-recipes.md" \
  "Migrate: rows are linked to the spec that governs their plan block"
assert_contains "$mig_dry" "tasks/backlog.md: 2 open item(s) left in place" \
  "Migrate: the backlog is reported, not consumed"
assert_contains "$mig_dry" "Nothing here is deleted." "Migrate: the report states the no-deletion rule"
assert_contains "$mig_dry" "kind is inferred from row wording" \
  "Migrate: the heuristic declares itself as a heuristic"

mig_apply="$("$PY" "$MIGRATE" --repo "$F_MIG" --apply 2>&1)"
mig_apply_code=$?
assert_eq "0" "$mig_apply_code" "Migrate: --apply exits 0"
assert_contains "$mig_apply" "minted" "Migrate: --apply reports how many ids it minted"
assert_file_contains "$F_MIG/tasks/todo.md" \
  "- [ ] Morph live grid recipe <!-- task-id: recipe-morphs.morph-live-grid-recipe --> — ship the live grid morph" \
  "Migrate: the id is inserted after the title, leaving the rest of the row untouched"
assert_file_contains "$F_MIG/tasks/todo.md" "    through the existing renderer" \
  "Migrate: applying ids preserves indented legacy continuation detail"
assert_file_contains "$F_MIG/tasks/todo.md" "[x] TDD: living texture flow -> impl" \
  "Migrate: completed history rows are left exactly as they were"
completed_ids="$(grep -c 'TDD: living texture flow -> impl <!-- task-id' "$F_MIG/tasks/todo.md" || true)"
assert_eq "0" "$completed_ids" "Migrate: no id is minted for a completed history row"
assert_file_contains "$F_MIG/tasks/task-registry-migration.md" "# Task Registry Migration Audit" \
  "Migrate: an audit trail is written"
assert_file_contains "$F_MIG/tasks/task-registry-migration.md" "living texture flow" \
  "Migrate: the audit lists completed rows too — nothing is dropped from the record"
assert_file_contains "$F_MIG/tasks/task-registry-migration.md" "## Proposed grouping" \
  "Migrate: the audit records the proposed grouping"

# A BOM on the first physical row is the classic vendored-parser divergence:
# under plain utf-8 it prefixes line 1, the row regex misses, and the row is
# lost without ever being reported. The live index reads utf-8-sig, so the two
# must agree on the same bytes.
F_BOM="$(registry_project)"
printf '\xef\xbb\xbf- [ ] First row\n- [ ] Second row\n' > "$F_BOM/tasks/todo.md"
bom_out="$("$PY" "$MIGRATE" --repo "$F_BOM" 2>&1)"
assert_contains "$bom_out" "rows scanned:        2" \
  "Migrate: a BOM on the first row does not hide it from the one-shot"
bom_live="$(cd "$F_BOM" && "$PY" - <<'EOF'
from registry.index import load_index
print("live-rows=" + str(len(load_index("tasks/todo.md", "tasks/todo.md").rows)))
EOF
)"
assert_contains "$bom_live" "live-rows=2" \
  "Migrate: and the live index agrees on the same bytes"

# The row shape CLAUDE.md prescribes. Splitting it on '->' alone leaves an
# unbalanced backtick in the title, mints a 'tdd-' prefixed id, and breaks every
# blocked-by that names the row by wording. --apply mints ids once, so a wrong
# title is written to a human's file permanently.
F_TDD="$(registry_project)"
printf '# Plan\n\n## Plan: Recovery\n\n- [ ] TDD: `recover active thread` -> impl detail\n- [ ] TDD: `resume` -> more (blocked-by: recover active thread)\n' \
  > "$F_TDD/tasks/todo.md"
tdd_out="$("$PY" "$MIGRATE" --repo "$F_TDD" 2>&1)"
assert_contains "$tdd_out" "recovery.recover-active-thread" \
  "Migrate: a backticked TDD row mints an id from the test name, with no tdd- prefix"
assert_not_contains "$tdd_out" "recovery.tdd-recover-active-thread" \
  "Migrate: the 'TDD:' literal never becomes part of the identity"
assert_contains "$tdd_out" "recover active thread -> recovery.recover-active-thread" \
  "Migrate: a blocked-by naming a TDD row by its wording resolves to the minted id"
assert_not_contains "$tdd_out" 'TDD: `recover active thread$' \
  "Migrate: the title carries no unbalanced backtick"

# The vendored superseded marker must not be wider than reconcile's, or the two
# tools disagree about the same repository.
F_SUP="$(registry_project)"
printf '# Plan\n\n## Plan: Effects\n> Spec: specs/loose.md\n\n- [ ] Row under a loosely-worded spec\n' \
  > "$F_SUP/tasks/todo.md"
printf '# Loose\n\nSuperseded by the stage pipeline (see notes)\n' > "$F_SUP/specs/loose.md"
sup_out="$("$PY" "$MIGRATE" --repo "$F_SUP" 2>&1)"
assert_contains "$sup_out" "superseded:          0" \
  "Migrate: prose mentioning supersession is not a marker -- same rule as reconcile"

id_count_first="$(grep -c 'task-id:' "$F_MIG/tasks/todo.md")"
"$PY" "$MIGRATE" --repo "$F_MIG" --apply >/dev/null 2>&1
id_count_second="$(grep -c 'task-id:' "$F_MIG/tasks/todo.md")"
assert_eq "$id_count_first" "$id_count_second" \
  "Migrate: re-running --apply mints no duplicate ids"

# --- the one-shot's own surface, which section 10's inherited assertions miss -
# A wrong path is a usage error (2); unreadable rows are a content failure (1).
# The sibling CLI splits these deliberately so an unattended caller can retry the
# first and page a human for the second.
F_NOIDX="$(registry_project)"
rm -f "$F_NOIDX/tasks/todo.md"
noidx_out="$("$PY" "$MIGRATE" --repo "$F_NOIDX" 2>&1)"
noidx_code=$?
assert_eq "2" "$noidx_code" "Migrate: a missing index is a usage error, exit 2"
assert_contains "$noidx_out" "no index at tasks/todo.md" \
  "Migrate: the failure names the path it looked for"

badrow_out="$("$PY" "$MIGRATE" --repo "$F_NOIDX" 2>&1)"
printf '# Plan\n\n- [ ] Fine row\n- [?] Bad box\n' > "$F_NOIDX/tasks/todo.md"
badrow_out="$("$PY" "$MIGRATE" --repo "$F_NOIDX" 2>&1)"
badrow_code=$?
assert_eq "1" "$badrow_code" "Migrate: an unreadable row is a content failure, exit 1"
assert_contains "$badrow_out" "unknown status box '[?]' (expected one of:" \
  "Migrate: the malformed-row report says which characters are accepted"

# --repo declares a root, and --apply rewrites files. A path escaping that root
# is refused rather than silently written, matching the confinement the retired
# subcommand inherited from Config.path().
F_ESCM="$(registry_project)"
printf '# Plan\n\n- [ ] Row\n' > "$F_ESCM/tasks/todo.md"
mkdir -p "$F_ESCM/../escape-probe" 2>/dev/null || true
esc_out="$("$PY" "$MIGRATE" --repo "$F_ESCM" --index ../escape-probe/todo.md --apply 2>&1)"
esc_code=$?
assert_eq "2" "$esc_code" "Migrate: a path escaping --repo is refused, exit 2"
assert_contains "$esc_out" "resolves outside" \
  "Migrate: the refusal says the path left the declared root"
rm -rf "$F_ESCM/../escape-probe"

# The path flags are the port's own invention; nothing else exercises them.
F_FLAGS="$(registry_project)"
mkdir -p "$F_FLAGS/plans"
printf '# Plan\n\n## Plan: Alt\n\n- [ ] Row in an alternate index\n' \
  > "$F_FLAGS/plans/work.md"
flags_out="$("$PY" "$MIGRATE" --repo "$F_FLAGS" --index plans/work.md 2>&1)"
flags_code=$?
assert_eq "0" "$flags_code" "Migrate: --index reads an index outside the default path"
assert_contains "$flags_out" "alt.row-in-an-alternate-index" \
  "Migrate: rows from the alternate index are the ones classified"
assert_contains "$flags_out" "rows scanned:        1" \
  "Migrate: and the default tasks/todo.md is not read instead"

# Deliberately NOT asserted: that --spec-dir changes which specs a row links to.
# `SPEC_REFERENCE_RE` hardcodes `specs?/`, so a row can only ever cite a spec
# under `specs/` no matter where --spec-dir points -- the directory governs the
# superseded scan alone. That mismatch is carried verbatim from the retired
# subcommand, where `config.spec_dir` had the same relationship to the same
# regex, so it is pre-existing rather than introduced by the port. Recorded here
# so the next reader does not mistake the gap for coverage.

# An unreadable spec changes how its rows are classified, so it must reach the
# exit code rather than only a stderr warning an unattended run never reads.
if [ "$(id -u)" -eq 0 ]; then
  skip "Migrate: the unreadable-spec case needs an unprivileged user (root ignores permission bits)"
else
  F_BADSPEC="$(registry_project)"
  printf '# Plan\n\n## Plan: Thing\n> Spec: specs/locked.md\n\n- [ ] Row\n' > "$F_BADSPEC/tasks/todo.md"
  printf '# Locked\n\n> Superseded by: specs/other.md\n' > "$F_BADSPEC/specs/locked.md"
  chmod 000 "$F_BADSPEC/specs/locked.md"
  badspec_out="$("$PY" "$MIGRATE" --repo "$F_BADSPEC" 2>&1)"
  badspec_code=$?
  chmod 644 "$F_BADSPEC/specs/locked.md"
  if [ "$badspec_code" = "0" ]; then
    fail "Migrate: an unreadable spec must not report success (exit was 0)"
  else
    pass "Migrate: an unreadable spec fails the run rather than misclassifying silently"
  fi
  assert_contains "$badspec_out" "cannot read" \
    "Migrate: the unreadable spec is named in the report, not just on stderr"
fi

# `missing-id` was a reconcile diagnostic and died with it, so the migration's
# outcome is now read off the index itself: every active row carries a stable id
# and the file still parses clean.
post_mig="$(cd "$F_MIG" && "$PY" - <<'EOF'
from registry.index import load_index

index = load_index("tasks/todo.md", "tasks/todo.md")
active = [row for row in index.rows if row.task.status not in ("done", "dropped")]
print("active=" + str(len(active)))
print("without-id=" + str(len([row for row in active if not row.task.id])))
print("problems=" + str(len(index.problems)))
EOF
)"
assert_not_contains "$post_mig" "active=0" \
  "Migrate: the fixture actually has active rows to check"
assert_contains "$post_mig" "without-id=0" \
  "Migrate: active rows no longer report as missing an id"
assert_contains "$post_mig" "problems=0" \
  "Migrate: the migrated index parses without a malformed row"
fi
end_case

# =============================================================================
# 11. CLI surface — exit codes, dry-run precedence, report file
# =============================================================================
if begin_case "11. CLI surface"; then
F_CLI="$(registry_project)"
write_index "$F_CLI"

bad_cmd_out="$(reg frobnicate --repo "$F_CLI" 2>&1)"
bad_cmd_code=$?
assert_eq "2" "$bad_cmd_code" "CLI: an unknown command is a usage error (exit 2)"
assert_contains "$bad_cmd_out" "invalid choice" "CLI: the usage error names the invalid command"

no_id_out="$(reg show --repo "$F_CLI" 2>&1)"
no_id_code=$?
assert_eq "2" "$no_id_code" "CLI: 'show' without a task id is a usage error"
assert_contains "$no_id_out" "requires a task id" "CLI: the usage error says what is missing"

no_dir_out="$(reg selectors --repo "$F_CLI/nope" 2>&1)"
no_dir_code=$?
assert_eq "2" "$no_dir_code" "CLI: a missing project root is a usage error"
assert_contains "$no_dir_out" "no such directory" "CLI: the usage error names the missing path"

# `--dry-run` beating `--apply` is decided in main() for every gated command,
# so `upsert` pins it for all of them.
dry_wins="$(reg upsert cli.dry --repo "$F_CLI" --title 'Dry run wins' --apply --dry-run 2>&1)"
assert_contains "$dry_wins" "would create" "CLI: --dry-run overrides --apply"

reg selectors --repo "$F_CLI" --report "$F_CLI/report.txt" >/dev/null 2>&1
assert_file_contains "$F_CLI/report.txt" "selectors:" \
  "CLI: --report writes the same output to a file"

for command in doctor selectors; do
  out="$(reg "$command" --repo "$F_CLI" 2>&1)"
  code=$?
  assert_eq "0" "$code" "CLI: '$command' runs clean on a well-formed repository"
done

# --- upsert --parent: native, metadata degradation, and dry run ------------
#
# AC7: `upsert --parent` records a native parent on the local fixture, and
# `parent:` metadata plus the existing disclosure line on the GitHub fixture.
# Dry run by default, and the preview is decided from capabilities alone --
# it must never resolve the reference through the provider.
F_PARENT="$(registry_project)"
write_index "$F_PARENT"
reg upsert existing.parent --repo "$F_PARENT" --title 'Existing parent' --apply >/dev/null

parent_dry="$(reg upsert child.of-parent --repo "$F_PARENT" --title 'Child of parent' --parent existing.parent 2>&1)"
assert_contains "$parent_dry" "upsert: would link parent existing.parent (native on local)" \
  "upsert --parent: a local dry run names the intended link without --apply"

parent_local="$(reg upsert child.of-parent --repo "$F_PARENT" --title 'Child of parent' --apply --parent existing.parent 2>&1)"
assert_contains "$parent_local" "upsert: parent local:existing.parent linked natively" \
  "upsert --parent: the local provider links natively and says so plainly"
assert_file_contains "$F_PARENT/tasks/details/child.of-parent.md" "parent: existing.parent" \
  "upsert --parent: the child's detail file records the native parent"
assert_not_contains "${parent_local}X" "stored as metadata" \
  "upsert --parent: a native link carries no metadata-degradation disclosure"

# The reference must resolve to exactly one task: a typo is a hard failure the
# unattended caller (/slice --file) sees as a non-zero exit, never a `✓ Filed`.
parent_missing="$(reg upsert child.orphan --repo "$F_PARENT" --title 'Child of nobody' --apply --parent no.such.task 2>&1)"
parent_missing_code=$?
assert_eq "1" "$parent_missing_code" \
  "upsert --parent: a reference that names no task exits 1"
assert_contains "$parent_missing" "cannot resolve exactly one authoritative parent" \
  "upsert --parent: the failure names the unresolved reference"

# GitHub has no native parent link: the same flag lands as `parent:` metadata
# with the existing disclosure line -- and a dry run must not even resolve the
# reference, let alone write, so issue #44 is never fetched.
gh_parent_dry="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-parent-dry.log" \
  reg upsert recipe.morph-live-grid --repo "$F_GH" --title 'Morph live grid recipe' --parent '#44' 2>&1)"
assert_contains "$gh_parent_dry" "upsert: would link parent #44 (parent: metadata on github)" \
  "upsert --parent: a GitHub dry run names the degraded link without --apply"
assert_not_contains "$(cat "$F_GH/gh-parent-dry.log")X" "issues/44" \
  "upsert --parent: a dry run never resolves the parent reference through gh"

gh_parent_apply="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-parent-apply.log" \
  reg upsert recipe.morph-live-grid --repo "$F_GH" --title 'Morph live grid recipe' --apply --approve --parent '#44' 2>&1)"
gh_parent_apply_code=$?
assert_eq "0" "$gh_parent_apply_code" \
  "upsert --parent: a resolvable GitHub parent link exits clean"
assert_contains "$gh_parent_apply" \
  'upsert: parent github:44 stored as metadata — GitHub issues expose no parent link through gh; stored as `parent:` metadata' \
  "upsert --parent: GitHub reports the degraded link with the existing disclosure line"
assert_contains "$(cat "$F_GH/gh-parent-apply.log")" "parent: render.dither-strategy" \
  "upsert --parent: the child issue's body gains parent: metadata naming the resolved parent"

# --- upsert: seeded blocked-by survives a fresh provider record ------------
#
# `/slice --file` seeds the compact row -- including its `(blocked-by: ...)`
# marker -- before the task it names has ever been created. `_existing` reads
# the provider record, not the index row, so the first `upsert --apply` sees
# no record and creates one with an empty `depends_on`; rendering the row
# straight from that record would drop the marker on this very first refresh.
# A second run after an interrupted filing must be exactly as safe.
F_SEEDED="$(registry_project)"
cat > "$F_SEEDED/tasks/todo.md" <<'EOF'
# Task Plan

- [ ] Seeded task <!-- task-id: seeded.blocked --> — filed ahead of itself (blocked-by: seeded.blocker)
EOF

seeded_run1="$(reg upsert seeded.blocked --repo "$F_SEEDED" --title 'Seeded task' --summary 'filed ahead of itself' --apply 2>&1)"
assert_contains "$seeded_run1" "created seeded.blocked" \
  "upsert seeded blocked-by: no provider record exists yet, so the first run creates"
assert_file_contains "$F_SEEDED/tasks/todo.md" "(blocked-by: seeded.blocker)" \
  "upsert seeded blocked-by: the first refresh keeps the marker the row seeded"

seeded_run2="$(reg upsert seeded.blocked --repo "$F_SEEDED" --title 'Seeded task' --summary 'filed ahead of itself' --apply 2>&1)"
assert_contains "$seeded_run2" "updated seeded.blocked" \
  "upsert seeded blocked-by: the second run finds the record the first run created"
assert_file_contains "$F_SEEDED/tasks/todo.md" "(blocked-by: seeded.blocker)" \
  "upsert seeded blocked-by: the second refresh keeps the marker too"
assert_eq "1" "$(grep -c 'task-id: seeded\.blocked' "$F_SEEDED/tasks/todo.md")" \
  "upsert seeded blocked-by: exactly one row for the id, never a duplicate"

# A slice built before it was filed is seeded `[x]`; the task is created from
# the row's status, so the first refresh keeps the box instead of reopening it.
cat >> "$F_SEEDED/tasks/todo.md" <<'EOF'
- [x] Seeded done <!-- task-id: seeded.done --> — finished before filing
EOF
seeded_done="$(reg upsert seeded.done --repo "$F_SEEDED" --title 'Seeded done' --summary 'finished before filing' --apply 2>&1)"
assert_contains "$seeded_done" "created seeded.done" \
  "upsert seeded [x]: the first run creates the task from the seeded row"
assert_file_contains "$F_SEEDED/tasks/todo.md" "- [x] Seeded done" \
  "upsert seeded [x]: the first refresh keeps the done box the row seeded"
fi
end_case

finish
