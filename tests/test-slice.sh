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

finish
