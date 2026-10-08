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
# the page refuses the Blocked by cells /slice validate refuses: one grammar for both
assert_failure fail-blocked-by 8 "Blocked by"
assert_failure fail-flow-empty 7 "empty node name"

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
assert_contains "$PAGE" '<details class="text-diagram card-text-diagram">' "legacy: an ASCII diagram sits in a collapsed text-diagram disclosure"
assert_not_contains "$PAGE" '<details class="text-diagram card-text-diagram" open' "legacy: the text diagram is collapsed"
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
mkdir -p "$TMP/bare" && cp "$FIX/legacy.md" "$TMP/bare/legacy.md"
(cd "$TMP/bare" && "$TEST_PYTHON" "$RENDER" legacy.md -o page.html >/dev/null 2>&1)
assert_eq "$(md5sum < "$TMP/bare/page.html")" "$(md5sum < "$TMP/project/page.html")" "theme: the page is identical with or without a project DESIGN.md"
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
RISKS="$(between '<section class="sec sec-risks' '</section>' "$FULL")"
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
NONE="$(between '<section class="sec sec-risks' '</section>' "$(cat "$TMP/risks-none.html")")"
assert_contains "$NONE" '<p class="risks-none">None identified — a read-only report with no external writes.</p>' "risks: None identified renders as a single line"
assert_not_contains "$NONE" '<article' "risks: None identified renders no cards"

printf '\n--- questions: a blocking question marks its slices in the DAG and appears in Blockers ---\n'
QS="$(between '<section class="sec sec-open-questions' '</section>' "$FULL")"
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

printf '\n--- disclosure: approval content is open, reference content is collapsed ---\n'
sec_details() { printf '%s' "$FULL" | tr -d '\n' | grep -o "<section class=\"sec sec-[a-z-]*[^\"]*\" id=\"$1\"[^>]*><details class=\"sec-body\"[^>]*>"; }
for sid in decisions acceptance-criteria risks open-questions build-order system-design behavior; do
  assert_contains "$(sec_details "$sid")" ' open>' "disclosure: § $sid is open on load"
done
for sid in constraints component-contracts data-models references; do
  got="$(sec_details "$sid")"
  assert_contains "$got" '<details class="sec-body">' "disclosure: § $sid is present and collapsed on load"
done
assert_contains "$FULL" '<section class="lead' "disclosure: the lead summary is outside any disclosure"
assert_contains "$FULL" '<nav class="strip' "disclosure: the summary strip is outside any disclosure"
assert_contains "$FULL" '<section class="blockers' "disclosure: Blockers is outside any disclosure"
CON="$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'card card-constraint' | grep 'Export window')"
assert_contains "$CON" '<span class="chip chip-verify">verify</span>' "disclosure: an inferred constraint carries a verify badge"
assert_contains "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'card card-constraint' | grep 'Maximum rows')" 'card-label">Constraint' "disclosure: constraints render as typed cards"
CT="$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'card card-contract' | grep 'Exporter')"
assert_contains "$CT" '<span class="chip chip-new">new</span>' "disclosure: a (NEW) contract heading becomes a new chip"
assert_contains "$CT" '<h3>Exporter</h3>' "disclosure: the contract title drops the parenthetical"
assert_contains "$CT" '<button type="button" class="copy"' "disclosure: a contract block has a copy button"
assert_contains "$CT" 'export(team_id: str, rows: Iterable[Row]) -&gt; list[Path]' "disclosure: the contract signature is kept"
assert_contains "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'card card-contract' | grep 'Splitter')" '<span class="chip chip-changed">changed</span>' "disclosure: a (changed) contract heading becomes a changed chip"
assert_contains "$(printf '%s' "$FULL" | sed 's/<article/\n<article/g' | grep 'card card-model')" '<th scope="col">Field</th>' "disclosure: a data model renders its schema table"
assert_contains "$FULL" 'class="card card-reference"' "disclosure: references render as reference items"
CTRL="$(between '<div class="controls"' '</div>' "$FULL")"
assert_contains "$CTRL" '<button type="button" class="btn" data-action="expand">Expand all</button>' "disclosure: Expand all is a named button"
assert_contains "$CTRL" '<button type="button" class="btn" data-action="collapse">Collapse all</button>' "disclosure: Collapse all is a named button"
assert_contains "$CTRL" '<button type="button" class="btn" data-action="blockers" aria-pressed="false">Show only blockers</button>' "disclosure: Show only blockers is a toggle button"
assert_contains "$(printf '%s' "$FULL" | tr -d '\n' | grep -o '<section class="sec sec-decisions[^"]*"')" 'has-blockers' "disclosure: a section holding a blocker card is marked for blockers-only view"
assert_not_contains "$(printf '%s' "$FULL" | tr -d '\n' | grep -o '<section class="sec sec-constraints[^"]*"')" 'has-blockers' "disclosure: a section with no blocker is not marked"

printf '\n--- deep-links: the page script opens collapsed ancestors and dismisses the mobile menu ---\n'
SCRIPT="$(between '<script>' '</script>' "$FULL")"
assert_contains "$SCRIPT" 'function openTo(' "deep-links: the script has a hash target opener"
assert_contains "$SCRIPT" "closest('details')" "deep-links: the opener walks up through every ancestor details"
assert_contains "$SCRIPT" "addEventListener('hashchange'" "deep-links: a hash change opens its target"
assert_contains "$SCRIPT" 'openTo(location.hash' "deep-links: the initial URL fragment is honoured on load"
assert_contains "$SCRIPT" "matchMedia('(max-width: 767px)')" "deep-links: the menu knows the 768 px breakpoint"
assert_contains "$SCRIPT" 'menu.open = false' "deep-links: choosing an item closes the mobile menu"
assert_contains "$SCRIPT" 'IntersectionObserver' "deep-links: the table of contents has scrollspy"
assert_contains "$SCRIPT" "'aria-current'" "deep-links: the active entry is exposed as aria-current"
assert_contains "$SCRIPT" "addEventListener('beforeprint'" "deep-links: printing opens every disclosure"
TOC="$(between '<nav class="toc"' '</nav>' "$FULL")"
assert_contains "$TOC" '<details class="toc-menu" open><summary>Contents</summary>' "deep-links: the table of contents is a details menu"
for sid in summary-lead blockers decisions acceptance-criteria build-order references; do
  assert_contains "$TOC" "href=\"#$sid\"" "deep-links: the table of contents links #$sid"
done
assert_contains "$FULL" '<div class="shell"><nav class="toc"' "deep-links: the navigation sits in the layout shell beside main"

printf '\n--- prompt: the build-prompt panel copies the canonical Build Order prompt ---\n'
# full.md is deliberately not ready (D2 open, Q1 blocks slice 2); the ready
# variant settles D2 and unblocks Q1, so its prompt is executable.
mkdir -p "$TMP/ready"
sed -e 's/| Rows grow past 2 KB each | open |/| Rows grow past 2 KB each | settled |/' \
    -e 's/| Which bucket region holds part files? | 2 |/| Which bucket region holds part files? | none |/' \
    "$FIX/full.md" > "$TMP/ready/full.md"
(cd "$TMP/ready" && "$TEST_PYTHON" "$RENDER" full.md -o full.html >/dev/null 2>&1)
READY="$(cat "$TMP/ready/full.html" 2>/dev/null)"
PANEL="$(between '<section class="card card-prompt' '</section>' "$READY")"
assert_not_contains "$PANEL" 'not-ready' "prompt: the ready variant's panel is executable"
assert_contains "$PANEL" 'id="build-prompt"' "prompt: the panel has a stable anchor"
assert_contains "$PANEL" '<span class="card-label">Build prompt</span>' "prompt: the panel carries its type label"
assert_contains "$PANEL" '<button type="button" class="copy" data-copy-from="build-prompt-text">Copy build prompt</button>' "prompt: Copy build prompt copies the prompt element"
assert_contains "$(between '<header class="masthead"' '</header>' "$FULL")" 'href="#build-prompt"' "prompt: the first screen links the panel"
assert_contains "$(between '<nav class="toc"' '</nav>' "$FULL")" 'href="#build-prompt"' "prompt: the table of contents links the panel"
cat > "$TMP/prompt_bytes.py" <<'PY'
import html, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
spec = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r'<code id="build-prompt-text">(.*?)</code>', page, re.S)
canon = re.search(r"Build prompt:\s*\n\s*```\n(.*?)\n```", spec, re.S)
print("equal" if m and canon and html.unescape(m.group(1)) == canon.group(1) else "differ")
PY
assert_eq "equal" "$("$TEST_PYTHON" "$TMP/prompt_bytes.py" "$TMP/ready/full.html" "$TMP/ready/full.md")" "prompt: the copy payload equals the Build Order prompt byte for byte"

printf '\n--- not-ready: an open decision or a blocking question disables the prompt ---\n'
NR="$(between '<section class="card card-prompt' '</section>' "$FULL")"
assert_contains "$NR" 'card card-prompt not-ready' "not-ready: the panel switches to its not-ready shape"
assert_contains "$NR" '<p class="not-ready-msg">Not ready: <a href="#d2">D2</a>, <a href="#q1">Q1</a></p>' "not-ready: the panel names the same ids /slice prints"
assert_contains "$NR" 'data-copy-from="build-prompt-text" disabled>Copy build prompt</button>' "not-ready: copy is disabled"
assert_not_contains "$NR" '<details class="prompt-stale" open' "not-ready: the superseded prompt text is not shown as executable"
assert_eq "not ready: D2, Q1" "$(cd "$FIX" && "$TEST_PYTHON" "$REPO_ROOT/.agents/skills/slice/scripts/slice.py" readiness --spec full.md)" "not-ready: /slice readiness names the same ids for the same spec"
assert_contains "$(between '<header class="masthead"' '</header>' "$FULL")" 'Not ready' "not-ready: the first screen says the prompt is not ready"
assert_contains "$PANEL" 'quote &quot;values&quot; &amp; &lt;escape&gt; them' "prompt: the prompt payload is HTML-escaped"
assert_not_contains "$PSHAPE" 'id="build-prompt"' "prompt: an unsliced spec has no prompt panel"

printf '\n--- source: the header names the spec and its hash; nothing is embedded or fetched ---\n'
SHA="$("$TEST_PYTHON" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],encoding="utf-8").read().encode()).hexdigest()[:12])' "$FIX/full.md")"
HEADER="$(between '<header class="masthead"' '</header>' "$FULL")"
assert_contains "$HEADER" "\">full.md</a> · sha256 <code>$SHA</code>" "source: the header names the spec with its SHA-256 prefix"
assert_contains "$HEADER" '<p class="source">Source: <a href="' "source: the source line is a link"
assert_eq "$SHA" "$(cd "$FIX" && "$TEST_PYTHON" "$RENDER" --hash full.md)" "source: --hash prints the same prefix for /plan to compare"
mkdir -p "$TMP/out/plans"
(cd "$FIX" && "$TEST_PYTHON" "$RENDER" full.md -o "$TMP/out/plans/full.plan.html" >/dev/null 2>&1)
REL="$("$TEST_PYTHON" -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace(os.sep, "/"))' "$FIX/full.md" "$TMP/out/plans")"
assert_contains "$(cat "$TMP/out/plans/full.plan.html")" "<a href=\"$REL\">" "source: the link is relative to where the page is written"
assert_not_contains "$FULL" '| ID | Decision | Options |' "source: no raw markdown table is embedded"
assert_not_contains "$FULL" 'implementation_paths' "source: the frontmatter is not embedded"
assert_not_contains "$FULL" 'text/markdown' "source: no markdown payload block"
assert_not_contains "$FULL" 'download' "source: no download of the markdown is offered"
for needle in 'src="http' "src='http" '<link' '@import' 'url(http' 'fetch(' 'XMLHttpRequest' 'sendBeacon' 'WebSocket'; do
  assert_not_contains "$FULL" "$needle" "source: nothing loads over the network ($needle)"
done

printf '\n--- review: hash-keyed marks on every reviewable card, an export /plan applies ---\n'
for id in AC1 D1 D2 R1 Q1 S1; do
  assert_contains "$FULL" "<div class=\"review\" data-review=\"$id\"" "review: $id carries ok / questioned controls"
done
D2CARD="$(between '<article class="card card-decision is-open is-blocker" id="d2"' '</article>' "$FULL")"
assert_contains "$D2CARD" '<option value="A">A — 50000 rows</option><option value="B">B — 100 MB</option>' "review: an open decision offers its options as lettered picks"
assert_not_contains "$(between '<article class="card card-decision" id="d1"' '</article>' "$FULL")" 'data-field="pick"' "review: a settled decision has no picker"
assert_contains "$(between ' id="q1"' '</article>' "$FULL")" '<input data-field="answer"' "review: a question has an answer field"
REVIEW="$(between '<section class="review-panel"' '</section>' "$FULL")"
assert_contains "$REVIEW" "data-spec=\"full.md\" data-sha=\"$SHA\"" "review: the panel carries the spec path and its SHA-256 prefix"
assert_contains "$REVIEW" 'data-action="export-review">Export review</button>' "review: the panel offers Export review"
assert_contains "$FULL" "return 'jplugin-plan-review:' + sha + ':' + spec;" "review: the storage key includes the spec hash"
assert_contains "$(between '<nav class="toc"' '</nav>' "$FULL")" '<a href="#review">Review</a>' "review: the contents list the review panel"
if command -v node >/dev/null 2>&1; then
  cp "$(dirname "$RENDER")/plan_page.js" "$TMP/plan_page.js"
  cat > "$TMP/review-check.js" <<'EOF'
var r = require('./plan_page.js');
var items = [['D3', {mark: 'questioned', note: 'why not\n  JSON?'}], ['D4', {pick: 'B', note: 'fits'}],
  ['Q2', {answer: 'yes, weekly'}], ['AC5', {mark: 'ok'}], ['S4', {mark: 'questioned', note: 'too big'}],
  ['AC6', {}], ['R1', undefined]];
console.log(r.format('specs/x.md', 'abc123def456', items));
var denied = r.openStore(function () { throw new Error('denied'); }, 'k');
console.log('denied', denied.ok, JSON.stringify(denied.load()), denied.save({a: 1}));
var full = r.openStore(function () {
  return {setItem: function () { throw new Error('quota'); }, removeItem: function () {}, getItem: function () { return null; }};
}, 'k');
console.log('full', full.ok, JSON.stringify(full.load()));
EOF
  EXPECTED="Review of specs/x.md @ abc123def456
D3: questioned — why not JSON?
D4: pick B — fits
Q2: answer — yes, weekly
AC5: ok
S4: questioned — too big
denied false {} false
full false {}"
  assert_eq "$EXPECTED" "$(cd "$TMP" && node review-check.js | tr -d '\r')" "review: the export matches the § Behavior block, and a throwing storage is handled"
else
  printf '  SKIP review: node is not installed — the export format and storage fallback are unchecked\n'
fi
assert_contains "$FULL" 'review marks will not persist' "review: a failing localStorage says marks will not persist"

printf '\n--- plan-consumer: /plan applies a review export and refuses a stale one ---\n'
PLAN_SKILL="$REPO_ROOT/.agents/skills/plan/SKILL.md"
assert_file_contains "$PLAN_SKILL" 'Review of specs/<feature>.md @ <sha256[:12]>' "plan-consumer: /plan names the export block it accepts"
assert_file_contains "$PLAN_SKILL" 'plan_render.py --hash specs/<feature>.md' "plan-consumer: /plan compares the block's hash with plan_render.py --hash"
assert_file_contains "$PLAN_SKILL" 'naming both hashes' "plan-consumer: a hash mismatch is refused naming both hashes"
for verb in 'answer' 'pick' 'questioned' 'ok'; do
  assert_file_contains "$PLAN_SKILL" "\`<ID>: $verb" "plan-consumer: /plan says how a \`$verb\` line is applied"
done
assert_file_contains "$PLAN_SKILL" 'then re-run Step 3' "plan-consumer: an applied review re-runs /slice"

printf '\n--- distinct: every component type is present and told apart by icon and label ---\n'
cat > "$TMP/distinct.py" <<'EOF'
import html, re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from plan_cards import COMPONENTS
page = open(sys.argv[2], encoding="utf-8").read()
page = page[page.index("<body"):]
pairs = {}
for kind, (glyph, text) in COMPONENTS.items():
    m = re.search(r'class="[^"]*\bcard-%s\b[^"]*"' % re.escape(kind), page)
    if not m:
        print("missing: %s" % kind)
        continue
    head = page[m.end():m.end() + 600]
    if ('<span class="card-icon" aria-hidden="true">%s</span>' % html.escape(glyph, quote=False)) not in head \
            or ('<span class="card-label">%s</span>' % html.escape(text, quote=False)) not in head:
        print("unlabelled: %s" % kind)
    pairs.setdefault((glyph, text), []).append(kind)
    pairs.setdefault(("icon", glyph), []).append(kind)
    pairs.setdefault(("label", text), []).append(kind)
for key, kinds in pairs.items():
    if len(kinds) > 1:
        print("shared %s: %s" % (key[0], ", ".join(kinds)))
EOF
assert_eq "" "$("$TEST_PYTHON" "$TMP/distinct.py" "$(dirname "$RENDER")" "$TMP/full.html" 2>&1)" "distinct: every registry type renders in full.md with its own icon and label, none shared"

printf '\n--- preservation: what the spec says reaches the page ---\n'
cat > "$TMP/preserve.py" <<'EOF'
import html, re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from plan_md import parse_document, plain
from plan_sections import parse_build_order, parse_criteria

# typed sections: their table headings and ID prefixes become card chrome
TYPED = ("decisions", "acceptance criteria", "risks", "open questions", "build order")

UNITS = r"(?:%|ms|s|seconds?|minutes?|hours?|days?|weeks?|KB|KiB|MB|MiB|GB|bytes?|rows?|px|chars?|characters|lines?|files?|slices?|UTC)"

def norm(text):
    return re.sub(r"\s+", " ", text).strip()

def page_text(path):
    raw = open(path, encoding="utf-8").read()
    raw = re.sub(r"<(style|script)\b.*?</\1>", " ", raw, flags=re.S)
    return norm(html.unescape(re.sub(r"<[^>]+>", " ", raw)))

def expected(doc):
    """AC sentences, table rows (decisions included), code lines (signatures), numeric limits."""
    for section in doc.sections:
        key = plain(section.title).lower()
        if key == "acceptance criteria":
            for c in parse_criteria(section):
                yield "AC sentence", c.text
            continue
        if key == "build order":
            for sl in parse_build_order(section).slices:
                yield "slice", "S%d" % sl.number
                for col, cell in sl.cells.items():
                    if col not in ("#", "blocked by", "acs") and plain(cell):
                        yield "slice cell", plain(cell)
                for ac in sl.acs:
                    yield "slice criterion", ac
        for b in section.blocks:
            if b.kind == "table" and key == "build order":
                continue
            if b.kind == "table":
                for row in (b.rows[1:] if key in TYPED else b.rows):
                    for cell in row:
                        if plain(cell).strip():
                            yield "table cell", plain(cell)
            elif b.kind == "code":
                for line in b.text.splitlines():
                    if line.strip():
                        yield "code line", line
            elif b.kind == "list":
                for item in b.items:
                    yield "list item", plain(item.text)
            elif b.kind == "para":
                for m in re.finditer(r"\b\d[\d,.]*\s?" + UNITS + r"\b", plain(b.text)):
                    yield "numeric limit", m.group(0)

doc = parse_document(open(sys.argv[2], encoding="utf-8").read())
text = page_text(sys.argv[3])
squeezed = text.replace(" ", "")  # tags became spaces; inline markup may split a phrase
for what, item in expected(doc):
    if norm(item).replace(" ", "") not in squeezed:
        print("%s missing: %s" % (what, norm(item)[:80]))
EOF
for name in full legacy legacy-dialects plan-shape diagram-escape risks-none; do
  (cd "$FIX" && "$TEST_PYTHON" "$RENDER" "$name.md" -o "$TMP/preserve-$name.html" >/dev/null 2>&1)
  assert_eq "" "$("$TEST_PYTHON" "$TMP/preserve.py" "$(dirname "$RENDER")" "$FIX/$name.md" "$TMP/preserve-$name.html" 2>&1)" \
    "preservation: every AC sentence, table row, code line and numeric limit of $name.md is in its page"
done

printf '\n--- wiring: both planners render through plan_render.py, from the spec alone ---\n'
VP_SKILL="$REPO_ROOT/.agents/skills/visual-plan/SKILL.md"
SDP_SKILL="$REPO_ROOT/.agents/skills/system-design-planning/SKILL.md"
for f in "$VP_SKILL" "$SDP_SKILL"; do
  name="$(basename "$(dirname "$f")")"
  assert_file_contains "$f" 'python3 .agents/skills/visual-plan/scripts/plan_render.py specs/<feature>.md -o specs/<feature>.plan.html' "wiring: $name renders with plan_render.py"
  assert_file_not_matches "$f" 'visual-render.py' "wiring: $name no longer calls the recap renderer"
  assert_file_not_matches "$f" 'content-model.json' "wiring: $name builds no content model"
  assert_file_not_matches "$f" '```text blocks' "wiring: $name no longer requires text fences for diagrams and tables"
done
assert_eq "absent" "$([ -e "$REPO_ROOT/.agents/skills/system-design-planning/templates/content-model.json" ] && echo present || echo absent)" "wiring: content-model.json is removed"

printf '\n--- template: the system-design template carries what the renderer types ---\n'
SDP_TMPL="$REPO_ROOT/.agents/skills/system-design-planning/templates/architecture-spec-template.md"
for heading in '## Summary' '## Risks' '## Open questions'; do
  assert_file_contains "$SDP_TMPL" "$heading" "template: has $heading"
done
assert_file_contains "$SDP_TMPL" '| ID | Decision | Options | Recommended | Wrong when | Status |' "template: Decisions carry ID and Status columns"
assert_file_contains "$SDP_TMPL" '| ID | Risk | Likelihood | Impact | Mitigation | Slice |' "template: Risks carry the typed columns"
assert_file_contains "$SDP_TMPL" '| ID | Question | Blocks | Needed from |' "template: Open questions carry the typed columns"
assert_file_contains "$SDP_TMPL" '```flow' "template: System design shows a flow diagram"
assert_file_contains "$SDP_TMPL" '```sequence' "template: a contract shows a sequence diagram"
assert_file_contains "$SDP_TMPL" '- AC1:' "template: criteria carry AC ids"
SDP_TMPL_SPEC="$TMP/template-spec.md"
sed '/^<!--/,/-->$/d' "$SDP_TMPL" > "$SDP_TMPL_SPEC"
assert_eq "0" "$(cd "$TMP" && "$TEST_PYTHON" "$RENDER" template-spec.md -o template-spec.html >/dev/null 2>&1; echo $?)" "template: the template itself renders"
assert_contains "$(cat "$TMP/template-spec.html" 2>/dev/null)" 'has not been sliced' "template: an empty Build order renders as a spec not sliced yet, not a failure"
assert_file_contains "$SDP_SKILL" 'at least one `flow` diagram under § System design' "template: /system-design-planning requires a flow diagram"
assert_file_contains "$SDP_SKILL" 'a `sequence` diagram for each changed external contract or cross-component failure path' "template: /system-design-planning requires sequence diagrams"
assert_file_contains "$SDP_SKILL" '| Risks |' "template: /system-design-planning requires § Risks"

printf '\n--- editorial: both planners tell the author how to write a readable spec ---\n'
for f in "$REPO_ROOT/.agents/skills/plan/SKILL.md" "$SDP_SKILL"; do
  name="$(basename "$(dirname "$f")")"
  for phrase in 'remove repetition' 'empty qualifiers' 'workflow narration' 'connected sentences' 'slash-packed shorthand'; do
    assert_prose_contains "$f" "$phrase" "editorial: $name says '$phrase'"
  done
done
for heading in '## Summary' '## Risks' '## Open questions'; do
  assert_file_contains "$REPO_ROOT/.agents/skills/plan/SKILL.md" "$heading" "template: /plan's template offers $heading"
done
assert_file_contains "$REPO_ROOT/.agents/skills/plan/SKILL.md" '- AC1:' "template: /plan's criteria carry AC ids"

for heading in '## Palette' '## Typography' '## Layout' '## Motion' '## Accessibility' '## Component vocabulary' '## Authoring record'; do
  assert_file_contains "$THEME/DESIGN.md" "$heading" "theme: design/plan-theme/DESIGN.md has $heading"
done

finish
