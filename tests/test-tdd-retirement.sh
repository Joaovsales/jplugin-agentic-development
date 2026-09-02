# tests/test-tdd-retirement.sh — /tdd folded into /build, then retired.
#
# WHY THIS EXISTS
#
# /build never delegated to /tdd; it reimplemented the loop, so the two trees
# held duplicate TDD doctrine and neither called the other. README even drew a
# `delegates to` edge that no line of build/SKILL.md implemented.
#
# Retirement follows the precedent set by `simplify` and `deslop`, which became
# `/quality-gate` Phase 1 and Phase 2: fold the content in, keep the label, then
# delete the skill. The hazard being pinned here is the other kind of retirement
# — deleting the file and losing what only it carried. /tdd held the entire
# anti-rationalization doctrine, and a learning document cites it by line.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")" && cd .. && pwd)"
cd "$REPO"

TREES=".agents .claude"

# ── The doctrine survived the fold ───────────────────────────────────────────
for tree in $TREES; do
  f="$tree/skills/build/SKILL.md"
  assert_file_contains "$f" "Tests-after" \
    "Fold: $tree/build carries the tests-after rule"
  assert_file_contains "$f" "Test written after implementation" \
    "Fold: $tree/build carries the TDD red flags"
  assert_file_matches "$f" '\| *Excuse *\|' \
    "Fold: $tree/build carries the rationalization table"
  assert_file_contains "$f" "testing-anti-patterns.md" \
    "Fold: $tree/build links the testing anti-patterns reference"
  assert_file_contains "$tree/skills/build/references/testing-anti-patterns.md" "mock" \
    "Fold: $tree/build/references/testing-anti-patterns.md exists"
done

# ── The escape hatch died with the file, and was not relocated ───────────────
# tdd/SKILL.md:129 was the repo's only written authorization to commit code
# without wrap-up ("Run /wrap-up-session **or at minimum** ... Commit"). The
# whole wrap-up gate is pointless if this survives anywhere.
hits="$(grep -rn "or at minimum" --include='*.md' \
        .agents .claude CLAUDE.md README.md project-template 2>/dev/null || true)"
assert_eq "" "$hits" "Retire: no 'or at minimum' commit escape hatch anywhere"

# ── Every reference repointed ────────────────────────────────────────────────
for tree in $TREES; do
  assert_file_not_matches "$tree/skills/plan/SKILL.md" '/tdd' \
    "Repoint: $tree/plan hands off to /build, not /tdd"
  assert_file_not_matches "$tree/skills/prd/SKILL.md" '/tdd' \
    "Repoint: $tree/prd no longer names /tdd"
  assert_file_not_matches "$tree/skills/brainstorm/SKILL.md" '/tdd' \
    "Repoint: $tree/brainstorm no longer names /tdd"
  assert_file_not_matches "$tree/skills/auto-push/SKILL.md" '/tdd' \
    "Repoint: $tree/auto-push no longer routes to /tdd"
done

assert_file_contains "project-template/tasks/todo.md" "executed by \`/build\`" \
  "Repoint: shipped project template names /build"
assert_file_not_matches "project-template/tasks/todo.md" '/tdd' \
  "Repoint: shipped project template no longer names /tdd"

assert_file_not_matches "README.md" 'delegates to.*\n?.*/tdd' \
  "Repoint: README has no delegates-to-/tdd diagram edge"
assert_file_not_matches "README.md" '\| `/tdd`' \
  "Repoint: README skills table has no /tdd row"
assert_file_not_matches "CLAUDE.md" '\| `/tdd`' \
  "Repoint: CLAUDE.md skills table has no /tdd row"
assert_file_not_matches ".claude/hooks/session-start.sh" '/tdd' \
  "Repoint: session-start banner no longer lists /tdd"

# ── The learning document still points at something real ─────────────────────
# tasks/solutions/architecture/tdd-enforcement.md cited tdd/SKILL.md by line
# number. Deleting the file without repointing orphans the learning.
LEARN="tasks/solutions/architecture/tdd-enforcement.md"
assert_file_not_matches "$LEARN" 'skills/tdd' \
  "Learning: tdd-enforcement.md no longer cites the retired skill"
assert_file_contains "$LEARN" "skills/build" \
  "Learning: tdd-enforcement.md cites /build instead"

# ── The skill is gone from both trees ────────────────────────────────────────
for tree in $TREES; do
  if [ -e "$tree/skills/tdd" ]; then
    assert_eq "removed" "present" "Retire: $tree/skills/tdd removed"
  else
    assert_eq "removed" "removed" "Retire: $tree/skills/tdd removed"
  fi
done

# ── /sync retires it downstream ──────────────────────────────────────────────
# A downstream project that already installed /tdd keeps the stale copy — and
# with it the escape hatch — unless /sync is told to remove it.
for tree in $TREES; do
  assert_file_contains "$tree/skills/sync/SKILL.md" "tdd" \
    "Retire: $tree/sync lists tdd among retired skills to remove"
done

finish
