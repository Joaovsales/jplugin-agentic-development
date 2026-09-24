#!/bin/bash
# tests/test-go-lanes.sh — /go consults the lane catalogue and carries no lanes
# of its own.
#
# /go (specs/go-front-door.md, superseded in part by specs/lane-catalogue.md) is
# a prose router: it reads a goal, picks a lane from the catalogue the registry
# ships, prints a [ROUTE] line, and runs the skills the lane's steps name. The
# lanes themselves are pinned by tests/test-lane-catalogue.sh; this test pins the
# skill's side of the contract — that it reaches the catalogue through the two
# registry commands, restates no lane table, and that no routine host invokes it.
# A green run means the skill is written down and consistent, not that an agent
# obeyed it; the behavioural half is the recorded live run in tasks/e2e-log.md.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TREES=".agents"
LANES_DIR=".agents/skills/task-registry/lanes"

# Every `/skill` token in a file, first appearance first, one per line. A slash
# preceded by a path character (`tasks/todo.md`, `.agents/skills/go`) is a path
# segment, not a skill, and is excluded by the leading class.
skill_tokens() {
  tr -d '\r' < "$1" \
    | grep -oE '(^|[[:space:]`(,;])/[a-z][a-z0-9-]*' \
    | sed 's/^[^/]*//' \
    | awk '!seen[$0]++'
}

# --- AC1: the skill and its contract ------------------------------------------
for tree in $TREES; do
  f="$tree/skills/go/SKILL.md"
  assert_eq "present" "$([ -f "$f" ] && echo present || echo missing)" \
    "GoLanes: $f exists"
  assert_file_contains "$f" '[ROUTE] lane=<lane> | chain=<skill, skill, ...> | reason: <one sentence>' \
    "GoLanes: $f states the [ROUTE] emission format"
  assert_prose_contains "$f" '`fix` outranks `perf`, `perf` outranks `refactor`' \
    "GoLanes: $f states the precedence rule"
  assert_prose_contains "$f" '`investigate` is decided first' \
    "GoLanes: $f decides investigate before the change lanes"
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
  # Both registry commands: the deterministic router for an issue reference, the
  # catalogue for everything else. The registry wins wherever its fact exists.
  assert_file_contains "$f" "task-registry.py workflow" \
    "GoLanes: $f consults the registry for an issue reference"
  assert_file_contains "$f" "task-registry.py lanes" \
    "GoLanes: $f reads the lane catalogue through the registry"
  assert_file_contains "$f" "task-registry.py lanes <lane>" \
    "GoLanes: $f fetches the chosen lane's playbook by name"
  assert_prose_contains "$f" "never routed around" \
    "GoLanes: $f refuses a misconfigured tracker"
  assert_prose_contains "$f" 'under `.agents/skills/`' \
    "GoLanes: $f resolves chains against the canonical skill root"
  assert_prose_contains "$f" "<ref>" \
    "GoLanes: $f substitutes <ref> when recording a lane's steps"
  # No lane of its own. A table row here would be a second statement of a lane
  # the catalogue already defines — the drift specs/lane-catalogue.md removed.
  assert_file_not_matches "$f" '^\| `[a-z]+` \|' \
    "GoLanes: $f carries no lane table"
  assert_file_not_matches "$f" 'lanes/[a-z]+\.md' \
    "GoLanes: $f names no playbook file of its own"
  assert_file_not_matches "$f" 'TODO\(shortcut\)' \
    "GoLanes: $f carries no TODO(shortcut) — the catalogue was the upgrade path"
  assert_eq "absent" "$([ -d "$tree/skills/go/lanes" ] && echo present || echo absent)" \
    "GoLanes: $tree/skills/go/lanes/ no longer exists"
done

# --- AC1: every /skill the skill names is on disk ------------------------------
for tree in $TREES; do
  f="$tree/skills/go/SKILL.md"
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

# --- AC7: the interactive lanes /go picks reach a human gate before /build -----
# /plan asks "Confirm with 'y'"; /debug's prelude stops before any edit. Nothing
# else in these chains asks, so one of them must come first. The lane files are
# the registry's, pinned in full by tests/test-lane-catalogue.sh; this is the one
# property /go's own contract depends on.
for lane in fix improve refactor perf babysit; do
  f="$LANES_DIR/$lane.md"
  [ -f "$f" ] || { assert_eq "present" "missing" "GoLanes: $f exists"; continue; }
  flat="$(flatten "$f")"
  gate='/plan'
  pos_plan="$(first_pos "$flat" '/plan')"
  pos_debug="$(first_pos "$flat" '/debug')"
  if [ -n "$pos_debug" ] && { [ -z "$pos_plan" ] || [ "$pos_debug" -lt "$pos_plan" ]; }; then
    gate='/debug'
  fi
  assert_precedes "$flat" "$gate" '/build' "GoLanes: $f names /plan or /debug before /build"
done
assert_file_not_matches "$LANES_DIR/investigate.md" '/wrap-up-session' \
  "GoLanes: investigate never names /wrap-up-session"

# --- AC3: no routine host invokes /go ------------------------------------------
# The routine contract chooses the lane from the label; there is no prompt to
# match. The session-start hook lists no skills since the plugin took over
# (#156), so the hook root is swept like every other host: zero mentions.
GO_INVOCATION='(^|[^A-Za-z0-9_/.-])/go([^A-Za-z0-9_/-]|$)'
HOST_ROOTS=".agents/skills/sweep .agents/skills/tidy .agents/skills/yolo .agents/skills/auto-push
  .agents/skills/wrap-up-session/references .agents/skills/task-registry/lanes
  .agents/hooks"
# A negative sweep passes on nothing if a root moved or the regex is dead, so
# every root is asserted present and the skill's own file is the positive
# control: the same regex must hit it before the sweep's empty result counts.
for root in $HOST_ROOTS; do
  assert_eq "present" "$([ -d "$root" ] && echo present || echo missing)" \
    "GoLanes: host sweep root $root exists"
done
assert_eq "yes" "$(grep -qE "$GO_INVOCATION" .agents/skills/go/SKILL.md && echo yes || echo no)" \
  "GoLanes: host sweep regex matches /go in the skill's own file (positive control)"
host_hits="$(grep -rnE "$GO_INVOCATION" $HOST_ROOTS || true)"
assert_eq "" "$host_hits" \
  "GoLanes: no routine host, lane file, or hook invokes /go (offenders: ${host_hits:-none})"

finish
