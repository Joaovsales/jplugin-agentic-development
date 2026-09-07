#!/bin/bash
# tests/test-routine-skills.sh — a routine's skill chain is configuration, not code.
#
# specs/workflow-routing.md AC4, AC5, AC8, AC9, AC12. The `workflow` command's
# whole output is "which routine, and what does it run" — the second half of that
# answer has to come from somewhere, and hardcoding it in the CLI would put the
# one thing a project most wants to change (#107 asks for exactly this) behind a
# code edit.
#
# Four properties are pinned here, each silent if unchecked:
#   1. a project with no `[routines.skills]` still gets working chains, and they
#      are the ones `references/routines.md` states — that document is the
#      routine contract and six test files assert its contents
#   2. a declared chain naming a skill that is not on disk is refused NAMING IT,
#      not discovered at spine step 4 with the claim label already written
#   3. every chain ends at `/wrap-up-session`, the review gate whose omission
#      shipped #93 green
#   4. `[routines.skills]` replaces WHOLESALE, matching `[routines.selectors]`.
#      That is only safe because a selector without a chain is refused, so both
#      halves are pinned together — dropping either one lets a project silently
#      lose a routine.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SCRIPTS="$REPO/.agents/skills/task-registry/scripts"
PY=python3

TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

pyreg() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" -; }

# A project root carrying a skills tree, so the on-disk check has something to
# read. Named skills exist; anything else deliberately does not.
new_fixture() {
  local d name
  d="$(mktemp -d "${TMPDIR:-/tmp}/routine-skills.XXXXXX")"
  TMP_DIRS+=("$d")
  mkdir -p "$d/tasks" "$d/docs"
  printf '[ ] placeholder\n' > "$d/tasks/todo.md"
  for name in "$@"; do
    mkdir -p "$d/.agents/skills/$name"
    printf -- '---\nname: %s\n---\n' "$name" > "$d/.agents/skills/$name/SKILL.md"
  done
  printf '%s' "$d"
}

# $1 = project root, $2 = kind_precedence covering exactly the selected labels.
# Declaring it is not incidental: `_refuse_divergent_label_sets` already refuses a
# chain whose domain differs from the selector union, and leaving the shipped
# five-label default in place would refuse every fixture below for THAT reason —
# turning each new gate's test green without the gate existing.
write_config() {
  { printf '# Task tracking\n\n```ini\n[tracker]\nprovider = local\n'
    printf '\n[routines]\nkind_precedence = %s\n' "$2"
    cat
    printf '```\n'
  } > "$1/docs/task-tracking.md"
}

# Loads the config and prints either the chains or the refusal, so every
# assertion below reads one channel.
#
# `refusal_of` narrows that to the refusal LINE. Asserting a skill or routine
# name against the whole report would also match the success output, where the
# loaded chain prints the same name -- so deleting the gate under test would
# leave the assertion green. Empty output fails `assert_contains` by
# construction, so a load that did not refuse cannot pass silently.
load_report() {
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" - "$1" <<'PY'
import sys
from registry.config import ConfigError, load_config

try:
    config = load_config(sys.argv[1], env={})
except ConfigError as exc:
    print("REFUSED:", exc)
    sys.exit(0)
for routine in sorted(config.routine_skills):
    print(f"chain {routine}: {' -> '.join(config.routine_skills[routine])}")
print("routines:", ",".join(sorted(config.routine_skills)))
PY
}

refusal_of() { load_report "$1" | grep '^REFUSED:' || true; }

# ============================================================================
# 1. The shipped default — chains without configuration, matching the contract
# ============================================================================
printf '\n-- shipped defaults --\n'
bare="$(new_fixture)"
defaults="$(load_report "$bare")"

assert_contains "$defaults" "routines: build,fix,improve,plan" \
  "default: all four contract routines ship a chain, including deferred build"
assert_contains "$defaults" "chain plan: /plan -> /wrap-up-session" \
  "AC12: plan's default chain is references/routines.md step 4 + the spine's step 5"
assert_contains "$defaults" "chain fix: /debug -> /build -> /quality-gate -> /wrap-up-session" \
  "AC12: fix's default chain is routines.md steps 4a-4c + step 5"
assert_contains "$defaults" "chain improve: /plan -> /build -> /quality-gate -> /wrap-up-session" \
  "AC12: improve's default chain is routines.md steps 4a-4c + step 5"
assert_contains "$defaults" "chain build: /build -> /quality-gate -> /wrap-up-session" \
  "AC12: build's default chain reads a merged spec rather than writing one"
assert_not_contains "$defaults" "chain plan: /plan -> /build" \
  "plan's chain omits /build — routines.md calls it deliberately absent"

# The defaults name skills that must actually exist in THIS template. Declared
# chains are checked against the project's own disk (AC4 below); the shipped
# defaults are checked here, so neither layer is unverified.
missing_default_skills="$(pyreg <<'PY'
import os
from registry.config import DEFAULT_ROUTINE_SKILLS

missing = [
    skill
    for chain in DEFAULT_ROUTINE_SKILLS.values()
    for skill in chain
    if not os.path.isfile(os.path.join(".agents/skills", skill.lstrip("/"), "SKILL.md"))
]
print("missing:", ", ".join(sorted(set(missing))) or "none")
PY
)"
assert_contains "$missing_default_skills" "missing: none" \
  "AC4 (default layer): every skill a shipped chain names exists in this template"

# A project that HAS a configuration file but declares no `[routines.skills]`
# reaches validation carrying the shipped defaults. It must still load with no
# skills tree of its own: the registry is installable without the rest of the
# harness, and refusing there would take every command down over chains the
# project never wrote. The bare fixture above cannot pin this -- with no config
# file at all, `load_config` returns before any validator runs.
printf '\n-- defaults are not held against a project that declared none --\n'
undeclared="$(new_fixture)"
write_config "$undeclared" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision
INI
undeclared_out="$(load_report "$undeclared")"
assert_contains "$undeclared_out" "chain fix: /debug -> /build -> /quality-gate -> /wrap-up-session" \
  "AC4 scope: a configured project with no [routines.skills] keeps the defaults"
assert_not_contains "$undeclared_out" "REFUSED:" \
  "AC4 scope: shipped defaults are not checked against a project with no skills tree"

# ============================================================================
# 2. AC4 — a declared chain naming a skill absent from disk is refused, naming it
# ============================================================================
printf '\n-- AC4: unknown skill --\n'
ghost="$(new_fixture plan debug build quality-gate wrap-up-session)"
write_config "$ghost" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /summon-the-kraken, /wrap-up-session
INI
ghost_out="$(load_report "$ghost")"
ghost_refusal="$(refusal_of "$ghost")"

assert_contains "$ghost_out" "REFUSED:" \
  "AC4: a chain naming a skill that is not on disk is refused at load"
assert_contains "$ghost_refusal" "/summon-the-kraken" \
  "AC4: the refusal names the missing skill, not just the routine"
assert_contains "$ghost_refusal" "plan" \
  "AC4: the refusal names the routine whose chain is broken"

# The same chain with every skill present must load, or the assertion above
# would pass for a project that simply cannot load any configuration.
printf '\n-- AC4 control: same shape, skill present --\n'
present="$(new_fixture plan debug build quality-gate wrap-up-session summon-the-kraken)"
write_config "$present" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /summon-the-kraken, /wrap-up-session
INI
present_out="$(load_report "$present")"
assert_contains "$present_out" "chain plan: /plan -> /summon-the-kraken -> /wrap-up-session" \
  "AC4 control: the identical chain loads once the skill exists on disk"

# `.claude/skills/` satisfies the check too — the two trees are pinned
# byte-identical, and a project that carries only the Claude Code copy is
# correctly configured, not broken.
printf '\n-- AC4: .claude/skills counts as on disk --\n'
claude_only="$(mktemp -d "${TMPDIR:-/tmp}/routine-skills.XXXXXX")"
TMP_DIRS+=("$claude_only")
mkdir -p "$claude_only/tasks" "$claude_only/docs"
printf '[ ] placeholder\n' > "$claude_only/tasks/todo.md"
for name in plan wrap-up-session; do
  mkdir -p "$claude_only/.claude/skills/$name"
  printf -- '---\nname: %s\n---\n' "$name" > "$claude_only/.claude/skills/$name/SKILL.md"
done
write_config "$claude_only" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /wrap-up-session
INI
assert_contains "$(load_report "$claude_only")" "chain plan: /plan -> /wrap-up-session" \
  "AC4: a skill present only in .claude/skills/ satisfies the on-disk check"

# ============================================================================
# 3. AC5 — every chain ends at /wrap-up-session
# ============================================================================
printf '\n-- AC5: terminal step --\n'
unterminated="$(new_fixture plan build wrap-up-session)"
write_config "$unterminated" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /build
INI
unterminated_out="$(load_report "$unterminated")"
unterminated_refusal="$(refusal_of "$unterminated")"

assert_contains "$unterminated_out" "REFUSED:" \
  "AC5: a chain not ending at /wrap-up-session is refused"
assert_contains "$unterminated_refusal" "/wrap-up-session" \
  "AC5: the refusal names the step that must terminate the chain"
assert_contains "$unterminated_refusal" "plan" \
  "AC5: the refusal names the offending routine"

# /wrap-up-session present but not last is still a refusal: the gate has to be
# terminal, not merely mentioned.
printf '\n-- AC5: present but not last --\n'
midchain="$(new_fixture plan build wrap-up-session)"
write_config "$midchain" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /wrap-up-session, /build
INI
assert_contains "$(load_report "$midchain")" "REFUSED:" \
  "AC5: /wrap-up-session in the middle of a chain does not satisfy the gate"

# ============================================================================
# 4. AC8 — [routines.skills] replaces wholesale, it does not merge per key
# ============================================================================
printf '\n-- AC8: wholesale replace --\n'
sole="$(new_fixture plan wrap-up-session)"
write_config "$sole" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /wrap-up-session
INI
sole_out="$(load_report "$sole")"

assert_contains "$sole_out" "routines: plan" \
  "AC8: declaring one chain replaces the whole map — fix/improve/build do not survive"
assert_not_contains "$sole_out" "chain fix:" \
  "AC8: the shipped fix chain is not merged in beside the declared one"
assert_not_contains "$sole_out" "chain build:" \
  "AC8: the shipped build chain is not merged in beside the declared one"

# ============================================================================
# 5. AC9 — a routine with a selector and no chain is refused, naming it
# ============================================================================
printf '\n-- AC9: selector without chain --\n'
orphan="$(new_fixture plan debug build quality-gate wrap-up-session)"
write_config "$orphan" "bug, design-decision, tech-debt" <<'INI'
[routines.selectors]
plan = design-decision
fix = bug, tech-debt

[routines.skills]
plan = /plan, /wrap-up-session
INI
orphan_out="$(load_report "$orphan")"
orphan_refusal="$(refusal_of "$orphan")"

assert_contains "$orphan_out" "REFUSED:" \
  "AC9: a wholesale replace that drops a selected routine's chain is refused"
assert_contains "$orphan_refusal" "fix" \
  "AC9: the refusal names the routine left without a chain"

# The reverse is legal and must stay legal: `build` ships a chain and no
# selector, because it is deferred behind #97/#98. AC9 is one-directional.
printf '\n-- AC9 is one-directional --\n'
chain_only="$(new_fixture plan build quality-gate wrap-up-session)"
write_config "$chain_only" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /wrap-up-session
build = /build, /quality-gate, /wrap-up-session
INI
assert_contains "$(load_report "$chain_only")" "chain build: /build -> /quality-gate -> /wrap-up-session" \
  "AC9: a chain with no selector is legal — deferred build ships exactly that way"

# ============================================================================
# 6. AC12 — reconfiguring an EXISTING routine is one file and no code
# ============================================================================
printf '\n-- AC12: reconfigure without code --\n'
recfg="$(new_fixture debug build quality-gate wrap-up-session auto-improve)"
write_config "$recfg" "bug, tech-debt" <<'INI'
[routines.selectors]
fix = bug, tech-debt

[routines.skills]
fix = /auto-improve, /build, /wrap-up-session
INI
assert_contains "$(load_report "$recfg")" "chain fix: /auto-improve -> /build -> /wrap-up-session" \
  "AC12: an existing routine's chain changes by editing one file and no code"

# Inventing a routine name stays a deliberate contract edit — AC12 is scoped to
# reconfiguring an existing one, and CONTRACT_ROUTINES is explicitly kept.
printf '\n-- AC12: inventing a routine is still refused --\n'
invented="$(new_fixture plan wrap-up-session)"
write_config "$invented" "design-decision, question" <<'INI'
[routines.selectors]
plan = design-decision
triage = question

[routines.skills]
plan = /plan, /wrap-up-session
triage = /plan, /wrap-up-session
INI
invented_out="$(load_report "$invented")"
invented_refusal="$(refusal_of "$invented")"
assert_contains "$invented_out" "REFUSED:" \
  "AC12: a routine outside CONTRACT_ROUTINES is still refused"
assert_contains "$invented_refusal" "triage" \
  "AC12: the refusal names the invented routine"

finish
