# tests/test-doc-conventions.sh — documentation invariants across skills/config.
# Extended as P2/P4/P5 land. Pure grep assertions; no temp state.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# One flattening pipeline for every whole-file order check below.
flatten() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; }

# --- M3: retired store — the old monolith files have no live references ------
# INVERTED from the pre-M3 assertion that /build and /checkpoint reference
# tasks/memory.md. The store is now tasks/solutions/ + tasks/history.md; only
# tasks/archive/ and specs/ may name the retired files. Detection logic (e.g.
# /sync, session-start.sh) constructs the paths instead of naming them literally,
# so this sweep stays strict.
# Every swept root must exist — the `|| true` below absorbs grep's no-match
# exit, but it would also absorb a missing-path error, letting a renamed root
# silently shrink the sweep's coverage.
for root in .agents .claude/agents \
            CLAUDE.md AGENTS.md README.md install.sh project-template; do
  assert_eq "present" "$([ -e "$root" ] && echo present || echo missing)" \
    "M3: sweep root $root exists (sweep coverage intact)"
done
for old in "tasks/memory.md" "tasks/lessons.md" "tasks/bugs.md"; do
  offenders="$(grep -rlF "$old" .agents .claude/agents \
      CLAUDE.md AGENTS.md README.md install.sh project-template 2>/dev/null \
    | grep -v '\.claude/worktrees/' || true)"
  assert_eq "" "$offenders" "M3: no live reference to $old (offenders: ${offenders:-none})"
done
for f in .agents/skills/checkpoint/SKILL.md \
         .agents/skills/build/SKILL.md; do
  assert_file_contains "$f" "tasks/solutions" "M3: $f references the typed store"
done

# --- Task 5 (P2): both build copies checkpoint at task boundaries ---
for f in .agents/skills/build/SKILL.md; do
  assert_file_contains "$f" "Task-boundary checkpoint" "Task5: $f checkpoints at task boundary"
  assert_file_contains "$f" "pre-compact.sh" "Task5: $f reuses the shared PreCompact flush"
done

# --- Task 7 (P3): circuit breaker auto-invokes /refresh before escalating ---
for f in .agents/skills/build/SKILL.md; do
  assert_file_contains "$f" "Backstop first" "Task7: $f circuit breaker runs /refresh backstop"
done

# --- Task 6 (P3): /refresh registered in the README table (the one skills catalog) ---
assert_file_contains "README.md" "\`/refresh\`" "Task6: README skills table lists /refresh"

# --- Task 9 (P5): Large-Artifact Handoff convention + references ---
assert_file_contains "AGENTS.md" "Large-Artifact Handoff" "Task9: AGENTS.md defines the convention"
assert_file_contains "AGENTS.md" "truncate with a" "Task9: AGENTS.md states truncate-with-pointer"
for f in .agents/skills/build/SKILL.md .agents/skills/verify-deployment/SKILL.md; do
  assert_file_contains "$f" "Large-Artifact Handoff" "Task9: $f references the convention"
done

# --- visual-recap: documentation contract present in both tree copies ---
for f in .agents/skills/visual-recap/SKILL.md; do
  for token in "name: visual-recap" "argument-hint:" "Skip when trivial" \
               "true by construction" "git diff" "--name-status" "--stat" \
               "data-model" "api-endpoint" "file-tree" "keychange-" \
               "scripts/visual-render.py" "tasks/recaps/"; do
    assert_file_contains "$f" "$token" "visual-recap: $f contains '$token'"
  done
done

# --- visual-plan: documentation contract present in both tree copies ---
# The renderer token was `../visual-recap/scripts/visual-render.py` until
# test-skill-references.sh surfaced it as an escaping path: the Bash tool's cwd is
# the project root, so `../visual-recap/...` resolved OUTSIDE the repo and the
# documented command could never have run. This suite passed anyway because
# test-visual-render.sh invokes the script by an explicit absolute path -- a green
# suite over a broken skill. The pin is updated to the canonical-tree path that
# actually resolves; it is not relaxed.
for f in .agents/skills/visual-plan/SKILL.md; do
  for token in "name: visual-plan" "argument-hint:" "Skip when trivial" \
               "read-only" "specs/" ".plan.html" \
               ".agents/skills/visual-recap/scripts/visual-render.py" "file map" \
               "open questions" "wireframe" "NEW"; do
    assert_file_contains "$f" "$token" "visual-plan: $f contains '$token'"
  done
done


# --- system-design-planning: documentation contract present in both tree copies ---
# The skill replaces /brainstorm -> /plan for boundary-crossing changes, so the
# pins are the handoffs that make it interchangeable with /plan downstream: the
# fixed section order of the spec it writes, the registry-only intake and filing,
# the shared renderer, the approval gate wording, and the plan block /build reads.
for f in .agents/skills/system-design-planning/SKILL.md; do
  for token in "name: system-design-planning" "argument-hint:" \
               "disable-model-invocation: false" \
               "Skipping system-design-planning:" \
               "task-registry.py show" \
               ".agents/skills/visual-recap/scripts/visual-render.py" ".plan.html" \
               "references/review-card.md" "templates/architecture-spec-template.md" \
               "templates/content-model.json" \
               "[ ] TDD:" "### Slice" "UNVERIFIED"; do
    assert_file_contains "$f" "$token" "system-design-planning: $f contains '$token'"
  done
  # The four elements plus the build order, in the order the spec table lists them.
  # Pinned by ORDER, not by count: a reflow that swaps constraints below data
  # models silently changes what the reviewer reads first.
  flat_sdp="$(flatten "$f")"
  pos_c=$(printf '%s' "$flat_sdp" | grep -bo '| Constraints |' | head -1 | cut -d: -f1)
  pos_s=$(printf '%s' "$flat_sdp" | grep -bo '| System design |' | head -1 | cut -d: -f1)
  pos_k=$(printf '%s' "$flat_sdp" | grep -bo '| Component contracts |' | head -1 | cut -d: -f1)
  pos_d=$(printf '%s' "$flat_sdp" | grep -bo '| Data models |' | head -1 | cut -d: -f1)
  pos_b=$(printf '%s' "$flat_sdp" | grep -bo '| Build order |' | head -1 | cut -d: -f1)
  if [ -n "${pos_c:-}" ] && [ -n "${pos_s:-}" ] && [ -n "${pos_k:-}" ] && [ -n "${pos_d:-}" ] && [ -n "${pos_b:-}" ] \
     && [ "$pos_c" -lt "$pos_s" ] && [ "$pos_s" -lt "$pos_k" ] && [ "$pos_k" -lt "$pos_d" ] && [ "$pos_d" -lt "$pos_b" ]; then
    assert_eq "ordered" "ordered" "system-design-planning: $f lists the elements in dependency order"
  else
    assert_eq "constraints < system design < contracts < data models < build order" \
      "${pos_c:-missing} ${pos_s:-missing} ${pos_k:-missing} ${pos_d:-missing} ${pos_b:-missing}" \
      "system-design-planning: $f lists the elements in dependency order"
  fi
  # The gate: nothing is filed or built in this session; the reviewer approves
  # by starting the build session with the printed prompt instead.
  assert_contains "$flat_sdp" \
    "NOTHING IS FILED AND NOTHING IS BUILT IN THE PLANNING SESSION. THE REVIEWER STARTS THE BUILD SESSION WITH THE BUILD PROMPT." \
    "system-design-planning: $f carries the approval iron law"
  assert_file_contains "$f" "filed in the planning session" \
    "system-design-planning: $f's Red Flag names filing in the planning session"
  # The path is printed before the gate asks, so the reviewer opens the file
  # the approval attaches to. Pinned by ORDER: the line must precede Step 7.
  pos_v=$(printf '%s' "$flat_sdp" | grep -bo '✓ Visual written:' | head -1 | cut -d: -f1)
  pos_g=$(printf '%s' "$flat_sdp" | grep -bo '### 7. Review Loop' | head -1 | cut -d: -f1)
  if [ -n "${pos_v:-}" ] && [ -n "${pos_g:-}" ] && [ "$pos_v" -lt "$pos_g" ]; then
    assert_eq "ordered" "ordered" "system-design-planning: $f prints the render path before the gate"
  else
    assert_eq "visual written < review gate" "${pos_v:-missing} ${pos_g:-missing}" \
      "system-design-planning: $f prints the render path before the gate"
  fi
  # Every intake form the skill accepts is in the hint, so a caller sees them.
  assert_file_contains "$f" 'argument-hint: "[#issue | task-id | feature idea or problem statement]"' \
    "system-design-planning: $f advertises every intake form"
  # Tracker access is registry-only (AGENTS.md § Task Tracking); a direct gh
  # call is the regression this pin exists to catch.
  assert_file_not_matches "$f" '\bgh (issue|api|pr)\b' \
    "system-design-planning: $f never calls gh directly"
done

# The spec template is the section order every design inherits; the review
# card is the 25 dependency-ordered questions the self-review walks. Both are
# pinned by the smallest falsifiable unit — heading order and question ids —
# never by prose.
tmpl=.agents/skills/system-design-planning/templates/architecture-spec-template.md
assert_eq "Problem Constraints System design Component contracts Data models Build order Decisions Acceptance Criteria Implementation Paths" \
  "$(grep '^## ' "$tmpl" | tr -d '\r' | sed 's/^## //' | paste -sd ' ' -)" \
  "system-design-planning: spec template carries the nine sections in order"
card=.agents/skills/system-design-planning/references/review-card.md
assert_eq "C1 C2 C3 C4 C5 S1 S2 S3 S4 S5 K1 K2 K3 K4 K5 D1 D2 D3 D4 D5 B1 B2 B3 B4 B5" \
  "$(grep -oE '^\| [CSKDB][1-5] ' "$card" | tr -d '| ' | paste -sd ' ' -)" \
  "system-design-planning: review card carries the 25 questions in dependency order"
# The plan block nests TDD rows under a registry row; /build must know not to
# build that row, or the first design plan dispatches a coder against a title.
for tree in .agents; do
  assert_file_contains "$tree/skills/build/SKILL.md" "slice header" \
    "system-design-planning: $tree/build names the slice header row it must not build"
done
# Registration in the one listing a new skill must appear in (the AGENTS.md
# managed block carries no skills table and the banner lists none — README is
# the one catalog).
assert_file_contains "README.md" "\`/system-design-planning\`" \
  "system-design-planning: README skills table lists it"

# --- tidy: harness-hygiene contract present in both tree copies ---
# specs/tidy-skill.md. /tidy is neither a producer nor a consumer under the
# routine contract: it fixes Tier 0 tree content in place, prints Tier 1
# remedies as commands, and files Tier 2 through the registry. The pins are the
# laws that keep it from doing more than that -- clean tree, red suite first, a
# retired set computed from history, the operator's machine untouched, no
# worktree removed without forge evidence -- plus the filing block the consumer
# routines' selectors depend on. Pinned by the smallest falsifiable unit: a
# frontmatter key, a table row, a flag, a section heading order.
for f in .agents/skills/tidy/SKILL.md; do
  for token in "name: tidy" 'argument-hint: "[--report] [--check <name>[,<name>]]"' \
               "disable-model-invocation: false" "harness: universal" \
               "neither a producer nor a consumer" \
               "Tier 0" "Tier 1" "Tier 2" \
               "git log --no-renames --diff-filter=D" \
               "bash install.sh" "installed_plugins.json" \
               "never executed by the skill" "Never delete unmerged work" "forge evidence" \
               "squash-merge" "git branch --merged" \
               "task-registry.py upsert" "--derive-id tidy --source" "--fold-title" \
               "--label documentation" "--label tech-debt" "discovered: tidy" \
               "publication pending" "is not a destination" \
               "require_write_approval = false" "TASK_REGISTRY_TRUSTED_CONFIG=1" \
               "external issue is the record" \
               "git status --porcelain" \
               "Clean tree or stop" "Red suite first" "One concern per commit" \
               "Never on the default branch" \
               "tasks/sweeps/<YYYY-MM-DD>-tidy.md" "opens no pull request" \
               "/tidy --report" "/tidy --check" \
               "no commits, no \`upsert --apply\`" "never folded into" \
               "## Allowlist" "CLAUDE.local.md — " "installed:" "graphify — " \
               "'.claude/skills/*/SKILL.md'" "headRefOid" "--untracked-files=no" \
               "is-shallow-repository" "detached" ".claude/tidy-allowlist" \
               "unshipped, provenance unknown" "routine/tidy/<YYYYMMDD>-sweep" \
               "routine-prompts/tidy.md"; do
    assert_file_contains "$f" "$token" "tidy: $f contains '$token'"
  done
  flat_tidy="$(flatten "$f")"
  # AC-2: nine checks, each a table row naming the surfaces it reads, and a
  # surface the host repository lacks is skipped rather than reported.
  for check in suite inventory retired installed refs worktrees strays registers graph; do
    assert_file_matches "$f" "^\| \`$check\` \|" \
      "tidy: $f defines the \`$check\` check as a table row"
  done
  # The banner lists no skills since specs/single-instruction-file.md slice 3, so
  # it is not an inventory surface any more.
  assert_file_not_matches "$f" 'SKILLS AVAILABLE' \
    "tidy: $f inventory no longer reads a banner skills list"
  assert_file_matches "$f" '^\| `graph` \| `command -v graphify`' \
    "tidy: $f graph check reads graphify and the graph file"
  assert_file_matches "$f" '^\| `registers` \| `tasks/todo.md`, `tasks/checkpoint.md` \|' \
    "tidy: $f registers reads the two task registers"
  assert_contains "$flat_tidy" "skipped with a note" \
    "tidy: $f skips a missing surface instead of reporting it"
  # AC-4: history is exempt from the retired sweep.
  assert_contains "$flat_tidy" "every file outside \`tasks/\` and \`specs/\`" \
    "tidy: $f exempts tasks/ and specs/ from the retired check"
  # AC-5: the machine is the operator's -- the prohibition names its objects.
  assert_contains "$flat_tidy" "**never modifies** \`~/.claude/\` or \`~/.agents/\`" \
    "tidy: $f never modifies the installed copies"
  # AC-7: the label mapping, not the two labels' presence.
  assert_contains "$flat_tidy" "Documentation drift → \`--label documentation\`" \
    "tidy: $f maps documentation drift to the documentation label"
  assert_contains "$flat_tidy" "→ \`--label tech-debt\` (selected by \`fix\`)" \
    "tidy: $f maps structural drift to the tech-debt label"
  # AC-8: the write-policy table and its one excluded destination.
  assert_contains "$flat_tidy" "local record is canonical" \
    "tidy: $f states the local-canonical row of the write policy"
  assert_contains "$flat_tidy" "\`tasks/backlog.md\` is not a destination" \
    "tidy: $f refuses backlog.md as a destination"
  # AC-9: tracker access is registry-only. The repo-wide coupling guard below
  # covers this too; the explicit pin names the skill when it regresses.
  assert_file_not_matches "$f" "gh issue|/rest/api/" \
    "tidy: $f never calls a tracker's task API"
  assert_file_not_matches "$f" "gh pr (create|merge)" \
    "tidy: $f opens no pull request itself"
  # AC-10: the default branch is named, not implied.
  assert_contains "$flat_tidy" "\`master\`/\`main\`" \
    "tidy: $f names the default branches it refuses to commit on"
  # AC-11: the six session-record sections in /sweep's order. Pinned by ORDER:
  # a consumer routine reads *Filed* by position in the record, not by search.
  pos_sc=$(printf '%s' "$flat_tidy" | grep -bo '\*\*Scope\*\*' | head -1 | cut -d: -f1)
  pos_cg=$(printf '%s' "$flat_tidy" | grep -bo '\*\*Coverage gaps\*\*' | head -1 | cut -d: -f1)
  pos_fi=$(printf '%s' "$flat_tidy" | grep -bo '\*\*Filed\*\*' | head -1 | cut -d: -f1)
  pos_un=$(printf '%s' "$flat_tidy" | grep -bo '\*\*Unverified\*\*' | head -1 | cut -d: -f1)
  pos_in=$(printf '%s' "$flat_tidy" | grep -bo '\*\*Independence\*\*' | head -1 | cut -d: -f1)
  pos_sl=$(printf '%s' "$flat_tidy" | grep -bo '\*\*Step ledger\*\*' | head -1 | cut -d: -f1)
  if [ -n "${pos_sc:-}" ] && [ -n "${pos_cg:-}" ] && [ -n "${pos_fi:-}" ] && [ -n "${pos_un:-}" ] \
     && [ -n "${pos_in:-}" ] && [ -n "${pos_sl:-}" ] \
     && [ "$pos_sc" -lt "$pos_cg" ] && [ "$pos_cg" -lt "$pos_fi" ] && [ "$pos_fi" -lt "$pos_un" ] \
     && [ "$pos_un" -lt "$pos_in" ] && [ "$pos_in" -lt "$pos_sl" ]; then
    assert_eq "ordered" "ordered" "tidy: $f lists the six record sections in /sweep's order"
  else
    assert_eq "scope < coverage gaps < filed < unverified < independence < step ledger" \
      "${pos_sc:-missing} ${pos_cg:-missing} ${pos_fi:-missing} ${pos_un:-missing} ${pos_in:-missing} ${pos_sl:-missing}" \
      "tidy: $f lists the six record sections in /sweep's order"
  fi
  # Law 8: every allowlist entry carries a reason. An entry is a non-blank line
  # inside the fence under the Allowlist heading; a bare path is not an entry.
  bare_entries="$(awk '
    /^## Allowlist/ { on = 1; next }
    on && /^## /     { on = 0 }
    on && /^```/     { fence = !fence; next }
    on && fence && NF && !/ — / { bad++ }
    END { print bad + 0 }
  ' "$f")"
  assert_eq "0" "$bare_entries" "tidy: $f allowlist entries all carry a reason"
done
# Registration in the one listing a new skill must appear in. AGENTS.md
# carries no skills table and the banner lists none, so neither is a listing
# here -- the same rule the skill's own `inventory` check applies to a missing
# surface.
assert_file_matches "README.md" '^\| `/tidy`' \
  "tidy: README skills table lists it"

# --- Banned construct: load-time shell pre-resolution in skill bodies ---
# A SKILL.md line of the form  !`cmd`  runs cmd when the SKILL LOADS and inlines
# its stdout. It is banned outright here for two reasons that cannot be guarded
# around:
#   1. It is Claude-Code-only. On Pi the line is inert literal text, so any skill
#      depending on the inlined value is already broken on the other harness.
#   2. On Claude Code a non-zero exit ABORTS skill load with a user-facing error.
#      Every plausible use is git/gh context (`git rev-parse`, `gh pr view`) whose
#      non-zero exit is a NORMAL state -- no PR yet, detached HEAD, not a repo --
#      so the ordinary case would break the skill. The POSIX guards that force
#      exit 0 (`2>/dev/null || echo X`) then fail to PARSE under PowerShell.
# Gather context at runtime with one argv-style command per tool call instead.
# The `!\[` exclusion keeps markdown image syntax from matching.
while IFS= read -r f; do
  hits="$(grep -n '![`]' "$f" 2>/dev/null | grep -cv '!\[' || true)"
  assert_eq "0" "${hits:-0}" "BannedConstruct: $f has no load-time !\`cmd\` pre-resolution"
done <<INNER_EOF
$(find .agents/skills -name '*.md' -not -path '*/.claude/worktrees/*' | sort)
INNER_EOF

# --- Tier 2 (M1): independence accounting -----------------------------------
# Corroboration is only evidence when the findings came from separately
# dispatched contexts. The regression this guards is a skill quietly promoting a
# finding because two lenses inside ONE context agreed.
# These docs are hard-wrapped prose, so a pinned multi-word phrase can straddle a
# newline. Match against a whitespace-collapsed rendering: the guard is about the
# rule being stated, not about where the paragraph happens to wrap.
#
# `tr -d '\r'` first, and it is not optional. These files are checked out with CRLF
# on Windows, so collapsing only '\n' leaves the '\r' behind and "dispatched\r
# contexts" never matches "dispatched contexts". Without it the guard passes in a
# worktree whose files were authored with LF and fails on a fresh clone of the same
# commit -- which is exactly what it did.

assert_file_contains ".agents/references/finding-model.md" "## Independence Accounting" \
  "M1: finding-model.md has an Independence Accounting section"
assert_contains "$(flatten .agents/references/finding-model.md)" "separately dispatched contexts" \
  "M1: finding-model.md requires separately dispatched contexts for corroboration"

taxonomy="$(sed -n '/^## Review Gate Taxonomy/,/^## Core Principles/p' AGENTS.md | tr -d '\r' | tr '\n' ' ' | tr -s ' ')"
assert_contains "$taxonomy" "Independence Accounting" \
  "M1: Review Gate Taxonomy cross-references Independence Accounting"
assert_contains "$taxonomy" "Finding Model" \
  "M1: Review Gate Taxonomy cross-references the Finding Model"

# --- Tier 2 (M2): four-axis findings in the finding model and both review skills -----
# Each axis, enum value, and confidence anchor is pinned as its own token. A
# dropped enum value is exactly what would let an unsure finding auto-apply, and
# it is invisible in a whole-block snapshot. `wrap-up-session` is not among them
# since #188: it dispatches no reviewer of its own and applies no finding, so it
# defines none of this machinery -- `/quality-gate` is the one place a finding
# is classified.
for f in .agents/references/finding-model.md \
         .agents/skills/quality-gate/SKILL.md \
         .agents/skills/software-design-expert-review/SKILL.md; do
  flat="$(flatten "$f")"
  for axis in severity confidence autofix_class owner; do
    assert_contains "$flat" "\`$axis\`" "M2: $f defines the \`$axis\` axis"
  done
  for value in gated_auto manual advisory release; do
    assert_contains "$flat" "\`$value\`" "M2: $f names the \`$value\` enum value"
  done
  for anchor in 50 75 100; do
    assert_contains "$flat" "\`$anchor\`" "M2: $f names confidence anchor \`$anchor\`"
  done
  # Evidence gate: 75+ requires file:line, and its absence demotes rather than drops.
  assert_contains "$flat" "file:line" "M2: $f requires file:line evidence"
  assert_contains "$flat" "demote" "M2: $f demotes on missing evidence"
  # Apply gate: the conjunction is the gate. Either half alone is the bug.
  assert_contains "$flat" "confidence >= 75" "M2: $f gates auto-apply at anchor 75+"
  # Backwards compatibility: an old single-axis finding is neither applied nor lost.
  assert_contains "$flat" "no \`confidence\`" \
    "M2: $f handles a finding arriving with no confidence"
  # Synthesis never widens the autofix class on disagreement.
  assert_contains "$flat" "more conservative" \
    "M2: $f takes the more conservative autofix_class on disagreement"
done

# /quality-gate must disclose whether its passes were dispatched or ran inline,
# and must not promote on same-context agreement. `wrap-up-session` carries no
# Dispatch Disclosure requirement of its own since #188 -- it reuses the gate's
# receipt rather than running a review pass, so there is nothing here for it to
# disclose.
for f in .agents/skills/quality-gate/SKILL.md; do
  assert_file_contains "$f" "Dispatch Disclosure" \
    "M1: $f carries a Dispatch Disclosure requirement"
  assert_file_contains "$f" "Review independence:" \
    "M1: $f emits the independence line in its output block"
done

# /software-design-expert-review dispatches its reviewer per file-batch, so its
# independence question is batching, not dispatch-vs-inline. Two batches naming the
# same file:line corroborate; two lenses inside one batch do not. It must also stop
# telling the agent to emit the old single-axis format -- that instruction would
# override the persona and degrade every finding to anchor 50.
for f in .agents/skills/software-design-expert-review/SKILL.md; do
  assert_file_contains "$f" "Review independence:" \
    "M1: $f emits the independence line in its output block"
  assert_contains "$(flatten "$f")" "separately dispatched" \
    "M1: $f promotes only on separately dispatched batches"
  if grep -qF 'format only."' "$f"; then
    assert_eq "absent" "present" \
      "M2: $f must not instruct the agent to emit single-axis findings"
  else
    assert_eq "absent" "absent" \
      "M2: $f must not instruct the agent to emit single-axis findings"
  fi
done

# --- Tier 2 (M2): unattended loops route a non-auto-appliable MUST-FIX -------
# The apply gate narrows what may be auto-applied, so a MUST-FIX can now be
# unappliable. In an unattended loop that must reach the existing FAIL/STOP
# path, never a user prompt.
for f in .agents/skills/yolo/SKILL.md \
         .agents/skills/auto-push/SKILL.md; do
  assert_file_contains "$f" "gated_auto" \
    "M2: $f states how a non-gated_auto MUST-FIX is routed"
done

# --- /wrap-up-session re-syncs a stale PR description ------------------------
# `gh pr create` writes the body once. Later commits falsify it and nothing
# re-reads it, so a PR can keep advertising a defect as deferred after the commit
# that fixed it already landed -- observed on PR #55. Two things are pinned: that
# the step exists, and that Step 7 no longer says "create if none exists" without
# handling the update case, which is the wording the gap lived in.
for f in .agents/skills/wrap-up-session/SKILL.md; do
  # The sync step lives inside the one canonical PR section that
  # specs/category-routines.md AC7 converged Step 7 and Step 7.5 onto.
  assert_file_contains "$f" "Creating and re-syncing" \
    "PRSync: $f carries the PR description sync step"
  assert_contains "$(flatten "$f")" "Correct, do not erase" \
    "PRSync: $f forbids silently deleting a superseded claim"
  assert_file_contains "$f" "- PR: [" \
    "PRSync: $f reports the sync outcome on the Done report's PR line"
  # The create-only wording is the defect itself, not merely incomplete docs.
  if grep -qF "Create PR if none exists" "$f"; then
    assert_eq "absent" "present" \
      "PRSync: $f must not describe PR creation as the only case"
  else
    assert_eq "absent" "absent" \
      "PRSync: $f must not describe PR creation as the only case"
  fi
done

# --- Tier 3.3 (M4): accreting concept glossary --------------------------------
# tasks/concepts.md is project vocabulary: seeded, populated once by a bootstrap
# sweep, then accreted by /learn and pruned by /memory-maintain. Pinned tokens:
# both seeds exist, the repo copy defines the six harness terms, and both carry
# the Sweep marker that keys the one-time sweep.
# The template seed must SHIP pending (downstream sweep not yet run); the repo
# copy dogfooded the sweep, so its marker may read either legal state — but only
# a legal state. A loose prefix match here would stay green while the marker
# rots into a spelling the light pass's exact grep no longer recognizes.
for f in tasks/concepts.md project-template/tasks/concepts.md; do
  assert_eq "present" "$([ -f "$f" ] && echo present || echo missing)" \
    "M4: $f exists"
  assert_eq "1" "$(grep -cE '^> Sweep: (pending|done [0-9]{4}-[0-9]{2}-[0-9]{2})$' "$f" 2>/dev/null || true)" \
    "M4: $f carries exactly one legal-state sweep marker"
done
assert_file_contains "project-template/tasks/concepts.md" "> Sweep: pending" \
  "M4: template glossary seed ships unswept"
# Anchored to the bullet form so a term surviving only in prose cannot pass.
for term in tier gate register drift ceiling store; do
  for f in tasks/concepts.md project-template/tasks/concepts.md; do
    assert_file_contains "$f" "- **$term** — " \
      "M4: $f defines '$term' as a glossary bullet"
  done
done
# /learn accretes the glossary as a side effect (no separate prompt); a file it
# bootstraps from scratch must still carry the pending marker so the sweep fires.
for f in .agents/skills/learn/SKILL.md; do
  assert_file_contains "$f" "tasks/concepts.md" \
    "M4: $f captures concepts to the glossary"
  assert_file_contains "$f" "Sweep: pending" \
    "M4: $f bootstraps an absent glossary with the sweep marker"
done
# /memory-maintain owns both glossary lifecycles: the one-time bootstrap sweep
# (keyed on the pending marker, fires from the LIGHT pass so a fresh install
# does not wait 5 sessions) and steady-state pruning in the heavy pass.
for f in .agents/skills/memory-maintain/SKILL.md; do
  assert_file_contains "$f" "tasks/concepts.md" \
    "M4: $f maintains the glossary"
  assert_file_contains "$f" "standard industry meaning" \
    "M4: $f prunes non-project-specific glossary entries"
  assert_file_contains "$f" "Phase 0" \
    "M4: $f defines the bootstrap sweep phase"
  assert_file_contains "$f" "Sweep: pending" \
    "M4: $f keys the sweep on the pending marker"
  assert_file_contains "$f" "Sweep: done" \
    "M4: $f flips the marker after the sweep"
  # Pins the fix for the one regression this feature actually shipped with: the
  # light pass's empty-store no-op swallowing Phase 0 on a fresh install. The
  # exemption clause is the smallest falsifiable unit that fails if it returns.
  assert_file_contains "$f" "runs regardless" \
    "M4: $f exempts the glossary marker check from the empty-store no-op"
done
# Registration: the glossary is a listed register in the managed block and the seed.
keydirs="$(sed -n '/^## Key Directories/,/^## Agents/p' AGENTS.md)"
assert_contains "$keydirs" "tasks/concepts.md" \
  "M4: AGENTS.md Key Directories lists tasks/concepts.md"
assert_file_contains "project-template/AGENTS.md" "concepts.md" \
  "M4: project-template AGENTS.md lists the glossary"

# --- lightpanda: JS-capable page reads offered as an OPTIONAL research fallback ---
# WebFetch returns the empty shell for a JS-rendered page and gives no signal that
# it did, so a research step can silently read nothing and report nothing found.
# `lightpanda fetch` executes the scripts. It is optional everywhere: the machines
# running this workflow differ (no Windows build exists), so each mention must say
# absence is not an error, or a skill turns a missing optional tool into a blocker.
for f in .agents/skills/prd/SKILL.md \
         .agents/skills/brainstorm/SKILL.md; do
  assert_file_contains "$f" "lightpanda fetch" \
    "lightpanda: $f offers the JS-capable fetch fallback"
  assert_prose_contains "$f" "not an error" \
    "lightpanda: $f states that its absence is not an error"
done

# --- lightpanda: the DOM tier must not leak into manual QA -------------------
# /start-qa launches a browser for a HUMAN to look at. Lightpanda has no
# rendering path, so routing manual QA to it would hand the user a browser that
# cannot show them anything. This is not a preference — it is the one place the
# tier is categorically wrong, so it is pinned rather than left to judgement.
for f in .agents/skills/start-qa/SKILL.md; do
  assert_file_not_matches "$f" "lightpanda"     "lightpanda: $f does NOT route manual QA to the DOM tier"
done

# --- agent-reach was evaluated and declined ----------------------------------
# Recorded as a guard so a later session does not quietly add the dependency the
# spec argued its way out of. specs/ is exempt: that is where the decision and
# its reversal path are written down. tests/ is exempt for the obvious reason
# that this assertion names the token itself.
reach_hits="$(grep -rl "agent-reach"   .agents .claude/agents .claude/browsers   AGENTS.md CLAUDE.md install.sh project-template 2>/dev/null | grep -vF '.claude/worktrees' || true)"
assert_eq "" "$reach_hits"   "lightpanda: agent-reach is not a dependency anywhere outside specs/"

# --- task-registry: the tracker abstraction ----------------------------------
# The capability is worth nothing if a workflow skill can still reach a tracker
# directly: the point of the abstraction is that a project can change tracker
# without editing a workflow skill. Four things are pinned — the skill is
# registered where agents look for it, the configuration contract is
# discoverable, the five workflow skills route through it, and nothing outside
# the registry itself names a provider's task API.
assert_file_contains "README.md" '`/task-registry`' \
  "task-registry: README skills table lists the skill"
assert_file_contains "AGENTS.md" "## Task Tracking" \
  "task-registry: AGENTS.md defines the task-tracking section"
# The convention is documented in the managed block, which must not itself emit
# a live pointer. The block ships to every consumer, while `docs/` is outside
# every syncable root — so a bare `Task tracking instructions: <file>` inside it
# is a pointer whose target the template can never deliver, and the loader
# refuses a pointer with no target (#82). The loader's POINTER_RE stops at a
# backtick or `<` but does not require one, so a backticked concrete path still
# matches: only the `<path>` placeholder is inert. The live pointer this
# repository does carry sits below the end marker and must resolve to a file
# this repository ships (tests/test-instruction-budget.sh pins the placement).
assert_file_contains "AGENTS.md" '`Task tracking instructions: <path>`' \
  "task-registry: AGENTS.md documents the pointer convention"
assert_file_contains "AGENTS.md" "templates/task-tracking.md" \
  "task-registry: AGENTS.md names the template a project starts its configuration from"
agents_md_pointers="$(grep -oiE 'Task tracking instructions:[[:space:]]*[^[:space:]`<>]+' AGENTS.md \
  | sed -E 's/^[^:]*:[[:space:]]*//' || true)"
for target in $agents_md_pointers; do
  assert_eq "present" "$([ -f "$target" ] && echo present || echo missing)" \
    "task-registry: live pointer in AGENTS.md resolves to a shipped file ($target)"
done
assert_prose_contains "AGENTS.md" "is an **index**, not the detailed source of truth" \
  "task-registry: AGENTS.md states that tasks/todo.md is an index"
assert_not_contains "$(flatten AGENTS.md)" \
  "a project without one gets the local Markdown provider and works offline" \
  "task-registry: absent configuration does not erase GitHub auto-selection"
assert_prose_contains "AGENTS.md" \
  "else GitHub when a GitHub remote and an authenticated \`gh\` both exist, else local Markdown" \
  "task-registry: AGENTS.md pins GitHub-before-local auto-selection"
wrap_up_gate_spec="$(flatten specs/wrap-up-gate-and-tdd-fold.md)"
assert_not_contains "$wrap_up_gate_spec" \
  "no \`docs/task-tracking.md\`, so the registry resolves to the offline local provider regardless" \
  "task-registry: wrap-up spec does not claim absent configuration forces local"
assert_contains "$wrap_up_gate_spec" "hook never invokes \`/task-registry\`" \
  "task-registry: wrap-up spec gives the real reason the hook cannot reach a tracker"
assert_file_matches "README.md" '^\| `/task-registry`' \
  "task-registry: the README skills table lists the skill"

for tree in .agents; do
  f="$tree/skills/task-registry/SKILL.md"
  assert_file_contains "$f" "Dry-run is the default" \
    "task-registry: $f states the dry-run default"
  assert_file_contains "$f" "A title is never an identity" \
    "task-registry: $f states that a title is not an identity"
  assert_prose_contains "$f" "never creates, renames, or removes a label" \
    "task-registry: $f states the label-preservation rule"
  assert_file_contains "$f" "Nothing unresolved is deleted" \
    "task-registry: $f states the no-silent-deletion rule"
  assert_prose_contains "$f" "No tracker is ever selected implicitly" \
    "task-registry: $f states that no tracker is selected implicitly"
  template="$tree/skills/task-registry/templates/task-tracking.md"
  assert_file_contains "$template" \
    "selection still prefers GitHub when a GitHub remote and an authenticated \`gh\`" \
    "task-registry: $template pins GitHub auto-selection"
  assert_file_contains "$template" \
    "both exist, then falls back to local Markdown" \
    "task-registry: $template pins the local fallback"
  # The two companion documents the skill points at must exist, or the
  # progressive-disclosure promise ("detail on demand") has nowhere to land.
  for ref in configuration progressive-disclosure; do
    assert_eq "present" \
      "$([ -f "$tree/skills/task-registry/references/$ref.md" ] && echo present || echo missing)" \
      "task-registry: $tree/skills/task-registry/references/$ref.md exists"
  done
  # AC14's absence half (specs/workflow-routing.md). Cut 1 retired these; nothing
  # else asserts they stay retired. On a template repo the realistic way one
  # returns is a /sync or a merge restoring a path, which every presence-shaped
  # assertion above is blind to by construction.
  for retired in \
      scripts/registry/providers/jira.py \
      scripts/registry/migrate.py \
      references/migration.md; do
    assert_eq "absent" \
      "$([ -e "$tree/skills/task-registry/$retired" ] && echo present || echo absent)" \
      "task-registry: $tree/skills/task-registry/$retired stays retired (AC14)"
  done
  assert_eq "present" \
    "$([ -f "$tree/skills/task-registry/templates/task-tracking.md" ] && echo present || echo missing)" \
    "task-registry: $tree ships the docs/task-tracking.md template"
  assert_prose_contains "$tree/skills/task-registry/references/configuration.md" \
    "nothing — configuration defaults apply; provider auto-selection still follows the table below" \
    "task-registry: $tree configuration guide separates discovery from provider selection"
done

# The five workflow skills reach tracking only through the registry. /plan
# is not one of them any more: specs/plan-slices-and-handover.md AC8 moved
# filing to /slice, so /plan reaches tracking transitively and is asserted
# separately below rather than dropped from coverage.
for tree in .agents; do
  for skill in slice build verify-evidence quality-gate wrap-up-session; do
    assert_file_contains "$tree/skills/$skill/SKILL.md" "/task-registry" \
      "task-registry: $tree/$skill routes task state through the registry"
  done
  assert_file_matches "$tree/skills/plan/SKILL.md" '^Invoke `/slice' \
    "task-registry: $tree/plan reaches tracking transitively, through /slice"
done

assert_eq "absent" \
  "$([ -e "tests/fixtures/task-registry/fake-jira.py" ] && echo present || echo absent)" \
  "task-registry: the Jira fixture retires with the adapter it served (AC14)"

# Provider coupling guard. `gh pr` is fine — /wrap-up-session opens PRs, which is
# not task state. `gh issue` and any tracker REST path are the coupling this
# abstraction exists to remove, so they may appear only inside the registry.
# `/rest/api/` stays in the pattern after the Jira adapter's removal: it guards
# the next HTTP tracker somebody is tempted to call from a skill directly.
coupling_hits="$(grep -rlE "gh issue|/rest/api/" .agents/skills 2>/dev/null \
  | grep -v '/task-registry/' | grep -vF '.claude/worktrees' || true)"
assert_eq "" "$coupling_hits" \
  "task-registry: no skill outside the registry calls a tracker's task API (offenders: ${coupling_hits:-none})"

# --- /route is gone, and nothing in the shipping surface still names it ------
# specs/category-routines.md AC1/AC2. The issue router computed how much autonomy
# an issue permitted by running a model's description of the work through a policy
# lattice -- 923 LOC of policy plus 728 of tests, which produced three unattended
# halts in one week, two of them from routing preconditions rather than from the
# work itself. A schedule already answers the autonomy question, so routines
# replaced it (.agents/skills/wrap-up-session/references/routines.md).
#
# SCOPE. "References /route" is asserted over the SHIPPING SURFACE -- the trees
# /sync and install.sh actually copy, plus the root docs and the test suite. Three
# categories are deliberately outside it, and the exclusion is the point rather
# than an escape hatch:
#   * tasks/history.md and tasks/eval-results/ are append-only records of what
#     happened. Editing them to erase a deleted skill falsifies the log.
#   * tasks/solutions/ is exempted by AC1 itself; AC13 reconciles the two
#     documents that CITE deleted paths, which is citation hygiene, not erasure.
#   * specs/ records the design. specs/category-routines.md must name what it
#     removed to be readable at all.
assert_eq "absent" "$([ -e ".agents/skills/route" ] && echo present || echo absent)" \
  "AC1: .agents/skills/route/ is deleted"
assert_eq "absent" "$([ -e ".claude/skills/route" ] && echo present || echo absent)" \
  "AC1: .claude/skills/route/ is deleted"

# Only this file is excluded, and only because it holds the pattern itself. Every
# other absence-asserting test builds the retired token at runtime instead of
# earning an entry here -- see tasks/solutions/patterns/construct-retired-paths-
# at-runtime-to-keep-literal-sweeps-strict.md. An allowlist rots: three
# exceptions accumulated in a single session before that pattern was applied, and
# a sweep that excludes its own quarry decays into documentation.
ROUTE_SWEEP_SELF_REFERENTIAL='^tests/test-doc-conventions\.sh$'
route_refs="$(grep -rlE '/route\b|route_issue|materialize_route|finalize_route' \
  .agents .claude CLAUDE.md README.md AGENTS.md PI_SETUP.md install.sh tests scripts \
  2>/dev/null | grep -vF '.claude/worktrees' \
  | grep -vE "$ROUTE_SWEEP_SELF_REFERENTIAL" || true)"
assert_eq "" "$route_refs" \
  "AC1: nothing in the shipping surface references the deleted router (offenders: ${route_refs:-none})"

assert_eq "absent" "$([ -e ".claude/hooks/user-prompt-route.sh" ] && echo present || echo absent)" \
  "AC2: the UserPromptSubmit routing hook is deleted"
assert_file_not_matches ".claude/settings.json" "user-prompt-route" \
  "AC2: settings.json no longer registers the routing hook"
assert_file_not_matches ".agents/hooks/session-start.sh" "/route" \
  "AC2: the session-start banner no longer advertises the router"

# The routines that replaced it must be reachable from the skill that implements
# the branch convention, in both trees.
for tree in .agents; do
  assert_eq "present" \
    "$([ -f "$tree/skills/wrap-up-session/references/routines.md" ] && echo present || echo missing)" \
    "AC1: $tree ships the routine contract that replaced the router"
done

# --- /plan's reuse gate must look INWARD before outward ----------------------
# The Research & Reuse rule enumerates `gh search repos`, `gh search code`, Exa,
# and package registries -- every rung points at EXTERNAL prior art. Nothing said
# "check what this repository already merged", so a session read three sibling
# skills that were present in a 9-commit-stale tree, concluded no overlap existed,
# and planned a feature that duplicated a capability merged hours earlier.
#
# Your own merged work is the highest-priority prior art AND the one category an
# outward search structurally cannot find. It goes first.
for tree in .agents; do
  P="$tree/skills/plan/SKILL.md"
  assert_prose_contains "$P" 'Check this repository first' \
    "PlanReuse($tree): pre-flight opens with the inward check"
  assert_prose_contains "$P" 'HEAD..@{upstream}' \
    "PlanReuse($tree): stale-clone check is named as a command"
  assert_prose_contains "$P" 'gh pr list --state merged' \
    "PlanReuse($tree): recently merged PRs are consulted"
  assert_prose_contains "$P" 'before any outward search' \
    "PlanReuse($tree): inward-before-outward ordering is stated"
done

# --- sync: the plugin declaration and the retired root -----------------------
# specs/claude-plugin-manifest.md § /sync. Step 5 merges the two plugin keys
# into the project's settings.json instead of overwriting it and writes no
# `ref` (a sha does not clone; plugin.json version pins — Spike S4); Step 6.4
# keeps the .claude/skills/ copies of a project that has not enabled the plugin
# out of the plan. Pinned by the smallest falsifiable unit: the marker, the two
# keys, the no-ref sentence, the guard's own wording.
for f in .agents/skills/sync/SKILL.md; do
  for token in "RETIRED —" "extraKnownMarketplaces" "enabledPlugins" "writes no \`ref\`" \
               "jplugin@jplugin-agentic-development" "rather than overwriting" \
               "does not enable" "\`version\` pins" "never in \`<selected-files>\`"; do
    assert_file_contains "$f" "$token" "sync: $f contains '$token'"
  done
  assert_file_matches "$f" '^\.claude/skills/ +→ RETIRED — ' \
    "sync: $f marks .claude/skills/ RETIRED in the doc block's right-hand column"
done
# session-start.sh: one line when the project enables the plugin and the
# machine has no record of installing it. A settings-driven install is recorded
# only by the versioned cache directory (Spike S4), install.sh's user-scope
# install by installed_plugins.json; the hook has to accept either.
for token in "enabledPlugins" "installed_plugins.json" "cache/jplugin-agentic-development/jplugin" "PLUGIN NOT INSTALLED"; do
  assert_file_contains .agents/hooks/session-start.sh "$token" \
    "session-start: names '$token' for the enabled-but-uninstalled line"
done

# --- the legacy shims are gone (specs/claude-plugin-manifest.md, slice 7) ------
# /sync Steps 2.5 and 2.6 migrated `.claude/commands/` and a CLAUDE.md
# `## Deployment Targets` section for projects synced years ago; the
# session-start hook, /verify-evidence, /verify-deployment and /setup-deployment all
# read CLAUDE.md as a fallback for the same section; the auto test-runner hook
# and tests.md were placeholders nothing wired. Each is deleted with every
# reference, so nothing can route a user to a step that no longer exists.
# The literals are assembled at runtime so this block is not itself a hit.
shim_hits() { git grep -l -e "$1" -- . ':!tasks' ':!specs' 2>/dev/null | paste -sd' ' - || true; }
for needle in "commands.""legacy" "Step 2.""5" "Step 2.""6" "auto-test-""runner" "auto test ""runner" "TARGETS_IN_""CLAUDE"; do
  hits="$(shim_hits "$needle")"
  assert_eq "" "$hits" \
    "Shims: no tracked file outside tasks/ and specs/ names '$needle' (hits: ${hits:-none})"
done
for gone in tests.md .claude/hooks/auto-test-"runner.sh" .claude/hooks/auto-test-"runner.ps1"; do
  assert_eq "absent" "$([ -e "$gone" ] && echo present || echo absent)" \
    "Shims: $gone is deleted"
done
assert_file_not_matches README.md 'tests\.md' \
  "Shims: the README directory tree no longer lists tests.md"
for f in .agents/skills/verify-deployment/SKILL.md \
         .agents/skills/verify-evidence/SKILL.md \
         .agents/skills/setup-deployment/SKILL.md \
         .claude/deployments/README.md .agents/hooks/session-start.sh; do
  assert_file_not_matches "$f" \
    '[Ll]egacy (fallback|location|section|projects|Deployment Targets|`CLAUDE\.md`)|auto-migrat|Deprecation' \
    "Shims: $f no longer reads or migrates a CLAUDE.md Deployment Targets section"
done
for f in .claude/deployments/README.md .claude/deployments/github-actions.md \
         .claude/deployments/railway.md .claude/deployments/vercel.md \
         .agents/skills/verify-deployment/SKILL.md .agents/skills/setup-deployment/SKILL.md; do
  assert_file_not_matches "$f" 'CLAUDE\.md` § Deployment Targets|CLAUDE\.md § Deployment Targets' \
    "Shims: $f points at AGENTS.md, not CLAUDE.md, for the Deployment Targets table"
done
assert_file_contains .agents/hooks/session-start.sh 'grep -qE "$TARGETS_REGEX" AGENTS.md' \
  "Shims: session-start reads AGENTS.md for the section (non-vacuity)"
# The pre-single-file location is still read, second, with a notice — a
# declined migration must not silence deployment verification
# (specs/single-instruction-file.md, D3).
assert_file_contains .agents/hooks/session-start.sh 'Deployment Targets found in .claude/project.md — /sync will move them to AGENTS.md' \
  "Shims: session-start prints the one-line notice for a table still in .claude/project.md"
assert_file_contains .agents/skills/sync/SKILL.md "### Step 2 — Detect Remote Default Branch" \
  "Shims: /sync Step 2 survives the deletion of its two legacy sub-steps (non-vacuity)"

# --- slice: spec to session-sized slices, documentation contract ------------
# specs/plan-slices-and-handover.md AC4-6. /slice is the one owner of sizing,
# ordering, filing and the build-prompt handover that both /plan and
# /system-design-planning call. Pinned by the smallest falsifiable unit: the
# frontmatter, the three references' existence, the two fenced templates
# compared byte-for-byte between SKILL.md and their references (the build
# prompt verbatim, the plan block after flattening), the required output
# lines, the refusal conditions, and the negative pins that keep the removed
# ceremony (a build invocation, a 'y' gate, an approval word, a dependency
# flag `upsert` does not have) from creeping back in.
SLICE_SKILL=.agents/skills/slice/SKILL.md
for token in "name: slice" "disable-model-invocation: false" "harness: universal" \
             "argument-hint:" "slice.py validate" \
             "✓ Build Order written:" "✓ Plan written:" \
             "Spec and plan are ready to be built. Start a fresh session with this prompt:" \
             "--derive-id plan" "--fold-title" "never start with \`/\`" \
             "--parent" "local-pending" "✓ Filed:"; do
  assert_file_contains "$SLICE_SKILL" "$token" "slice: SKILL.md contains '$token'"
done

# The three references exist.
for ref in plan-block sizing build-prompt; do
  assert_eq "present" \
    "$([ -f ".agents/skills/slice/references/$ref.md" ] && echo present || echo missing)" \
    "slice: references/$ref.md exists"
done

# In-place replacement, the no-plan-block refusal, the idempotent re-run and
# the --approve rule are hard-wrapped prose; pinned via flatten rather than a
# single-line literal.
flat_slice="$(flatten "$SLICE_SKILL")"
assert_contains "$flat_slice" "replaced section by section, in place" \
  "slice: SKILL.md states the in-place plan-block replacement rule"
assert_contains "$flat_slice" "Never two blocks for one feature" \
  "slice: SKILL.md states the one-block-per-feature rule"
assert_contains "$flat_slice" "there is nothing to file before a proposal" \
  "slice: SKILL.md states the no-plan-block refusal"
assert_contains "$flat_slice" "filing is idempotent" \
  "slice: SKILL.md states the idempotent re-run rule"
assert_contains "$flat_slice" "the build prompt a human typed is the reviewer's word" \
  "slice: SKILL.md states the --approve rule the /build and /yolo callers follow"

# Negative pins: the ceremony this spec removed must not reappear here.
assert_file_not_matches "$SLICE_SKILL" "Invoke /build" \
  "slice: SKILL.md never itself invokes /build"
assert_file_not_matches "$SLICE_SKILL" "meet your requirements" \
  "slice: SKILL.md carries no 'y' gate sentence"
assert_file_not_matches "$SLICE_SKILL" "> Approved" \
  "slice: SKILL.md carries no approval-word line"
if grep -qF -- "--depends-on" "$SLICE_SKILL" 2>/dev/null; then
  assert_eq "absent" "present" "slice: the --file upsert invocation names no --depends-on flag"
else
  assert_eq "absent" "absent" "slice: the --file upsert invocation names no --depends-on flag"
fi

# Registration in the one listing a new skill must appear in (the AGENTS.md
# managed block carries no skills table and the banner lists none — README is
# the one catalog, rendered from SKILL.md frontmatter).
assert_file_matches "README.md" '^\| `/slice`' \
  "slice: README skills table lists it"

# sizing.md: the one ceiling, no floor, no size labels/buckets.
SIZING=.agents/skills/slice/references/sizing.md
for token in "files > 8" "systems > 2" "ACs > 3"; do
  assert_file_contains "$SIZING" "$token" "slice: sizing.md states '$token'"
done
for absent in "floor" "S (" "M (" "L ("; do
  if grep -qF -- "$absent" "$SIZING" 2>/dev/null; then
    assert_eq "absent" "present" "slice: sizing.md must not contain '$absent'"
  else
    assert_eq "absent" "absent" "slice: sizing.md must not contain '$absent'"
  fi
done

# The plan-block example: the fenced ```markdown block that carries
# "## Plan:", byte-identical between SKILL.md and its reference after
# flattening.
extract_markdown_fence() {
  awk '
    /^```markdown$/ { capturing=1; buffer=""; next }
    capturing && /^```$/ { if (buffer ~ /## Plan:/) { printf "%s", buffer; exit } else { capturing=0 } }
    capturing { buffer = buffer $0 "\n" }
  ' "$1" | tr -d '\r'
}
plan_block_skill="$(extract_markdown_fence "$SLICE_SKILL" | tr '\n' ' ' | tr -s ' ')"
plan_block_ref="$(extract_markdown_fence .agents/skills/slice/references/plan-block.md | tr '\n' ' ' | tr -s ' ')"
assert_eq "$plan_block_ref" "$plan_block_skill" \
  "slice: plan-block example in SKILL.md matches references/plan-block.md (flattened)"
assert_contains "$plan_block_skill" "task-id: plan." \
  "slice: plan-block example carries the plan.<id> task-id form"

# The build-prompt template: the fenced block following the literal
# "Build prompt:" marker, byte-identical between SKILL.md and its reference.
extract_build_prompt() {
  awk '
    /Build prompt:/ { seen=1 }
    seen && /^```$/ { if (infence) { exit } else { infence=1; next } }
    infence { print }
  ' "$1" | tr -d '\r'
}
build_prompt_skill="$(extract_build_prompt "$SLICE_SKILL")"
build_prompt_ref="$(extract_build_prompt .agents/skills/slice/references/build-prompt.md)"
assert_eq "$build_prompt_ref" "$build_prompt_skill" \
  "slice: build-prompt template in SKILL.md matches references/build-prompt.md verbatim"
for token in "--file --approve" "Surface" "§ Decisions" "[AMBIGUITY]" "> Handover:" "/wrap-up-session"; do
  assert_contains "$build_prompt_skill" "$token" \
    "slice: build prompt instruction lines name '$token'"
done

# --- plan: /plan calls /slice instead of writing the plan block itself ------
# specs/plan-slices-and-handover.md AC8. /plan keeps its six-question
# interview and the carry-forward rule, escalates to /system-design-planning
# on its own § When to Use bar, and hands off to /slice for sizing, the plan
# block and the build prompt -- so the pins are the carry-forward vocabulary,
# the seven-section spec template in order, the `Invoke /slice` line, and the
# negative pins that keep the retired ceremony (a hand-written plan block, a
# 'y' gate, a build invocation, an upsert call) from creeping back in.
PLAN_SKILL=.agents/skills/plan/SKILL.md
for token in "DECISIONS CARRIED" "/grill-me" "/brainstorm" \
             "Escalating to /system-design-planning" \
             "What is the desired behavior?" "What are the inputs and outputs?" \
             "What are the edge cases and failure modes?" \
             "What constraints exist" \
             "Which existing files/components are likely involved?" \
             "What does \"done\" look like?" \
             "Spec and plan are ready to be built" \
             "references/build-prompt.md"; do
  assert_file_contains "$PLAN_SKILL" "$token" "plan: SKILL.md contains '$token'"
done

# The spec template's seven sections, in order. Pinned by ORDER, not count:
# a reflow that moves Decisions above Edge Cases silently changes what
# /slice reads as settled versus what the human still has to answer.
flat_plan="$(flatten "$PLAN_SKILL")"
pos_beh=$(printf '%s' "$flat_plan" | grep -bo '## Behavior' | head -1 | cut -d: -f1)
pos_in=$(printf '%s' "$flat_plan" | grep -bo '## Inputs' | head -1 | cut -d: -f1)
pos_out=$(printf '%s' "$flat_plan" | grep -bo '## Outputs' | head -1 | cut -d: -f1)
pos_edge=$(printf '%s' "$flat_plan" | grep -bo '## Edge Cases' | head -1 | cut -d: -f1)
pos_dec=$(printf '%s' "$flat_plan" | grep -bo '## Decisions' | head -1 | cut -d: -f1)
pos_ac=$(printf '%s' "$flat_plan" | grep -bo '## Acceptance Criteria' | head -1 | cut -d: -f1)
pos_impl=$(printf '%s' "$flat_plan" | grep -bo '## Implementation Paths' | head -1 | cut -d: -f1)
if [ -n "${pos_beh:-}" ] && [ -n "${pos_in:-}" ] && [ -n "${pos_out:-}" ] && [ -n "${pos_edge:-}" ] \
   && [ -n "${pos_dec:-}" ] && [ -n "${pos_ac:-}" ] && [ -n "${pos_impl:-}" ] \
   && [ "$pos_beh" -lt "$pos_in" ] && [ "$pos_in" -lt "$pos_out" ] && [ "$pos_out" -lt "$pos_edge" ] \
   && [ "$pos_edge" -lt "$pos_dec" ] && [ "$pos_dec" -lt "$pos_ac" ] && [ "$pos_ac" -lt "$pos_impl" ]; then
  assert_eq "ordered" "ordered" "plan: spec template lists the seven sections in order"
else
  assert_eq "Behavior < Inputs < Outputs < Edge Cases < Decisions < Acceptance Criteria < Implementation Paths" \
    "${pos_beh:-missing} ${pos_in:-missing} ${pos_out:-missing} ${pos_edge:-missing} ${pos_dec:-missing} ${pos_ac:-missing} ${pos_impl:-missing}" \
    "plan: spec template lists the seven sections in order"
fi

# § Decisions' three sources, in the prose that explains the column.
assert_contains "$flat_plan" '`user` for an answer the user gave' \
  "plan: SKILL.md defines Source \`user\`"
assert_contains "$flat_plan" '`assumed` for one `/plan` picked without asking' \
  "plan: SKILL.md defines Source \`assumed\`"
assert_contains "$flat_plan" '`open` for one nobody has decided yet' \
  "plan: SKILL.md defines Source \`open\`"

# Negative pins: the ceremony this spec removed must not reappear here.
assert_file_not_matches "$PLAN_SKILL" 'Invoke `/grilling' \
  "plan: SKILL.md never itself invokes /grilling"
assert_file_not_matches "$PLAN_SKILL" 'Invoke `/build' \
  "plan: SKILL.md never itself invokes /build"
assert_file_not_matches "$PLAN_SKILL" "Does this spec and plan meet your requirements" \
  "plan: SKILL.md carries no 'y' gate sentence"
assert_file_not_matches "$PLAN_SKILL" "upsert" \
  "plan: SKILL.md never calls upsert itself"
assert_file_not_matches "$PLAN_SKILL" "> Approved" \
  "plan: SKILL.md carries no approval-word line"
assert_file_not_matches "$PLAN_SKILL" '^## Plan:' \
  "plan: SKILL.md no longer carries a hand-written plan-block template"
assert_file_not_matches "$PLAN_SKILL" "Hand Off to TDD" \
  "plan: SKILL.md no longer hands off to TDD directly"
assert_file_not_matches "$PLAN_SKILL" "Register the Tasks" \
  "plan: SKILL.md no longer registers tasks itself"

# --- pipelines: /yolo and /auto-push after /plan's handover rewrite ---------
# specs/plan-slices-and-handover.md AC9 ("In-session pipelines"). Both are
# named exceptions to building in a fresh session -- /yolo because it is
# unattended end to end, /auto-push because its one gate is now its own,
# owned as an override on /plan's Step 6 instead of /plan's default handover.
YOLO_SKILL=.agents/skills/yolo/SKILL.md
AUTO_PUSH_SKILL=.agents/skills/auto-push/SKILL.md
assert_file_contains "$YOLO_SKILL" '`assumed` row' \
  "pipelines: yolo Step 1 override records gaps as \`assumed\` rows"
assert_file_matches "$YOLO_SKILL" 'Step 6.*no prompt' \
  "pipelines: yolo Step 6 row prints no prompt"
assert_file_matches "$YOLO_SKILL" 'no prompt.*in place' \
  "pipelines: yolo Step 6 row invokes /build in place"
assert_prose_contains "$YOLO_SKILL" 'runs `--file` without `--approve`' \
  "pipelines: yolo Phase B files with --file and no --approve"
assert_file_contains "$YOLO_SKILL" "fresh session" \
  "pipelines: yolo names the fresh-session rule it is excepted from"

assert_file_contains "$AUTO_PUSH_SKILL" \
  "Does this spec and plan meet your requirements? Once you confirm with **'y'**, I'll build, wrap up and push in this session." \
  "pipelines: auto-push Phase A owns the 'y' sentence as its own override on /plan Step 6"
assert_file_contains "$AUTO_PUSH_SKILL" "Step 6" \
  "pipelines: auto-push Phase A names /plan's Step 6 as the overridden step"
assert_file_contains "$AUTO_PUSH_SKILL" "--approve" \
  "pipelines: auto-push Phase B names --approve"
assert_file_contains "$AUTO_PUSH_SKILL" "fresh session" \
  "pipelines: auto-push names the fresh-session rule it is excepted from"

# --- design-planning: /system-design-planning interviews and hands off instead of filing ---
# specs/plan-slices-and-handover.md AC10. Step 1 reads a settled § Decisions
# tree instead of re-asking; the new §2.5 runs the mandatory /grilling
# interview with its own seed frontier and carry-forward rule; the template's
# build-order table and "Slice criteria" are gone because /slice now owns
# sizing (Step 3.5); Step 7 ends with the build prompt instead of an approval
# word; Step 8 (filing) is deleted outright; Step 9 (hand off) stays. The
# negative pins are the retired ceremony this rewrite removes -- a pin on
# retired text is replaced by a pin on the new contract, never silently
# dropped.
SDP_SKILL=.agents/skills/system-design-planning/SKILL.md
for token in "§ Decisions" "DECISIONS CARRIED" "frontier is empty" \
             "how a violation would be detected" \
             "who owns each fact a boundary crosses" \
             "outcomes and its failure unit" \
             "illegal states and transitions a status field must forbid" \
             "Spec and plan are ready to be built" \
             "[constraints|system-design|contracts|data-models|build-order]" \
             "### 9. Hand off" "references/build-prompt.md" \
             "NOTHING IS FILED AND NOTHING IS BUILT IN THE PLANNING SESSION. THE REVIEWER STARTS THE BUILD SESSION WITH THE BUILD PROMPT." \
             "filed in the planning session"; do
  assert_file_contains "$SDP_SKILL" "$token" "design-planning: SKILL.md contains '$token'"
done

# Step 1 names § Decisions specifically as what it reads from a prior spec.
step1_sdp="$(awk '/^### 1\. Intake/{p=1} /^### 2\. Recon/{p=0} p' "$SDP_SKILL")"
assert_contains "$step1_sdp" "§ Decisions" \
  "design-planning: Step 1 names § Decisions"

# §2.5 carries the mandatory /grilling invocation, at column 0 so the
# chain test can pin it beside /brainstorm's and /grill-me's.
assert_file_matches "$SDP_SKILL" '^Invoke `/grilling' \
  "design-planning: §2.5 invokes /grilling"

# Step 3.5 carries the /slice invocation, same column-0 convention.
assert_file_matches "$SDP_SKILL" '^Invoke `/slice' \
  "design-planning: Step 3.5 invokes /slice"

# Negative pins: the retired filing ceremony must not reappear. A bare
# "upsert" pin would false-flag the pre-existing worked example
# specs/upsert-depends-on.md, so these target the actual invocation and
# markers that made up Step 8 instead of the substring.
for absent in "task-registry.py upsert" "--derive-id design" "--apply --approve" \
              "> Approved" "TODO(shortcut)" "File slices" \
              "after approval only"; do
  if grep -qF -- "$absent" "$SDP_SKILL" 2>/dev/null; then
    assert_eq "absent" "present" "design-planning: SKILL.md must not contain '$absent'"
  else
    assert_eq "absent" "absent" "design-planning: SKILL.md must not contain '$absent'"
  fi
done
assert_file_not_matches "$SDP_SKILL" '"approved"' \
  "design-planning: SKILL.md no longer treats the bare word approved as approval"

# The template's build-order table and Slice criteria list are gone; /slice
# owns sizing now.
SDP_TEMPLATE=.agents/skills/system-design-planning/templates/architecture-spec-template.md
for absent in "| # | Slice |" "### Slice criteria"; do
  if grep -qF -- "$absent" "$SDP_TEMPLATE" 2>/dev/null; then
    assert_eq "absent" "present" "design-planning: template must not contain '$absent'"
  else
    assert_eq "absent" "absent" "design-planning: template must not contain '$absent'"
  fi
done
# The Build order heading survives -- it is one of the nine pinned headings --
# with one line saying /slice fills it, not the table itself.
assert_file_contains "$SDP_TEMPLATE" "## Build order" \
  "design-planning: template keeps the Build order heading"
assert_prose_contains "$SDP_TEMPLATE" "/slice fills this section's table" \
  "design-planning: template says /slice fills the Build order table"

# The rendered document's reflection line is what the reviewer reads last;
# an approval word there would reintroduce the gate Step 7 retired.
SDP_MODEL=.agents/skills/system-design-planning/templates/content-model.json
assert_file_not_matches "$SDP_MODEL" ', or approved' \
  "design-planning: content-model.json reflection no longer offers the approval word"
assert_file_contains "$SDP_MODEL" "starting a fresh session with the build prompt" \
  "design-planning: content-model.json reflection points at the build session"
assert_file_not_matches "$SDP_MODEL" 'Contract exposed        Size' \
  "design-planning: content-model.json build-order example is /slice's table, not the retired one"

# --- brainstorm: Step 6's template carries § Decisions with a Source column ---
# specs/plan-slices-and-handover.md AC11. /plan Step 1 carries a settled tree
# forward only when it can read a § Decisions table -- Step 6 must write one,
# every row `user`, so a brainstormed spec is on equal terms with a planned
# one.
BRAINSTORM_SKILL=.agents/skills/brainstorm/SKILL.md
assert_file_contains "$BRAINSTORM_SKILL" "## Decisions" \
  "brainstorm: Step 6 template carries a Decisions section"
assert_file_contains "$BRAINSTORM_SKILL" "| Source |" \
  "brainstorm: Step 6 template's Decisions table carries a Source column"

# Decisions sits between the free-form design section and Acceptance
# Criteria -- the template has no Edge Cases heading of its own, so the
# order check degrades to Decisions-before-Acceptance-Criteria only.
flat_brainstorm="$(flatten "$BRAINSTORM_SKILL")"
pos_dec_b=$(printf '%s' "$flat_brainstorm" | grep -bo '## Decisions' | head -1 | cut -d: -f1)
pos_ac_b=$(printf '%s' "$flat_brainstorm" | grep -bo '## Acceptance Criteria' | head -1 | cut -d: -f1)
if [ -n "${pos_dec_b:-}" ] && [ -n "${pos_ac_b:-}" ] && [ "$pos_dec_b" -lt "$pos_ac_b" ]; then
  assert_eq "ordered" "ordered" "brainstorm: template lists Decisions before Acceptance Criteria"
else
  assert_eq "Decisions < Acceptance Criteria" "${pos_dec_b:-missing} ${pos_ac_b:-missing}" \
    "brainstorm: template lists Decisions before Acceptance Criteria"
fi

# --- build: /build files slices, reads the ready set, closes with a handover ---
# specs/plan-slices-and-handover.md AC12. Pre-flight files an unlinked slice
# header through /slice --file --approve (/yolo omits --approve); a plan
# with no ### Slice headings is one implicit slice over implementation_paths,
# so every plan written before this spec still builds; Parallel Dispatch
# Assessment reads slice.py ready instead of guessing independence from
# prose; the delegation prompt carries the slice's Surface (with the
# [SURFACE] + escape), the blocking slices' handovers, and the tool-call
# budget with the ## Not finished list; Slice Close runs slice.py check
# (undeclared:/untouched:), writes the > Handover: blockquote, and records
# an interrupted slice as unfinished: rather than renumbering; Phase 6
# counts nested rows and calls a header/child mismatch the forbidden state.
# Pinned by the smallest falsifiable unit: the literal flags and phrases,
# plus the negative pins that keep the retired prose from creeping back.
BUILD_SKILL=.agents/skills/build/SKILL.md
for token in "--file --approve" "lacks a provider link" "implicit slice" \
             "implementation_paths" "slice.py ready" "intersecting pair" \
             "[SURFACE] +" "> Handover:" "## Not finished" "slice.py check" \
             "undeclared:" "untouched:" "unfinished:" "<short-sha>..<short-sha>" \
             "forbidden state" "Use in the session the build prompt starts" \
             "slice header" "\`/yolo\` omits \`--approve\`"; do
  assert_file_contains "$BUILD_SKILL" "$token" "build: SKILL.md contains '$token'"
done

# The ready call is described before the delegation prompt items -- a
# reflow that moves it after would have the assessment re-derive
# independence before it ever runs the command that replaced the guess.
flat_build="$(flatten "$BUILD_SKILL")"
pos_ready=$(printf '%s' "$flat_build" | grep -bo 'slice.py ready' | head -1 | cut -d: -f1)
pos_deleg=$(printf '%s' "$flat_build" | grep -bo 'Delegation prompt must include' | head -1 | cut -d: -f1)
if [ -n "${pos_ready:-}" ] && [ -n "${pos_deleg:-}" ] && [ "$pos_ready" -lt "$pos_deleg" ]; then
  assert_eq "ordered" "ordered" "build: the ready call is described before the delegation prompt items"
else
  assert_eq "ready < delegation prompt" "${pos_ready:-missing} ${pos_deleg:-missing}" \
    "build: the ready call is described before the delegation prompt items"
fi

# Negative pins: the retired ceremony this spec removed must not reappear.
assert_file_not_matches "$BUILD_SKILL" "after /plan is confirmed" \
  "build: SKILL.md no longer says 'after /plan is confirmed'"
assert_file_not_matches "$BUILD_SKILL" "Tasks are independent when" \
  "build: SKILL.md no longer assesses independence from prose"

# --- wrap-up: PR body gains a Handovers section before the linkage check ---
# specs/plan-slices-and-handover.md AC13. Step 7's Pull Request section
# writes a `## Handovers` block -- one `### Slice n/N` heading per slice,
# its lines verbatim -- before the linkage check reads the body, and falls
# back to the commit message when there is no tracker to host a PR.
WRAP_SKILL=.agents/skills/wrap-up-session/SKILL.md
for token in "## Handovers" "### Slice n/N" "commit message"; do
  assert_file_contains "$WRAP_SKILL" "$token" "wrap-up: SKILL.md contains '$token'"
done

flat_wrap="$(flatten "$WRAP_SKILL")"
pos_handovers=$(printf '%s' "$flat_wrap" | grep -bo '## Handovers' | head -1 | cut -d: -f1)
pos_linkage=$(printf '%s' "$flat_wrap" | grep -bo 'pr_linkage.py check' | head -1 | cut -d: -f1)
if [ -n "${pos_handovers:-}" ] && [ -n "${pos_linkage:-}" ] && [ "$pos_handovers" -lt "$pos_linkage" ]; then
  assert_eq "ordered" "ordered" "wrap-up: ## Handovers section appears before the linkage check"
else
  assert_eq "Handovers < linkage check" "${pos_handovers:-missing} ${pos_linkage:-missing}" \
    "wrap-up: ## Handovers section appears before the linkage check"
fi

# --- workflow: AGENTS.md § Workflow steps 2-4 after the build prompt replaced the y gate
# specs/plan-slices-and-handover.md AC14. The planner interviews, slices and
# hands over; the fresh session the build prompt starts files and builds. The
# pins are the vocabulary a reader needs to find the skills, the two retired
# gates as negative pins, and the five glossary terms in tasks/concepts.md.
WORKFLOW="$(awk '/^## Workflow/{p=1} p&&/^## Review Gate/{exit} p' AGENTS.md)"
for token in "/grill-me" "/brainstorm" "DECISIONS CARRIED" "/grilling" \
             "/system-design-planning" "/slice" "build prompt" "fresh session" \
             "> Handover:" "never builds and never files" \
             "Spec and plan are ready to be built" "--file --approve" \
             "slice.py ready" "/auto-push" "/yolo"; do
  assert_contains "$WORKFLOW" "$token" "workflow: AGENTS.md § Workflow names '$token'"
done
assert_not_contains "$WORKFLOW" "Confirm with 'y' to begin" \
  "workflow: the y gate is gone from AGENTS.md § Workflow"
assert_not_contains "$WORKFLOW" "**approved**" \
  "workflow: the approved parenthetical is gone from AGENTS.md § Workflow"
assert_not_contains "$WORKFLOW" "Do not proceed without user confirmation" \
  "workflow: the planning session no longer waits for a confirmation word"

for term in "build prompt" "handover" "ready set" "slice" "surface"; do
  assert_file_contains tasks/concepts.md "- **$term** —" \
    "workflow: tasks/concepts.md defines '$term'"
done

# --- fewer full runs (build): the full suite only at the cached baseline -----
# specs/fewer-full-suite-runs.md AC4. The pre-flight baseline goes through
# cached-suite.sh and records the base SHA; the pre-flight also resolves the
# project's `Affected tests:` command (with `{base}`) and the fallback when a
# project declares none. Every other checkpoint -- Step 3, the parallel
# barrier, the slice close, Phase 2 and the post-quality-gate run -- names the
# affected-test command instead of the full suite.
build_section() {  # <heading prefix>: that heading's body, up to the next ## or ### heading
  awk -v h="$1" 'index($0, h) == 1 { p = 1; print; next } p && /^##/ { exit } p' "$BUILD_SKILL" \
    | tr -s '[:space:]' ' '
}
PREFLIGHT="$(build_section "## Pre-Flight Checks")"
for token in "cached-suite.sh -- " "base SHA" "Affected tests:" "{base}" "declares none"; do
  assert_contains "$PREFLIGHT" "$token" "fewer full runs: /build pre-flight names '$token'"
done
for heading in "### Parallel Dispatch Assessment" "### Step 3 — Run Tests" "### Slice Close" \
               "## Phase 2 —" "## Phase 3 — Quality Gate"; do
  assert_contains "$(build_section "$heading")" "affected-test command" \
    "fewer full runs: /build '$heading' runs the affected-test command"
done
for heading in "### Step 3 — Run Tests" "### Slice Close" "## Phase 2 —" "## Phase 3 — Quality Gate"; do
  body="$(build_section "$heading")"
  for retired in "full test suite" "complete test suite" "run the full suite"; do
    assert_not_contains "$body" "$retired" \
      "fewer full runs: /build '$heading' no longer says '$retired'"
  done
done
assert_file_not_matches "$BUILD_SKILL" "Full test suite after every task" \
  "fewer full runs: Key Principles no longer says 'Full test suite after every task'"

# --- affected declaration: this repository's `Affected tests:` line ----------
# specs/fewer-full-suite-runs.md AC7. Below the end marker, so /sync keeps it.
BELOW_END="$(awk '/<!-- jplugin-agentic-development:end -->/{p=1; next} p' AGENTS.md)"
assert_contains "$BELOW_END" "Affected tests: bash tests/affected.sh --run {base}" \
  "affected declaration: AGENTS.md declares the command below the end marker"
# The cache key hashes the command, so every skill that runs the full suite
# reads it from one declaration instead of spelling it itself.
assert_contains "$BELOW_END" "Full suite: bash tests/run.sh" \
  "affected declaration: AGENTS.md declares the full-suite command below the end marker"
for skill in build yolo auto-push wrap-up-session; do
  assert_file_contains ".agents/skills/$skill/SKILL.md" "\`Full suite:" \
    "affected declaration: /$skill reads the declared full-suite command"
done
assert_contains "$PREFLIGHT" "cached-suite.sh -- <affected-test command>" \
  "affected declaration: /build runs the affected-test command through the lock"

# --- fewer full runs (wrap-up, pipelines): every full run goes through the cache
# specs/fewer-full-suite-runs.md AC5. /wrap-up-session Step 6 and the Step 7.5
# merged-result run, and the /yolo and /auto-push pre-flight baselines, so
# /build's baseline and a Step 6 on a proven-green tree reuse the record.
WRAP_SKILL=.agents/skills/wrap-up-session/SKILL.md
wrap_section() {  # <heading prefix>: that heading's body, up to the next ## heading
  awk -v h="$1" 'index($0, h) == 1 { p = 1; print; next } p && /^## / { exit } p' "$WRAP_SKILL" \
    | tr -s '[:space:]' ' '
}
assert_contains "$(wrap_section "## Step 6 — Run Tests")" "cached-suite.sh -- " \
  "fewer full runs: /wrap-up-session Step 6 runs the full suite through cached-suite.sh"
assert_contains "$(wrap_section "## Step 7.5 —")" "cached-suite.sh -- " \
  "fewer full runs: /wrap-up-session Step 7.5 merged-result run goes through cached-suite.sh"
for pipeline in yolo auto-push; do
  baseline_line="$(grep -F '**Test baseline**' ".agents/skills/$pipeline/SKILL.md")"
  assert_contains "$baseline_line" "cached-suite.sh -- " \
    "fewer full runs: /$pipeline pre-flight baseline goes through cached-suite.sh"
  # /plan and the pre-flight write to the tree before /build starts, so a
  # baseline run here would hash a tree /build never sees.
  assert_contains "$baseline_line" "Do not run a baseline here" \
    "fewer full runs: /$pipeline leaves its baseline to /build's pre-flight"
done
assert_contains "$(flatten AGENTS.md)" "Every slice closes with the affected-test command" \
  "fewer full runs: AGENTS.md § Workflow closes a slice with the affected-test command"
assert_not_contains "$(flatten AGENTS.md)" "closes with the full suite" \
  "fewer full runs: AGENTS.md § Workflow no longer closes a slice with the full suite"
BLOCK="$(awk '/jplugin-agentic-development:begin/{p=1} p; /jplugin-agentic-development:end/{exit}' AGENTS.md)"
for token in "Full suite: <command>" "Affected tests: <command with {base}>"; do
  assert_contains "$BLOCK" "$token" "fewer full runs: the managed block tells every project to declare '$token'"
done

# --- one suite, no polling: no test run beside a suite, no poll loops --------
# specs/fewer-full-suite-runs.md AC6. The load-contention cost came from
# targeted loops beside a running suite; the lock only covers full runs, so
# the rest of the rule lives in the prose of both skills.
for skill in "$BUILD_SKILL" "$WRAP_SKILL"; do
  flat="$(flatten "$skill")"
  for token in "One suite at a time, no polling." "no test run starts while a suite is running" \
               "run_in_background" "completion notification" "foreground \`sleep\`" "poll loop" \
               "leaves the working tree alone" "A refusal is not a test result." \
               "never count it as a fix attempt"; do
    assert_contains "$flat" "$token" "one suite: $skill names '$token'"
  done
done

# --- quality receipt (gate): /quality-gate owns the one review pass and mints its receipt
# specs/quality-receipt-closure.md AC4. Security runs as phase 3 over the
# gate's own file list, before the dispatched APOSD phase 4 so the design
# reviewer sees the security fixes; nothing edits the tree after phase 4; the
# affected tests run through the cache as phase 5 and receipt.py write mints
# the receipt as phase 6. A write refusal is `Receipt: none`, never GO.
QG_SKILL=.agents/skills/quality-gate/SKILL.md
qg_section() {  # <heading prefix>: that heading's body, up to the next ## heading
  awk -v h="$1" 'index($0, h) == 1 { p = 1; print; next } p && /^## / { exit } p' "$QG_SKILL" \
    | tr -s '[:space:]' ' '
}
assert_file_matches "$QG_SKILL" '^argument-hint: .*--scope <path>.*--parent <fingerprint>' \
  "quality receipt: /quality-gate's argument hint takes --scope and --parent <fingerprint>"
flat_qg="$(flatten "$QG_SKILL")"
prev=0
for heading in "## Phase 1 — " "## Phase 2 — " "## Phase 3 — Security" "## Phase 4 — Design Quality (APOSD)" \
               "## Phase 5 — Tests" "## Phase 6 — Receipt" "## Output"; do
  pos=$(printf '%s' "$flat_qg" | grep -bo -- "$heading" | head -1 | cut -d: -f1)
  if [ -n "${pos:-}" ] && [ "$pos" -gt "$prev" ]; then
    assert_eq "ordered" "ordered" "quality receipt: '$heading' follows the phase before it"
    prev=$pos
  else
    assert_eq "after $prev" "${pos:-missing}" "quality receipt: '$heading' follows the phase before it"
  fi
done
SCOPE_QG="$(qg_section "## Scope")"
for token in "receipt.py fingerprint" "untracked" "tasks/**" "--scope"; do
  assert_contains "$SCOPE_QG" "$token" "quality receipt: the gate's Scope names '$token'"
done
assert_not_contains "$SCOPE_QG" "git diff --name-only <base>..HEAD" \
  "quality receipt: the gate's file list is no longer the committed diff alone"
SEC_QG="$(qg_section "## Phase 3 — Security")"
for token in "/security-scan" "the gate's own file list" "untracked" "Apply Gate" "\"inline\""; do
  assert_contains "$SEC_QG" "$token" "quality receipt: phase 3 names '$token'"
done
assert_contains "$flat_qg" "No phase after 4 edits the tree" \
  "quality receipt: the gate forbids edits after the APOSD phase"
TESTS_QG="$(qg_section "## Phase 5 — Tests")"
for token in "Affected tests:" "cached-suite.sh -- " "\"tree\"" "never a silent fix"; do
  assert_contains "$TESTS_QG" "$token" "quality receipt: phase 5 names '$token'"
done
RECEIPT_QG="$(qg_section "## Phase 6 — Receipt")"
for token in "receipt.py write --outcome" "--parent <fingerprint>" "--git-common-dir" \
             "never supplies a verdict" "Receipt: none —"; do
  assert_contains "$RECEIPT_QG" "$token" "quality receipt: phase 6 names '$token'"
done
OUTPUT_QG="$(qg_section "## Output")"
assert_contains "$OUTPUT_QG" "Receipt: <GO|HOLD|STOP> <fp8> policy <qg1-xxxxxxxx> [parent <fp8>]" \
  "quality receipt: the Output block carries the Receipt line"
assert_contains "$OUTPUT_QG" "Receipt: none — <receipt.py stderr>" \
  "quality receipt: the Output block carries the refusal form"

# --- no wrap-up reviewer: wrap-up dispatches no reviewer of its own ----------
# specs/quality-receipt-closure.md AC7. Before #188, wrap-up ran 4 dispatched
# review passes (Step 4) plus an inline /security-scan (Step 3.5). Both are
# gone: /quality-gate is the one review pass per diff, and wrap-up only checks
# its receipt.
flat_wrap="$(flatten "$WRAP_SKILL")"
# Targets the dispatch machinery itself, not the disclaimer sentence in Step 4
# that names these personas on purpose to say wrap-up dispatches none of them.
for token in "Review Payload" "Parallel Code Review" "Dispatch Disclosure" \
             "Finding Classification" "Agent assignments:"; do
  assert_not_contains "$flat_wrap" "$token" \
    "no wrap-up reviewer: $WRAP_SKILL no longer carries '$token'"
done
assert_file_not_matches "$WRAP_SKILL" '^### Pass [0-9]' \
  "no wrap-up reviewer: $WRAP_SKILL no longer defines its own review passes"
assert_file_not_matches "$WRAP_SKILL" '^## Step 3\.5' \
  "no wrap-up reviewer: $WRAP_SKILL no longer has a Step 3.5 security scan"
assert_file_not_matches "$WRAP_SKILL" '^## Step 5 —' \
  "no wrap-up reviewer: $WRAP_SKILL no longer has a Step 5 apply-and-reconcile"

# --- receipt check: wrap-up's Step 4 reuses the gate's receipt --------------
# specs/quality-receipt-closure.md AC8. On `valid` it reuses the receipt; on
# `diff-changed` it re-enters the gate at delta scope with --parent; on any
# other stale reason, at full scope, once. It approves a HOLD only after a
# human answer in an interactive run, and never on an unattended one.
WRAP_STEP4="$(wrap_section "## Step 4 — Quality Gate Receipt")"
for token in "receipt.py check" "diff-changed" "--scope <delta paths> --parent <fp>" \
             "at full scope" "Quality receipt:" "receipt.py approve --fingerprint" \
             "Interactive run" "Unattended run" "never approves" "Step 8.5"; do
  assert_contains "$WRAP_STEP4" "$token" \
    "receipt check: /wrap-up-session Step 4 names '$token'"
done
assert_contains "$WRAP_STEP4" "Never call \`/quality-gate\` a second time on an unchanged tree." \
  "receipt check: /wrap-up-session Step 4 runs no second gate on the same tree"
# receipt.py reports an unapproved HOLD as `stale verdict HOLD`, never as
# `valid HOLD`; the approval path keys on that line, before any re-entry, and
# takes the fingerprint from `receipt.py fingerprint` (check prints none there).
assert_contains "$WRAP_STEP4" "stale verdict HOLD" \
  "receipt check: /wrap-up-session Step 4 keys the approval path on 'stale verdict HOLD'"
assert_contains "$WRAP_STEP4" "receipt.py fingerprint" \
  "receipt check: /wrap-up-session Step 4 reads the HOLD's fingerprint from receipt.py fingerprint"
assert_not_contains "$WRAP_STEP4" "\`valid HOLD\` (not yet approved)" \
  "receipt check: /wrap-up-session Step 4 names no 'valid HOLD' line receipt.py never prints"

# --- closure PR: Step 7 is rewritten around the closure engine -------------
# specs/quality-receipt-closure.md AC9. From Step 4 on, wrap-up performs the
# actions closure.py step prints, with its state file under the git common
# dir, never --no-verify, and the PR body carries the receipt line and a
# Closure section while still passing the linkage check.
STEP7="$(wrap_section "## Step 7 — Commit & Push")"
for token in "closure.py step" "git-common-dir" "action <name>" "terminal"; do
  assert_contains "$STEP7" "$token" "closure PR: Step 7 names '$token'"
done
assert_contains "$flat_wrap" "closure/<sanitized branch>.json" \
  "closure PR: the closure state path lives under the git common dir"
assert_not_contains "$flat_wrap" "--no-verify" \
  "closure PR: wrap-up commits never pass --no-verify"
assert_contains "$flat_wrap" "the \`Quality receipt: <verdict> · <fp8> · policy <v>\` line" \
  "closure PR: the PR body carries the Quality receipt line from Step 4"
assert_contains "$flat_wrap" "a \`## Closure\` section" \
  "closure PR: the PR body carries a ## Closure section"
PR_SECTION="$(awk '/^### The Pull Request/{f=1;next} f&&/^### Push Failure Handling/{exit} f' "$WRAP_SKILL")"
assert_contains "$PR_SECTION" "pr_linkage.py" \
  "closure PR: the PR section still runs the linkage check"
assert_contains "$PR_SECTION" "pr-sync" \
  "closure PR: the pull-request section is the pr-sync action"

# --- closure CI: mergeability, CI watch and bounded repair ------------------
# specs/quality-receipt-closure.md AC10.
CI_SECTION="$(wrap_section "#### CI Watch and Repair")"
MERGE_SECTION="$(wrap_section "#### Mergeability")"
assert_contains "$MERGE_SECTION" "gh pr view <n> --json mergeable" \
  "closure CI: mergeability names 'gh pr view <n> --json mergeable'"
for token in "gh pr checks <n> --watch --required" "run_in_background" \
             "gh pr checks <n>" "30 minutes" "2-minute registration window" \
             "gh run view <run-id> --log-failed" "/debug" "re-enters Step 4" "Step 6" \
             "2 total" "closure repair"; do
  assert_contains "$CI_SECTION" "$token" "closure CI: CI Watch and Repair names '$token'"
done
assert_contains "$flat_wrap" "no \`.github/workflows/*\` file triggers on \`pull_request\`" \
  "closure CI: ci: none requires no pull_request-triggered workflow too"
assert_contains "$flat_wrap" "closure repair <n>\` line to \`tasks/todo.md\` in that same commit" \
  "closure CI: every repair commit adds a closure-repair Session Summary line"
assert_contains "$flat_wrap" "introduces_summary" \
  "closure CI: the repair-commit line is named against the pre-push hook's check"

# --- closure conflicts: merge, never rebase, never force ---------------------
# specs/quality-receipt-closure.md AC11.
CONFLICT_SECTION="$(wrap_section "#### Conflict Repair")"
for token in "git merge origin/<base>" "git merge origin/<branch>" \
             "never \`rebase\`" "never \`--force\`" "git merge --abort" \
             "merge: unresolved" "at most 1 round"; do
  assert_contains "$CONFLICT_SECTION" "$token" "closure conflicts: Conflict Repair names '$token'"
done
assert_not_contains "$flat_wrap" "pull --rebase" \
  "closure conflicts: wrap-up no longer resolves a non-fast-forward push with pull --rebase"
PUSH_FAILURE="$(wrap_section "### Push Failure Handling")"
assert_contains "$PUSH_FAILURE" "Conflict Repair" \
  "closure conflicts: the non-fast-forward row routes to Conflict Repair"

# --- closure deploy: verify-deploy runs when a target applies, else n/a -----
# specs/quality-receipt-closure.md AC12. A moved HEAD re-enters Step 4 once.
STEP8="$(wrap_section "## Step 8 — Deployment Verification")"
for token in "/verify-evidence --scope deployment" "head-moved: true" "head-moved: false" \
             "re-enters Step 4" "deploy_reentries" "at most once" \
             "Deployments: not applicable —" "\`--skip-deploy\`"; do
  assert_contains "$STEP8" "$token" "closure deploy: Step 8 names '$token'"
done
assert_contains "$STEP8" "Deployment Targets\` row applies to the pushed branch" \
  "closure deploy: Step 8 names the applying-target case"
assert_contains "$STEP8" "Accepted exception" \
  "closure deploy: Step 8 names the accepted exception"

# --- closure record: record-closure and mark-draft are described, and the ---
# Done report carries a Closure line. specs/quality-receipt-closure.md AC13.
DONE_SECTION="$(wrap_section "## Done")"
for token in "record-closure" "gh pr edit <n> --body-file" "record: recorded" "record: record-failed" \
             "mark-draft" "gh pr ready <n> --undo" "partial: drafted" "partial: draft-failed" \
             "partial: no-pr" "Closure: [complete / partial" "closure engine failed" \
             "facts known before the push"; do
  assert_contains "$DONE_SECTION" "$token" "closure record: the Done section names '$token'"
done
assert_contains "$flat_wrap" "closure repair" \
  "closure record: closure repair commits stay named in the wrap-up flow"

# --- closure loop table: the three pointers now name real sections ----------
LOOP_TABLE="$(wrap_section "### The Closure Loop")"
assert_contains "$LOOP_TABLE" "Step 8 — Deployment Verification" \
  "closure loop table: verify-deploy points at Step 8's real heading"
assert_contains "$LOOP_TABLE" "Recording the closure" \
  "closure loop table: record-closure points at its own section"
assert_contains "$LOOP_TABLE" "Marking a partial PR draft" \
  "closure loop table: mark-draft points at its own section"
# An unapproved HOLD is its own observation and action, so the engine and
# Step 4 route it the same way; a terminal line ends the run for good.
for token in "approve-hold" "receipt: hold" "approve: approved" "starts a fresh run"; do
  assert_contains "$LOOP_TABLE" "$token" "closure loop table: names '$token'"
done

# --- closure history: Step 2 states the pre-push-only recording rule --------
STEP2="$(wrap_section "## Step 2 — Update Task Register")"
for token in "facts known" "before" "the push" "CI, conflict-repair and deployment outcomes" \
             "never written here"; do
  assert_contains "$STEP2" "$token" "closure history: Step 2 names '$token'"
done

# --- routine spine: step 5/4 name the receipt, not review passes ------------
# specs/quality-receipt-closure.md AC13.
ROUTINES=.agents/skills/wrap-up-session/references/routines.md
flat_routines="$(flatten "$ROUTINES")"
assert_contains "$flat_routines" "checks the quality receipt, tests, and the pull request" \
  "routine spine: routines.md names the quality receipt in place of review passes"
assert_not_contains "$flat_routines" "review passes, tests, and the pull request" \
  "routine spine: routines.md no longer names review passes in either spine table"

finish
