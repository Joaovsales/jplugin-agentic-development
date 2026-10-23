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
under_test .agents/agents >/dev/null

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
  # Routing lives in per-harness settings, so a canonical persona pins no model.
  assert_file_not_matches "$f" '^model: ' "Agents: $base is model-agnostic"
done

# 2. Every Claude agent persona has a canonical counterpart
for f in "$CLAUDE"/*.md; do
  base="$(basename "$f")"
  assert_file_exists "$CANONICAL/$base" \
    "Agents: canonical counterpart exists for .claude/agents/$base"
done

# 3. The four review personas emit all four finding axes (Tier 2 / M2).
#
# These are the agents whose output feeds the severity-enforcement tables in
# /wrap-up-session and /quality-gate. A persona that emits only `severity` sends
# a finding with no confidence downstream, where it degrades to anchor 50 and is
# never applied -- so a silently dropped axis reads as "reviewer found nothing
# actionable". Pinned per axis and per enum value in BOTH trees.
for base in code-reviewer critic security-reviewer software-design-expert-review test-engineer; do
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
FIXDIR="$(fixture_dir)"

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
  if [ "$want" = 1 ]; then
    assert_true "Agents: detector self-test — $name.md is flagged" -- test -n "$got"
  else
    assert_true "Agents: detector self-test — $name.md is clean" -- test -z "$got"
  fi
done

# 4b. Sweep the real personas.
for f in "$CANONICAL"/*.md "$CLAUDE"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  # An unreadable file makes awk exit non-zero and print nothing; without this
  # branch that is indistinguishable from "clean".
  if ! hazards="$(frontmatter_hazards "$f" "${base%.md}")"; then
    fail "Agents: $f could not be scanned for frontmatter"
  elif [ -n "$hazards" ]; then
    fail "Agents: $f has frontmatter the harness cannot register" "$hazards"
  else
    pass "Agents: $f frontmatter is registerable"
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

# The table must name at least as many personas as there are files, so a heading
# renamed or a column reordered cannot leave the loop below with nothing to walk.
# (A file that asserts nothing at all is lib.sh's finish to catch, not this one.)
assert_true "Agents: model-routing.md Agents table yields $CLAUDE_MD_AGENT_COUNT names (>= $CANONICAL_AGENT_COUNT on disk)" \
  -- test "$CLAUDE_MD_AGENT_COUNT" -ge "$CANONICAL_AGENT_COUNT"

for agent in $CLAUDE_MD_AGENTS; do
  for tree in "$CANONICAL" "$CLAUDE"; do
    assert_file_exists "$tree/$agent.md" \
      "Agents: model-routing.md routes to \`$agent\` and $tree/$agent.md exists"
  done
done

# specs/wrap-up-phases.md AC9. Since #188 /wrap-up-session reuses the quality
# receipt and dispatches no reviewer, so a persona description naming it as a
# dispatcher routes the harness toward a call that never happens.
for tree in "$CANONICAL" "$CLAUDE"; do
  desc="$(grep -m1 '^description:' "$tree/code-reviewer.md")"
  assert_contains "$desc" "/quality-gate" \
    "Agents: $tree/code-reviewer.md names /quality-gate as its dispatcher"
  assert_not_contains "$desc" "/wrap-up-session" \
    "Agents: $tree/code-reviewer.md no longer claims /wrap-up-session dispatches it"
done

# --- 6. One shortcut rule, one home (specs/review-load-and-failure-cases.md AC2) --
# The rule used to be restated per persona — the security clause in two, the
# "limit wider than written" clause in a third, the load clause nowhere — and
# each copy drifted on its own. It now lives in finding-model.md § Deferrals;
# everyone else cites it. The single-home check is the guard: a persona that
# grows its own copy again turns the count to 2.
FM=.agents/references/finding-model.md
deferrals="$(section_body "$FM" '## Deferrals')"
assert_contains "$deferrals" 'the assumed load already crosses the limit it names' \
  "AC2: § Deferrals names the load exception"
assert_contains "$deferrals" 'never-on-the-chopping-block list' \
  "AC2: § Deferrals names the never-cut exception"
assert_contains "$deferrals" 'the shortcut itself is the finding' \
  "AC2: § Deferrals makes the shortcut itself the finding"
homes=""
for f in .agents/references/*.md "$CANONICAL"/*.md; do
  case "$(tr -s '[:space:]' ' ' < "$f")" in *'load already crosses'*) homes="$homes $f" ;; esac
done
assert_eq " $FM" "$homes" \
  "AC2: the 'load already crosses' clause lives in exactly one file"
DEFERRAL_CITERS=".agents/references/review-dispatch-contract.md .agents/skills/software-design-expert-review/SKILL.md"
for tree in "$CANONICAL" "$CLAUDE"; do
  for p in critic security-reviewer software-design-expert-review; do
    DEFERRAL_CITERS="$DEFERRAL_CITERS $tree/$p.md"
  done
done
for f in $DEFERRAL_CITERS; do
  assert_prose_contains "$f" 'finding-model.md` § *Deferrals*' \
    "AC2: $f cites finding-model.md § Deferrals"
done
item5="$(grep '^| 5 |' .agents/references/review-dispatch-contract.md)"
assert_contains "$item5" '§ *Deferrals*' \
  "AC2: dispatch contract item 5 is where the citation sits"

# --- 7. Expected load (AC3) ---------------------------------------------------
# A scale finding means nothing without the load it was judged against, so the
# load is stated first and its source named. The six patterns are pinned one by
# one: a heading with an emptied list would otherwise stay green.
load="$(section_body "$FM" '## Expected load')"
assert_contains "$load" 'Load assumed: <who and how many run this> (source: <path | none found>)' \
  "AC3: § Expected load defines the Load assumed: line"
assert_contains "$load" '§ Edge Cases and § Decisions' \
  "AC3: § Expected load reads the spec first"
assert_contains "$load" '`[NON-FUNCTIONAL]`' \
  "AC3: § Expected load reads tasks/project-context.md next"
assert_contains "$load" 'the README and the deploy or routine config' \
  "AC3: § Expected load reads the README and deploy config last"
assert_contains "$load" 'one operator, one process (source: none found)' \
  "AC3: § Expected load states the no-source default"
for pattern in 'check-then-write races' 'the same work done by every process or session' \
               'state or lists that only grow' 'one query or call per item' \
               'O(n²) on input that can be large' 'per-process state that has to be shared'; do
  assert_contains "$load" "$pattern" "AC3: scale checklist names '$pattern'"
done
assert_contains "$load" 'valid only when the assumed load reaches it' \
  "AC3: a scale finding needs the load to reach it"
for tree in "$CANONICAL" "$CLAUDE"; do
  for p in critic security-reviewer software-design-expert-review; do
    assert_prose_contains "$tree/$p.md" 'finding-model.md` § *Expected load*' \
      "AC3: $tree/$p.md references § Expected load"
    assert_file_contains "$tree/$p.md" 'failure:' \
      "AC3: $tree/$p.md output carries a failure: line"
  done
done
dispatch="$(grep 'The instruction: "Review ONLY these changed files' .agents/skills/software-design-expert-review/SKILL.md)"
assert_contains "$dispatch" '`failure:` line' \
  "AC3: the software-design-expert-review dispatch instruction asks for failure:"

# --- 8. code-reviewer: a human layer, no filler (AC4) -------------------------
# The persona opened with self-praise, asked for a Strengths section and closed
# with a free-form Recommendations list — none of which the Apply Gate can parse
# or gate. The human layer replaces them: an opener, numbered findings with a
# failure case each, and closing lines that restate decisions made elsewhere.
# Presentation only (D15): the file must not grow a question to the user.
assert_files_identical "$CANONICAL/code-reviewer.md" "$CLAUDE/code-reviewer.md" \
  "AC4: code-reviewer.md is byte-identical in both trees"
CR="$CANONICAL/code-reviewer.md"
for cite in 'finding-model.md` § *Deferrals*' 'finding-model.md` § *Expected load*'; do
  assert_prose_contains "$CR" "$cite" "AC4: code-reviewer cites $cite"
done
for absent in '^## Strengths' '^## Recommendations' '[Ee]lite' '[Mm]aster craftsman' \
              '[Aa]sk for clarification' 'which (finding|one)s? (to|should I) fix'; do
  assert_file_not_matches "$CR" "$absent" "AC4: code-reviewer has no '$absent'"
done
for line in 'What this change does:' 'Load assumed:' '1. [MUST-FIX' '  failure: ' \
            'Verdict:' 'Lean: -' 'Not checked:'; do
  assert_file_contains "$CR" "$line" "AC4: code-reviewer template shows '$line'"
done
assert_prose_contains "$CR" 'a summary for the orchestrator' \
  "AC4: code-reviewer's Verdict: is a summary, not a decision"
assert_prose_contains "$CR" 'No "consider…"' "AC4: code-reviewer bans 'consider'"
assert_prose_contains "$CR" 'no style taste' "AC4: code-reviewer bans style taste"
assert_prose_contains "$CR" 'no vague worry' "AC4: code-reviewer bans vague worries"

# --- 9. test-engineer: one persona, one Review job (AC13) ---------------------
# Unlike the other .claude/agents copies it pins no model: the tier rides each
# dispatch from model-routing.md, so a pinned alias would fix it silently.
TE="$CANONICAL/test-engineer.md"
assert_files_identical "$TE" "$CLAUDE/test-engineer.md"   "AC13: test-engineer.md is byte-identical in both trees"
assert_file_not_matches "$CLAUDE/test-engineer.md" '^model:'   "AC13: the .claude copy of test-engineer pins no model"
for needle in '## Review job' 'Reviewer tier' 'an AC with no test' 'an edge case neither tested nor defined away'               'a test that reaches past the interface' 'no spec — '; do
  assert_prose_contains "$TE" "$needle" "AC13: test-engineer names '$needle'"
done
TE_TEXT="$(cat "$TE")"
for needle in '## Write job' 'Builder tier' 'context: fresh' 'an amendment that weakens a test' '> Frozen:' '> Test amended:'; do
  assert_not_contains "$TE_TEXT" "$needle" "revert: test-engineer carries no '$needle'"
done
for tree_file in .agents/references/model-routing.md config/agent-policy.toml README.md                  PI_SETUP.md .claude/AGENTS.md; do
  assert_file_contains "$tree_file" 'test-engineer' "AC13: $tree_file lists test-engineer"
done

# --- 10. software-design-expert-review: R2 and R10 follow the book (AC16) ------
for f in "$CANONICAL/software-design-expert-review.md" "$CLAUDE/software-design-expert-review.md"; do
  assert_file_matches "$f" '^\| \*\*MEDIUM\*\*[^|]*\| `SHOULD-FIX` \|[^|]*R2 \(Pass-Through' "AC16: $f rates R2 pass-through SHOULD-FIX in the severity-mapping row"
  assert_prose_contains "$f" 'cannot be understood apart' "AC16: $f defines R10 as conjoined methods that cannot be understood apart"
done

# --- floor: the doc guards count through the library only (AC 12) --------------
# pass and fail in lib.sh are the only writers of the counters, and finish fails a
# file that asserted nothing, so the hand-rolled counter bookkeeping and the
# assertion floor it fed are gone from all eight doc-guard files. lib.sh is the
# positive control: it is where the arithmetic legitimately lives.
DOC_GUARDS="tests/test-agents.sh tests/test-model-tiers.sh tests/test-skill-frontmatter.sh
            tests/test-skill-references.sh tests/test-skills-table.sh tests/test-instruction-budget.sh
            tests/test-grilling-adoption.sh tests/test-doc-conventions.sh"
# shellcheck disable=SC2086 -- the list is words by construction.
assert_sweep_empty "floor: no doc-guard test does its own counter arithmetic" tests/lib.sh \
  -- grep -nE '_(TESTS|FAILS)=\$\(\(' -- $DOC_GUARDS
# shellcheck disable=SC2086
assert_sweep_empty "floor: no doc-guard test makes its own scratch directory" tests/lib.sh \
  -- grep -nE 'mktemp [-]d' -- $DOC_GUARDS

finish
