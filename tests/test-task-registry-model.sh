#!/bin/bash
# tests/test-task-registry-model.sh — contract tests for the provider-agnostic task registry:
# the domain model and the local index.
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
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-model.sh runs only the cases whose name matches.
. "$(dirname "$0")/lib.sh"

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

# --- shared fixture content --------------------------------------------------
# The seed lives under tests/fixtures/task-registry/; these helpers only place it.

write_index() {
  fixture_copy task-registry/todo.md "$1/tasks/todo.md"
}

# =============================================================================
# 1. Domain model — canonical vocabulary, validation, identity
# =============================================================================
if begin_case "1. Domain model"; then
model_out="$("$PY" - <<'EOF'
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
fi
end_case

# =============================================================================
# 2. Local index — compact rows, legacy rows, malformed rows, byte preservation
# =============================================================================
if begin_case "2. Local index"; then
F_INDEX="$(registry_project)"
write_index "$F_INDEX"
cat >> "$F_INDEX/tasks/todo.md" <<'EOF'
- [ ]
- [?] unknown box character
EOF
cp "$F_INDEX/tasks/todo.md" "$F_INDEX/todo.before"

index_out="$(cd "$F_INDEX" && "$PY" - <<'EOF'
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

closing_out="$("$PY" - <<'EOF'
from registry.providers import keyword_reference
print("github-url=" + str(keyword_reference("https://github.com/o/r/issues/42", "github")))
print("github-bare=" + str(keyword_reference("42", "github")))
print("github-qualified=" + str(keyword_reference("o/r#7")))
print("local-path=" + str(keyword_reference("tasks/local-1.md", "local")))
print("unknown=" + str(keyword_reference("PROJ-7")))
EOF
)"
assert_contains "$closing_out" "github-url=o/r#42" "Closing reference: a GitHub issue URL reads owner/repo#N"
assert_contains "$closing_out" "github-bare=#42" "Closing reference: a bare number reads #N"
assert_contains "$closing_out" "github-qualified=o/r#7" "Closing reference: an unnamed provider is found by grammar"
assert_contains "$closing_out" "local-path=None" "Closing reference: a local task has none"
assert_contains "$closing_out" "unknown=None" "Closing reference: text no tracker reads has none"

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
fi
end_case

finish
