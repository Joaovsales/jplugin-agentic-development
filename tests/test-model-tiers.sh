#!/bin/bash
# tests/test-model-tiers.sh — the `ceiling` tier must stay un-pinned.
#
# `ceiling` means "omit the model override so the sub-agent inherits the session
# model". The three highest-stakes review roles resolve to it, and the whole point
# is that they run at whatever capability the user is paying for: pin one to a
# concrete model and an Opus session silently gets a Sonnet reviewer.
#
# That regression is invisible at runtime — the review still runs and still
# reports findings, just from a weaker model — so it needs a mechanical guard
# rather than a convention. A single re-added `model: sonnet` line is enough to
# reintroduce it, which is exactly the smallest falsifiable unit to pin.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CEILING_AGENTS="code-reviewer security-reviewer software-design-expert-review critic"

# Reviewer-tier personas that MUST keep their Claude-side pin. This is the mirror
# of the ceiling assertion and it guards a real, already-observed regression: the
# `.agents/` -> `.claude/` parity copy is a plain `cp`, and the canonical tree is
# model-agnostic by contract, so copying over a Claude-only `model:` line drops it
# silently. Parity tests cannot catch it -- the `cp` is what made the two files
# identical. Pin the line itself.
PINNED_AGENTS="context-document-optimizer:sonnet"

# --- 1. Ceiling agents carry no model pin in the Claude Code tree -------------
# assert_file_not_matches covers both failure modes this used to hand-roll: a
# missing file and a present pin. It also treats a missing file as a failure
# rather than a skip, which is what the hand-rolled version did.
for agent in $CEILING_AGENTS; do
  assert_file_not_matches ".claude/agents/$agent.md" '^model:' \
    "ModelTier: $agent inherits the session model (no pin)"
done

# --- 1b. Reviewer-tier agents keep their Claude-side model pin ----------------
for entry in $PINNED_AGENTS; do
  agent="${entry%%:*}"; want="${entry##*:}"
  f=".claude/agents/$agent.md"
  assert_file_contains "$f" "model: $want" \
    "ModelTier: $agent keeps its Claude-side 'model: $want' pin (not a ceiling role)"
done

# --- 2. Canonical agent tree stays model-agnostic ----------------------------
# Also covered by test-agents.sh; asserted here so this guard reads as a complete
# statement of the tier contract rather than depending on a sibling file.
for f in .agents/agents/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in README.md) continue ;; esac
  assert_file_not_matches "$f" '^model:' \
    "ModelTier: canonical $(basename "$f") is model-agnostic"
done

# --- 3. Non-ceiling agents still resolve to a tier ---------------------------
# Guards the opposite mistake: stripping every pin, which would silently promote
# cheap roles to the session model and inflate cost.
# The [ -f ] guard is kept deliberately: `scout-unused` names no real file, so
# this loop skips absent personas rather than failing on them — unlike section 1,
# where every named agent must exist.
for agent in backend-developer frontend-developer code-debugger scout-unused; do
  f=".claude/agents/$agent.md"
  [ -f "$f" ] || continue
  assert_file_matches "$f" '^model:' \
    "ModelTier: non-ceiling $agent still pins a tier model"
done

# --- 4. The tier contract is documented where agents are routed --------------
assert_file_contains CLAUDE.md "| Ceiling |" \
  "ModelTier: CLAUDE.md Model Routing has a Ceiling row"
assert_file_contains CLAUDE.md "omit the model override" \
  "ModelTier: CLAUDE.md defines ceiling as omitting the override"
for f in .agents/skills/build/SKILL.md .claude/skills/build/SKILL.md; do
  assert_file_contains "$f" "Ceiling-tier agents take no \`model\` at all" \
    "ModelTier: $f states the ceiling dispatch rule"
done
for f in .agents/skills/plan/SKILL.md .claude/skills/plan/SKILL.md; do
  assert_file_contains "$f" "ceiling" \
    "ModelTier: $f defers to the ceiling tier"
done

# --- 5. Ceiling roles are not pinned in any routing table -------------------
# A table row that gives a ceiling agent a concrete Claude Code model reintroduces
# the cap in documentation even when the agent file is clean.
for f in CLAUDE.md .agents/skills/build/SKILL.md .claude/skills/build/SKILL.md; do
  for agent in $CEILING_AGENTS; do
    if grep -E "^\|.*\`$agent\`" "$f" | grep -qE '`(sonnet|haiku|opus)`'; then
      _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
      printf '  FAIL ModelTier: %s routes %s to a concrete model\n' "$f" "$agent"
    else
      assert_eq "unpinned" "unpinned" "ModelTier: $f does not pin $agent in a table"
    fi
  done
done

# --- 6. critic never resolves below planner tier ------------------------------
# Plain ceiling downgrades critic on a sub-planner session, and critic is the
# adversarial gate of last resort. The floor is a dispatch rule, not frontmatter:
# a `model: opus` pin would cap the agent at Opus rather than floor it, which is
# the defect the ceiling tier exists to remove. So the rule text is what gets
# pinned here, alongside the no-pin assertion above.
#
# The needles are prose unique to the *rule*, not the phrase "planner floor" --
# that phrase also appears in the Agents table cell, so a looser needle stayed
# green even with the whole explanation deleted (verified: 0 failures before this
# was tightened). assert_prose_contains rather than assert_file_contains because
# CLAUDE.md hard-wraps, and one of these phrases straddles a line break.
assert_prose_contains CLAUDE.md "dispatch rule, not frontmatter" \
  "ModelTier: CLAUDE.md explains critic's floor as a dispatch rule"
assert_prose_contains CLAUDE.md "never resolves below planner tier" \
  "ModelTier: CLAUDE.md states what critic's floor bounds"
assert_file_matches CLAUDE.md '^\| .critic. \| .?ceiling \(planner floor\)' \
  "ModelTier: CLAUDE.md Agents table marks critic ceiling (planner floor)"

# --- 7. No concrete provider model IDs in the routing docs -------------------
# PI_SETUP.md owns them. Three copies of a release-sensitive fact is three
# chances to go stale, and the tables are the copies nobody updates.
for f in CLAUDE.md .agents/skills/build/SKILL.md .claude/skills/build/SKILL.md; do
  for vendor in 'moonshotai/' 'qwen/' 'z-ai/' 'deepseek/' 'anthropic/claude'; do
    assert_file_not_matches "$f" "$vendor" "ModelTier: $f has no hardcoded $vendor ID"
  done
  assert_file_contains "$f" 'PI_SETUP.md` § Sub-Agent Routing' \
    "ModelTier: $f points at PI_SETUP.md for concrete IDs"
done
assert_file_contains PI_SETUP.md "single source of concrete model IDs" \
  "ModelTier: PI_SETUP.md claims ownership of the concrete IDs"

# --- 8. No skill pins a Ceiling role to any alias -----------------------------
# Any alias, not just sonnet. An alias-specific needle is trivially walked around
# by naming a different one, which is how `model: opus` and `model: haiku`
# mutations stayed green here.
for tree in .agents .claude; do
  for skill in quality-gate software-design-expert-review wrap-up-session build plan auto-improve; do
    assert_file_not_matches "$tree/skills/$skill/SKILL.md" 'model: .?(sonnet|opus|haiku)' \
      "ModelTier: $tree $skill pins no Ceiling role to an alias"
  done
done

# --- 8b. A table cell pins just as hard as frontmatter -----------------------
# `model: <alias>` was the whole needle above, so a routing table written as
# `| Design review | sonnet | ... |` walked past it untouched. That is exactly how
# auto-improve kept the design reviewer pinned to `sonnet` through all of #61 --
# the guard existed, matched the wrong syntax, and reported green.
#
# Matches a table row whose FIRST cell names a review charter and whose later cells
# carry an alias. Deliberately loose on both sides, because the first draft of this
# guard was defeated three ways in review: `**sonnet**` (bold), `Sonnet` (capital),
# and `sonnet (floor)` (trailing token) all evaded a `.?alias.?` cell pattern, and a
# hardcoded charter list missed `Code review` and `Correctness review`. Matching any
# first-cell "review"/"critic"/"adversarial"/"audit" against any later alias catches
# all of those; validated against 8 evasion fixtures and the repo's 6 legitimate
# alias rows (Coding agents, Debugger, Scout, Test health, Performance, Reviewer).
#
# One grep per tree, reusing section 9's shape rather than looping files: the
# per-file loop this replaces spawned three processes per skill and cost ~35s of
# suite time on Windows, and a glob that matched nothing would have reported zero
# assertions as a pass.
for tree in .agents .claude; do
  hits="$(grep -rlE '^\|[^|]*([Rr]eview|[Aa]dversarial|[Cc]ritic|[Aa]udit)[^|]*\|.*([Ss]onnet|[Oo]pus|[Hh]aiku)' \
    "$tree/skills" 2>/dev/null || true)"
  assert_eq "" "$hits" "ModelTier: no review role pinned in a table cell under $tree/skills"
done

# --- 9. No concrete provider ID anywhere in either skill tree ----------------
# Section 7 names the two routing tables; this sweeps every skill, because a
# hardcoded ID goes stale in a prose paragraph exactly as fast as in a table.
for tree in .agents .claude; do
  hits="$(grep -rlE 'moonshotai/|qwen/|z-ai/|deepseek/|anthropic/claude' "$tree/skills" 2>/dev/null || true)"
  assert_eq "" "$hits" "ModelTier: no concrete provider model ID under $tree/skills"
done

# --- 10. critic's floor is stated where critic is dispatched ------------------
# The floor lived only in CLAUDE.md while three skills instructed plain ceiling
# unconditionally — documented and simultaneously negated. Pin it at the sites
# that actually dispatch, or the rule is not shipped.
for tree in .agents .claude; do
  for skill in build plan wrap-up-session; do
    assert_prose_contains "$tree/skills/$skill/SKILL.md" "planner floor" \
      "ModelTier: $tree $skill states critic's planner floor at its dispatch"
  done
done

# --- 11. Pi keeps explicit pins — omission there downgrades, not inherits -----
# On Pi, omitting an agent from agentOverrides falls through to
# subagents.defaultModel, a fixed builder-tier model. Deleting these entries
# downgrades every review rather than lifting it. Both the config and the rule
# explaining it are pinned, because the config alone reads as an oversight.
for agent in code-reviewer security-reviewer software-design-expert-review critic; do
  assert_file_matches PI_SETUP.md "\"$agent\":" \
    "ModelTier: PI_SETUP.md keeps an explicit Pi pin for $agent"
done
assert_prose_contains PI_SETUP.md "Ceiling cannot be expressed by omission on Pi" \
  "ModelTier: PI_SETUP.md explains why Pi pins rather than omits"
assert_prose_contains CLAUDE.md "falls through to \`subagents.defaultModel\`" \
  "ModelTier: CLAUDE.md states the Pi omission hazard"

# --- 12. The debugger escalation ladder has a real middle rung ----------------
# Reviewer and Builder both resolve to `sonnet` on Claude Code, so a debugger
# escalation written as plain reviewer tier re-runs the model that just failed
# twice: the ladder documents three rungs and delivers two. That is invisible at
# runtime — the retries happen, they just cannot succeed for a new reason — so it
# needs a mechanical guard. Both the resolution and the rule forbidding a
# collapsed rung are pinned, because the row alone reads as an arbitrary choice
# and gets "simplified" back.
for f in .agents/skills/build/SKILL.md .claude/skills/build/SKILL.md; do
  assert_file_matches "$f" '^\| Debugger \(attempts 3-4.*ceiling \(builder floor\)' \
    "ModelTier: $f routes debugger attempts 3-4 to ceiling (builder floor)"
  assert_prose_contains "$f" "must never resolve to the same model" \
    "ModelTier: $f forbids a ladder whose first two rungs collapse"
  assert_prose_contains "$f" "Confirm it resolved to something stronger than Tier 1" \
    "ModelTier: $f makes the circuit breaker's Tier 2 check its own escalation"
done
assert_prose_contains CLAUDE.md "Reviewer and Builder both resolve to" \
  "ModelTier: CLAUDE.md names why the reviewer rung collapsed on Claude Code"
# Prose rather than regex: the phrase carries an en dash and an em dash, and a
# multibyte character does not match `.` under grep -E in the C locale.
assert_prose_contains CLAUDE.md 'Debugger attempts 3–4 — `ceiling (builder floor)`' \
  "ModelTier: CLAUDE.md documents the debugger's builder floor"
assert_file_matches CLAUDE.md '^\| Reviewer \|.*see the floor below' \
  "ModelTier: CLAUDE.md Reviewer row points at the floor rather than reading as flat sonnet"

finish
