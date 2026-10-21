# tests/test-tdd-retirement.sh — one home for the TDD rules.
#
# WHY THIS EXISTS
#
# The first /tdd drifted: /build reimplemented the loop, so two trees held
# duplicate doctrine and neither called the other. /tdd was then folded into
# /build § TDD Discipline and deleted. That left /debug and the lanes to restate
# the rules, the same duplication one level up. specs/aposd-first-build.md (D2,
# D12) re-creates /tdd as the only definition and makes /build call it.
#
# This is an invariant test, not a history test: whatever else changes, the
# red-flags list, the rationalization table and Prove-It live only in
# .agents/skills/tdd/SKILL.md, /build invokes /tdd, and the "or at minimum"
# commit escape — the repo's one written authorization to commit without
# wrap-up — appears nowhere.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")" && cd .. && pwd)"
cd "$REPO"

TDD=".agents/skills/tdd/SKILL.md"
BUILD=".agents/skills/build/SKILL.md"

# ── The doctrine lives in /tdd ───────────────────────────────────────────────
assert_file_matches "$TDD" '^name: tdd$' "Home: tdd/SKILL.md is the skill named tdd"
assert_file_contains "$TDD" "Test written after implementation" \
  "Home: /tdd carries the red-flags list"
assert_file_matches "$TDD" '\| *Excuse *\|' \
  "Home: /tdd carries the rationalization table"
assert_file_contains "$TDD" "Prove-It" "Home: /tdd carries Prove-It"
assert_file_contains "$TDD" "testing-anti-patterns.md" \
  "Home: /tdd links the testing anti-patterns reference"
assert_file_contains ".agents/skills/tdd/references/testing-anti-patterns.md" "mock" \
  "Home: tdd/references/testing-anti-patterns.md exists"
assert_eq "gone" "$([ -e .agents/skills/build/references/testing-anti-patterns.md ] && echo present || echo gone)" \
  "Home: the anti-pattern reference moved out of build/references"

# ── ... and only there ───────────────────────────────────────────────────────
# Scoped to the skills and agents the rules could leak into. /debug is held to
# the same rule once it calls /tdd (specs/aposd-first-build.md slice 7); today
# it restates neither phrase, so it is already covered.
for phrase in "Test written after implementation" "Too simple to test" \
              "Rationalizing \"just this once\"" "Tests-after"; do
  hits="$(grep -rlF "$phrase" --include='*.md' .agents .claude/agents 2>/dev/null \
          | grep -v '^\.agents/skills/tdd/' || true)"
  assert_eq "" "$hits" "Only: '$phrase' appears only under tdd/"
done
assert_file_not_matches "$BUILD" '\| *Excuse *\|' "Only: /build carries no rationalization table"
assert_file_not_matches "$BUILD" '^#+ *TDD Discipline' "Only: /build has no TDD Discipline section"

# ── /build calls /tdd ────────────────────────────────────────────────────────
assert_prose_contains "$BUILD" 'through `/tdd`: failing test first, then minimal implementation, then refactor' \
  "Call: /build delegates each acceptance criterion to /tdd"

# ── /debug runs its fix rows through /tdd; no writer emits a TDD: row ────────
assert_prose_contains ".agents/skills/debug/SKILL.md" '`/debug` then runs the rows through `/tdd` itself' \
  "Debug: /debug runs the fix rows through /tdd itself"
assert_prose_contains ".agents/skills/task-registry/lanes/fix.md" 'run the fix through `/tdd`' \
  "Writers: the fix lane says /debug runs the fix through /tdd"
assert_file_contains ".agents/skills/debug/SKILL.md" "- [ ] <criterion" \
  "Debug: /debug writes plain criterion rows"
hits="$(grep -rlF 'TDD:' .agents/skills/debug .agents/skills/task-registry/lanes \
        .agents/skills/wrap-up-session/references/routine-prompts \
        .agents/agents/planner.md .claude/agents/planner.md 2>/dev/null || true)"
assert_eq "" "$hits" "Writers: no lane, routine prompt, planner or /debug names a TDD: row"
for f in .agents/skills/wrap-up-session/references/routine-prompts/fix.md \
         .agents/agents/planner.md .claude/agents/planner.md; do
  assert_file_contains "$f" "/tdd" "Writers: $f says the fix runs through /tdd"
done

# ── The escape hatch is nowhere ──────────────────────────────────────────────
# .claude/worktrees/ holds other checkouts (git-excluded, frozen at older
# commits), not this tree, so it is skipped.
hits="$(grep -rn "or at minimum" --exclude-dir=worktrees --include='*.md' \
        .agents .claude CLAUDE.md AGENTS.md README.md project-template 2>/dev/null || true)"
assert_eq "" "$hits" "Escape: no 'or at minimum' commit escape hatch anywhere"

# ── Other entry points still hand off to /build, not /tdd ────────────────────
assert_file_not_matches ".agents/skills/plan/SKILL.md" '/tdd' \
  "Repoint: plan hands off to /build, not /tdd"
assert_file_not_matches ".agents/skills/prd/SKILL.md" '/tdd' \
  "Repoint: prd no longer names /tdd"
assert_file_not_matches ".agents/skills/brainstorm/SKILL.md" '/tdd' \
  "Repoint: brainstorm no longer names /tdd"
assert_file_not_matches ".agents/skills/auto-push/SKILL.md" '/tdd' \
  "Repoint: auto-push no longer routes to /tdd"
assert_file_contains "project-template/tasks/todo.md" "executed by \`/build\`" \
  "Repoint: shipped project template names /build"
assert_file_not_matches "project-template/tasks/todo.md" '/tdd' \
  "Repoint: shipped project template no longer names /tdd"
assert_file_not_matches ".agents/hooks/session-start.sh" '/tdd' \
  "Repoint: session-start banner does not list /tdd"

# ── The catalog lists it ─────────────────────────────────────────────────────
assert_file_matches "README.md" '^\| `/tdd` \|' "Catalog: README skills table has a /tdd row"

# ── /sync does not retire the re-created skill (R4) ──────────────────────────
# Retirement deletes only a file byte-identical to something the template once
# shipped at that path. The new tdd/SKILL.md must differ from every historic one.
# A shallow clone cannot answer, so it is skipped rather than guessed.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  assert_eq "skipped" "skipped" "Retire: shallow clone — history check skipped"
elif [ -z "$(git log --all --diff-filter=D --format=%H -1 -- "$TDD")" ]; then
  assert_eq "skipped" "skipped" "Retire: no deletion commit in history — history check skipped"
else
  # Only copies shipped before the retirement count: the commit that re-created
  # the file is not history, and the live file always matches itself.
  del="$(git log --all --diff-filter=D --format=%H -1 -- "$TDD")"
  cur="$(git hash-object "$TDD")"
  old="$(git log "$del" --format=%H -- "$TDD" | while read -r c; do
           git rev-parse -q --verify "$c:$TDD" 2>/dev/null
           git rev-parse -q --verify "$c^:$TDD" 2>/dev/null
         done | sort -u | grep -Fx "$cur" || true)"
  assert_eq "" "$old" "Retire: tdd/SKILL.md is not byte-identical to any historic copy"
fi
assert_file_not_matches ".agents/skills/sync/SKILL.md" '`tdd` is the live' \
  "Retire: /sync no longer cites tdd as the retired example"
assert_file_not_matches ".agents/skills/sync/SKILL.md" '`tdd` → ' \
  "Retire: /sync no longer maps tdd as retired content"

finish
