#!/bin/bash
# tests/test-task-registry.sh — contract tests for the provider-agnostic task registry.
#
# WHAT THIS PINS
#
# The registry is three layers (normalized model, provider adapters, reconciler)
# and the value of the split is entirely in what each layer refuses to know. So
# the tests are written against the seams rather than the internals:
#
#   * the model is exercised in-process (vocabulary, identity, lossless body)
#   * every provider is run through the SAME contract block, so a fourth adapter
#     inherits the checks instead of re-deriving them
#   * GitHub runs against a `gh` mock first on PATH — real argv construction
#   * Jira runs against a real HTTP server on a real socket — real auth headers,
#     real error bodies, real redaction
#   * everything else runs through the CLI, which is what skills actually call
#
# Zero external dependencies beyond git + python3. Every scenario builds a
# throwaway repo under a temp dir and cleans it up on exit.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO/.agents/skills/task-registry"
SCRIPTS="$SKILL/scripts"
CLI="$SCRIPTS/task-registry.py"
FIXTURES="$REPO/tests/fixtures/task-registry"

if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
elif command -v py >/dev/null 2>&1; then
  PY=py
else
  printf '  FAIL no python interpreter found (python3/python/py)\n'
  exit 1
fi

TMP_DIRS=()
JIRA_PIDS=()
cleanup() {
  local pid d
  for pid in "${JIRA_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  for d in "${TMP_DIRS[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT

new_fixture() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/task-registry-test.XXXXXX")"
  TMP_DIRS+=("$d")
  mkdir -p "$d/tasks" "$d/specs" "$d/docs"
  printf '%s' "$d"
}

# Run the CLI the way a skill does.
run() { "$PY" "$CLI" "$@"; }

# Run a snippet against the package, the way another Python caller would.
# PYTHONDONTWRITEBYTECODE mirrors the CLI's own `sys.dont_write_bytecode`: a
# __pycache__ inside the canonical skills tree breaks tests/test-skill-parity.sh,
# so no entry point to this package may leave one behind.
pyreg() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" -; }

# --- shared fixture content --------------------------------------------------

write_index() {
  cat > "$1/tasks/todo.md" <<'EOF'
# Task Plan

## Plan: Recipe morphs
> Spec: specs/morph-recipes.md

- [ ] Morph live grid recipe <!-- task-id: recipe.morph-live-grid --> — ship the live grid morph (blocked-by: recipe.color-lut)
- [ ] Colour LUT loader <!-- task-id: recipe.color-lut --> — palette mapping for 8-bit sources
- [!] Verify nightly render deploy <!-- task-id: ops.verify-deploy --> — smoke the rollout
[x] TDD: legacy checkbox row that predates the registry -> impl detail
EOF
}

write_github_config() {
  cat > "$1/docs/task-tracking.md" <<'EOF'
# Task tracking

```ini
[tracker]
provider = github
repository = fixture-owner/fixture-repo
require_write_approval = false

[status]
in_progress = label:now
EOF
  printf '```\n' >> "$1/docs/task-tracking.md"
}

install_gh_mock() {
  local d="$1"
  mkdir -p "$d/bin" "$d/ghdata"
  cp "$FIXTURES/gh" "$d/bin/gh"
  chmod +x "$d/bin/gh"
  cat > "$d/ghdata/labels.json" <<'EOF'
[{"name":"bug"},{"name":"enhancement"},{"name":"design-decision"},{"name":"question"},
 {"name":"now"},{"name":"next"},{"name":"documentation"},{"name":"tech-debt"},
 {"name":"area/render"},{"name":"area/color"}]
EOF
  cat > "$d/ghdata/issues.json" <<'EOF'
[
 {"number":42,"title":"Morph live grid recipe","state":"OPEN",
  "url":"https://github.com/fixture-owner/fixture-repo/issues/42",
  "labels":[{"name":"enhancement"},{"name":"now"},{"name":"area/render"},{"name":"tech-debt"}],
  "assignees":[],"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-02T00:00:00Z",
  "body":"Ship the live grid morph.\n\n<!-- task-registry:begin -->\ntask-id: recipe.morph-live-grid\nkind: feature\ndepends-on: recipe.color-lut\n<!-- task-registry:end -->\n"},
 {"number":43,"title":"Colour LUT loader crashes on 8-bit input","state":"CLOSED",
  "url":"https://github.com/fixture-owner/fixture-repo/issues/43",
  "labels":[{"name":"bug"},{"name":"area/color"}],
  "assignees":[],"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-03T00:00:00Z",
  "body":"<!-- task-registry:begin -->\ntask-id: recipe.color-lut\nkind: bug\n<!-- task-registry:end -->\n"},
 {"number":44,"title":"Decide on dither strategy","state":"OPEN",
  "url":"https://github.com/fixture-owner/fixture-repo/issues/44",
  "labels":[{"name":"design-decision"},{"name":"next"},{"name":"area/render"}],
  "assignees":[],"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-04T00:00:00Z",
  "body":"Which dither?\n\n<!-- task-registry:begin -->\ntask-id: render.dither-strategy\nkind: decision\n<!-- task-registry:end -->\n"}
]
EOF
  cp "$d/ghdata/issues.json" "$d/ghdata/issue-42.json.all"
  cat > "$d/ghdata/issue-42.json" <<'EOF'
{"number":42,"title":"Morph live grid recipe","state":"OPEN",
 "url":"https://github.com/fixture-owner/fixture-repo/issues/42",
 "labels":[{"name":"enhancement"},{"name":"now"},{"name":"area/render"},{"name":"tech-debt"}],
 "assignees":[],"createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-02T00:00:00Z",
 "body":"Ship the live grid morph.\n\n<!-- task-registry:begin -->\ntask-id: recipe.morph-live-grid\nkind: feature\ndepends-on: recipe.color-lut\n<!-- task-registry:end -->\n"}
EOF
  rm -f "$d/ghdata/issue-42.json.all"
  printf '100\n' > "$d/ghdata/next-number"
}

gh_env() {
  local d="$1"
  export PATH="$d/bin:$PATH"
  export GH_MOCK_DIR="$d/ghdata"
  export GH_MOCK_LOG="$d/gh.log"
  : > "$GH_MOCK_LOG"
}

git_init_github_remote() {
  git -C "$1" init -q
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "Test"
  git -C "$1" remote add origin https://github.com/fixture-owner/fixture-repo.git
}

free_port() {
  "$PY" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'
}

start_fake_jira() {
  local port="$1"; shift
  "$PY" "$FIXTURES/fake-jira.py" "$port" "$@" &
  JIRA_PIDS+=("$!")
  local attempt=0
  while [ "$attempt" -lt 50 ]; do
    if "$PY" -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1',$port))==0 else 1)"; then
      return 0
    fi
    attempt=$((attempt + 1))
    "$PY" -c 'import time; time.sleep(0.1)'
  done
  printf '  FAIL fake jira did not start on port %s\n' "$port"
  return 1
}

# =============================================================================
# 1. Domain model — canonical vocabulary, validation, identity
# =============================================================================
model_out="$(pyreg <<'EOF'
from registry.model import (
    KINDS, STATUSES, PRIORITIES, Task, TaskModelError, ExternalRef,
    render_metadata_block, parse_metadata_block, upsert_metadata_block,
)

print("kinds=" + ",".join(KINDS))
print("statuses=" + ",".join(STATUSES))
print("priorities=" + ",".join(PRIORITIES))

for bad_field, value in (("kind", "chore"), ("status", "wip"), ("priority", "urgent")):
    try:
        Task(id="t", title="T", **{bad_field: value})
        print(f"accepted-bad-{bad_field}")
    except TaskModelError as exc:
        print(f"rejected-{bad_field}: {exc}")

task = Task(
    id="recipe.morph-live-grid",
    title="Morph live grid recipe",
    kind="feature",
    status="in_progress",
    priority="high",
    labels=("area/render", "now", "tech-debt"),
    depends_on=("recipe.color-lut",),
    spec_path="specs/morph-recipes.md",
    external=ExternalRef("github", "42", "https://github.com/o/r/issues/42"),
)
print("id-not-number=" + str(task.id != task.external.id))
print("frozen=" + str(getattr(Task, "__dataclass_params__").frozen))

body = "Human prose nobody should touch.\n\n## Notes\n\n- a note\n"
merged = upsert_metadata_block(body, task)
print("body-preserved=" + str("Human prose nobody should touch." in merged and "- a note" in merged))
again = upsert_metadata_block(merged, task.with_(kind="bug"))
print("single-block=" + str(again.count("<!-- task-registry:begin -->")))
print("roundtrip-id=" + parse_metadata_block(again)["task-id"])
print("roundtrip-kind=" + parse_metadata_block(again)["kind"])
print("roundtrip-deps=" + ",".join(parse_metadata_block(again)["depends-on"]))
print("no-id-in-labels=" + str(all("task-id" not in label for label in task.labels)))
EOF
)"

assert_contains "$model_out" "kinds=epic,feature,bug,decision,research,operational,task" \
  "Model: canonical kinds are exactly the seven in the spec"
assert_contains "$model_out" "statuses=open,in_progress,blocked,done,cancelled" \
  "Model: canonical statuses are exactly the five in the spec"
assert_contains "$model_out" "priorities=high,medium,low" \
  "Model: canonical priorities are high/medium/low (unset is absence, not a value)"
assert_contains "$model_out" "rejected-kind: unknown kind: 'chore'" \
  "Model: an unknown kind is rejected by name, not coerced"
assert_contains "$model_out" "rejected-status: unknown status: 'wip'" \
  "Model: an unknown status is rejected by name, not coerced"
assert_contains "$model_out" "rejected-priority: unknown priority: 'urgent'" \
  "Model: an unknown priority is rejected by name, not coerced"
assert_contains "$model_out" "id-not-number=True" \
  "Model: the stable id is independent of the provider issue number"
assert_contains "$model_out" "frozen=True" \
  "Model: the task record is immutable"
assert_contains "$model_out" "body-preserved=True" \
  "Model: upserting the metadata block preserves every other line of the body"
assert_contains "$model_out" "single-block=1" \
  "Model: a second upsert replaces the block rather than appending a second one"
assert_contains "$model_out" "roundtrip-id=recipe.morph-live-grid" \
  "Model: the stable id survives a body round trip"
assert_contains "$model_out" "roundtrip-deps=recipe.color-lut" \
  "Model: dependencies survive a body round trip"
assert_contains "$model_out" "no-id-in-labels=True" \
  "Model: the stable id is never encoded as a label"

# =============================================================================
# 2. Local index — compact rows, legacy rows, malformed rows, byte preservation
# =============================================================================
F_INDEX="$(new_fixture)"
write_index "$F_INDEX"
cat >> "$F_INDEX/tasks/todo.md" <<'EOF'
- [ ]
- [?] unknown box character
EOF
cp "$F_INDEX/tasks/todo.md" "$F_INDEX/todo.before"

index_out="$(cd "$F_INDEX" && pyreg <<'EOF'
from registry.index import TaskIndex, load_index, render_row
from registry.model import ExternalRef, Task

index = load_index("tasks/todo.md", "tasks/todo.md")
print("rows=" + str(len(index.rows)))
print("problems=" + "|".join(p.render() for p in index.problems))
by_id = {row.task.id: row for row in index.rows}
morph = by_id["recipe.morph-live-grid"].task
print("title=" + morph.title)
print("summary=" + morph.summary)
print("deps=" + ",".join(morph.depends_on))
print("blocked-status=" + by_id["ops.verify-deploy"].task.status)
legacy = [row for row in index.rows if row.legacy]
print("legacy-count=" + str(len(legacy)))
print("legacy-status=" + legacy[0].task.status)
print("legacy-title=" + legacy[0].task.title)

rendered = render_row(
    Task(
        id="recipe.morph-live-grid", title="Morph live grid recipe", status="open",
        summary="ship the live grid morph", depends_on=("recipe.color-lut",),
        external=ExternalRef("github", "42", "https://github.com/o/r/issues/42"),
    )
)
print("rendered=" + rendered)
kind_row = render_row(Task(id="bug.routing", title="Preserve kind", kind="bug"), include_kind=True)
kind_task = TaskIndex("tasks/todo.md", kind_row + "\n").rows[0].task
print("kind-row=" + kind_row)
print("kind-roundtrip=" + kind_task.kind)
EOF
)"

assert_contains "$index_out" "rows=4" "Index: four well-formed rows parse (three compact, one legacy)"
assert_contains "$index_out" "title=Morph live grid recipe" "Index: title is separated from the summary"
assert_contains "$index_out" "summary=ship the live grid morph" "Index: one-line summary parses"
assert_contains "$index_out" "deps=recipe.color-lut" "Index: dependency marker parses"
assert_contains "$index_out" "blocked-status=blocked" "Index: '[!]' box reads as blocked"
assert_contains "$index_out" "legacy-count=1" "Index: a checkbox-only row still parses"
assert_contains "$index_out" "legacy-status=done" "Index: legacy '[x]' reads as done"
assert_contains "$index_out" "tasks/todo.md:10 — row has a status box but no title" \
  "Index: a titleless row is reported with file:line and a named defect"
assert_contains "$index_out" "tasks/todo.md:11 — unknown status box '[?]'" \
  "Index: an unknown box character is reported with file:line, not guessed at"
assert_contains "$index_out" \
  "rendered=- [ ] Morph live grid recipe <!-- task-id: recipe.morph-live-grid --> — ship the live grid morph ([#42](https://github.com/o/r/issues/42)) (blocked-by: recipe.color-lut)" \
  "Index: the canonical row carries box, title, id, summary, link, dependency — and nothing else"
assert_contains "$index_out" "kind-row=- [ ] Preserve kind <!-- task-id: bug.routing --> <!-- task-kind: bug -->" \
  "Index: candidate registration can opt into a canonical task-kind marker"
assert_contains "$index_out" "kind-roundtrip=bug" \
  "Index: an opted-in task kind survives the compact-row round trip"
assert_files_identical "$F_INDEX/tasks/todo.md" "$F_INDEX/todo.before" \
  "Index: parsing never writes to the file it read"

# =============================================================================
# 3. Configuration — parsing, pointer indirection, malformed input
# =============================================================================
F_CONF="$(new_fixture)"
write_index "$F_CONF"
mkdir -p "$F_CONF/.claude"
mkdir -p "$F_CONF/config"
cat > "$F_CONF/config/tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = jira
project = REG
local_detail_dir = tasks/details
require_write_approval = true

[labels.kind]
bug = bug
enhancement = feature
design-decision = decision
question = research

[labels.priority]
now = high
next = medium
EOF
printf '```\n' >> "$F_CONF/config/tracking.md"
printf 'Task tracking instructions: config/tracking.md\n' > "$F_CONF/AGENTS.md"

conf_out="$(cd "$F_CONF" && pyreg <<'EOF'
from registry.config import load_config, find_config_path

config = load_config(".")
print("source=" + str(config.source_path))
print("provider=" + str(config.provider))
print("project=" + config.project)
print("approval=" + str(config.require_write_approval))
print("kind-question=" + config.kind_labels.get("question", "(unmapped)"))
print("kind-bug=" + config.kind_labels["bug"])
print("priority-now=" + config.priority_labels["now"])
print("priority-none=" + str(config.priority_labels.get("someday", None)))
EOF
)"
assert_contains "$conf_out" "source=config/tracking.md" \
  "Config: the AGENTS.md pointer redirects discovery away from the default path"
assert_contains "$conf_out" "provider=jira" "Config: explicit provider is read"
assert_contains "$conf_out" "project=REG" "Config: project identifier is read"
assert_contains "$conf_out" "approval=True" "Config: require_write_approval is read"
assert_contains "$conf_out" "kind-question=research" \
  "Config: 'question' maps only because this project configured it"
assert_contains "$conf_out" "priority-now=high" "Config: queue label 'now' maps to priority high"
assert_contains "$conf_out" "priority-none=None" \
  "Config: an unmapped queue label leaves priority unset"

# defaults with no configuration at all
F_NOCONF="$(new_fixture)"
noconf_out="$(cd "$F_NOCONF" && pyreg <<'EOF'
from registry.config import load_config
config = load_config(".")
print("source=" + str(config.source_path))
print("provider=" + str(config.provider))
print("kinds=" + ",".join(f"{k}->{v}" for k, v in sorted(config.kind_labels.items())))
print("question-default=" + str(config.kind_labels.get("question")))
EOF
)"
assert_contains "$noconf_out" "source=None" "Config: an absent configuration is not an error"
assert_contains "$noconf_out" "provider=None" "Config: no provider is asserted without configuration"
assert_contains "$noconf_out" "bug->bug,design-decision->decision,enhancement->feature" \
  "Config: the shipped default mapping matches the repository's existing label vocabulary"
assert_contains "$noconf_out" "question-default=None" \
  "Config: 'question' is unmapped by default — it is ambiguous, so it needs configuring"

# malformed configuration fails loudly through the CLI
F_BADCONF="$(new_fixture)"
write_index "$F_BADCONF"
printf '# Tracking\n\nno fenced block here\n' > "$F_BADCONF/docs/task-tracking.md"
badconf_out="$(run reconcile --repo "$F_BADCONF" 2>&1)"
badconf_code=$?
assert_eq "1" "$badconf_code" "Config: a configuration file with no ini block exits non-zero"
assert_contains "$badconf_out" "no \`\`\`ini configuration block found" \
  "Config: the failure names what is missing"

F_UNKPROV="$(new_fixture)"
write_index "$F_UNKPROV"
printf '# T\n\n```ini\n[tracker]\nprovider = trello\n```\n' > "$F_UNKPROV/docs/task-tracking.md"
unkprov_out="$(run reconcile --repo "$F_UNKPROV" 2>&1)"
unkprov_code=$?
assert_eq "1" "$unkprov_code" "Config: an unknown provider exits non-zero"
assert_contains "$unkprov_out" "unknown provider 'trello'" "Config: the failure names the bad provider"

# =============================================================================
# 4. Provider selection precedence
# =============================================================================
F_SEL="$(new_fixture)"
write_index "$F_SEL"
sel_local="$(run doctor --repo "$F_SEL" 2>&1)"
assert_contains "$sel_local" "provider:       local" \
  "Selection: no configuration and no GitHub remote falls back to local"
assert_contains "$sel_local" "no configuration and no usable GitHub remote" \
  "Selection: the fallback states its reason"

# Jira credentials in the environment must NOT make Jira implicit.
sel_jira_env="$(JIRA_BASE_URL=https://example.atlassian.net JIRA_EMAIL=a@b.c \
  JIRA_API_TOKEN=zzz JIRA_PROJECT=REG run doctor --repo "$F_SEL" 2>&1)"
assert_contains "$sel_jira_env" "provider:       local" \
  "Selection: Jira is never selected implicitly, even with full credentials present"

F_SEL_GH="$(new_fixture)"
write_index "$F_SEL_GH"
git_init_github_remote "$F_SEL_GH"
install_gh_mock "$F_SEL_GH"
sel_gh="$(
  export PATH="$F_SEL_GH/bin:$PATH" GH_MOCK_DIR="$F_SEL_GH/ghdata" GH_MOCK_LOG="$F_SEL_GH/gh.log"
  run doctor --repo "$F_SEL_GH" 2>&1
)"
assert_contains "$sel_gh" "provider:       github" \
  "Selection: a GitHub remote plus authenticated gh selects github"
assert_contains "$sel_gh" "authenticated gh" "Selection: github selection states its reason"

sel_gh_unauth="$(
  export PATH="$F_SEL_GH/bin:$PATH" GH_MOCK_DIR="$F_SEL_GH/ghdata" \
    GH_MOCK_LOG="$F_SEL_GH/gh.log" GH_MOCK_UNAUTH=1
  run doctor --repo "$F_SEL_GH" 2>&1
)"
assert_contains "$sel_gh_unauth" "provider:       local" \
  "Selection: a GitHub remote with unauthenticated gh falls back to local"
assert_contains "$sel_gh_unauth" "gh is unavailable or unauthenticated" \
  "Selection: the unauthenticated fallback names the cause"

# =============================================================================
# 5. Provider contract — every adapter, same checks
# =============================================================================
contract_out="$(pyreg <<'EOF'
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
assert_contains "$contract_out" "providers=github,jira,local" \
  "Contract: three providers are registered by name"
for provider in github jira local; do
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

github_reference_out="$(pyreg <<'EOF'
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
clean = provider._to_task({
    "number": 1, "title": "clean", "state": "OPEN", "url": "",
    "closedByPullRequestsReferences": [],
})
open_pr = provider._to_task({
    "number": 2, "title": "open pr", "state": "OPEN", "url": "",
    "closedByPullRequestsReferences": [{"state": "OPEN"}],
})
print("clean-pr=" + clean.extra.get("unresolved_linked_pr", "unknown"))
print("open-pr=" + open_pr.extra.get("unresolved_linked_pr", "unknown"))
print("identity=" + clean.extra.get("registry_identity", "stable"))
EOF
)"
assert_contains "$github_reference_out" "own=42" \
  "GitHub: canonical URLs for the configured repository resolve"
assert_contains "$github_reference_out" "foreign=github: issue URL belongs to other/repo, not owner/repo" \
  "GitHub: a foreign repository URL is refused instead of retargeted"
assert_contains "$github_reference_out" "clean-pr=false" \
  "GitHub: an empty closing-PR set explicitly attests no unresolved PR"
assert_contains "$github_reference_out" "open-pr=true" \
  "GitHub: an open closing PR is reported as unresolved"
assert_contains "$github_reference_out" "identity=provisional-title-slug" \
  "GitHub: an unmanaged issue exposes its provisional identity"

# =============================================================================
# 6. Local provider — the full lifecycle, entirely offline
# =============================================================================
F_LOCAL="$(new_fixture)"
write_index "$F_LOCAL"
local_out="$(cd "$F_LOCAL" && pyreg <<'EOF'
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
assert_eq "yes" "$([ -f "$F_LOCAL/tasks/details/recipe.color-lut.md" ] && echo yes || echo no)" \
  "Local: detail files land under the configured local_detail_dir"
todo_after_local="$(cat "$F_LOCAL/tasks/todo.md")"
assert_not_contains "$todo_after_local" "8-bit sources load" \
  "Local: acceptance criteria never leak into the index"

# =============================================================================
# 7. GitHub provider — label vocabulary, status, identity, gated writes
# =============================================================================
F_GH="$(new_fixture)"
write_index "$F_GH"
write_github_config "$F_GH"
install_gh_mock "$F_GH"
git_init_github_remote "$F_GH"
# A local row deliberately sharing issue #44's title, with a different id and no
# link: if anything ever matches on title, this row silently disappears.
printf -- '- [ ] Decide on dither strategy <!-- task-id: local.dither-note --> — different task, same words\n' \
  >> "$F_GH/tasks/todo.md"

gh_norm="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-norm.log" pyreg <<'EOF'
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

gh_recon="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-recon.log" run reconcile --repo "$F_GH" 2>&1)"
gh_recon_code=$?
assert_eq "0" "$gh_recon_code" "GitHub: a read-only reconcile exits 0"
assert_contains "$gh_recon" "local.dither-note: 'Decide on dither strategy' exists only locally" \
  "GitHub: a row sharing a title with an issue is NOT matched to it"
assert_contains "$gh_recon" "possible-duplicate" \
  "GitHub: the title collision is surfaced as advisory, not resolved silently"
assert_contains "$gh_recon" "a matching title is not identity" \
  "GitHub: the advisory says outright that a title is not identity"
assert_contains "$gh_recon" "ops.verify-deploy: 'Verify nightly render deploy' exists only locally" \
  "GitHub: an unlinked local row is reported as publishable"
assert_contains "$gh_recon" "status-drift" \
  "GitHub: a configured in_progress label produces status drift against an open local row"
assert_contains "$gh_recon" "no native dependency links" \
  "GitHub: the missing dependency capability is stated, never emulated"
assert_not_contains "$gh_recon" "Ship the live grid morph." \
  "GitHub: reconcile output never reproduces an issue body"

gh_pub_dry="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-dry.log" run publish --repo "$F_GH" 2>&1)"
assert_contains "$gh_pub_dry" "mode: dry-run" "GitHub: publish defaults to dry-run"
assert_contains "$gh_pub_dry" "would-create" "GitHub: dry-run names what it would create"
assert_not_contains "$(cat "$F_GH/gh-dry.log")X" "issue create" \
  "GitHub: dry-run issues no create call to gh"

cp "$F_GH/tasks/todo.md" "$F_GH/todo.before-publish"
gh_pub="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-apply.log" run publish --repo "$F_GH" --apply --approve 2>&1)"
gh_pub_code=$?
gh_apply_log="$(cat "$F_GH/gh-apply.log")"
assert_eq "0" "$gh_pub_code" "GitHub: publish --apply exits 0 when every write succeeds"
assert_contains "$gh_apply_log" "issue create --repo fixture-owner/fixture-repo" \
  "GitHub: publish --apply calls gh issue create"
assert_contains "$gh_apply_log" "task-id: ops.verify-deploy" \
  "GitHub: the created issue body carries the stable id in the metadata block"
assert_not_contains "$gh_apply_log" "label create" \
  "GitHub: an ordinary sync never creates a label"
assert_not_contains "$gh_apply_log" "--add-label status" \
  "GitHub: no status label is invented"
assert_file_contains "$F_GH/tasks/todo.md" "([#100](https://github.com/fixture-owner/fixture-repo/issues/100))" \
  "GitHub: the new issue link is written back into the index row"
assert_file_contains "$F_GH/tasks/todo.md" "<!-- task-id: ops.verify-deploy -->" \
  "GitHub: the published row keeps its stable id"
published_index="$(cat "$F_GH/tasks/todo.md")"
assert_not_contains "$published_index" "smoke the rollout — smoke the rollout" \
  "GitHub: the rewritten row is not duplicated"

# partial failure: two rows to publish, every write rejected
F_GHFAIL="$(new_fixture)"
write_index "$F_GHFAIL"
write_github_config "$F_GHFAIL"
install_gh_mock "$F_GHFAIL"
ghfail_out="$(cd "$F_GHFAIL" && PATH="$F_GHFAIL/bin:$PATH" GH_MOCK_DIR="$F_GHFAIL/ghdata" \
  GH_MOCK_LOG="$F_GHFAIL/gh.log" GH_MOCK_FAIL=1 run publish --repo "$F_GHFAIL" --apply --approve 2>&1)"
ghfail_code=$?
assert_eq "1" "$ghfail_code" "GitHub: a failed write exits non-zero"
assert_contains "$ghfail_out" "Failures:" "GitHub: failures are reported in their own section"
assert_contains "$ghfail_out" "ops.verify-deploy:" "GitHub: the failure names the task that failed"
assert_contains "$ghfail_out" "422" "GitHub: the failure carries the provider's own error"

# unauthenticated gh: reads degrade, writes refuse
gh_unauth_read="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-unauth.log" GH_MOCK_UNAUTH=1 run reconcile --repo "$F_GH" 2>&1)"
gh_unauth_read_code=$?
assert_eq "0" "$gh_unauth_read_code" "GitHub: an offline read degrades rather than failing the run"
assert_contains "$gh_unauth_read" "reads degraded to local-only" \
  "GitHub: the degraded read says so out loud"
gh_unauth_write="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-unauth2.log" GH_MOCK_UNAUTH=1 run publish --repo "$F_GH" --apply --approve 2>&1)"
gh_unauth_write_code=$?
assert_eq "1" "$gh_unauth_write_code" "GitHub: an external write against an unreachable provider fails loudly"
assert_contains "$gh_unauth_write" "refusing to publish" \
  "GitHub: the refusal is explicit, not a silent no-op"
assert_not_contains "$(cat "$F_GH/gh-unauth2.log")X" "issue create" \
  "GitHub: no create call is attempted while unauthenticated"

# =============================================================================
# 8. Jira provider — auth, mapping, redaction, degradation, offline writes
# =============================================================================
JIRA_PORT="$(free_port)"
start_fake_jira "$JIRA_PORT"
JIRA_BASE="http://127.0.0.1:$JIRA_PORT"
GOOD_TOKEN="fixture-jira-token-abcdef123456"

F_JIRA="$(new_fixture)"
write_index "$F_JIRA"
cat > "$F_JIRA/docs/task-tracking.md" <<'EOF'
# Task tracking

```ini
[tracker]
provider = jira
project = REG
require_write_approval = false
```
EOF

jira_env() {
  export JIRA_BASE_URL="$1" JIRA_EMAIL="fixture@example.com" JIRA_API_TOKEN="$2" JIRA_PROJECT=REG
}

jira_doctor="$(jira_env "$JIRA_BASE" "$GOOD_TOKEN"; run doctor --repo "$F_JIRA" 2>&1)"
assert_contains "$jira_doctor" "provider:       jira" "Jira: explicit configuration selects jira"
assert_contains "$jira_doctor" "reachable:      yes" "Jira: a reachable site with valid auth reports reachable"

jira_norm="$(cd "$F_JIRA" && jira_env "$JIRA_BASE" "$GOOD_TOKEN"; pyreg <<'EOF'
from registry.config import load_config
from registry.providers import build_provider
from registry.providers.base import WriteGate

provider = build_provider("jira", load_config("."), WriteGate(apply=True, require_approval=False))
tasks = {task.id: task for task in provider.list_tasks()}
for task_id in sorted(tasks):
    task = tasks[task_id]
    print(f"{task_id}|kind={task.kind}|status={task.status}|priority={task.priority}"
          f"|labels={','.join(task.labels)}|ref={task.external.id}")
print("deps=" + ",".join(tasks["recipe.morph-live-grid"].depends_on))
a, b = tasks["recipe.morph-live-grid"], tasks["recipe.color-lut"]
print("dep-native=" + str(provider.add_dependency(a, b).native))
print("parent-native=" + str(provider.link_parent(a, b).native))
EOF
)"
assert_contains "$jira_norm" "recipe.morph-live-grid|kind=feature|status=in_progress|priority=high|labels=area/render,now|ref=REG-1" \
  "Jira: Story->feature, In Progress->in_progress, High->high, labels preserved"
assert_contains "$jira_norm" "recipe.color-lut|kind=bug|status=done|priority=medium|labels=area/color|ref=REG-2" \
  "Jira: Bug->bug, done category->done"
assert_contains "$jira_norm" "deps=recipe.color-lut" \
  "Jira: dependencies round-trip through the description metadata block"
assert_contains "$jira_norm" "dep-native=True" \
  "Jira: a site that accepts issue links reports the dependency as native"
assert_contains "$jira_norm" "parent-native=True" \
  "Jira: a site that accepts a parent field reports the hierarchy as native"

# capability degradation on a site that refuses both link types
JIRA_PORT2="$(free_port)"
start_fake_jira "$JIRA_PORT2" --reject-links
jira_degraded="$(cd "$F_JIRA" && jira_env "http://127.0.0.1:$JIRA_PORT2" "$GOOD_TOKEN"; pyreg <<'EOF'
from registry.config import load_config
from registry.providers import build_provider
from registry.providers.base import WriteGate

provider = build_provider("jira", load_config("."), WriteGate(apply=True, require_approval=False))
tasks = {task.id: task for task in provider.list_tasks()}
a, b = tasks["recipe.morph-live-grid"], tasks["recipe.color-lut"]
dep = provider.add_dependency(a, b)
parent = provider.link_parent(a, b)
print("dep-native=" + str(dep.native))
print("dep-render=" + dep.render())
print("parent-native=" + str(parent.native))
print("limitations=" + " || ".join(provider.limitations))
EOF
)"
assert_contains "$jira_degraded" "dep-native=False" \
  "Jira: a refused link degrades to metadata instead of pretending it is native"
assert_contains "$jira_degraded" "inferred (stored in task metadata)" \
  "Jira: the degraded link renders as inferred, never as native"
assert_contains "$jira_degraded" "parent-native=False" \
  "Jira: a refused parent field degrades the same way"
assert_contains "$jira_degraded" "limitations=" \
  "Jira: the degradation is recorded as a limitation for the report"

# credential redaction: the fake site echoes the Authorization header back
jira_redact="$(cd "$F_JIRA" && jira_env "$JIRA_BASE" "$GOOD_TOKEN"; pyreg <<'EOF'
from registry.config import load_config
from registry.providers import build_provider
from registry.providers.base import ProviderError, WriteGate

config = load_config(".")
config = type(config)(**{**{f.name: getattr(config, f.name) for f in config.__dataclass_fields__.values()},
                         "jira_token": type(config.jira_token)("wrong-token-9999")})
provider = build_provider("jira", config, WriteGate())
try:
    provider.list_tasks()
    print("no-error")
except ProviderError as exc:
    print("error=" + str(exc).replace("\n", " "))
EOF
)"
assert_contains "$jira_redact" "HTTP 401" "Jira: a rejected credential surfaces the HTTP status"
assert_contains "$jira_redact" "REDACTED" "Jira: the echoed Authorization header is masked"
assert_not_contains "$jira_redact" "wrong-token-9999" \
  "Jira: the credential itself never reaches the error text"
jira_doctor_bad="$(jira_env "$JIRA_BASE" "$GOOD_TOKEN-invalid"; run doctor --repo "$F_JIRA" 2>&1)"
assert_not_contains "$jira_doctor_bad" "$GOOD_TOKEN" \
  "Jira: no CLI output path prints the token"
assert_contains "$jira_doctor_bad" "authentication rejected" \
  "Jira: a rejected credential is reported as an authentication failure"

# offline: nothing listening on that port
JIRA_DEAD_PORT="$(free_port)"
jira_offline="$(jira_env "http://127.0.0.1:$JIRA_DEAD_PORT" "$GOOD_TOKEN"
  run publish --repo "$F_JIRA" --apply --approve 2>&1)"
jira_offline_code=$?
assert_eq "1" "$jira_offline_code" "Jira: an external write with no connectivity exits non-zero"
assert_contains "$jira_offline" "refusing to publish" "Jira: the offline write refuses explicitly"
assert_contains "$jira_offline" "cannot reach" "Jira: the refusal names the unreachable site"

# =============================================================================
# 9. Reconcile, frontier, and progressive disclosure
# =============================================================================
F_REC="$(new_fixture)"
mkdir -p "$F_REC/tasks/details" "$F_REC/specs/pending" "$F_REC/specs/completed"
cat > "$F_REC/tasks/todo.md" <<'EOF'
# Task Plan

> Specs in flight: specs/completed/shipped-thing.md

- [ ] Morph live grid recipe <!-- task-id: recipe.morph-live-grid --> — ship the live grid morph (blocked-by: recipe.new-only)
- [ ] Post-LUT polish <!-- task-id: recipe.polish --> — cleanup pass (blocked-by: recipe.color-lut)
- [ ] Colour LUT loader <!-- task-id: recipe.color-lut --> — palette mapping
- [ ] Colour LUT loader again <!-- task-id: recipe.color-lut --> — a second row claiming the same id
- [ ] Vanished work <!-- task-id: recipe.gone --> — points at a task file nobody has ([recipe.gone](tasks/details/recipe.gone.md))
EOF
cat > "$F_REC/tasks/details/recipe.color-lut.md" <<'EOF'
# Colour LUT loader

<!-- task-registry:begin -->
task-id: recipe.color-lut
kind: bug
<!-- task-registry:end -->

- status: done
- priority: high

## Summary

palette mapping

## Acceptance Criteria

- [ ] eight-bit sources load without a colour shift
- [ ] the regression fixture stays green
EOF
cat > "$F_REC/tasks/details/recipe.new-only.md" <<'EOF'
# Provider-only task

<!-- task-registry:begin -->
task-id: recipe.new-only
kind: feature
<!-- task-registry:end -->

- status: open
EOF
printf '# Orphan\n\nnothing references this\n' > "$F_REC/specs/pending/orphan.md"
printf '# Shipped\n\ndone work\n' > "$F_REC/specs/completed/shipped-thing.md"
printf '# Old approach\n\n> Superseded by: specs/pending/orphan.md\n' > "$F_REC/specs/pending/old-approach.md"

rec_out="$(run reconcile --repo "$F_REC" 2>&1)"
rec_code=$?
assert_eq "0" "$rec_code" "Reconcile: a read-only run exits 0"
assert_eq "task-registry reconcile — provider: local" "$(printf '%s\n' "$rec_out" | head -1)" \
  "Reconcile: the first line names the command and the provider"
summary_line="$(printf '%s\n' "$rec_out" | grep -n '^Summary:$' | cut -d: -f1)"
first_detail_line="$(printf '%s\n' "$rec_out" | grep -n '^[a-z-]*:$' | grep -v 'Summary' | head -1 | cut -d: -f1)"
assert_eq "before" "$([ "${summary_line:-99}" -lt "${first_detail_line:-0}" ] && echo before || echo after)" \
  "Reconcile: the summary is printed before any per-task detail"
assert_contains "$rec_out" "status-drift: 2" \
  "Reconcile: drift is counted per row — both rows claiming the done id are reported"
assert_contains "$rec_out" "recipe.color-lut: local 'open' vs provider 'done'" \
  "Reconcile: the drift line names both sides"
assert_contains "$rec_out" "duplicate-id" "Reconcile: two rows claiming one id are reported"
assert_contains "$rec_out" "appears on 2 rows" "Reconcile: the duplicate names how many rows claim the id"
assert_contains "$rec_out" "orphaned-link" "Reconcile: a link the provider cannot resolve is reported"
assert_contains "$rec_out" "left untouched for a human to resolve" \
  "Reconcile: an orphaned link is never auto-removed"
assert_contains "$rec_out" "unlinked-external" "Reconcile: a provider task with no local row is reported"
assert_contains "$rec_out" "stale-spec" "Reconcile: an unreferenced pending spec is reported"
assert_contains "$rec_out" "specs/pending/orphan.md is pending with no task referencing it" \
  "Reconcile: the stale spec is named"
assert_contains "$rec_out" "classify it, do not delete it" \
  "Reconcile: the stale-spec finding refuses deletion as a remedy"
assert_contains "$rec_out" "superseded-spec" "Reconcile: a spec declaring itself superseded is reported"
assert_contains "$rec_out" "completed-spec" \
  "Reconcile: a completed spec still referenced by the index is reported"
assert_not_contains "$rec_out" "eight-bit sources load without a colour shift" \
  "Reconcile: acceptance criteria never appear in the summary output"
assert_contains "$rec_out" "Run \`task-registry show <task-id>\` for the full detail" \
  "Reconcile: detail is offered on demand, not printed"

# idempotence — note the *first* apply must change something, otherwise a
# reconcile that silently did nothing at all would satisfy the comparison below.
cp "$F_REC/tasks/todo.md" "$F_REC/todo.before-first"
rec_first="$(run reconcile --repo "$F_REC" --apply 2>&1)"
assert_not_contains "$rec_first" "updated 0 local row(s)" \
  "Reconcile: the first --apply actually rewrites rows"
assert_files_differ "$F_REC/tasks/todo.md" "$F_REC/todo.before-first" \
  "Reconcile: the first --apply changes the index on disk"
cp "$F_REC/tasks/todo.md" "$F_REC/todo.after-first"
rec_second="$(run reconcile --repo "$F_REC" --apply 2>&1)"
assert_files_identical "$F_REC/tasks/todo.md" "$F_REC/todo.after-first" \
  "Reconcile: a second --apply changes nothing on disk"
assert_contains "$rec_second" "updated 0 local row(s)" \
  "Reconcile: the second run reports that it changed nothing"
assert_file_contains "$F_REC/tasks/todo.md" "recipe.gone" \
  "Reconcile: --apply never deletes the row whose link it could not resolve"
assert_eq "yes" "$([ -f "$F_REC/specs/pending/orphan.md" ] && echo yes || echo no)" \
  "Reconcile: --apply never deletes a stale spec"
applied_index="$(cat "$F_REC/tasks/todo.md")"
assert_not_contains "$applied_index" "eight-bit sources load" \
  "Reconcile: --apply never copies acceptance criteria into the index"

show_out="$(run show recipe.color-lut --repo "$F_REC" 2>&1)"
show_code=$?
assert_eq "0" "$show_code" "Show: a known task exits 0"
assert_contains "$show_out" "kind:     bug" "Show: the full record includes the kind"
assert_contains "$show_out" "eight-bit sources load without a colour shift" \
  "Show: acceptance criteria are revealed here, and only here"
assert_contains "$show_out" "external: local:recipe.color-lut" "Show: the external reference is named"
missing_show="$(run show no-such-task --repo "$F_REC" 2>&1)"
missing_code=$?
assert_eq "1" "$missing_code" "Show: an unknown id exits non-zero"
assert_contains "$missing_show" "no task with reference 'no-such-task'" "Show: the failure names the reference"

front_out="$(run frontier --repo "$F_REC" 2>&1)"
assert_contains "$front_out" "blocked:" "Frontier: blocked work is a section of its own"
assert_contains "$front_out" "recipe.morph-live-grid: 'Morph live grid recipe' waits on recipe.new-only" \
  "Frontier: a task blocked by open work names its blocker"
assert_contains "$front_out" "ready:" "Frontier: ready work is listed"
assert_contains "$front_out" "recipe.polish" "Frontier: a task whose only blocker is done is ready"
front_blocked_block="$(printf '%s\n' "$front_out" | sed -n '/^blocked:/,/^$/p')"
assert_not_contains "$front_blocked_block" "recipe.polish" \
  "Frontier: a satisfied dependency does not keep a task blocked"
# Match the entry, not a mention: recipe.new-only is legitimately named as the
# blocker on another line of this same block.
blocked_entries="$(printf '%s\n' "$front_blocked_block" | grep -c '^  recipe\.new-only:')"
assert_eq "0" "$blocked_entries" \
  "Frontier: a task with no dependencies is never listed as blocked"

# =============================================================================
# 10. Migration — an ascii_video_pipeline-shaped repository
# =============================================================================
F_MIG="$(new_fixture)"
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
mig_dry="$(run migrate --repo "$F_MIG" 2>&1)"
mig_dry_code=$?
mig_after_dry="$(cd "$F_MIG" && find . -type f | sort)"
assert_eq "0" "$mig_dry_code" "Migrate: the dry run exits 0"
assert_contains "$mig_dry" "DRY RUN (nothing written)" "Migrate: dry-run is the default and says so"
assert_eq "$mig_before" "$mig_after_dry" "Migrate: the dry run writes nothing"
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

mig_apply="$(run migrate --repo "$F_MIG" --apply 2>&1)"
mig_apply_code=$?
assert_eq "0" "$mig_apply_code" "Migrate: --apply exits 0"
assert_contains "$mig_apply" "minted" "Migrate: --apply reports how many ids it minted"
assert_file_contains "$F_MIG/tasks/todo.md" \
  "- [ ] Morph live grid recipe <!-- task-id: recipe-morphs.morph-live-grid-recipe --> — ship the live grid morph" \
  "Migrate: the id is inserted after the title, leaving the rest of the row untouched"
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

id_count_first="$(grep -c 'task-id:' "$F_MIG/tasks/todo.md")"
run migrate --repo "$F_MIG" --apply >/dev/null 2>&1
id_count_second="$(grep -c 'task-id:' "$F_MIG/tasks/todo.md")"
assert_eq "$id_count_first" "$id_count_second" \
  "Migrate: re-running --apply mints no duplicate ids"

post_mig_recon="$(run reconcile --repo "$F_MIG" 2>&1)"
post_mig_code=$?
assert_eq "0" "$post_mig_code" "Migrate: the migrated index reconciles cleanly"
assert_eq "0" "$(printf '%s\n' "$post_mig_recon" | grep -c '^  missing-id:')" \
  "Migrate: active rows no longer report as missing an id"

# =============================================================================
# 11. CLI surface — exit codes, dry-run precedence, report file
# =============================================================================
F_CLI="$(new_fixture)"
write_index "$F_CLI"

bad_cmd_out="$(run frobnicate --repo "$F_CLI" 2>&1)"
bad_cmd_code=$?
assert_eq "2" "$bad_cmd_code" "CLI: an unknown command is a usage error (exit 2)"
assert_contains "$bad_cmd_out" "invalid choice" "CLI: the usage error names the invalid command"

no_id_out="$(run show --repo "$F_CLI" 2>&1)"
no_id_code=$?
assert_eq "2" "$no_id_code" "CLI: 'show' without a task id is a usage error"
assert_contains "$no_id_out" "requires a task id" "CLI: the usage error says what is missing"

no_dir_out="$(run reconcile --repo "$F_CLI/nope" 2>&1)"
no_dir_code=$?
assert_eq "2" "$no_dir_code" "CLI: a missing project root is a usage error"
assert_contains "$no_dir_out" "no such directory" "CLI: the usage error names the missing path"

dry_wins="$(run publish --repo "$F_CLI" --apply --dry-run 2>&1)"
assert_contains "$dry_wins" "mode: dry-run" "CLI: --dry-run overrides --apply"

run reconcile --repo "$F_CLI" --report "$F_CLI/report.txt" >/dev/null 2>&1
assert_file_contains "$F_CLI/report.txt" "task-registry reconcile" \
  "CLI: --report writes the same output to a file"

for command in reconcile publish pull frontier doctor migrate; do
  out="$(run "$command" --repo "$F_CLI" 2>&1)"
  code=$?
  assert_eq "0" "$code" "CLI: '$command' runs clean on a well-formed repository"
done

malformed_repo="$(new_fixture)"
printf '# Plan\n\n- [ ]\n' > "$malformed_repo/tasks/todo.md"
malformed_out="$(run reconcile --repo "$malformed_repo" 2>&1)"
malformed_code=$?
assert_eq "1" "$malformed_code" "CLI: malformed input exits non-zero rather than passing quietly"
assert_contains "$malformed_out" "Malformed input (reported, nothing dropped)" \
  "CLI: malformed rows get their own reported section"

# =============================================================================
# 12. Regressions — one block per defect found in review
#
# Each assertion here failed before its fix. They are grouped by the layer the
# defect lived in rather than by the review that found it, so the next reader
# finds them next to the code they constrain.
# =============================================================================

# --- model: an unbalanced marker must not eat the body ------------------------
model_reg="$(pyreg <<'EOF'
from registry.model import Task, upsert_metadata_block, safe_task

task = Task(id="a.b", title="A task")
stray = (
    "Intro paragraph.\n\n"
    "Someone quoted the format: <!-- task-registry:begin -->\n\n"
    "A paragraph a human wrote that must survive.\n\n"
    "<!-- task-registry:begin -->\ntask-id: stale.id\n<!-- task-registry:end -->\n"
)
out = upsert_metadata_block(stray, task)
print("stray-kept=" + str("A paragraph a human wrote that must survive." in out))
print("stray-intro-kept=" + str("Intro paragraph." in out))
print("stray-real-block-replaced=" + str("task-id: a.b" in out and "stale.id" not in out))

# The well-formed case still replaces in place, exactly once.
good = "Body.\n\n<!-- task-registry:begin -->\ntask-id: old\n<!-- task-registry:end -->\n\nTail.\n"
replaced = upsert_metadata_block(good, task)
print("replaced-count=" + str(replaced.count("<!-- task-registry:begin -->")))
print("tail-kept=" + str("Tail." in replaced))
print("old-id-gone=" + str("task-id: old" not in replaced))

# A foreign vocabulary value is defaulted and reported, never raised.
built, notes = safe_task("issue #7", id="x.y", title="T", kind="chore", status="triage")
print("safe-kind=" + built.kind)
print("safe-status=" + built.status)
print("safe-notes=" + str(len(notes)))
print("safe-note-names-source=" + str(all("issue #7" in note for note in notes)))
EOF
)"
assert_contains "$model_reg" "stray-kept=True" \
  "Model: a stray begin marker never deletes the prose after it"
assert_contains "$model_reg" "stray-intro-kept=True" \
  "Model: a stray begin marker never deletes the prose before it"
assert_contains "$model_reg" "stray-real-block-replaced=True" \
  "Model: the real block is still the one rewritten when a stray marker precedes it"
assert_contains "$model_reg" "replaced-count=1" \
  "Model: a well-formed block is still replaced in place, not duplicated"
assert_contains "$model_reg" "tail-kept=True" "Model: text after the block survives replacement"
assert_contains "$model_reg" "old-id-gone=True" "Model: the superseded identity is removed"
assert_contains "$model_reg" "safe-kind=task" "Model: an unknown kind reads as the default"
assert_contains "$model_reg" "safe-status=open" "Model: an unknown status reads as the default"
assert_contains "$model_reg" "safe-notes=2" "Model: each defaulted field is reported, not swallowed"
assert_contains "$model_reg" "safe-note-names-source=True" \
  "Model: the report names the record the bad value came from"

# --- index: titles, references, indentation, provider classification ---------
index_reg="$(pyreg <<'EOF'
from registry.index import TaskIndex, render_row
from registry.model import ExternalRef, Task

text = "\n".join([
    "# Plan",
    "- [ ] -fno-strict-aliasing crashes the build <!-- task-id: bug.aliasing --> — a compiler flag",
    "  - [ ] Nested child row <!-- task-id: bug.aliasing.child --> — indented on purpose",
    "- [ ] Crafted ref ([--body-file=/etc/passwd](https://github.com/o/r/issues/1)) <!-- task-id: evil.one -->",
    "- [ ] Jira linked ([REG-4](https://jira.example.com/browse/REG-4)) <!-- task-id: jira.one -->",
])
index = TaskIndex("tasks/todo.md", text, "tasks/todo.md")
by_id = {row.task.id: row for row in index.rows}
print("title=" + by_id["bug.aliasing"].task.title)
print("indent=[" + by_id["bug.aliasing.child"].indent + "]")
child = by_id["bug.aliasing.child"]
print("rerendered-indent=[" + render_row(child.task, child.indent)[:2] + "]")
print("crafted-parsed=" + str("evil.one" in by_id))
print("crafted-problem=" + str(any("body-file" in p.message for p in index.problems)))
print("jira-provider=" + by_id["jira.one"].task.external.provider)
label = render_row(Task(id="j", title="J", external=ExternalRef("jira", "REG-4", "u")))
print("jira-label-plain=" + str("[REG-4]" in label and "#REG-4" not in label))
gh_label = render_row(Task(id="g", title="G", external=ExternalRef("github", "42", "u")))
print("github-label-hashed=" + str("[#42]" in gh_label))
EOF
)"
assert_contains "$index_reg" "title=-fno-strict-aliasing crashes the build" \
  "Index: a title that starts with a dash is not silently trimmed"
assert_contains "$index_reg" "indent=[  ]" "Index: a nested row's indentation is captured"
assert_contains "$index_reg" "rerendered-indent=[  ]" \
  "Index: rewriting a nested row preserves its indentation"
assert_contains "$index_reg" "crafted-parsed=False" \
  "Index: a reference id shaped like a CLI flag is not turned into a task"
assert_contains "$index_reg" "crafted-problem=True" \
  "Index: the rejected reference is reported as malformed input, not dropped"
assert_contains "$index_reg" "jira-provider=jira" \
  "Index: a browse URL is classified by the provider that owns it"
assert_contains "$index_reg" "jira-label-plain=True" \
  "Index: a Jira reference renders as its own key, not as #key"
assert_contains "$index_reg" "github-label-hashed=True" \
  "Index: a GitHub reference still renders as #number"

# --- config: merging, pointer precedence, confinement, floors ----------------
F_CFG="$(new_fixture)"
mkdir -p "$F_CFG/.claude"
cat > "$F_CFG/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = local

[labels.kind]
question = research
EOF
printf '```\n' >> "$F_CFG/docs/task-tracking.md"
cp "$F_CFG/docs/task-tracking.md" "$F_CFG/docs/project-owned.md"
printf 'Task tracking instructions: docs/project-owned.md\n' > "$F_CFG/.claude/project.md"
printf 'Task tracking instructions: docs/template-managed.md\n' > "$F_CFG/CLAUDE.md"
cp "$F_CFG/docs/task-tracking.md" "$F_CFG/docs/template-managed.md"

cfg_reg="$(cd "$F_CFG" && pyreg <<'EOF'
from registry.config import Config, ConfigError, load_config, require_secure_transport

config = load_config(".")
print("source=" + str(config.source_path))
labels = config.kind_labels
print("declared=" + labels.get("question", "(missing)"))
print("default-bug=" + labels.get("bug", "(missing)"))
print("default-enhancement=" + labels.get("enhancement", "(missing)"))
print("default-decision=" + labels.get("design-decision", "(missing)"))

confined = Config(root=".", local_detail_dir="../../escape")
try:
    confined.path(confined.local_detail_dir)
    print("escape=allowed")
except ConfigError as exc:
    print("escape-refused=" + str(exc))

for url in ("http://jira.example.com", "http://127.0.0.1:8080", "https://jira.example.com"):
    try:
        require_secure_transport(url, {})
        print(f"transport {url} = allowed")
    except ConfigError:
        print(f"transport {url} = refused")
print("transport-optout=" + str(
    require_secure_transport("http://jira.example.com",
                             {"TASK_REGISTRY_ALLOW_INSECURE_TRANSPORT": "1"}) is None))
EOF
)"
assert_contains "$cfg_reg" "source=docs/project-owned.md" \
  "Config: the project-owned pointer wins over the template-managed one"
assert_contains "$cfg_reg" "declared=research" "Config: a declared label mapping is read"
assert_contains "$cfg_reg" "default-bug=bug" \
  "Config: declaring one mapping does not unmap the shipped defaults"
assert_contains "$cfg_reg" "default-enhancement=feature" \
  "Config: 'enhancement' still maps after a section is declared"
assert_contains "$cfg_reg" "default-decision=decision" \
  "Config: 'design-decision' still maps after a section is declared"
assert_contains "$cfg_reg" "escape-refused=" \
  "Config: a configured path outside the project root is refused"
assert_contains "$cfg_reg" "transport http://jira.example.com = refused" \
  "Config: credentials are never sent over plain http to a remote host"
assert_contains "$cfg_reg" "transport http://127.0.0.1:8080 = allowed" \
  "Config: loopback http is allowed — there is no wire to sniff"
assert_contains "$cfg_reg" "transport https://jira.example.com = allowed" \
  "Config: https is allowed"
assert_contains "$cfg_reg" "transport-optout=True" \
  "Config: an operator can override the transport floor from the environment"

# A pointer that escapes the repository must not be followed.
F_ESC="$(new_fixture)"
printf 'Task tracking instructions: ../../../etc/passwd\n' > "$F_ESC/AGENTS.md"
esc_out="$(cd "$F_ESC" && pyreg <<'EOF'
from registry.config import find_config_path
print("resolved=" + str(find_config_path(".")))
EOF
)"
assert_contains "$esc_out" "resolved=None" \
  "Config: a pointer resolving outside the project root is not followed"

# Approval is a floor: a repository file may add it, never remove it.
F_FLOOR="$(new_fixture)"
cat > "$F_FLOOR/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = github
require_write_approval = false
EOF
printf '```\n' >> "$F_FLOOR/docs/task-tracking.md"
install_gh_mock "$F_FLOOR"
floor_out="$(cd "$F_FLOOR" && pyreg <<'EOF'
from registry.config import load_config
plain = load_config(".", env={})
trusted = load_config(".", env={"TASK_REGISTRY_TRUSTED_CONFIG": "1"})
print("untrusted=" + str(plain.require_write_approval))
print("ignored-flag=" + str(plain.approval_relaxation_ignored))
print("trusted=" + str(trusted.require_write_approval))
EOF
)"
assert_contains "$floor_out" "untrusted=True" \
  "Config: a checked-in file cannot switch off the approval requirement"
assert_contains "$floor_out" "ignored-flag=True" \
  "Config: the ignored relaxation is recorded so doctor can say so"
assert_contains "$floor_out" "trusted=False" \
  "Config: an operator who trusts the repository can lower the floor"
floor_doctor="$(cd "$F_FLOOR" && PATH="$F_FLOOR/bin:$PATH" GH_MOCK_DIR="$F_FLOOR/ghdata" \
  run doctor --repo "$F_FLOOR" 2>&1)"
assert_contains "$floor_doctor" "approval is a floor" \
  "Doctor: the refused relaxation is visible to the user"

# --- local provider: a compact row must not delete detail --------------------
F_LOSS="$(new_fixture)"
write_index "$F_LOSS"
loss_out="$(cd "$F_LOSS" && pyreg <<'EOF'
from registry.config import load_config
from registry.model import Task
from registry.providers import build_provider
from registry.providers.base import WriteGate

config = load_config(".")
provider = build_provider("local", config, WriteGate(apply=True))

rich = Task(
    id="recipe.morph-live-grid",
    title="Morph live grid recipe",
    kind="feature",
    summary="Ship the live grid morph.",
    acceptance_criteria=("the grid morphs live", "no frame drops"),
)
provider.create_task(rich)
path = "tasks/details/recipe.morph-live-grid.md"
with open(path, "a", encoding="utf-8") as handle:
    handle.write("\n## Notes\n\nA human wrote this.\n")

# Exactly what a compact index row produces: title, status, nothing else.
provider.update_task(Task(id="recipe.morph-live-grid", title="Morph live grid recipe"))
after = open(path, encoding="utf-8").read()
print("summary-kept=" + str("Ship the live grid morph." in after))
print("criteria-kept=" + str("no frame drops" in after))
print("kind-kept=" + str("kind: feature" in after))
print("human-section-kept=" + str("A human wrote this." in after))
EOF
)"
assert_contains "$loss_out" "summary-kept=True" \
  "Local: updating from a compact row does not delete the Summary section"
assert_contains "$loss_out" "criteria-kept=True" \
  "Local: updating from a compact row does not delete the Acceptance Criteria"
assert_contains "$loss_out" "kind-kept=True" \
  "Local: updating from a compact row does not downgrade the recorded kind"
assert_contains "$loss_out" "human-section-kept=True" \
  "Local: a section a human added survives an update"

# The offline provider writes inside the repository, so approval has no subject.
F_OFFLINE="$(new_fixture)"
write_index "$F_OFFLINE"
cat > "$F_OFFLINE/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = local
EOF
printf '```\n' >> "$F_OFFLINE/docs/task-tracking.md"
offline_pub="$(run publish --repo "$F_OFFLINE" --apply 2>&1)"
offline_code=$?
assert_eq "0" "$offline_code" \
  "Local: --apply alone publishes offline — approval gates external writes only"
assert_contains "$offline_pub" "created" "Local: the offline publish actually created tasks"

# --- github: argv hardening, label creation, truncation ----------------------
gh_reg="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-reg.log" pyreg <<'EOF'
from registry.config import load_config
from registry.model import ExternalRef, Task
from registry.providers import build_provider
from registry.providers.base import ProviderError, WriteGate

config = load_config(".")
provider = build_provider("github", config, WriteGate(apply=True, require_approval=False))
try:
    provider.get_task(ExternalRef("github", "--body-file=/etc/passwd", ""))
    print("crafted-ref=accepted")
except ProviderError as exc:
    print("crafted-ref-refused=" + str(exc))

# A legitimate number still round-trips — and the mock refuses any positional
# that did not arrive after a `--`, so this call also pins the separator.
fetched = provider.get_task(ExternalRef("github", "42", ""))
print("legit-ref=" + fetched.id)

# An unmapped label is reported and dropped while creation is off.
provider.create_task(Task(id="lbl.one", title="Needs a new label", labels=("brand-new-label",)))
print("creation-off=" + str(any("allow_label_creation is off" in n for n in provider.limitations)))
EOF
)"
assert_contains "$gh_reg" "crafted-ref-refused=github:" \
  "GitHub: a reference that is not an issue number never reaches gh"
assert_contains "$gh_reg" "legit-ref=" \
  "GitHub: a legitimate issue number is still fetched after the guard"
assert_contains "$gh_reg" "creation-off=True" \
  "GitHub: an unknown label is reported and omitted while creation is off"
assert_contains "$(cat "$F_GH/gh-reg.log")" " -- " \
  "GitHub: positional arguments are passed after a -- separator"

F_LBL="$(new_fixture)"
write_index "$F_LBL"
mkdir -p "$F_LBL/bin" "$F_LBL/lbldata"
cp "$FIXTURES/gh" "$F_LBL/bin/gh"
chmod +x "$F_LBL/bin/gh"
printf '[]\n' > "$F_LBL/lbldata/issues.json"
printf '[{"name":"bug"}]\n' > "$F_LBL/lbldata/labels.json"
cat > "$F_LBL/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = github
repository = fixture-owner/fixture-repo
allow_label_creation = true
EOF
printf '```\n' >> "$F_LBL/docs/task-tracking.md"
lbl_out="$(cd "$F_LBL" && PATH="$F_LBL/bin:$PATH" GH_MOCK_DIR="$F_LBL/lbldata" \
  GH_MOCK_LOG="$F_LBL/gh.log" pyreg <<'EOF'
from registry.config import load_config
from registry.model import Task
from registry.providers import build_provider
from registry.providers.base import WriteGate

provider = build_provider("github", load_config("."), WriteGate(apply=True, require_approval=False))
provider.create_task(Task(id="lbl.two", title="Needs a new label", labels=("area/render",)))
print("created-note=" + str(any("created label" in n for n in provider.limitations)))
EOF
)"
assert_contains "$lbl_out" "created-note=True" \
  "GitHub: allow_label_creation actually creates the missing label"
assert_contains "$(cat "$F_LBL/gh.log")" "label create" \
  "GitHub: label creation goes through gh label create, not a silent skip"
assert_file_contains "$F_LBL/lbldata/labels.json" "area/render" \
  "GitHub: the created label is really added to the repository vocabulary"

trunc_out="$(cd "$F_GH" && pyreg <<'EOF'
from registry.config import load_config
from registry.providers import build_provider
from registry.providers.base import WriteGate
from registry.reconcile import Registry

config = load_config(".")
provider = build_provider("local", config, WriteGate(apply=True))
provider.result_truncated = True
report = Registry(config, provider).publish(apply=True)
print("exit=" + str(report.exit_code))
print("refusal=" + "; ".join(report.failures))
EOF
)"
assert_contains "$trunc_out" "exit=1" \
  "Publish: a truncated provider read makes the run fail rather than duplicate"
assert_contains "$trunc_out" "refusal=refusing to publish" \
  "Publish: the refusal explains that an unseen task could be created twice"

# --- jira: key validation, redaction, credential-stripping redirects ---------
jira_reg="$(cd "$F_JIRA" && jira_env "$JIRA_BASE" "$GOOD_TOKEN"; pyreg <<'EOF'
from registry.config import load_config
from registry.model import ExternalRef
from registry.providers import build_provider
from registry.providers.base import ProviderError, ProviderUnavailable, WriteGate

provider = build_provider("jira", load_config("."), WriteGate(apply=True, require_approval=False))
try:
    provider.get_task(ExternalRef("jira", "../../secure/admin", ""))
    print("crafted-key=accepted")
except ProviderError as exc:
    print("crafted-key-refused=" + str(exc))
EOF
)"
assert_contains "$jira_reg" "is not an issue key (expected PROJ-123)" \
  "Jira: a reference that is not an issue key never becomes a request path"

leak_out="$(cd "$F_JIRA" && pyreg <<'EOF'
from registry.config import Config, Secret
from registry.providers.jira import JiraProvider
from registry.providers.base import ProviderUnavailable

config = Config(
    root=".",
    provider="jira",
    project="REG",
    jira_base_url="https://user:sup3rsecretvalue@jira.example.invalid",
    jira_email="fixture@example.com",
    jira_token=Secret("fixture-jira-token-abcdef123456"),
)
provider = JiraProvider(config)
try:
    provider._call("GET", "/rest/api/2/myself")
    print("reached=yes")
except ProviderUnavailable as exc:
    print("unreachable=" + str(exc))
EOF
)"
assert_contains "$leak_out" "unreachable=jira: cannot reach" \
  "Jira: an unreachable site is reported, not swallowed"
assert_not_contains "$leak_out" "sup3rsecretvalue" \
  "Jira: a credential embedded in the base URL is redacted out of the error"

ECHO_PORT="$(free_port)"
"$PY" "$FIXTURES/fake-jira.py" "$ECHO_PORT" --echo-auth >/dev/null 2>&1 &
JIRA_PIDS+=("$!")
REDIRECT_PORT="$(free_port)"
"$PY" "$FIXTURES/fake-jira.py" "$REDIRECT_PORT" \
  --redirect-to "http://127.0.0.1:$ECHO_PORT/rest/api/2/myself" >/dev/null 2>&1 &
JIRA_PIDS+=("$!")
"$PY" - "$ECHO_PORT" "$REDIRECT_PORT" <<'EOF'
import sys, time, urllib.request
for port in sys.argv[1:]:
    for _ in range(80):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/ping", timeout=1).read()
            break
        except Exception as exc:
            if "Connection refused" not in str(exc):
                break
            time.sleep(0.05)
EOF
redirect_out="$(cd "$F_JIRA" && jira_env "http://127.0.0.1:$REDIRECT_PORT" "$GOOD_TOKEN"; pyreg <<'EOF'
from registry.config import load_config
from registry.providers import build_provider
from registry.providers.base import WriteGate

provider = build_provider("jira", load_config("."), WriteGate())
status, body = provider._call("GET", "/rest/api/2/myself")
print("status=" + str(status))
print("body=" + body)
EOF
)"
assert_contains "$redirect_out" '"received_authorization": ""' \
  "Jira: credentials are stripped when a redirect crosses to another origin"

# --- reconcile: status floor, skipped rows, frontier order ------------------
F_DRIFT="$(new_fixture)"
cat > "$F_DRIFT/tasks/todo.md" <<'EOF'
# Plan

- [~] Morph live grid recipe <!-- task-id: recipe.morph-live-grid --> — in flight ([#41](https://github.com/o/r/issues/41))
- [ ] No identity here — a row from before the registry existed
EOF
drift_out="$(cd "$F_DRIFT" && pyreg <<'EOF'
from registry.config import load_config
from registry.model import ExternalRef, Task
from registry.providers.base import Capabilities, ProviderStatus, TrackerProvider, WriteGate
from registry.reconcile import Registry


class OpenClosedOnly(TrackerProvider):
    """A tracker with GitHub's vocabulary: it can only say open or done."""

    name = "stub"
    capabilities = Capabilities(comments=True, labels=True)

    def discover(self):
        return ProviderStatus(True, "stub")

    def list_tasks(self):
        return [Task(id="recipe.morph-live-grid", title="Morph live grid recipe",
                     status="open", external=ExternalRef("github", "41", ""))]

    def get_task(self, ref):
        return self.list_tasks()[0]

    def resolve_reference(self, raw):
        return None

    def create_task(self, task):
        return task

    def update_task(self, task):
        return task

    def close_task(self, task, resolution="done"):
        return task

    def comment(self, task, body):
        return None

    def link_parent(self, child, parent):
        raise NotImplementedError

    def add_dependency(self, task, depends_on):
        raise NotImplementedError


config = load_config(".")
registry = Registry(config, OpenClosedOnly(config, WriteGate(apply=True)))
report = registry.reconcile(apply=True)
print("kept=" + str(any(f.category == "status-kept-local" for f in report.findings)))
print("row=" + open("tasks/todo.md", encoding="utf-8").read().splitlines()[2][:8])

publish_report = registry.publish(apply=False)
print("skipped=" + str(any(f.category == "skipped-no-id" for f in publish_report.findings)))
print("skip-message=" + "".join(
    f.message for f in publish_report.findings if f.category == "skipped-no-id"))
EOF
)"
assert_contains "$drift_out" "kept=True" \
  "Reconcile: a local in_progress is kept when the provider cannot express it"
assert_contains "$drift_out" "row=- [~]" \
  "Reconcile: the in-flight row on disk is not rewritten back to open"
assert_contains "$drift_out" "skipped=True" \
  "Publish: a row with no stable id is reported as skipped, never silently passed over"
assert_contains "$drift_out" "skip-message=" "Publish: the skip names the row and the remedy"

F_FRONT="$(new_fixture)"
cat > "$F_FRONT/tasks/todo.md" <<'EOF'
# Plan

- [ ] Downstream work <!-- task-id: dep.downstream --> — high priority (blocked-by: dep.upstream)
- [ ] Upstream work <!-- task-id: dep.upstream --> — low priority
- [ ] Cycle one <!-- task-id: cyc.one --> — a (blocked-by: cyc.two)
- [ ] Cycle two <!-- task-id: cyc.two --> — b (blocked-by: cyc.one)
- [ ] Dangling <!-- task-id: dep.dangling --> — c (blocked-by: nothing.here)
EOF
cat > "$F_FRONT/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = local
EOF
printf '```\n' >> "$F_FRONT/docs/task-tracking.md"
front_out="$(run frontier --repo "$F_FRONT" --verbose 2>&1)"
front_code=$?
assert_eq "1" "$front_code" "Frontier: a dependency cycle makes the run fail"
assert_contains "$front_out" "dependency cycle" "Frontier: the cycle is named as a cycle"
assert_contains "$front_out" "cyc.one -> cyc.two -> cyc.one" \
  "Frontier: the cycle report names every task in it"
assert_contains "$front_out" "unknown-dependency" \
  "Frontier: a dependency naming no task is reported, not read as satisfied"
front_order="$(printf '%s\n' "$front_out" | grep -n '^  dep\.' | head -2)"
assert_contains "$front_order" "dep.upstream" \
  "Frontier: the task others wait on is listed before the task that waits"

# --- migrate: id collisions, block-bounded specs, dependency rewrites --------
F_MIG2="$(new_fixture)"
cat > "$F_MIG2/tasks/todo.md" <<'EOF'
# Task Plan

## Plan: Alpha
> Spec: specs/alpha.md

- [ ] Shared title <!-- task-id: alpha.shared-title --> — already has the id a mint would pick
- [ ] Shared title — the second one, which must not steal the same id

## Plan: Beta

- [ ] Beta work — no spec of its own, and must not inherit Alpha's
- [ ] Waits on the other one (blocked-by: Beta work)
EOF
printf '# Alpha\n' > "$F_MIG2/specs/alpha.md"
mig2_dry="$(run migrate --repo "$F_MIG2" 2>&1)"
assert_contains "$mig2_dry" "beta.beta-work" "Migrate: a second plan block mints under its own group"
mig2_ids="$(printf '%s\n' "$mig2_dry" | grep -o 'alpha\.shared-title[^ ]*' | sort -u | tr '\n' ' ')"
assert_contains "$mig2_ids" "alpha.shared-title-2" \
  "Migrate: a minted id never collides with an id already in the index"
assert_contains "$mig2_dry" "Dependency references to rewrite" \
  "Migrate: a dependency written as prose is resolved to the minted id"
run migrate --repo "$F_MIG2" --apply >/dev/null 2>&1
assert_file_contains "$F_MIG2/tasks/todo.md" "blocked-by: beta.beta-work" \
  "Migrate: --apply rewrites the dependency to the id it minted"
mig2_after="$(run frontier --repo "$F_MIG2" 2>&1)"
assert_not_contains "$mig2_after" "unknown-dependency" \
  "Migrate: after --apply the rewritten dependency resolves"
mig2_spec="$(printf '%s\n' "$mig2_dry" | grep 'beta.beta-work')"
assert_not_contains "$mig2_spec" "specs/alpha.md" \
  "Migrate: a spec lookback never crosses into the previous plan block"

F_MARK="$(new_fixture)"
cat > "$F_MARK/tasks/todo.md" <<'EOF'
# Task Plan

## Plan: Shipped work

- [x] Done row
- [ ] Left open when the plan closed

## Retrospective — 2026-08-13
- what happened
EOF
cat > "$F_MARK/docs/task-tracking.md" <<'EOF'
# Tracking

```ini
[tracker]
provider = local
closed_plan_marker = Retrospective
EOF
printf '```\n' >> "$F_MARK/docs/task-tracking.md"
mark_out="$(run migrate --repo "$F_MARK" 2>&1)"
assert_contains "$mark_out" "stale (open in a closed plan): 1" \
  "Migrate: a project's own closed-plan heading is honoured"
F_NOMARK="$(new_fixture)"
printf '# Task Plan\n\n## Plan: Ongoing\n\n- [ ] Still open\n' > "$F_NOMARK/tasks/todo.md"
nomark_out="$(run migrate --repo "$F_NOMARK" 2>&1)"
assert_contains "$nomark_out" "no 'Session Summary' heading found" \
  "Migrate: an index with no closed-plan marker says so instead of guessing"

# --- CLI: unexpected failures are redacted, exit codes are honest ------------
F_CRASH="$(new_fixture)"
printf '# Plan\n\n- [ ]\n' > "$F_CRASH/tasks/todo.md"
crash_code=0
run migrate --repo "$F_CRASH" --apply >/dev/null 2>&1 || crash_code=$?
assert_eq "1" "$crash_code" \
  "CLI: migrate --apply still exits non-zero when rows could not be read"

crash_out="$("$PY" - "$CLI" <<'EOF' 2>&1
import importlib.util, sys

spec = importlib.util.spec_from_file_location("task_registry_cli", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def explode(*args, **kwargs):
    raise RuntimeError("boom: Authorization: Basic ZmFrZTpsZWFrZWR0b2tlbnZhbHVl")


module._run = explode
print("exit=" + str(module.main([])))
EOF
)"
assert_contains "$crash_out" "exit=1" "CLI: an unexpected failure exits non-zero"
assert_contains "$crash_out" "credentials masked" \
  "CLI: an unexpected failure says the trace was scrubbed"
assert_not_contains "$crash_out" "ZmFrZTpsZWFrZWR0b2tlbnZhbHVl" \
  "CLI: an Authorization header in a traceback never reaches the terminal"

finish
