#!/bin/bash
# tests/test-skill-frontmatter.sh — frontmatter validity across the skill tree.
#
# A skill whose frontmatter is malformed does not fail loudly: the harness either
# skips it or registers it under the wrong name, and the only symptom is that
# `/skill-name` silently does nothing. These are the invariants that make a skill
# discoverable at all:
#
#   1. SKILL.md exists in every skill directory
#   2. It opens with a `---` frontmatter block on line 1
#   3. `name:` is present
#   4. `name:` matches the directory name — the directory is what the user types,
#      so a mismatch registers the skill under a name nobody will guess
#   5. `description:` is present — it is the model's only signal for auto-invocation
#   6. `description:` stays within the 1024-char skill-spec cap
#
# Excludes .claude/worktrees/, which holds full copies of the tree.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

DESC_MAX=1024

# Read every frontmatter fact in ONE awk pass — three lines: has-block, name,
# description length. One subprocess per skill rather than one per key: on Windows
# process spawn dominates this guard's runtime, and 54 skills x 3 spawns was slow
# enough to push `tests/run.sh` past a two-minute timeout.
#
# Frontmatter is the block between the leading `---` on line 1 and the next `---`;
# a key outside that block is body text and must not count as frontmatter.
scan_frontmatter() {
  awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; has = 1; next }
    fm && /^---[[:space:]]*$/ { fm = 0; next }
    fm && index($0, "name:") == 1 {
      v = substr($0, 6); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v); name = v; next
    }
    fm && index($0, "description:") == 1 {
      v = substr($0, 13); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v); desc = v; dlen = length(v); next
    }
    END { print (has ? "yes" : "no"); print name; print dlen + 0 }
  ' "$1"
}

for tree in .agents/skills; do
  [ -d "$tree" ] || continue
  for dir in "$tree"/*/; do
    [ -d "$dir" ] || continue
    skill="$(basename "$dir")"
    md="$dir/SKILL.md"

    if [ ! -f "$md" ]; then
      _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
      printf '  FAIL Frontmatter: %s has no SKILL.md\n' "$dir"
      continue
    fi

    { read -r has_fm; read -r name; read -r desc_len; } <<EOF
$(scan_frontmatter "$md")
EOF

    assert_eq "yes" "$has_fm" "Frontmatter: $tree/$skill opens with a --- block"
    assert_eq "$skill" "$name" "Frontmatter: $tree/$skill name matches its directory"

    if [ "${desc_len:-0}" -gt 0 ]; then
      assert_eq "present" "present" "Frontmatter: $tree/$skill has a description"
      if [ "$desc_len" -le "$DESC_MAX" ]; then
        assert_eq "within" "within" "Frontmatter: $tree/$skill description <= $DESC_MAX chars"
      else
        _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
        printf '  FAIL Frontmatter: %s/%s description is %s chars (max %s)\n' \
          "$tree" "$skill" "$desc_len" "$DESC_MAX"
      fi
    else
      _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
      printf '  FAIL Frontmatter: %s/%s has no description\n' "$tree" "$skill"
    fi
  done
done

finish
