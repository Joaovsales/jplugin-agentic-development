#!/bin/bash
# tests/test-task-registry-providers.sh — contract tests for the provider-agnostic task registry:
# the provider contract, the local provider and the GitHub provider.
#
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-providers.sh runs only the cases whose name matches.
. "$(dirname "$0")/lib.sh"

py_module .agents/skills/task-registry/scripts
SCRIPTS="${PYTHONPATH%%:*}"   # py_module puts the declared directory first
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
  fixture_copy task-registry/task-tracking.md "$1/docs/task-tracking.md"
  sed -i '$d' "$1/docs/task-tracking.md"
  printf '\n[status]\nin_progress = label:now\n```\n' >> "$1/docs/task-tracking.md"
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

# =============================================================================
# 5. Provider contract — every adapter, same checks
# =============================================================================
if begin_case "5. Provider contract"; then
contract_out="$("$PY" - <<'EOF'
import inspect
from registry.config import Config
from registry.providers import PROVIDER_CLASSES, build_provider
from registry.providers.base import TrackerProvider, WriteGate, WriteNotAuthorized

REQUIRED = [
    "discover", "list_tasks", "get_task", "create_task", "update_task",
    "close_task", "comment", "link_parent", "add_dependency", "resolve_reference",
]
CAPABILITIES = [
    "native_hierarchy", "native_dependencies", "comments", "labels",
    "offline", "atomic_updates",
]

print("providers=" + ",".join(sorted(PROVIDER_CLASSES)))
for name in sorted(PROVIDER_CLASSES):
    provider = build_provider(name, Config(root="."), WriteGate(apply=False))
    missing = [m for m in REQUIRED if not callable(getattr(provider, m, None))]
    print(f"{name}-interface-complete=" + str(not missing))
    caps = [c for c in CAPABILITIES if not hasattr(provider.capabilities, c)]
    print(f"{name}-capabilities-declared=" + str(not caps))
    print(f"{name}-offline=" + str(provider.capabilities.offline))
    print(f"{name}-native-deps=" + str(provider.capabilities.native_dependencies))
    try:
        provider.gate.authorize("create issue", name)
        print(f"{name}-gate=open-without-apply")
    except WriteNotAuthorized as exc:
        print(f"{name}-gate-refused={exc}")

# The gate stays shut when the project requires approval and none was given.
gate = WriteGate(apply=True, require_approval=True, approved=False)
try:
    gate.authorize("create issue", "github")
    print("approval-gate=open")
except WriteNotAuthorized as exc:
    print(f"approval-gate-refused={exc}")
gate_ok = WriteGate(apply=True, require_approval=True, approved=True)
gate_ok.authorize("create issue", "github")
print("approved-gate=open")
EOF
)"
assert_contains "$contract_out" "providers=github,local" \
  "Contract: two providers are registered by name"
for provider in github local; do
  assert_contains "$contract_out" "$provider-interface-complete=True" \
    "Contract: $provider implements all ten interface operations"
  assert_contains "$contract_out" "$provider-capabilities-declared=True" \
    "Contract: $provider declares all six capabilities"
  assert_contains "$contract_out" "$provider-gate-refused=$provider: refusing to create issue — dry-run is the default" \
    "Contract: $provider refuses a write without --apply, by name"
done
assert_contains "$contract_out" "local-offline=True" "Contract: local declares offline support"
assert_contains "$contract_out" "github-offline=False" "Contract: github declares no offline support"
assert_contains "$contract_out" "github-native-deps=False" \
  "Contract: github declares it has no native dependency links"
assert_contains "$contract_out" "local-native-deps=True" \
  "Contract: local declares native dependency links"
assert_contains "$contract_out" "approval-gate-refused=github: refusing to create issue — external writes need approval" \
  "Contract: --apply alone does not satisfy require_write_approval"
assert_contains "$contract_out" "approved-gate=open" \
  "Contract: --apply plus --approve opens the gate"

github_reference_out="$("$PY" - <<'EOF'
from registry.config import Config
from registry.providers.base import ProviderError
from registry.providers.github import GitHubProvider

provider = GitHubProvider(Config(root=".", repository="owner/repo"))
print("own=" + provider.resolve_reference("https://github.com/owner/repo/issues/42").id)
try:
    provider.resolve_reference("https://github.com/other/repo/issues/42")
    print("foreign=accepted")
except ProviderError as exc:
    print("foreign=" + str(exc))
clean = provider._to_task({"number": 1, "title": "clean", "state": "open", "html_url": ""})


def pull(state):
    return {"event": "cross-referenced", "source": {"type": "issue", "issue": {
        "number": 9, "state": state, "body": "", "pull_request": {"merged_at": None},
        "repository_url": "https://api.github.com/repos/owner/repo"}}}


def linked(events):
    provider._json = lambda command, input=None: events
    task = provider._to_task({"number": 2, "title": "linked", "state": "open",
                              "html_url": "https://github.com/owner/repo/issues/2"})
    return (provider.linked_pr_state(task) or {}).get("unresolved_linked_pr", "unknown")


print("clean-pr=" + linked([]))
print("open-pr=" + linked([pull("open")]))
print("unread-pr=" + linked([pull(None)]))
print("plain-read=" + clean.extra.get("unresolved_linked_pr", "unset"))
print("identity=" + clean.extra.get("registry_identity", "stable"))
EOF
)"
assert_contains "$github_reference_out" "own=42" \
  "GitHub: canonical URLs for the configured repository resolve"
assert_contains "$github_reference_out" "foreign=github: issue URL belongs to other/repo, not owner/repo" \
  "GitHub: a foreign repository URL is refused instead of retargeted"
assert_contains "$github_reference_out" "clean-pr=false" \
  "GitHub: an empty timeline explicitly attests no unresolved PR"
assert_contains "$github_reference_out" "open-pr=true" \
  "GitHub: an open cross-referencing PR is reported as unresolved"
assert_contains "$github_reference_out" "unread-pr=true" \
  "GitHub: a cross-referencing PR whose state is missing counts as unresolved"
assert_contains "$github_reference_out" "plain-read=unset" \
  "GitHub: a plain read carries no linked-PR state -- only select's read looks it up"
assert_contains "$github_reference_out" "identity=provisional-title-slug" \
  "GitHub: an unmanaged issue exposes its provisional identity"
fi
end_case

# =============================================================================
# 6. Local provider — the full lifecycle, entirely offline
# =============================================================================
if begin_case "6. Local provider"; then
F_LOCAL="$(registry_project)"
write_index "$F_LOCAL"
local_out="$(cd "$F_LOCAL" && "$PY" - <<'EOF'
from registry.config import load_config
from registry.model import Task
from registry.providers import build_provider
from registry.providers.base import WriteGate

config = load_config(".")
provider = build_provider("local", config, WriteGate(apply=True, require_approval=False))
print("available=" + str(provider.discover().available))

parent = provider.create_task(Task(id="epic.recipes", title="Recipe epic", kind="epic"))
child = provider.create_task(
    Task(id="recipe.color-lut", title="Colour LUT loader", kind="feature",
         priority="high", labels=("area/color", "now"), summary="palette mapping",
         acceptance_criteria=("8-bit sources load", "no colour shift"))
)
blocked = provider.create_task(Task(id="recipe.morph-live-grid", title="Morph live grid", kind="feature"))
print("external=" + child.external.display() + " " + child.external.url)

link = provider.link_parent(child, parent)
dep = provider.add_dependency(blocked, child)
print("parent-native=" + str(link.native))
print("dep-native=" + str(dep.native))
provider.comment(child, "Reviewed with the render team")
provider.close_task(parent, "done")

reloaded = {task.id: task for task in provider.list_tasks()}
print("count=" + str(len(reloaded)))
lut = reloaded["recipe.color-lut"]
print("labels=" + ",".join(lut.labels))
print("priority=" + str(lut.priority))
print("parent=" + str(lut.parent))
print("criteria=" + "|".join(lut.acceptance_criteria))
print("summary=" + lut.summary)
print("epic-status=" + reloaded["epic.recipes"].status)
print("deps=" + ",".join(reloaded["recipe.morph-live-grid"].depends_on))
import io, os
body = io.open(os.path.join("tasks/details", "recipe.color-lut.md"), encoding="utf-8").read()
print("comment-kept=" + str("Reviewed with the render team" in body))
EOF
)"
assert_contains "$local_out" "available=True" "Local: the provider is always available"
assert_contains "$local_out" "external=local:recipe.color-lut tasks/details/recipe.color-lut.md" \
  "Local: the external reference is the detail file path"
assert_contains "$local_out" "parent-native=True" "Local: parent links are native to this format"
assert_contains "$local_out" "dep-native=True" "Local: dependency links are native to this format"
assert_contains "$local_out" "count=3" "Local: all three tasks round-trip through disk"
assert_contains "$local_out" "labels=area/color,now" "Local: labels survive the round trip"
assert_contains "$local_out" "priority=high" "Local: priority survives the round trip"
assert_contains "$local_out" "parent=epic.recipes" "Local: the parent link survives the round trip"
assert_contains "$local_out" "criteria=8-bit sources load|no colour shift" \
  "Local: acceptance criteria live in the detail file, not the index"
assert_contains "$local_out" "epic-status=done" "Local: close_task persists a terminal status"
assert_contains "$local_out" "deps=recipe.color-lut" "Local: the dependency survives the round trip"
assert_contains "$local_out" "comment-kept=True" "Local: a comment is appended and preserved"
assert_file_exists "$F_LOCAL/tasks/details/recipe.color-lut.md" \
  "Local: detail files land under the configured local_detail_dir"
todo_after_local="$(cat "$F_LOCAL/tasks/todo.md")"
assert_not_contains "$todo_after_local" "8-bit sources load" \
  "Local: acceptance criteria never leak into the index"
fi
end_case

# =============================================================================
# 7. GitHub provider — label vocabulary, status, identity, gated writes
# =============================================================================
if begin_case "7. GitHub provider"; then
F_GH="$(registry_repo)"
write_index "$F_GH"
write_github_config "$F_GH"
install_gh_mock "$F_GH"
git_init_github_remote "$F_GH"
# A local row deliberately sharing issue #44's title, with a different id and no
# link: if anything ever matches on title, this row silently disappears.
printf -- '- [ ] Decide on dither strategy <!-- task-id: local.dither-note --> — different task, same words\n' \
  >> "$F_GH/tasks/todo.md"

gh_norm="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-norm.log" "$PY" - <<'EOF'
from registry.config import load_config
from registry.providers import build_provider
from registry.providers.base import WriteGate

provider = build_provider("github", load_config("."), WriteGate())
tasks = {task.id: task for task in provider.list_tasks()}
for task_id in sorted(tasks):
    task = tasks[task_id]
    print(f"{task_id}|kind={task.kind}|status={task.status}|priority={task.priority}"
          f"|area={task.area}|labels={','.join(task.labels)}|ref={task.external.id}")
print("ids-not-numbers=" + str(all(not t.id.isdigit() for t in tasks.values())))
EOF
)"
assert_contains "$gh_norm" "recipe.morph-live-grid|kind=feature|status=in_progress|priority=high|area=render|labels=enhancement,now,area/render,tech-debt|ref=42" \
  "GitHub: 'enhancement'->feature, 'now'->high, area/* read, unmapped 'tech-debt' preserved"
assert_contains "$gh_norm" "recipe.color-lut|kind=bug|status=done|priority=None|area=color|labels=bug,area/color|ref=43" \
  "GitHub: 'bug'->bug, closed->done, no queue label leaves priority unset"
assert_contains "$gh_norm" "render.dither-strategy|kind=decision|status=open|priority=medium|area=render|labels=design-decision,next,area/render|ref=44" \
  "GitHub: 'design-decision'->decision, 'next'->medium, open->open"
assert_contains "$gh_norm" "ids-not-numbers=True" \
  "GitHub: identity comes from the body metadata, never from the issue number"
assert_not_contains "$gh_norm" "ref=45" \
  "GitHub (AC4): an issues entry carrying a pull_request key is a pull request, not a task"
assert_contains "$(cat "$F_GH/gh-norm.log")" "api repos/fixture-owner/fixture-repo/issues?state=all&per_page=100&page=1" \
  "GitHub (AC4): issues are listed through the REST issues route, paged"

# The write gate itself survives the sync engine: `upsert` is now the command
# that reaches a provider, so it is where "unreachable means refuse, never
# half-write" is pinned.
gh_unauth_write="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-unauth2.log" GH_MOCK_UNAUTH=1 \
  reg upsert ops.unreachable --repo "$F_GH" --title 'Written while offline' --apply --approve 2>&1)"
gh_unauth_write_code=$?
# `upsert` degrades where `publish` refused, and that difference is deliberate:
# the local record is the point of the command, so an unreachable tracker must
# not lose it. What it may never do is go quiet about the half that did not
# happen.
assert_eq "0" "$gh_unauth_write_code" \
  "GitHub: an unreachable provider does not lose the local record"
assert_contains "$gh_unauth_write" "local-pending" \
  "GitHub: the record is marked as not yet published"
assert_contains "$gh_unauth_write" "external publication pending" \
  "GitHub: the unpublished half is reported, never silently dropped"
assert_not_contains "$(cat "$F_GH/gh-unauth2.log")X" "--method POST" \
  "GitHub: no create call is attempted while unauthenticated"

# A local-pending write must not replace a previously published tracker address.
# The fake external provider deliberately cannot find the task by stable ID: the
# second run can succeed only if upsert consults the preserved index reference.
F_PUBLISHED_REF="$(registry_project)"
write_index "$F_PUBLISHED_REF"
sed -i 's|— ship the live grid morph (blocked-by: recipe.color-lut)|— ship the live grid morph ([#42](https://github.com/fixture-owner/fixture-repo/issues/42)) (blocked-by: recipe.color-lut)|' "$F_PUBLISHED_REF/tasks/todo.md"
published_ref_out="$(cd "$F_PUBLISHED_REF" && "$PY" - <<'EOF'
from registry.config import load_config
from registry.model import Task
from registry.providers.base import ProviderStatus, WriteGate
from registry.upsert import upsert_task, upsert_task_result

class FakeGithub:
    name = "github"

    def __init__(self, config):
        self.config = config
        self.gate = WriteGate(apply=True, require_approval=True, approved=False)
        self.fetched = []
        self.created = []
        self.updated = []

    def discover(self):
        return ProviderStatus(True, "fake GitHub")

    def list_tasks(self):
        return []

    def get_task(self, reference):
        self.fetched.append(reference)
        return Task(id="remote-title-derived-id", title="Published task", external=reference)

    def create_task(self, task):
        self.created.append(task)
        return task

    def update_task(self, task):
        self.updated.append(task)
        return task

config = load_config(".")
provider = FakeGithub(config)
registry = type("Registry", (), {"config": config, "provider": provider})()
task = Task(id="recipe.morph-live-grid", title="Morph live grid recipe")

first_result = upsert_task_result(registry, task, apply=True)
first_lines, first_code = first_result.lines, first_result.code
provider.gate.approved = True
second_lines, second_code = upsert_task(registry, task, apply=True)
index = open("tasks/todo.md", encoding="utf-8").read()
print("first-code=" + str(first_code))
print("first-output=" + " | ".join(first_lines))
print("first-result-ref=" + first_result.reference_summary())
print("first-readback-ref=" + first_result.readback.external.display())
print("second-code=" + str(second_code))
print("second-output=" + " | ".join(second_lines))
print("fetched=" + ",".join(ref.display() for ref in provider.fetched))
print("created=" + str(len(provider.created)))
print("updated=" + str(len(provider.updated)))
print("updated-ref=" + provider.updated[0].external.display())
print("index-has-github=" + str("([#42](https://github.com/fixture-owner/fixture-repo/issues/42))" in index))
print("index-has-local=" + str("tasks/details/recipe.morph-live-grid.md" in index))
EOF
)"
assert_contains "$published_ref_out" "first-code=0" \
  "Upsert reference preservation: approval-gated fallback succeeds"
assert_contains "$published_ref_out" "local-pending" \
  "Upsert reference preservation: first run uses the local-pending destination"
assert_contains "$published_ref_out" "first-result-ref=recipe.morph-live-grid (publication pending)" \
  "AC7: structured fallback truthfully identifies pending publication"
assert_contains "$published_ref_out" "first-readback-ref=github:42" \
  "AC7: structured fallback retains the published reference after local readback"
assert_contains "$published_ref_out" "index-has-github=True" \
  "Upsert reference preservation: fallback keeps the original GitHub link"
assert_contains "$published_ref_out" "index-has-local=False" \
  "Upsert reference preservation: fallback does not replace the issue link with a local path"
assert_contains "$published_ref_out" "fetched=github:42" \
  "Upsert reference preservation: approved run consults the preserved issue reference"
assert_contains "$published_ref_out" "created=0" \
  "Upsert reference preservation: approved run does not create a duplicate"
assert_contains "$published_ref_out" "updated=1" \
  "Upsert reference preservation: approved run updates the original task"
assert_contains "$published_ref_out" "updated-ref=github:42" \
  "Upsert reference preservation: the original issue remains the update address"
fi
end_case

finish
