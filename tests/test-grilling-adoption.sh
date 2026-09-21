#!/bin/bash
# tests/test-grilling-adoption.sh — pins specs/grilling-adoption.md AC 1–9.
#
# WHY THIS EXISTS
#
# The grilling primitive is adopted prose: a `/grilling` skill other skills
# invoke, a `/grill-me` front door users type, and a rewritten /brainstorm
# Step 3 that runs the interview in frontier rounds with a domain layer.
# Nothing executes any of it — the harness reads the SKILL.md and follows it —
# so the only mechanical guard is that the load-bearing tokens stay written
# down: the frontmatter flags that decide whether the Skill tool may fire a
# skill, the round format another skill recognises, the handoff names, the
# provenance pins, and the three inventory surfaces a skill must appear in.
#
# Pinned by the smallest falsifiable unit (a frontmatter key, a token, a path,
# a table row), never by prose wording, per /writing-skills § Right-Sizing
# Mechanical Guards. One canonical tree: `.claude/skills/` is a retired root
# (#156), so there is no copy to compare against.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

SKILLS=".agents/skills"
GRILLING="$SKILLS/grilling/SKILL.md"
GRILL_ME="$SKILLS/grill-me/SKILL.md"
BRAINSTORM="$SKILLS/brainstorm/SKILL.md"
DOMAIN="$SKILLS/brainstorm/references/domain-modeling.md"
WRITING="$SKILLS/writing-skills/SKILL.md"
UPSTREAMS=".github/upstreams.json"
NOTICES="THIRD_PARTY_NOTICES.md"
BANNER=".claude/hooks/session-start.sh"
BASELINE="c55ee46073ed923f86ce59a5eb3b6d895095d1b7"
UPSTREAM_BLOB="https://github.com/mattpocock/skills/blob/$BASELINE"
MIT_LICENSE_BLOB="f1dd2c09108dde1a5f56097cee8461b3ea834499"

# ── AC 1: /grilling — the model-invoked interview primitive ──────────────────
assert_file_matches "$GRILLING" '^name: grilling$' \
  "AC1: grilling frontmatter name"
assert_file_matches "$GRILLING" '^disable-model-invocation: false$' \
  "AC1: grilling is model-invocable (other skills call it through the Skill tool)"
assert_file_matches "$GRILLING" '^harness: universal$' \
  "AC1: grilling is harness-neutral"
assert_file_contains "$GRILLING" "design tree" \
  "AC1: grilling names the design tree"
assert_file_contains "$GRILLING" "frontier" \
  "AC1: grilling names the frontier"
assert_file_matches "$GRILLING" '^### 3. Ask the whole frontier in one round' \
  "AC1: grilling asks the frontier in rounds"
assert_file_contains "$GRILLING" "❓ **Q1**" \
  "AC1: grilling shows the numbered question marker"
assert_file_contains "$GRILLING" "➡️" \
  "AC1: grilling shows the recommendation marker"
assert_prose_contains "$GRILLING" "recommended answer" \
  "AC1: grilling puts a recommended answer on every question"
assert_file_contains "$GRILLING" "Scout" \
  "AC1: grilling looks facts up at Scout tier"
assert_file_matches "$GRILLING" "^### 4. Facts are yours, decisions are the user's" \
  "AC1: grilling hands decisions to the user"
assert_prose_contains "$GRILLING" "frontier is empty" \
  "AC1: grilling ends when the frontier is empty"
assert_prose_contains "$GRILLING" "Do not act" \
  "AC1: grilling carries the confirmation gate before acting"
assert_prose_contains "$GRILLING" "When grilling, ask one question at a time." \
  "AC1: grilling documents the one-line opt-out sentence"
assert_file_contains "$GRILLING" "CLAUDE.local.md" \
  "AC1: grilling names the Claude Code override file"
assert_file_contains "$GRILLING" "~/.pi/agent/AGENTS.md" \
  "AC1: grilling names the Pi override file"
assert_file_not_matches "$GRILLING" "jplugin:" \
  "AC1: grilling body hardcodes no harness namespace"

# ── AC 2: /grill-me — the user-only front door ───────────────────────────────
assert_file_matches "$GRILL_ME" '^name: grill-me$' \
  "AC2: grill-me frontmatter name"
assert_file_matches "$GRILL_ME" '^disable-model-invocation: true$' \
  "AC2: grill-me is user-only (the agent never fires it on its own)"
assert_file_matches "$GRILL_ME" '^harness: universal$' \
  "AC2: grill-me is harness-neutral"
assert_file_matches "$GRILL_ME" '^argument-hint:' \
  "AC2: grill-me carries an argument-hint"
assert_file_matches "$GRILL_ME" '^Invoke `/grilling`' \
  "AC2: grill-me invokes /grilling"
assert_file_matches "$WRITING" '^### YAML Frontmatter' \
  "AC2: the /writing-skills heading grill-me cites exists"
assert_prose_contains "$GRILL_ME" "no files" \
  "AC2: grill-me states that it writes no files"
assert_prose_contains "$GRILL_ME" "no repository" \
  "AC2: grill-me states that it needs no repository"
assert_file_contains "$GRILL_ME" "/brainstorm" \
  "AC2: grill-me routes repository feature work to /brainstorm"
assert_file_not_matches "$GRILL_ME" "jplugin:" \
  "AC2: grill-me body hardcodes no harness namespace"

# ── AC 3: provenance travels with each adapted skill; one canonical tree ─────
# The notice quotes the MIT text once; each bundled copy must be that text,
# byte for byte (CR stripped on both sides so a CRLF checkout compares text).
notice_text="$(awk '{ sub(/\r$/, "") }
  /^## Matt Pocock skills/ { sec=1 }
  sec && /^> MIT License$/ { found=1 }
  found && /^>/ { sub(/^> ?/, ""); print; next }
  found { exit }' "$NOTICES")"
for skill in grilling grill-me; do
  lic="$SKILLS/$skill/LICENSE.mattpocock"
  assert_file_contains "$lic" "Copyright (c) 2026 Matt Pocock" \
    "AC3: $skill notice names the upstream author"
  assert_eq "$notice_text" "$(tr -d '\r' < "$lic")" \
    "AC3: $skill bundled license matches the notice's quoted MIT text"
  assert_eq "$MIT_LICENSE_BLOB" "$(git hash-object "$lic")" \
    "AC3: $skill bundled license matches the reviewed MIT text exactly"
done
assert_files_identical "$SKILLS/grilling/LICENSE.mattpocock" "$SKILLS/grill-me/LICENSE.mattpocock" \
  "AC3: both bundled licenses are one text"
assert_eq "absent" "$([ -e .claude/skills/grilling ] || [ -e .claude/skills/grill-me ] && echo present || echo absent)" \
  "AC3: no copy under the retired .claude/skills/ root"

# ── AC 4: /brainstorm Step 3 runs the interview through /grilling ────────────
step3="$(awk '/^### Step 3/{p=1} /^### Step 4/{p=0} p' "$BRAINSTORM")"
assert_contains "$step3" 'Invoke `/grilling`' \
  "AC4: brainstorm Step 3 invokes /grilling"
assert_contains "$step3" "references/domain-modeling.md" \
  "AC4: brainstorm Step 3 names the domain layer reference"
assert_file_matches "$BRAINSTORM" '[Mm]ultiple-choice' \
  "AC4: brainstorm keeps the multiple-choice preference"
assert_file_not_matches "$BRAINSTORM" '[Oo]ne question at a time' \
  "AC4: brainstorm no longer lists one question at a time"
assert_file_not_matches "$BRAINSTORM" 'Do NOT dump all questions at once' \
  "AC4: brainstorm no longer forbids asking the whole frontier"
# Step 1 reads the glossary so Step 3 can challenge terms against it.
step1="$(awk '/^### Step 1/{p=1} /^### Step 2/{p=0} p' "$BRAINSTORM")"
assert_contains "$step1" "tasks/concepts.md" \
  "AC4: brainstorm Step 1 reads tasks/concepts.md"
# Key Principles name the three replacements.
principles="$(awk '/^## Key Principles/{p=1} p' "$BRAINSTORM")"
assert_contains "$principles" "Rounds, not drips" \
  "AC4: Key Principles name rounds over drips"
assert_contains "$principles" "Facts are the agent's job" \
  "AC4: Key Principles name the facts-versus-decisions split"
assert_contains "$principles" "Glossary is a glossary" \
  "AC4: Key Principles name the glossary-only rule"
# Untouched stages survive: heading plus one load-bearing body line each, so a
# rewritten body fails even while its heading stands.
assert_file_contains "$BRAINSTORM" "### Step 4 — Propose 2-3 Approaches" \
  "AC4: Step 4 options table present"
assert_file_contains "$BRAINSTORM" "**Complexity**: [Low/Medium/High]" \
  "AC4: Step 4 options table keeps its complexity row"
assert_file_contains "$BRAINSTORM" "### Step 4.5 — Pre-mortem Analysis" \
  "AC4: Step 4.5 pre-mortem present"
assert_file_contains "$BRAINSTORM" "It's 3 months from now and this approach failed. Why?" \
  "AC4: Step 4.5 pre-mortem keeps its prompt"
assert_file_contains "$BRAINSTORM" "### Step 6 — Write the Design Spec" \
  "AC4: Step 6 living-contract spec present"
assert_prose_contains "$BRAINSTORM" "Use the canonical terms settled in Step 3" \
  "AC4: Step 6 gains only the canonical-vocabulary constraint"
assert_file_contains "$BRAINSTORM" "DO NOT invoke /plan, /build, write any code" \
  "AC4: the hard gate is preserved"
assert_file_contains "$BRAINSTORM" "lightpanda fetch" \
  "AC4: the lightpanda research paragraph is preserved"
assert_file_not_matches "$BRAINSTORM" '/tdd' \
  "AC4: brainstorm names no /tdd"

# ── AC 5: the domain layer reference ─────────────────────────────────────────
assert_file_contains "$DOMAIN" "tasks/concepts.md" \
  "AC5: domain layer writes the glossary at tasks/concepts.md"
assert_file_contains "$DOMAIN" '- **term** — definition.' \
  "AC5: domain layer uses the /learn glossary entry format"
assert_file_contains "$DOMAIN" "Capture New Concepts" \
  "AC5: domain layer references the /learn seed rule rather than duplicating it"
assert_file_matches "$SKILLS/learn/SKILL.md" '^### .*Capture New Concepts' \
  "AC5: the cited /learn seed-rule heading exists"
assert_prose_contains "$DOMAIN" "glossary and nothing else" \
  "AC5: domain layer states the glossary-only rule"
assert_file_contains "$DOMAIN" "Hard to reverse" \
  "AC5: architecture-decision gate 1"
assert_file_contains "$DOMAIN" "Surprising without context" \
  "AC5: architecture-decision gate 2"
assert_file_contains "$DOMAIN" "real trade-off" \
  "AC5: architecture-decision gate 3"
assert_file_contains "$DOMAIN" "tasks/solutions/architecture/" \
  "AC5: architecture decisions land in the knowledge track directory"
assert_file_contains "$DOMAIN" "problem_type: architecture-decision" \
  "AC5: architecture decisions carry the store's problem_type"
assert_file_contains "$DOMAIN" "applies_when" \
  "AC5: architecture decisions carry the knowledge-track field"
assert_file_contains "$DOMAIN" "Score Overlap Before Writing" \
  "AC5: architecture decisions are overlap-scored per /learn"
assert_file_matches "$SKILLS/learn/SKILL.md" '^### .*Score Overlap Before Writing' \
  "AC5: the cited /learn overlap heading exists"
assert_file_contains "$DOMAIN" "file:line" \
  "AC5: code cross-reference cites file:line"
assert_file_matches "$DOMAIN" '[Ss]cenario' \
  "AC5: relationships are stress-tested with concrete scenarios"
assert_file_contains "$DOMAIN" "The offer is a frontier question" \
  "AC5: an architecture decision is offered as a frontier question, never assumed"

# ── AC 6: /writing-skills documents the true exception ──────────────────────
assert_file_contains "$WRITING" "disable-model-invocation: false" \
  "AC6: writing-skills states the false default"
assert_file_contains "$WRITING" "disable-model-invocation: true" \
  "AC6: writing-skills states the true exception"
assert_file_contains "$WRITING" "/grill-me" \
  "AC6: writing-skills names /grill-me as the exception's example"
assert_prose_contains "$WRITING" "front door" \
  "AC6: writing-skills scopes the exception to user-only front doors"
assert_prose_contains "$WRITING" "route through the Skill tool" \
  "AC6: writing-skills tells the author to check the harness routing"

# ── AC 7: the upstream is registered for the drift checker ───────────────────
assert_file_contains "$UPSTREAMS" '"id": "mattpocock-skills"' \
  "AC7: registry identifies the mattpocock import"
assert_file_contains "$UPSTREAMS" '"url": "https://github.com/mattpocock/skills.git"' \
  "AC7: registry names the upstream url"
assert_file_contains "$UPSTREAMS" "$BASELINE" \
  "AC7: registry pins the reviewed baseline"
for path in "LICENSE" "skills/productivity/grilling/SKILL.md" \
            "skills/productivity/grill-me/SKILL.md" \
            "skills/engineering/domain-modeling/SKILL.md"; do
  assert_file_contains "$UPSTREAMS" "\"$path\"" \
    "AC7: registry scopes $path"
done
# ref and source_notice belong to this one source, so read them out of its
# object rather than matching a value every registered source shares.
mp_source="$(python3 -c 'import json, sys
sources = json.load(open(sys.argv[1], encoding="utf-8"))["sources"]
source = [s for s in sources if s["id"] == "mattpocock-skills"][0]
print(source["ref"] + "|" + source["source_notice"])' "$UPSTREAMS")"
assert_eq "refs/heads/main|THIRD_PARTY_NOTICES.md" "$mp_source" \
  "AC7: mattpocock-skills tracks refs/heads/main and names THIRD_PARTY_NOTICES.md"
# The checker must accept the registry. A near-zero deadline keeps the run off
# the network and forces one deterministic outcome: validation passes, then
# every fetch stops at the deadline (status 1, "unavailable"). Status 2 is an
# invalid registry; anything else means the checker never ran.
drift_out="$(python3 scripts/check-upstream-drift.py --registry "$UPSTREAMS" --deadline-seconds 0.000001 2>&1)"
drift_rc=$?
assert_not_contains "$drift_out" "invalid registry" \
  "AC7: check-upstream-drift.py accepts the registry"
assert_eq "1" "$drift_rc" \
  "AC7: checker reaches the fetch stage (status 1, not a configuration error)"
assert_contains "$drift_out" "unavailable: mattpocock-skills" \
  "AC7: checker validated the mattpocock source and stopped at the network deadline"

# ── AC 8: attribution links the four upstream files at the pinned revision ───
assert_file_matches "$NOTICES" '^## .*Matt Pocock' \
  "AC8: notices carry a Matt Pocock skills section"
for path in "LICENSE" "skills/productivity/grilling/SKILL.md" \
            "skills/productivity/grill-me/SKILL.md" \
            "skills/engineering/domain-modeling/SKILL.md"; do
  assert_file_contains "$NOTICES" "$UPSTREAM_BLOB/$path" \
    "AC8: notices link $path at the pinned revision"
done
assert_file_contains "$NOTICES" "Copyright (c) 2026 Matt Pocock" \
  "AC8: notices quote the upstream copyright line"

# ── AC 9: registration on the three inventory surfaces + README credit ──────
for skill in grilling grill-me; do
  assert_file_matches "CLAUDE.md" "^\\| \`/$skill\`" \
    "AC9: CLAUDE.md skills table lists /$skill"
  assert_file_matches "README.md" "^\\| \`/$skill\`" \
    "AC9: README skills table lists /$skill"
  assert_file_contains "$BANNER" "/$skill " \
    "AC9: session-start banner lists /$skill"
done
sources="$(awk '/^## Sources/{p=1} p' README.md)"
assert_contains "$sources" "mattpocock/skills" \
  "AC9: README § Sources credits mattpocock/skills"

finish
