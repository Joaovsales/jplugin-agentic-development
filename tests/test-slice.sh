#!/bin/bash
# tests/test-slice.sh — `/slice`'s script half: validate, ready, check, and the
# shared glob matcher it imports from `registry/globs.py`.
#
# `/slice` writes a spec's § Build Order and a `## Plan:` block that a human
# never re-derives by hand — so the three questions this script answers
# (does the plan even parse? which slices can go now? did a closed slice stay
# inside its declared surface?) are pinned here against small fixtures rather
# than against the real, 7-slice `specs/plan-slices-and-handover.md`, whose
# Build Order this suite models its fixtures on.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

PY="$TEST_PYTHON"   # resolved once in tests/lib.sh
SLICE="$REPO/.agents/skills/slice/scripts/slice.py"
GLOBS_ROOT="$REPO/.agents/skills/task-registry/scripts"
# Relative to $REPO (the cwd below): `ready`'s plan-block match compares the
# `--spec` argument against the fixture's own `> Spec:` line, which is written
# relative -- exactly as a real `## Plan:` block always is.
FIXTURES="tests/fixtures/slice"

TMP_DIRS=()
cleanup() { for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

printf '\n--- validate: a clean Build Order passes all three checks ---\n'

OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-clean/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "validate: clean fixture exits 0"
assert_eq "" "$OUT" "validate: clean fixture prints nothing"

printf '\n--- validate: a fenced example above the real Build Order is skipped ---\n'

# The real spec shows the § Build Order grammar inside a ```markdown fence
# before the section itself. Reading the first heading found parses the decoy
# table and refuses a clean plan (found on the first live run).
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-fenced/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "validate: a fenced decoy Build Order is not the section"
assert_eq "" "$OUT" "validate: the fenced decoy's outside path is never reported"

printf '\n--- validate: an intersecting pair with no blocker ---\n'

OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-intersect/spec.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "validate: intersecting pair with no blocker exits 1"
assert_contains "$OUT" "intersecting surfaces" "validate: names the intersection, not just a generic failure"
assert_contains "$OUT" "1 and 2" "validate: names both slices of the intersecting pair"

printf '\n--- validate: a cycle in Blocked by ---\n'

OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-cycle/spec.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "validate: a cycle exits 1"
assert_contains "$OUT" "cycle:" "validate: names the cycle, not just a generic failure"
assert_contains "$OUT" "2 -> 3 -> 2" "validate: the cycle path names both slices in the loop"

printf '\n--- validate: a Blocked by number that names no slice ---\n'

# Refused once, at parse time, so a typo (`9` for `1`) is an error the author
# sees -- not a slice that validates clean and is never ready.
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-unknown-blocker/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "validate: an unknown Blocked by number is a malformed table, exit 2"
assert_contains "$OUT" "slice 2 (two) is blocked by 9, which names no slice" "validate: names the slice and the unknown number"

printf '\n--- validate: a surface with an unsupported glob token ---\n'

# Surfaces go through the same validator as implementation_paths; without it
# `[ab]` reaches `check` as a literal that matches nothing and `ready` as a
# pattern that intersects nothing.
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-bad-surface-glob/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "validate: an unsupported glob token in a surface is refused, exit 2"
assert_contains "$OUT" "unsupported glob syntax" "validate: the surface refusal names the unsupported syntax"

printf '\n--- validate: a Build Order row with fewer cells than the header ---\n'

OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-ragged-row/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "validate: a ragged row is a malformed table, exit 2 -- not a traceback"
assert_contains "$OUT" "Build Order row has 2 cells, header has 8" "validate: the refusal counts the cells"

printf '\n--- validate: a spec with no Build Order section ---\n'

OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-no-build-order/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "validate: a missing Build Order is unreadable input, exit 2"
assert_contains "$OUT" "no '## Build Order' section found" "validate: names the missing section"

printf '\n--- validate: a surface outside implementation_paths ---\n'

OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/validate-outside-paths/spec.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "validate: a surface outside implementation_paths exits 1"
assert_contains "$OUT" "src/other/thing.py" "validate: names the offending path"
assert_contains "$OUT" "outside implementation_paths" "validate: says why the path was refused"

printf '\n--- validate and ready: a TDD row whose test file is outside its slice surface ---\n'

# Found live on specs/design-stack-hyperframes.md: slice 4's row targeted
# tests/test-design-stack-video.sh while its Surface named only skill text, so
# the build noticed only when slice 4 became ready and widened the surface by
# hand. Only an open row whose token before ` § ` is a `tests/...` path is
# checked: slice 2's open row matches its surface, its `t3 -> impl3` row
# carries no path, its `[x]` row's test is already written, and the session
# summary after the last heading is not slice 2's span (the live todo.md
# attributed every later `## Fix:` row to the last slice before the `##` stop).
TDD_FIX="$FIXTURES/validate-tdd-outside-surface"
OUT="$("$PY" "$SLICE" validate --spec "$TDD_FIX/spec.md" --index "$TDD_FIX/todo.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "validate: a TDD row naming a test file outside its slice's surface exits 1"
assert_contains "$OUT" "slice 1 (one): TDD row names tests/test-one.sh, which no surface pattern matches" "validate: names the slice and the test path"
assert_not_contains "$OUT" "slice 2" "validate: a matched tests/ path and a row with no tests/ path both pass"
assert_not_contains "$OUT" "tests/test-done.sh" "validate: a done [x] row outside the surface is history, not a refusal"
assert_not_contains "$OUT" "tests/test-later.sh" "validate: a row after the next ## heading is not the last slice's"

OUT="$("$PY" "$SLICE" validate --spec "$TDD_FIX/spec.md" --index "$TDD_FIX/no-such-todo.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "validate: with no plan block written yet (Propose step 1) the TDD check is skipped"
assert_eq "" "$OUT" "validate: a missing index is not reported"

OUT="$("$PY" "$SLICE" ready --index "$TDD_FIX/todo.md" --spec "$TDD_FIX/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "ready: the same plan block is refused before any slice is named ready, exit 2"
assert_contains "$OUT" "slice 1 (one): TDD row names tests/test-one.sh, which no surface pattern matches" "ready: names the slice and the test path"
assert_not_contains "$OUT" "ready: 1 one" "ready: no ready set is printed on the refusal"

printf '\n--- ready: a three-slice index, 2 blocked by 1 ---\n'

OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-open.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "ready: parses and exits 0"
assert_contains "$OUT" "ready: 1 one" "ready: slice 1 (no blockers) is ready"
assert_contains "$OUT" "ready: 3 three" "ready: slice 3 (no blockers) is ready"
assert_not_contains "$OUT" "ready: 2 two" "ready: slice 2 is absent while its blocker (1) is open"
assert_contains "$OUT" "surface: src/one/**" "ready: prints slice 1's surface"
assert_contains "$OUT" "surface: src/one/sub/**" "ready: prints slice 3's surface"
assert_contains "$OUT" "intersects: 1 ↔ 3 (no blocker; serialize in table order)" "ready: reports the intersecting ready pair with the exact separator"

printf '\n--- ready: after slice 1 closes, 2 joins the ready set ---\n'

OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-slice1-done.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "ready: still exits 0 once slice 1 is [x]"
assert_contains "$OUT" "ready: 2 two" "ready: slice 2 is ready once its blocker (1) is done"
assert_contains "$OUT" "ready: 3 three" "ready: slice 3 stays ready"
assert_not_contains "$OUT" "ready: 1 one" "ready: a done slice is absent from the ready set"

printf '\n--- ready: a fenced example row above the real header row ---\n'

# `registry/index.py` parses every `[ ]` line, fenced or not; `ready` must
# attribute only prose rows to a heading, or a pasted example marks a finished
# slice as ready again.
OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-fenced-decoy.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "ready: a fenced decoy row still exits 0"
assert_not_contains "$OUT" "ready: 1 one" "ready: the fenced decoy row is not slice 1's header; the real [x] row is"
assert_contains "$OUT" "ready: 2 two" "ready: slice 2 is ready because the real slice 1 row is [x]"

printf '\n--- ready: a flat legacy plan with no ### Slice headings ---\n'

OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready-implicit/todo-open.md" --spec "$FIXTURES/ready-implicit/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "ready: an implicit slice still exits 0"
assert_contains "$OUT" "ready: 1 legacy-feature" "ready: the implicit slice takes the plan's name"
assert_contains "$OUT" "surface: src/legacy/**, tests/test-legacy.sh" "ready: the implicit slice's surface is the spec's whole implementation_paths"

printf '\n--- ready: a plan block that drifted from the Build Order ---\n'

# Slice 2 has a table row and no heading: without the refusal it is never
# ready and never named, and slice 3 would look ready on its own.
OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-missing-heading.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "ready: a Build Order row with no heading is drift, exit 2"
assert_contains "$OUT" "slices [2] have no \`### Slice\` heading" "ready: names the slice the plan block lost"

printf '\n--- ready: a missing index file ---\n'

OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/no-such-todo.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "ready: a missing index exits 2"
assert_contains "$OUT" "no such index file" "ready: names the missing index"

printf '\n--- ready: a malformed index fails at load ---\n'

DM="$(mktemp -d)"
TMP_DIRS+=("$DM")
{ cat "$FIXTURES/ready/todo-header-open.md"; printf '\n- [ ] broken row <!-- never closed\n'; } > "$DM/todo.md"
OUT="$("$PY" "$SLICE" ready --index "$DM/todo.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "ready: a malformed index exits 2"
assert_contains "$OUT" "slice: refusing to act on a malformed index" "ready: a malformed index is a slice: refusal"
assert_not_contains "$OUT" "Traceback" "ready: a malformed index is not a traceback"

printf '\n--- header-plan: bare slice headers under one feature row ---\n'

# specs/aposd-first-build.md AC1/AC2: a block `/slice` writes carries no task id,
# no `(blocked-by:)` and no `TDD:` child on a slice row; `ready` reads it through
# the same index path as a legacy block.
OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-header-open.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "header-plan: a block of bare slice headers exits 0"
assert_contains "$OUT" "ready: 1 one" "header-plan: slice 1 (no blockers) is ready"
assert_not_contains "$OUT" "ready: 2 two" "header-plan: slice 2 waits on slice 1, whose blocker lives only in the Build Order"
OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-header-slice1-done.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
assert_contains "$OUT" "ready: 2 two" "header-plan: slice 2 is ready once its header is [x]"
assert_not_contains "$OUT" "ready: 1 one" "header-plan: a done header is absent from the ready set"

TWO="$FIXTURES/validate-two-links"
for ok in todo-one-row todo-one-issue; do
  OUT="$("$PY" "$SLICE" validate --spec "$TWO/spec.md" --index "$TWO/$ok.md" 2>&1)"
  CODE=$?
  assert_eq "0" "$CODE" "header-plan: $ok holds one feature link and validates"
  assert_eq "" "$OUT" "header-plan: $ok prints nothing"
done
for bad in todo-both todo-two-issues todo-two-rows; do
  OUT="$("$PY" "$SLICE" validate --spec "$TWO/spec.md" --index "$TWO/$bad.md" 2>&1)"
  CODE=$?
  assert_eq "1" "$CODE" "header-plan: $bad holds two feature links, exit 1"
  assert_contains "$OUT" "$TWO/$bad.md:6: " "header-plan: $bad names <path>:<line> of the second link"
  assert_contains "$OUT" "two feature links" "header-plan: $bad says why"
done

printf '\n--- legacy-plan: task-id blocks still validate and ready unchanged ---\n'

OUT="$("$PY" "$SLICE" ready --index "$FIXTURES/ready/todo-slice1-done.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
assert_contains "$OUT" "ready: 2 two" "legacy-plan: a task-id block still readies slice 2 after slice 1 is [x]"
OUT="$("$PY" "$SLICE" validate --spec "$TWO/spec.md" --index "$TWO/todo-legacy.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "legacy-plan: a task-id block with TDD rows and no feature link still validates"
assert_eq "" "$OUT" "legacy-plan: a legacy block prints nothing"
OUT="$("$PY" "$SLICE" ready --index "$TWO/todo-legacy.md" --spec "$TWO/spec.md" 2>&1)"
assert_contains "$OUT" "ready: 1 one" "legacy-plan: a legacy block's open slice 1 is ready"

printf '\n--- interfaces: ready names no mode; validate no longer requires a Path (AC3 withdrawn) ---\n'

MODE="$FIXTURES/mode"
OUT="$("$PY" "$SLICE" ready --index "$MODE/todo-new.md" --spec "$MODE/spec.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "interfaces: a new block exits 0"
assert_contains "$OUT" "ready: 1 one" "interfaces: a slice whose Surface matches an Interfaces Path is ready"
assert_contains "$OUT" "ready: 2 two" "interfaces: a slice matching no Interfaces Path is ready"
assert_not_contains "$OUT" "mode=" "interfaces: ready prints no mode"
assert_not_contains "$OUT" "loop:" "interfaces: ready prints no loop line"
OUT="$("$PY" "$SLICE" validate --spec "$MODE/spec.md" --index "$MODE/todo-new.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "interfaces: validate passes when every Interfaces entry has a Path"
OUT="$("$PY" "$SLICE" validate --spec "$MODE/spec-no-path.md" --index "$MODE/todo-new.md" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "interfaces: validate accepts an Interfaces entry with no Path, exit 0"

printf '\n--- link: one classification of how a plan block links its feature ---\n'

LINKF="$FIXTURES/link"
link_case() {  # <label> <index> <spec> <expected link> <expected done>
  OUT="$("$PY" "$SLICE" link --index "$2" --spec "$3" 2>&1)"
  CODE=$?
  OUT="${OUT//$'\r'/}"
  assert_eq "0" "$CODE" "link: $1 exits 0"
  assert_eq "link: $4
done: $5" "$OUT" "link: $1 prints link and done"
}
link_case "a task-id on a slice header" "$TWO/todo-legacy.md" "$TWO/spec.md" "legacy" "no"
link_case "a > Issue: line" "$TWO/todo-one-issue.md" "$TWO/spec.md" "issue o/r#7" "no"
link_case "a feature row with no provider link" "$TWO/todo-one-row.md" "$TWO/spec.md" "unlinked plan.two-links" "no"
link_case "a feature row with a provider link" "$LINKF/todo-linked.md" "$FIXTURES/ready/spec.md" "linked plan.ready-fixture o/r#42" "no"
link_case "no feature link" "$LINKF/todo-none.md" "$FIXTURES/ready/spec.md" "none" "no"
link_case "a flat block" "$FIXTURES/ready-implicit/todo-open.md" "$FIXTURES/ready-implicit/spec.md" "none" "no"
link_case "every header [x]" "$LINKF/todo-done.md" "$FIXTURES/ready/spec.md" "issue o/r#42" "yes"
link_case "an Issue ref already #N" "$LINKF/todo-issue-ref.md" "$FIXTURES/ready/spec.md" "issue #9" "no"
link_case "a bare-number Issue ref closes as #N" "$LINKF/todo-issue-bare.md" "$FIXTURES/ready/spec.md" "issue #9" "no"
link_case "an Issue URL in another repo keeps its repo" "$LINKF/todo-issue-cross-repo.md" "$FIXTURES/ready/spec.md" "issue other/repo#213" "no"
link_case "one header [x] of three" "$FIXTURES/ready/todo-header-slice1-done.md" "$FIXTURES/ready/spec.md" "unlinked plan.ready-fixture" "no"
OUT="$("$PY" "$SLICE" link --index "$LINKF/no-such-todo.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "link: a missing index exits 2"
assert_contains "$OUT" "slice: " "link: a missing index is a slice: refusal"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-none.md" --spec "$LINKF/other-spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "link: a spec the index has no block for exits 2"
assert_contains "$OUT" "has no \`## Plan:\` block naming" "link: a spec the index has no block for says why"
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/ready/spec.md" --index "$LINKF/todo-feature-no-id.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "link: a feature row with no task-id fails validate"
assert_contains "$OUT" "todo-feature-no-id.md:5: " "link: the no-id feature row is named by <path>:<line>"
assert_contains "$OUT" "no task-id" "link: the no-id feature row refusal says why"
for verb in link ready; do
  OUT="$("$PY" "$SLICE" "$verb" --index "$LINKF/todo-feature-no-id.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
  CODE=$?
  assert_eq "2" "$CODE" "link: $verb refuses a feature row with no task-id, exit 2"
  assert_contains "$OUT" "todo-feature-no-id.md:5: " "link: $verb names the no-id feature row by <path>:<line>"
  assert_contains "$OUT" "no task-id" "link: $verb says why"
done
for bad in todo-both todo-two-issues todo-two-rows; do
  for verb in link ready; do
    OUT="$("$PY" "$SLICE" "$verb" --index "$TWO/$bad.md" --spec "$TWO/spec.md" 2>&1)"
    CODE=$?
    assert_eq "2" "$CODE" "link: $verb on $bad holds two feature links, exit 2"
    assert_contains "$OUT" "two feature links" "link: $verb on $bad says why"
  done
done
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-multi.md" 2>&1)"
CODE=$?
OUT="${OUT//$'\r'/}"
assert_eq "0" "$CODE" "link: without --spec exits 0"
assert_eq "tests/fixtures/slice/ready/spec.md link: issue o/r#42 done: yes
tests/fixtures/slice/link/other-spec.md link: linked plan.second-fixture o/r#43 done: no" "$OUT" "link: without --spec prints one line per block that names a spec"
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/ready/spec.md" --index "$LINKF/todo-issue-odd.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "link: an Issue ref no provider can close fails validate"
assert_contains "$OUT" "todo-issue-odd.md:5: " "link: the unclosable Issue line is named by <path>:<line>"
assert_contains "$OUT" "closing reference" "link: the unclosable Issue refusal says why"
for verb in link ready; do
  OUT="$("$PY" "$SLICE" "$verb" --index "$LINKF/todo-issue-odd.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
  CODE=$?
  assert_eq "2" "$CODE" "link: $verb refuses an Issue ref no provider can close, exit 2"
  assert_contains "$OUT" "closing reference" "link: $verb says why"
done
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/ready/spec.md" --index "$LINKF/todo-same-spec.md" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "link: two blocks naming one spec fail validate"
assert_contains "$OUT" "more than one plan block" "link: the duplicate-spec refusal says why"
for verb in link ready; do
  OUT="$("$PY" "$SLICE" "$verb" --index "$LINKF/todo-same-spec.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
  CODE=$?
  assert_eq "2" "$CODE" "link: $verb --spec refuses a spec two blocks name, exit 2"
  assert_contains "$OUT" "more than one plan block" "link: $verb --spec says why"
done
OUT="$("$PY" "$SLICE" validate --spec "$FIXTURES/ready/spec.md" --index "$LINKF/todo-two-done.md" 2>&1)"
CODE=$?
assert_not_contains "$OUT" "more than one plan block" "link: two finished blocks for one spec are history, validate says nothing of it"
for mode in "--spec $FIXTURES/ready/spec.md" ""; do
  OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-two-done.md" $mode 2>&1)"
  CODE=$?
  assert_eq "0" "$CODE" "link: two finished blocks for one spec exit 0 (${mode:-no --spec})"
done
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-same-spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "link: without --spec two blocks naming one spec exit 2"
assert_contains "$OUT" "more than one plan block" "link: without --spec the duplicate-spec refusal says why"
OUT="$("$PY" "$SLICE" link --index "$LINKF/no-such-todo.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "link: without --spec a missing index exits 2"
link_case "a feature row whose external is a local task has no closing reference" "$LINKF/todo-local-ref.md" "$FIXTURES/ready/spec.md" "unlinked plan.ready-fixture" "no"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-open-then-malformed.md" 2>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "link: without --spec an open block then a malformed one exits 2"
assert_eq "" "$OUT" "link: without --spec a malformed block mid-file leaves stdout empty"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-open-then-malformed.md" 2>&1 >/dev/null)"
assert_contains "$OUT" "no task-id" "link: without --spec the refusal goes to stderr"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-two-refusals.md" 2>/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "link: without --spec two refusing blocks exit 2"
assert_eq "" "$OUT" "link: without --spec two refusing blocks leave stdout empty"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-two-refusals.md" 2>&1 >/dev/null)"
assert_contains "$OUT" "closing reference" "link: without --spec the first refusing block is named on stderr"
assert_contains "$OUT" "no task-id" "link: without --spec the second refusing block is named on stderr too"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-bad-row-in-x.md" --spec "$LINKF/other-spec.md" 2>&1)"
CODE=$?
OUT="${OUT//$'\r'/}"
assert_eq "0" "$CODE" "link: a malformed row in another plan block does not refuse this spec"
assert_eq "link: linked plan.second-fixture o/r#43
done: no" "$OUT" "link: this spec's block links as usual past another block's malformed row"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-bad-row-in-x.md" --spec "$FIXTURES/ready/spec.md" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "link: a malformed row inside the targeted block exits 2"
assert_contains "$OUT" "slice: refusing to act on a malformed index" "link: the targeted block's malformed row is a slice: refusal"
assert_contains "$OUT" "todo-bad-row-in-x.md:9" "link: the refusal names the malformed row's line"
OUT="$("$PY" "$SLICE" link --index "$LINKF/todo-bad-row-in-x.md" 2>&1 >/dev/null)"
CODE=$?
assert_eq "2" "$CODE" "link: without --spec a malformed row in any block exits 2"

printf '\n--- plan-block.md: the grammar a fresh block follows ---\n'

PLAN_REF="$REPO/.agents/skills/slice/references/plan-block.md"
PLAN_FENCE="$(awk '/^```markdown$/{c=1;next} c&&/^```$/{exit} c' "$PLAN_REF" | tr -d '\r')"
assert_contains "$PLAN_FENCE" "### Slice 1/<N>" "plan-block.md: the example holds slice headings"
assert_not_contains "$PLAN_FENCE" "blocked-by" "plan-block.md: no slice row carries a blocker marker"
assert_not_contains "$PLAN_FENCE" "TDD:" "plan-block.md: the example holds no TDD row"
assert_eq "1" "$(printf '%s\n' "$PLAN_FENCE" | grep -c 'task-id')" "plan-block.md: the one task id is the feature row's"

printf '\n--- check: a clean diff exits 0 and prints nothing ---\n'

D1="$(mktemp -d)"
TMP_DIRS+=("$D1")
git -C "$D1" init -q -b main
git -C "$D1" config user.email t@example.com
git -C "$D1" config user.name Test
mkdir -p "$D1/src/feature" "$D1/tests"
printf 'one\n' > "$D1/src/feature/a.py"
printf 'test\n' > "$D1/tests/test-feature.sh"
git -C "$D1" add -A >/dev/null
git -C "$D1" commit -qm base
BASE1="$(git -C "$D1" rev-parse HEAD)"
printf 'two\n' >> "$D1/src/feature/a.py"
printf 'test2\n' >> "$D1/tests/test-feature.sh"
git -C "$D1" add -A >/dev/null
git -C "$D1" commit -qm work

OUT="$("$PY" "$SLICE" check --spec "$FIXTURES/check/spec.md" --slice 1 --base "$BASE1" --repo "$D1" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "check: a diff matching the declared surface exits 0"
assert_eq "" "$OUT" "check: a clean diff prints nothing"

printf '\n--- check: a legacy spec with no Build Order is one implicit slice ---\n'

# The implicit slice is defined once (`resolve_slices`) and read by `ready`
# and `check` alike, so a plan written before § Build Order still checks.
OUT="$("$PY" "$SLICE" check --spec "$FIXTURES/check-implicit/spec.md" --slice 1 --base "$BASE1" --repo "$D1" 2>&1)"
CODE=$?
assert_eq "0" "$CODE" "check: the implicit slice's surface is the spec's implementation_paths"
assert_eq "" "$OUT" "check: a legacy spec's clean diff prints nothing"

printf '\n--- check: an undeclared path and an untouched pattern ---\n'

D2="$(mktemp -d)"
TMP_DIRS+=("$D2")
git -C "$D2" init -q -b main
git -C "$D2" config user.email t@example.com
git -C "$D2" config user.name Test
mkdir -p "$D2/src/feature" "$D2/tests"
printf 'one\n' > "$D2/src/feature/a.py"
printf 'test\n' > "$D2/tests/test-feature.sh"
git -C "$D2" add -A >/dev/null
git -C "$D2" commit -qm base
BASE2="$(git -C "$D2" rev-parse HEAD)"
printf 'two\n' >> "$D2/src/feature/a.py"
printf 'stray\n' > "$D2/src/other.py"
git -C "$D2" add -A >/dev/null
git -C "$D2" commit -qm work

OUT="$("$PY" "$SLICE" check --spec "$FIXTURES/check/spec.md" --slice 1 --base "$BASE2" --repo "$D2" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "check: an undeclared path or untouched pattern exits 1"
assert_contains "$OUT" "undeclared: src/other.py" "check: names the changed path no surface pattern declared"
assert_contains "$OUT" "untouched: tests/test-feature.sh" "check: names the declared pattern nothing in the diff touched"

printf '\n--- check: an untouched pattern alone still exits 1 ---\n'

# The two conditions are pinned apart: a diff inside the surface that leaves
# one declared pattern untouched must fail on `untouched:` alone.
BASE3="$(git -C "$D1" rev-parse HEAD)"
printf 'three\n' >> "$D1/src/feature/a.py"
git -C "$D1" add -A >/dev/null
git -C "$D1" commit -qm more

OUT="$("$PY" "$SLICE" check --spec "$FIXTURES/check/spec.md" --slice 1 --base "$BASE3" --repo "$D1" 2>&1)"
CODE=$?
assert_eq "1" "$CODE" "check: an untouched pattern with nothing undeclared exits 1"
assert_contains "$OUT" "untouched: tests/test-feature.sh" "check: names the untouched pattern"
assert_not_contains "$OUT" "undeclared:" "check: prints no undeclared line when every changed path is declared"

OUT="$("$PY" "$SLICE" check --spec "$FIXTURES/check/spec.md" --slice 9 --base "$BASE3" --repo "$D1" 2>&1)"
CODE=$?
assert_eq "2" "$CODE" "check: a slice number the table lacks exits 2"
assert_contains "$OUT" "no slice 9 in" "check: names the missing slice number"

printf '\n--- globs: registry/globs.py rejects what spec-reconcile.py used to reject ---\n'

GLOBS_JSON="$("$PY" - "$GLOBS_ROOT" <<'PYEOF'
import sys, json
sys.path.insert(0, sys.argv[1])
from registry.globs import validate_pattern, SpecPathError

cases = {
    "absolute": "/etc/passwd",
    "traversal": "../secret",
    "backslash": "src\\thing.py",
    "unsupported": "src/[ab]/**",
}
results = {}
for name, value in cases.items():
    try:
        validate_pattern(value, "specs/x.md")
        results[name] = None
    except SpecPathError as exc:
        results[name] = str(exc)
print(json.dumps(results))
PYEOF
)"

assert_contains "$GLOBS_JSON" '"absolute": "specs/x.md: absolute path not allowed' \
  "globs: an absolute path is rejected, naming the spec and the value"
assert_contains "$GLOBS_JSON" "specs/x.md: \`..\` traversal not allowed" \
  "globs: a \`..\` traversal is rejected, naming the spec and the value"
assert_contains "$GLOBS_JSON" "specs/x.md: use POSIX separators, not backslashes" \
  "globs: a backslash is rejected, naming the spec and the value"
assert_contains "$GLOBS_JSON" "specs/x.md: unsupported glob syntax" \
  "globs: an unsupported glob character is rejected, naming the spec and the value"

printf '\n--- globs: patterns_intersect is decided per segment, not by literalizing one side ---\n'

INTERSECT_JSON="$("$PY" - "$GLOBS_ROOT" <<'PYEOF'
import sys, json
sys.path.insert(0, sys.argv[1])
from registry.globs import patterns_intersect, match_path

cases = {
    "star-vs-literal-segment": patterns_intersect("src/*/x.py", "src/one/**"),
    "disjoint-siblings": patterns_intersect("src/one/**", "src/two/**"),
    "nested-under-doublestar": patterns_intersect("src/one/**", "src/one/sub/**"),
    "depth-mismatch": patterns_intersect("a/*.py", "a/b/c.py"),
    "question-vs-literal": patterns_intersect("src/?.py", "src/a.py"),
    "different-extensions": patterns_intersect("src/*.py", "src/*.sh"),
    "match-star-stays-in-segment": match_path("src/*.py", "src/a/b.py"),
}
print(json.dumps(cases))
PYEOF
)"
assert_contains "$INTERSECT_JSON" '"star-vs-literal-segment": true' \
  "globs: a * segment intersects a literal segment under **"
assert_contains "$INTERSECT_JSON" '"disjoint-siblings": false' \
  "globs: sibling directories do not intersect"
assert_contains "$INTERSECT_JSON" '"nested-under-doublestar": true' \
  "globs: a nested surface intersects its parent's **"
assert_contains "$INTERSECT_JSON" '"depth-mismatch": false' \
  "globs: * never crosses a segment boundary"
assert_contains "$INTERSECT_JSON" '"question-vs-literal": true' \
  "globs: ? intersects one literal character"
assert_contains "$INTERSECT_JSON" '"different-extensions": false' \
  "globs: two wildcards with different literal tails do not intersect"
assert_contains "$INTERSECT_JSON" '"match-star-stays-in-segment": false' \
  "globs: match_path's * stops at /"

printf '\n--- readiness: an open decision or a blocking question refuses the build prompt ---\n'
# specs/readable-visual-plans.md AC16 (D23, D26): `/slice` runs `readiness`
# before printing a build prompt. The ids it names are the ones the visual
# plan page shows as `Not ready:`, because both read the spec the same way.
READY_TMP="$(mktemp -d)"; TMP_DIRS+=("$READY_TMP")
readiness_spec() {  # <file> <D2 status> <Q1 Blocks>
  cat > "$1" <<SPEC
# Spec: Readiness fixture

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|---|---|---|---|---|---|
| D1 | Format | CSV, JSON | CSV | A consumer needs nesting | settled |
| D2 | Threshold | 50000, 100000 | 50000 | Rows grow | $2 |

## Open questions

| ID | Question | Blocks | Needed from |
|---|---|---|---|
| Q1 | Which region? | $3 | platform |
| Q2 | Add a BOM? | none | data |

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Writer | CSV | \`src/a/**\` | — | 1 | \`make\` | 1 file |
| 2 | Splitter | Parts | \`src/b/**\` | 1 | 2 | \`make\` | 1 file |
SPEC
}
readiness_spec "$READY_TMP/open.md" open 2
OUT="$("$PY" "$SLICE" readiness --spec "$READY_TMP/open.md" 2>&1)"; CODE=$?
assert_eq "1" "$CODE" "readiness: an open decision and a blocking question exit 1"
assert_eq "not ready: D2, Q1" "$OUT" "readiness: prints not ready with the decision and question ids"
readiness_spec "$READY_TMP/question.md" settled 2
OUT="$("$PY" "$SLICE" readiness --spec "$READY_TMP/question.md" 2>&1)"; CODE=$?
assert_eq "1" "$CODE" "readiness: a blocking question alone exits 1"
assert_eq "not ready: Q1" "$OUT" "readiness: names only the blocking question"
readiness_spec "$READY_TMP/ready.md" settled none
OUT="$("$PY" "$SLICE" readiness --spec "$READY_TMP/ready.md" 2>&1)"; CODE=$?
assert_eq "0" "$CODE" "readiness: settled decisions and non-blocking questions exit 0"
assert_eq "" "$OUT" "readiness: a ready spec prints nothing"
printf '# Spec: Broken\n\n## Decisions\n\n| ID | Decision | Status |\n|---|---|---|\n| D1 | Format |\n' > "$READY_TMP/broken.md"
OUT="$("$PY" "$SLICE" readiness --spec "$READY_TMP/broken.md" 2>&1)"; CODE=$?
assert_eq "2" "$CODE" "readiness: a malformed Decisions table exits 2"
assert_contains "$OUT" "broken.md:7: " "readiness: the failure names <spec>:<line>"
if find "$REPO/.agents/skills/visual-plan/scripts" -name __pycache__ | grep -q .; then
  assert_eq "no __pycache__" "__pycache__ written" "readiness: importing the renderer's parser writes no bytecode"
else
  assert_eq "no __pycache__" "no __pycache__" "readiness: importing the renderer's parser writes no bytecode"
fi
SLICE_DOC="$REPO/.agents/skills/slice/SKILL.md"
assert_file_contains "$SLICE_DOC" "slice.py readiness --spec" "readiness: /slice runs the readiness check before the build prompt"
assert_file_contains "$SLICE_DOC" "not ready: <ids>" "readiness: /slice documents the not-ready output"
assert_file_contains "$REPO/.agents/skills/slice/references/build-prompt.md" "slice.py readiness" "readiness: the build-prompt reference names the gate"
assert_file_not_matches "$SLICE_DOC" 'An `open` row is an `\[AMBIGUITY\]` line' "readiness: the retired open-row [AMBIGUITY] rule is gone (D26)"
assert_file_not_matches "$REPO/.agents/skills/slice/references/build-prompt.md" 'An `open` row is an `\[AMBIGUITY\]` line' "readiness: the retired rule is gone from the reference too"

finish
