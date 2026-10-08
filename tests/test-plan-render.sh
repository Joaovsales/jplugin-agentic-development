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
assert_contains "$PAGE" '<section class="lead card-lead"' "legacy: the fallback summary is the lead card"
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

printf '\n--- theme: the jplugin plan theme is inlined; no design-stack install or project DESIGN.md is read ---\n'
THEME="$REPO_ROOT/design/plan-theme"
PAGE="$(cat "$TMP/legacy.html" 2>/dev/null)"
assert_contains "$PAGE" '/* jplugin plan theme' "theme: the page inlines design/plan-theme/plan.css"
assert_contains "$PAGE" 'prefers-color-scheme: dark' "theme: the theme carries dark tokens"
assert_contains "$PAGE" '--paper:' "theme: the theme defines its paper token"
assert_contains "$PAGE" '@media print' "theme: the theme carries print rules"
assert_not_contains "$PAGE" '<link ' "theme: no stylesheet is linked; the CSS is inline"
mkdir -p "$TMP/project"
cp "$FIX/legacy.md" "$TMP/project/legacy.md"
printf '# Project design\n\nbody { color: hotpink; } PROJECT-DESIGN-MARKER\n' > "$TMP/project/DESIGN.md"
(cd "$TMP/project" && "$TEST_PYTHON" "$RENDER" legacy.md -o page.html >/dev/null 2>&1)
assert_not_contains "$(cat "$TMP/project/page.html" 2>/dev/null)" 'PROJECT-DESIGN-MARKER' "theme: a project DESIGN.md beside the spec is not read"
assert_eq "$(sed 1d "$TMP/legacy.html" | md5sum)" "$(sed 1d "$TMP/project/page.html" | md5sum)" "theme: the page is identical with or without a project DESIGN.md"
# Lowercased through tr: `grep -i` aborts on multibyte input under Git Bash.
SCRIPTS_LC="$(cat "$REPO_ROOT"/.agents/skills/visual-plan/scripts/*.py | tr 'A-Z' 'a-z')"
for scripts_needle in 'design.md' 'design-stack' '.claude/skills' 'impeccable' 'taste'; do
  if printf '%s' "$SCRIPTS_LC" | grep -qF -- "$scripts_needle"; then
    assert_eq "unread" "read" "theme: the renderer never names $scripts_needle"
  else
    assert_eq "unread" "unread" "theme: the renderer never names $scripts_needle"
  fi
done
# between <start-needle> <end-needle> <haystack> — the text from the first start
# needle up to the next end needle, so an assertion reads one card, not the page.
between() { printf '%s' "$3" | tr -d '\n' | awk -v s="$1" -v e="$2" '{i=index($0,s); if(!i) exit; r=substr($0,i); j=index(substr(r,length(s)+1),e); print (j ? substr(r,1,length(s)+j-1) : r)}'; }

render full
assert_eq "0" "$CODE" "render: full fixture exits 0"
FULL="$(cat "$TMP/full.html" 2>/dev/null)"
render plan-shape
assert_eq "0" "$CODE" "render: plan-shape fixture exits 0"
PSHAPE="$(cat "$TMP/plan-shape.html" 2>/dev/null)"

printf '\n--- decisions: both table shapes render as cards ---\n'
D2="$(between '<article class="card card-decision' '</article>' "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'id="d2"')")"
assert_contains "$D2" 'is-open' "decisions: an open system-design row is marked open"
assert_contains "$D2" '<span class="card-id">D2</span>' "decisions: the card shows its ID"
assert_contains "$D2" '<span class="chip chip-open">open</span>' "decisions: the status chip is a text label"
assert_contains "$D2" '<span class="card-label">Decision</span>' "decisions: the card carries its type label"
assert_contains "$D2" '<h3>Split threshold</h3>' "decisions: the title is the card heading"
assert_contains "$D2" '<p class="chosen"><span class="visually-hidden">Recommended: </span>50000 rows</p>' "decisions: the recommended option is visible outside the disclosure"
assert_contains "$D2" '<details class="card-more">' "decisions: the body sits in a collapsed disclosure"
assert_not_contains "$D2" '<details class="card-more" open' "decisions: the body is collapsed"
assert_contains "$D2" '<dt>Options</dt><dd>50000 rows, 100 MB</dd>' "decisions: other options sit in the body"
assert_contains "$D2" '<p class="callout-wrong"><strong>Wrong when:</strong> Rows grow past 2 KB each</p>' "decisions: Wrong when is a reversal callout"
D1="$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'id="d1"')"
assert_contains "$D1" '<span class="chip chip-settled">settled</span>' "decisions: a settled row carries the settled chip"
PD2="$(printf '%s' "$PSHAPE" | sed 's/<article/\n<article/g' | grep 'id="d2"')"
assert_contains "$PD2" 'chip-open' "decisions: a /plan row with Source = open is open"
assert_contains "$PD2" 'Not decided yet' "decisions: an open /plan row says it is not decided"
PD1="$(printf '%s' "$PSHAPE" | sed 's/<article/\n<article/g' | grep 'id="d1"')"
assert_contains "$PD1" '<span class="visually-hidden">Decision: </span>gzip</p>' "decisions: a /plan row shows its Decision as the chosen option"
assert_contains "$PD1" '<dt>Why</dt><dd>Every reader supports it</dd>' "decisions: a /plan Why is the rationale"
assert_contains "$PD1" '<dt>Source</dt><dd>user</dd>' "decisions: a /plan Source is kept"
assert_contains "$PSHAPE" 'id="d3"' "decisions: a bare number 3 in the # column becomes D3"
assert_contains "$(printf '%s' "$PAGE" | grep -o 'card card-decision[^"]*" id="d1"')" 'card-decision' "decisions: a table with no ID column still renders cards"

printf '\n--- criteria: each AC shows the slices that cover it ---\n'
AC1="$(printf '%s' "$FULL" | sed 's/<li class="card card-criterion/\n&/g' | grep 'id="ac1"' | sed 's/<\/li>.*//')"
assert_contains "$AC1" '<span class="card-id">AC1</span>' "criteria: the AC shows its ID"
assert_contains "$AC1" 'covered by <a href="#slice-1">slice 1</a>' "criteria: the AC names its covering slice"
assert_not_contains "$AC1" 'uncovered' "criteria: a covered AC has no uncovered badge"
AC3="$(printf '%s' "$FULL" | sed 's/<li class="card card-criterion/\n&/g' | grep 'id="ac3"' | sed 's/<\/li>.*//')"
assert_contains "$AC3" '<span class="chip chip-uncovered">uncovered</span>' "criteria: an AC no slice names carries the uncovered badge"
assert_contains "$AC3" 'is-uncovered' "criteria: the uncovered AC changes its border shape too"
assert_contains "$PSHAPE" 'not been sliced' "criteria: a spec with no Build Order says it has not been sliced"
assert_not_contains "$PSHAPE" '<span class="chip chip-uncovered">' "criteria: an unsliced spec marks no AC uncovered"

printf '\n--- blockers: the panel lists exactly the blocking items; the strip links its counts ---\n'
BLOCKERS="$(between '<section class="blockers' '</section>' "$FULL")"
for anchor in '#d2' '#q1' '#ac3' '#r2'; do
  assert_contains "$BLOCKERS" "href=\"$anchor\"" "blockers: lists $anchor"
done
assert_eq "4" "$(printf '%s' "$BLOCKERS" | grep -o '<li' | wc -l | tr -d ' ')" "blockers: lists exactly four items"
for anchor in '#d1' '#d3' '#q2' '#ac1' '#r1' '#r3'; do
  assert_not_contains "$BLOCKERS" "href=\"$anchor\"" "blockers: does not list $anchor"
done
assert_contains "$BLOCKERS" 'open decision' "blockers: names why each item blocks"
STRIP="$(between '<nav class="strip' '</nav>' "$FULL")"
assert_contains "$STRIP" '<a class="stat" href="#build-order"><span class="stat-n">3</span><span class="stat-l">slices</span></a>' "blockers: the strip counts slices and links Build Order"
assert_contains "$STRIP" 'href="#acceptance-criteria"><span class="stat-n">4</span><span class="stat-l">criteria</span>' "blockers: the strip counts criteria"
assert_contains "$STRIP" 'href="#decisions"><span class="stat-n">3</span><span class="stat-l">decisions</span>' "blockers: the strip counts decisions"
assert_contains "$STRIP" 'href="#risks"><span class="stat-n">4</span><span class="stat-l">risks</span>' "blockers: the strip counts risks"
assert_contains "$STRIP" 'href="#open-questions"><span class="stat-n">3</span><span class="stat-l">open items</span>' "blockers: the strip counts open decisions plus questions"
assert_contains "$STRIP" 'href="#blockers"><span class="stat-n">4</span><span class="stat-l">blockers</span>' "blockers: the strip counts blockers"
LEAD="$(between '<section class="lead' '</section>' "$FULL")"
assert_contains "$LEAD" 'The exporter turns the weekly report store into one CSV per team' "blockers: the lead card is the Summary section"
assert_eq "1" "$(printf '%s' "$FULL" | grep -o 'The exporter turns the weekly report store' | wc -l | tr -d ' ')" "blockers: the Summary renders once, as the lead"

printf '\n--- dag: Build Order renders a layered SVG with one linked, named node per slice ---\n'
DAG="$(between '<figure class="diagram card-diagram dag"' '</figure>' "$FULL")"
assert_contains "$DAG" '<svg' "dag: the Build Order carries an inline SVG"
assert_contains "$DAG" '<title id=' "dag: the SVG has a title"
assert_contains "$DAG" '<desc id=' "dag: the SVG has a description"
for n in 1 2 3; do
  assert_contains "$DAG" "<a href=\"#slice-$n\" aria-label=\"Slice $n:" "dag: node $n links to its slice card with an accessible name"
done
assert_contains "$(printf '%s' "$DAG" | sed 's/<a /\n<a /g' | grep 'href="#slice-1"')" 'data-layer="0"' "dag: slice 1 has no blocker, so it sits in layer 0"
assert_contains "$(printf '%s' "$DAG" | sed 's/<a /\n<a /g' | grep 'href="#slice-2"')" 'data-layer="1"' "dag: slice 2 is blocked by 1, so it sits in layer 1"
assert_contains "$(printf '%s' "$DAG" | sed 's/<a /\n<a /g' | grep 'href="#slice-3"')" 'data-layer="1"' "dag: slice 3 is blocked by 1, so it sits in layer 1"
assert_eq "2" "$(printf '%s' "$DAG" | grep -o 'class="edge' | wc -l | tr -d ' ')" "dag: one edge per Blocked by entry"
SLICE2="$(between '<article class="card card-slice' '</article>' "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'id="slice-2"')")"
assert_contains "$SLICE2" '<span class="card-id">S2</span>' "dag: each slice has a card with its id"
assert_contains "$SLICE2" '<h3>Splitter</h3>' "dag: the slice card names the slice"
assert_contains "$SLICE2" '<dt>Blocked by</dt><dd><a href="#slice-1">slice 1</a></dd>' "dag: the slice card links its blockers"
assert_contains "$SLICE2" '<dt>Surface</dt>' "dag: the slice card lists its surface"
assert_contains "$SLICE2" '<dt>Verify</dt>' "dag: the slice card lists its verify command"
assert_not_contains "$PSHAPE" '<article class="card card-slice' "dag: an unsliced spec renders no slice cards"
assert_not_contains "$PSHAPE" 'class="diagram card-diagram dag"' "dag: an unsliced spec renders no DAG"

printf '\n--- flow-sequence: DSL fences render as inline SVG with caption, title and desc ---\n'
FLOW="$(between '<figure class="diagram card-diagram flow"' '</figure>' "$FULL")"
assert_contains "$FLOW" '<figcaption>Weekly export path</figcaption>' "flow-sequence: the flow carries its caption"
assert_contains "$FLOW" '<title id=' "flow-sequence: the flow SVG has a title"
assert_contains "$FLOW" 'Scheduler to Exporter: Monday 06:00' "flow-sequence: the flow desc spells out each edge"
assert_contains "$FLOW" 'class="node node-new"' "flow-sequence: a (new) node is styled new"
assert_contains "$FLOW" 'class="node node-changed"' "flow-sequence: a (changed) node is styled changed"
assert_contains "$FLOW" '(new)</text>' "flow-sequence: the new marker is also a text label"
assert_contains "$FLOW" 'class="edge edge-dashed"' "flow-sequence: a --> edge is dashed"
assert_contains "$FLOW" '<details class="diagram-source"><summary>Diagram source</summary>' "flow-sequence: the DSL source sits in a disclosure"
assert_not_contains "$FLOW" '<details class="diagram-source" open' "flow-sequence: the source disclosure is collapsed"
assert_contains "$(between '<section class="lead' '</section>' "$FULL")" 'card-diagram flow' "flow-sequence: a flow inside Summary renders in the lead"
SEQ="$(between '<figure class="diagram card-diagram sequence"' '</figure>' "$FULL")"
assert_contains "$SEQ" '<figcaption>Export of one team</figcaption>' "flow-sequence: the sequence carries its caption"
assert_contains "$SEQ" 'class="frame"' "flow-sequence: an alt block draws a frame"
assert_contains "$SEQ" '>alt [rows over 50000]</text>' "flow-sequence: the frame is labelled with its condition"
assert_contains "$SEQ" '>[rows within 50000]</text>' "flow-sequence: the else branch is labelled"
assert_contains "$SEQ" 'class="frame-divider"' "flow-sequence: else draws a divider"
assert_contains "$SEQ" 'class="msg msg-reply"' "flow-sequence: a --> reply is dashed"
assert_eq "5" "$(printf '%s' "$SEQ" | grep -o 'class="lifeline"' | wc -l | tr -d ' ')" "flow-sequence: one lifeline per participant"
assert_not_contains "$FULL" '<script src' "flow-sequence: the page loads no diagram library"
assert_not_contains "$FULL" 'mermaid' "flow-sequence: no Mermaid runtime is referenced"
render diagram-escape
assert_eq "0" "$CODE" "flow-sequence: untrusted diagram text renders"
ESC="$(cat "$TMP/diagram-escape.html" 2>/dev/null)"
assert_not_contains "$ESC" 'Client <script>' "flow-sequence: a <script> node name is escaped in the SVG"
assert_not_contains "$ESC" '<b>now</b>' "flow-sequence: markup in an edge label is escaped"
assert_contains "$ESC" 'Client &lt;script&gt;' "flow-sequence: the escaped node name is still shown"
assert_contains "$ESC" 'Gateway &amp; Co' "flow-sequence: an ampersand in a node name is escaped"
assert_contains "$ESC" 'get &lt;id&gt; &amp; &quot;flag&quot;' "flow-sequence: sequence message text is escaped"

printf '\n--- risks: cards sort by impact then likelihood with text H/M/L labels ---\n'
RISKS="$(between '<section class="sec sec-risks"' '</section>' "$FULL")"
ORDER="$(printf '%s' "$RISKS" | grep -o 'id="r[0-9]"' | tr -d '\n')"
assert_eq 'id="r1"id="r2"id="r3"id="r4"' "$ORDER" "risks: R1 (H impact, M likelihood), R2 (H, L), R3 (M, H), R4 (L, L)"
R2="$(printf '%s' "$RISKS" | sed 's/<article/\n<article/g' | grep 'id="r2"')"
assert_contains "$R2" '<span class="card-label">Risk</span>' "risks: the card carries its type label"
assert_contains "$R2" '<span class="lvl lvl-L">Likelihood L</span>' "risks: likelihood is a text label"
assert_contains "$R2" '<span class="lvl lvl-H">Impact H</span>' "risks: impact is a text label"
assert_contains "$R2" 'No mitigation yet' "risks: an empty mitigation says so"
assert_contains "$R2" 'is-blocker' "risks: an unmitigated high-impact risk is a blocker card"
R1="$(printf '%s' "$RISKS" | sed 's/<article/\n<article/g' | grep 'id="r1"')"
assert_contains "$R1" '<dt>Mitigation</dt><dd>Read in pages of 5000 rows</dd>' "risks: the mitigation is shown"
assert_contains "$R1" '<dt>Slice</dt><dd><a href="#slice-1">slice 1</a></dd>' "risks: the slice links its card"
assert_not_contains "$R1" 'is-blocker' "risks: a mitigated risk is not a blocker"
render risks-none
assert_eq "0" "$CODE" "risks: 'None identified — <why>' renders"
NONE="$(between '<section class="sec sec-risks"' '</section>' "$(cat "$TMP/risks-none.html")")"
assert_contains "$NONE" '<p class="risks-none">None identified — a read-only report with no external writes.</p>' "risks: None identified renders as a single line"
assert_not_contains "$NONE" '<article' "risks: None identified renders no cards"

printf '\n--- questions: a blocking question marks its slices in the DAG and appears in Blockers ---\n'
QS="$(between '<section class="sec sec-open-questions"' '</section>' "$FULL")"
Q1="$(printf '%s' "$QS" | sed 's/<article/\n<article/g' | grep 'id="q1"')"
assert_contains "$Q1" '<span class="card-label">Question</span>' "questions: the card carries its type label"
assert_contains "$Q1" '<span class="card-icon" aria-hidden="true">?</span>' "questions: the card carries the ? icon"
assert_contains "$Q1" 'Blocks <a href="#slice-2">slice 2</a>' "questions: Blocks links the slices it blocks"
assert_contains "$Q1" 'Needed from platform team' "questions: Needed from is a tag"
assert_contains "$Q1" 'is-blocker' "questions: a blocking question is a blocker card"
Q2="$(printf '%s' "$QS" | sed 's/<article/\n<article/g' | grep 'id="q2"')"
assert_contains "$Q2" 'Blocks nothing' "questions: a non-blocking question says it blocks nothing"
assert_not_contains "$Q2" 'is-blocker' "questions: a non-blocking question is not a blocker"
DAG2="$(printf '%s' "$(between '<figure class="diagram card-diagram dag"' '</figure>' "$FULL")" | sed 's/<a /\n<a /g' | grep 'href="#slice-2"')"
assert_contains "$DAG2" 'class="node node-blocked"' "questions: the blocked slice is marked in the DAG"
assert_contains "$DAG2" '>blocked</text>' "questions: the DAG mark is also a text label"
assert_contains "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'id="slice-2"')" 'chip-blocked' "questions: the blocked slice card carries a blocked chip"
assert_not_contains "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'id="slice-3"')" 'chip-blocked' "questions: an unblocked slice carries no blocked chip"

for heading in '## Palette' '## Typography' '## Layout' '## Motion' '## Accessibility' '## Component vocabulary' '## Authoring record'; do
  assert_file_contains "$THEME/DESIGN.md" "$heading" "theme: design/plan-theme/DESIGN.md has $heading"
done

finish
