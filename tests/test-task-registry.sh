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
cleanup() {
  local d
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
from registry.index import MAX_LOGICAL_ROW_CHARS, TaskIndex, load_index, render_row
from registry.model import ExternalRef, Task
from registry.providers.github import _seed_body

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

legacy_multiline = TaskIndex(
    "tasks/todo.md",
    """[ ] TDD: `agent chat attachment starts recovery in the active owned thread` -> extend the composer and <!-- task-id: chat.recovery -->
    authenticated route using the existing protocol; record the file turn,

    restore state on reload.
- [ ] A later task <!-- task-id: later.task --> — remains separate
## A later section
    section prose is not task detail
""",
)
print("multiline-rows=" + str(len(legacy_multiline.rows)))
print("multiline-next=" + legacy_multiline.rows[1].task.title)
legacy_multiline = legacy_multiline.rows[0].task
print("multiline-title=" + legacy_multiline.title)
print("multiline-body=" + _seed_body(legacy_multiline).replace("\n", "|"))
detail_dash = TaskIndex(
    "tasks/todo.md",
    "[ ] TDD: `recover active thread` -> extend composer <!-- task-id: recovery.dash -->\n"
    "    preserve reloads — including attachments\n",
).rows[0].task
print("detail-dash=" + detail_dash.title + "|" + detail_dash.summary)
multiline_index = TaskIndex(
    "tasks/todo.md", "[ ] Ship recovery -> preserve state <!-- task-id: recovery.span -->\n    across reloads\n\n    after reconnect\n"
)
multiline_index.replace_row(1, "- [ ] Ship recovery <!-- task-id: recovery.span --> — preserve state across reloads")
print("multiline-rewrite=" + multiline_index.render().replace("\n", "|"))
generic_arrow = TaskIndex(
    "tasks/todo.md", "[ ] Ship recovery and -> preserve reload state <!-- task-id: recovery.ship -->\n"
).rows[0].task
print("generic-arrow=" + generic_arrow.title + "|" + generic_arrow.summary)
tight_arrow = TaskIndex(
    "tasks/todo.md", "[ ] TDD: `tight recovery`->preserve state <!-- task-id: recovery.tight -->\n"
).rows[0].task
print("tight-arrow=" + tight_arrow.title + "|" + tight_arrow.summary)
for label, canonical_text in (
    ("canonical-spaced", "[ ] Document transition <!-- task-id: docs.spaced --> — explain pending -> active behavior\n"),
    ("canonical-tight", "[ ] Document syntax <!-- task-id: docs.tight --> — explain a->b notation\n"),
):
    canonical = TaskIndex("tasks/todo.md", canonical_text).rows[0].task
    print(label + "=" + canonical.title + "|" + canonical.summary)
exact_rest = " Exact -> detail <!-- task-id: exact.limit -->"
oversized_detail = "x" * (MAX_LOGICAL_ROW_CHARS - len(exact_rest))
oversized = TaskIndex("tasks/todo.md", "[ ]" + exact_rest + "\n    " + oversized_detail + "\n")
print("oversized=" + "|".join(problem.message for problem in oversized.problems))
exact_detail = "x" * (MAX_LOGICAL_ROW_CHARS - len(exact_rest) - 1)
exact = TaskIndex("tasks/todo.md", "[ ]" + exact_rest + "\n    " + exact_detail + "\n")
print("exact-limit-rows=" + str(len(exact.rows)))
unbalanced_detail = TaskIndex(
    "tasks/todo.md",
    "[ ] Valid identity -> initial detail <!-- task-id: comment.balance -->\n"
    "    continuation <!-- unfinished\n",
)
print("unbalanced-detail=" + "|".join(problem.message for problem in unbalanced_detail.problems))
for label, malformed_comment in (
    ("stray-close", "[ ] Stray close -> detail -->\n"),
    ("nested-open", "[ ] Nested -> detail <!-- outer <!-- inner -->\n"),
):
    malformed = TaskIndex("tasks/todo.md", malformed_comment)
    print(label + "=" + "|".join(problem.message for problem in malformed.problems))
# The legacy-row publish diagnostics. Their only guards went with `publish`, but
# the messages did not: via load_index_strict they now refuse `upsert`, so they
# are load-bearing on a path `publish` never touched.
for label, legacy_text in (
    ("legacy-tdd-no-detail", "[ ] TDD: `some test` ->\n"),
    ("legacy-tdd-unquoted", "[ ] TDD: `` -> detail\n"),
    ("legacy-no-title", "[ ]  -> detail only\n"),
    ("legacy-two-arrows", "[ ] One -> two -> three\n"),
):
    legacy = TaskIndex("tasks/todo.md", legacy_text)
    print(label + "=" + "|".join(problem.message for problem in legacy.problems))
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
assert_contains "$index_out" \
  "multiline-title=agent chat attachment starts recovery in the active owned thread" \
  "Index: a legacy TDD row derives its title from the quoted deliverable"
assert_contains "$index_out" \
  "multiline-body=extend the composer and authenticated route using the existing protocol; record the file turn, restore state on reload." \
  "Index: a legacy row carries its complete implementation clause into the provider body"
assert_contains "$index_out" \
  "detail-dash=recover active thread|extend composer preserve reloads — including attachments" \
  "Index: punctuation in continuation detail cannot override header title derivation"
assert_contains "$index_out" "multiline-rows=2" \
  "Index: continuation capture stops before the next task and section"
assert_contains "$index_out" "multiline-next=A later task" \
  "Index: a task after legacy continuation detail remains independently parseable"
multiline_rewrite="$(printf '%s\n' "$index_out" | sed -n 's/^multiline-rewrite=//p')"
assert_eq "- [ ] Ship recovery <!-- task-id: recovery.span --> — preserve state across reloads|" \
  "$multiline_rewrite" \
  "Index: replacing a logical row consumes its original continuation span"
assert_contains "$index_out" "generic-arrow=Ship recovery|preserve reload state" \
  "Index: a non-TDD legacy arrow row separates detail and drops a dangling conjunction"
assert_contains "$index_out" "tight-arrow=tight recovery|preserve state" \
  "Index: a tight legacy arrow cannot bypass title and body derivation"
assert_contains "$index_out" "canonical-spaced=Document transition|explain pending -> active behavior" \
  "Index: a spaced arrow inside a canonical summary remains body text"
assert_contains "$index_out" "canonical-tight=Document syntax|explain a->b notation" \
  "Index: a tight arrow inside a canonical summary remains body text"
assert_contains "$index_out" "oversized=logical task row exceeds the 60000-character publish limit" \
  "Index: provider-bound logical rows have an explicit non-truncating size limit"
assert_contains "$index_out" "exact-limit-rows=1" \
  "Index: the 60000-character logical-row boundary remains publishable"
assert_contains "$index_out" "unbalanced-detail=unbalanced HTML comment in logical task row" \
  "Index: a valid ID cannot hide an unfinished comment in continuation detail"
assert_contains "$index_out" "stray-close=unbalanced HTML comment in logical task row" \
  "Index: a stray HTML comment close marker is refused"
assert_contains "$index_out" "nested-open=unbalanced HTML comment in logical task row" \
  "Index: nested HTML comment open markers are refused"
assert_contains "$index_out" "legacy-tdd-no-detail=cannot publish legacy TDD row" \
  "Index: a TDD row with no detail after '->' is reported, not parsed"
assert_contains "$index_out" "legacy-tdd-unquoted=cannot publish legacy TDD row" \
  "Index: a TDD row with an empty quoted test name is reported"
assert_contains "$index_out" "legacy-no-title=cannot publish legacy row: expected a clean title" \
  "Index: an arrow row with no title is reported"
assert_contains "$index_out" "legacy-two-arrows=cannot publish legacy row: multiple '->' delimiters are ambiguous" \
  "Index: two '->' delimiters are ambiguous rather than silently split on the first"
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
provider = local
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
assert_contains "$conf_out" "provider=local" "Config: explicit provider is read"
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
# Unchanged by the routine work, deliberately. Routine selection reads
# [routines.selectors], never this map, and this map is bidirectional: the GitHub
# provider reverse-looks-up kind -> label to decide what to stamp on a published
# issue. Adding `tech-debt = task` here labelled every published task `tech-debt`
# (specs/category-routines.md AC12, and the guard in test-routine-selectors.sh).
assert_contains "$noconf_out" "bug->bug,design-decision->decision,enhancement->feature" \
  "Config: the shipped default mapping matches the repository's existing label vocabulary"
assert_contains "$noconf_out" "question-default=None" \
  "Config: 'question' is unmapped by default — it is ambiguous, so it needs configuring"

# malformed configuration fails loudly through the CLI
F_BADCONF="$(new_fixture)"
write_index "$F_BADCONF"
printf '# Tracking\n\nno fenced block here\n' > "$F_BADCONF/docs/task-tracking.md"
badconf_out="$(run selectors --repo "$F_BADCONF" 2>&1)"
badconf_code=$?
assert_eq "1" "$badconf_code" "Config: a configuration file with no ini block exits non-zero"
assert_contains "$badconf_out" "no \`\`\`ini configuration block found" \
  "Config: the failure names what is missing"

F_UNKPROV="$(new_fixture)"
write_index "$F_UNKPROV"
printf '# T\n\n```ini\n[tracker]\nprovider = trello\n```\n' > "$F_UNKPROV/docs/task-tracking.md"
unkprov_out="$(run selectors --repo "$F_UNKPROV" 2>&1)"
unkprov_code=$?
assert_eq "1" "$unkprov_code" "Config: an unknown provider exits non-zero"
assert_contains "$unkprov_out" "unknown provider 'trello'" "Config: the failure names the bad provider"

# A retired provider is the likeliest real encounter with Cut 1: a downstream
# project whose checked-in config still says `provider = jira`. It must be
# refused by the same path as a name that never existed, and the refusal must
# enumerate what actually ships — this pins `config.PROVIDERS`, which the
# `--provider` override path does not reach.
F_RETPROV="$(new_fixture)"
write_index "$F_RETPROV"
printf '# T\n\n```ini\n[tracker]\nprovider = jira\n```\n' > "$F_RETPROV/docs/task-tracking.md"
retprov_out="$(run doctor --repo "$F_RETPROV" 2>&1)"
retprov_code=$?
# Exit 1, not 2: a config fault raised out of `load_config` reaches the CLI's
# unexpected-failure handler rather than the configuration branch. That is
# pre-existing behaviour for every malformed config (the `trello` case above
# exits 1 too), so it is pinned as-is rather than changed inside a deletion.
assert_eq "1" "$retprov_code" "Config: a config declaring a retired provider exits non-zero"
assert_contains "$retprov_out" "retired provider 'jira'" \
  "Config: a retired provider is called retired, not unknown — it was valid one sync ago"
assert_contains "$retprov_out" "Set \`provider = github\` or" \
  "Config: the refusal tells the operator what to change it to"
assert_contains "$retprov_out" "expected one of: github, local" \
  "Config: the refusal enumerates the providers that ship, and jira is not among them"

# Three pointer states, and only the first is silent (#82). "No pointer" is an
# unconfigured project and defaults silently. "Pointer -> existing file" loads
# it. "Pointer -> missing file" is a CONFIGURED project, broken: folding it into
# the first state made every consumer run on defaults while its own project
# instructions claimed otherwise, and nothing said so.
F_NOPTR="$(new_fixture)"
write_index "$F_NOPTR"
noptr_out="$(run doctor --repo "$F_NOPTR" 2>&1)"
noptr_code=$?
assert_eq "0" "$noptr_code" "Pointer states: no pointer — defaults, exit 0"
assert_contains "$noptr_out" "configuration:  none (defaults + local fallback)" \
  "Pointer states: no pointer — reported as none"
assert_not_contains "$noptr_out" "BROKEN" \
  "Pointer states: no pointer — no new noise on the common path"

F_PTROK="$(new_fixture)"
write_index "$F_PTROK"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_PTROK/docs/tracking.md"
printf 'Task tracking instructions: docs/tracking.md\n' > "$F_PTROK/CLAUDE.md"
ptrok_out="$(run doctor --repo "$F_PTROK" 2>&1)"
ptrok_code=$?
assert_eq "0" "$ptrok_code" "Pointer states: pointer to an existing file — exit 0"
assert_contains "$ptrok_out" "configuration:  docs/tracking.md" \
  "Pointer states: pointer to an existing file — that file is loaded"

F_PTRMISS="$(new_fixture)"
write_index "$F_PTRMISS"
printf 'Task tracking instructions: docs/tracking.md\n' > "$F_PTRMISS/CLAUDE.md"
ptrmiss_doctor="$(run doctor --repo "$F_PTRMISS" 2>&1)"
ptrmiss_code=$?
assert_eq "1" "$ptrmiss_code" "Pointer states: pointer to a missing file — doctor exits non-zero"
assert_contains "$ptrmiss_doctor" "configuration:  BROKEN" \
  "Pointer states: pointer to a missing file — doctor reports BROKEN, not none"
assert_contains "$ptrmiss_doctor" "CLAUDE.md declares" \
  "Pointer states: the fault names where the pointer was declared"
assert_contains "$ptrmiss_doctor" "'docs/tracking.md' does not exist" \
  "Pointer states: the fault names the declared path"
assert_contains "$ptrmiss_doctor" "templates/task-tracking.md" \
  "Pointer states: the fault says how to fix it"
assert_contains "$ptrmiss_doctor" "Every command except this one refuses to run until it is fixed." \
  "Pointer states: doctor says the fault blocks every other command"
assert_contains "$ptrmiss_doctor" "provider:" \
  "Pointer states: the rest of the diagnosis still renders"
assert_not_contains "$ptrmiss_doctor" "MISCONFIGURED" \
  "Pointer states: the fault sits on the configuration line, not the routines line"
assert_eq "different" "$([ "$noptr_out" = "$ptrmiss_doctor" ] && echo same || echo different)" \
  "Pointer states: a broken declaration is distinguishable from no declaration"
ptrmiss_rec="$(run selectors --repo "$F_PTRMISS" 2>&1)"
ptrmiss_rec_code=$?
assert_eq "1" "$ptrmiss_rec_code" \
  "Pointer states: every command except doctor refuses to run on a broken pointer"
assert_contains "$ptrmiss_rec" "task-registry: CLAUDE.md declares" \
  "Pointer states: the refusal carries the same fault text"

# First pointer wins, broken or not: a dangling project-owned pointer is not
# rescued by a valid template-managed one further down the search order. The
# most authoritative declaration is the one that is wrong, and that is what the
# user must hear.
F_PTRPREC="$(new_fixture)"
write_index "$F_PTRPREC"
mkdir -p "$F_PTRPREC/.claude"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_PTRPREC/docs/tracking.md"
printf 'Task tracking instructions: docs/missing.md\n' > "$F_PTRPREC/.claude/project.md"
printf 'Task tracking instructions: docs/tracking.md\n' > "$F_PTRPREC/CLAUDE.md"
ptrprec_out="$(run selectors --repo "$F_PTRPREC" 2>&1)"
ptrprec_code=$?
assert_eq "1" "$ptrprec_code" \
  "Pointer states: a broken project-owned pointer is not rescued by a later valid one"
assert_contains "$ptrprec_out" ".claude/project.md declares" \
  "Pointer states: the refusal names the project-owned file, not the template one"

# The refusal is the only place repository text reaches a terminal or an agent's
# context unparsed, so the declared path is echoed escaped (repr), the way
# `confine` already renders an escaping pointer — an ESC byte the regex admits
# must not pass through raw. And a target that exists but is a directory is
# named as such: "does not exist — create it" would send the user to create
# something that is already there.
F_PTRDIR="$(new_fixture)"
write_index "$F_PTRDIR"
printf 'Task tracking instructions: docs\n' > "$F_PTRDIR/CLAUDE.md"
ptrdir_out="$(run doctor --repo "$F_PTRDIR" 2>&1)"
assert_contains "$ptrdir_out" "'docs' exists but is not a file" \
  "Pointer states: a pointer to a directory is not reported as missing"
assert_not_contains "$ptrdir_out" "does not exist" \
  "Pointer states: a directory target never gets the create-it advice"
F_PTRESC="$(new_fixture)"
write_index "$F_PTRESC"
printf 'Task tracking instructions: \033[31mdocs/x.md\n' > "$F_PTRESC/CLAUDE.md"
ptresc_out="$(run doctor --repo "$F_PTRESC" 2>&1)"
assert_contains "$ptresc_out" "'\\x1b[31mdocs/x.md' does not exist" \
  "Pointer states: the declared path is echoed escaped, never raw"
assert_eq "0" "$(printf '%s' "$ptresc_out" | grep -c $'\033' || true)" \
  "Pointer states: no raw ESC byte reaches the output"

# A refusal is only earned by a genuine declaration. The regex admits any
# non-space run after the colon, so a prose mention that ends its sentence —
# `...: docs/tracking.md.` — must name `docs/tracking.md`, not `docs/tracking.md.`;
# otherwise a project that worked yesterday refuses today over a full stop.
F_PTRPROSE="$(new_fixture)"
write_index "$F_PTRPROSE"
mkdir -p "$F_PTRPROSE/.claude"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_PTRPROSE/docs/tracking.md"
printf 'See the Task tracking instructions: docs/tracking.md. It is optional.\n' > "$F_PTRPROSE/.claude/project.md"
ptrprose_out="$(run doctor --repo "$F_PTRPROSE" 2>&1)"
ptrprose_code=$?
assert_eq "0" "$ptrprose_code" \
  "Pointer states: sentence punctuation after the path is not part of the path"
assert_contains "$ptrprose_out" "configuration:  docs/tracking.md" \
  "Pointer states: the prose mention resolves to the file it names"

# A run that is nothing but punctuation (`Task tracking instructions: ...`) is a
# sentence fragment, not a path — it must read as "no pointer", not as a
# pointer to a file called `...`.
F_PTRDOTS="$(new_fixture)"
write_index "$F_PTRDOTS"
printf 'Task tracking instructions: ...\n' > "$F_PTRDOTS/CLAUDE.md"
ptrdots_out="$(run doctor --repo "$F_PTRDOTS" 2>&1)"
ptrdots_code=$?
assert_eq "0" "$ptrdots_code" \
  "Pointer states: a punctuation-only pointer is no pointer — exit 0"
assert_contains "$ptrdots_out" "configuration:  none (defaults + local fallback)" \
  "Pointer states: a punctuation-only pointer falls back to defaults"

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

# A retired provider is refused by name, and the refusal lists what survives.
# Silently falling back would route a project that asked for a tracker we no
# longer ship into the local store without saying so.
sel_retired="$(run doctor --repo "$F_SEL" --provider jira 2>&1)"
sel_retired_code=$?
assert_eq "2" "$sel_retired_code" \
  "Selection: an override naming a retired provider exits 2 (misconfiguration)"
assert_contains "$sel_retired" "unknown provider" \
  "Selection: the refusal says the provider is unknown"
assert_contains "$sel_retired" "github" \
  "Selection: the refusal lists the providers that do exist"
assert_not_contains "$sel_retired" "jira, local" \
  "Selection: jira is gone from the available-provider list, not just from the dict"

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

# A `gh` older than the release that added an optional issue field rejects the
# whole query client-side, so asking for it unconditionally turns every read into
# a hard failure. The field is optional to us; the run must degrade, not die.
github_old_gh_out="$(pyreg <<'EOF'
from registry.config import Config
from registry.providers.base import ProviderError
from registry.providers.github import GitHubProvider

class OldGh(GitHubProvider):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.attempts = []

    def _run(self, command, check=True):
        fields = command[command.index("--json") + 1]
        self.attempts.append(fields)
        if "closedByPullRequestsReferences" in fields:
            raise ProviderError(
                "github: `gh issue list` exited 1 — Unknown JSON field: "
                '"closedByPullRequestsReferences"'
            )
        return 0, '[{"number": 7, "title": "old gh", "state": "OPEN", "url": "", "labels": []}]'

provider = OldGh(Config(root=".", repository="owner/repo"))
tasks = provider.list_tasks()
print("count=%d" % len(tasks))
print("linked=" + tasks[0].extra.get("unresolved_linked_pr", "unset"))
print("attempts=%d" % len(provider.attempts))
print("degraded=" + ("yes" if any("closedByPullRequestsReferences" in n for n in provider.limitations) else "no"))

strict = OldGh(Config(root=".", repository="owner/repo"))
strict.__class__._run = lambda self, command, check=True: (_ for _ in ()).throw(
    ProviderError('github: `gh issue list` exited 1 — Unknown JSON field: "title"')
)
try:
    strict.list_tasks()
    print("required=dropped")
except ProviderError:
    print("required=refused")
EOF
)"
assert_contains "$github_old_gh_out" "count=1" \
  "GitHub: an unsupported optional field degrades the read instead of failing it"
assert_contains "$github_old_gh_out" "linked=unset" \
  "GitHub: a degraded read reports linked-PR state as unknown, never as clean"
assert_contains "$github_old_gh_out" "attempts=2" \
  "GitHub: the field is dropped and the read retried exactly once"
assert_contains "$github_old_gh_out" "degraded=yes" \
  "GitHub: the dropped field is recorded as a limitation, not silently swallowed"
assert_contains "$github_old_gh_out" "required=refused" \
  "GitHub: an unknown *required* field still fails — only optional ones are dropped"

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

# The write gate itself survives the sync engine: `upsert` is now the command
# that reaches a provider, so it is where "unreachable means refuse, never
# half-write" is pinned.
gh_unauth_write="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-unauth2.log" GH_MOCK_UNAUTH=1 \
  run upsert ops.unreachable --repo "$F_GH" --title 'Written while offline' --apply --approve 2>&1)"
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
assert_not_contains "$(cat "$F_GH/gh-unauth2.log")X" "issue create" \
  "GitHub: no create call is attempted while unauthenticated"

# A local-pending write must not replace a previously published tracker address.
# The fake external provider deliberately cannot find the task by stable ID: the
# second run can succeed only if upsert consults the preserved index reference.
F_PUBLISHED_REF="$(new_fixture)"
write_index "$F_PUBLISHED_REF"
sed -i 's|— ship the live grid morph (blocked-by: recipe.color-lut)|— ship the live grid morph ([#42](https://github.com/fixture-owner/fixture-repo/issues/42)) (blocked-by: recipe.color-lut)|' "$F_PUBLISHED_REF/tasks/todo.md"
published_ref_out="$(cd "$F_PUBLISHED_REF" && pyreg <<'EOF'
from registry.config import load_config
from registry.model import Task
from registry.providers.base import ProviderStatus, WriteGate
from registry.upsert import upsert_task

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

first_lines, first_code = upsert_task(registry, task, apply=True)
provider.gate.approved = True
second_lines, second_code = upsert_task(registry, task, apply=True)
index = open("tasks/todo.md", encoding="utf-8").read()
print("first-code=" + str(first_code))
print("first-output=" + " | ".join(first_lines))
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


# =============================================================================
# 10. Migration — an ascii_video_pipeline-shaped repository
#
# The migration moved out of the skill in Cut 1 (specs/workflow-routing.md) and
# is now `scripts/migrate-task-registry.py`. These assertions are deliberately
# the same ones the subcommand had: a remedy that is documented but never
# exercised is not a remedy, and the one-shot has to keep behaving identically
# for the projects the retired command was the only answer for.
# =============================================================================
MIGRATE="$REPO/scripts/migrate-task-registry.py"

# The subcommand is gone, and it fails as an unknown command rather than as a
# broken import — a project that scripted it learns that from the CLI.
mig_retired="$(run migrate --repo "$REPO" 2>&1)"
mig_retired_code=$?
assert_eq "2" "$mig_retired_code" "Migrate: the retired subcommand exits 2 as unknown"
assert_contains "$mig_retired" "invalid choice: 'migrate'" \
  "Migrate: argparse refuses `migrate` by name"

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
assert_ne_zero() { [ "$1" -gt 0 ]; }
if assert_ne_zero "$mig_import_lines"; then
  _TESTS=$((_TESTS + 1)); printf '  ok   %s\n' \
    "Migrate: the import-line pattern matches this grep (found $mig_import_lines lines)"
else
  _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1)); printf '  FAIL %s\n' \
    "Migrate: the import-line pattern matched nothing -- the guard below is vacuous here"
fi
mig_imports="$(grep -nE "^[[:space:]]*(from|import)[[:space:]]" "$MIGRATE" | grep -E "registry|skills" || true)"
assert_eq "" "$mig_imports" \
  "Migrate: the one-shot imports nothing from the skill (offenders: ${mig_imports:-none})"

# Execution beats inspection: run it against a tree with both Cut 2 casualties
# actually deleted. This is the assertion the todo row's wording claims.
F_CUT2="$(new_fixture)"
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
F_BOM="$(new_fixture)"
printf '\xef\xbb\xbf- [ ] First row\n- [ ] Second row\n' > "$F_BOM/tasks/todo.md"
bom_out="$("$PY" "$MIGRATE" --repo "$F_BOM" 2>&1)"
assert_contains "$bom_out" "rows scanned:        2" \
  "Migrate: a BOM on the first row does not hide it from the one-shot"
bom_live="$(cd "$F_BOM" && pyreg <<'EOF'
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
F_TDD="$(new_fixture)"
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
F_SUP="$(new_fixture)"
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
F_NOIDX="$(new_fixture)"
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
F_ESCM="$(new_fixture)"
printf '# Plan\n\n- [ ] Row\n' > "$F_ESCM/tasks/todo.md"
mkdir -p "$F_ESCM/../escape-probe" 2>/dev/null || true
esc_out="$("$PY" "$MIGRATE" --repo "$F_ESCM" --index ../escape-probe/todo.md --apply 2>&1)"
esc_code=$?
assert_eq "2" "$esc_code" "Migrate: a path escaping --repo is refused, exit 2"
assert_contains "$esc_out" "resolves outside" \
  "Migrate: the refusal says the path left the declared root"
rm -rf "$F_ESCM/../escape-probe"

# The path flags are the port's own invention; nothing else exercises them.
F_FLAGS="$(new_fixture)"
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
F_BADSPEC="$(new_fixture)"
printf '# Plan\n\n## Plan: Thing\n> Spec: specs/locked.md\n\n- [ ] Row\n' > "$F_BADSPEC/tasks/todo.md"
printf '# Locked\n\n> Superseded by: specs/other.md\n' > "$F_BADSPEC/specs/locked.md"
chmod 000 "$F_BADSPEC/specs/locked.md"
badspec_out="$("$PY" "$MIGRATE" --repo "$F_BADSPEC" 2>&1)"
badspec_code=$?
chmod 644 "$F_BADSPEC/specs/locked.md"
if [ "$badspec_code" = "0" ]; then
  _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
  printf '  FAIL %s\n' "Migrate: an unreadable spec must not report success (exit was 0)"
else
  _TESTS=$((_TESTS + 1))
  printf '  ok   %s\n' "Migrate: an unreadable spec fails the run rather than misclassifying silently"
fi
assert_contains "$badspec_out" "cannot read" \
  "Migrate: the unreadable spec is named in the report, not just on stderr"

# `missing-id` was a reconcile diagnostic and died with it, so the migration's
# outcome is now read off the index itself: every active row carries a stable id
# and the file still parses clean.
post_mig="$(cd "$F_MIG" && pyreg <<'EOF'
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

no_dir_out="$(run selectors --repo "$F_CLI/nope" 2>&1)"
no_dir_code=$?
assert_eq "2" "$no_dir_code" "CLI: a missing project root is a usage error"
assert_contains "$no_dir_out" "no such directory" "CLI: the usage error names the missing path"

# `--dry-run` beating `--apply` is decided in main() for every gated command,
# so `upsert` pins it for all of them.
dry_wins="$(run upsert cli.dry --repo "$F_CLI" --title 'Dry run wins' --apply --dry-run 2>&1)"
assert_contains "$dry_wins" "would create" "CLI: --dry-run overrides --apply"

run selectors --repo "$F_CLI" --report "$F_CLI/report.txt" >/dev/null 2>&1
assert_file_contains "$F_CLI/report.txt" "selectors:" \
  "CLI: --report writes the same output to a file"

for command in doctor selectors; do
  out="$(run "$command" --repo "$F_CLI" 2>&1)"
  code=$?
  assert_eq "0" "$code" "CLI: '$command' runs clean on a well-formed repository"
done

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
    "- [ ] Foreign tracker ([REG-4](https://tracker.example.com/browse/REG-4)) <!-- task-id: foreign.one -->",
])
index = TaskIndex("tasks/todo.md", text, "tasks/todo.md")
by_id = {row.task.id: row for row in index.rows}
print("title=" + by_id["bug.aliasing"].task.title)
print("indent=[" + by_id["bug.aliasing.child"].indent + "]")
child = by_id["bug.aliasing.child"]
print("rerendered-indent=[" + render_row(child.task, child.indent)[:2] + "]")
print("crafted-parsed=" + str("evil.one" in by_id))
print("crafted-problem=" + str(any("body-file" in p.message for p in index.problems)))
print("foreign-provider=" + by_id["foreign.one"].task.external.provider)
label = render_row(Task(id="j", title="J", external=ExternalRef("local", "REG-4", "u")))
print("foreign-label-plain=" + str("[REG-4]" in label and "#REG-4" not in label))
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
assert_contains "$index_reg" "foreign-provider=local" \
  "Index: a URL no shipped provider owns falls back to local, never to a guess"
assert_contains "$index_reg" "foreign-label-plain=True" \
  "Index: a non-GitHub reference renders as its own key, not as #key"
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
from registry.config import Config, ConfigError, load_config
from registry.redaction import redactor_for

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

# A retired provider must leave no half-configuration behind: a `jira_*` field
# surviving on Config is a credential slot nothing fills and nothing redacts.
print("jira-attrs=" + str(sorted(a for a in dir(Config(root=".")) if "jira" in a.lower())))
# Dropping the configured-secret list must not cost the generic scrubbing. The
# masker keeps its own patterns, so an Authorization header and the password half
# of URL userinfo are still masked with no secret registered at all.
#
# Scope, stated rather than implied: pattern 3 requires a scheme, so userinfo in
# text that names the host WITHOUT `https://` is not matched. That is precisely
# the case the deleted `_url_credentials` existed for. Nothing leaks today, since
# no shipped provider keeps a URL credential in config -- but the gap is real and
# is asserted below as a known gap rather than left for someone to discover.
redactor = redactor_for(Config(root="."))
print("mask-auth=" + redactor.scrub("Authorization: Basic ZmFrZTp0b2tlbg=="))
print("mask-userinfo=" + redactor.scrub("https://user:sup3rsecretvalue@site.example/x"))
print("leaks-userinfo=" + str("sup3rsecretvalue" in redactor.scrub(
    "https://user:sup3rsecretvalue@site.example/x")))
print("no-scheme-gap=" + str("sup3rsecretvalue" in redactor.scrub(
    "cannot reach user:sup3rsecretvalue@site.example")))

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
assert_contains "$cfg_reg" "jira-attrs=[]" \
  "Config: a retired provider leaves no credential field behind on Config"
assert_contains "$cfg_reg" "mask-auth=Authorization: ***REDACTED***" \
  "Redaction: an Authorization header is masked with no configured secret"
assert_contains "$cfg_reg" "mask-userinfo=https://user:***REDACTED***@site.example/x" \
  "Redaction: the password is masked and the username is preserved"
assert_contains "$cfg_reg" "leaks-userinfo=False" \
  "Redaction: the with-scheme userinfo pattern still masks the password half"
assert_contains "$cfg_reg" "no-scheme-gap=True" \
  "Redaction: userinfo without a scheme is a KNOWN gap — a provider carrying a URL credential must register it through redactor_for, not rely on the patterns"

# The configured-secret path has no production caller since Cut 1 (redactor_for
# returns Redactor([])), and the assertions that exercised it lived in the Jira
# block this cut deleted. The seam is kept deliberately, so it is tested
# deliberately -- an untested seam is not a seam, and the next provider to carry
# a credential inherits this mechanism.
redactor_unit="$(pyreg <<'EOF'
from registry.redaction import Redactor
print("registered=" + Redactor(["sup3rsecretvalue"]).scrub("saw sup3rsecretvalue here"))
print("short-filtered=" + Redactor(["ab"]).scrub("saw ab here"))
merged = Redactor(["alpha-secret"])
merged.adopt(Redactor(["beta-secret"]))
print("adopted=" + merged.scrub("alpha-secret and beta-secret"))
EOF
)"
assert_contains "$redactor_unit" "registered=saw ***REDACTED*** here" \
  "Redaction: a registered secret is masked wherever it appears"
assert_contains "$redactor_unit" "short-filtered=saw ab here" \
  "Redaction: a secret under four characters is not registered -- it would mask prose"
assert_contains "$redactor_unit" "adopted=***REDACTED*** and ***REDACTED***" \
  "Redaction: adopt() merges both sets, so a late-loaded credential is still masked"

# A pointer that escapes the repository must not be followed — and must not be
# silently skipped either. It is a declared intent with a broken target, the
# same shape as a missing file (#82), and the configuration guide already
# documents escapes as refused. The declared string is echoed, never opened.
F_ESC="$(new_fixture)"
printf 'Task tracking instructions: ../../../etc/passwd\n' > "$F_ESC/AGENTS.md"
esc_out="$(cd "$F_ESC" && pyreg <<'EOF'
from registry.config import ConfigError, find_config_path
try:
    print("resolved=" + str(find_config_path(".")))
except ConfigError as exc:
    print("refused=" + str(exc))
EOF
)"
assert_contains "$esc_out" "refused=" \
  "Config: a pointer resolving outside the project root is refused, not silently skipped"
assert_contains "$esc_out" "AGENTS.md" \
  "Config: the refusal names the file that declared the escaping pointer"
assert_contains "$esc_out" "outside the project root" \
  "Config: the refusal says why"

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
offline_pub="$(run upsert offline.record --repo "$F_OFFLINE" --title 'Recorded offline' --apply 2>&1)"
offline_code=$?
assert_eq "0" "$offline_code" \
  "Local: --apply alone writes offline — approval gates external writes only"
assert_contains "$offline_pub" "created" "Local: the offline write actually created the task"

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
mig2_dry="$("$PY" "$MIGRATE" --repo "$F_MIG2" 2>&1)"
assert_contains "$mig2_dry" "beta.beta-work" "Migrate: a second plan block mints under its own group"
mig2_ids="$(printf '%s\n' "$mig2_dry" | grep -o 'alpha\.shared-title[^ ]*' | sort -u | tr '\n' ' ')"
assert_contains "$mig2_ids" "alpha.shared-title-2" \
  "Migrate: a minted id never collides with an id already in the index"
assert_contains "$mig2_dry" "Dependency references to rewrite" \
  "Migrate: a dependency written as prose is resolved to the minted id"
"$PY" "$MIGRATE" --repo "$F_MIG2" --apply >/dev/null 2>&1
assert_file_contains "$F_MIG2/tasks/todo.md" "blocked-by: beta.beta-work" \
  "Migrate: --apply rewrites the dependency to the id it minted"
# `frontier` used to answer this by resolving the dependency graph; it went with
# the sync engine. The property it pinned -- that the rewritten `blocked-by`
# names a task that actually exists -- is checked directly against the index,
# which is where the answer lived all along.
mig2_after="$(pyreg <<PYEOF
from registry.index import load_index
index = load_index("$F_MIG2/tasks/todo.md", "tasks/todo.md")
ids = {row.task.id for row in index.rows}
blockers = {b for row in index.rows for b in row.task.depends_on}
print("dangling=" + ",".join(sorted(blockers - ids)) if blockers - ids else "dangling=none")
print("blockers=" + ",".join(sorted(blockers)))
PYEOF
)"
assert_contains "$mig2_after" "dangling=none" \
  "Migrate: after --apply the rewritten dependency resolves to a task in the index"
assert_contains "$mig2_after" "blockers=beta.beta-work" \
  "Migrate: the rewritten dependency is the minted id, not the original prose"
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
mark_out="$("$PY" "$MIGRATE" --repo "$F_MARK" --closed-plan-marker Retrospective 2>&1)"
assert_contains "$mark_out" "stale (open in a closed plan): 1" \
  "Migrate: a project's own closed-plan heading is honoured"
# ... and without the flag the same repository reads that block as still open,
# which is what makes the assertion above about the flag rather than the fixture.
mark_default="$("$PY" "$MIGRATE" --repo "$F_MARK" 2>&1)"
assert_contains "$mark_default" "stale (open in a closed plan): 0" \
  "Migrate: the default marker does not silently match a project's own heading"
F_NOMARK="$(new_fixture)"
printf '# Task Plan\n\n## Plan: Ongoing\n\n- [ ] Still open\n' > "$F_NOMARK/tasks/todo.md"
nomark_out="$("$PY" "$MIGRATE" --repo "$F_NOMARK" 2>&1)"
assert_contains "$nomark_out" "no 'Session Summary' heading found" \
  "Migrate: an index with no closed-plan marker says so instead of guessing"

# --- CLI: unexpected failures are redacted, exit codes are honest ------------
F_CRASH="$(new_fixture)"
printf '# Plan\n\n- [ ]\n' > "$F_CRASH/tasks/todo.md"
crash_code=0
"$PY" "$MIGRATE" --repo "$F_CRASH" --apply >/dev/null 2>&1 || crash_code=$?
assert_eq "1" "$crash_code" \
  "Migrate: --apply still exits non-zero when rows could not be read"

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

# The degraded-link branch is shared provider code, not Jira code: GitHub returns
# native=False from BOTH link operations, so `LinkResult.render()`'s "inferred"
# arm is the one every real GitHub link takes. Its only assertions lived in the
# Jira block Cut 1 deleted, and the surviving link assertions are the local
# provider's, which are both native=True. Restored here against the gh mock.
gh_links="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-links.log" pyreg <<'EOF'
from registry.config import load_config
from registry.model import ExternalRef, Task
from registry.providers import build_provider
from registry.providers.base import WriteGate

BASE = "https://github.com/fixture-owner/fixture-repo/issues"
provider = build_provider("github", load_config("."), WriteGate(apply=True, require_approval=False))
# Both ends must be real issues: linking writes through update_task, which
# refuses a task with no issue reference.
child = Task(id="recipe.morph-live-grid", title="Morph live grid recipe",
             external=ExternalRef("github", "42", f"{BASE}/42"))
parent = Task(id="recipe.color-lut", title="Colour LUT loader",
              external=ExternalRef("github", "43", f"{BASE}/43"))
parent_link = provider.link_parent(child, parent)
dep_link = provider.add_dependency(child, parent)
print("parent-native=" + str(parent_link.native))
print("dep-native=" + str(dep_link.native))
print("parent-render=" + parent_link.render())
print("dep-render=" + dep_link.render())
print("limitations=" + "|".join(provider.limitations))
EOF
)"
assert_contains "$gh_links" "parent-native=False" \
  "GitHub: hierarchy is declared non-native rather than silently claimed"
assert_contains "$gh_links" "dep-native=False" \
  "GitHub: dependencies are declared non-native rather than silently claimed"
assert_contains "$gh_links" "inferred (stored in task metadata)" \
  "GitHub: a degraded link renders as inferred, naming where the relationship went"
assert_contains "$gh_links" "parent-render=parent: recipe.morph-live-grid -> recipe.color-lut" \
  "GitHub: the rendered link names both ends of the relationship"
assert_contains "$gh_links" "expose no parent link through gh" \
  "GitHub: the limitation is surfaced, not swallowed"

assert_file_contains "$SKILL/templates/task-tracking.md" "## Naming conventions" \
  "Template: projects get a stub for provider-facing title and label conventions"
assert_file_contains "$SKILL/templates/task-tracking.md" "Never publish raw plan text" \
  "Template: legacy implementation clauses are documented as provider body content"
assert_not_contains "$(cat "$SKILL/templates/task-tracking.md")" '<PLAN-ID> —' \
  "Template: the recommended title separator cannot collide with row summary serialization"

# =============================================================================
# 13. Cut 2 — the sync engine is gone; progressive disclosure survives it
# =============================================================================
# `show` was the one surviving command implemented as a `Registry` *method*, so
# it could not stay where it was. These assertions pin the boundary the cut
# creates: the sync modules are absent, their commands are unknown, and reading
# one task still works from the module that inherited it.

nonzero() { [ "$1" -ne 0 ] && echo nonzero || echo zero; }

assert_eq "absent" "$([ -f "$SCRIPTS/registry/reconcile.py" ] && echo present || echo absent)" \
  "Cut 2: registry/reconcile.py is deleted"
assert_eq "" "$(grep -rln 'from \.reconcile\|registry\.reconcile' "$SCRIPTS" || true)" \
  "Cut 2: no module still imports the deleted sync engine"
# `index.py` outlives the cut on purpose. Two survivors read through it -- `show`
# for the row behind a reference, and `upsert` for the external ref the local
# store cannot remember -- so deleting it would mean deleting them. What retires
# is the part only the sync engine called.
for retired in collect_problems row_text replace_line; do
  assert_eq "" "$(grep -n "def $retired" "$SCRIPTS/registry/index.py" || true)" \
    "Cut 2: index.py no longer carries the sync-only helper $retired"
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
F_SHOW="$(new_fixture)"
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
  gone_out="$(run "$gone" --repo "$F_SHOW" 2>&1)"; gone_code=$?
  assert_eq "nonzero" "$(nonzero "$gone_code")" "Cut 2: \`$gone\` is not a command any more"
  assert_contains "$gone_out" "invalid choice" "Cut 2: \`$gone\` is rejected by name"
done

show_prov="$(run show show.color-lut --repo "$F_SHOW" 2>&1)"; show_prov_code=$?
assert_eq "0" "$show_prov_code" "Show: a provider-backed task exits 0"
assert_contains "$show_prov" "kind:     bug" "Show: the full record includes the kind"
assert_contains "$show_prov" "eight-bit sources load without a colour shift" \
  "Show: acceptance criteria are disclosed on demand"
assert_contains "$show_prov" "external: local:show.color-lut" \
  "Show: the external reference is named"

show_local="$(run show show.index-only --repo "$F_SHOW" 2>&1)"; show_local_code=$?
assert_eq "0" "$show_local_code" "Show: a row the provider has never seen still resolves"
assert_contains "$show_local" "never published anywhere" \
  "Show: the local index row supplies the detail when the provider has none"
assert_contains "$show_local" "index row: tasks/todo.md" \
  "Show: the row's source file is named"

show_miss="$(run show no-such-task --repo "$F_SHOW" 2>&1)"; show_miss_code=$?
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
F_BAD="$(new_fixture)"
printf '# Plan\n\n- [ ] Broken row <!-- task-id: dup.target\n- [ ] Fine row <!-- task-id: ok.other --> — parses\n' > "$F_BAD/tasks/todo.md"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_BAD/docs/task-tracking.md"

bad_show="$(run show ok.other --repo "$F_BAD" 2>&1)"; bad_show_code=$?
assert_eq "0" "$bad_show_code" \
  "Malformed index: show still answers for a row that parses"
bad_show_degraded="$(printf '%s\n' "$bad_show" | sed -n '/^  degraded:$/,/^  [a-z]*:$/p')"
assert_contains "$bad_show_degraded" "tasks/todo.md:3" \
  "Malformed index: show names the broken row with file:line, in the degraded block"
assert_contains "$bad_show_degraded" "unbalanced HTML comment" \
  "Malformed index: show names the fault, not just the line"

bad_up="$(run upsert dup.target --repo "$F_BAD" --title 'Broken row' --apply 2>&1)"; bad_up_code=$?
assert_eq "1" "$bad_up_code" "Malformed index: upsert refuses before any provider write"
assert_contains "$bad_up" "tasks/todo.md:3" "Malformed index: upsert's refusal carries file:line"
assert_eq "1" "$(grep -c 'dup.target' "$F_BAD/tasks/todo.md")" \
  "Malformed index: no second row is appended for a row that failed to parse"

# The dry run must refuse identically, or the preview describes a different run
# than `--apply` performs -- which is the divergence resolve_destination argues against.
bad_dry="$(run upsert dup.target --repo "$F_BAD" --title 'Broken row' 2>&1)"; bad_dry_code=$?
assert_eq "1" "$bad_dry_code" "Malformed index: the dry run refuses too, not only --apply"

# The ordering AC-19 actually states, on the only path that writes to a provider.
# The local fixture above cannot catch this: it refuses via `_published_ref`,
# which the external path skips.
F_BADGH="$(new_fixture)"
install_gh_mock "$F_BADGH"; write_github_config "$F_BADGH"; git_init_github_remote "$F_BADGH"
printf '# Plan\n\n- [ ] Broken row <!-- task-id: dup.target\n' > "$F_BADGH/tasks/todo.md"
bad_gh="$(cd "$F_BADGH" && PATH="$F_BADGH/bin:$PATH" GH_MOCK_DIR="$F_BADGH/ghdata" \
  GH_MOCK_LOG="$F_BADGH/gh-bad.log" \
  run upsert brand.new --repo "$F_BADGH" --title 'Brand new' --apply --approve 2>&1)"; bad_gh_code=$?
assert_eq "1" "$bad_gh_code" "Malformed index: upsert refuses on the GitHub path too"
assert_eq "" "$(cat "$F_BADGH/gh-bad.log" 2>/dev/null)" \
  "Malformed index: no provider call is made at all before the refusal (AC-19 ordering)"

# `offline_reads = fail` is the other half of the same policy: degrade is the
# default, but a project that would rather have no answer than a partial one says
# so, and then an unreachable provider is a failure -- non-zero exit, a
# `failures:` section, and the reason named. Nothing pinned Report.exit_code or
# the failures render once `publish`'s failure path went with the sync engine.
F_FAIL="$(new_fixture)"
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
  run show fail.local --repo "$F_FAIL" 2>&1)"; fail_show_code=$?
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
  run show ops.verify-deploy --repo "$F_GH" 2>&1)"
# Scope the needle to the section header, not the word: the limitation's own text
# is "reads degraded to local-only", so a bare "degraded" matches even when the
# section is never rendered.
degraded_block="$(printf '%s\n' "$gh_degraded" | sed -n '/^  degraded:$/,/^  [a-z]*:$/p')"
assert_contains "$degraded_block" "reads degraded to local-only" \
  "Show: an answer assembled without the provider says so rather than reading as complete"

finish
