#!/usr/bin/env bash
# Tests for the visual-recap HTML post-processor (visual-render.py).
# Verifies diff coloring and keychange tabset injection on top of the
# base html-presentation generator output.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDER_SCRIPT="$REPO_ROOT/.claude/skills/visual-recap/scripts/visual-render.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FIXTURE="$TMP/model.json"
OUT="$TMP/out.html"

cat >"$FIXTURE" <<'JSON'
{
  "title": "Visual Render Test",
  "subtitle": "fixture",
  "takeaway": "Testing diff coloring and keychange tabs.",
  "meta": {},
  "summary_cards": [],
  "sections": [
    {
      "id": "overview",
      "title": "Overview",
      "icon": "",
      "body_md": "A normal section with plain text."
    },
    {
      "id": "the-diff",
      "title": "The Diff",
      "icon": "",
      "body_md": "```diff\n+added line\n-removed line\n context line\n```"
    },
    {
      "id": "keychange-1",
      "title": "Key Change 1",
      "icon": "",
      "body_md": "First key change."
    },
    {
      "id": "keychange-2",
      "title": "Key Change 2",
      "icon": "",
      "body_md": "Second key change."
    }
  ],
  "code_blocks": [],
  "references": [],
  "reflection": ""
}
JSON

python3 "$RENDER_SCRIPT" --input "$FIXTURE" -o "$OUT" >"$TMP/render.log" 2>&1
RENDER_STATUS=$?
assert_eq "0" "$RENDER_STATUS" "visual-render.py exits 0"

HEAD="$(sed '/<\/head>/q' "$OUT" 2>/dev/null)"

# 1. Base generator CSS survived + injected diff CSS present + injected before </head>
assert_file_contains "$OUT" "--accent" "base generator CSS (--accent) survived"
assert_file_contains "$OUT" ".diff-add" "injected diff-add CSS present"
assert_contains "$HEAD" ".diff-add" "injected marker appears before </head>"

# 2. (AC5) diff-del CSS + diff-coloring JS present
assert_file_contains "$OUT" ".diff-del" "injected diff-del CSS present"
assert_file_contains "$OUT" "lang-diff" "diff-coloring JS references lang-diff"

# 3. (AC4) tabset markup + tab switch JS present
assert_file_contains "$OUT" "tab-btn" "tab-btn CSS/markup present"
assert_file_contains "$OUT" "tabset" "tabset CSS/markup present"
assert_file_contains "$OUT" "addEventListener" "tab switch JS uses addEventListener"

# 4. (AC6) no network refs in <head>
assert_not_contains "$HEAD" "http://" "head has no http:// references"
assert_not_contains "$HEAD" "https://" "head has no https:// references"
assert_not_contains "$HEAD" " src=" "head has no external src= attributes"

# --- Group E: acceptance-criteria smoke tests ---

# (AC1) visual-plan-shaped model: narrative + file map (with a NEW file) + open questions.
PLAN_FIXTURE="$TMP/plan-model.json"
PLAN_OUT="$TMP/plan-out.html"

cat >"$PLAN_FIXTURE" <<'JSON'
{
  "title": "Widget Export Visual Plan",
  "subtitle": "spec walkthrough",
  "takeaway": "Adds a CSV export button to the widget dashboard.",
  "meta": {},
  "summary_cards": [],
  "sections": [
    {
      "id": "narrative",
      "title": "Narrative",
      "icon": "",
      "body_md": "This plan adds a CSV export button to the widget dashboard so operators can download the current view without leaving the page."
    },
    {
      "id": "file-map",
      "title": "File Map",
      "icon": "",
      "body_md": "- `src/widgets/export.py` — NEW: export handler\n- `src/widgets/dashboard.py` — wires the export button into the toolbar"
    },
    {
      "id": "open-questions",
      "title": "Open Questions",
      "icon": "",
      "body_md": "Should the export include archived widgets, or only active ones? This is hard to reverse once external tooling depends on the CSV shape."
    }
  ],
  "code_blocks": [],
  "references": [],
  "reflection": ""
}
JSON

python3 "$RENDER_SCRIPT" --input "$PLAN_FIXTURE" -o "$PLAN_OUT" >"$TMP/plan-render.log" 2>&1
assert_eq "0" "$?" "(AC1) plan fixture renders exit 0"
assert_file_contains "$PLAN_OUT" "CSV export button to the widget dashboard" "(AC1) narrative text present"
assert_file_contains "$PLAN_OUT" "src/widgets/export.py" "(AC1) file-map filename present"
assert_file_contains "$PLAN_OUT" "NEW" "(AC1) file-map NEW marker present"
assert_file_contains "$PLAN_OUT" "archived widgets" "(AC1) open-questions text present"
assert_file_contains "$PLAN_OUT" "data-theme" "(AC1) data-theme signal present"
assert_file_contains "$PLAN_OUT" '[data-theme="light"]' "(AC1) light-theme CSS signal present"

# (AC3/AC7) recap fixture: file-tree body lists exactly three known entries from
# a --name-status-style list — renderer must neither invent nor drop entries.
RECAP_FIXTURE="$TMP/recap-model.json"
RECAP_OUT="$TMP/recap-out.html"

cat >"$RECAP_FIXTURE" <<'JSON'
{
  "title": "Recap Fixture",
  "subtitle": "faithful rendering",
  "takeaway": "Three files changed.",
  "meta": {},
  "summary_cards": [],
  "sections": [
    {
      "id": "file-tree",
      "title": "File Tree",
      "icon": "",
      "body_md": "A  src/added.py\nM  src/changed.py\nD  src/removed.py"
    }
  ],
  "code_blocks": [],
  "references": [],
  "reflection": ""
}
JSON

python3 "$RENDER_SCRIPT" --input "$RECAP_FIXTURE" -o "$RECAP_OUT" >"$TMP/recap-render.log" 2>&1
assert_eq "0" "$?" "(AC3/AC7) recap fixture renders exit 0"
assert_file_contains "$RECAP_OUT" "src/added.py" "(AC3/AC7) added file present"
assert_file_contains "$RECAP_OUT" "src/changed.py" "(AC3/AC7) changed file present"
assert_file_contains "$RECAP_OUT" "src/removed.py" "(AC3/AC7) removed file present"
assert_not_contains "$(cat "$RECAP_OUT")" "src/PHANTOM_NOT_IN_DIFF.py" \
  "(AC3/AC7) renderer invents no entries not in the diff"

# (AC6) checksum guard: the base generator is untouched by post-processor renders.
GEN_CLAUDE="$REPO_ROOT/.claude/skills/html-presentation/scripts/generate-presentation.py"
GEN_AGENTS="$REPO_ROOT/.agents/skills/html-presentation/scripts/generate-presentation.py"
CKSUM_CLAUDE_BEFORE="$(cksum "$GEN_CLAUDE")"
CKSUM_AGENTS_BEFORE="$(cksum "$GEN_AGENTS")"

python3 "$RENDER_SCRIPT" --input "$FIXTURE" -o "$TMP/cksum-guard-out.html" >"$TMP/cksum-render.log" 2>&1

CKSUM_CLAUDE_AFTER="$(cksum "$GEN_CLAUDE")"
CKSUM_AGENTS_AFTER="$(cksum "$GEN_AGENTS")"
assert_eq "$CKSUM_CLAUDE_BEFORE" "$CKSUM_CLAUDE_AFTER" "(AC6) .claude generate-presentation.py untouched by render"
assert_eq "$CKSUM_AGENTS_BEFORE" "$CKSUM_AGENTS_AFTER" "(AC6) .agents generate-presentation.py untouched by render"

# Regression: pin the base generator's </head> contract that the splice relies on.
python3 "$REPO_ROOT/.claude/skills/html-presentation/scripts/generate-presentation.py" \
  --input "$FIXTURE" -o "$TMP/base_only.html" >"$TMP/base-only.log" 2>&1
assert_file_contains "$TMP/base_only.html" "</head>" "base generator still emits </head> (splice contract)"

# --- Group F: system-design-planning content-model template renders ---
# The skill's Step 6 renders templates/content-model.json through this script;
# a template the renderer rejects is a skill whose Step 6 cannot run. The
# generator appends its own reflection/references sections after the authored
# ones, so those are filtered out and the whole remaining list is compared —
# an eighth authored section would fail this, where a head -7 would not.
SDP_MODEL="$REPO_ROOT/.agents/skills/system-design-planning/templates/content-model.json"
SDP_OUT="$TMP/sdp-out.html"
python3 "$RENDER_SCRIPT" --input "$SDP_MODEL" -o "$SDP_OUT" >"$TMP/sdp-render.log" 2>&1
SDP_STATUS=$?
[ "$SDP_STATUS" -eq 0 ] || cat "$TMP/sdp-render.log"
assert_eq "0" "$SDP_STATUS" "(system-design-planning) content-model.json renders exit 0"
SDP_IDS="$(grep -o 'section id="[a-z-]*"' "$SDP_OUT" | sed 's/section id="//; s/"//' | grep -vE '^(reflection|references|code-blocks)$' | paste -sd ' ' -)"
assert_eq "problem constraints system-design contracts data-models build-order decisions" "$SDP_IDS" \
  "(system-design-planning) rendered sections are the seven authored ones, in order"

finish
