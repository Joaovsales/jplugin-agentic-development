#!/bin/bash
# tests/test-go-lanes.sh — /go's lanes are written down, name only skills that
# exist, and agree with the registry on the one lane they share.
#
# /go (specs/go-front-door.md) is a prose router: it reads a goal, picks a lane
# playbook, prints a [ROUTE] line, and runs the skills the playbook names. Every
# part of that contract is markdown, so this test pins the smallest units that
# would fail on the regressing change — file set, tokens, order — in the
# tradition of tests/test-model-tiers.sh and tests/test-skill-invocation-chain.sh.
# A green run means the lanes exist and are internally consistent, not that an
# agent obeyed them; the behavioural half is the recorded live run and the
# triggerability eval in tasks/e2e-log.md.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TREES=".agents .claude"
LANES="investigate fix refactor perf babysit"

# One flattening pipeline for every whole-file order check below. CRLF-safe:
# these files are checked out with CRLF on Windows.
flatten() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; }

# Every `/skill` token in a file, first appearance first, one per line. A slash
# preceded by a path character (`tasks/todo.md`, `.agents/skills/go`) is a path
# segment, not a skill, and is excluded by the leading class.
skill_tokens() {
  tr -d '\r' < "$1" \
    | grep -oE '(^|[[:space:]`(,;])/[a-z][a-z0-9-]*' \
    | sed 's/^[^/]*//' \
    | awk '!seen[$0]++'
}

# Byte offset of the first occurrence of a literal in a flattened file, or
# empty when absent. Used for the "gate before /build" order pins.
first_pos() { printf '%s' "$1" | grep -bo -- "$2" | head -1 | cut -d: -f1; }

# --- AC1: the skill and its contract ------------------------------------------
for tree in $TREES; do
  f="$tree/skills/go/SKILL.md"
  assert_eq "present" "$([ -f "$f" ] && echo present || echo missing)" \
    "GoLanes: $f exists"
  # The [ROUTE] emission format, the lane table, the precedence rule, and the
  # one iron law. Tokens, not prose.
  assert_file_contains "$f" '[ROUTE] lane=<lane> | chain=<skill, skill, ...> | reason: <one sentence>' \
    "GoLanes: $f states the [ROUTE] emission format"
  for lane in $LANES feature none; do
    assert_file_matches "$f" "^\| \`$lane\` \|" \
      "GoLanes: $f lane table has a \`$lane\` row"
  done
  assert_prose_contains "$f" '`fix` outranks `perf`, `perf` outranks `refactor`' \
    "GoLanes: $f states the precedence rule"
  assert_file_contains "$f" "## The Iron Law" \
    "GoLanes: $f carries one iron law"
  assert_prose_contains "$f" "NOTHING HAPPENS BEFORE THE [ROUTE] LINE" \
    "GoLanes: $f iron law forbids action before the route"
  assert_prose_contains "$f" "/go ITSELF NEVER ASKS THE HUMAN A QUESTION" \
    "GoLanes: $f iron law forbids /go asking its own question"
  # The record shape: plain numbered lines, never the checkbox rows /build runs.
  assert_file_contains "$f" "## Lane: " \
    "GoLanes: $f names the lane block heading"
  assert_prose_contains "$f" "Never checkbox rows" \
    "GoLanes: $f forbids checkbox rows in the lane block"
  # The registry wins wherever its fact exists.
  assert_file_contains "$f" "task-registry.py workflow" \
    "GoLanes: $f consults the registry for an issue reference"
done

# --- AC2: five playbooks, free markdown, no frontmatter ------------------------
for tree in $TREES; do
  for lane in $LANES; do
    f="$tree/skills/go/lanes/$lane.md"
    assert_eq "present" "$([ -f "$f" ] && echo present || echo missing)" \
      "GoLanes: $f exists"
    [ -f "$f" ] || continue
    assert_eq "no" "$(head -1 "$f" | tr -d '\r' | grep -q '^---' && echo yes || echo no)" \
      "GoLanes: $f has no frontmatter"
    assert_file_matches "$f" "^# " "GoLanes: $f opens with a heading"
    assert_file_matches "$f" "^1\. " "GoLanes: $f has numbered steps"
    assert_file_matches "$f" "^## Reply" "GoLanes: $f has a Reply section"
    # No row in a playbook may be a checkbox: steps are copied verbatim into
    # tasks/todo.md, and /build executes every `[ ]` row it finds there.
    assert_file_not_matches "$f" '^[[:space:]]*\[[ ~x]\]' \
      "GoLanes: $f has no checkbox rows"
  done
done

# --- AC2/AC3: every /skill a playbook or the skill names is on disk ------------
# Resolved against the canonical tree for both copies: a playbook in .claude/
# naming a skill only .claude/ has would be a parity failure, not a resolution.
for tree in $TREES; do
  for f in "$tree/skills/go/SKILL.md" "$tree"/skills/go/lanes/*.md; do
    [ -f "$f" ] || continue
    tokens="$(skill_tokens "$f")"
    assert_eq "yes" "$([ -n "$tokens" ] && echo yes || echo no)" \
      "GoLanes: $f names at least one skill (extractor is not a no-op)"
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      assert_eq "present" "$([ -f ".agents/skills/${tok#/}/SKILL.md" ] && echo present || echo missing)" \
        "GoLanes: $f names $tok and .agents/skills/${tok#/}/SKILL.md exists"
    done <<EOF
$tokens
EOF
  done
done

# --- AC3: fix.md is the registry's fix chain, verbatim and in order ------------
# The two routers share exactly one lane. Read the registry's value rather than
# restating it here, so a chain edit in config.py fails this test instead of
# drifting past it. `-B` keeps the probe from writing __pycache__ into the
# canonical tree, which tests/test-skill-parity.sh would report as drift.
expected_fix="$(PYTHONDONTWRITEBYTECODE=1 python3 -B -c '
import sys
sys.path.insert(0, ".agents/skills/task-registry/scripts")
from registry.config import DEFAULT_ROUTINE_SKILLS
print(" ".join(DEFAULT_ROUTINE_SKILLS["fix"]))
' 2>/dev/null || true)"
assert_eq "yes" "$([ -n "$expected_fix" ] && echo yes || echo no)" \
  "GoLanes: DEFAULT_ROUTINE_SKILLS[\"fix\"] read from config.py"
for tree in $TREES; do
  f="$tree/skills/go/lanes/fix.md"
  [ -f "$f" ] || continue
  actual_fix="$(skill_tokens "$f" | paste -sd' ' -)"
  assert_eq "$expected_fix" "$actual_fix" \
    "GoLanes: $f skill tokens, first appearance order, equal the registry's fix chain"
done

# --- AC3: investigate ends with an answer, never a wrap-up ---------------------
for tree in $TREES; do
  assert_file_not_matches "$tree/skills/go/lanes/investigate.md" '/wrap-up-session' \
    "GoLanes: $tree investigate.md never names /wrap-up-session"
done

# --- AC3: refactor and babysit reach a human gate before /build ----------------
# /plan asks "Confirm with 'y'"; /debug's prelude stops before any edit. Nothing
# else in either chain asks, so one of them must come first.
for tree in $TREES; do
  for lane in refactor babysit; do
    f="$tree/skills/go/lanes/$lane.md"
    [ -f "$f" ] || continue
    flat="$(flatten "$f")"
    pos_build="$(first_pos "$flat" '/build')"
    pos_plan="$(first_pos "$flat" '/plan')"
    pos_debug="$(first_pos "$flat" '/debug')"
    gate=""
    for p in $pos_plan $pos_debug; do
      [ -z "$gate" ] || [ "$p" -lt "$gate" ] && gate="$p"
    done
    if [ -n "$pos_build" ] && [ -n "$gate" ] && [ "$gate" -lt "$pos_build" ]; then
      assert_eq "ordered" "ordered" "GoLanes: $f names /plan or /debug before /build"
    else
      assert_eq "gate < /build" "gate=${gate:-missing} build=${pos_build:-missing}" \
        "GoLanes: $f names /plan or /debug before /build"
    fi
  done
done

# --- AC3: no routine host invokes /go ------------------------------------------
# The routine contract chooses the chain from the label; there is no prompt to
# match. The two session-start banner lines are the only allowed mentions,
# matched by their exact text so a third line cannot hide behind them.
# `tidy` joined the producer routines after the spec listed its roots; a host
# added later is still a host, so it is swept too.
BANNER_ROW='/go <goal>   — Natural-language front door: pick a lane, print [ROUTE], run its skills'
BANNER_CLOSE='Ready. Use /go <goal> to start, or continue from tasks/todo.md.'
host_hits="$(grep -rnE '(^|[^A-Za-z0-9_/.-])/go([^A-Za-z0-9_/-]|$)' \
    .agents/skills/sweep .agents/skills/tidy .agents/skills/yolo .agents/skills/auto-push \
    .agents/skills/wrap-up-session/references \
    .claude/skills/sweep .claude/skills/tidy .claude/skills/yolo .claude/skills/auto-push \
    .claude/skills/wrap-up-session/references \
    .claude/hooks 2>/dev/null \
  | grep -vF "$BANNER_ROW" | grep -vF "$BANNER_CLOSE" || true)"
assert_eq "" "$host_hits" \
  "GoLanes: no routine host or hook invokes /go (offenders: ${host_hits:-none})"

# --- AC5: the banner leads with /go and closes on it ---------------------------
first_skill_row="$(grep -E '^echo "  /' .claude/hooks/session-start.sh | head -1)"
assert_contains "$first_skill_row" "/go <goal>" \
  "GoLanes: session-start banner lists /go first in the skills block"
assert_file_contains .claude/hooks/session-start.sh "$BANNER_CLOSE" \
  "GoLanes: session-start banner closes on /go"

finish
