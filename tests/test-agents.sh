# tests/test-agents.sh — .agents/agents/ canonical layer integrity.
#
# Verifies:
#   - every canonical agent has name + description frontmatter (required by
#     pi-subagents discovery)
#   - no canonical agent pins a model (routing is per-harness; see
#     .agents/agents/README.md)
#   - every .claude/agents/ persona has a canonical counterpart
#   - no agent's frontmatter carries the plain-scalar constructs that break the
#     YAML parse and silently deregister the persona (see § 4)
#   - every persona model-routing.md § Agents names has a file in both trees (see § 5)
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CANONICAL=".agents/agents"
CLAUDE=".claude/agents"

# Report frontmatter constructs that abort the YAML parse and so silently
# deregister a persona. Emits one `<problem> <key>` line per hazard, or the bare
# token `no-frontmatter` when no block was found at all.
#
# Emitting `no-frontmatter` rather than nothing is the point: "clean" and "I had
# nothing to look at" must not be the same signal, or the guard evaporates the
# moment a file stops looking the way it does today.
#
# Line endings: worktree checkouts here are CRLF (core.autocrlf=true) while git
# blobs and the Linux CI checkout are LF, so \r is stripped to make both work.
# A UTF-8 BOM is tolerated for the same reason — PowerShell redirection in this
# environment writes one, and a BOM would otherwise hide the whole block.
#
# Deliberately NOT shared with scan_frontmatter() in test-skill-frontmatter.sh:
# that one extracts field values in a single pass for speed, this one classifies
# malformedness. Merging them would trade a real cost (awk spawns dominate this
# suite's runtime on Windows) for a cosmetic one.
# Usage: frontmatter_hazards <file> <expected-name>
frontmatter_hazards() {
  awk -v want="$2" '
    NR == 1 { if (substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4) }
    { sub(/\r$/, "") }
    NR == 1 && /^---[[:space:]]*$/ { inside = 1; found = 1; next }
    inside && /^---[[:space:]]*$/  { inside = 0; next }
    inside && /^[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]/ {
      key = $0; sub(/:[[:space:]].*/, "", key)
      val = $0; sub(/^[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      first = substr(val, 1, 1); last = substr(val, length(val), 1)
      if (key == "name")        { seen_name = 1; bare = val; gsub(/^["'\'']|["'\'']$/, "", bare) }
      if (key == "description") seen_desc = 1
      # Block scalars carry anything; their body is not this line.
      if (first == "|" || first == ">") next
      # A BALANCED quoted scalar may legally contain ": ". An unbalanced one is
      # itself the parse error, so it must not take the bypass — that is the
      # shape a half-applied "just quote it" fix produces.
      if (first == "\"" || first == "'\''") {
        if (length(val) > 1 && last == first) next
        print "unbalanced-quote " key; next
      }
      # A plain scalar may not OPEN with a YAML indicator character.
      if (index("@`%*&!,[]{}#", first) > 0) print "reserved-indicator " key
      # ": " opens a nested mapping; a trailing bare ":" does the same at EOL.
      if (val ~ /:([[:space:]]|$)/) print "colon-in-plain-scalar " key
      # " #" opens a comment: the value is silently TRUNCATED, not rejected, so
      # the persona registers with a mangled description and nothing errors.
      if (val ~ /[[:space:]]#/) print "inline-comment-truncation " key
    }
    END {
      if (!found) { print "no-frontmatter"; exit }
      if (!seen_name) print "missing-name"
      if (!seen_desc) print "missing-description"
      # The harness registers by the `name:` VALUE, not the filename. A mismatch
      # parses cleanly and still dispatches as "agent type not found" — the same
      # symptom as a parse error, from a different cause.
      if (seen_name && want != "" && bare != want) print "name-filename-mismatch " bare
    }
  ' "$1"
}

# Emit the agent names model-routing.md § Agents routes to, one per line. Scoped to
# that section so the Finding Model and Skills tables (same row shape) do not
# leak in. Callers must check the count — see the floor assertion in § 5.
claude_md_agent_names() {
  awk '
    { sub(/\r$/, "") }
    /^## Agents/ { inside = 1; next }
    inside && /^## /                { exit }
    inside && /^\| `[a-z0-9-]+` \|/ { sub(/^\| `/, ""); sub(/`.*/, ""); print }
  ' .agents/references/model-routing.md
}

# 1. Frontmatter validity + no model pin in canonical agents
for f in "$CANONICAL"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  assert_file_contains "$f" "name:" "Agents: $base has name frontmatter"
  assert_file_contains "$f" "description:" "Agents: $base has description frontmatter"
  if grep -qE '^model: ' "$f"; then
    _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
    printf '  FAIL Agents: %s must not pin a model (routing lives in per-harness settings)\n' "$base"
  else
    _TESTS=$((_TESTS + 1)); printf '  ok   Agents: %s is model-agnostic\n' "$base"
  fi
done

# 2. Every Claude agent persona has a canonical counterpart
for f in "$CLAUDE"/*.md; do
  base="$(basename "$f")"
  assert_eq "present" "$([ -f "$CANONICAL/$base" ] && echo present || echo missing)" \
    "Agents: canonical counterpart exists for .claude/agents/$base"
done

# 3. The four review personas emit all four finding axes (Tier 2 / M2).
#
# These are the agents whose output feeds the severity-enforcement tables in
# /wrap-up-session and /quality-gate. A persona that emits only `severity` sends
# a finding with no confidence downstream, where it degrades to anchor 50 and is
# never applied -- so a silently dropped axis reads as "reviewer found nothing
# actionable". Pinned per axis and per enum value in BOTH trees.
for base in code-reviewer critic security-reviewer software-design-expert-review; do
  for f in "$CANONICAL/$base.md" "$CLAUDE/$base.md"; do
    for axis in severity confidence autofix_class owner; do
      assert_file_contains "$f" "$axis" "Findings: $f emits the $axis axis"
    done
    for value in gated_auto manual advisory; do
      assert_file_contains "$f" "$value" "Findings: $f names the $value autofix class"
    done
    # Evidence gate at anchor 75+ -- the rule that keeps a confident-sounding
    # guess from being auto-applied.
    assert_file_contains "$f" "file:line" "Findings: $f requires file:line evidence"
    assert_file_contains "$f" "evidence" "Findings: $f names the evidence field"
  done
done

# 4. Frontmatter must survive a YAML parse, or the harness never registers it.
#
# Observed failure: dispatching `code-reviewer` returned "Agent type
# 'code-reviewer' not found" while the file sat on disk with the right `name:`.
# The cause was the `description:` value — an unquoted plain scalar carrying
# prose like "Context: the user wants ..." and "user: \"...\"". YAML forbids
# ": " inside a plain scalar (it reads as a nested mapping), so the whole block
# fails to parse and the persona is dropped.
#
# That is why every other invariant here passed while the agent was unusable:
# the file existed, the name matched, parity held. Only the parse was broken.
# Quote the value, use a block scalar, or keep the description colon-free.
# 4a. Self-test the detector against fixtures, so it can catch its OWN
# regression. Without this every assertion below is an `ok` on a healthy file,
# and a detector quietly reduced to a no-op would still report a green suite.
FIXDIR="$(mktemp -d)"
trap 'rm -rf "$FIXDIR"' EXIT

fixture() { printf '%s' "$2" > "$FIXDIR/$1"; }
# Each hazardous fixture is a shape verified to break a real YAML load, or (for
# the last two) to register the persona under something other than its filename.
fixture clean.md          '---
name: clean
description: A perfectly ordinary sentence with no indicators.
---
body'
fixture quoted.md         '---
name: quoted
description: "Quoted: colons are legal inside balanced quotes"
---
body'
fixture colon.md          '---
name: colon
description: Examples: Context: the shape that broke registration.
---
body'
fixture trailing.md       '---
name: trailing
description: Ends in a bare colon like Examples:
---
body'
fixture unbalanced.md     '---
name: unbalanced
description: "opened but never closed
---
body'
fixture indicator.md      '---
name: indicator
description: @mention-driven reviewer
---
body'
fixture comment.md        '---
name: comment
description: Review PRs #fast and thorough
---
body'
fixture mismatch.md       '---
name: something-else
description: Parses fine, registers under the wrong type name.
---
body'
fixture nofm.md           '# no frontmatter at all

description: Context: this must not read as clean.'

for case in clean:0 quoted:0 colon:1 trailing:1 unbalanced:1 indicator:1 comment:1 mismatch:1 nofm:1; do
  name="${case%%:*}"; want="${case##*:}"
  got="$(frontmatter_hazards "$FIXDIR/$name.md" "$name")"
  assert_eq "$want" "$([ -n "$got" ] && echo 1 || echo 0)" \
    "Agents: detector self-test — $name.md $([ "$want" = 1 ] && echo 'is flagged' || echo 'is clean')"
done

# 4b. Sweep the real personas.
for f in "$CANONICAL"/*.md "$CLAUDE"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  _TESTS=$((_TESTS + 1))
  # An unreadable file makes awk exit non-zero and print nothing; without this
  # branch that is indistinguishable from "clean".
  if ! hazards="$(frontmatter_hazards "$f" "${base%.md}")"; then
    _FAILS=$((_FAILS + 1))
    printf '  FAIL Agents: %s could not be scanned for frontmatter\n' "$f"
  elif [ -n "$hazards" ]; then
    _FAILS=$((_FAILS + 1))
    printf '  FAIL Agents: %s has frontmatter the harness cannot register (%s)\n' \
      "$f" "$(printf '%s' "$hazards" | tr '\n' ';')"
  else
    printf '  ok   Agents: %s frontmatter is registerable\n' "$f"
  fi
done

# 5. Every persona model-routing.md § Agents names must exist in both trees.
#
# The mirror of check 2, which only walks disk -> docs and so cannot see a
# documented agent with no file at all. /wrap-up-session and /quality-gate
# dispatch these by name straight out of the table, so a name with no file is a
# runtime "agent type not found", not a documentation nit.
#
# LIMIT: this is a static check. It proves a file exists for every documented
# name; it cannot prove the harness actually registered the persona — that
# depends on the runtime agent loader and is not observable from the repo.
# Check 4 covers the one registration failure mode that IS visible on disk
# (unparseable frontmatter). A persona can still pass both and fail to register
# for reasons only a live session would reveal.
CLAUDE_MD_AGENTS="$(claude_md_agent_names)"
CLAUDE_MD_AGENT_COUNT="$(printf '%s\n' "$CLAUDE_MD_AGENTS" | grep -c '[^[:space:]]' || true)"
CANONICAL_AGENT_COUNT="$(ls "$CANONICAL"/*.md | grep -vc '/README\.md$' || true)"

# Floor first. A zero-iteration loop registers zero assertions and still exits
# 0, so if the extractor stops matching -- heading renamed, table columns
# reordered, pipe spacing reflowed by a formatter -- the whole check deletes
# itself silently. Pin the count to the files on disk so drift is loud.
if [ "$CLAUDE_MD_AGENT_COUNT" -lt "$CANONICAL_AGENT_COUNT" ]; then
  _TESTS=$((_TESTS + 1)); _FAILS=$((_FAILS + 1))
  printf '  FAIL Agents: model-routing.md §%s Agents yielded %s names but %s persona files exist — table or heading drifted\n' \
    ' ' "$CLAUDE_MD_AGENT_COUNT" "$CANONICAL_AGENT_COUNT"
else
  _TESTS=$((_TESTS + 1))
  printf '  ok   Agents: model-routing.md Agents table yields %s names (>= %s on disk)\n' \
    "$CLAUDE_MD_AGENT_COUNT" "$CANONICAL_AGENT_COUNT"
fi

for agent in $CLAUDE_MD_AGENTS; do
  for tree in "$CANONICAL" "$CLAUDE"; do
    # Plain `if` rather than a $(...) subshell per assertion: process spawn
    # dominates this suite's runtime on Windows (see test-skill-frontmatter.sh).
    if [ -f "$tree/$agent.md" ]; then found=present; else found=missing; fi
    assert_eq "present" "$found" \
      "Agents: model-routing.md routes to \`$agent\` and $tree/$agent.md exists"
  done
done

finish
