# Task Plan

> Spec: specs/issue-lane-routing.md — automatic issue → lane routing (hybrid architecture)
> Baseline: master @ 907ac6d (#79), suite green 26/26, tree current with origin.
> Branch: worktree off master (name at build time)
>
> Settled with user:
> 1. Three-part split — shared decision engine + thin `/route` + `/auto-improve` delegates
> 2. Propose-and-wait interactive; auto-execute only when autonomy is `autonomous` AND
>    the caller is unattended
> 3. Autonomy label `auto-mode-allowed`, single gate, `authorAssociation` recorded
> 4. **Hybrid with pstack `poteto-mode`**: the model perceives (structured claim), the
>    code decides (lattice, default-deny, monotonicity). Lanes are playbooks whose steps
>    are copied verbatim into `tasks/todo.md` with `skip: <reason>` for omissions.
>
> Related, not blocking: issue #81 retrofits the `skip: <reason>` ritual to `/build`,
> `/wrap-up-session`, and `/quality-gate`.
>
> [AMBIGUITY] route_issue.py needs structured task fields but task-registry's CLI prints
> bounded human text | options: A) use the registry library API B) add --json to
> task-registry C) parse text | picked: A | reason: `Registry.resolve_task` returns the
> complete provider-neutral record without parsing a deliberately-truncating summary;
> provider selection and metadata normalization stay task-registry's.

---

## Task 0 — Barriers fixed ahead of the feature (DONE this session)
[x] TDD: `tests/test-session-start.sh` — a clone behind its upstream prints
    `BEHIND UPSTREAM` with count and remedy; silent when current or when no upstream
    is configured -> `.claude/hooks/session-start.sh` reports divergence from the last
    fetch, no network call.
[x] TDD: `tests/test-doc-conventions.sh` — `/plan` pre-flight opens with
    `Check this repository first`, names `HEAD..@{upstream}` and
    `gh pr list --state merged`, states `before any outward search` (both trees)
    -> inward reuse rung added as `/plan` Step 0 item 1.

## Task 1 — Claim schema: perception/policy boundary (AC 5)
[x] TDD: `tests/test-route-decision.sh` — a complete claim is accepted; a claim with
    any field missing, null-where-non-nullable, or of the wrong type is **rejected**
    with the field named, never defaulted
    -> `.agents/skills/route/scripts/route_issue.py` validates the claim schema from
    the spec. Reject-not-default is the whole point: an absent signal is not a safe one.

## Task 2 — No prose classification in the engine (AC 5)
[x] TDD: grep asserts `route_issue.py` holds no keyword/regex lists over issue text
    (no `security|auth|crypto`-style alternations, no vagueness heuristics)
    -> perception lives in the SKILL body as instructions to the model; the engine
    consumes only the structured claim.

## Task 3 — Autonomy ceiling lattice, label from project config (AC 14)
[x] TDD: `min(channel, label, content)` computed with each grant reported separately in
    `ceiling`; label name read from the task-tracking configuration, not hardcoded; a
    project declaring no autonomy label never reaches `autonomous`
    -> three grant functions returning an ordered enum, combined by `min`. Reuse
    `registry.config` for the config read rather than a second parser.

## Task 4 — Default-deny eligibility over the claim
[x] TDD: each claim field that disqualifies independently drops `content_ceiling` and
    appends `{reason, signal}` to `downgrades`; a claim with
    `has_acceptance_criteria: false` is never `autonomous`
    -> named checks over claim fields only. Lane-selecting imperatives reported by the
    claim land in `ignored_directives` and count as a downgrade.

## Task 5 — Monotonicity by exhaustive enumeration (AC 9)
[x] TDD: enumerate the full claim space — every `kind` × the boolean cross product ×
    radius buckets — and assert autonomy never exceeds `min(channel, label)` at any
    point; include the adversarial all-permissive claim
    -> the guarantee is structural (content may only lower the enum), so enumeration
    proves it rather than sampling it.

## Task 6 — Lane playbooks + the skip ritual (AC 3, 4)
[x] TDD: `tests/test-route-skill.sh` — each playbook under
    `.agents/skills/route/playbooks/` lists all six steps; `/route`'s body documents
    copying them verbatim into `tasks/todo.md` before any source edit, and requires
    `skip: <reason>` on any step not run
    -> playbooks as files, not a constant in code. Provenance: pattern from
    `pstack/skills/poteto-mode`; add a `.github/upstreams.json` entry if any upstream
    text is copied verbatim rather than paraphrased.

## Task 7 — Slot derivation from task kinds, seven fixtures (AC 2)
[x] TDD: fixtures under `tests/fixtures/route/` — `kind: decision` (→ `/brainstorm`,
    never auto-confirm), #93 as the tracker-labeled bug (`/debug`, blocking question,
    `auto_confirm: false`), docs-only (`link-check`), another `kind: bug` (`/debug`),
    `kind: epic` (gated twice, three reviewers), real radius-three feature #81
    (`/brainstorm`), security-touching feature (`+ security-reviewer`)
    -> derive slots from `kind` first. Rows compose: `autonomy` by `min`, `reviewers`
    by union — assert on a fixture tripping two rows.

## Task 8 — Tracker I/O only through /task-registry (AC 12, 13)
[x] TDD: grep asserts zero `gh `/`curl`/`urllib` in `route_issue.py` and in
    `route/SKILL.md` bash fences; "take the next backlog item" resolves through
    `frontier`; a task reported `blocked` or `unknown-dependency` is refused with the
    blocker named
    -> per CLAUDE.md § Task Tracking. No hand-rolled `tasks/backlog.md` read.

## Task 9 — Project-gate discovery (AC 8)
[x] TDD: a `.claude/project.md` fixture with `^## Evidence Gate$` yields
    `verification_method: project-evidence-gate` and `human_verification.needed: true`
    with artifacts named in `judges`; absent heading — and the placeholder form
    `## Evidence Gate (placeholder …)` — yields neither
    -> reuse the exact-match convention proven by `^## Deployment Targets$`.

## Task 10 — UserPromptSubmit hook (AC 10)
[x] TDD: `tests/test-route-hook.sh` — emits `additionalContext` for an issue URL,
    `fix #123`, `#123`, "take the next backlog item"; emits nothing (exit 0, empty
    stdout) otherwise
    -> `.claude/hooks/user-prompt-route.sh`; register `UserPromptSubmit` in
    `.claude/settings.json` (project-level, syncable, no user-level counterpart).

## Task 11 — The /route skill (AC 1)
[x] TDD: SKILL.md in both trees, frontmatter valid, description names
    issue/ticket/URL/#123/backlog, body documents the decision record written before any
    source edit and propose-and-wait for interactive callers
    -> write canonical, copy byte-identically. Perception instructions live here.

## Task 12 — Reviewer dispatch + hang handling (AC 6, 7)
[x] TDD: `tests/test-review-context.sh` gains `skills/route/SKILL.md` as a dispatch site
    and passes; body states the hung-reviewer rule, the inverted floor, the runtime
    tripwire, and carrying unapplied findings into the wrap-up output
    -> seven contract items with empty-vs-absent markers; `autonomous` requires
    `code-reviewer` + `critic` (planner floor) separately dispatched; a hung reviewer is
    reported, never counted as agreement, and demotes the run to gated. Findings applied
    under the Finding Model gates only.

## Task 13 — /auto-improve delegates to the same engine (AC 15)
[x] TDD: `tests/test-doc-conventions.sh` — `/auto-improve` Phase 3 names
    `route_issue.py`; its three-row prose routing table is gone from both trees
    -> replace the table with a call. Behaviour change noted per AC 10.

## Task 14 — Eval before push (AC 11)
[x] TDD: `/eval` Mode A — three organic issue-shaped prompts (an issue URL, `fix #123`,
    "take the next backlog item"), N >= 3, own sanitized worktree each, graded by
    `.agents/skills/eval/scripts/grade-skill-loads.sh`. Record `FIRED` / `MISROUTED`
    (naming the winner) / `NONE`
    -> a misroute is a description defect: fix `/route`'s description before touching
    the prompt. Blinding is non-negotiable — no candidate learns it is measured, and no
    prompt contains eval vocabulary.

[x] TDD: `/eval` Mode B — hook arm vs description-only arm on two pushed branches, same
    prompts, N >= 2 per arm, one judge pass on one scale
    -> measures the claim the design rests on: that a hook beats a description under a
    suppression directive. This is the empirical answer to what static tests cannot
    reach. Report the result whatever it shows; presence/absence lift is unavailable in
    this harness and is not claimed.

## Task 15 — Registration surfaces, model tiers, residual limit
[x] TDD: `tests/test-model-tiers.sh` includes `route` in its ceiling sweep;
    `tests/test-doc-conventions.sh` and `tests/test-skill-invocation-chain.sh` pin
    `/route` in the CLAUDE.md table and the session-start banner; `tests/run.sh` green
    -> add to `CLAUDE.md`, `session-start.sh`, `README.md`. No `model` for ceiling
    reviewers; `critic` keeps its planner floor as a dispatch rule. Document the one
    untestable thing: the hook fires deterministically, but whether the agent obeys
    under a suppression directive is not observable from disk.

## Review remediation — quality gate APOSD STOP
[x] TDD: public materialization operation decides, atomically persists
    `tasks/route-decision.md`, and renders the selected playbook into `tasks/todo.md`
    before returning -> callers cannot omit or reorder the audit-before-edit sequence.
[x] TDD: all playbooks expose one generic reviewer slot and dispatch exactly the
    engine-returned set -> reviewer policy has one executable source of truth.
[x] TDD: project policy is loaded from the repository root by the public operation,
    while pure policy calls require explicit project text -> omission cannot masquerade
    as an absent Evidence Gate.
[x] TDD: decisions retain declared paths and a shared diff tripwire reports overflow
    consistently -> callers do not invent subsystem mapping independently.
[x] TDD: every materialized lane includes a mandatory post-build `finalize_route`
    row that persists the radius result and demotes overflow before verification or
    push -> the runtime guard cannot be omitted while following the visible lane.
[x] TDD: the public route entry accepts a task reference and resolves the complete
    normalized record through task-registry -> callers never reconstruct `Task.extra`
    or silently lose dependency/provider state at the human-text boundary.

## Review remediation — wrap-up independent passes
[x] TDD: malformed hook envelopes fail non-zero with an actionable schema error;
    valid non-issue prompts remain silent -> routing cannot disappear on harness drift.
[x] TDD: claim kind must equal task-registry's structured kind, and visual output
    forces the pre-push human gate -> untrusted perception cannot weaken policy.
[x] TDD: exact `## Autonomy Policy` bullets override the label and cap the lattice;
    duplicate, unknown, and malformed entries fail closed.
[x] TDD: monotonicity enumerates interactive/configured/unconfigured trusted grants
    across the entire claim space -> the proof covers every trusted ceiling.
[x] TDD: route finalization derives tracked and untracked paths from its recorded Git
    baseline; conservative two-component roots expose broad-prefix subsystem spread.
[x] TDD: tripwire and reviewer demotions rewrite both the decision record and the
    visible playbook; missing or hung reviewer outcomes cannot retain autonomy.
[x] TDD: managed lane markers accept exactly zero or one complete pair -> duplicate
    stale workflow blocks are rejected rather than partially replaced.
[x] TDD: direct resolution annotates known-open dependencies with frontier semantics;
    route refuses them as well as blocked and unknown dependencies.
[x] TDD: task-registry `show` resolves provider references, GitHub rejects foreign-repo
    URLs, and provider evidence records unresolved closing-PR state.
[x] TDD: playbooks emit only supported `/verify` invocations and `/auto-improve`
    registers fresh discoveries through task-registry's canonical row seam.
[x] TDD: a materialize-then-finalize integration excludes only route control files
    and unchanged pre-route dirt -> the runtime tripwire measures session work.
[x] TDD: baseline worktree fingerprints survive later commits and include untracked
    files -> callers cannot omit changed paths or smuggle a broad prefix.
[x] TDD: no-AC work adds the software-design reviewer required by the lane matrix.
[x] TDD: reviewer finalization records independent dispatch and unresolved findings;
    liveness alone cannot preserve autonomous permission.
[x] TDD: persisted decision identity is authoritative across finalizers -> a stale
    caller cannot erase a tripwire or reviewer demotion.
[x] TDD: route decision and visible todo use a recoverable transaction manifest;
    injected interruption is completed on the next policy operation.
[x] TDD: pair writes persist canonical/audit decisions before exposing a todo lane;
    interrupted materialization never leaves an executable unrecorded route.
[x] TDD: reviewer completion with a pending or failed runtime tripwire demotes;
    each cause records its truthful reason and signal.
[x] TDD: canonical lifecycle state lives under Git metadata; editing the worktree
    audit copy cannot widen paths, radius, reviewers, or autonomy.
[x] TDD: worktree fingerprints use `lstat`, link text, mode, and `O_NOFOLLOW` ->
    changed symlinks never read or hash targets outside the repository.
[x] TDD: unmanaged provider tasks expose provisional title-derived identity and
    route refuses them until task-registry registration or migration.
[x] TDD: `/auto-improve` delegates build, verification/review, and wrap exactly
    once across its phases instead of executing and then repeating a full lane.
[x] TDD: public route finalizers refuse absent canonical lifecycle state -> callers
    cannot bootstrap an unmaterialized decision with arbitrary supplied policy.
[x] TDD: auto-improve candidate registration opts into a compact task-kind marker ->
    task-registry resolution preserves the kind used by the structured claim.

---

## Notes

- Parity: every `.agents/skills/route/` file byte-identical in `.claude/skills/route/`.
- Syncable: no new root — `.agents/skills/`, `.claude/skills/`, `.claude/hooks/`,
  `.claude/settings.json` are already on `/sync`'s list.
- Executed paths in bash fences must name `.agents/skills/…`, never `.claude/skills/…`
  and never `../`.
- Classification *quality* is an `/eval` question, not a unit-test question. Only
  classification *safety* is pinned here.
- Out of scope, still open: `ascii_video_pipeline` #93 uncommitted with no independent
  review. Different repo, different session.

## Session Summary — 2026-09-01 [907ac6d..worktree]
- Completed: 48 tasks
- Pending: 0 tasks
- Carry-forward: formal user-surface E2E remains unavailable until a project-local
  verification skill exists; Mode B found no measurable hook lift in this harness.

---

## Plan: Wrap-Up Push Gate + `/tdd` Fold-and-Retire
> Spec: specs/wrap-up-gate-and-tdd-fold.md
> Two independent commits. A = gate, B = fold. A first: B's value depends on the
> gate existing, not the reverse.

### A — Wrap-Up Push Gate

[x] TDD: fingerprint parser extracts `[start..end]` from `## Session Summary` lines, ignores malformed endpoints -> parse function in `.agents/git-hooks/pre-push`, reading `tasks/todo.md` via `git show <sha>:tasks/todo.md`
[x] TDD: code-vs-docs classifier — `*.md`, `LICENSE*`, `.gitignore`, `tasks/**` are non-code -> path filter over `git diff-tree --no-commit-id --name-only -r`
[x] TDD: uncovered code commit exits **0**, names its short-SHA on stderr -> coverage check via `git rev-list start..end` membership; never blocks
[x] TDD: covered code commit exits 0 and prints nothing -> success path silent per Observability Discipline
[x] TDD: the commit introducing a session-summary line is treated as covered -> wrap-up-commit exemption (spec Contract clause 2)
[x] TDD: uncovered push writes one `tasks/wrap-up-debt.md` entry keyed on `<branch> <first>..<last>` -> ledger writer
[x] TDD: re-pushing the same uncovered range updates the entry in place, never duplicates -> ledger key lookup before append
[x] TDD: docs-only push passes silently and records nothing -> classifier short-circuit
[x] TDD: repo with no `tasks/todo.md` at the pushed sha passes silently and records nothing -> absent-file guard
[x] TDD: new-branch push (zero remote sha) resolves range from merge-base with default branch -> zero-sha branch
[x] TDD: branch-deletion push (zero local sha) passes, records nothing -> zero-sha branch
[x] TDD: merge commits are exempt from coverage -> `git rev-list --no-merges`
[x] TDD: `SKIP_WRAPUP_GATE=1` bypasses the gate while `SKIP_PREPUSH=1` still bypasses the whole hook -> env guards, gate guard nested inside the existing one
[x] TDD: malformed fingerprint is reported on stderr, neither widens coverage nor suppresses the warning -> parser rejects `[907ac6d..worktree]`-shaped endpoints
[x] TDD: hook makes no network call and invokes no tracker command -> grep the hook for `gh`/`curl`/`task-registry` in the test
[x] TDD: `session-start.sh` prints outstanding debt with the `/task-registry publish` invocation, silent when ledger empty or absent -> banner section beside the existing counts
[x] TDD: `install.sh` run inside a repo installs the hook to `--git-common-dir/hooks/pre-push` -> new install step beside `install.sh:256-259`
[x] TDD: `/sync` refreshes the pre-push hook in an already-cloned repo -> sync step + doc row
[x] Delete `.claude/hooks/pre-push-guard.sh` (header already reads "safe to delete"; two pre-push scripts invite editing the dormant one)

### B — Fold `/tdd` into `/build`, then retire

[x] TDD: `build/SKILL.md` Phase 1 carries the Red Flags list, rationalization table, and When Stuck table -> move `tdd/SKILL.md:74-111` under Phase 1, keeping `(tdd)` as the label per the `simplify`/`deslop` precedent
[x] TDD: `build/references/testing-anti-patterns.md` exists and Phase 1 links it -> `git mv` from `.agents/skills/tdd/`
[x] TDD: no prose anywhere authorizes committing code without wrap-up -> confirm `tdd/SKILL.md:129-131` is destroyed, not relocated
[x] TDD: `plan/SKILL.md` § 7 hands off to `/build` -> repoint `:188`
[x] TDD: `project-template/tasks/todo.md` says "executed by `/build`" -> repoint `:4` (ships downstream)
[x] TDD: `auto-push/SKILL.md:73`, `prd/SKILL.md:24`, `brainstorm/SKILL.md:17` no longer name `/tdd` -> repoint or drop
[x] TDD: `README.md` has no `delegates to /tdd` diagram edge and no skills-table row -> remove `:215`, `:272`
[x] TDD: `CLAUDE.md:441` and `session-start.sh:383` no longer register `/tdd` -> remove both rows
[x] TDD: `tasks/solutions/architecture/tdd-enforcement.md` cites a line range that exists in `build/SKILL.md` -> repoint `:5`, `:16-17`
[x] TDD: both `.agents/skills/tdd/` and `.claude/skills/tdd/` are gone and parity holds -> remove both, run `tests/test-skill-parity.sh`
[x] TDD: `/sync` removes a stale `tdd/` from a downstream project -> retirement list entry
[x] Full suite green -> `tests/run.sh`

## Session Summary — 2026-09-02 [d0f54fc..bb071e8]
- Completed: 31 tasks (A: wrap-up push gate, 18; B: /tdd fold-and-retire, 13)
- Pending: 0
- Carry-forward: force-push guard in .agents/git-hooks/pre-push is dead code —
  git passes no push flags to a pre-push hook. Recorded open in
  tasks/solutions/bugs/pre-push-force-guard-never-fires.md; needs a separate
  change that infers non-fast-forward from the stdin ref list.
