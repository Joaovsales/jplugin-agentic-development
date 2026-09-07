#!/bin/bash
# tests/test-sweep-routines.sh — the two producer routines and the /sweep skill.
#
# specs/sweep-routines.md AC1, AC3, AC5, AC6, AC7, AC8, AC9, AC10. Every routine
# in the contract was a CONSUMER: it selected an issue by kind label and ended at
# a PR that closed it. Nothing PRODUCED issues -- the closest thing, the retired
# unattended discover-and-fix skill, sank its findings into tasks/backlog.md
# (downstream PR #407: 15 findings, zero issues). `janitor` and `architect` are
# producers: read the backlog, run an engine, file verified findings through the
# registry, commit a session record, hand off to /wrap-up-session.
#
# These are static assertions over both skill trees. AC2 (the Python surface)
# lives in test-routine-branch.sh / test-routine-selectors.sh; AC4 (the handoff
# schema) lives in test-sweep-handoff.sh.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TREES=".agents .claude"
WRAP=".agents/skills/wrap-up-session"
CONTRACT="$WRAP/references/routines.md"
PROMPTS="$WRAP/references/routine-prompts"

# ============================================================================
# AC1 — the contract carries both producers
# ============================================================================
for routine in janitor architect; do
  assert_file_matches "$CONTRACT" "^\| \`$routine\` \|" \
    "AC1: routine \`$routine\` has a row in the routine table"
  assert_file_matches "$CONTRACT" "^### .$routine. — steps" \
    "AC1: $routine has a step section of its own"
done

assert_file_matches "$CONTRACT" '^### (The )?[Pp]roducer spine' \
  "AC1: the producer spine is stated once, in its own section"
producer_spine="$(awk '/^### (The )?[Pp]roducer spine/{f=1;next} f&&/^### /{exit} f' "$CONTRACT")"
assert_contains "$producer_spine" "task-registry doctor" \
  "AC1: producer step 1 is task-registry doctor"
assert_contains "$producer_spine" "routine_branch.py format" \
  "AC1: producer step 2 creates the branch through the shared formatter"
assert_contains "$producer_spine" "/sweep --routine" \
  "AC1: producer step 3 is /sweep --routine <name>"
assert_contains "$producer_spine" "/wrap-up-session" \
  "AC1: producer step 4 reaches /wrap-up-session"
sweep_gate="$(printf '%s\n' "$producer_spine" | grep -E '^\| 3 \|.*/sweep' || true)"
assert_contains "$sweep_gate" "non-skippable" \
  "AC1: the /sweep step is non-skippable"
wrap_gate="$(printf '%s\n' "$producer_spine" | grep -E '^\| 4 \|.*/wrap-up-session' || true)"
assert_contains "$wrap_gate" "non-skippable" \
  "AC1: the producer's /wrap-up-session step is non-skippable"
producer_rows="$(printf '%s\n' "$producer_spine" | grep -cE '^\| [0-9]+ \|' || true)"
assert_eq "4" "$producer_rows" "AC1: the producer spine has exactly four steps"

assert_prose_contains "$CONTRACT" "never edit product code" \
  "AC1: the contract states that producers never edit product code"
assert_prose_contains "$CONTRACT" "run stamp" \
  "AC1: the producer branch number is described as a run stamp, not an issue"

# ============================================================================
# AC3 — /sweep and its two lens files, byte-identical in both trees
# ============================================================================
for f in SKILL.md references/lens-janitor.md references/lens-architect.md; do
  assert_files_identical ".agents/skills/sweep/$f" ".claude/skills/sweep/$f" \
    "AC3: sweep/$f ships byte-identically to the .claude parity copy"
done

SWEEP=".agents/skills/sweep/SKILL.md"
assert_file_contains "$SWEEP" "task-registry doctor" \
  "AC3: /sweep names task-registry doctor"
assert_file_contains "$SWEEP" "/task-registry" \
  "AC3: /sweep reads the backlog through /task-registry"
assert_file_not_matches "$SWEEP" "gh issue" \
  "AC3: /sweep never calls gh issue"
assert_file_contains "$SWEEP" "upsert --apply" \
  "AC3: /sweep files through task-registry upsert --apply"
for flag in --reproduction --proposed-fix --criterion --evidence --summary --derive-id --source --fold-title; do
  assert_file_contains "$SWEEP" "$flag" "AC3: /sweep passes $flag"
done
# Every subcommand the skill names must exist: `task-registry sync` once did not.
commands="$(python3 -c '
import re, pathlib
src = pathlib.Path(".agents/skills/task-registry/scripts/task-registry.py").read_text()
print(" ".join(re.findall(r"\"([a-z]+)\"", re.search(r"COMMANDS = \((.*?)\)", src, re.S).group(1))))
')"
for sub in $(grep -oE 'task-registry [a-z]+' "$SWEEP" | awk '{print $2}' | sort -u); do
  case " $commands " in
    *" $sub "*) assert_eq "$sub" "$sub" "AC3: /sweep names a real subcommand: $sub" ;;
    *) assert_eq "one of: $commands" "$sub" "AC3: /sweep names a real subcommand: $sub" ;;
  esac
done
assert_file_contains "$SWEEP" "--kind bug" \
  "AC3: janitor findings file as --kind bug"
assert_file_contains "$SWEEP" "--kind task --label tech-debt" \
  "AC3: architect findings file as --kind task --label tech-debt"
assert_file_contains "$SWEEP" "--kind decision" \
  "AC3: a design choice files as --kind decision"
assert_prose_contains "$SWEEP" "MUST-FIX" "AC3: /sweep maps MUST-FIX"
assert_file_contains "$SWEEP" "--label now" "AC3: MUST-FIX maps to --label now"
assert_file_contains "$SWEEP" "--label next" "AC3: SHOULD-FIX maps to --label next"
assert_prose_contains "$SWEEP" "publication pending" \
  "AC3: /sweep states the destination table's pending-publication outcome"
assert_prose_contains "$SWEEP" "require_write_approval = false" \
  "AC3: /sweep names the first write switch"
assert_prose_contains "$SWEEP" "TASK_REGISTRY_TRUSTED_CONFIG=1" \
  "AC3: /sweep names the second write switch"
assert_prose_contains "$SWEEP" "never pauses" \
  "AC3: pending publication never pauses the run"
assert_prose_contains "$SWEEP" "STOP" \
  "AC3: a failed local write STOPs the run"
assert_file_contains "$SWEEP" "tasks/sweeps/" \
  "AC3: /sweep writes the session record under tasks/sweeps/"
for section in Scope "Coverage gaps" Filed Unverified Independence "Step ledger"; do
  assert_file_contains "$SWEEP" "$section" \
    "AC3: the session record has a $section section"
done
assert_file_contains "$SWEEP" "Refs #" "AC3: the PR body carries Refs # per filed issue"
assert_file_contains "$SWEEP" "chore(sweep):" "AC3: the PR title format is stated"
assert_prose_contains "$SWEEP" "single witness" \
  "AC3: the run states every finding has a single witness"
assert_prose_contains "$SWEEP" "No sub-agent" \
  "AC3: /sweep dispatches no sub-agent"
assert_file_contains "$SWEEP" "references/lens-janitor.md" \
  "AC3: /sweep points at the janitor lens"
assert_file_contains "$SWEEP" "references/lens-architect.md" \
  "AC3: /sweep points at the architect lens"
assert_file_contains ".agents/skills/sweep/references/lens-janitor.md" \
  "/maintain-verification-skill" "AC3: the janitor lens names its engine"
assert_file_contains ".agents/skills/sweep/references/lens-architect.md" \
  "--scope tree" "AC3: the architect lens names its engine scope"

# ============================================================================
# AC5 — /debug consumer intake
# ============================================================================
for tree in $TREES; do
  f="$tree/skills/debug/SKILL.md"
  assert_file_contains "$f" "task-registry show" \
    "AC5: $tree/debug reads an issue reference through task-registry show"
  assert_prose_contains "$f" "candidate one" \
    "AC5: $tree/debug enters the proposed fix as candidate one"
  assert_file_contains "$f" "blocked: reproduction failed" \
    "AC5: $tree/debug emits the unattended blocked line"
  assert_prose_contains "$f" "non-zero" \
    "AC5: $tree/debug exits non-zero when blocked"
  assert_file_contains "$f" "[ ] TDD:" \
    "AC5: $tree/debug writes TDD tasks from the issue's proposed fix and criteria"
done
fix_section="$(awk 'index($0, "### `fix` — steps") == 1 {found=1; next} found && /^### / {exit} found {print}' "$CONTRACT")"
assert_contains "$fix_section" "/debug #N" \
  "AC5: the fix routine's step 4a reads /debug #N"

# ============================================================================
# AC6 — engine amendments
# ============================================================================
for tree in $TREES; do
  mvs="$tree/skills/maintain-verification-skill/SKILL.md"
  assert_prose_contains "$mvs" "inline" \
    "AC6: $tree/maintain-verification-skill runs the source wave inline when dispatch is unavailable"
  assert_prose_contains "$mvs" "lost corroboration" \
    "AC6: $tree/maintain-verification-skill states the lost corroboration"
  assert_file_contains "$mvs" "/sweep" \
    "AC6: $tree/maintain-verification-skill defers shipping to /sweep"
  sder="$tree/skills/software-design-expert-review/SKILL.md"
  assert_file_contains "$sder" "--scope tree" \
    "AC6: $tree/software-design-expert-review documents --scope tree"
  assert_prose_contains "$sder" "single batch — no promotion available" \
    "AC6: $tree/software-design-expert-review reports the inline fallback as a single batch"
done

# ============================================================================
# AC7 — wrap-up's linkage table has the producer row
# ============================================================================
for tree in $TREES; do
  w="$tree/skills/wrap-up-session/SKILL.md"
  assert_file_matches "$w" '^\| `routine/(janitor|architect|\(janitor\|architect\))/' \
    "AC7: $tree/wrap-up-session linkage table has a producer row"
  assert_file_contains "$w" "chore(sweep):" \
    "AC7: $tree/wrap-up-session states the producer PR title format"
  assert_prose_contains "$w" "run stamp" \
    "AC7: $tree/wrap-up-session says the producer branch number is a run stamp"
done

# ============================================================================
# AC8 — five routine prompts, each short and project-agnostic
# ============================================================================
declare -A PROMPT_SKILL=([janitor]="/sweep" [architect]="/sweep" [fix]="/debug" [improve]="/plan" [plan]="/plan")
for name in janitor architect fix improve plan; do
  p="$PROMPTS/$name.md"
  assert_eq "present" "$([ -f "$p" ] && echo present || echo missing)" \
    "AC8: routine prompt $name.md exists"
  lines="$(wc -l < "$p" 2>/dev/null || echo 999)"
  assert_eq "under" "$([ "$lines" -lt 25 ] && echo under || echo "over ($lines)")" \
    "AC8: $name.md is under 25 lines"
  assert_file_contains "$p" "${PROMPT_SKILL[$name]}" \
    "AC8: $name.md names the skill it invokes"
  assert_file_contains "$p" "$name" "AC8: $name.md names its routine"
  assert_prose_contains "$p" "sub-agent" \
    "AC8: $name.md says sub-agent dispatch is not required"
  assert_file_not_matches "$p" 'jplugin|agentic-development|github\.com/' \
    "AC8: $name.md carries no repository name"
  assert_files_identical "$p" ".claude/skills/wrap-up-session/references/routine-prompts/$name.md" \
    "AC8: $name.md ships byte-identically to the .claude parity copy"
done
readme="$PROMPTS/README.md"
assert_prose_contains "$readme" "Planner" "AC8: the README states the producer tier"
assert_prose_contains "$readme" "Builder" "AC8: the README states the consumer tier"
assert_prose_contains "$readme" "weekly" "AC8: the README suggests a producer cadence"
assert_prose_contains "$readme" "daily" "AC8: the README suggests a consumer cadence"
assert_prose_contains "$readme" "require_write_approval = false" \
  "AC8: the README checklist names the first write switch"
assert_prose_contains "$readme" "TASK_REGISTRY_TRUSTED_CONFIG=1" \
  "AC8: the README checklist names the second write switch"
assert_file_contains "$readme" "gh" "AC8: the README checklist requires an authenticated gh"
assert_file_contains "$readme" "allow_label_creation" \
  "AC8: the README checklist covers pre-existing labels"
assert_file_contains "$readme" "verify-<app>" \
  "AC8: the README checklist covers janitor's app launch prerequisite"

# ============================================================================
# AC9 — the retired skill is gone from everything outside tasks/ and specs/
# ============================================================================
# The needle is BUILT at runtime rather than written literally so this file does
# not match its own sweep -- see
# tasks/solutions/patterns/construct-retired-paths-at-runtime-to-keep-literal-sweeps-strict.md
retired="auto""-improve"
# `--` must come last: it ends option parsing, so an --exclude-dir after it is a
# (nonexistent) file operand and the sweep silently loses its exclusions.
hits="$(grep -rlF \
  --exclude-dir=.git --exclude-dir=tasks --exclude-dir=specs \
  --exclude-dir=node_modules --exclude-dir=worktrees --exclude-dir=graphify-out \
  -- "$retired" . 2>/dev/null || true)"
assert_eq "" "$hits" \
  "AC9: no file outside tasks/ and specs/ mentions the retired skill (offenders: ${hits:-none})"
for tree in $TREES; do
  assert_eq "absent" "$([ -e "$tree/skills/$retired" ] && echo present || echo absent)" \
    "AC9: $tree/skills/$retired is deleted"
done
assert_eq "absent" "$([ -e "tests/test-$retired-rewire.sh" ] && echo present || echo absent)" \
  "AC9: the retired skill's rewire test is deleted"

survey="$(awk '/repo-survey dispatch has no session/{f=1} f{print} f&&/^$/{exit}' CLAUDE.md)"
assert_contains "$survey" "/sweep" \
  "AC9: CLAUDE.md's repo-survey exception names /sweep"
assert_file_matches CLAUDE.md '^\| `/sweep' \
  "AC9: CLAUDE.md's skills table lists /sweep"
assert_file_matches README.md '^\| `/sweep' \
  "AC9: README.md's skills table lists /sweep"
assert_file_contains .claude/hooks/session-start.sh "/sweep" \
  "AC9: session-start.sh lists /sweep"

# ============================================================================
# AC10 — configuration.md has the unattended-routines checklist
# ============================================================================
CONF=".agents/skills/task-registry/references/configuration.md"
assert_file_matches "$CONF" '^## Unattended routines' \
  "AC10: configuration.md has an Unattended routines section"
unattended="$(awk '/^## Unattended routines/{f=1;next} f&&/^## /{exit} f' "$CONF")"
assert_contains "$unattended" "require_write_approval = false" \
  "AC10: the section names the first write switch"
assert_contains "$unattended" "TASK_REGISTRY_TRUSTED_CONFIG=1" \
  "AC10: the section names the second write switch"
assert_contains "$unattended" "gh" "AC10: the section names gh"
assert_contains "$unattended" "allow_label_creation" \
  "AC10: the section names allow_label_creation"
assert_files_identical "$CONF" ".claude/skills/task-registry/references/configuration.md" \
  "AC10: configuration.md ships byte-identically to the .claude parity copy"

finish
