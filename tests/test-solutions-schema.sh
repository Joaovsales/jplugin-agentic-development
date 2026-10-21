#!/bin/bash
# tests/test-solutions-schema.sh — validates typed learning store documents
# (tasks/solutions/<category>/<slug>.md) against the schema in
# tasks/solutions/README.md: required frontmatter, problem_type enum, category
# map, track-required fields, and no dates in filenames.
# Self-tests the validator against bad fixtures, then validates the real store.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

# The store this file validates; the literal is what affected.sh selects on.
STORE="$(under_test tasks/solutions)"

# validate_doc <file> — print one violation per line; silent when valid.
validate_doc() {
  local f="$1" base fm pt expected_dir track dir key
  base="$(basename "$f" .md)"
  case "$base" in
    *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*|[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*)
      echo "$f: date in filename (dates belong in frontmatter)" ;;
  esac
  fm="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$f")"
  if [ -z "$fm" ]; then echo "$f: missing frontmatter block"; return; fi
  # Here-strings, not `printf | grep -q`: grep -q exits at its first match, and
  # under pipefail the SIGPIPE printf then takes reports a valid key as missing.
  grep -Eq '^title: *[^ ]'  <<<"$fm" || echo "$f: missing title"
  grep -Eq '^module: *[^ ]' <<<"$fm" || echo "$f: missing module"
  grep -Eq '^date: *[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$fm" \
    || echo "$f: missing or malformed date (YYYY-MM-DD)"
  grep -Eq '^tags: *\[[^]]+\]' <<<"$fm" || echo "$f: missing or empty tags"
  pt="$(sed -n 's/^problem_type: *//p' <<<"$fm" | head -1)"
  case "$pt" in
    bug|build-failure|test-failure|runtime-error) expected_dir=bugs;         track=bug ;;
    performance)                                  expected_dir=performance;  track=bug ;;
    security)                                     expected_dir=security;     track=bug ;;
    architecture-decision)                        expected_dir=architecture; track=knowledge ;;
    pattern)                                      expected_dir=patterns;     track=knowledge ;;
    convention)                                   expected_dir=conventions;  track=knowledge ;;
    tooling)                                      expected_dir=tooling;      track=knowledge ;;
    process)                                      expected_dir=process;      track=knowledge ;;
    *) echo "$f: unknown problem_type '$pt'"; return ;;
  esac
  dir="$(basename "$(dirname "$f")")"
  [ "$dir" = "$expected_dir" ] || echo "$f: category dir '$dir' does not match problem_type '$pt' (expected $expected_dir)"
  if [ "$track" = bug ]; then
    for key in symptoms root_cause resolution; do
      grep -q "^$key:" <<<"$fm" || echo "$f: bug track missing $key"
    done
  else
    grep -q '^applies_when:' <<<"$fm" || echo "$f: knowledge track missing applies_when"
  fi
}

# validate_store <dir> — validate every category document under a store root.
validate_store() {
  local f
  for f in "$1"/*/*.md; do
    [ -e "$f" ] || continue
    validate_doc "$f"
  done
}

# --- Self-test: the validator must reject each violation kind ---------------
FIX="$(fixture_dir)"
mkdir -p "$FIX/patterns" "$FIX/bugs"

cat > "$FIX/patterns/unknown-type.md" <<'EOF'
---
title: Unknown type fixture
date: 2026-08-11
problem_type: banana
module: tests
tags: [fixture]
applies_when: never
---
Body.
EOF

cat > "$FIX/bugs/missing-root-cause.md" <<'EOF'
---
title: Bug missing track field
date: 2026-08-11
problem_type: bug
module: tests
tags: [fixture]
symptoms: it broke
resolution: restarted
---
Body.
EOF

cat > "$FIX/patterns/missing-applies-when.md" <<'EOF'
---
title: Knowledge missing track field
date: 2026-08-11
problem_type: pattern
module: tests
tags: [fixture]
---
Body.
EOF

cat > "$FIX/patterns/2026-08-11-dated-name.md" <<'EOF'
---
title: Dated filename fixture
date: 2026-08-11
problem_type: pattern
module: tests
tags: [fixture]
applies_when: never
---
Body.
EOF

cat > "$FIX/patterns/valid-doc.md" <<'EOF'
---
title: Valid knowledge doc
date: 2026-08-11
problem_type: pattern
module: tests
tags: [fixture, schema]
applies_when: validating this test
---
Body.
EOF

cat > "$FIX/bugs/valid-flagged-doc.md" <<'EOF'
---
title: Flagged bug doc with empty track values
date: 2026-08-11
problem_type: bug
module: tests
tags: [fixture, migrated]
symptoms: intermittent failure
root_cause:
resolution:
needs_review: true
---
Body.
EOF

VIOLATIONS="$(validate_store "$FIX")"
assert_contains "$VIOLATIONS" "unknown problem_type 'banana'" \
  "validator rejects unknown problem_type"
assert_contains "$VIOLATIONS" "bug track missing root_cause" \
  "validator rejects bug doc missing a track-required field"
assert_contains "$VIOLATIONS" "knowledge track missing applies_when" \
  "validator rejects knowledge doc missing applies_when"
assert_contains "$VIOLATIONS" "date in filename" \
  "validator rejects a date in the filename"
assert_not_contains "$VIOLATIONS" "valid-doc.md" \
  "validator passes a valid knowledge doc"
assert_not_contains "$VIOLATIONS" "valid-flagged-doc.md" \
  "validator passes a needs_review doc with empty track values"

# --- Enum sync: script CATEGORY_MAP <-> this validator <-> README -----------
# The problem_type -> category enum exists in three places (the migration
# script's CATEGORY_MAP, the case statement above, tasks/solutions/README.md).
# Anchor on the script's map: every pair it defines must validate here and be
# documented in the README, so drift in any copy fails this file.
ENUM_PAIRS="$(sed -n '/^CATEGORY_MAP = {/,/^}/p' scripts/migrate-learning-store.py \
  | grep -oE '"[a-z-]+": "[a-z-]+"' | tr -d '"' | sed 's/: / /')"
assert_eq "11" "$(printf '%s\n' "$ENUM_PAIRS" | grep -c .)" \
  "enum sync: extracted the CATEGORY_MAP pairs from the migration script"
while read -r pt cat; do
  [ -n "$pt" ] || continue
  mkdir -p "$FIX/$cat"
  cat > "$FIX/$cat/enum-probe-$pt.md" <<EOF
---
title: Enum probe for $pt
date: 2026-08-11
problem_type: $pt
module: tests
tags: [fixture]
symptoms: probe
root_cause: probe
resolution: probe
applies_when: probe
---
Body.
EOF
  probe="$(validate_doc "$FIX/$cat/enum-probe-$pt.md")"
  assert_eq "" "$probe" \
    "enum sync: validator accepts script pair '$pt -> $cat/' (violations: ${probe:-none})"
  assert_file_contains tasks/solutions/README.md "| \`$pt\` |" \
    "enum sync: README documents problem_type '$pt'"
done <<ENUM_EOF
$ENUM_PAIRS
ENUM_EOF

# --- Overlap dimensions: one set per track, the same in every copy ----------
# /learn Step 4 scores a candidate on its own track's dimensions (#168): the
# bug set alone left a knowledge-track document unable to reach High. The
# store README and its project-template seed restate both rows verbatim.
BUG_DIMS='| bug | problem, root cause, solution, files touched, prevention rule |'
KNOWLEDGE_DIMS='| knowledge | situation (`applies_when`), claim, files or module, rule, consequence |'
CROSS_TRACK_CAP="on the other track scores Moderate at most"
for f in .agents/skills/learn/SKILL.md tasks/solutions/README.md \
         project-template/tasks/solutions/README.md; do
  assert_file_contains "$f" "$BUG_DIMS" "overlap dimensions: $f carries the bug-track set"
  assert_file_contains "$f" "$KNOWLEDGE_DIMS" "overlap dimensions: $f carries the knowledge-track set"
  assert_prose_contains "$f" "the five dimensions of the candidate's track" \
    "overlap dimensions: $f scores a candidate on its own track's set"
  assert_prose_contains "$f" "$CROSS_TRACK_CAP" \
    "overlap dimensions: $f caps a cross-track match at Moderate"
done
# /memory-maintain's merge test points at Step 4 for the rows, but states the
# cap as its reason a cross-track pair never merges, so it carries this copy too.
assert_prose_contains .agents/skills/memory-maintain/SKILL.md "$CROSS_TRACK_CAP" \
  "overlap dimensions: memory-maintain's merge test states Step 4's cross-track cap"

# --- Real store: every document in tasks/solutions/ must validate -----------
if [ -d tasks/solutions ]; then
  REAL="$(validate_store "$STORE")"
  assert_eq "" "$REAL" "real store documents all validate (violations: ${REAL:-none})"
  assert_file_contains tasks/solutions/README.md "problem_type" \
    "store README documents the schema"
fi

finish
