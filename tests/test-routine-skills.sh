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
# Whether the project DECLARED the section, not merely whether the resulting
# chains happen to match. A project whose chains equal the shipped defaults --
# this repository's do -- is otherwise indistinguishable from one that declared
# nothing, so every assertion about the file being read would pass with the
# section deleted.
print("declared:", config.routine_skills_declared)
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
assert_contains "$defaults" "declared: False" \
  "default: an unconfigured project is recorded as having declared nothing"
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

# A skill reference is a directory NAME, not a path. The name comes from a file
# in the repository — the same untrusted input class the task-tracking pointer is
# confined for — and without a shape check the probe reads
# `<root>/.agents/skills/../../../etc/SKILL.md`: an existence oracle for
# arbitrary paths that answers False for the wrong reason.
#
# Asserting the refusal alone proves nothing: a hostile step is refused anyway
# because nothing exists where it points, so the assertion holds with the shape
# check deleted. Each case below therefore CREATES the file the unguarded probe
# would find — `<root>/.agents/skills/<hostile>/SKILL.md` after the OS resolves
# it — so refusing and traversing give different answers, and only the guard
# produces this one.
printf '\n-- AC4: a chain step may not be a path --\n'
for hostile in "/../../etc" "/../wrap-up-session" "/.." "/nested/name"; do
  trav="$(new_fixture plan wrap-up-session)"
  # The literal, unnormalized path config.py probes. Creating it is what makes
  # the assertion below falsifiable.
  bait="$trav/.agents/skills/${hostile#/}/SKILL.md"
  mkdir -p "$(dirname "$bait")"
  printf -- '---\nname: bait\n---\n' > "$bait"
  [ -f "$bait" ] || { printf 'FIXTURE BROKEN: no bait at %s\n' "$bait"; exit 1; }
  write_config "$trav" "design-decision" <<INI
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, $hostile, /wrap-up-session
INI
  trav_refusal="$(refusal_of "$trav")"
  assert_contains "$trav_refusal" "not skill" \
    "AC4: a chain step is refused for its SHAPE, though the path it names exists ($hostile)"
  # "not installed" would send the reader to check their install for a step no
  # install could ever satisfy.
  assert_not_contains "$trav_refusal" "not installed" \
    "AC4: the refusal names the shape, not a missing installation ($hostile)"
done

# A step that IS a name and simply is not installed keeps the other message, so
# the pair above is pinned on the shape rule rather than on any refusal at all.
absent="$(new_fixture plan wrap-up-session)"
write_config "$absent" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /never-installed, /wrap-up-session
INI
assert_contains "$(refusal_of "$absent")" "not installed" \
  "AC4: a well-formed step that is absent from disk is refused for BEING absent"

# An empty chain is a declaration, not an absence. Dropping the key made
# `plan =` indistinguishable from a project that never mentioned plan.
empty_chain="$(new_fixture plan wrap-up-session)"
write_config "$empty_chain" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan =
INI
empty_refusal="$(refusal_of "$empty_chain")"
assert_contains "$empty_refusal" "plan is empty" \
  "AC5: a declared-but-empty chain is refused by name, not silently dropped"

# A step that renders as an installed skill without being one. `/build` here
# carries a Cyrillic 'е'; a reviewer reading the file cannot see the difference.
homoglyph="$(new_fixture plan wrap-up-session)"
write_config "$homoglyph" "design-decision" <<INI
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /build, /wrap-up-session
INI
# Written through sed because a literal in this file is invisible to a reader.
sed -i 's|/build|/buil\xd0\xb5|' "$homoglyph/docs/task-tracking.md"
assert_file_not_matches "$homoglyph/docs/task-tracking.md" '/build,' \
  "Fixture: the ASCII /build really was replaced — otherwise the next assertion is vacuous"
assert_contains "$(refusal_of "$homoglyph")" "not skill" \
  "AC4: a non-ASCII step is refused for its shape — it is not the name it renders as"

# The refusal echoes repository text, so it is repr-escaped — an ANSI escape in a
# skill name must not reach a terminal or an agent's context raw. Same rule the
# pointer refusal adopted for the same reason.
#
# The ESC must be a REAL 0x1b byte: writing the four characters `\x1b` into the
# file makes the needle match whether or not repr is applied, and the assertion
# cannot fail. Built with printf for that reason.
esc="$(new_fixture plan wrap-up-session)"
{ printf '# Task tracking\n\n```ini\n[tracker]\nprovider = local\n'
  printf '\n[routines]\nkind_precedence = design-decision\n'
  printf '\n[routines.selectors]\nplan = design-decision\n'
  printf '\n[routines.skills]\nplan = /plan, /boom\033[31mred, /wrap-up-session\n'
  printf '```\n'
} > "$esc/docs/task-tracking.md"
# Confirm the fixture really carries the control byte, or the assertion below is
# testing the escaping of a string that never needed escaping.
assert_eq "1" "$(grep -c "$(printf '\033')" "$esc/docs/task-tracking.md")" \
  "AC4 fixture: the skill name carries a real ESC byte, not the literal text \\x1b"
esc_refusal="$(refusal_of "$esc")"
assert_contains "$esc_refusal" '\x1b' \
  "AC4: the refusal escapes control characters in a skill name rather than emitting them"
assert_not_contains "$esc_refusal" "$(printf '\033')" \
  "AC4: no raw ESC byte reaches the refusal output"

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
recfg="$(new_fixture debug build quality-gate wrap-up-session brainstorm)"
write_config "$recfg" "bug, tech-debt" <<'INI'
[routines.selectors]
fix = bug, tech-debt

[routines.skills]
fix = /brainstorm, /build, /wrap-up-session
INI
assert_contains "$(load_report "$recfg")" "chain fix: /brainstorm -> /build -> /wrap-up-session" \
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

# The case above declares `triage` in BOTH sections, so the selectors arm of the
# check fires and the skills arm never runs. A chain-only invention is the arm
# that had no coverage — and it is the reachable one, since a project can add a
# chain without a selector.
skills_only="$(new_fixture plan wrap-up-session)"
write_config "$skills_only" "design-decision" <<'INI'
[routines.selectors]
plan = design-decision

[routines.skills]
plan = /plan, /wrap-up-session
triage = /plan, /wrap-up-session
INI
skills_only_refusal="$(refusal_of "$skills_only")"
assert_contains "$skills_only_refusal" "[routines.skills]" \
  "AC12: an invented routine declared ONLY as a chain is refused by the skills arm"
assert_contains "$skills_only_refusal" "triage" \
  "AC12: the chain-only refusal names the invented routine"

# ============================================================================
# 7. AC7/AC12 — THIS project's configuration, and why it lives where it does
# ============================================================================
# Everything above tests the engine against fixtures. This section tests the
# repository itself: a configuration contract nobody dogfoods is a contract
# nobody has run.
#
# The placement is the substance of #82. `CLAUDE.md` is template-managed and
# `/sync` overwrites it wholesale, while `docs/` is in no syncable root — so a
# pointer in `CLAUDE.md` would ship to every adopter naming a file the template
# can never deliver, permanently in the "declared but missing" state the loader
# now refuses. The declaration therefore lives in `.claude/project.md`, which
# `/sync` never touches, next to a target that ships with the project.
printf '\n-- this project is configured, and the configuration is where /sync cannot reach --\n'

assert_eq "present" "$([ -f docs/task-tracking.md ] && echo present || echo missing)" \
  "AC7: this project ships its own docs/task-tracking.md"

# The pointer, and the file it names. A declaration whose target is missing is
# refused loudly (#82) — so asserting the target exists is asserting the project
# is in the "configured" state rather than the "broken" one.
assert_file_matches ".claude/project.md" "^Task tracking instructions: " \
  "AC7: .claude/project.md carries the declaration"
project_pointer="$(grep -oiE 'Task tracking instructions:[[:space:]]*[^[:space:]`<>]+' .claude/project.md \
  | sed -E 's/^[^:]*:[[:space:]]*//' | head -1)"
assert_eq "docs/task-tracking.md" "$project_pointer" \
  "AC7: the declaration names this project's configuration file"
assert_eq "present" "$([ -f "$project_pointer" ] && echo present || echo missing)" \
  "AC7: the declared target exists — the project is configured, not broken"

# Pi does not read `.claude/project.md` and Claude Code does not read `AGENTS.md`,
# so one pointer configures one harness. Shipping only the Claude Code copy left
# this project silently loading defaults on Pi, with the routine chains and the
# claim label unconfigured and nothing saying so.
assert_file_matches "AGENTS.md" "^Task tracking instructions: " \
  "AC7: AGENTS.md carries the declaration too — Pi reads no other project file"
agents_pointer="$(grep -oiE 'Task tracking instructions:[[:space:]]*[^[:space:]`<>]+' AGENTS.md \
  | sed -E 's/^[^:]*:[[:space:]]*//' | head -1)"
assert_eq "$project_pointer" "$agents_pointer" \
  "AC7: both harnesses are pointed at the SAME configuration file"

# CLAUDE.md documents the convention and emits no live pointer of its own.
claude_pointers="$(grep -oiE 'Task tracking instructions:[[:space:]]*[^[:space:]`<>]+' CLAUDE.md || true)"
assert_eq "" "$claude_pointers" \
  "AC7: CLAUDE.md emits no bare parseable pointer — it ships to every adopter"

# Neither the declaration nor its target may sit under a syncable root, or the
# next /sync destroys the project's configuration. The root list is read from
# the same doc block /sync itself parses rather than restated here, so this
# cannot pass against a stale copy of the list.
sync_roots="$(awk '/^## Syncable Paths/ { inblock = 1; next }
                   inblock && /^##+ / { exit }
                   inblock && /→/ { print $1 }' .agents/skills/sync/SKILL.md \
              | sed 's|/$||' | grep -v '^$' | sort -u)"
assert_not_contains "$sync_roots" "docs" \
  "AC7: docs/ is not a syncable root — the configuration survives /sync"
assert_not_contains "$sync_roots" ".claude/project.md" \
  "AC7: .claude/project.md is not a syncable root — the declaration survives /sync"

# `doctor` is what a human runs to ask "am I configured?". It must name the file,
# not report `none`. Pinned against the local provider so the answer does not
# depend on the network or on `gh` being authenticated.
doctor_out="$(PYTHONDONTWRITEBYTECODE=1 "$PY" \
  "$SCRIPTS/task-registry.py" doctor --repo "$REPO" --provider local 2>&1)"
assert_contains "$doctor_out" "configuration:  docs/task-tracking.md" \
  "AC7: doctor reports this project's configured path"
assert_not_contains "$doctor_out" "configuration:  none" \
  "AC7: doctor no longer reports this project as unconfigured"

# AC12 live: this project reconfigures its routines by editing that one file and
# no code -- and because it DECLARES [routines.skills], the on-disk skill check
# runs against this repository for real rather than only against fixtures.
project_chains="$(load_report "$REPO")"
assert_not_contains "$project_chains" "REFUSED:" \
  "AC4 live: every skill this project's chains name is installed in this repository"
assert_contains "$project_chains" "routines: build,fix,improve,plan" \
  "AC9 live: this project declares a chain for every routine it selects with"
assert_contains "$project_chains" "chain fix: /debug -> /build -> /quality-gate -> /wrap-up-session" \
  "AC12 live: the fix chain is read from docs/task-tracking.md"
assert_contains "$project_chains" "declared: True" \
  "AC8/AC12 live: the chains come from the file, not from the shipped defaults"

# The template an adopter starts from must document the section, or the layer
# exists only for projects that read the source.
for tree in .agents .claude; do
  assert_file_contains "$tree/skills/task-registry/templates/task-tracking.md" "[routines.skills]" \
    "AC12: $tree template documents the [routines.skills] section"
  assert_file_contains "$tree/skills/task-registry/templates/task-tracking.md" "/wrap-up-session" \
    "AC5: $tree template shows chains ending at the review gate"
done


finish
