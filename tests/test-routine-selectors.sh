#!/bin/bash
# tests/test-routine-selectors.sh — routine selection reads the PROJECT's vocabulary.
#
# specs/category-routines.md AC12 plus its Concurrency section. Hardcoding six
# English label names in a skill would reproduce, at six times the surface, the
# halt that opened the spec: a scheduled run found zero eligible issues because
# `auto-mode-allowed` had never been created, and it exited 0 while doing it.
#
# So three things are pinned here:
#   1. the selector map, precedence chain and claim label come from configuration
#   2. the SHIPPED DEFAULT covers every label in the precedence chain — otherwise
#      `tech-debt` and `documentation` resolve to nothing out of the box and
#      `fix`/`improve` under-select silently, which is the same halt arriving as
#      a quiet miss instead of a loud one
#   3. a configured label absent upstream exits NON-ZERO NAMING IT. "Nothing
#      matched" and "the vocabulary is wrong" must not share an exit code.
#
# The check covers the three ACTIVE routines. `build` is deferred behind #97/#98
# and must not be able to fail this gate for a capability nobody ships yet.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SCRIPTS="$REPO/.agents/skills/task-registry/scripts"
CLI="$SCRIPTS/task-registry.py"
FIXTURES="$REPO/tests/fixtures/task-registry"
PY=python3

TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

new_fixture() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/routine-selectors.XXXXXX")"
  TMP_DIRS+=("$d")
  mkdir -p "$d/tasks" "$d/docs" "$d/bin" "$d/ghdata"
  printf '[ ] placeholder\n' > "$d/tasks/todo.md"
  cp "$FIXTURES/gh" "$d/bin/gh"
  chmod +x "$d/bin/gh"
  printf '[]\n' > "$d/ghdata/issues.json"
  printf '100\n' > "$d/ghdata/next-number"
  printf '%s' "$d"
}

# Labels the fixture repository actually has upstream.
write_labels() {
  local d="$1"; shift
  local first=1
  { printf '['
    local name
    for name in "$@"; do
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{"name":"%s"}' "$name"
    done
    printf ']\n'
  } > "$d/ghdata/labels.json"
}

write_config() {
  { printf '# Task tracking\n\n```ini\n[tracker]\nprovider = github\n'
    printf 'repository = fixture-owner/fixture-repo\nrequire_write_approval = false\n'
    cat
    printf '```\n'
  } > "$1/docs/task-tracking.md"
}

run_selectors() {
  local d="$1"; shift
  ( cd "$d" && PATH="$d/bin:$PATH" GH_MOCK_DIR="$d/ghdata" GH_MOCK_LOG="$d/gh.log" \
      "$PY" "$CLI" selectors --repo "$d" "$@" 2>&1 )
}

pyreg() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" -; }

# ============================================================================
# 1. The shipped default covers the whole precedence chain
# ============================================================================
defaults="$(pyreg <<'PY'
from registry.config import (
    Config,
    DEFAULT_KIND_LABELS,
    DEFAULT_KIND_PRECEDENCE,
    DEFAULT_SELECTORS,
)

config = Config(root=".")
selected = sorted({label for labels in DEFAULT_SELECTORS.values() for label in labels})
print("chain:", ",".join(DEFAULT_KIND_PRECEDENCE))
print("selector-union:", ",".join(selected))
print("domains-equal:", sorted(DEFAULT_KIND_PRECEDENCE) == selected)
print("routines:", ",".join(sorted(DEFAULT_SELECTORS)))
print("claim:", config.claim_label)
print("kinds-mapping-to-task:", ",".join(sorted(
    label for label, kind in DEFAULT_KIND_LABELS.items() if kind == "task")) or "none")
PY
)"

# AC12's substance: every label the chain ranks is one some routine selects. The
# ROUTINE vocabulary is what must cover the chain -- selection reads
# DEFAULT_SELECTORS and kind_precedence and never touches [labels.kind].
assert_contains "$defaults" "domains-equal: True" \
  "AC12: the chain's domain and the selector union are the same set"
assert_contains "$defaults" "chain: bug,design-decision,tech-debt,enhancement,documentation" \
  "AC12: the shipped precedence order is the one the contract states"
assert_contains "$defaults" "selector-union: bug,design-decision,documentation,enhancement,tech-debt" \
  "AC12: the shipped default selectors cover every label in the precedence chain"
assert_contains "$defaults" "routines: fix,improve,plan" \
  "AC12: only the three ACTIVE routines ship a selector -- build is deferred"
assert_not_contains "$defaults" "routines: build" \
  "AC12: build ships no selector, so it cannot fail this gate"
assert_contains "$defaults" "claim: in-progress" \
  "Concurrency: the claim label defaults to in-progress"

# REGRESSION GUARD. [labels.kind] is bidirectional: the GitHub provider reverse-
# looks-up kind -> first matching label to decide what to stamp on a published
# issue. `task` is upsert's DEFAULT kind, so any default label mapping to `task`
# is stamped on every ordinary published task. Adding `tech-debt: task` here to
# make the chain "resolve" therefore labelled every task with the `fix` routine's
# own selector -- the registry feeding issues to a routine by writing them.
assert_contains "$defaults" "kinds-mapping-to-task: none" \
  "AC12: no default kind label maps to task, so publishing stamps no routine selector"

# ============================================================================
# 2. select_routine — precedence, claim skip, unclassified
# ============================================================================
picks="$(pyreg <<'PY'
from registry.config import Config
from registry.routines import select_routine

config = Config(root=".")
cases = {
    "bug-only": ("bug",),
    "two-kinds": ("documentation", "tech-debt"),
    "bug-beats-decision": ("design-decision", "bug"),
    "debt-beats-enhancement": ("enhancement", "tech-debt"),
    "documentation": ("documentation",),
    "priority-only": ("now", "next"),
    "no-kind": ("area/render",),
    "claimed": ("bug", "in-progress"),
    "empty": (),
}
for name, labels in cases.items():
    print(f"{name}={select_routine(labels, config)}")
PY
)"

assert_contains "$picks" "bug-only=fix" "Selector: bug -> fix"
assert_contains "$picks" "documentation=improve" "Selector: documentation -> improve"
assert_contains "$picks" "two-kinds=fix" \
  "Precedence: tech-debt outranks documentation on a two-kind issue"
assert_contains "$picks" "bug-beats-decision=fix" \
  "Precedence: bug outranks design-decision"
assert_contains "$picks" "debt-beats-enhancement=fix" \
  "AC12: tech-debt selects and outranks enhancement -- with no [labels.kind] entry"
assert_contains "$picks" "priority-only=None" \
  "Priority axis never selects a routine — now/next alone yield nothing"
assert_contains "$picks" "no-kind=None" \
  "An unclassified issue is not selected by any routine"
assert_contains "$picks" "empty=None" "An unlabelled issue is not selected"
assert_contains "$picks" "claimed=None" \
  "Concurrency: an issue already carrying the claim label is skipped as in-flight"

# ============================================================================
# 3. Configuration overrides the shipped vocabulary
# ============================================================================
custom="$(pyreg <<'PY'
import os, pathlib, tempfile
from registry.config import load_config
from registry.routines import select_routine

root = tempfile.mkdtemp()
pathlib.Path(root, "docs").mkdir()
pathlib.Path(root, "docs/task-tracking.md").write_text(
    "# T\n\n```ini\n"
    "[tracker]\nprovider = github\n"
    "[labels.kind]\ndefeito = bug\nmelhoria = feature\n"
    "[routines]\nclaim_label = em-curso\nkind_precedence = defeito, melhoria\n"
    "[routines.selectors]\nfix = defeito\nimprove = melhoria\n"
    "```\n",
    encoding="utf-8",
)
config = load_config(root)
print("claim:", config.claim_label)
print("chain:", ",".join(config.kind_precedence))
print("pick:", select_routine(("melhoria", "defeito"), config))
print("claimed:", select_routine(("defeito", "em-curso"), config))
print("stale-default:", select_routine(("bug",), config))
PY
)"

assert_contains "$custom" "claim: em-curso" "AC12: the claim label is configurable"
assert_contains "$custom" "chain: defeito,melhoria" "AC12: the precedence order is configurable"
assert_contains "$custom" "pick: fix" "AC12: a configured vocabulary selects routines"
assert_contains "$custom" "claimed: None" "AC12: the configured claim label is honoured"
assert_contains "$custom" "stale-default: None" \
  "AC12: a project's chain replaces the shipped one rather than layering under it"

# ============================================================================
# 4. A configured selector label absent upstream fails LOUDLY
# ============================================================================
F_OK="$(new_fixture)"
write_config "$F_OK" <<'EOF'
EOF
write_labels "$F_OK" bug enhancement design-decision tech-debt documentation now next in-progress
ok_out="$(run_selectors "$F_OK")"; ok_code=$?
assert_eq "0" "$ok_code" "AC12: a repository carrying every routine label exits 0"
assert_contains "$ok_out" "design-decision" "AC12: the report names plan's selector"
assert_contains "$ok_out" "in-progress" "AC12: the report names the claim label"

F_MISSING="$(new_fixture)"
write_config "$F_MISSING" <<'EOF'
EOF
write_labels "$F_MISSING" bug enhancement design-decision now next
miss_out="$(run_selectors "$F_MISSING")"; miss_code=$?
assert_eq "1" "$miss_code" \
  "AC12: a selector label absent upstream exits NON-ZERO (not a silent under-select)"
miss_verdict="$(printf '%s\n' "$miss_out" | grep '^upstream check: FAILED')"
assert_contains "$miss_verdict" "tech-debt" "AC12: the failure names the missing label tech-debt"
assert_contains "$miss_verdict" "documentation" "AC12: the failure names the missing label documentation"
assert_contains "$miss_verdict" "in-progress" \
  "AC12: the failure names the missing CLAIM label -- the same-routine overlap guard"
assert_not_contains "$miss_verdict" "design-decision" \
  "AC12: the verdict names only the absent labels, not every configured one"

# The claim label alone, with every selector present. It is the only guard against
# two runs of one routine picking the same issue, and `select_routine` excludes on
# its PRESENCE -- so a claim label the tracker never created is written, silently
# dropped, and read back as a clean backlog.
F_NOCLAIM="$(new_fixture)"
write_config "$F_NOCLAIM" <<'EOF'
EOF
write_labels "$F_NOCLAIM" bug enhancement design-decision tech-debt documentation now next
noclaim_out="$(run_selectors "$F_NOCLAIM")"; noclaim_code=$?
assert_eq "1" "$noclaim_code" \
  "AC12: a claim label absent upstream exits NON-ZERO even when every selector exists"
assert_contains "$noclaim_out" "in-progress" "AC12: the refusal names the absent claim label"

# A project that configures a label its tracker has never had gets the same loud
# failure — this is the exact halt in the spec's problem table.
F_TYPO="$(new_fixture)"
write_config "$F_TYPO" <<'EOF'
[labels.kind]
techdebt = task
[routines]
kind_precedence = bug, techdebt
[routines.selectors]
fix = bug, techdebt
EOF
write_labels "$F_TYPO" bug tech-debt
typo_out="$(run_selectors "$F_TYPO")"; typo_code=$?
assert_eq "1" "$typo_code" "AC12: a mistyped configured label exits non-zero"
assert_contains "$typo_out" "techdebt" "AC12: the failure names the mistyped label"

# ============================================================================
# 5. Configuration that cannot describe a total selection is refused
# ============================================================================
F_SPLIT="$(new_fixture)"
write_config "$F_SPLIT" <<'EOF'
[routines]
kind_precedence = bug, enhancement
[routines.selectors]
fix = bug
improve = enhancement, documentation
EOF
write_labels "$F_SPLIT" bug enhancement documentation
split_out="$(run_selectors "$F_SPLIT")"; split_code=$?
assert_eq "1" "$split_code" \
  "AC12: a chain whose domain differs from the selector union is refused"
assert_contains "$split_out" "documentation" \
  "AC12: the refusal names the label that no precedence rank can order"

# Two routines claiming one label makes selection non-deterministic.
F_DUP="$(new_fixture)"
write_config "$F_DUP" <<'EOF'
[routines]
kind_precedence = bug
[routines.selectors]
fix = bug
improve = bug
EOF
write_labels "$F_DUP" bug
dup_out="$(run_selectors "$F_DUP")"; dup_code=$?
assert_eq "1" "$dup_code" "AC12: two routines claiming one label is refused"
assert_contains "$dup_out" "bug" "AC12: the refusal names the contested label"

# ============================================================================
# 6. `select` — the seam the contract's step 1 actually names
# ============================================================================
# Without this, select_routine has no caller outside its own tests: the contract
# tells every routine to "read the issue through /task-registry", and the rule
# would be re-implemented per host, in whatever language, drifting from the
# in-tree copy with no failing test anywhere to notice.

F_SEL="$(new_fixture)"
write_config "$F_SEL" <<'EOF'
EOF
write_labels "$F_SEL" bug enhancement design-decision tech-debt documentation now next in-progress
cat > "$F_SEL/ghdata/issues.json" <<'EOF'
[
 {"number":10,"title":"Crash on load","state":"OPEN","url":"https://github.com/o/r/issues/10",
  "labels":[{"name":"bug"},{"name":"next"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]},
 {"number":11,"title":"Urgent crash","state":"OPEN","url":"https://github.com/o/r/issues/11",
  "labels":[{"name":"bug"},{"name":"now"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]},
 {"number":12,"title":"Already claimed","state":"OPEN","url":"https://github.com/o/r/issues/12",
  "labels":[{"name":"bug"},{"name":"now"},{"name":"in-progress"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]},
 {"number":13,"title":"Has an open routine PR","state":"OPEN","url":"https://github.com/o/r/issues/13",
  "labels":[{"name":"bug"},{"name":"now"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[{"state":"OPEN"}]},
 {"number":14,"title":"Decide the thing","state":"OPEN","url":"https://github.com/o/r/issues/14",
  "labels":[{"name":"design-decision"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]},
 {"number":15,"title":"Untriaged","state":"OPEN","url":"https://github.com/o/r/issues/15",
  "labels":[{"name":"area/render"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]}
]
EOF

run_select() {
  local d="$1"; shift
  ( cd "$d" && PATH="$d/bin:$PATH" GH_MOCK_DIR="$d/ghdata" GH_MOCK_LOG="$d/gh.log" \
      "$PY" "$CLI" select --repo "$d" "$@" 2>&1 )
}

fix_out="$(run_select "$F_SEL" --routine fix)"; fix_code=$?
assert_eq "0" "$fix_code" "select: a routine with a candidate exits 0"
assert_contains "$fix_out" "11" \
  "select: priority orders WITHIN the pool — now (#11) beats next (#10)"
assert_not_contains "$fix_out" "Already claimed" \
  "select: an issue carrying the claim label is skipped as in-flight"
assert_not_contains "$fix_out" "Has an open routine PR" \
  "select: an issue with an open linked routine PR is skipped"
assert_contains "$fix_out" "remaining:     1 other candidate(s)" \
  "select: the pool size pins BOTH exclusions -- 4 fix issues in, 2 candidates out"
assert_contains "$fix_out" "bug" "select: the matched label is reported"

plan_out="$(run_select "$F_SEL" --routine plan)"
assert_contains "$plan_out" "14" "select: plan selects the design-decision issue"

# An unclassified issue belongs to nobody, and the gap must stay visible.
assert_contains "$fix_out" "unclassified" \
  "select: the count of issues with no kind label is reported"

# Nothing to do is a success, and it is silent.
F_EMPTY="$(new_fixture)"
write_config "$F_EMPTY" <<'EOF'
EOF
write_labels "$F_EMPTY" bug enhancement design-decision tech-debt documentation in-progress
printf '[]\n' > "$F_EMPTY/ghdata/issues.json"
empty_out="$(run_select "$F_EMPTY" --routine fix)"; empty_code=$?
assert_eq "0" "$empty_code" \
  "select: no candidate exits 0 — a routine with nothing to do is not a failure"
assert_contains "$empty_out" "none — fix has nothing to claim" \
  "select: an empty pool says so in words rather than printing nothing"

# A routine nobody can branch for is a configuration error. `format_routine_branch`
# refuses it at spine step 3 -- after the claim label is written -- so the refusal
# has to happen at load time instead.
F_UNKNOWN="$(new_fixture)"
write_config "$F_UNKNOWN" <<'EOF'
[routines]
kind_precedence = bug, perf
[routines.selectors]
fix = bug
refactor = perf
EOF
write_labels "$F_UNKNOWN" bug perf in-progress
unknown_out="$(run_selectors "$F_UNKNOWN")"; unknown_code=$?
assert_eq "1" "$unknown_code" "AC12: a routine outside the contract is refused at load"
assert_contains "$unknown_out" "refactor" "AC12: the refusal names the invented routine"

# The contract document is the single source. Two mirrors guard it: routine_branch's
# CONTRACT_ROUTINES (pinned in test-routine-branch.sh) and config's copy, here.
contract_doc="$REPO/.agents/skills/wrap-up-session/references/routines.md"
for routine in plan fix improve build; do
  assert_file_contains "$contract_doc" "$routine" \
    "AC8: the contract document defines the '$routine' routine"
  assert_file_contains "$REPO/.agents/skills/task-registry/scripts/registry/config.py" \
    "\"$routine\"" "AC12: config's CONTRACT_ROUTINES carries '$routine'"
done

# ============================================================================
# 5b. The three-state seams, and the diagnostic that must survive a broken config
# ============================================================================

# A provider that cannot enumerate its vocabulary is "not checked", never "nothing
# missing" -- and NOT RUN is the branch every local/Jira project takes.
F_LOCAL="$(new_fixture)"
{ printf '# Task tracking\n\n```ini\n[tracker]\nprovider = local\n```\n'; } \
  > "$F_LOCAL/docs/task-tracking.md"
local_out="$(run_selectors "$F_LOCAL")"; local_code=$?
assert_eq "0" "$local_code" \
  "AC12: a provider that cannot enumerate labels does not fail the check"
assert_contains "$local_out" "NOT RUN" \
  "AC12: an unenumerable vocabulary reports NOT RUN — it never reports a pass"

# `doctor` is the command you run BECAUSE configuration is broken. Hoisting
# validate_selectors into load_config must not make the diagnostic unreachable.
F_BROKEN="$(new_fixture)"
{ printf '# Task tracking\n\n```ini\n[routines]\nkind_precedence = bug, tech-debt\n```\n'; } \
  > "$F_BROKEN/docs/task-tracking.md"
broken_doctor="$( cd "$F_BROKEN" && "$PY" "$CLI" doctor --repo "$F_BROKEN" 2>&1 )"
broken_code=$?
assert_eq "1" "$broken_code" "doctor: a misconfigured [routines] block is reported, loudly"
assert_contains "$broken_doctor" "MISCONFIGURED" "doctor: the fault is named, not swallowed"
assert_contains "$broken_doctor" "provider:" \
  "doctor: the rest of the diagnosis still renders — it is reachable when it matters"
broken_frontier="$( cd "$F_BROKEN" && "$PY" "$CLI" frontier --repo "$F_BROKEN" >/dev/null 2>&1 )"
assert_eq "1" "$?" "doctor is the ONLY exemption — every other command still refuses"

# `" "` is truthy, so a claim label stripped after an `or` fallback yields "" --
# and an empty claim label silently disables the same-routine overlap guard.
claim_blank="$("$PY" - "$SCRIPTS" <<'PY'
import pathlib, sys, tempfile
sys.path.insert(0, sys.argv[1])
from registry.config import load_config
for raw in ('', '   '):
    root = tempfile.mkdtemp()
    pathlib.Path(root, "docs").mkdir()
    pathlib.Path(root, "docs/task-tracking.md").write_text(
        "# T\n\n```ini\n[tracker]\nprovider = local\n"
        "[routines]\nclaim_label =" + raw + "\n```\n", encoding="utf-8")
    print(repr(load_config(root).claim_label))
PY
)"
assert_contains "$claim_blank" "'in-progress'" \
  "AC12: an empty or whitespace claim label falls back — it never resolves to ''"
assert_not_contains "$claim_blank" "''" \
  "AC12: no blank claim label survives, which would disable the overlap guard"

# ============================================================================
# 6. `claim` — the spine's step 2, and the contract's only write
# ============================================================================
run_claim() {
  local d="$1" ref="$2"; shift 2
  # The issue reference is positional and must follow the command directly.
  ( cd "$d" && PATH="$d/bin:$PATH" GH_MOCK_DIR="$d/ghdata" GH_MOCK_LOG="$d/gh.log" \
      "$PY" "$CLI" claim "$ref" --repo "$d" "$@" 2>&1 )
}

F_CLAIM="$(new_fixture)"
write_config "$F_CLAIM" <<'EOF'
EOF
write_labels "$F_CLAIM" bug enhancement design-decision tech-debt documentation now next in-progress
cat > "$F_CLAIM/ghdata/issues.json" <<'EOF'
[
 {"number":42,"title":"Crash","state":"OPEN","url":"https://github.com/o/r/issues/42",
  "labels":[{"name":"bug"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]}
]
EOF
printf '{"number":42,"title":"Crash","body":"","labels":[{"name":"bug"}]}\n' \
  > "$F_CLAIM/ghdata/issue-42.json"

# Dry-run is the default for every write in this CLI, and claim is a write.
claim_dry="$(run_claim "$F_CLAIM" 42 --routine fix)"; claim_dry_code=$?
assert_eq "1" "$claim_dry_code" "claim: dry-run is the default — a write needs --apply"
assert_not_contains "$claim_dry" "wrote in-progress" "claim: a dry run writes nothing"

# Claiming across routines is how two routines land on one issue.
claim_wrong="$(run_claim "$F_CLAIM" 42 --routine plan --apply --approve)"; claim_wrong_code=$?
assert_eq "1" "$claim_wrong_code" "claim: REFUSES an issue that belongs to another routine"
assert_contains "$claim_wrong" "belongs to fix" "claim: the refusal names the owning routine"

claim_out="$(run_claim "$F_CLAIM" 42 --routine fix --apply --approve)"; claim_code=$?
assert_eq "0" "$claim_code" "claim: writes the claim label for the owning routine"
assert_contains "$claim_out" "wrote in-progress to 42" "claim: the write is reported"
assert_file_contains "$F_CLAIM/gh.log" "--add-label in-progress" \
  "claim: the label reaches the tracker — the read half is not the whole guard"

# A retried routine must not need to know whether its first attempt got through.
# The label is set directly here because the gh mock does not persist `issue edit`
# back into its issue list -- the property under test is how claim reads an issue
# that ALREADY carries the label, not whether the mock round-trips a write.
cat > "$F_CLAIM/ghdata/issues.json" <<'EOF'
[
 {"number":42,"title":"Crash","state":"OPEN","url":"https://github.com/o/r/issues/42",
  "labels":[{"name":"bug"},{"name":"in-progress"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":"",
  "closedByPullRequestsReferences":[]}
]
EOF
claim_again="$(run_claim "$F_CLAIM" 42 --routine fix --apply --approve)"; again_code=$?
assert_eq "0" "$again_code" "claim: re-claiming an already-claimed issue is not an error"
assert_contains "$claim_again" "already carries" "claim: idempotent, and says so"

claim_missing="$(run_claim "$F_CLAIM" 999 --routine fix --apply --approve)"; missing_code=$?
assert_eq "1" "$missing_code" "claim: an unknown issue exits non-zero"

# `select` IS routine start. A vocabulary gap must halt it, not quietly under-select:
# the missing label makes the pool empty, and an empty pool is a normal day.
F_SEL_GAP="$(new_fixture)"
write_config "$F_SEL_GAP" <<'EOF'
EOF
write_labels "$F_SEL_GAP" bug enhancement design-decision now next in-progress
printf '[]\n' > "$F_SEL_GAP/ghdata/issues.json"
gap_out="$(run_select "$F_SEL_GAP" --routine fix)"; gap_code=$?
assert_eq "1" "$gap_code" \
  "AC12: select REFUSES when a configured selector label is absent upstream"
assert_contains "$gap_out" "tech-debt" "AC12: select's refusal names the missing label"
assert_not_contains "$gap_out" "nothing to claim" \
  "AC12: a vocabulary gap never masquerades as an empty backlog"

# A `gh` too old for closedByPullRequestsReferences cannot answer the in-flight
# exclusion. Proceeding would re-pick every issue already under review.
F_OLDGH="$(new_fixture)"
write_config "$F_OLDGH" <<'EOF'
EOF
write_labels "$F_OLDGH" bug enhancement design-decision tech-debt documentation now next in-progress
cat > "$F_OLDGH/ghdata/issues.json" <<'EOF'
[
 {"number":21,"title":"Crash","state":"OPEN","url":"https://github.com/o/r/issues/21",
  "labels":[{"name":"bug"},{"name":"now"}],"assignees":[],
  "createdAt":"2026-08-01T00:00:00Z","updatedAt":"2026-08-01T00:00:00Z","body":""}
]
EOF
printf 'closedByPullRequestsReferences\n' > "$F_OLDGH/ghdata/unknown-fields"
old_out="$(run_select "$F_OLDGH" --routine fix)"; old_code=$?
assert_eq "1" "$old_code" \
  "select: REFUSES when gh cannot report linked pull request state"
assert_contains "$old_out" "closedByPullRequestsReferences" \
  "select: the refusal names the field it could not read"

# An unknown routine name is a configuration error, not an empty result.
bad_out="$(run_select "$F_SEL" --routine nonesuch)"; bad_code=$?
assert_eq "2" "$bad_code" "select: an unknown routine name exits non-zero"
assert_contains "$bad_out" "nonesuch" "select: the refusal names the unknown routine"

# ============================================================================
# 7. The template documents what it ships
# ============================================================================
for tree in .agents .claude; do
  tmpl="$tree/skills/task-registry/templates/task-tracking.md"
  assert_file_contains "$tmpl" "[routines]" \
    "AC12: $tree template documents the [routines] section"
  assert_file_contains "$tmpl" "[routines.selectors]" \
    "AC12: $tree template documents the [routines.selectors] section"
  assert_file_contains "$tmpl" "claim_label" \
    "AC12: $tree template documents the claim label"
  assert_file_contains "$tmpl" "kind_precedence" \
    "AC12: $tree template documents the precedence order"
  # The chain's labels must appear under [routines.selectors] -- and must NOT
  # appear as `= task` under [labels.kind], which is the publish-path trap.
  selectors_block="$(awk '/^\[routines.selectors\]/{f=1;next} f&&/^\[/{exit} f' "$tmpl")"
  assert_contains "$selectors_block" "tech-debt" \
    "AC12: $tree template ships tech-debt as a routine selector"
  assert_contains "$selectors_block" "documentation" \
    "AC12: $tree template ships documentation as a routine selector"
  # Directives only -- the section's own warning comment quotes `tech-debt = task`
  # as the thing not to do, and a raw grep cannot tell advice from configuration.
  kind_block="$(awk '/^\[labels.kind\]/{f=1;next} f&&/^\[/{exit} f' "$tmpl" \
    | grep -v '^;' | grep -v '^$')"
  assert_not_contains "$kind_block" "= task" \
    "AC12: $tree template maps no label to \`task\` — that stamps every published task"
done

finish
