#!/bin/bash
# tests/test-task-registry-regressions-github.sh — contract tests for the provider-agnostic task registry:
# regressions of the GitHub provider, the migration and the CLI.
#
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-regressions-github.sh runs only the cases whose name matches.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO/.agents/skills/task-registry"
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

# Extend the shared label vocabulary of a fixture with more names.
add_labels() {
  local f="$1/ghdata/labels.json" name
  shift
  for name in "$@"; do sed -i "s/\]\$/,{\"name\":\"$name\"}]/" "$f"; done
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

MIGRATE="$REPO/scripts/migrate-task-registry.py"

# --- github: argv hardening, label creation, truncation ----------------------
if begin_case "12. github: argv hardening, label creation, truncation"; then
gh_reg="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-reg.log" "$PY" - <<'EOF'
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
assert_contains "$(cat "$F_GH/gh-reg.log")" "api repos/fixture-owner/fixture-repo/issues/42" \
  "GitHub: one issue is read through the REST issues route, the number in the path"
assert_contains "$(cat "$F_GH/gh-reg.log")" 'api --method POST repos/fixture-owner/fixture-repo/issues --input - {"body":' \
  "GitHub (AC3): an issue is created through POST /issues, the payload on stdin"
assert_not_contains "$(grep -- '--method POST' "$F_GH/gh-reg.log")" "brand-new-label" \
  "GitHub (AC7): an unknown label is filtered before the write reaches the API"

# Exactly LIST_LIMIT issues is indistinguishable from "there were more": the
# REST read pages 100 at a time, stops at the cap instead of paging past it,
# sets the truncation flag, and `select` refuses rather than claim from a
# partial pool (specs/github-rest-in-sandboxes.md, AC5).
F_PAGE="$(registry_project)"
write_index "$F_PAGE"
write_github_config "$F_PAGE"
install_gh_mock "$F_PAGE"
add_labels "$F_PAGE" in-progress needs-investigation
"$PY" - "$F_PAGE/ghdata/issues.json" <<'PY'
import io, json, sys
issues = [
    {"number": n, "title": f"Issue {n}", "state": "open", "body": "",
     "html_url": f"https://github.com/fixture-owner/fixture-repo/issues/{n}",
     "labels": [{"name": "bug"}, {"name": "next"}], "assignees": [],
     "created_at": "2026-08-01T00:00:00Z", "updated_at": "2026-08-01T00:00:00Z"}
    for n in range(1, 501)
]
io.open(sys.argv[1], "w", encoding="utf-8", newline="\n").write(json.dumps(issues))
PY
page_out="$(cd "$F_PAGE" && PATH="$F_PAGE/bin:$PATH" GH_MOCK_DIR="$F_PAGE/ghdata" \
  GH_MOCK_LOG="$F_PAGE/gh.log" reg select --routine fix --repo "$F_PAGE" 2>&1)"; page_code=$?
assert_eq "1" "$page_code" \
  "GitHub (AC5): a read of exactly LIST_LIMIT issues makes select refuse"
assert_contains "$page_out" "truncated read" \
  "GitHub (AC5): the refusal names the truncated read"
assert_contains "$(cat "$F_PAGE/gh.log")" "issues?state=all&per_page=100&page=1" \
  "GitHub (AC5): the issue list is paged from page 1, 100 per page"
assert_contains "$(cat "$F_PAGE/gh.log")" "per_page=100&page=5" \
  "GitHub (AC5): the read pages up to the LIST_LIMIT-th entry"
assert_not_contains "$(cat "$F_PAGE/gh.log")" "page=6" \
  "GitHub (AC5): the read stops at the cap instead of paging past it"

F_LBL="$(registry_project)"
write_index "$F_LBL"
mkdir -p "$F_LBL/bin" "$F_LBL/lbldata"
fixture_copy task-registry/gh "$F_LBL/bin/gh"
chmod +x "$F_LBL/bin/gh"
fixture_copy task-registry/issues-empty.json "$F_LBL/lbldata/issues.json"
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
  GH_MOCK_LOG="$F_LBL/gh.log" "$PY" - <<'EOF'
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
assert_contains "$(cat "$F_LBL/gh.log")" 'api --method POST repos/fixture-owner/fixture-repo/labels --input - {"name": "area/render"}' \
  "GitHub (AC3): label creation is POST /labels with the name on stdin, not a silent skip"
assert_file_contains "$F_LBL/lbldata/labels.json" "area/render" \
  "GitHub: the created label is really added to the repository vocabulary"
fi
end_case

# --- github (AC7): the mock refuses a label the repository lacks ------------
if begin_case "12. github (AC7): the mock refuses a label the repository lacks"; then
# REST `POST /issues` silently CREATES an unknown label, so the provider's
# known-label filter is the only guard; the mock fails where the API would stay
# quiet, which is what makes the filter assertions above worth anything.
slipped_out="$(cd "$F_GH" && printf '%s' '{"labels":["not-in-vocabulary"]}' \
  | PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" GH_MOCK_LOG="$F_GH/gh-slipped.log" \
    gh api --method POST repos/fixture-owner/fixture-repo/issues/42/labels --input - 2>&1)"
slipped_code=$?
assert_eq "1" "$slipped_code" \
  "GitHub (AC7): a write naming a label absent from labels.json exits 1"
assert_contains "$slipped_out" "not-in-vocabulary" \
  "GitHub (AC7): the refusal names the label"
assert_contains "$(cat "$F_GH/gh-slipped.log")" '--input - {"labels": ["not-in-vocabulary"]}' \
  "GitHub (AC7, Decision 10): the log line carries the parsed stdin body"
fi
end_case

# --- github (AC3, AC8): update is PATCH then POST labels; close and comment --
if begin_case "12. github (AC3, AC8): update is PATCH then POST labels; close and comment"; then
# REST has no single call that edits a body and adds labels, so the second write
# can fail after the first landed. GH_MOCK_FAIL_ROUTE fails only the label add.
upd_out="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-update.log" GH_MOCK_FAIL_ROUTE=issues/42/labels "$PY" - <<'EOF'
from registry.config import load_config
from registry.model import ExternalRef
from registry.providers import build_provider
from registry.providers.base import ProviderError, WriteGate

provider = build_provider("github", load_config("."), WriteGate(apply=True, require_approval=False))
current = provider.get_task(ExternalRef("github", "42", ""))
try:
    provider.update_task(current.with_(labels=current.labels + ("bug",)))
    print("update=ok")
except ProviderError as exc:
    print("update-error=" + str(exc))
EOF
)"
assert_contains "$upd_out" "update-error=github: issue #42: body written, but adding label(s) bug failed" \
  "GitHub (AC8): a label add that fails after the PATCH names the body as already written"
upd_writes="$(grep -- '--method' "$F_GH/gh-update.log")"
assert_contains "$(printf '%s\n' "$upd_writes" | sed -n '1p')" 'api --method PATCH repos/fixture-owner/fixture-repo/issues/42 --input - {"body": "' \
  "GitHub (AC8): the body goes first, through PATCH /issues/{n} with the payload on stdin"
assert_contains "$(printf '%s\n' "$upd_writes" | sed -n '2p')" 'api --method POST repos/fixture-owner/fixture-repo/issues/42/labels --input - {"labels": ["bug"]}' \
  "GitHub (AC8): the new label follows, through POST /issues/{n}/labels"
assert_eq "2" "$(printf '%s\n' "$upd_writes" | grep -c .)" \
  "GitHub (AC8): an update is exactly those two writes"

life_out="$(cd "$F_GH" && PATH="$F_GH/bin:$PATH" GH_MOCK_DIR="$F_GH/ghdata" \
  GH_MOCK_LOG="$F_GH/gh-life.log" "$PY" - <<'EOF'
from registry.config import load_config
from registry.model import ExternalRef
from registry.providers import build_provider
from registry.providers.base import WriteGate

provider = build_provider("github", load_config("."), WriteGate(apply=True, require_approval=False))
task = provider.get_task(ExternalRef("github", "42", ""))
provider.update_task(task)
provider.comment(task, "Reviewed over REST")
print("closed=" + provider.close_task(task, "cancelled").status)
EOF
)"
assert_contains "$life_out" "closed=cancelled" \
  "GitHub (AC3): close_task answers the terminal status"
assert_contains "$(cat "$F_GH/gh-life.log")" 'api --method POST repos/fixture-owner/fixture-repo/issues/42/comments --input - {"body": "Reviewed over REST"}' \
  "GitHub (AC3): a comment is POST /issues/{n}/comments, the body on stdin"
assert_contains "$(cat "$F_GH/gh-life.log")" 'api --method PATCH repos/fixture-owner/fixture-repo/issues/42 --input - {"state": "closed", "state_reason": "not_planned"}' \
  "GitHub (AC3): a cancelled close is PATCH /issues/{n} with state closed and state_reason not_planned"
assert_eq "0" "$(grep -c 'issues/42/labels' "$F_GH/gh-life.log")" \
  "GitHub (AC3): an update with nothing new to label makes no label write"
assert_eq "0" "$(cat "$F_GH"/gh-*.log | grep -cvE '^api (--method [A-Z]+ )?(user|repos/fixture-owner/fixture-repo[/?])')" \
  "GitHub (AC2): every gh call in the lifecycle logs is gh api on user or repos/<owner>/<repo>/..."
fi
end_case

# --- migrate: id collisions, block-bounded specs, dependency rewrites --------
if begin_case "12. migrate: id collisions, block-bounded specs, dependency rewrites"; then
F_MIG2="$(registry_project)"
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
mig2_after="$("$PY" - <<PYEOF
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

F_MARK="$(registry_project)"
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
F_NOMARK="$(registry_project)"
printf '# Task Plan\n\n## Plan: Ongoing\n\n- [ ] Still open\n' > "$F_NOMARK/tasks/todo.md"
nomark_out="$("$PY" "$MIGRATE" --repo "$F_NOMARK" 2>&1)"
assert_contains "$nomark_out" "no 'Session Summary' heading found" \
  "Migrate: an index with no closed-plan marker says so instead of guessing"
fi
end_case

# --- CLI: unexpected failures are redacted, exit codes are honest ------------
if begin_case "12. CLI: unexpected failures are redacted, exit codes are honest"; then
F_CRASH="$(registry_project)"
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
  GH_MOCK_LOG="$F_GH/gh-links.log" "$PY" - <<'EOF'
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
fi
end_case

finish
