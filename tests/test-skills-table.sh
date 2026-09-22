#!/bin/bash
# tests/test-skills-table.sh — the README skills table is generated from the
# skill frontmatter by scripts/render-skills-table.py, and `--check` is the drift
# test (specs/single-instruction-file.md slice 6). A row added or edited by hand
# fails here until the frontmatter says the same.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
GEN="$REPO/scripts/render-skills-table.py"

run_gen() { PYTHONDONTWRITEBYTECODE=1 "$TEST_PYTHON" "$GEN" "$@"; }

# ── HEAD is current ───────────────────────────────────────────────────────────
out="$(run_gen --check 2>&1)"; code=$?
assert_eq "0" "$code" "--check: exits 0 on HEAD — README.md carries the table rendered from .agents/skills/*/SKILL.md"
assert_eq "" "$out" "--check: silent when the table is current (failure-only, like the sweeps that run it)"
assert_eq "1" "$(grep -c '^<!-- skills-table:begin -->$' README.md)" "README: one begin marker"
assert_eq "1" "$(grep -c '^<!-- skills-table:end -->$' README.md)" "README: one end marker"
for dir in .agents/skills/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  name="$(grep -m1 '^name:' "$dir/SKILL.md" | sed 's/^name:[[:space:]]*//')"
  assert_file_matches README.md "^\\| \`/$name\` \\|" "README: a row for /$name"
done
assert_file_matches README.md '^\| `/setup-deployment` \| .* \| claude \|' \
  "README: a claude-only skill carries its harness in the third column"
assert_file_matches README.md '^\| `/build` \| .* \|  \|' \
  "README: a universal skill leaves the harness cell blank"

# ── Fixture repository: two skills copied from the tree ──────────────────────
box="$(mktemp -d)"
mkdir -p "$box/.agents/skills"
cp README.md "$box/README.md"
cp -r .agents/skills/build .agents/skills/plan "$box/.agents/skills/"
run_gen --repo "$box" > "$box/render.log" 2>&1
assert_eq "0" "$?" "fixture: rendering exits 0"
assert_contains "$(cat "$box/render.log")" "rewritten" "fixture: the rewrite is reported"
assert_file_matches "$box/README.md" '^\| `/build` \|' "fixture: the build row is rendered"
assert_file_matches "$box/README.md" '^\| `/plan` \|' "fixture: the plan row is rendered"
assert_file_not_matches "$box/README.md" '^\| `/tidy` \|' \
  "fixture: rows come from the fixture's skills, not this checkout's"
assert_eq "$(sed -n '/^## Philosophy/,$p' README.md)" "$(sed -n '/^## Philosophy/,$p' "$box/README.md")" \
  "fixture: everything outside the markers is untouched"
run_gen --repo "$box" --check > /dev/null 2>&1
assert_eq "0" "$?" "fixture: --check exits 0 right after a rewrite"

# A row removed by hand: exit 1, the diff names the row, nothing is written.
sed -i '/^| `\/plan` |/d' "$box/README.md"
out="$(run_gen --repo "$box" --check 2>&1)"; code=$?
assert_eq "1" "$code" "removed row: --check exits 1"
assert_contains "$out" '+| `/plan`' "removed row: the unified diff shows the row that is missing"
assert_contains "$out" '--- README.md' "removed row: the diff names README.md"
assert_file_not_matches "$box/README.md" '^\| `/plan` \|' "removed row: --check writes nothing"

# Non-universal harness → third column; universal → blank.
mkdir -p "$box/.agents/skills/only-claude"
printf -- '---\nname: only-claude\ndescription: Needs the Claude Code runtime.\nharness: claude\n---\n# x\n' \
  > "$box/.agents/skills/only-claude/SKILL.md"
run_gen --repo "$box" > /dev/null 2>&1
assert_file_matches "$box/README.md" '^\| `/only-claude` \| Needs the Claude Code runtime\. \| claude \|' \
  "harness: a non-universal harness fills the third column"
assert_file_matches "$box/README.md" '^\| `/build` \| .* \|  \|' \
  "harness: universal leaves the third column blank"

# Exit 2 names the directory; nothing is written.
cp "$box/README.md" "$box/README.before"
mkdir -p "$box/.agents/skills/nodesc"
printf -- '---\nname: nodesc\n---\n# nodesc\n' > "$box/.agents/skills/nodesc/SKILL.md"
out="$(run_gen --repo "$box" 2>&1)"; code=$?
assert_eq "2" "$code" "missing description: exits 2"
assert_contains "$out" "nodesc" "missing description: the message names the skill directory"
assert_contains "$out" "description" "missing description: the message names the missing field"
assert_files_identical "$box/README.before" "$box/README.md" "missing description: README is not written"
rm -rf "$box/.agents/skills/nodesc"

# A `|` in a description is escaped so the row keeps its three cells.
mkdir -p "$box/.agents/skills/pipey"
printf -- '---\nname: pipey\ndescription: Renders a | b as one cell.\n---\n# x\n' > "$box/.agents/skills/pipey/SKILL.md"
run_gen --repo "$box" > /dev/null 2>&1
assert_file_matches "$box/README.md" '^\| `/pipey` \| Renders a \\| b as one cell\. \|  \|' \
  "pipe: a | in the description is escaped"
rm -rf "$box/.agents/skills/pipey"

# A CRLF README round-trips: every line still ends in CR after a rewrite.
run_gen --repo "$box" > /dev/null 2>&1
sed 's/\r$//; s/$/\r/' "$box/README.md" > "$box/README.crlf" && mv "$box/README.crlf" "$box/README.md"
mkdir -p "$box/.agents/skills/zz-crlf"
printf -- '---\nname: zz-crlf\ndescription: Added under CRLF.\n---\n# x\n' > "$box/.agents/skills/zz-crlf/SKILL.md"
run_gen --repo "$box" > /dev/null 2>&1
assert_eq "0" "$(grep -c -v $'\r$' "$box/README.md")" "crlf: no line lost its CR after a rewrite"
assert_file_contains "$box/README.md" "/zz-crlf" "crlf: the new row was written"
rm -rf "$box/.agents/skills/zz-crlf"
sed 's/\r$//' "$box/README.md" > "$box/README.lf" && mv "$box/README.lf" "$box/README.md"

# A SKILL.md that is not UTF-8, or has no frontmatter, is refused by directory name.
cp "$box/README.md" "$box/README.before"
mkdir -p "$box/.agents/skills/latin1"
printf -- '---\nname: latin1\ndescription: caf\351\n---\n' > "$box/.agents/skills/latin1/SKILL.md"
out="$(run_gen --repo "$box" 2>&1)"; code=$?
assert_eq "2" "$code" "not utf-8: exits 2"
assert_contains "$out" "latin1: SKILL.md is not UTF-8" "not utf-8: the message names the directory"
assert_not_contains "$out" "Traceback" "not utf-8: no traceback"
rm -rf "$box/.agents/skills/latin1"
mkdir -p "$box/.agents/skills/nofm"
printf '# no frontmatter here\n' > "$box/.agents/skills/nofm/SKILL.md"
out="$(run_gen --repo "$box" 2>&1)"; code=$?
assert_eq "2" "$code" "no frontmatter: exits 2"
assert_contains "$out" "nofm: SKILL.md has no frontmatter" "no frontmatter: the message names the directory"
rm -rf "$box/.agents/skills/nofm"
assert_files_identical "$box/README.before" "$box/README.md" "refusals: README is not written"

# Exit 2 on a second marker pair.
printf '\n<!-- skills-table:begin -->\n<!-- skills-table:end -->\n' >> "$box/README.md"
out="$(run_gen --repo "$box" --check 2>&1)"; code=$?
assert_eq "2" "$code" "two marker pairs: exits 2"
assert_contains "$out" "exactly once" "two marker pairs: the message says the pair must appear exactly once"
cp "$box/README.before" "$box/README.md"

# Exit 2 on a README without the marker pair.
grep -v 'skills-table:' "$box/README.md" > "$box/README.nomarkers" && mv "$box/README.nomarkers" "$box/README.md"
out="$(run_gen --repo "$box" --check 2>&1)"; code=$?
assert_eq "2" "$code" "missing markers: exits 2"
assert_contains "$out" "skills-table:begin" "missing markers: the message names the marker pair"

rm -rf "$box"
finish
