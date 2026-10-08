#!/usr/bin/env bash
# Tests for the visual plan renderer (.agents/skills/visual-plan/scripts/plan_render.py):
# a stdlib-only spec markdown -> self-contained HTML renderer with typed
# sections, loud parse failures and old-spec compatibility
# (specs/readable-visual-plans.md).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$REPO_ROOT/.agents/skills/visual-plan/scripts/plan_render.py"
FIX="$REPO_ROOT/tests/fixtures/plan-render"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# render <fixture-name> — renders tests/fixtures/plan-render/<name>.md into
# $TMP/<name>.html and leaves OUT (stdout+stderr) and CODE behind.
render() {
  OUT="$(cd "$FIX" && "$TEST_PYTHON" "$RENDER" "$1.md" -o "$TMP/$1.html" 2>&1)"
  CODE=$?
}

printf '\n--- failures: a malformed known section exits 1 with <spec>:<line>: <reason> ---\n'
assert_failure() {  # <fixture> <line> <reason-needle>
  render "$1"
  assert_eq "1" "$CODE" "failures: $1 exits 1"
  assert_contains "$OUT" "$1.md:$2: " "failures: $1 names <spec>:<line>"
  assert_contains "$OUT" "$3" "failures: $1 names the reason"
  if [ -e "$TMP/$1.html" ]; then
    assert_eq "absent" "present" "failures: $1 writes no file"
  else
    assert_eq "absent" "absent" "failures: $1 writes no file"
  fi
}
assert_failure fail-decision-cell 8 "Decisions"
assert_failure fail-risk-value 8 "H/M/L"
assert_failure fail-duplicate-id 8 "duplicate ID D3"
assert_failure fail-flow-line 7 "unsupported flow line"
assert_failure fail-sequence-end 8 "end without alt"
assert_failure fail-question-blocks 7 "slice 9"
assert_failure fail-build-cycle 7 "cycle"
assert_failure fail-ac-duplicate 6 "duplicate ID AC1"

render legacy
assert_eq "0" "$CODE" "render: legacy exits 0"
assert_contains "$OUT" "✓ Visual written: " "render: prints the written path"
PAGE="$(cat "$TMP/legacy.html" 2>/dev/null)"

printf '\n--- tables: markdown tables are semantic and scroll in their own container ---\n'
assert_contains "$PAGE" '<div class="table-scroll" tabindex="0" role="region"' "tables: a table sits in a focusable scroll container"
assert_contains "$PAGE" '<th scope="col">Review cadence</th>' "tables: header cells are <th scope=col>"
assert_contains "$PAGE" '<td>split beyond the maximum</td>' "tables: body cells are <td>"
assert_contains "$PAGE" 'overflow-x: auto' "tables: the scroll container scrolls horizontally"
assert_not_contains "$PAGE" '|---|' "tables: no raw separator row leaks into the page"

printf '\n--- legacy: a spec written before typed sections renders ---\n'
assert_eq "1" "$(printf '%s' "$PAGE" | grep -o '<h1' | wc -l | tr -d ' ')" "legacy: the page has exactly one h1"
assert_contains "$PAGE" 'Teams copy the weekly report by hand' "legacy: the summary falls back to the first Problem paragraph"
assert_contains "$PAGE" 'class="lead"' "legacy: the fallback summary is the lead card"
assert_contains "$PAGE" '>D1<' "legacy: decisions without an ID column are auto-numbered D1"
assert_contains "$PAGE" '>D2<' "legacy: and D2"
assert_contains "$PAGE" '>AC1<' "legacy: unprefixed acceptance criteria are auto-numbered AC1"
assert_contains "$PAGE" '>AC2<' "legacy: and AC2"
assert_contains "$PAGE" '<details class="text-diagram">' "legacy: an ASCII diagram sits in a collapsed text-diagram disclosure"
assert_not_contains "$PAGE" '<details class="text-diagram" open' "legacy: the text diagram is collapsed"
assert_contains "$PAGE" '| scheduler | ---&gt; | exporter' "legacy: the diagram text survives, escaped"
assert_contains "$PAGE" '<pre><code>plain text that is not a diagram' "legacy: a plain text fence stays an ordinary code block"
assert_contains "$PAGE" '<code>inline code</code> and <strong>bold</strong> and <em>italic</em>' "legacy: inline markdown renders"
assert_contains "$PAGE" '<ol>' "legacy: ordered lists render"
assert_contains "$PAGE" '<a href="docs/report-store.md">Report store notes</a>' "legacy: relative links render"
assert_contains "$PAGE" 'none — written before visual plans had typed sections.' "legacy: the preamble blockquote survives"
assert_not_contains "$PAGE" 'implementation_paths' "legacy: the frontmatter is not rendered"

render legacy-dialects
assert_eq "0" "$CODE" "legacy: older dialects (AC-1.1 ids, 1–2 ranges, 'settled (operator pick)') render"
PAGE="$(cat "$TMP/legacy-dialects.html" 2>/dev/null)"
assert_contains "$PAGE" '>AC1.1<' "legacy: a dotted AC-1.1 id normalises to AC1.1"
assert_contains "$PAGE" '>AC2<' "legacy: an 'AC-2 —' prefix normalises to AC2"
assert_contains "$PAGE" 'chip-settled' "legacy: 'settled (operator pick)' reads as settled"

finish
