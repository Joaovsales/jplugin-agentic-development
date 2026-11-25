#!/bin/bash
# tests/test-sync-keep.sh — .claude/sync-keep means "the project owns this path"
# for overwrite (/sync Step 5, via `sync-retire.py --keep-filter`) as well as
# retirement. One matcher serves both; the session-start drift check is covered
# in tests/test-session-start.sh.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RETIRE="$(under_test .agents/skills/sync/scripts/sync-retire.py)"

P="$(fixture_repo)"
mkdir -p "$P/.claude"
printf '%s\n' '# project-owned' '.agents/skills/verify-evidence/scripts/visual_check.py' '.agents/skills/mine/**' > "$P/.claude/sync-keep"

filter() { run sh -c "printf '%s\n' \"\$@\" | \"$TEST_PYTHON\" \"$RETIRE\" --repo \"$P\" --keep-filter" _ "$@"; }

filter .agents/skills/verify-evidence/scripts/visual_check.py .agents/skills/build/SKILL.md .agents/skills/mine/a/b.md
assert_exit 0 "keep-filter: exits 0"
assert_contains "$output" "kept	.agents/skills/verify-evidence/scripts/visual_check.py" "keep-filter: an exact kept path is marked kept"
assert_contains "$output" "kept	.agents/skills/mine/a/b.md" "keep-filter: ** crosses directories"
assert_contains "$output" "sync	.agents/skills/build/SKILL.md" "keep-filter: an unmatched template file stays open to sync"

# No file: nothing is kept.
rm "$P/.claude/sync-keep"
filter .agents/skills/build/SKILL.md
assert_contains "$output" "sync	.agents/skills/build/SKILL.md" "keep-filter: no sync-keep keeps nothing"

# A malformed line is a loud failure, never a silent "kept nothing".
printf '%s\n' '.agents/skills/[ab]/x' > "$P/.claude/sync-keep"
filter .agents/skills/build/SKILL.md
assert_exit 1 "keep-filter: an unsupported glob refuses"
assert_contains "$output" "unsupported glob" "keep-filter: names the problem"

# Retirement: a kept path that still exists upstream is a live entry, and the
# retire set is unchanged.
T="$(fixture_dir)"
mkdir -p "$T/.agents/skills/sync" "$T/.agents/skills/verify-evidence/scripts" "$P/.agents/skills/verify-evidence/scripts" "$P/.agents/skills/gone"
cp "$REPO/.agents/skills/sync/SKILL.md" "$T/.agents/skills/sync/SKILL.md"
echo upstream > "$T/.agents/skills/verify-evidence/scripts/visual_check.py"
# One file under every other syncable root, or the script refuses the source as incomplete.
for root in .agents/agents .agents/git-hooks .agents/hooks .agents/references .claude/agents .claude/browsers; do
  mkdir -p "$T/$root"; echo x > "$T/$root/f"
done
echo custom > "$P/.agents/skills/verify-evidence/scripts/visual_check.py"
echo retired > "$P/.agents/skills/gone/SKILL.md"
printf '%s\n' '.agents/skills/verify-evidence/scripts/visual_check.py' > "$P/.claude/sync-keep"
git -C "$P" add -A; git -C "$P" -c user.name=t -c user.email=t@example.com commit -qm fx
run "$TEST_PYTHON" "$RETIRE" --repo "$P" --from-dir "$T"
assert_exit 0 "retire: dry run succeeds"
assert_not_contains "$output" "unmatched" "retire: a kept path that exists upstream is not reported unmatched"
assert_contains "$output" "retire: .agents/skills/gone/SKILL.md" "retire: the retirement set is unchanged"
assert_not_contains "$output" "retire: .agents/skills/verify-evidence" "retire: a kept path is never retired"

finish
