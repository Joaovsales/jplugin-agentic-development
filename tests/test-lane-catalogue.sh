#!/bin/bash
# tests/test-lane-catalogue.sh — one definition per lane, read by both routers.
#
# specs/lane-catalogue.md AC1-AC4, AC6 (the template pin). A lane is a markdown
# file under .agents/skills/task-registry/lanes/; registry/lanes.py is the one
# reader. The registry derives every routine constant from it, `task-registry
# lanes` prints it, and /go matches against it. This test pins the reader's
# grammar, its refusals, the shipped catalogue's contents, and the command.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SCRIPTS="$REPO/.agents/skills/task-registry/scripts"
CLI="$SCRIPTS/task-registry.py"
LANES_DIR=".agents/skills/task-registry/lanes"
PY=python3

TMP_DIRS=()
cleanup() { local d; for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# `-B` keeps every probe from writing __pycache__ into the canonical tree, which
# every downstream /sync would then carry as an untracked change.
pyreg() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" -B -; }
run_cli() { PYTHONDONTWRITEBYTECODE=1 "$PY" -B "$CLI" "$@"; }

new_dir() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/lane-catalogue.XXXXXX")"
  TMP_DIRS+=("$d")
  printf '%s' "$d"
}

# A lane file in $1 named $2, frontmatter from $3 (newline-separated key: value
# lines), steps from stdin. `ends:` is always present unless the caller says
# otherwise, so a fixture tests one rule at a time.
write_lane() {
  local dir="$1" name="$2" front="$3"
  { printf -- '---\n'
    [ -n "$front" ] && printf '%s\n' "$front"
    printf -- '---\n# Lane: %s\n\nOwnership sentence.\n\n' "$name"
    cat
    printf '\n## Reply\n\nWhat to say.\n'
  } > "$dir/$name.md"
}

# Fixture paths travel as ARGUMENTS, never inside the Python text: on Windows
# the shell converts an argument's /tmp/... to a native path and leaves a string
# literal alone, so an embedded path is "not a directory" to Python.
pyreg_with() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$SCRIPTS" "$PY" -B - "$@"; }

# The refusal a fixture directory produces, or "LOADED" when it did not refuse.
refusal_of() {
  pyreg_with "$1" <<'PY'
import sys
from registry.lanes import LaneCatalogueError, load_catalogue
try:
    load_catalogue(sys.argv[1])
    print("LOADED")
except LaneCatalogueError as exc:
    print("REFUSED:", exc)
PY
}

# ============================================================================
# 1. AC1 — the shipped catalogue, read through its views
# ============================================================================
printf '\n-- shipped catalogue --\n'
views="$(pyreg <<'PY'
from registry.lanes import catalogue
c = catalogue()
print("names:", ",".join(c.names))
print("routines:", ",".join(c.routines))
print("producers:", ",".join(c.producers))
print("deferred:", ",".join(sorted(c.deferred)))
print("deferred-reason:", c.deferred.get("build", ""))
for name in sorted(c.selectors):
    print(f"selects {name}: {','.join(c.selectors[name])}")
for name in sorted(c.chains):
    print(f"chain {name}: {' -> '.join(c.chains[name])}")
print("interactive:", ",".join(lane.name for lane in c.interactive))
print("investigate-chain:", "|".join(c.lane("investigate").chain) or "none")
print("fix-ends:", c.lane("fix").ends)
print("fix-first-step:", c.lane("fix").steps[0])
print("babysit-chain:", " -> ".join(c.lane("babysit").chain))
print("janitor-chain:", " -> ".join(c.lane("janitor").chain))
print("none-chain:", " -> ".join(c.lane("none").chain))
PY
)"
assert_contains "$views" "names: architect,babysit,build,fix,improve,investigate,janitor,none,perf,plan,refactor,tidy" \
  "AC1: the catalogue carries the twelve lanes, alphabetical"
assert_contains "$views" "routines: architect,build,fix,improve,janitor,plan,tidy" \
  "AC1: routines are the seven lanes with routine: set"
assert_contains "$views" "producers: architect,janitor,tidy" \
  "AC1: producers are the three routine: producer lanes"
assert_contains "$views" "deferred: build" "AC1: build is the one deferred lane"
assert_contains "$views" "#97" "AC1: build's deferral reason cites #97"
assert_contains "$views" "#98" "AC1: build's deferral reason cites #98"
assert_contains "$views" "selects fix: bug,tech-debt" "AC1: fix selects bug and tech-debt"
assert_contains "$views" "selects improve: enhancement,documentation" \
  "AC1: improve selects enhancement and documentation"
assert_contains "$views" "selects plan: design-decision" "AC1: plan selects design-decision"
assert_not_contains "$views" "selects build" "AC1: build has no label selector"
assert_contains "$views" "chain build: /build -> /quality-gate -> /wrap-up-session" \
  "AC1: build's chain"
assert_contains "$views" "chain fix: /debug -> /build -> /quality-gate -> /wrap-up-session" \
  "AC1: fix's chain"
assert_contains "$views" "chain improve: /plan -> /build -> /quality-gate -> /wrap-up-session" \
  "AC1: improve's chain"
assert_contains "$views" "chain plan: /plan -> /wrap-up-session" "AC1: plan's chain"
assert_not_contains "$views" "chain janitor" \
  "AC1: chains covers consumers only — the domain [routines.skills] has"
assert_contains "$views" "janitor-chain: /sweep -> /wrap-up-session" \
  "AC1: a producer's chain is read from its lane"
assert_contains "$views" "interactive: babysit,fix,improve,investigate,none,perf,plan,refactor" \
  "AC1: interactive lanes are those with cues, alphabetical"
assert_contains "$views" "investigate-chain: none" \
  "AC1: investigate has no chain — its /how, /why and /checkpoint steps are optional"
assert_contains "$views" "fix-ends: ready PR" "AC1: ends is read verbatim"
assert_contains "$views" "fix-first-step: \`/debug <ref>\`" \
  "AC1: the first skill step of a routine lane takes <ref>"
assert_contains "$views" "babysit-chain: /receive-review -> /debug -> /plan -> /build -> /wrap-up-session" \
  "AC1: babysit's two branches are two skill steps, so the chain is linear"
assert_contains "$views" "none-chain: /brainstorm" "AC1: none routes to /brainstorm"

# --- AC1: config.py resolves its five names from the catalogue, lazily --------
lazy="$(pyreg <<'PY'
import registry.config as config
from registry import lanes
print("after-import:", lanes.catalogue.cache_info().currsize)
print("contract:", ",".join(config.CONTRACT_ROUTINES))
print("producers:", ",".join(config.PRODUCER_ROUTINES))
print("deferred:", ",".join(sorted(config.DEFERRED_ROUTINES)))
print("selectors:", ";".join(f"{k}={','.join(v)}" for k, v in sorted(config.DEFAULT_SELECTORS.items())))
print("skills:", ";".join(f"{k}={','.join(v)}" for k, v in sorted(config.DEFAULT_ROUTINE_SKILLS.items())))
print("after-access:", lanes.catalogue.cache_info().currsize)
PY
)"
assert_contains "$lazy" "after-import: 0" \
  "AC1: importing registry.config reads no lane file"
assert_contains "$lazy" "contract: architect,build,fix,improve,janitor,plan,tidy" \
  "AC1: CONTRACT_ROUTINES is the catalogue's routines view, one order everywhere"
assert_contains "$lazy" "producers: architect,janitor,tidy" "AC1: PRODUCER_ROUTINES from the catalogue"
assert_contains "$lazy" "deferred: build" "AC1: DEFERRED_ROUTINES from the catalogue"
assert_contains "$lazy" "selectors: fix=bug,tech-debt;improve=enhancement,documentation;plan=design-decision" \
  "AC1: DEFAULT_SELECTORS from the catalogue"
assert_contains "$lazy" "skills: build=/build,/quality-gate,/wrap-up-session;fix=/debug,/build,/quality-gate,/wrap-up-session;improve=/plan,/build,/quality-gate,/wrap-up-session;plan=/plan,/wrap-up-session" \
  "AC1: DEFAULT_ROUTINE_SKILLS from the catalogue"
assert_contains "$lazy" "after-access: 1" "AC1: the catalogue is read once, on first access"

config_py="$SCRIPTS/registry/config.py"
for literal in '"/debug"' '"/quality-gate"' '"janitor"' '"architect"' '"tidy"' '("plan", "fix"'; do
  assert_file_not_matches "$config_py" "$(printf '%s' "$literal" | sed 's/[][()]/\\&/g')" \
    "AC1: config.py no longer carries the lane literal $literal"
done

# ============================================================================
# 2. AC2 — the grammar, and every refusal names the file
# ============================================================================
printf '\n-- grammar --\n'
g="$(new_dir)"
write_lane "$g" "alpha" "$(printf 'ends: something\ncues: alpha, first')" <<'EOF'
1. `/first <ref>` — opens the chain
2. Prose that mentions `/never` in passing
3. `/optional-thing` — only if asked — optional
4. `/wrap-up-session` — closes
EOF
grammar="$(pyreg_with "$g" <<'PY'
import sys
from registry.lanes import load_catalogue
lane = load_catalogue(sys.argv[1]).lane("alpha")
print("chain:", " ".join(lane.chain))
print("steps:", len(lane.steps))
print("routine:", lane.routine)
print("reply:", lane.reply.strip())
PY
)"
assert_contains "$grammar" "chain: /first /wrap-up-session" \
  "AC2: the chain is the head skill of each step; prose and optional steps are not in it"
assert_contains "$grammar" "steps: 4" "AC2: every numbered line is a step, optional or not"
assert_contains "$grammar" "routine: None" "AC2: a lane without routine: is interactive-only"
assert_contains "$grammar" "reply: What to say." "AC2: the Reply section is read"

printf '\n-- refusals --\n'
r="$(new_dir)"; write_lane "$r" "Bad_Name" "ends: x" <<'EOF'
1. `/wrap-up-session` — x
EOF
assert_contains "$(refusal_of "$r")" "Bad_Name" "AC2: a stem outside [a-z][a-z-]* is refused by file"

r="$(new_dir)"; write_lane "$r" "beta" "$(printf 'ends: x\nselcts: bug')" <<'EOF'
1. `/wrap-up-session` — x
EOF
out="$(refusal_of "$r")"
assert_contains "$out" "REFUSED:" "AC2: an unknown frontmatter key is refused, not ignored"
assert_contains "$out" "selcts" "AC2: the refusal names the unknown key"
assert_contains "$out" "beta.md" "AC2: the refusal names the file"

r="$(new_dir)"; write_lane "$r" "gamma" "$(printf 'ends: x\nselects: bug')" <<'EOF'
1. `/wrap-up-session` — x
EOF
assert_contains "$(refusal_of "$r")" "selects" "AC2: selects without routine: consumer is refused"

r="$(new_dir)"; write_lane "$r" "delta" "$(printf 'ends: x\nroutine: producer\nselects: bug')" <<'EOF'
1. `/wrap-up-session` — x
EOF
assert_contains "$(refusal_of "$r")" "selects" "AC2: selects on a producer is refused"

r="$(new_dir)"; write_lane "$r" "epsilon" "$(printf 'ends: x\ndeferred: not yet')" <<'EOF'
1. `/wrap-up-session` — x
EOF
assert_contains "$(refusal_of "$r")" "deferred" "AC2: deferred without routine is refused"

r="$(new_dir)"; write_lane "$r" "zeta" "$(printf 'ends: x\nroutine: consumer')" <<'EOF'
1. `/build` — x
2. `/wrap-up-session` — y
3. `/extra` — after the gate
EOF
out="$(refusal_of "$r")"
assert_contains "$out" "/wrap-up-session" "AC2: a routine chain not ending at /wrap-up-session is refused"
assert_contains "$out" "zeta.md" "AC2: the terminal refusal names the file"

r="$(new_dir)"; write_lane "$r" "eta" "$(printf 'ends: x\ncues: eta')" <<'EOF'
1. `/build` — x
2. `/extra` — no gate needed
EOF
assert_eq "LOADED" "$(refusal_of "$r")" \
  "AC2: an interactive-only lane carries no terminal rule"

r="$(new_dir)"; write_lane "$r" "theta" "ends: x" <<'EOF'
1. `/build` — x
3. `/wrap-up-session` — a gap before me
EOF
assert_contains "$(refusal_of "$r")" "theta.md" "AC2: a step gap is refused by file"

r="$(new_dir)"; write_lane "$r" "iota" "ends: x" <<'EOF'
1. `/build` — x
- [ ] TDD: a checkbox row /build would dispatch
2. `/wrap-up-session` — y
EOF
assert_contains "$(refusal_of "$r")" "iota.md" "AC2: a checkbox row is refused by file"

r="$(new_dir)"; write_lane "$r" "kappa" "" <<'EOF'
1. `/wrap-up-session` — x
EOF
assert_contains "$(refusal_of "$r")" "ends" "AC2: a lane without ends: is refused"

r="$(new_dir)"; write_lane "$r" "lambda" "$(printf 'ends: x\nroutine: sometimes')" <<'EOF'
1. `/wrap-up-session` — x
EOF
assert_contains "$(refusal_of "$r")" "sometimes" "AC2: routine: outside consumer|producer is refused by value"

r="$(new_dir)"; write_lane "$r" "mu" "ends: x" <<'EOF'
No numbered steps at all.
EOF
assert_contains "$(refusal_of "$r")" "mu.md" "AC2: a lane with no steps is refused by file"

r="$(new_dir)"; write_lane "$r" "nu" "ends: x" <<'EOF'
1. `/build` — x
EOF
out="$(refusal_of "$r")"
assert_contains "$out" "cues" "AC2: a lane with neither routine: nor cues: is refused — no router reaches it"
assert_contains "$out" "nu.md" "AC2: the ghost-lane refusal names the file"

r="$(new_dir)"; write_lane "$r" "xi" "$(printf 'ends: x\ncues: xi')" <<'EOF'
1. `/build` — a long step that an editor
   wrapped onto a second line — optional
EOF
out="$(refusal_of "$r")"
assert_contains "$out" "wraps" "AC2: a step wrapped onto an indented line is refused, not truncated"
assert_contains "$out" "xi.md" "AC2: the wrapped-step refusal names the file"

r="$(new_dir)"
printf -- '---\nends: x\ncues: omicron\n---\n# Lane: omicron\n\n1. `/build` — x\n' > "$r/omicron.md"
out="$(refusal_of "$r")"
assert_contains "$out" "Reply" "AC2: a lane with no ## Reply section is refused"
assert_contains "$out" "omicron.md" "AC2: the missing-Reply refusal names the file"

# --- AC2: LaneCatalogueError is a ConfigError, so it flows through load_config -
assert_contains "$(pyreg <<'PY'
from registry.config import ConfigError
from registry.lanes import LaneCatalogueError
print("subclass:", issubclass(LaneCatalogueError, ConfigError))
PY
)" "subclass: True" "AC2: LaneCatalogueError is a ConfigError"

# ============================================================================
# 3. AC3 — twelve files in the canonical tree, every /skill token on disk
# ============================================================================
printf '\n-- files --\n'
for tree in .agents; do
  for lane in architect babysit build fix improve investigate janitor none perf plan refactor tidy; do
    f="$tree/skills/task-registry/lanes/$lane.md"
    assert_eq "present" "$([ -f "$f" ] && echo present || echo missing)" "AC3: $f exists"
    [ -f "$f" ] || continue
    assert_eq "yes" "$(head -1 "$f" | tr -d '\r' | grep -q '^---$' && echo yes || echo no)" \
      "AC3: $f opens with frontmatter"
    assert_file_matches "$f" "^# Lane: $lane\$" "AC3: $f heading names its lane"
    assert_file_matches "$f" "^## Reply" "AC3: $f has a Reply section"
    assert_file_not_matches "$f" '^[[:space:]]*-?[[:space:]]*\[[ ~x]\]' "AC3: $f has no checkbox rows"
  done
done
assert_eq "absent" "$([ -d .agents/skills/go/lanes ] && echo present || echo absent)" \
  "AC3: .agents/skills/go/lanes/ no longer exists"

# Every `/skill` token anywhere in a lane file — head, prose, or optional step —
# resolves on disk. A prose-named alternative is found before work starts.
skill_tokens() {
  tr -d '\r' < "$1" \
    | grep -oE '(^|[[:space:]`(,;])/[a-z][a-z0-9-]*' \
    | sed 's/^[^/]*//' | awk '!seen[$0]++'
}
for f in "$LANES_DIR"/*.md; do
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    assert_eq "present" "$([ -f ".agents/skills/${tok#/}/SKILL.md" ] && echo present || echo missing)" \
      "AC3: $f names $tok and .agents/skills/${tok#/}/SKILL.md exists"
  done <<EOF
$(skill_tokens "$f")
EOF
done

# Every routine lane's first skill step takes <ref>.
for lane in plan fix improve build; do
  first="$(grep -E '^1\. ' "$LANES_DIR/$lane.md" | head -1)"
  assert_contains "$first" "<ref>" "AC3: $lane's first step takes <ref>"
done

# The code-changing interactive lanes reach a human gate before /build.
for lane in refactor perf babysit; do
  flat="$(flatten "$LANES_DIR/$lane.md")"
  gate='/plan'
  pos_plan="$(first_pos "$flat" '/plan')"; pos_debug="$(first_pos "$flat" '/debug')"
  if [ -n "$pos_debug" ] && { [ -z "$pos_plan" ] || [ "$pos_debug" -lt "$pos_plan" ]; }; then gate='/debug'; fi
  assert_precedes "$flat" "$gate" '/build' "AC3: $lane names /plan or /debug before /build"
done
assert_file_not_matches "$LANES_DIR/investigate.md" '/wrap-up-session' \
  "AC3: investigate never names /wrap-up-session"

# ============================================================================
# 4. AC6 — the template's [routines.skills] block equals the catalogue
# ============================================================================
printf '\n-- template pin --\n'
template=".agents/skills/task-registry/templates/task-tracking.md"
template_chains="$(awk '/^\[routines.skills\]/{f=1;next} f&&/^\[/{exit} f&&/^[a-z]+ *=/' "$template" \
  | sed -E 's/ *= */=/; s/, */,/g' | sort | paste -sd';' -)"
catalogue_chains="$(pyreg <<'PY'
from registry.lanes import catalogue
print(";".join(f"{k}={','.join(v)}" for k, v in sorted(catalogue().chains.items())))
PY
)"
assert_eq "$catalogue_chains" "$template_chains" \
  "AC6: the template's [routines.skills] block equals catalogue().chains"
assert_file_contains "$template" "lanes/" \
  "AC6: the template names the lane catalogue as the source of its defaults"

# ============================================================================
# 5. AC4 — the `lanes` command
# ============================================================================
printf '\n-- lanes command --\n'
table="$(run_cli lanes --repo "$REPO" 2>&1)"; code=$?
assert_eq "0" "$code" "AC4: lanes exits 0 on this repository"
for lane in architect babysit build fix improve investigate janitor none perf plan refactor tidy; do
  assert_contains "$table" "$lane" "AC4: the table has a $lane row"
done
assert_contains "$table" "/debug -> /build -> /quality-gate -> /wrap-up-session" \
  "AC4: fix's row prints the effective chain"
assert_contains "$table" "deferred" "AC4: build's row says it is deferred"
assert_contains "$table" "broken, fails" "AC4: cues are printed for matching"

one="$(run_cli lanes fix --repo "$REPO" 2>&1)"; code=$?
assert_eq "0" "$code" "AC4: lanes fix exits 0"
assert_contains "$one" "1. \`/debug <ref>\`" "AC4: lanes fix prints the numbered steps verbatim"
assert_contains "$one" "## Reply" "AC4: lanes fix prints the Reply section"
assert_contains "$one" "chain:" "AC4: lanes fix prints the effective chain"
assert_not_contains "$one" "note:" "AC4: no note when the chain is not overridden"

unknown="$(run_cli lanes nope --repo "$REPO" 2>&1)"; code=$?
assert_eq "2" "$code" "AC4: an unknown lane exits 2"
assert_contains "$unknown" "investigate" "AC4: the unknown-lane refusal lists the known lanes"

# A fixture project: skills on disk as named, a local provider, and whatever
# [routines] block the case needs.
new_project() {
  local d name
  d="$(new_dir)"
  mkdir -p "$d/tasks" "$d/docs"
  printf '[ ] placeholder\n' > "$d/tasks/todo.md"
  for name in "$@"; do
    mkdir -p "$d/.agents/skills/$name"
    printf -- '---\nname: %s\n---\n' "$name" > "$d/.agents/skills/$name/SKILL.md"
  done
  printf '%s' "$d"
}
write_config() {
  { printf '# Task tracking\n\n```ini\n[tracker]\nprovider = local\n'; cat; printf '```\n'; } \
    > "$1/docs/task-tracking.md"
}

# --- override: the project replaced fix's chain --------------------------------
p="$(new_project debug build quality-gate wrap-up-session security-scan plan)"
write_config "$p" <<'EOF'

[routines]
kind_precedence = bug, tech-debt, design-decision, enhancement, documentation

[routines.selectors]
plan = design-decision
fix = bug, tech-debt
improve = enhancement, documentation

[routines.skills]
plan = /plan, /wrap-up-session
fix = /debug, /security-scan, /build, /quality-gate, /wrap-up-session
improve = /plan, /build, /quality-gate, /wrap-up-session
build = /build, /quality-gate, /wrap-up-session
EOF
over="$(run_cli lanes fix --repo "$p" 2>&1)"; code=$?
assert_eq "0" "$code" "AC4: an overridden lane still prints"
assert_contains "$over" "/security-scan" "AC4: the effective chain is the project's"
assert_contains "$over" "note:" "AC4: a configured override prints the note line"
assert_contains "$over" "[routines.skills]" "AC4: the note names the section that replaced the chain"
over_table="$(run_cli lanes --repo "$p" 2>&1)"
assert_contains "$over_table" "/debug -> /security-scan -> /build" \
  "AC4: the table prints the effective chain too"

# --- a producer's chain is shipped: [routines.skills] may not name one ---------
p="$(new_project sweep wrap-up-session)"
write_config "$p" <<'EOF'

[routines.skills]
janitor = /sweep, /wrap-up-session
EOF
prod="$(run_cli lanes janitor --repo "$p" 2>&1)"; code=$?
assert_eq "2" "$code" "AC4: a [routines.skills] key naming a producer is refused"
assert_contains "$prod" "producer" "AC4: the refusal says janitor is a producer"
assert_contains "$prod" "[routines.skills]" "AC4: the refusal names the section"

# --- missing skill: the chain names a skill absent from both roots -------------
p="$(new_project build quality-gate wrap-up-session)"
write_config "$p" <<'EOF'
EOF
missing="$(run_cli lanes fix --repo "$p" 2>&1)"; code=$?
assert_eq "2" "$code" "AC4: a chain skill absent from disk exits 2"
assert_contains "$missing" "/debug" "AC4: the refusal names the missing skill"
assert_contains "$missing" "fix" "AC4: the refusal names the lane"
listing="$(run_cli lanes --repo "$p" 2>&1)"; code=$?
assert_eq "0" "$code" "AC4: the table does not check disk — it is for matching, not running"

# --- unreadable configuration: interactive lanes are never blocked -------------
p="$(new_project debug build quality-gate wrap-up-session plan checkpoint)"
write_config "$p" <<'EOF'

[routines]
kind_precedence = bug, design-decision, tech-debt, enhancement, documentation

[routines.selectors]
plan = design-decision, bug
fix = bug, tech-debt
improve = enhancement, documentation
EOF
broken_table="$(run_cli lanes --repo "$p" 2>&1)"; code=$?
assert_eq "0" "$code" "AC4: lanes prints on a configuration that cannot be read"
assert_contains "$broken_table" "configuration could not be read" \
  "AC4: routine rows say the configuration could not be read"
assert_contains "$broken_table" "/debug -> /build" \
  "AC4: routine rows fall back to the shipped chain"
broken_inv="$(run_cli lanes investigate --repo "$p" 2>&1)"; code=$?
assert_eq "0" "$code" "AC4: lanes investigate exits 0 on a broken configuration"
broken_fix="$(run_cli lanes fix --repo "$p" 2>&1)"; code=$?
assert_eq "2" "$code" "AC4: lanes fix exits 2 on a broken configuration"
assert_contains "$broken_fix" "same label" "AC4: the refusal is the configuration's own error"
wf="$(run_cli workflow '#1' --repo "$p" 2>&1)"; code=$?
assert_eq "2" "$code" "AC4 control: workflow still exits 2 on the same configuration"

# --- no provider: a github declaration with no repository blocks workflow, not lanes
p="$(new_project debug build quality-gate wrap-up-session plan)"
{ printf '# Task tracking\n\n```ini\n[tracker]\nprovider = github\n```\n'; } > "$p/docs/task-tracking.md"
nogh_wf="$(run_cli workflow '#1' --repo "$p" 2>&1)"; wf_code=$?
nogh_lanes="$(run_cli lanes --repo "$p" 2>&1)"; lanes_code=$?
assert_eq "yes" "$([ "$wf_code" -ne 0 ] && echo yes || echo no)" \
  "AC4 control: workflow needs the provider and fails without a repository"
assert_contains "$nogh_wf" "no repository configured" \
  "AC4 control: workflow's failure is the provider's"
assert_eq "0" "$lanes_code" "AC4: lanes selects no provider, so the same project prints its table"
assert_not_contains "$nogh_lanes" "repository" "AC4: lanes never mentions the provider it did not build"

# The dispatch order is the mechanism: `lanes` returns before provider selection.
cli_flat="$(flatten "$CLI")"
assert_precedes "$cli_flat" 'command == "lanes"' 'select_provider(config)' \
  "AC4: task-registry.py dispatches lanes before selecting a provider"

# --- doctor survives a broken shipped catalogue ---------------------------------
# The catalogue is package data, so a broken one is simulated by pointing the
# reader at a fixture directory through the same loader load_config uses.
bad="$(new_dir)"
write_lane "$bad" "broken" "$(printf 'ends: x\nroutine: consumer')" <<'EOF'
1. `/build` — never wraps up
EOF
doctor_out="$(pyreg_with "$bad" "$REPO" <<'PY'
import sys
from registry import lanes, config as cfg
lanes.catalogue.cache_clear()
lanes.SHIPPED_LANES_DIR = sys.argv[1]
try:
    cfg.load_config(sys.argv[2])
    print("strict: loaded")
except cfg.ConfigError as exc:
    print("strict: REFUSED", exc)
loaded = cfg.load_config(sys.argv[2], strict=False)
print("lenient-fault:", loaded.catalogue_fault or "none")
PY
)"
assert_contains "$doctor_out" "strict: REFUSED" \
  "AC2: a broken shipped catalogue refuses a strict load as a ConfigError"
assert_contains "$doctor_out" "broken.md" "AC2: the strict refusal names the lane file"
assert_contains "$doctor_out" "lenient-fault: " "AC2: a lenient load records the fault instead of dying"
assert_not_contains "$doctor_out" "lenient-fault: none" \
  "AC2: the lenient load's recorded fault is not empty"
p="$(new_project)"
write_config "$p" <<'EOF'
EOF
doctor_cli="$(pyreg_with "$bad" "$p" "$CLI" <<'PY'
import importlib.util, io, sys
from contextlib import redirect_stdout
from registry import lanes
spec = importlib.util.spec_from_file_location("task_registry_cli", sys.argv[3])
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)
lanes.catalogue.cache_clear()
lanes.SHIPPED_LANES_DIR = sys.argv[1]
out = io.StringIO()
with redirect_stdout(out):
    code = cli.main(["doctor", "--repo", sys.argv[2]])
print("exit:", code)
print(out.getvalue())
PY
)"
assert_contains "$doctor_cli" "exit: 1" \
  "AC2: doctor runs to completion on a broken shipped catalogue and exits 1, as for any fault"
assert_not_contains "$doctor_cli" "routines:       MISCONFIGURED" \
  "AC2: the routines: line does not repeat a fault the catalogue: line owns"
assert_contains "$doctor_cli" "catalogue:      BROKEN" "AC2: doctor prints the catalogue: line as BROKEN"
assert_contains "$doctor_cli" "broken.md" "AC2: doctor's catalogue: line names the lane file"

finish
