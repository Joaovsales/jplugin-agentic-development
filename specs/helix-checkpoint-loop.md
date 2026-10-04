---
implementation_paths:
  - .agents/skills/helix/**
  - .agents/skills/prototype/**
  - .agents/skills/go/SKILL.md
  - .agents/skills/task-registry/lanes/helix.md
  - .agents/skills/slice/**
  - .agents/skills/build/SKILL.md
  - .agents/skills/wrap-up-session/**
  - .agents/hooks/session-stop.sh
  - .claude-plugin/plugin.json
  - README.md
  - specs/lane-catalogue.md
  - tests/**
---

# Spec: Helix checkpoint loop

> Origin: conversation · Designed 2026-10-04 · Review status: **revised after critic: 4 applied, 0 declined**
> Visual: specs/helix-checkpoint-loop.plan.html

## Problem

Agents building features through this template currently close slices after TDD and a handover, while visual and code review evidence is collected later for the whole build. An explicit Helix route makes each slice an evidence-gated checkpoint, so dependent work starts only after that slice has passed the applicable behavior, UI, code review and human gates and has its own commit. Shopify-specific mobile tooling and stacked pull requests are outside the first release.

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Activation | Only a plan marked `workflow: helix/1` uses checkpoint gates; plans without the marker retain current `/build` and `slice.py ready` behavior | user | route and legacy-plan fixture tests |
| Source of truth | The spec owns scope and Build Order, `tasks/todo.md` owns task status, per-slice files under `tasks/helix/<feature>/` own gate facts, and `run.json` owns activation/final review; no `.helix/` plan or flat learnings copy | user | evidence and duplicate-state fixture tests |
| Advancement | A completed Helix header releases dependents only when its evidence is valid and committed; the gate checker refuses missing, stale, malformed or unknown-version evidence | user | `slice.py ready` negative fixtures |
| Gate order | Behavior → applicable UI → independent code reviews → human decision; a changed candidate invalidates downstream evidence that examined older bytes | user | transition and stale-tree tests |
| Review policy | Use the existing four-axis Finding Model and GO/HOLD/STOP derivation; a STOP blocks, and a HOLD advances only through the existing explicit approval contract | user | receipt integration tests |
| Human cadence | Review each slice by default; an explicit owner message may authorize the next N named slices; after all slices, final integrated human review remains required before wrap-up | user | grant-scope, final-review and no-self-approval tests |
| Retry bound | Use `/build`'s existing two Builder plus two Reviewer attempts, then block that slice with evidence; unrelated ready slices may continue | user | retry and ready-set fixtures |
| Commit boundary | One commit per cleared slice, with source, plan status and evidence together; retain the final full suite, quality receipt, one PR and CI closure | user | commit and wrap-up fixtures |
| Parallel work | Disjoint ready slices may implement in separate worktrees; the orchestrator integrates them in table order and records a barrier for the exact merged slice set and combined source tree before dependent work advances | inferred | two-worktree merge and stale-barrier fixtures |
| Shared run writes | Workers edit only their declared source Surface and produce private evidence drafts. The orchestrator alone writes `tasks/todo.md`, `run.json`, final slice evidence and commits on the integration branch | inferred | parallel shared-file collision fixture |
| Owner authority | A next-N grant comes from a role-tagged owner turn exposed by the active host; an agent-authored record or unverified imported transcript cannot create one. Across sessions, a grant needs host-verifiable provenance or the owner must reissue it | inferred | role/provenance and resume fixtures |
| UI reference | A migration uses the existing app; a visually significant new feature uses an approved interactive prototype; a localized UI change may use the approved `DESIGN.md` and concept; logic-only slices record a UI skip reason | user | prototype and visual-gate fixtures |
| UI evidence retention | Gate 2 keeps capture hashes and local paths per candidate; wrap-up publishes the retained captures with the existing PR visual-evidence mechanism, or leaves the UI task open when publication is unavailable | inferred | publication fixture with two slice captures |
| Harness support | Gate advancement works in Claude Code, Codex and Pi without a Stop hook; a Claude Stop hook may prompt continuation but permits `waiting_human` and `blocked` stops | inferred | CLI and Stop-hook fixtures |
| Test economy | Full suite remains the cached baseline and pre-push run; slice and review loops run the affected-test command centrally | user | command-count fixtures |

## System design

### Current state

```text
spec § Build Order ──► slice.py ready ──► [x] header + done blockers
                                                 │
                            /build closes after affected tests + handover
                                                 │
                       whole-build quality receipt → wrap-up → one commit/PR
```

`slice.py ready` currently reads header status and blockers without evidence (`.agents/skills/slice/scripts/slice.py:386-428`). `/build` writes the handover after its informational surface check (`.agents/skills/build/SKILL.md:281-321`), then runs the quality gate after all tasks (`.agents/skills/build/SKILL.md:408-417`). The quality receipt is tied to the reviewed tree and excludes `tasks/**` (`.agents/skills/quality-gate/scripts/receipt.py:1-19`); wrap-up performs final receipt, suite and single-PR closure (`.agents/skills/wrap-up-session/SKILL.md:140-225`).

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `specs/<feature>.md` | Helix activation, acceptance criteria, reference/prototype digest and Build Order | Design brief and approved concept |
| `tasks/todo.md` | Slice task status and handovers | Spec and registry task IDs |
| `tasks/helix/<feature>/run.json`, **NEW** | Run activation, owner grants and final integrated review | Spec digest and host role-tagged owner turns |
| `tasks/helix/<feature>/barriers/<id>.json`, **NEW** | Exact merged-set integration result for one combined candidate | Integrated commits, affected tests and quality receipt |
| Helix gate CLI, **NEW** | Versioned per-slice evidence, gate transitions, grant scope and closed-slice verification | Run, spec, todo, test output, UI manifest and quality receipt |
| `/slice` | Dependency graph, surface validation and ready set | Todo statuses and Helix gate verification for marked plans |
| `/build` | Fresh test-planner and implementer dispatch, repair loop and one commit per cleared Helix slice | Ready set, gate outcomes and reviewer findings |
| `/quality-gate` | Existing GO/HOLD/STOP policy and tree-bound review receipt | Changed code and reviewer evidence |
| `prototype` skill, **NEW** | Interactive reference HTML and declared UI states before implementation | `DESIGN.md`, approved concept and spec |
| `tasks/solutions/` | Reusable corrections and decisions | Slice feedback and source evidence |
| `/wrap-up-session` | Final integrated quality/full-suite/PR/CI closure after human acceptance | Slice commits, final review and final tree receipt |

### Interaction

```text
owner ──explicit Helix request──► /go Helix lane (NEW)
                                  │ sync: plan/spec + /slice
                                  ▼
                        spec workflow: helix/1
                                  │ fresh build prompt
                                  ▼
             /build ──ready──► /slice ──verify done blockers──► Helix gate CLI (NEW)
               │                                 │
               ├─ tests ─► behavior evidence ────┤
               ├─ UI reference + captures ───────┤
               ├─ two isolated reviewers ────────┤
               └─ owner review/grant ─────────────┤
                                                 close + commit
                                                      │
                                  merged tree integration barrier
                                                      │
                                           next ready set / final wrap-up
```

| Arrow | Mode | On timeout or failure | On duplicate |
|-------|------|-----------------------|--------------|
| `/build` → gate CLI | sync, local | Refuse the current slice; preserve recorded evidence for resume | Recheck the same evidence, never add a second approval |
| Gate CLI → tests | sync, local | Record command and nonzero exit; gate stays open | Same command and candidate tree may reuse a green cached run |
| `/build` → reviewer agents | async dispatch | Mark `blocked` after the existing retry ladder; no fabricated verdict | A reviewer ID and candidate fingerprint identify one verdict |
| Owner → human gate | async conversation | `waiting_human`; the session may end without advancing | The same grant ID applies only to its named slices once |
| Worktree → integration branch | sync Git operation, serialized by orchestrator | Merge conflict or failed central test blocks dependent slices | Reapplying a merged slice is refused by its stable slice/task ID |

### Failure unit

- A gate failure blocks its slice and descendants, while unrelated ready slices may continue.
- A missing reviewer, browser or UI reference blocks only slices that require that gate; it does not turn a failed check into a skip.
- An invalid Helix evidence record makes `ready` fail closed for the marked plan; legacy plans are unaffected.
- A combined-tree integration failure blocks the next dependency wave and final wrap-up, including slices whose isolated worktree tests passed.
- An unavailable screenshot publication path leaves the UI task open under the existing visual-evidence policy, even if local comparison passed.

## Component contracts

### Helix route and plan marker

```text
/go <goal containing an explicit Helix request> -> helix lane | ordinary lane
spec frontmatter: workflow: helix/1
```

| Aspect | Contract |
|--------|----------|
| Inputs | Explicit user request; `workflow: helix/1` copied into the spec and fresh build prompt |
| Outcomes | Helix plan with gated build prompt, or the existing route with unchanged plan format |
| Raises | Unknown workflow version is a planning/build refusal, never a fallback to ordinary build |
| Idempotency | Replanning the same spec updates its Build Order and plan block in place |
| Versioning | Missing marker means legacy; `helix/1` is the first supported opt-in version |

### Gate evidence and advancement

```text
helix.py record --spec PATH --slice N --gate GATE --evidence PATH -> recorded | invalid | stale
helix.py close --spec PATH --index PATH --slice N -> ready_to_commit | refused
helix.py verify --spec PATH --index PATH --slice N -> valid | missing | stale | invalid
helix.py barrier --spec PATH --index PATH --slices IDS --evidence PATH -> recorded | refused
helix.py verify-barrier --spec PATH --index PATH --slices IDS -> valid | missing | stale | invalid
slice.py ready --index PATH --spec PATH -> ready set | refusal
```

| Aspect | Contract |
|--------|----------|
| Inputs | Stable slice ID, digest of that slice's ACs, surface, reference and gate policy, candidate fingerprint of the declared Surface, gate-specific evidence and a human decision/grant; stored at `tasks/helix/<feature>/<slice-id>.json` with activation/final review in `run.json` |
| Outcomes | `record` persists validated evidence; `close` validates every gate on the slice candidate, then the orchestrator writes receipt and `[x]` status in one slice commit; `ready` releases a dependent only after `verify` confirms that historical committed candidate and `verify-barrier` confirms the latest combined tree |
| Raises | I/O and unexpected Git errors are explicit; malformed/unknown schemas return a refusal with file and reason |
| Idempotency | Repeating `record`, `close` or `verify` with identical input preserves one receipt; a changed slice contract or Surface candidate is stale, while appending an unrelated correction slice leaves older receipts valid. Barrier IDs derive from sorted merged slice IDs and the combined candidate fingerprint |
| Versioning | Evidence schema `helix-evidence/1`; readers refuse unknown versions and retain old files for audit |

The slice candidate is a sorted manifest of Git eligible regular files and symlinks matching its declared Surface, including tracked files and new files not ignored by Git. Each entry records path, mode and SHA-256 of bytes (or symlink target). The manifest hash excludes `tasks/**` status, receipts, captures and logs, which are checked through their own hashes. The slice contract digest separately covers its ACs, Surface, dependencies, applicable gate policy and approved UI reference. Gate 1, Gate 2 and both reviewers record this candidate hash. Any Surface edit after a gate invalidates that gate and later gates. The orchestrator validates the manifest against the integration branch immediately before the slice commit; workers' private drafts never become authoritative evidence.

After commit, `verify` recomputes the same manifest from that recorded commit's tree using the recorded Surface, and checks that the receipt and done header occur in the commit. It does **not** compare old slice receipts with today's source tree: later slices may change other paths. A missing or unreachable commit fails verification. The combined candidate uses the same manifest algorithm over every Git eligible path outside `tasks/**`; its barrier additionally binds the sorted merged slice IDs, ordered slice commit IDs known before the final wave commit, affected-test command/result and quality receipt fingerprint. `barrier` writes `tasks/helix/<feature>/barriers/<id>.json` only after central affected tests and the existing quality gate pass on that combined candidate. The orchestrator includes this record in the final slice commit of the wave; its own commit ID is derived from Git during verification, not stored inside itself. `verify-barrier` requires that committed record, the exact completed slice set, reachable slice commits and the current combined manifest hash; any new source edit invalidates it. `ready` checks the latest barrier for all completed blockers before releasing a dependent, and wrap-up checks the final barrier.

For a parallel wave, workers return source changes and private evidence drafts only. The orchestrator integrates source in Build Order order, rejects paths outside each Surface, reruns gates invalidated by the combined candidate, and serializes `close`, todo handovers/status, final evidence and one commit per slice on the integration branch. No worker commits shared plan or run files. A merge conflict blocks the affected slice, while completed independent slices retain their commits; dependents wait for a valid barrier covering the merged set.

### Prototype and UI comparison

```text
/prototype <spec> -> design/prototypes/<feature>.html + <feature>.states.json
ui-review(reference, implementation, state_manifest, slice_scope) -> PASS | FAIL | INVALID
```

| Aspect | Contract |
|--------|----------|
| Inputs | Existing app reference or approved prototype digest; named states, viewport, fixture data and slice-specific visual scope |
| Outcomes | Matched captures plus located/severity-ranked differences and hashes/paths for later publication; `INVALID` means recapture the same state and viewport, not a pass or product defect |
| Raises | Missing reference, stale digest or unavailable full-fidelity browser blocks a UI slice |
| Idempotency | The same reference/implementation/tree/state tuple yields one comparison record; a changed prototype invalidates affected comparisons and grants |
| Versioning | Prototype state manifest v1; existing `DESIGN.md` and concept approval remain authoritative for style |

### Code and human review

```text
review_slice(slice_diff, architecture_spec, policy) -> two independent verdicts + quality receipt
authorize_slices(host_owner_turn, spec_digest, next_n) -> grant(named_slice_ids) | rejected | waiting_owner
```

| Aspect | Contract |
|--------|----------|
| Inputs | Two separately dispatched read-only reviewers receive the seven-item review contract and no peer findings; a role-tagged owner turn in the active host supplies human authority |
| Outcomes | Existing GO/HOLD/STOP receipt rules decide code review; human gate records `reviewed` or `delegated` with exact grant ID and slice scope |
| Raises | Missing independent verdict, unapproved HOLD, STOP or an owner turn whose role cannot be checked blocks close |
| Idempotency | Reviewer verdicts are keyed by reviewer dispatch and candidate fingerprint; a grant names exact slices and cannot expand after creation |
| Versioning | Finding Model and quality receipt policy remain canonical; no second severity taxonomy or competing approval policy |

The host conversation role, not a digest supplied by the agent, establishes who spoke. For Claude Code, Codex and Pi, the orchestrator may accept a grant only from a new user-role message delivered through that host's conversation channel while this run is active; it records the host name, session/message reference where exposed, role, exact message hash, spec/prototype digests and named slice IDs. It refuses a tool result, repository file, assistant text or copied transcript as a grant source. The CLI can verify scope and integrity of this record, but cannot independently authenticate a role label written by the agent. Therefore a persisted next-N grant is usable only while the originating host session can verify that message; on a resumed session or a host without stable role/message lookup, the owner reissues the grant in a fresh user turn. This is the cross-harness trust limit; no record is treated as cryptographic proof of owner intent. Per-slice review likewise requires a fresh user turn. The final integrated acceptance always requires its own fresh user turn, even when a batch grant remains valid.

## Data models

### Entities

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `workflow` | `helix/1` or absent | An active Helix run never silently downgrades when the marker disappears | gate CLI activation check |
| `run` | `tasks/helix/<feature>/run.json` | Holds activation and final review only; slice completion remains in todo and proof remains in slice files | versioned run validator |
| `slice_id` | stable task ID plus slice number | Matches spec Build Order and todo heading | `slice.py` validation and gate CLI |
| `candidate` | Surface manifest hash + slice-contract/prototype/policy digests | Evidence refers to the code and requirements each gate examined; `tasks/**` bookkeeping cannot stale it | gate CLI fingerprint validation |
| `gate` | behavior, UI, review, human | Every required gate has producer, outcome, evidence path/hash and timestamp | `helix-evidence/1` validator |
| `grant` | ID, host/session/message reference, owner role, message digest, full-plan digest, exact slice IDs | Only a host-verified owner turn may authorize named slices; changed plan or lost provenance revokes applicability | host role check and grant validator |
| `commit` | Git commit containing code, status and receipt | A done header is not ready until committed evidence is reachable; the commit ID is derived from Git, avoiding a self-referential receipt | `ready` verification |
| `barrier` | version, sorted merged slice IDs, combined manifest hash, prior ordered slice commit IDs, test and quality evidence | A dependent can start only from the exact merged set and combined source tree that passed central checks; the final commit ID is derived from Git | `verify-barrier` |
| `final_review` | `waiting` / `accepted` / `changes_requested` | A next-N grant does not count as final acceptance | wrap-up preflight |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| `[x]` Helix header with no valid committed receipt | `slice.py ready` refusal and gate CLI close/commit contract |
| UI `skipped` on a UI slice, or UI `passed` from mismatched states | applicability validator and `INVALID` comparison outcome |
| Review `passed` from one context or an unapproved HOLD | two dispatch IDs and existing receipt verdict check |
| Human `approved` produced by the agent or a grant outside its exact slice set | host owner-role check and grant-scope validation; unverifiable resumed grants expire |
| New candidate bytes with old behavior, UI or reviewer evidence | candidate fingerprint check and downstream invalidation |
| Complete slice with failed test, missing handover, or unmerged parallel integration | close/ready and committed integration-barrier validation |

### Transitions — gate outcome

| From | To | Trigger |
|------|----|---------|
| `pending` | `passed` / `failed` | Evidence producer runs on current candidate |
| `pending` | `skipped` | Only UI gate on a non-UI slice with recorded reason |
| `pending` / `failed` | `invalid` | UI captures represent different states or viewports |
| `failed` / `invalid` | `passed` | Repair or recapture, followed by a fresh check |
| `passed` / `skipped` | `stale` | Candidate, this slice's contract, its prototype or the gate policy changes |
| `stale` | `passed` / `failed` | Gate reruns on the new candidate |

### Transitions — slice progress

| From | To | Trigger |
|------|----|---------|
| `open` | `implementing` | Failing test recorded before implementation |
| `implementing` | `waiting_human` | Behavior, applicable UI and review gates clear |
| `implementing` | `blocked` | Existing retry ladder exhausted or required capability unavailable |
| `blocked` | `implementing` | A later correction or restored capability starts a fresh attempt |
| `waiting_human` | `closed` | Owner reviews the slice or an applicable named-slice grant is used; close writes receipt and status |
| `closed` | `committed` | Git commit contains source, handover, `[x]` header and evidence |
| `committed` | `ready_for_dependents` | The combined-tree integration barrier passes |

### Transitions — review verdict and grant

| From | To | Trigger |
|------|----|---------|
| Review `pending` | `GO` / `HOLD` / `STOP` | Two independent verdicts are recorded and the existing receipt policy derives the result |
| Review `HOLD` | `HOLD-approved` | Existing human approval contract records the exact receipt fingerprint |
| Review `GO` / `HOLD-approved` | `stale` | Candidate or review policy changes |
| Grant `issued` | `used` | A named slice closes under the grant; other named slices remain eligible |
| Grant `issued` / `used` | `stale` | Full plan or approved prototype digest changes, or the owner revokes the grant |

### Transitions — final review

| From | To | Trigger |
|------|----|---------|
| `waiting` | `accepted` | Owner tests the integrated feature and accepts it |
| `waiting` | `changes_requested` | Owner requests a correction; the request becomes a new gated slice |
| `changes_requested` | `waiting` | Correction slice closes and integrated checks rerun |
| `accepted` | `waiting` | Source tree or spec changes before wrap-up |

### Transitions — integration barrier

| From | To | Trigger |
|------|----|---------|
| `absent` | `passed` | Central affected tests and quality gate pass on the exact combined candidate; record is committed with the final slice of the wave |
| `absent` | `failed` | Merge, test or quality check fails; retain command/result and block dependents |
| `failed` | `passed` | Repair and rerun both central checks on the new combined candidate |
| `passed` | `stale` | Completed slice set or combined source manifest changes |
| `stale` | `passed` / `failed` | Rerun central checks and commit a new barrier record |

### Migration and compatibility

- Existing specs without `workflow: helix/1` and their flat or sliced plan blocks follow the current route, build and ready behavior without new evidence files.
- An active run's evidence remains discoverable if its marker is removed; removal produces a refusal, not a downgrade. Cancelling a run is an explicit recorded action, after which ordinary planning may start a new spec revision.
- Evidence records are retained when superseded. New readers validate `helix-evidence/1`; unknown versions fail closed only for Helix plans. A new correction slice changes the plan digest and grants but preserves prior receipts whose own slice contracts remain unchanged.
- Rollback disables the opt-in route for new plans while active Helix plans remain gated or explicitly cancelled. No existing task, quality receipt or E2E log format is migrated.
- The first version uses one PR containing slice commits. Stacked PRs require branch-base, CI and rebase coordination in the single-PR closure engine and are deferred.
- The Claude Stop reminder checks whether the run may pause before the existing session-stop cleanup; a blocked continuation keeps the session-active sentinel intact.

## Build Order

Sizing: 13 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: the new skill inventory, plugin pin and gate tests must ship together; slice 12: the lane declaration and canonical lane catalogue must agree in one change.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Evidence kernel | Versioned evidence validates Surface manifests, historical commit identity, barrier records, gate order, staleness and idempotence without enabling a route. | `.agents/skills/helix/**`, `README.md`, `.claude-plugin/plugin.json`, `tests/test-helix-gates.sh` | — | 4 | `bash tests/test-helix-gates.sh` | 4 planned files · 3 systems · 1 AC |
| 2 | Prototype reference | A design-grounded clickable HTML reference exposes named, reachable UI states. | `.agents/skills/prototype/**`, `README.md`, `tests/test-helix-prototype.sh` | 1 | 7 | `bash tests/test-helix-prototype.sh` | 3 planned files · 2 systems · 1 AC |
| 3 | Readiness verifier | `slice.py ready` refuses unproved Helix blockers and missing or stale combined-tree barriers while legacy readiness stays stable. | `.agents/skills/slice/scripts/slice.py`, `tests/test-slice.sh` | 1 | 5 | `bash tests/test-slice.sh` | 2 files · 2 systems · 1 AC |
| 4 | Behavior and UI gates | Fresh test planning proves behavior first; matched-state visual review records PASS, FAIL or INVALID. | `.agents/skills/helix/**`, `tests/test-helix-behavior.sh`, `tests/test-helix-ui.sh` | 2, 3 | 6, 9 | `bash tests/test-helix-behavior.sh && bash tests/test-helix-ui.sh` | 4 planned files · 2 systems · 2 ACs |
| 5 | Review and human gates | Independent reviewers use the existing receipt policy; host-role-checked exact-scope grants and bounded retries control advancement. | `.agents/skills/helix/**`, `tests/test-helix-review.sh`, `tests/test-helix-human.sh` | 4 | 10, 11, 12 | `bash tests/test-helix-review.sh && bash tests/test-helix-human.sh` | 4 planned files · 2 systems · 3 ACs |
| 6 | Build checkpoints | `/build` serializes shared writes and one commit per proved slice, merges disjoint source work, records the exact combined-tree barrier and passes feedback forward. | `.agents/skills/build/SKILL.md`, `tests/test-helix-build.sh`, `tests/test-helix-parallel.sh` | 3, 5 | 13, 14, 15 | `bash tests/test-helix-build.sh && bash tests/test-helix-parallel.sh` | 3 planned files · 2 systems · 3 ACs |
| 7 | Single-PR closure | Wrap-up requires final human acceptance, checks every slice receipt, publishes captures and keeps the final suite and one PR. | `.agents/skills/wrap-up-session/**`, `tests/test-helix-wrapup.sh` | 6 | 18 | `bash tests/test-helix-wrapup.sh` | 4 planned files · 2 systems · 1 AC |
| 8 | Helix plan marker | Helix planning records the workflow marker, reference and checkpoint gate contract. | `.agents/skills/helix/**`, `tests/test-helix-plan.sh` | 2, 7 | 3 | `bash tests/test-helix-plan.sh` | 3 planned files · 2 systems · 1 AC |
| 9 | Prototype digest prompt | The fresh build prompt carries the approved prototype digest and invalidates stale visual authority. | `.agents/skills/slice/SKILL.md`, `.agents/skills/slice/references/build-prompt.md`, `tests/test-helix-plan.sh` | 2, 8 | 8 | `bash tests/test-helix-plan.sh` | 3 files · 2 systems · 1 AC |
| 10 | Checkpoint viewer | An HTML view reads the canonical plan and evidence to show order, statuses and review links. | `.agents/skills/helix/**`, `tests/test-helix-view.sh` | 9 | 16 | `bash tests/test-helix-view.sh` | 3 planned files · 2 systems · 1 AC |
| 11 | Stop reminder | The existing Claude Stop hook reports open gates but permits human waits and blocked exits. | `.agents/hooks/session-stop.sh`, `tests/test-helix-stop.sh` | 6 | 17 | `bash tests/test-helix-stop.sh` | 2 files · 2 systems · 1 AC |
| 12 | Helix lane | The lane catalogue registers an explicit Helix route without changing ordinary cues. | `.agents/skills/task-registry/lanes/helix.md`, `specs/lane-catalogue.md`, `tests/test-lane-catalogue.sh` | 7, 9, 10, 11 | 1 | `bash tests/test-lane-catalogue.sh` | 3 planned files · 3 systems · 1 AC |
| 13 | Route selection | `/go` chooses the Helix lane only on an explicit build request. | `.agents/skills/go/SKILL.md`, `tests/test-go-lanes.sh` | 12 | 2 | `bash tests/test-go-lanes.sh` | 2 files · 2 systems · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/helix-checkpoint-loop.md`.
Plan: `## Plan: helix-checkpoint-loop` in `tasks/todo.md`, 13 slices, ready set 1.
Files: .agents/skills/helix/**, .agents/skills/prototype/**, .agents/skills/go/SKILL.md, .agents/skills/task-registry/lanes/helix.md, .agents/skills/slice/**, .agents/skills/build/SKILL.md, .agents/skills/wrap-up-session/**, .agents/hooks/session-stop.sh, .claude-plugin/plugin.json, README.md, specs/lane-catalogue.md, tests/**.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/helix-checkpoint-loop.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Helix is opt-in and this integration is built through the existing `/build`; use the current Finding Model and GO/HOLD policy; default human review is per slice with explicit next-N delegation; one commit per future Helix slice and one PR per feature; no stacked PRs in v1; bounded retries block without bypass; a transition CLI enforces gates across harnesses; final integrated human acceptance precedes wrap-up.
```
## Decisions

| Decision | Options | Recommended | Wrong when |
|----------|---------|-------------|------------|
| Activation | Opt-in route / replace ordinary build | **Opt-in**, source: user | Replacement is justified only after real downstream runs establish parity |
| Approval cadence | Per slice / batches / final only | **Per slice**, with explicit next-N grants, source: user | A human cannot inspect each slice; they may then delegate named slices |
| UI reference | Prototype for significant new UI / every UI / docs alone | **Approved prototype when significant**, existing reference for migrations and `DESIGN.md`/concept for localized UI, source: user | A prototype would merely duplicate an already runnable reference |
| Review verdict | New all-findings-fixed rule / existing GO-HOLD-STOP | **Existing receipt policy**, with two independent verdicts, source: user | The current policy cannot represent a proven blocker; fix that policy rather than fork it |
| Commit/PR shape | Slice commits in one PR / stacked PRs / one final commit | **Slice commits in one PR**, source: user | Stacked PR support becomes cheap only after closure can track a chain of PR bases and CI |
| Retry | Unlimited / bounded and blocked | **Existing bounded escalation**, source: user | A recoverable environment issue is resolved; resume from retained evidence |
| Enforcement | Agent-written Stop state / validated transition CLI | **Validated advancement**, source: conversation | A harness supplies a stronger trusted gate without trapping legitimate pauses |
| Evidence identity | Current HEAD / explicit candidate fingerprint | **Explicit fingerprint**, source: inferred | A later commit or worktree merge otherwise makes `HEAD` refer to different bytes |

## Acceptance Criteria

- The lane catalogue registers a distinct Helix route with explicit cues and no fallback from ordinary requests.
- `/go` selects that route only for an explicit Helix build request; ordinary requests retain their current lane and no unmarked plan changes behavior.
- Helix planning marks the spec `workflow: helix/1`, carries that mode into the fresh build prompt, and records each checkpoint's reference, applicable gates and done criteria in the Build Order.
- The versioned gate CLI refuses malformed, missing, stale or wrong-slice evidence and refuses an active run whose marker disappears; repeated identical records are idempotent. A slice candidate hashes declared Surface bytes and mode while excluding `tasks/**`, and old receipts verify against their recorded commit tree.
- A done Helix header without valid committed evidence and a committed barrier for the exact merged slice set and current combined tree cannot release a dependent slice; valid proof can. Legacy `slice.py ready` fixtures remain unchanged.
- A fresh test-planner context expands each checkpoint's user-perspective behavior cases before a separate implementer writes code, and Gate 1 records a failing test followed by a passing affected-test run on the candidate tree.
- The prototype skill produces a self-contained interactive HTML reference and explicit reachable-state manifest from approved design inputs before implementation.
- Helix planning carries the approved prototype path and digest in the spec and fresh build prompt; a changed prototype invalidates affected UI evidence and grants.
- UI slices compare real app and reference captures for the same state, viewport and slice scope; state mismatch is `INVALID`, fixable visual differences block, and only non-UI slices may skip with a reason; capture hashes and paths remain available for PR publication.
- Two context-isolated reviewers check each candidate independently using the review dispatch contract; existing GO/HOLD/STOP policy controls Gate 3, and fixes rerun affected tests and changed UI comparisons.
- Each slice waits for owner review by default; an explicit next-N grant from a host role-tagged owner turn applies only to the exact named slices and is recorded as delegated, never as personal approval. Agent-authored or unverifiable resumed grants are refused.
- Exhausted repair attempts or unavailable required capabilities block the affected slice with evidence without releasing descendants; unrelated ready slices can continue.
- Closing a slice records its evidence and handover, marks its header done, and produces one orchestrator-owned commit before its dependents become ready; a failed commit cannot release them.
- Disjoint ready slices may implement in isolated worktrees without writing shared status; the orchestrator integrates source in table order, then dependent slices wait for central affected-test and quality checks recorded in a committed barrier bound to the exact merged slice set and combined tree.
- Human corrections are captured in relevant typed learnings and the next slice's handover/context without a second flat memory store.
- The Helix route renders a reviewable checkpoint view with statuses and evidence links from the canonical spec, todo and receipts.
- A Claude Stop hook reports open gates yet permits human waits and blocked exits, while Codex and Pi use the same gate CLI for advancement.
- After all slices, the owner reviews the integrated feature; requested changes become gated slices, and final `/wrap-up-session` waits for acceptance before checking every slice and integrated quality receipt, running the cached full suite, publishing captures, pushing the slice-commit branch and maintaining one PR; ordinary-build closure still works.

## Implementation Paths

- `.agents/skills/helix/**` — opt-in gate contract, versioned evidence validation, grant scope, advancement and cross-harness orchestration.
- `.agents/skills/prototype/**` — interactive reference authoring and state manifest validation.
- `.agents/skills/go/SKILL.md`, `.agents/skills/task-registry/lanes/helix.md`, `specs/lane-catalogue.md` — explicit Helix route without changing ordinary route precedence.
- `.agents/skills/slice/**` — prototype digest in the build prompt and ready-set gate check.
- `.agents/skills/build/SKILL.md` — fresh test-planning and implementation contexts, per-slice gate order, retry/resume, human review, commit and parallel integration barrier.
- `.agents/skills/wrap-up-session/**` — final single-PR closure over slice commits and retained visual evidence.
- `.agents/hooks/session-stop.sh` — optional Claude Stop reminder without replacing the transition gate.
- `.claude-plugin/plugin.json`, `README.md`, `tests/**` — plugin version, skills table and focused cross-harness, legacy and failure fixtures.
