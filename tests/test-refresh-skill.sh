# tests/test-refresh-skill.sh — P3 /refresh skill exists in the canonical tree.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

A=".agents/skills/refresh/SKILL.md"

for f in "$A"; do
  assert_eq "true" "$([ -f "$f" ] && echo true || echo false)" "P3: $f exists"
  assert_file_contains "$f" "name: refresh" "P3: $f frontmatter name: refresh"
  assert_file_contains "$f" "Snapshot working state" "P3: $f has snapshot step"
  assert_file_contains "$f" "pre-compact.sh" "P3: $f reuses shared flush"
  assert_file_contains "$f" "resume from disk" "P3: $f has handoff/resume instruction"
done

finish
