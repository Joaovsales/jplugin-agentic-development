#!/bin/bash
# tests/test-task-registry-config.sh — contract tests for the provider-agnostic task registry:
# configuration parsing and provider selection.
#
# One of the contract files of the provider-agnostic task registry, split from the
# former tests/test-task-registry.sh at its section seams (specs/test-suite-aposd.md
# D4). Every piece declares the same artefact path, so tests/affected.sh selects all of
# them on a change under the registry. Each section is a case:
# TEST_CASE='<glob>' bash tests/test-task-registry-config.sh runs only the cases whose name matches.
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

# Run the CLI the way a skill does.
reg() { "$PY" "$CLI" "$@"; }

# --- shared fixture content --------------------------------------------------
# The seed lives under tests/fixtures/task-registry/; these helpers only place it.

write_index() {
  fixture_copy task-registry/todo.md "$1/tasks/todo.md"
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

# =============================================================================
# 3. Configuration — parsing, pointer indirection, malformed input
# =============================================================================
if begin_case "3. Configuration"; then
F_CONF="$(registry_project)"
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

conf_out="$(cd "$F_CONF" && "$PY" - <<'EOF'
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
F_NOCONF="$(registry_project)"
noconf_out="$(cd "$F_NOCONF" && "$PY" - <<'EOF'
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
F_BADCONF="$(registry_project)"
write_index "$F_BADCONF"
printf '# Tracking\n\nno fenced block here\n' > "$F_BADCONF/docs/task-tracking.md"
badconf_out="$(reg selectors --repo "$F_BADCONF" 2>&1)"
badconf_code=$?
assert_eq "1" "$badconf_code" "Config: a configuration file with no ini block exits non-zero"
assert_contains "$badconf_out" "no \`\`\`ini configuration block found" \
  "Config: the failure names what is missing"

F_UNKPROV="$(registry_project)"
write_index "$F_UNKPROV"
printf '# T\n\n```ini\n[tracker]\nprovider = trello\n```\n' > "$F_UNKPROV/docs/task-tracking.md"
unkprov_out="$(reg selectors --repo "$F_UNKPROV" 2>&1)"
unkprov_code=$?
assert_eq "1" "$unkprov_code" "Config: an unknown provider exits non-zero"
assert_contains "$unkprov_out" "unknown provider 'trello'" "Config: the failure names the bad provider"

# A retired provider is the likeliest real encounter with Cut 1: a downstream
# project whose checked-in config still says `provider = jira`. It must be
# refused by the same path as a name that never existed, and the refusal must
# enumerate what actually ships — this pins `config.PROVIDERS`, which the
# `--provider` override path does not reach.
F_RETPROV="$(registry_project)"
write_index "$F_RETPROV"
printf '# T\n\n```ini\n[tracker]\nprovider = jira\n```\n' > "$F_RETPROV/docs/task-tracking.md"
retprov_out="$(reg doctor --repo "$F_RETPROV" 2>&1)"
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
F_NOPTR="$(registry_project)"
write_index "$F_NOPTR"
noptr_out="$(reg doctor --repo "$F_NOPTR" 2>&1)"
noptr_code=$?
assert_eq "0" "$noptr_code" "Pointer states: no pointer — defaults, exit 0"
assert_contains "$noptr_out" "configuration:  none (defaults + local fallback)" \
  "Pointer states: no pointer — reported as none"
assert_not_contains "$noptr_out" "BROKEN" \
  "Pointer states: no pointer — no new noise on the common path"

F_PTROK="$(registry_project)"
write_index "$F_PTROK"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_PTROK/docs/tracking.md"
printf 'Task tracking instructions: docs/tracking.md\n' > "$F_PTROK/AGENTS.md"
ptrok_out="$(reg doctor --repo "$F_PTROK" 2>&1)"
ptrok_code=$?
assert_eq "0" "$ptrok_code" "Pointer states: pointer to an existing file — exit 0"
assert_contains "$ptrok_out" "configuration:  docs/tracking.md" \
  "Pointer states: pointer to an existing file — that file is loaded"

F_PTRMISS="$(registry_project)"
write_index "$F_PTRMISS"
printf 'Task tracking instructions: docs/tracking.md\n' > "$F_PTRMISS/AGENTS.md"
ptrmiss_doctor="$(reg doctor --repo "$F_PTRMISS" 2>&1)"
ptrmiss_code=$?
assert_eq "1" "$ptrmiss_code" "Pointer states: pointer to a missing file — doctor exits non-zero"
assert_contains "$ptrmiss_doctor" "configuration:  BROKEN" \
  "Pointer states: pointer to a missing file — doctor reports BROKEN, not none"
assert_contains "$ptrmiss_doctor" "AGENTS.md declares" \
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
assert_false "Pointer states: a broken declaration is distinguishable from no declaration" -- \
  test "$noptr_out" = "$ptrmiss_doctor"
ptrmiss_rec="$(reg selectors --repo "$F_PTRMISS" 2>&1)"
ptrmiss_rec_code=$?
assert_eq "1" "$ptrmiss_rec_code" \
  "Pointer states: every command except doctor refuses to run on a broken pointer"
assert_contains "$ptrmiss_rec" "task-registry: AGENTS.md declares" \
  "Pointer states: the refusal carries the same fault text"

# First pointer wins, broken or not: a dangling project-owned pointer is not
# rescued by a valid one further down the search order (CLAUDE.md is the
# @AGENTS.md pointer and is not searched at all, so the third line is inert). The
# most authoritative declaration is the one that is wrong, and that is what the
# user must hear.
F_PTRPREC="$(registry_project)"
write_index "$F_PTRPREC"
mkdir -p "$F_PTRPREC/.claude"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_PTRPREC/docs/tracking.md"
printf 'Task tracking instructions: docs/missing.md\n' > "$F_PTRPREC/.claude/project.md"
printf 'Task tracking instructions: docs/tracking.md\n' > "$F_PTRPREC/CLAUDE.md"
ptrprec_out="$(reg selectors --repo "$F_PTRPREC" 2>&1)"
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
F_PTRDIR="$(registry_project)"
write_index "$F_PTRDIR"
printf 'Task tracking instructions: docs\n' > "$F_PTRDIR/AGENTS.md"
ptrdir_out="$(reg doctor --repo "$F_PTRDIR" 2>&1)"
assert_contains "$ptrdir_out" "'docs' exists but is not a file" \
  "Pointer states: a pointer to a directory is not reported as missing"
assert_not_contains "$ptrdir_out" "does not exist" \
  "Pointer states: a directory target never gets the create-it advice"
F_PTRESC="$(registry_project)"
write_index "$F_PTRESC"
printf 'Task tracking instructions: \033[31mdocs/x.md\n' > "$F_PTRESC/AGENTS.md"
ptresc_out="$(reg doctor --repo "$F_PTRESC" 2>&1)"
assert_contains "$ptresc_out" "'\\x1b[31mdocs/x.md' does not exist" \
  "Pointer states: the declared path is echoed escaped, never raw"
assert_eq "0" "$(printf '%s' "$ptresc_out" | grep -c $'\033' || true)" \
  "Pointer states: no raw ESC byte reaches the output"

# A refusal is only earned by a genuine declaration. The regex admits any
# non-space run after the colon, so a prose mention that ends its sentence —
# `...: docs/tracking.md.` — must name `docs/tracking.md`, not `docs/tracking.md.`;
# otherwise a project that worked yesterday refuses today over a full stop.
F_PTRPROSE="$(registry_project)"
write_index "$F_PTRPROSE"
mkdir -p "$F_PTRPROSE/.claude"
printf '# T\n\n```ini\n[tracker]\nprovider = local\n```\n' > "$F_PTRPROSE/docs/tracking.md"
printf 'See the Task tracking instructions: docs/tracking.md. It is optional.\n' > "$F_PTRPROSE/.claude/project.md"
ptrprose_out="$(reg doctor --repo "$F_PTRPROSE" 2>&1)"
ptrprose_code=$?
assert_eq "0" "$ptrprose_code" \
  "Pointer states: sentence punctuation after the path is not part of the path"
assert_contains "$ptrprose_out" "configuration:  docs/tracking.md" \
  "Pointer states: the prose mention resolves to the file it names"
# `.claude/project.md` is where the pointer lived before the single instruction
# file. It is still read — a declined migration must not break the registry —
# but doctor says so, so the state is visible and not permanent by accident
# (specs/single-instruction-file.md, D3).
assert_contains "$ptrprose_out" "pointer found in .claude/project.md — /sync will move it to AGENTS.md" \
  "Pointer states: a pointer still in .claude/project.md is read with the one-line notice"
assert_not_contains "$ptrok_out" "pointer found in .claude/project.md" \
  "Pointer states: a pointer in AGENTS.md prints no notice"

# A run that is nothing but punctuation (`Task tracking instructions: ...`) is a
# sentence fragment, not a path — it must read as "no pointer", not as a
# pointer to a file called `...`.
F_PTRDOTS="$(registry_project)"
write_index "$F_PTRDOTS"
printf 'Task tracking instructions: ...\n' > "$F_PTRDOTS/AGENTS.md"
ptrdots_out="$(reg doctor --repo "$F_PTRDOTS" 2>&1)"
ptrdots_code=$?
assert_eq "0" "$ptrdots_code" \
  "Pointer states: a punctuation-only pointer is no pointer — exit 0"
assert_contains "$ptrdots_out" "configuration:  none (defaults + local fallback)" \
  "Pointer states: a punctuation-only pointer falls back to defaults"
fi
end_case

# =============================================================================
# 4. Provider selection precedence
# =============================================================================
if begin_case "4. Provider selection precedence"; then
F_SEL="$(registry_project)"
write_index "$F_SEL"
sel_local="$(reg doctor --repo "$F_SEL" 2>&1)"
assert_contains "$sel_local" "provider:       local" \
  "Selection: no configuration and no GitHub remote falls back to local"
assert_contains "$sel_local" "no configuration and no usable GitHub remote" \
  "Selection: the fallback states its reason"

# A retired provider is refused by name, and the refusal lists what survives.
# Silently falling back would route a project that asked for a tracker we no
# longer ship into the local store without saying so.
sel_retired="$(reg doctor --repo "$F_SEL" --provider jira 2>&1)"
sel_retired_code=$?
assert_eq "2" "$sel_retired_code" \
  "Selection: an override naming a retired provider exits 2 (misconfiguration)"
assert_contains "$sel_retired" "unknown provider" \
  "Selection: the refusal says the provider is unknown"
assert_contains "$sel_retired" "github" \
  "Selection: the refusal lists the providers that do exist"
assert_not_contains "$sel_retired" "jira, local" \
  "Selection: jira is gone from the available-provider list, not just from the dict"

F_SEL_GH="$(registry_repo)"
write_index "$F_SEL_GH"
git_init_github_remote "$F_SEL_GH"
install_gh_mock "$F_SEL_GH"
sel_gh="$(
  PATH="$F_SEL_GH/bin:$PATH" GH_MOCK_DIR="$F_SEL_GH/ghdata" GH_MOCK_LOG="$F_SEL_GH/gh.log" \
    reg doctor --repo "$F_SEL_GH" 2>&1
)"
assert_contains "$sel_gh" "provider:       github" \
  "Selection: a GitHub remote plus authenticated gh selects github"
assert_contains "$sel_gh" "authenticated gh" "Selection: github selection states its reason"
# The sandbox proxy fails `gh auth status` while every REST call succeeds, so
# reachability is `gh api user` exiting 0 -- in provider selection and in the
# provider's own `discover()` alike (specs/github-rest-in-sandboxes.md, AC1).
assert_contains "$sel_gh" "reachable:      yes — gh authenticated for fixture-owner/fixture-repo" \
  "Selection (AC1): doctor reports the remote-resolved repository reachable"
assert_contains "$(cat "$F_SEL_GH/gh.log")" "api user" \
  "Selection (AC1): reachability is probed with gh api user"
assert_not_contains "$(cat "$F_SEL_GH/gh.log")" "auth status" \
  "Selection (AC1): gh auth status never runs -- it fails in the sandbox while REST works"

sel_gh_unauth="$(
  PATH="$F_SEL_GH/bin:$PATH" GH_MOCK_DIR="$F_SEL_GH/ghdata" \
    GH_MOCK_LOG="$F_SEL_GH/gh.log" GH_MOCK_UNAUTH=1 \
    reg doctor --repo "$F_SEL_GH" 2>&1
)"
assert_contains "$sel_gh_unauth" "provider:       local" \
  "Selection: a GitHub remote with unauthenticated gh falls back to local"
assert_contains "$sel_gh_unauth" "gh is unavailable or unauthenticated" \
  "Selection: the unauthenticated fallback names the cause"

# #124 — a provider selected from the remote must also READ and WRITE through
# it. `doctor` learned the repository via `gh repo view`; `select`, `claim` and
# `workflow` reached `_repo()` without that step and refused on the same
# checkout `doctor` had just called reachable.
#
# No configuration file means the DEFAULT claim and escalation labels, so the
# fixture vocabulary must carry them or the (correct) upstream label check halts
# before the repository resolution under test is ever exercised.
add_labels "$F_SEL_GH" in-progress needs-investigation
: > "$F_SEL_GH/gh.log"
sel_gh_select="$(
  PATH="$F_SEL_GH/bin:$PATH" GH_MOCK_DIR="$F_SEL_GH/ghdata" GH_MOCK_LOG="$F_SEL_GH/gh.log" \
    reg select --routine fix --repo "$F_SEL_GH" 2>&1
)"
sel_gh_select_code=$?
assert_eq "0" "$sel_gh_select_code" \
  "Selection (#124): select on a remote-resolved github provider exits 0 without a repository line"
assert_not_contains "$sel_gh_select" "no repository configured" \
  "Selection (#124): select does not refuse on the repository doctor already resolved"
# `select` prints the upstream verdict only when it fails, so a passing check is
# proved from the mock's call log: the label listing named the discovered repo.
assert_contains "$(cat "$F_SEL_GH/gh.log")" "api repos/fixture-owner/fixture-repo/labels?per_page=100&page=1" \
  "Selection (#124): the upstream label check ran against the discovered repository"
assert_contains "$sel_gh_select" "candidate:" \
  "Selection (#124): select reached the candidate pool"
sel_gh_repo_views="$(grep -c '^repo view' "$F_SEL_GH/gh.log")"
assert_eq "0" "$sel_gh_repo_views" \
  "Selection (#124, AC1): the repository is parsed from the remote -- gh repo view is GraphQL and never runs"

sel_gh_workflow="$(
  PATH="$F_SEL_GH/bin:$PATH" GH_MOCK_DIR="$F_SEL_GH/ghdata" GH_MOCK_LOG="$F_SEL_GH/gh.log" \
    reg workflow '#42' --repo "$F_SEL_GH" 2>&1
)"
sel_gh_workflow_code=$?
assert_eq "0" "$sel_gh_workflow_code" \
  "Selection (#124): workflow on a remote-resolved github provider exits 0"
assert_not_contains "$sel_gh_workflow" "no repository configured" \
  "Selection (#124): workflow does not refuse on the repository doctor already resolved"
fi
end_case

finish
