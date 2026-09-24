#!/bin/bash
# tests/test-how-why-skills.sh — contract for the vendored pstack /how and /why.
#
# Both skills are adapted from pstack (cursor/plugins) with the smallest change
# that makes them run in this harness. Four things are pinned:
#
#   1. FIDELITY — every reference file is upstream's, byte for byte: its git blob
#      matches the blob at the adapted revision. Only SKILL.md is adapted.
#   2. HARNESS — no Cursor-only mechanism survives in SKILL.md (the models rule
#      file, the Task tool's subagent types and readonly flag, the mcps/
#      directory); the dispatches name this harness's tiers instead.
#   3. ROUTING — the investigate lane reaches both as optional steps, so /go can
#      pick one while the lane's chain stays empty; that needs the Skill tool to
#      accept them, hence `disable-model-invocation: false`.
#   4. PROVENANCE — the MIT notice travels with each skill, and the import is
#      registered for upstream-drift checks.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

REVISION=12d587dfb20741cafc376c42c696c5f6e2a64487
MIT_LICENSE_BLOB=6b5400237fdf6545be0b8fae370d6f2fcff8fb25
HOW=.agents/skills/how
WHY=.agents/skills/why
LANE=.agents/skills/task-registry/lanes/investigate.md

frontmatter() {
  awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm { print }' "$1" 2>/dev/null
}

# --- 1. fidelity: references are upstream blobs ------------------------------
while read -r blob path; do
  [ -n "$blob" ] || continue
  f=".agents/skills/$path"
  assert_eq "$blob" "$(git hash-object "$f" 2>/dev/null)" \
    "HowWhy: $f is upstream's file at $REVISION, unmodified"
done <<'EOF'
3a36fb6736c5b74ac2774350841e332a019dec94 how/references/explainer-prompt.md
9b4b0594bfd779015616e9d280369aba939583b4 how/references/explorer-prompt.md
3732bf6881b60d1337fa3498574452a85d33ba30 why/references/epistemics.md
3b56af44c589833508f4605cfdd4432b39a16739 why/references/investigator-prompt.md
aa3d877cd539763ff05e266ae0a02dd811441e2b why/references/source-playbook.md
32d5f97f8d2d3974c668f5f0392737b7e8e25afd why/references/sources/code-archaeology.md
2770763ff5d0d1ad004abcc9a0138c9537ad1978 why/references/sources/databricks.md
d8363b1c1d1c7eadb15d47abd83bf70537c39620 why/references/sources/datadog.md
450d6e52f25b1b41f741cb3e9c93e1c74ef858b4 why/references/sources/incident-postmortem.md
899c643c078f322afe6ae0ef78a007f8ffd356c1 why/references/sources/linear.md
d16230a4105fd1dacf870da0950a38faeb9381e6 why/references/sources/notion.md
2b7cf6f3098ee868547dc4e69efacfe9c255246b why/references/sources/sentry.md
863a527d60e4e055e680834ef8098ea04273a1ae why/references/sources/slack.md
9707dfcc2fc57ea126484a433c5cd9ee4d400ef3 why/references/synthesizer-prompt.md
EOF

# --- 2. harness: frontmatter and dispatch ------------------------------------
for skill in how why; do
  f=".agents/skills/$skill/SKILL.md"
  fm="$(frontmatter "$f")"
  assert_contains "$fm" "name: $skill" "HowWhy: $skill frontmatter names the skill"
  assert_contains "$fm" "disable-model-invocation: false" \
    "HowWhy: $skill is model-invocable, so /go's investigate lane can run it"
  assert_contains "$fm" "harness: universal" "HowWhy: $skill registers for every harness"
  for cursorism in 'pstack-models.mdc' 'generalPurpose' 'readonly' 'grok-' 'Task tool' 'mcps/'; do
    assert_file_not_matches "$f" "$cursorism" \
      "HowWhy: $skill carries no Cursor-only '$cursorism'"
  done
  assert_file_contains "$f" ".agents/references/model-routing.md" \
    "HowWhy: $skill routes its dispatches through the model-routing tiers"
  assert_file_contains "$f" "## Provenance" "HowWhy: $skill states its provenance"
  assert_file_contains "$f" "$REVISION" "HowWhy: $skill pins the adapted revision"
done

# The explorers are read-only recon (Scout), the explainer and synthesizer the
# strongest model available (Ceiling: no model passed). Investigators need every
# MCP the session has, so they never run on a restricted agent type.
assert_prose_contains "$HOW/SKILL.md" 'the `Explore` agent with `model: "haiku"`' \
  "HowWhy: how explorers dispatch at Scout tier through Explore"
assert_prose_contains "$HOW/SKILL.md" 'pass no `model`' \
  "HowWhy: how explainer runs at Ceiling tier"
assert_prose_contains "$WHY/SKILL.md" 'the `general-purpose` agent with `model: "haiku"`' \
  "HowWhy: why investigators dispatch at Scout tier with full tool access"
assert_prose_contains "$WHY/SKILL.md" 'pass no `model`' \
  "HowWhy: why synthesizer runs at Ceiling tier"

# --- 3. routing: the investigate lane offers both -----------------------------
assert_file_matches "$LANE" '^[0-9]+\. `/how <ref>` .* — optional$' \
  "HowWhy: investigate offers /how as an optional step"
assert_file_matches "$LANE" '^[0-9]+\. `/why <ref>` .* — optional$' \
  "HowWhy: investigate offers /why as an optional step"
assert_prose_contains ".agents/skills/go/SKILL.md" '`/how`, `/why`' \
  "HowWhy: /go lists /how and /why among the skills it calls"

# --- 4. provenance -----------------------------------------------------------
for skill in how why; do
  lic=".agents/skills/$skill/LICENSE.pstack"
  assert_eq "$MIT_LICENSE_BLOB" "$(git hash-object "$lic" 2>/dev/null)" \
    "HowWhy: $lic is the reviewed MIT text exactly"
  assert_file_contains THIRD_PARTY_NOTICES.md "pstack/skills/$skill/SKILL.md" \
    "HowWhy: notices name upstream $skill"
  assert_file_contains .github/upstreams.json "pstack/skills/$skill" \
    "HowWhy: registry watches upstream $skill for drift"
done
assert_file_contains .github/upstreams.json '"id": "pstack-how-why"' \
  "HowWhy: the import has its own drift-registry entry"
assert_file_contains .github/upstreams.json "$REVISION" \
  "HowWhy: the registry pins the adapted revision"

finish
