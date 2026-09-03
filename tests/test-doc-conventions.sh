# tests/test-doc-conventions.sh — documentation invariants across skills/config.
# Extended as P2/P4/P5 land. Pure grep assertions; no temp state.
. "$(dirname "$0")/lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# --- M3: retired store — the old monolith files have no live references ------
# INVERTED from the pre-M3 assertion that /build and /checkpoint reference
# tasks/memory.md. The store is now tasks/solutions/ + tasks/history.md; only
# tasks/archive/ and specs/ may name the retired files. Detection logic (e.g.
# /sync, session-start.sh) constructs the paths instead of naming them literally,
# so this sweep stays strict.
# Every swept root must exist — the `|| true` below absorbs grep's no-match
# exit, but it would also absorb a missing-path error, letting a renamed root
# silently shrink the sweep's coverage.
for root in .agents .claude/skills .claude/agents .claude/hooks \
            CLAUDE.md AGENTS.md .claude/project.md README.md install.sh project-template; do
  assert_eq "present" "$([ -e "$root" ] && echo present || echo missing)" \
    "M3: sweep root $root exists (sweep coverage intact)"
done
for old in "tasks/memory.md" "tasks/lessons.md" "tasks/bugs.md"; do
  offenders="$(grep -rlF "$old" .agents .claude/skills .claude/agents .claude/hooks \
      CLAUDE.md AGENTS.md .claude/project.md README.md install.sh project-template 2>/dev/null \
    | grep -v '\.claude/worktrees/' || true)"
  assert_eq "" "$offenders" "M3: no live reference to $old (offenders: ${offenders:-none})"
done
for f in .claude/skills/checkpoint/SKILL.md .agents/skills/checkpoint/SKILL.md \
         .claude/skills/build/SKILL.md .agents/skills/build/SKILL.md; do
  assert_file_contains "$f" "tasks/solutions" "M3: $f references the typed store"
done

# --- Task 5 (P2): both build copies checkpoint at task boundaries ---
for f in .claude/skills/build/SKILL.md .agents/skills/build/SKILL.md; do
  assert_file_contains "$f" "Task-boundary checkpoint" "Task5: $f checkpoints at task boundary"
  assert_file_contains "$f" "pre-compact.sh" "Task5: $f reuses the shared PreCompact flush"
done

# --- Task 7 (P3): circuit breaker auto-invokes /refresh before escalating ---
for f in .claude/skills/build/SKILL.md .agents/skills/build/SKILL.md; do
  assert_file_contains "$f" "Backstop first" "Task7: $f circuit breaker runs /refresh backstop"
done

# --- Task 6 (P3): /refresh registered in CLAUDE.md table + session-start banner ---
assert_file_contains "CLAUDE.md" "\`/refresh\`" "Task6: CLAUDE.md skills table lists /refresh"
assert_file_contains ".claude/hooks/session-start.sh" "/refresh" "Task6: session-start banner lists /refresh"

# --- Task 9 (P5): Large-Artifact Handoff convention + references ---
assert_file_contains ".claude/project.md" "Large-Artifact Handoff" "Task9: project.md defines the convention"
assert_file_contains ".claude/project.md" "truncate with a" "Task9: project.md states truncate-with-pointer"
for f in .claude/skills/build/SKILL.md .agents/skills/build/SKILL.md .claude/skills/verify-deployment/SKILL.md; do
  assert_file_contains "$f" "Large-Artifact Handoff" "Task9: $f references the convention"
done

# --- visual-recap: documentation contract present in both tree copies ---
for f in .claude/skills/visual-recap/SKILL.md .agents/skills/visual-recap/SKILL.md; do
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
for f in .claude/skills/visual-plan/SKILL.md .agents/skills/visual-plan/SKILL.md; do
  for token in "name: visual-plan" "argument-hint:" "Skip when trivial" \
               "read-only" "specs/" ".plan.html" \
               ".agents/skills/visual-recap/scripts/visual-render.py" "file map" \
               "open questions" "wireframe" "NEW"; do
    assert_file_contains "$f" "$token" "visual-plan: $f contains '$token'"
  done
done


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
$(find .agents/skills .claude/skills -name '*.md' -not -path '*/.claude/worktrees/*' | sort)
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
flatten() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; }

assert_file_contains "CLAUDE.md" "### Independence Accounting" \
  "M1: CLAUDE.md has an Independence Accounting subsection"
assert_contains "$(flatten CLAUDE.md)" "separately dispatched contexts" \
  "M1: CLAUDE.md requires separately dispatched contexts for corroboration"

taxonomy="$(sed -n '/^## Review Gate Taxonomy/,/^## Finding Model/p' CLAUDE.md | tr -d '\r' | tr '\n' ' ' | tr -s ' ')"
assert_contains "$taxonomy" "Independence Accounting" \
  "M1: Review Gate Taxonomy cross-references Independence Accounting"
assert_contains "$taxonomy" "Finding Model" \
  "M1: Review Gate Taxonomy cross-references the Finding Model"

# --- Tier 2 (M2): four-axis findings in CLAUDE.md and both review skills -----
# Each axis, enum value, and confidence anchor is pinned as its own token. A
# dropped enum value is exactly what would let an unsure finding auto-apply, and
# it is invisible in a whole-block snapshot.
for f in CLAUDE.md \
         .claude/skills/quality-gate/SKILL.md .agents/skills/quality-gate/SKILL.md \
         .claude/skills/wrap-up-session/SKILL.md .agents/skills/wrap-up-session/SKILL.md \
         .claude/skills/software-design-expert-review/SKILL.md \
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

# Both review skills must disclose whether their passes were dispatched or ran
# inline, and must not promote on same-context agreement.
for f in .claude/skills/quality-gate/SKILL.md .agents/skills/quality-gate/SKILL.md \
         .claude/skills/wrap-up-session/SKILL.md .agents/skills/wrap-up-session/SKILL.md; do
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
for f in .claude/skills/software-design-expert-review/SKILL.md \
         .agents/skills/software-design-expert-review/SKILL.md; do
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
for f in .claude/skills/yolo/SKILL.md .agents/skills/yolo/SKILL.md \
         .claude/skills/auto-push/SKILL.md .agents/skills/auto-push/SKILL.md \
         .claude/skills/auto-improve/SKILL.md .agents/skills/auto-improve/SKILL.md; do
  assert_file_contains "$f" "gated_auto" \
    "M2: $f states how a non-gated_auto MUST-FIX is routed"
done

# --- /wrap-up-session re-syncs a stale PR description ------------------------
# `gh pr create` writes the body once. Later commits falsify it and nothing
# re-reads it, so a PR can keep advertising a defect as deferred after the commit
# that fixed it already landed -- observed on PR #55. Two things are pinned: that
# the step exists, and that Step 7 no longer says "create if none exists" without
# handling the update case, which is the wording the gap lived in.
for f in .claude/skills/wrap-up-session/SKILL.md .agents/skills/wrap-up-session/SKILL.md; do
  assert_file_contains "$f" "PR Description Sync" \
    "PRSync: $f carries the PR Description Sync step"
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
for f in .claude/skills/learn/SKILL.md .agents/skills/learn/SKILL.md; do
  assert_file_contains "$f" "tasks/concepts.md" \
    "M4: $f captures concepts to the glossary"
  assert_file_contains "$f" "Sweep: pending" \
    "M4: $f bootstraps an absent glossary with the sweep marker"
done
# /memory-maintain owns both glossary lifecycles: the one-time bootstrap sweep
# (keyed on the pending marker, fires from the LIGHT pass so a fresh install
# does not wait 5 sessions) and steady-state pruning in the heavy pass.
for f in .claude/skills/memory-maintain/SKILL.md .agents/skills/memory-maintain/SKILL.md; do
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
# Registration: the glossary is a listed register in both CLAUDE.md variants.
keydirs="$(sed -n '/^## Key Directories/,/^## Agents/p' CLAUDE.md)"
assert_contains "$keydirs" "tasks/concepts.md" \
  "M4: CLAUDE.md Key Directories lists tasks/concepts.md"
assert_file_contains "project-template/CLAUDE.md" "concepts.md" \
  "M4: project-template CLAUDE.md lists the glossary"

# --- lightpanda: JS-capable page reads offered as an OPTIONAL research fallback ---
# WebFetch returns the empty shell for a JS-rendered page and gives no signal that
# it did, so a research step can silently read nothing and report nothing found.
# `lightpanda fetch` executes the scripts. It is optional everywhere: the machines
# running this workflow differ (no Windows build exists), so each mention must say
# absence is not an error, or a skill turns a missing optional tool into a blocker.
for f in .agents/skills/prd/SKILL.md .claude/skills/prd/SKILL.md \
         .agents/skills/brainstorm/SKILL.md .claude/skills/brainstorm/SKILL.md; do
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
for f in .agents/skills/start-qa/SKILL.md .claude/skills/start-qa/SKILL.md; do
  assert_file_not_matches "$f" "lightpanda"     "lightpanda: $f does NOT route manual QA to the DOM tier"
done
assert_files_identical .agents/skills/start-qa/SKILL.md .claude/skills/start-qa/SKILL.md   "lightpanda: start-qa stays byte-identical across both trees"

# --- agent-reach was evaluated and declined ----------------------------------
# Recorded as a guard so a later session does not quietly add the dependency the
# spec argued its way out of. specs/ is exempt: that is where the decision and
# its reversal path are written down. tests/ is exempt for the obvious reason
# that this assertion names the token itself.
reach_hits="$(grep -rl "agent-reach"   .agents .claude/skills .claude/agents .claude/hooks .claude/browsers   CLAUDE.md install.sh project-template 2>/dev/null | grep -v '.claude/worktrees' || true)"
assert_eq "" "$reach_hits"   "lightpanda: agent-reach is not a dependency anywhere outside specs/"

# --- task-registry: the tracker abstraction ----------------------------------
# The capability is worth nothing if a workflow skill can still reach a tracker
# directly: the point of the abstraction is that a project can change tracker
# without editing a workflow skill. Four things are pinned — the skill is
# registered where agents look for it, the configuration contract is
# discoverable, the five workflow skills route through it, and nothing outside
# the registry itself names a provider's task API.
assert_file_contains "CLAUDE.md" '`/task-registry`' \
  "task-registry: CLAUDE.md skills table lists the skill"
assert_file_contains "CLAUDE.md" "## Task Tracking" \
  "task-registry: CLAUDE.md defines the task-tracking section"
assert_file_contains "CLAUDE.md" "Task tracking instructions: docs/task-tracking.md" \
  "task-registry: CLAUDE.md carries the configuration pointer the loader looks for"
assert_prose_contains "CLAUDE.md" "is an **index**, not the detailed source of truth" \
  "task-registry: CLAUDE.md states that tasks/todo.md is an index"
assert_file_contains ".claude/hooks/session-start.sh" "/task-registry" \
  "task-registry: the session-start banner lists the skill"

for tree in .agents .claude; do
  f="$tree/skills/task-registry/SKILL.md"
  assert_file_contains "$f" "Dry-run is the default" \
    "task-registry: $f states the dry-run default"
  assert_file_contains "$f" "A title is never an identity" \
    "task-registry: $f states that a title is not an identity"
  assert_prose_contains "$f" "never creates, renames, or removes a label" \
    "task-registry: $f states the label-preservation rule"
  assert_file_contains "$f" "Nothing unresolved is deleted" \
    "task-registry: $f states the no-silent-deletion rule"
  assert_file_contains "$f" "Jira is never selected implicitly" \
    "task-registry: $f states that Jira is never implicit"
  # The three companion documents the skill points at must exist, or the
  # progressive-disclosure promise ("detail on demand") has nowhere to land.
  for ref in configuration migration progressive-disclosure; do
    assert_eq "present" \
      "$([ -f "$tree/skills/task-registry/references/$ref.md" ] && echo present || echo missing)" \
      "task-registry: $tree/skills/task-registry/references/$ref.md exists"
  done
  assert_eq "present" \
    "$([ -f "$tree/skills/task-registry/templates/task-tracking.md" ] && echo present || echo missing)" \
    "task-registry: $tree ships the docs/task-tracking.md template"
done

# The five workflow skills reach tracking only through the registry.
for tree in .agents .claude; do
  for skill in plan build verify quality-gate wrap-up-session; do
    assert_file_contains "$tree/skills/$skill/SKILL.md" "/task-registry" \
      "task-registry: $tree/$skill routes task state through the registry"
  done
done

# Provider coupling guard. `gh pr` is fine — /wrap-up-session opens PRs, which is
# not task state. `gh issue` and Jira REST paths are the coupling this
# abstraction exists to remove, so they may appear only inside the registry.
coupling_hits="$(grep -rlE "gh issue|/rest/api/" .agents/skills .claude/skills 2>/dev/null \
  | grep -v '/task-registry/' | grep -v '.claude/worktrees' || true)"
assert_eq "" "$coupling_hits" \
  "task-registry: no skill outside the registry calls a tracker's task API (offenders: ${coupling_hits:-none})"

# --- issue lane routing is registered and reused -----------------------------
assert_file_contains "CLAUDE.md" '`/route`' \
  "route: CLAUDE.md skills table lists the issue router"
assert_file_contains ".claude/hooks/session-start.sh" "/route" \
  "route: the session-start banner lists the issue router"
assert_file_contains "README.md" '`/route`' \
  "route: README lists the issue router"
for tree in .agents .claude; do
  route_skill="$tree/skills/auto-improve/SKILL.md"
  assert_file_contains "$route_skill" "route_issue.py" \
    "route: $tree/auto-improve delegates lane policy to the shared engine"
  assert_file_not_matches "$route_skill" "Bug / test failure / flaky" \
    "route: $tree/auto-improve no longer carries its own bug routing row"
  assert_file_not_matches "$route_skill" "Refactor / design fix / perf" \
    "route: $tree/auto-improve no longer carries its own refactor routing row"
  assert_file_not_matches "$route_skill" "Small triaged backlog feature" \
    "route: $tree/auto-improve no longer carries its own feature routing row"
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
for tree in .agents .claude; do
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


finish
