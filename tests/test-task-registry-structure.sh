#!/bin/bash
# tests/test-task-registry-structure.sh — contract tests for the provider-agnostic task registry:
# the Cut 2 boundary and the registry-area harness sweep.
#
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-structure.sh runs only the cases whose name matches.
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
# 13. Cut 2 — the sync engine is gone; progressive disclosure survives it
# =============================================================================
if begin_case "13. Cut 2"; then
# `show` was the one surviving command implemented as a `Registry` *method*, so
# it could not stay where it was. These assertions pin the boundary the cut
# creates: the sync modules are absent, their commands are unknown, and reading
# one task still works from the module that inherited it.

assert_file_absent "$SCRIPTS/registry/reconcile.py" \
  "Cut 2: registry/reconcile.py is deleted"
cut2_control="$(fixture_dir)/control.py"
printf 'from .reconcile import x\n' > "$cut2_control"
assert_sweep_empty "Cut 2: no module still imports the deleted sync engine" "$cut2_control" -- \
  grep -rln 'from \.reconcile\|registry\.reconcile' -- "$SCRIPTS"
# `index.py` outlives the cut on purpose. Two survivors read through it -- `show`
# for the row behind a reference, and `upsert` for the external ref the local
# store cannot remember -- so deleting it would mean deleting them. What retires
# is the part only the sync engine called.
for retired in collect_problems row_text replace_line; do
  printf 'def %s(rows):\n' "$retired" > "$cut2_control"
  assert_sweep_empty "Cut 2: index.py no longer carries the sync-only helper $retired" "$cut2_control" -- \
    grep -n "def $retired" -- "$SCRIPTS/registry/index.py"
done
# `_published_ref` reads the link row that `_sync_index` writes. Deleting the
# write while keeping the read would re-open the duplicate-issue bug the read
# exists to prevent, so the pair is pinned together rather than one at a time.
assert_file_contains "$SCRIPTS/registry/upsert.py" "def _published_ref" \
  "Cut 2: upsert still remembers where a task was published"
assert_file_contains "$SCRIPTS/registry/upsert.py" "def _sync_index" \
  "Cut 2: upsert still writes the row that memory is read from"

# Progressive disclosure survives the module it used to live in. Two shapes,
# because they take different paths through the resolver: a task the local index
# knows and the provider does not, and a task the provider knows.
F_SHOW="$(registry_project)"
mkdir -p "$F_SHOW/tasks/details"
cat > "$F_SHOW/tasks/todo.md" <<'EOF'
# Task Plan

- [ ] Index-only row <!-- task-id: show.index-only --> — never published anywhere
- [ ] Colour LUT loader <!-- task-id: show.color-lut --> — palette mapping
EOF
cat > "$F_SHOW/tasks/details/show.color-lut.md" <<'EOF'
# Colour LUT loader

<!-- task-registry:begin -->
task-id: show.color-lut
kind: bug
<!-- task-registry:end -->

- status: done
- priority: high

## Summary

palette mapping

## Acceptance Criteria

- [ ] eight-bit sources load without a colour shift
EOF

for gone in reconcile publish pull frontier; do
  gone_out="$(reg "$gone" --repo "$F_SHOW" 2>&1)"; gone_code=$?
  assert_true "Cut 2: \`$gone\` is not a command any more" -- test "$gone_code" -ne 0
  assert_contains "$gone_out" "invalid choice" "Cut 2: \`$gone\` is rejected by name"
done

show_prov="$(reg show show.color-lut --repo "$F_SHOW" 2>&1)"; show_prov_code=$?
assert_eq "0" "$show_prov_code" "Show: a provider-backed task exits 0"
assert_contains "$show_prov" "kind:     bug" "Show: the full record includes the kind"
assert_contains "$show_prov" "eight-bit sources load without a colour shift" \
  "Show: acceptance criteria are disclosed on demand"
assert_contains "$show_prov" "external: local:show.color-lut" \
  "Show: the external reference is named"

show_local="$(reg show show.index-only --repo "$F_SHOW" 2>&1)"; show_local_code=$?
assert_eq "0" "$show_local_code" "Show: a row the provider has never seen still resolves"
assert_contains "$show_local" "never published anywhere" \
  "Show: the local index row supplies the detail when the provider has none"
assert_contains "$show_local" "index row: tasks/todo.md" \
  "Show: the row's source file is named"

show_miss="$(reg show no-such-task --repo "$F_SHOW" 2>&1)"; show_miss_code=$?
assert_eq "1" "$show_miss_code" "Show: an unknown reference exits 1"
assert_contains "$show_miss" "no task with reference 'no-such-task'" \
  "Show: the failure names the reference"

# A row that fails to parse is invisible to `by_id`, so a command that acts on
# the index would update nothing and append a second row carrying the same id.
# `reconcile` used to report the malformed row; it is gone, so the refusal lives
# at the seam every *acting* command crosses. AC-19 of specs/task-registry.md
# scopes this to acting: `show` writes nothing, so it reports the broken row and
# still answers -- refusing there would deny every task over one bad row, and
# leave no command able to diagnose the file.
F_BAD="$(registry_project)"
printf '# Plan\n\n- [ ] Broken row <!-- task-id: dup.target\n- [ ] Fine row <!-- task-id: ok.other --> — parses\n' > "$F_BAD/tasks/todo.md"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_BAD/docs/task-tracking.md"

bad_show="$(reg show ok.other --repo "$F_BAD" 2>&1)"; bad_show_code=$?
assert_eq "0" "$bad_show_code" \
  "Malformed index: show still answers for a row that parses"
bad_show_degraded="$(printf '%s\n' "$bad_show" | sed -n '/^  degraded:$/,/^  [a-z]*:$/p')"
assert_contains "$bad_show_degraded" "tasks/todo.md:3" \
  "Malformed index: show names the broken row with file:line, in the degraded block"
assert_contains "$bad_show_degraded" "unbalanced HTML comment" \
  "Malformed index: show names the fault, not just the line"

bad_up="$(reg upsert dup.target --repo "$F_BAD" --title 'Broken row' --apply 2>&1)"; bad_up_code=$?
assert_eq "1" "$bad_up_code" "Malformed index: upsert refuses before any provider write"
assert_contains "$bad_up" "tasks/todo.md:3" "Malformed index: upsert's refusal carries file:line"
assert_eq "1" "$(grep -c 'dup.target' "$F_BAD/tasks/todo.md")" \
  "Malformed index: no second row is appended for a row that failed to parse"

# The dry run must refuse identically, or the preview describes a different run
# than `--apply` performs -- which is the divergence resolve_destination argues against.
bad_dry="$(reg upsert dup.target --repo "$F_BAD" --title 'Broken row' 2>&1)"; bad_dry_code=$?
assert_eq "1" "$bad_dry_code" "Malformed index: the dry run refuses too, not only --apply"

# The ordering AC-19 actually states, on the only path that writes to a provider.
# The local fixture above cannot catch this: it refuses via `_published_ref`,
# which the external path skips.
F_BADGH="$(registry_repo)"
install_gh_mock "$F_BADGH"; write_github_config "$F_BADGH"; git_init_github_remote "$F_BADGH"
printf '# Plan\n\n- [ ] Broken row <!-- task-id: dup.target\n' > "$F_BADGH/tasks/todo.md"
bad_gh="$(cd "$F_BADGH" && PATH="$F_BADGH/bin:$PATH" GH_MOCK_DIR="$F_BADGH/ghdata" \
  GH_MOCK_LOG="$F_BADGH/gh-bad.log" \
  reg upsert brand.new --repo "$F_BADGH" --title 'Brand new' --apply --approve 2>&1)"; bad_gh_code=$?
assert_eq "1" "$bad_gh_code" "Malformed index: upsert refuses on the GitHub path too"
assert_contains "$bad_gh" "unbalanced HTML comment" \
  "Malformed index: the GitHub-path refusal names the malformed row, not some other guard"
# The mock creates its log on start, so "no log" is only evidence once a control
# call shows the mock on PATH leaves one -- a mock that never ran (the Windows
# gh.exe PATHEXT case) would otherwise satisfy the absence just as well.
(cd "$F_BADGH" && PATH="$F_BADGH/bin:$PATH" GH_MOCK_DIR="$F_BADGH/ghdata" \
  GH_MOCK_LOG="$F_BADGH/gh-control.log" gh api user) >/dev/null 2>&1
assert_file_exists "$F_BADGH/gh-control.log" \
  "Malformed index: control -- the mock on PATH creates its log when it is called"
assert_file_absent "$F_BADGH/gh-bad.log" \
  "Malformed index: no provider call is made at all before the refusal (AC-19 ordering)"

# `offline_reads = fail` is the other half of the same policy: degrade is the
# default, but a project that would rather have no answer than a partial one says
# so, and then an unreachable provider is a failure -- non-zero exit, a
# `failures:` section, and the reason named. Nothing pinned Report.exit_code or
# the failures render once `publish`'s failure path went with the sync engine.
F_FAIL="$(registry_repo)"
install_gh_mock "$F_FAIL"; git_init_github_remote "$F_FAIL"
cat > "$F_FAIL/docs/task-tracking.md" <<'EOF'
# T

```ini
[tracker]
provider = github
repository = fixture-owner/fixture-repo
offline_reads = fail
```
EOF
printf '# Plan\n\n- [ ] Local only <!-- task-id: fail.local --> — never published\n' > "$F_FAIL/tasks/todo.md"
fail_show="$(cd "$F_FAIL" && PATH="$F_FAIL/bin:$PATH" GH_MOCK_DIR="$F_FAIL/ghdata" \
  GH_MOCK_LOG="$F_FAIL/gh-fail.log" GH_MOCK_UNAUTH=1 \
  reg show fail.local --repo "$F_FAIL" 2>&1)"; fail_show_code=$?
assert_eq "1" "$fail_show_code" \
  "offline_reads=fail: an unreachable provider makes show exit non-zero"
fail_block="$(printf '%s\n' "$fail_show" | sed -n '/^  failures:$/,/^  [a-z]*:$/p')"
assert_contains "$fail_block" "provider unreachable" \
  "offline_reads=fail: the reason is named under failures:, not degraded:"
assert_not_contains "$fail_show" "  degraded:" \
  "offline_reads=fail: an unreachable read is a failure, never a mere degradation"

# A `show` that could not reach the provider answered from the local half alone.
# Printing that record with no marker is the silent partial answer the Report
# docstring says cannot happen.
gh_degraded="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-degraded.log" GH_MOCK_UNAUTH=1 \
  reg show ops.verify-deploy --repo "$F_GH" 2>&1)"
# Scope the needle to the section header, not the word: the limitation's own text
# is "reads degraded to local-only", so a bare "degraded" matches even when the
# section is never rendered.
degraded_block="$(printf '%s\n' "$gh_degraded" | sed -n '/^  degraded:$/,/^  [a-z]*:$/p')"
assert_contains "$degraded_block" "reads degraded to local-only" \
  "Show: an answer assembled without the provider says so rather than reading as complete"

label_only="$("$PY" - "$SCRIPTS" <<'PY'
import pathlib, sys, tempfile
sys.path.insert(0, sys.argv[1])
from registry.config import Config
from registry.model import ExternalRef, Task
from registry.providers.base import ProviderError, WriteGate
from registry.providers.github import GitHubProvider
from registry.providers.local import LocalMarkdownProvider

root = tempfile.mkdtemp()
config = Config(root=root)
local = LocalMarkdownProvider(config, WriteGate(apply=True))
task = local.create_task(Task(id="held.one", title="Original", labels=("bug",), summary="Keep me"))
path = pathlib.Path(root, "tasks/details/held.one.md")
with path.open("a", encoding="utf-8") as handle:
    handle.write("\n## Human notes\n\nbyte-for-byte marker\n")
before = path.read_text(encoding="utf-8")
local.add_labels(task, ("needs-investigation", "bug"))
local.add_labels(local.get_task(task.external), ("Needs-Investigation",))
after = path.read_text(encoding="utf-8")
print("local-labels:", local.get_task(task.external).labels)
print("local-preserved:", before.replace("- labels: bug", "- labels: bug, needs-investigation") == after)
print("local-case-deduped:", local.get_task(task.external).labels == ("bug", "needs-investigation"))

class RecordingGitHub(GitHubProvider):
    def __init__(self):
        super().__init__(Config(root=".", repository="o/r"), WriteGate(apply=True, require_approval=False))
        self.commands = []
    def _run(self, command, check=True, input=None):
        self.commands.append((list(command), input))
        if "/labels?" in command[2]:
            return 0, '[{"name": "bug"}, {"name": "needs-investigation"}]'
        return 0, "[]"

github = RecordingGitHub()
external = Task(id="held.two", title="Do not replace", labels=("bug",),
                external=ExternalRef("github", "42", "https://github.com/o/r/issues/42"))
github.add_labels(external, ("needs-investigation",))
command, body = github.commands[-1]
print("github-add:", command[2:5] == ["--method", "POST", "repos/o/r/issues/42/labels"]
      and body == '{"labels": ["needs-investigation"]}')
print("github-no-body:", command[5:] == ["--input", "-"] and "body" not in body and "title" not in body)
case_labels = github._writable_labels(
    external.with_(kind="bug", labels=("Bug", "Needs-Investigation"))
)
print("github-canonical-case:", case_labels == ("bug", "needs-investigation"))
try:
    github.add_labels(external, ("missing-label",))
except ProviderError as exc:
    print("github-missing:", "missing-label" in str(exc))
PY
)"
assert_contains "$label_only" "local-labels: ('bug', 'needs-investigation')" \
  "AC4: local additive labeling retains unrelated labels"
assert_contains "$label_only" "local-preserved: True" \
  "AC4: local additive labeling changes only the canonical labels header"
assert_contains "$label_only" "local-case-deduped: True" \
  "AC4: local label identity is case-insensitive and never duplicates the hold"
assert_contains "$label_only" "github-add: True" \
  "AC4: GitHub additive labeling targets only the requested label"
assert_contains "$label_only" "github-no-body: True" \
  "AC4: GitHub additive labeling sends no title or body replacement"
assert_contains "$label_only" "github-canonical-case: True" \
  "AC4: GitHub resolves case-insensitive labels to provider-canonical spelling"
assert_contains "$label_only" "github-missing: True" \
  "AC11: GitHub refuses an unknown hold label instead of silently dropping it"

structured_upsert="$("$PY" - "$SCRIPTS" <<'PY'
import pathlib, sys, tempfile
sys.path.insert(0, sys.argv[1])
import registry.upsert as upsert
from registry.config import Config
from registry.model import ExternalRef, Task
from registry.providers.base import ProviderStatus, WriteGate

class FakeProvider:
    name = "github"
    def __init__(self, existing=None, explode=False):
        self.gate = WriteGate(apply=True, require_approval=False)
        self.tasks = [] if existing is None else [existing]
        self.explode = explode
        self.creates = 0
        self.updates = 0
    def discover(self):
        return ProviderStatus(True, "fixture")
    def list_tasks(self):
        return list(self.tasks)
    def get_task(self, reference):
        return self.tasks[0]
    def create_task(self, task):
        self.creates += 1
        if self.explode:
            raise RuntimeError("delivery acknowledgement lost")
        written = task.with_(external=ExternalRef("github", "91", "https://github.com/o/r/issues/91"))
        self.tasks = [written]
        return written
    def update_task(self, task):
        self.updates += 1
        self.tasks = [task]
        return task

def registry_for(provider):
    root = tempfile.mkdtemp()
    pathlib.Path(root, "tasks").mkdir()
    pathlib.Path(root, "tasks/todo.md").write_text("# Tasks\n", encoding="utf-8")
    config = Config(root=root, provider="github", repository="o/r")
    return type("Registry", (), {"config": config, "provider": provider})()

incoming = Task(id="routine-blocker.src-test-py.launch", title="Launch blocker",
                labels=("bug",), evidence=("new",))
held = incoming.with_(labels=("bug", "area/test", "needs-investigation"), evidence=("old",),
                      external=ExternalRef("github", "80", "u"))
held_provider = FakeProvider(held)
held_result = upsert.upsert_task_result(registry_for(held_provider), incoming, apply=True)
print("held:", held_result.disposition, held_result.task.external.id,
      held_provider.creates, held_provider.updates, held_result.task.labels)

terminal = held.with_(status="done", labels=("bug", "area/test"))
terminal_provider = FakeProvider(terminal)
terminal_result = upsert.upsert_task_result(registry_for(terminal_provider), incoming, apply=True)
print("terminal:", terminal_result.disposition, terminal_result.task.status,
      terminal_provider.creates, terminal_provider.updates)

class LateHoldProvider(FakeProvider):
    def __init__(self, normal, held_task):
        super().__init__(normal)
        self.held_task = held_task
        self.reads = 0
    def list_tasks(self):
        self.reads += 1
        return [self.held_task if self.reads > 1 else self.tasks[0]]

late_provider = LateHoldProvider(incoming.with_(external=held.external), held)
late_result = upsert.upsert_task_result(registry_for(late_provider), incoming, apply=True)
print("late-held:", late_result.disposition, late_provider.reads, late_provider.updates)

unknown_provider = FakeProvider(explode=True)
unknown_result = upsert.upsert_task_result(registry_for(unknown_provider), incoming, apply=True)
print("unknown:", unknown_result.disposition, unknown_result.code, unknown_provider.creates)

published_provider = FakeProvider()
published_registry = registry_for(published_provider)
original_sync = upsert._sync_index
upsert._sync_index = lambda config, task: (_ for _ in ()).throw(OSError("index disk full"))
try:
    published_result = upsert.upsert_task_result(published_registry, incoming, apply=True)
finally:
    upsert._sync_index = original_sync
print("published:", published_result.disposition, published_result.code,
      published_result.task.external.id, published_result.readback.external.id,
      "index disk full" in published_result.detail)

merged, _ = upsert._merge(held, incoming)
print("labels-preserved:", merged.labels)
PY
)"
assert_contains "$structured_upsert" "held: existing-held 80 0 0 ('bug', 'area/test', 'needs-investigation')" \
  "AC6: a held blocker is reused without mutation or duplication"
assert_contains "$structured_upsert" "terminal: existing-terminal done 0 0" \
  "AC6: a terminal blocker is reused without reopening"
assert_contains "$structured_upsert" "late-held: existing-held 2 0" \
  "AC6: the immediate pre-write lookup honors a concurrent human hold"
assert_contains "$structured_upsert" "unknown: unknown 1 1" \
  "AC12: an ambiguous create failure is unknown and is attempted once"
assert_contains "$structured_upsert" "published: external 1 91 91 True" \
  "AC12: confirmed external publication survives a separate index failure"
assert_contains "$structured_upsert" "labels-preserved: ('bug', 'area/test', 'needs-investigation')" \
  "AC7: ordinary merging preserves all established labels"
fi
end_case

# =============================================================================
# 14. Registry-area primitives (specs/test-suite-aposd.md AC 9)
# =============================================================================
if begin_case "14. Registry-area primitives"; then
# The registry-area files (the seven test-task-registry-*.sh among them) share one harness. None keeps a private
# cleanup, fixture or repository constructor or Python wrapper; every one names
# its artefact through the library, so tests/affected.sh selects it on a change to
# the registry's model. The suite-wide rules (counter arithmetic, present/gone,
# PATH, interpreter environment, temp directory, hand-made repository) are
# swept once, over every file, in tests/test-lib.sh § invariants. The sweep is
# run against a control line that carries the pattern, so an empty sweep cannot
# be a pattern that stopped matching.
AREA_NAMES=(test-task-registry-model test-task-registry-config test-task-registry-providers test-task-registry-cli test-task-registry-regressions test-task-registry-regressions-github test-task-registry-structure
  test-routine-selectors test-routine-skills
  test-routines-contract test-routine-reproduction-e2e test-lane-catalogue
  test-sweep-handoff test-sweep-routines test-task-closes test-task-escalation
  test-closure test-go-lanes)
area_files=()
for area_test in "${AREA_NAMES[@]}"; do area_files+=("$REPO/tests/$area_test.sh"); done
assert_eq "18" "${#area_files[@]}" "Primitives: the registry area is eighteen files"
for area_file in "${area_files[@]}"; do
  assert_file_exists "$area_file" "Primitives: ${area_file##*/} exists"
done

area_control="$(fixture_dir)/control.sh"
printf '%s\n' 'new_fixture() { :; }' > "$area_control"
assert_sweep_empty "Primitives: no private cleanup, fixture, repository or Python wrapper" "$area_control" -- \
  grep -nE -e '^(cleanup|new_fixture|new_repo|new_dir|pyreg|pyreg_with|run_cli)\(\)' -- "${area_files[@]}"

# Selection by artefact path: a change to registry/model.py must reach every
# file, so each declares a path that contains it.
model_py=.agents/skills/task-registry/scripts/registry/model.py
covering_model="$(bash "$REPO/tests/affected.sh" --covering "$model_py" -- "${area_files[@]#"$REPO"/}")"
for area_file in "${area_files[@]}"; do
  assert_contains $'\n'"$covering_model"$'\n' $'\n'"tests/${area_file##*/}"$'\n' \
    "Primitives: ${area_file##*/} is selected by a change to registry/model.py"
done
fi
end_case

finish
