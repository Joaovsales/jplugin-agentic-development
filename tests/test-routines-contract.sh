#!/bin/bash
# tests/test-routines-contract.sh — the routine contract document (AC8).
#
# specs/category-routines.md replaces a 923-LOC policy lattice with a convention.
# A convention that ships no artifact is not a convention, so this test pins the
# artifact: the four routines, their kind selectors, the precedence chain, the
# branch convention, and — the part the lattice's replacement actually depends on
# — each active routine's mandatory step list with its non-skippable gates.
#
# That last item is the gate ledger. Pipeline #93 shipped green with /quality-gate
# and the pre-push reviewers never having run, "not by decision — by omission",
# and human PR review does not catch an ABSENT gate because an absent gate leaves
# no trace in the diff. The mechanism that fixed it was a materialized row on
# disk. This test is what keeps that row named somewhere a routine can read it.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CANON=".agents/skills/wrap-up-session/references/routines.md"
COPY=".claude/skills/wrap-up-session/references/routines.md"

assert_eq "present" "$([ -f "$CANON" ] && echo present || echo missing)" \
  "Contract: $CANON exists"
assert_files_identical "$CANON" "$COPY" \
  "Contract: ships byte-identically to the .claude parity copy"

# --- the four routines, three active and one deferred ------------------------
for routine in plan fix improve build; do
  assert_file_matches "$CANON" "^\| \`$routine\`" \
    "Contract: routine \`$routine\` has a row in the routine table"
done

# `build` must be unmistakably unavailable. A reader who mistakes it for shipped
# writes a `routine/build/...` branch that no scheduler will ever fire.
assert_file_matches "$CANON" '\| `build` \|.*deferred' \
  "Contract: build's routine-table row is marked deferred"
assert_file_contains "$CANON" "#97" \
  "Contract: build's deferral names #97 (the blockedBy provider capability)"
assert_file_contains "$CANON" "#98" \
  "Contract: build's deferral names #98 (the routine itself)"

# --- kind selectors ----------------------------------------------------------
# Every label in the precedence chain is claimed by exactly one routine, so the
# chain's domain and the selector union are the same set.
assert_prose_contains "$CANON" "design-decision" "Contract: plan selects design-decision"
assert_prose_contains "$CANON" "tech-debt" "Contract: fix selects tech-debt"
assert_prose_contains "$CANON" "documentation" "Contract: improve selects documentation"

# --- precedence chain, verbatim and ordered ----------------------------------
assert_prose_contains "$CANON" \
  "bug > design-decision > tech-debt > enhancement > documentation" \
  "Contract: the kind precedence chain is stated in order"

# The chain orders PROVIDER LABEL NAMES, not canonical kinds. `tech-debt` and
# `documentation` are both absent from KINDS and both normalize to `task`, so a
# chain over canonical kinds could not tell them apart and could not rank them.
assert_prose_contains "$CANON" "label" \
  "Contract: the chain is described as ordering label names"

# --- priority is not a selector ----------------------------------------------
# 9 of 28 open issues in the pipeline repo carry both a priority and a kind
# label, so a design selecting on both axes had two routines claiming one issue
# in a third of all cases.
assert_prose_contains "$CANON" "never select a routine" \
  "Contract: now/next order candidates within a pool and never select a routine"

# --- an unclassified issue is selected by nobody -----------------------------
assert_prose_contains "$CANON" "not selected by any routine" \
  "Contract: an issue with no kind label is never selected"

# --- branch convention -------------------------------------------------------
assert_file_contains "$CANON" "routine/<name>/<issue-number>-<slug>" \
  "Contract: the branch convention is stated"
assert_file_contains "$CANON" "routine_branch.py" \
  "Contract: the contract names the parser/formatter that implements it"

# --- terminal artifact and issue linkage -------------------------------------
assert_prose_contains "$CANON" "Refs #N" \
  "Contract: plan's PR body carries Refs #N"
assert_prose_contains "$CANON" "Closes #N" \
  "Contract: fix/improve PR bodies carry Closes #N"
assert_prose_contains "$CANON" "draft" \
  "Contract: plan's terminal artifact is a draft PR"

# --- step lists: one shared spine, per-routine differences only --------------
# The substance of AC8. Each active routine names an ordered, mandatory step list
# with its gates marked non-skippable -- but the rows every routine shares are
# stated ONCE. Writing them per routine is how a gate gets added to two tables
# out of three, which is the omission-not-decision failure (#93) this ledger
# exists to prevent, reproduced in the document that prevents it.
assert_file_matches "$CANON" '^### The shared spine' \
  "Contract: the steps every routine shares are stated once, in a spine section"

spine="$(awk '/^### The shared spine/{f=1;next} f&&/^### /{exit} f' "$CANON")"
assert_contains "$spine" "task-registry select --routine" \
  "Contract: step 1 names a command that exists, not a capability"
assert_contains "$spine" "claim label" "Contract: step 2 writes the claim"
assert_contains "$spine" "routine_branch.py format" \
  "Contract: step 3 creates the branch through the shared formatter"
assert_contains "$spine" "/wrap-up-session" "Contract: the spine reaches /wrap-up-session"
assert_contains "$spine" "non-skippable" "Contract: the spine marks its non-skippable gates"

# ANTI-DUPLICATION GUARD. /wrap-up-session belongs to the spine; a routine
# section restating it is the drift this restructure removed.
wrapup_rows="$(grep -cE '^\| [0-9a-c]+ \| .?/wrap-up-session' "$CANON" || true)"
assert_eq "1" "$wrapup_rows" \
  "Contract: /wrap-up-session appears as exactly one step row, in the spine"

for routine in plan fix improve; do
  assert_file_matches "$CANON" "^### .$routine. — steps" \
    "Contract: $routine has a step section of its own"
done

# The routines that produce code reach /build and /quality-gate; both are gates.
for routine in fix improve; do
  section="$(awk -v r="$routine" 'index($0, "### `" r "` — steps") == 1 {found=1; next} found && /^### / {exit} found {print}' "$CANON")"
  assert_contains "$section" "/build" "Contract: $routine step 4 reaches /build"
  assert_contains "$section" "/quality-gate" "Contract: $routine step 4 reaches /quality-gate"
  assert_contains "$section" "non-skippable" \
    "Contract: $routine marks its build and quality gates non-skippable"
done

# `plan` produces a spec and no implementation. Requiring /quality-gate there
# would write a `skip:` row on every run, and a ledger that always reads `skip:`
# teaches nobody anything -- so its absence is stated, not silent.
plan_section="$(awk 'index($0, "### `plan` — steps") == 1 {found=1; next} found && /^### / {exit} found {print}' "$CANON")"
assert_contains "$plan_section" "/plan" "Contract: plan's step 4 is /plan"
assert_contains "$plan_section" "deliberately absent" \
  "Contract: plan states WHY it carries no build or quality gate"

# --- the ledger rule itself --------------------------------------------------
assert_prose_contains "$CANON" "skip: <reason>" \
  "Contract: a step that could not run is retained with skip: <reason>"
assert_prose_contains "$CANON" "tasks/todo.md" \
  "Contract: the executed step list is written to tasks/todo.md"

# --- concurrency claim -------------------------------------------------------
assert_prose_contains "$CANON" "in-progress" \
  "Contract: the default claim label is named"
assert_prose_contains "$CANON" "/task-registry" \
  "Contract: the claim is written through the registry, like every tracker write"

# --- the contract must not reintroduce provider coupling ---------------------
# Closure happens on merge via `Closes #N`, so no routine needs `gh issue close`.
# That is what keeps tests/test-doc-conventions.sh's coupling guard intact and
# keeps Jira working.
assert_file_not_matches "$CANON" "gh issue" \
  "Contract: no routine calls gh issue directly"

# --- AC13: the two learning documents cite what exists ------------------------
# The AC1 sweep exempts tasks/solutions/, so nothing else would catch a document
# still pointing at a deleted script. These two named it directly.
for doc in \
  tasks/solutions/architecture/hard-gate-on-tasks-todo-md.md \
  tasks/solutions/patterns/consume-structured-records-before-rendering-human-summaries.md; do
  # Built at runtime, not written literally -- see the note in
  # test-auto-improve-rewire.sh and the pattern document it cites.
  assert_file_not_matches "$doc" "skills/rou""te/|rou""te_issue" \
    "AC13: $doc cites no deleted path"
done
assert_file_contains \
  "tasks/solutions/architecture/hard-gate-on-tasks-todo-md.md" \
  "references/routines.md" \
  "AC13: the gate-ledger learning cites the routine contract"
assert_file_contains \
  "tasks/solutions/patterns/consume-structured-records-before-rendering-human-summaries.md" \
  "registry/routines.py" \
  "AC13: the structured-records learning cites a live consumer of the seam"

finish
