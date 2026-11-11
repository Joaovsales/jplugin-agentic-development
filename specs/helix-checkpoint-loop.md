---
implementation_paths:
  - .agents/skills/helix/**
  - .agents/skills/prototype/**
  - .agents/skills/quality-gate/**
  - .agents/skills/go/SKILL.md
  - .agents/skills/task-registry/lanes/helix.md
  - .agents/skills/slice/**
  - .agents/skills/build/**
  - .agents/skills/wrap-up-session/**
  - .agents/hooks/session-stop.sh
  - .claude-plugin/plugin.json
  - README.md
  - specs/lane-catalogue.md
  - tests/**
---

# Spec: Helix checkpoint loop

> Origin: conversation · Designed 2026-10-04 · Review status: **portable worker review revised; 3 findings applied, 0 declined**
> Visual: specs/helix-checkpoint-loop.plan.html

## Problem

Agents building features through this template currently close slices after TDD and a handover, while visual and code review evidence is collected later for the whole build. An explicit Helix route makes each slice an evidence-gated checkpoint, so dependent work starts only after that slice has passed the applicable behavior, UI, code review and human gates and has its own commit. Explicit review units can publish groups of slices as a linear stack of smaller PRs. Shopify-specific mobile tooling remains outside the first release.

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
| Commit boundary | One commit per cleared slice, with source, plan status and evidence together; one PR when no review units are declared, or one PR per declared review unit in a linear stack | user | single-PR and stacked-PR closure fixtures |
| Review units | A stack is explicit and groups contiguous slices into independently green, reviewable PRs; every slice belongs to exactly one unit. A unit must not be one PR per slice merely because slices exist | user | coverage, ordering and independent-PR fixture tests |
| Stack merge policy | A stacked run never rewrites published slice commits. Parent PRs use merge commits; squash/rebase merge, force push, unavailable merge-commit policy or unverifiable ancestry blocks stack advancement | inferred | merge-strategy, rewritten-SHA and ancestry fixtures |
| Parallel work | Disjoint ready slices may implement in separate worktrees; the orchestrator integrates them in table order and records a barrier for the exact merged slice set and combined source tree before dependent work advances | inferred | two-worktree merge and stale-barrier fixtures |
| Shared run writes | Workers edit only their declared source Surface and produce private evidence drafts. The orchestrator alone writes `tasks/todo.md`, `run.json`, final slice evidence and commits on the integration branch | inferred | parallel shared-file collision fixture |
| Worker backend | `/build --worker-backend` accepts `auto`, `native` or `orca` and selects execution transport, not a gate policy. `auto` prefers a verified Orca orchestration runtime for this worktree, then a capable host-native dispatch; explicit `orca` refuses when unavailable. No selection weakens isolation, review or evidence rules | user | capability, selection and refusal fixtures |
| Runtime portability | Planning works without a worker runtime. Building requires repository write access, Git, test execution, isolated reviewer contexts and a supported worker backend; a host lacking these blocks the build with missing capabilities rather than pretending Helix ran | inferred | no-runtime and partial-capability fixtures |
| Owner authority | A next-N grant comes from a role-tagged owner turn exposed by the active host; an agent-authored record or unverified imported transcript cannot create one. Across sessions, a grant needs host-verifiable provenance or the owner must reissue it | inferred | role/provenance and resume fixtures |
| UI reference | A migration uses the existing app; a visually significant new feature uses an approved interactive prototype; a localized UI change may use the approved `DESIGN.md` and concept; logic-only slices record a UI skip reason | user | prototype and visual-gate fixtures |
| UI evidence retention | Gate 2 keeps capture hashes and local paths per candidate; wrap-up publishes the retained captures with the existing PR visual-evidence mechanism, or leaves the UI task open when publication is unavailable | inferred | publication fixture with two slice captures |
| Harness support | Gate advancement is host-neutral where the host exposes repository, Git and test tools; Claude Code, Codex and Pi use the local CLI without a Stop hook, while Claude Desktop or claude.ai may build only when their connected tools meet the same capability contract. A Claude Stop hook may prompt continuation but permits `waiting_human` and `blocked` stops | user | CLI, capability and Stop-hook fixtures |
| Test economy | Each review unit uses affected tests at slice/integration checkpoints and the existing cached full suite before its PR push; the final integrated tree is checked again after retargeting the last PR | user | per-unit command-count and retarget fixtures |

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
| Git common dir `helix-worker-attempts/`, **NEW** | Local attempt identity, chosen backend and result acceptance; operational state, never a gate receipt | Run/slice IDs and backend observations |
| `tasks/helix/<feature>/barriers/<id>.json`, **NEW** | Exact merged-set integration result for one combined candidate | Integrated commits, affected tests and quality receipt |
| Spec § Build Order `Review units`, **NEW** | Ordered unit IDs, exact slice ranges and parent unit relation; absent means one PR | Slice table and owner-selected review boundaries |
| GitHub PRs | Live PR number, base/head, draft/merge state, checks and review history | The declared unit chain; never inferred from a stale local cache |
| Helix gate CLI, **NEW** | Versioned per-slice evidence, gate transitions, grant scope and closed-slice verification | Run, spec, todo, test output, UI manifest and quality receipt |
| `/slice` | Dependency graph, surface validation and ready set | Todo statuses and Helix gate verification for marked plans |
| `/build` | Fresh test-planner and implementer dispatch, repair loop, one commit per cleared slice and review-unit boundary | Ready set, gate outcomes, reviewer findings and declared unit mapping |
| Worker backend adapter, **NEW** | Capability probing and supervised slice-attempt lifecycle for `native` or optional `orca`; never gate verdicts | Pinned integration SHA, slice ID, Surface, task/spec digest, backend preference and local attempt record |
| Orca orchestration, optional | Live Dispatch, request and worker liveness when Orca was selected; its state is re-queried after timeouts | Dispatch/request IDs from the local attempt record |
| `/quality-gate` | Existing GO/HOLD/STOP policy and tree-bound review receipt | Changed code and reviewer evidence |
| `prototype` skill, **NEW** | Interactive reference HTML and declared UI states before implementation | `DESIGN.md`, approved concept and spec |
| `tasks/solutions/` | Reusable corrections and decisions | Slice feedback and source evidence |
| `/wrap-up-session` | Per-unit quality/full-suite/PR/CI closure and final integrated closure after human acceptance | Slice commits, unit mapping, live PR state, final review and final tree receipt |

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
                                   review unit complete? ──yes──► PR to parent unit branch
                                                      │                        │
                                           next ready set           parent merges; retarget + recheck
                                                                               │
                                                                    final integrated review + wrap-up
```

| Arrow | Mode | On timeout or failure | On duplicate |
|-------|------|-----------------------|--------------|
| `/build` → gate CLI | sync, local | Refuse the current slice; preserve recorded evidence for resume | Recheck the same evidence, never add a second approval |
| Gate CLI → tests | sync, local | Record command and nonzero exit; gate stays open | Same command and candidate tree may reuse a green cached run |
| `/build` → reviewer agents | async dispatch | Mark `blocked` after the existing retry ladder; no fabricated verdict | A reviewer ID and candidate fingerprint identify one verdict |
| `/build` → worker backend | async attempt, private checkout | On unknown liveness retain and re-query the same attempt; no retry or backend switch until failure/stop is positively settled; terminal exit alone never clears a gate | Stable run/slice/attempt ID and pinned base SHA prevent duplicate editing |
| Owner → human gate | async conversation | `waiting_human`; the session may end without advancing | The same grant ID applies only to its named slices once |
| Worktree → integration branch | sync Git operation, serialized by orchestrator | Merge conflict or failed central test blocks dependent slices | Reapplying a merged slice is refused by its stable slice/task ID |
| Unit branch → GitHub PR | async network call | `unknown`: re-query by head/base before retry; leave this unit and descendants draft/blocked if state remains unknown | Find the existing PR by exact head/base and unit ID; never create a second PR |
| Parent PR → child PR | async merge observation then sync Git merge/retarget | A changed or unmerged parent keeps the child based on the parent branch and invalidates its combined barrier/CI claim | Re-query parent merge commit and child base before any merge or retarget |

### Failure unit

- A gate failure blocks its slice and descendants, while unrelated ready slices may continue.
- A missing reviewer, browser or UI reference blocks only slices that require that gate; it does not turn a failed check into a skip.
- An invalid Helix evidence record makes `ready` fail closed for the marked plan; legacy plans are unaffected.
- A combined-tree integration failure blocks the next dependency wave and final wrap-up, including slices whose isolated worktree tests passed.
- An unavailable screenshot publication path leaves the UI task open under the existing visual-evidence policy, even if local comparison passed.
- An upstream PR change blocks this unit's ready-for-review state until the parent is merged into its branch and its combined-tree checks rerun. A blocked unit does not erase already valid slice receipts on preserved commits.
- A failed, unknown or non-preserving PR merge blocks descendants; unrelated slices already under development can retain drafts, but no dependent PR is reported merge-ready.
- Orca absence before dispatch selects `native` only in `auto` mode and only when native capabilities pass. An explicit `orca` request refuses. A launched worker with unknown or unverifiable liveness is never retried or replaced; a positively confirmed stop/failure and inspection of private changes are required before a new attempt.

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

### Slice worker execution

```text
/build --worker-backend auto|native|orca
dispatch(slice_id, pinned_base_sha, Surface, task_digest, timeout) -> attempt_id
observe(attempt_id) -> running | reported | failed | stopped | unknown
collect(attempt_id) -> source_delta, draft_evidence, bounded_log_pointer | refused
```

| Aspect | Contract |
|--------|----------|
| Inputs | The build prompt or `/build` argument chooses `auto` (default), `native` or `orca`; each attempt receives exact run/slice IDs, immutable base SHA, declared Surface, task/spec digest, role and bounded work budget. The selector is execution configuration, never part of `workflow: helix/1` or a second gate policy. |
| Outcomes | `native` uses the host's existing isolated subagent/worktree path. `orca` uses supervised Orca orchestration with a distinct child worktree and a Dispatch ID, addressing the worker through orchestration rather than a terminal handle; a user launch setting may create a PTY or no terminal. `auto` chooses Orca only after a read-only probe confirms a running matching Orca worktree and the ability to start a worker in a separately verified checkout; otherwise it chooses capable native dispatch and reports the choice. |
| Raises | Explicit `orca` with unavailable runtime or mismatched repository refuses before dispatch. `auto` with neither capable backend blocks and lists missing capabilities. A host without repository write, Git, tests or independent reviewer contexts may plan and inspect evidence but cannot claim a completed build. A process exit, `worker_done` report or worker-supplied evidence is never a Helix gate verdict. |
| Idempotency | The orchestrator persists an attempt ID, backend identity, pinned SHA, backend request/Dispatch ID, lifecycle state and bounded log/result pointers under the Git common dir, outside worker checkouts. The attempt ID is the retry key; only the current attempt's result can be accepted for a slice. A new attempt is permitted only after the prior worker is positively confirmed failed or stopped and its private changes are inspected. Orca request lookup resolves ambiguous network results before mutation is repeated; contact loss or `unverifiable` is never proof of stop. |
| Versioning | Worker transport contract `helix-worker/1` is independent of evidence schema `helix-evidence/1`; a backend can be added without changing slice receipts. An ordinary build without the Helix marker retains its existing dispatch behavior unless the user explicitly invokes a supported backend. |

The orchestrator writes a `created` attempt and stable request ID before calling an external launcher; if it crashes between the local write and Orca's response, it queries that request ID before retrying. The local record owns result acceptance, while Orca owns live Dispatch state; an old local observation never proves a worker stopped. The orchestrator pins all parallel workers in a wave to the same integration commit and verifies each returned delta against that SHA and Surface before serial integration. Orca `--base-branch` chooses a ref but does not prove the exact SHA. Because `worker-start --spec` creates the worktree and sends the task in one operation, the adapter must create and verify the child worktree at the pinned SHA **before** starting a worker in that exact checkout; if the installed runtime cannot target the verified checkout, the Orca backend refuses before dispatch. It verifies the returned delta's base independently. Only the orchestrator writes shared plan/run state, authoritative evidence, commits and barriers. Reviewer contexts and owner-role checks remain separate from implementer worker transport. A host-native backend may run slices sequentially when it cannot provide safe parallel worktrees, but it must still provide the required independent reviewers and tests. No host is assumed to expose local terminals merely because it can display the spec; this includes Claude Desktop and claude.ai configurations.

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

### Review units and stacked PRs


```text
stack.py validate --spec PATH --index PATH -> units | invalid
stack.py inspect --spec PATH --unit ID -> planned | draft | ready | merged | stale | blocked | unknown
wrap-up-unit(spec, unit_id, expected_parent) -> PR(number, head, base) | blocked | unknown
```


| Aspect | Contract |
|--------|----------|
| Inputs | Explicit ordered `Review units` in the spec's Build Order, each naming a contiguous slice range; run ID from `run.json`; default branch; preserved slice commits and latest combined barrier; live GitHub PR observations |
| Outcomes | With no units, existing one-PR closure. With units, one branch and one PR per unit: `helix/<feature>/<run-id>/u<ID>` targets the preceding unit branch, or the default branch for the first. The PR diff covers only that unit; a child stays draft while its parent is unmerged. |
| Raises | A missing GitHub remote/authentication, disabled merge-commit strategy, rewritten slice SHA, duplicate head/base PR, changed base without revalidation, noncontiguous unit coverage or ambiguous remote state blocks stacked closure. No automatic fallback to one PR after a stack is published. |
| Idempotency | Unit ID plus run ID fixes the branch name; inspect exact head/base and existing PR before create or edit. On network timeout return `unknown`, then re-query; never issue a second create from a timeout alone. Repeated sync of an unchanged unit updates the same PR body. |
| Versioning | `Review units` grammar v1 is accepted only for `workflow: helix/1`; absent units mean single-PR mode. Current branch-local `closure.py` state remains a retry cache; GitHub is authoritative for PR state. Unknown grammar or mutation of a published unit's ID, start, end or base is refused. |

Grammar v1 is a `### Review units` subsection of § Build Order with one bullet per unit: `- U<n>: slices <start>-<end>; base: <default|U<n>>; <short purpose>`. IDs start at U1 and increase without gaps; ranges use ASCII hyphens and cover slice numbers once in table order; each base is the preceding unit except U1, whose base is `default`. The purpose is display text, never a parser input. A missing subsection means single-PR mode. A present but empty or malformed subsection is an error, not a fallback. The plan block mirrors the IDs and ranges for the builder, but the spec is authoritative.

`/slice` validates that units cover every slice exactly once, in table order, with no gaps or overlaps, and that each unit's last slice has a valid combined barrier before its PR opens. Publication freezes that unit's ID, range and base. A correction to a slice in an open unit reopens that slice under the same ID: append a linked correction commit on that unit branch, supersede its candidate evidence, rerun its gates and unit checks, and propagate the new parent head to descendants. A merged unit cannot be edited. New scope, including changes requested at final integrated review, becomes new numbered slices in an appended tail unit; previously published ranges never move. Unpublished suffix units may be regenerated to preserve contiguous coverage, but publication freezes each in turn. If a correction to a merged unit cannot be expressed as a tail slice without invalidating an ancestor's merge, stop for an explicit recovery plan. A unit can group multiple slice commits; an initial slice closure creates one commit, while a reopened slice may add linked correction commits without rewriting history.

The first unit branches from the default branch before its first slice; every next unit branches from its predecessor's published head before its first slice. Each unit carries its own GO or approved-HOLD quality receipt, cached full-suite run, CI result, handovers and visual evidence, with intermediate PRs using `Refs` and only the final PR allowed to use `Closes` issue linkage. For unit-local spec reconciliation, affected tests, quality receipt fingerprint and PR body, the explicit base is the parent unit branch (default for the first), never the single-PR default. Unit-scoped `/quality-gate --spec PATH --unit ID --base REF` is permitted when **that unit's** slices and combined barrier are done; it runs the existing six phases and Finding Model against the unit diff, writes an immutable receipt keyed by run, unit, base and fingerprint, and leaves later units pending. Slice 3 introduces one shared review-unit reader for this boundary check; `/slice` reuses and extends that reader for full coverage validation in slice 14. `receipt.py fingerprint` and `check` already accept `--base`; `write` gains the same argument, and every gate caller uses the identical resolved base. A changed unit head/base invalidates that unit receipt and any descendant receipt until the same gate reruns. The combined barrier and final owner review additionally cover the integrated source tree.

Published branch histories are never rebased or force-pushed. When a parent changes, merge its new head into the child, rerun candidate-sensitive gates, central affected tests, the quality receipt, the cached suite and child CI, and keep the child draft until clean. After a parent PR is merged with a **merge commit** into the default branch, verify every recorded slice commit remains an ancestor, explicitly retarget the child PR to the default branch, merge the updated default branch into the child if needed, and verify that the resulting PR diff contains only that child's declared unit changes. Then rerun the combined barrier, receipt, suite and CI on the new head/base before making that child ready. Squash or rebase merge cannot preserve the per-slice commit identity required by `verify`; if observed, stop stack advancement and report recovery as a human decision instead of accepting a rewritten history. No agent auto-merges a PR.

Intermediate unit PRs can be reviewed while later units are built. The final unit remains draft until every parent has merged, the last branch has passed integrated checks against the default branch, and a fresh owner turn accepts the integrated feature. A failed or unknown merge, retarget, check or publication leaves the affected and descendant PRs draft with evidence. Ordinary builds and one-PR Helix runs retain the current wrap-up contract.

## Data models

### Entities

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `workflow` | `helix/1` or absent | An active Helix run never silently downgrades when the marker disappears | gate CLI activation check |
| `run` | `tasks/helix/<feature>/run.json` | Holds activation and final review only; slice completion remains in todo and proof remains in slice files | versioned run validator |
| `worker_attempt` | Git common dir `helix-worker-attempts/<run>/<slice>/<attempt>.json`, schema `helix-worker/1`: IDs, backend, pinned SHA, Surface/task digests, backend Dispatch/request ID, state and bounded pointers | Operational state survives a local orchestrator restart without becoming gate evidence; only the current settled attempt's result may be accepted | backend adapter and resume preflight |
| `slice_id` | stable task ID plus slice number | Matches spec Build Order and todo heading | `slice.py` validation and gate CLI |
| `candidate` | Surface manifest hash + slice-contract/prototype/policy digests | Evidence refers to the code and requirements each gate examined; `tasks/**` bookkeeping cannot stale it | gate CLI fingerprint validation |
| `gate` | behavior, UI, review, human | Every required gate has producer, outcome, evidence path/hash and timestamp | `helix-evidence/1` validator |
| `grant` | ID, host/session/message reference, owner role, message digest, full-plan digest, exact slice IDs | Only a host-verified owner turn may authorize named slices; changed plan or lost provenance revokes applicability | host role check and grant validator |
| `commit` | Git commit containing code, status and receipt | A done header is not ready until committed evidence is reachable; a stack merge preserves each slice commit ID | `ready` and post-merge ancestry verification |
| `barrier` | version, sorted merged slice IDs, combined manifest hash, prior ordered slice commit IDs, test and quality evidence | A dependent can start only from the exact merged set and combined source tree that passed central checks; the final commit ID is derived from Git | `verify-barrier` |
| `review_unit` | stable ID, ordered inclusive slice range, predecessor ID | Exact one-time coverage of the Build Order; source of truth is spec § Build Order, not PR titles | `stack.py validate` |
| `unit_pr` | observed head/base SHA, branch, PR number, draft/ready/merged state, checks and merge method | GitHub owns live values; local closure cache never overrides a fresh observation | `stack.py inspect`, wrap-up and Git ancestry check |
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
| Two live attempts edit one slice, or a worker report closes a gate | one unsettled attempt per slice; orchestrator-only evidence and close validation |
| Two PRs for one unit, a child PR based on the wrong parent, or a unit missing a slice | stable branch/PR lookup and review-unit coverage validation |
| Child PR ready while parent is unmerged or parent head changed | draft-state and base/head checks before ready transition |
| Stack marked merged after squash/rebase rewrote slice commit IDs | post-merge ancestry verification; stop descendant advancement |

### Transitions — worker attempt

| From | To | Trigger |
|------|----|---------|
| `created` | `running` | Backend returns a confirmed Dispatch/worker identity and the private checkout matches the pinned SHA |
| `created` / `running` | `unknown` | Startup, observation or network call times out; retain request ID and re-query before any retry |
| `unknown` | `running` / `reported` / `failed` / `stopped` | Backend observation resolves the exact attempt |
| `running` | `reported` / `failed` / `stopped` | Worker reports a source result or backend proves failure/stop |
| `reported` | `accepted` / `failed` | Orchestrator validates base SHA, Surface and current attempt ID; acceptance only admits source for integration, never closes gates |
| `accepted` / `failed` / `stopped` | `released` | Result is integrated or rejected, logs remain at a bounded pointer, and backend resources are cleaned up |

A retry creates a new attempt ID only after the prior worker is positively confirmed failed or stopped, its private changes are inspected and the prior record is released; it does not move that record back to `created`. A resumed host reads the local attempt record and re-queries the backend before deciding whether it may start another attempt. Cross-host continuation requires transfer of the original Git common-dir attempt record and confirmation that every prior attempt is settled; without that record the new host refuses to dispatch on the same run, even at a committed slice boundary. A new independent run may start after the old host's worker resources are positively shut down. An imported transcript cannot establish liveness.

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
| `accepted` | `waiting` | A stacked PR is retargeted or its parent/default base changes before final closure |

### Transitions — integration barrier

| From | To | Trigger |
|------|----|---------|
| `absent` | `passed` | Central affected tests and quality gate pass on the exact combined candidate; record is committed with the final slice of the wave |
| `absent` | `failed` | Merge, test or quality check fails; retain command/result and block dependents |
| `failed` | `passed` | Repair and rerun both central checks on the new combined candidate |
| `passed` | `stale` | Completed slice set or combined source manifest changes |
| `stale` | `passed` / `failed` | Rerun central checks and commit a new barrier record |

### Transitions — review unit PR

| From | To | Trigger |
|------|----|---------|
| `planned` | `branch` | The declared base exists; create the stable branch before implementing this unit's first slice |
| `branch` | `draft` | Every unit slice closes and its combined barrier passes; push, query exact head/base, then create or reuse the draft PR |
| `draft` | `ready` | Parent is merged or this is the first unit; current head/base, quality receipt, full suite, CI and required owner review pass |
| `draft` / `ready` | `stale` | Parent head/base, unit source or policy changes; return to draft and invalidate affected barrier/receipt/CI |
| `stale` | `draft` | Merge parent without rewriting history, retarget if merged, rerun affected gates and central checks |
| `draft` / `ready` | `merged` | Remote says merged with a merge commit and recorded slice SHAs are ancestors of the default branch |
| `planned` / `branch` / `draft` / `ready` | `unknown` | GitHub create, query, retarget or merge observation times out; never infer success or retry creation blindly |
| `unknown` | observed state | Query exact branch, PR and base/head after service recovers |
| `draft` / `ready` / `stale` | `blocked` | CI, conflict, unavailable merge policy or rewritten commit fails verification; retain evidence and keep descendants draft |
| `blocked` | `draft` | Correct the cause and rerun the unit checks on the current candidate |

### Migration and compatibility

- Existing specs without `workflow: helix/1` and their flat or sliced plan blocks follow the current route, build and ready behavior without new evidence files.
- An active run's evidence remains discoverable if its marker is removed; removal produces a refusal, not a downgrade. Cancelling a run is an explicit recorded action, after which ordinary planning may start a new spec revision.
- Evidence records are retained when superseded. New readers validate `helix-evidence/1`; unknown versions fail closed only for Helix plans. A reopened or appended correction slice changes the plan digest and grants; prior receipts remain historical evidence, and affected unit and descendant receipts are revalidated.
- Rollback disables the opt-in route for new plans while active Helix plans remain gated or explicitly cancelled. No existing task, quality receipt or E2E log format is migrated.
- Plans without explicit `Review units` keep one PR and the existing closure contract. A declared stack is linear and cannot silently downgrade once its first PR exists. Existing `closure.py` state stays branch-local; live PR facts are re-queried from GitHub on resume.
- Stack mode requires a GitHub remote and a merge-commit path that preserves published slice SHAs. Projects that permit only squash/rebase merges use one-PR mode until they change that policy. A wrong-method merge stops descendants for explicit recovery; old evidence remains auditable but is never rebound to a different commit silently.
- Worker backend selection is independent of stack mode and Helix evidence. `auto` records its choice at each attempt; Orca is used only when its supervised orchestration runtime matches this worktree. Hosts without Orca use native dispatch when capable. A missing execution or reviewer capability blocks the build, while planning and evidence inspection remain available.
- Disabling the Orca adapter prevents new Orca attempts but retains local `helix-worker/1` records under the Git common dir for recovery. Existing native and evidence readers ignore those records; an active Orca attempt must be positively settled before native work resumes on that slice. Unknown future attempt schemas are refused for that slice, not interpreted as stopped. Cross-host transfer requires the original attempt record and positive settlement of every attempt; without the record, continuing the same run is refused.
- The Claude Stop reminder checks whether the run may pause before the existing session-stop cleanup; a blocked continuation keeps the session-active sentinel intact.

## Build Order

Sizing: 19 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: the new skill inventory, plugin pin and gate tests must ship together; slice 12: the lane declaration and canonical lane catalogue must agree in one change; slice 14: the review-unit schema and its `/slice` consumer must validate one shared grammar.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Evidence kernel | Versioned evidence validates Surface manifests, historical commit identity, barrier records, gate order, staleness and idempotence without enabling a route. | `.agents/skills/helix/**`, `README.md`, `.claude-plugin/plugin.json`, `tests/test-helix-gates.sh` | — | 4 | `bash tests/test-helix-gates.sh` | 4 planned files · 3 systems · 1 AC |
| 2 | Prototype reference | A design-grounded clickable HTML reference exposes named, reachable UI states. | `.agents/skills/prototype/**`, `README.md`, `tests/test-helix-prototype.sh` | 1 | 7 | `bash tests/test-helix-prototype.sh` | 3 planned files · 2 systems · 1 AC |
| 3 | Readiness and unit gate | `slice.py ready` refuses unproved Helix blockers and stale barriers while legacy readiness stays stable; `/quality-gate` uses a shared review-unit reader to review a completed unit against its parent base and retain its receipt while later units remain pending. | `.agents/skills/helix/**`, `.agents/skills/slice/scripts/slice.py`, `.agents/skills/quality-gate/SKILL.md`, `.agents/skills/quality-gate/scripts/receipt.py`, `tests/test-slice.sh`, `tests/test-helix-unit-gate.sh` | 1 | 5, 23 | `bash tests/test-slice.sh && bash tests/test-helix-unit-gate.sh` | 6 files · 3 systems · 2 ACs |
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
| 14 | Review-unit plan contract | The planner validates exact ordered slice coverage and records optional review units without changing single-PR plans. | `.agents/skills/helix/**`, `.agents/skills/slice/**`, `tests/test-helix-stack-plan.sh` | 7, 9, 13 | 19 | `bash tests/test-helix-stack-plan.sh` | 4 planned files · 3 systems · 1 AC |
| 15 | Stack branch lifecycle | Stable unit branches and PRs track explicit parent bases, preserved commits, remote outcomes and stale parents. | `.agents/skills/helix/**`, `tests/test-helix-stack-branch.sh` | 14 | 20 | `bash tests/test-helix-stack-branch.sh` | 3 planned files · 2 systems · 1 AC |
| 16 | Build unit boundaries | `/build` publishes a proved unit, creates the next branch from its head and carries handovers and barriers across the boundary. | `.agents/skills/build/SKILL.md`, `tests/test-helix-stack-build.sh` | 15 | 21 | `bash tests/test-helix-stack-build.sh` | 2 files · 2 systems · 1 AC |
| 17 | Stacked closure | Wrap-up checks each unit's retained receipt, suite, CI, merge ancestry and retargeted diff; final PR waits for integrated owner acceptance. | `.agents/skills/wrap-up-session/**`, `tests/test-helix-stack-wrapup.sh` | 16 | 22 | `bash tests/test-helix-stack-wrapup.sh` | 3 planned files · 2 systems · 1 AC |
| 18 | Worker backend selector | `/build` accepts `--worker-backend` values `auto`, `native` or `orca`, probes capabilities without mutation, records each attempt and preserves native behavior when Orca is absent. | `.agents/skills/build/SKILL.md`, `.agents/skills/build/scripts/worker-backend.py`, `tests/test-helix-worker-selector.sh` | 17 | 24 | `bash tests/test-helix-worker-selector.sh` | 3 planned files · 2 systems · 1 AC |
| 19 | Orca supervised worker | The optional Orca adapter starts a slice in a child worktree, supervises its Dispatch ID and settles failures before retry/fallback. | `.agents/skills/build/scripts/worker-backend.py`, `.agents/skills/build/scripts/orca-worker.py`, `tests/test-helix-orca-worker.sh` | 18 | 25 | `bash tests/test-helix-orca-worker.sh` | 3 planned files · 2 systems · 1 AC |

### Review units

- U1: slices 1-3; base: default; evidence kernel and readiness.
- U2: slices 4-7; base: U1; behavior, UI, human gates and single-PR compatibility.
- U3: slices 8-13; base: U2; planning, viewer, reminder and explicit route.
- U4: slices 14-17; base: U3; stacked-PR contract, branch lifecycle and closure.
- U5: slices 18-19; base: U4; portable worker selection and optional Orca supervision.

These are the review boundaries for implementing this spec. This implementation is an **ordinary `/build` bootstrap**, not a Helix run: before U1, record a provisional bootstrap ID and default-branch SHA in the first build handover, and create `helix/helix-checkpoint-loop/<bootstrap-id>/u1`. Its ID is never rebound to a `run.json` ID. Before each next unit, branch `u<n>` from the preceding published unit head. Until the stack helper exists, use explicit Git and `gh pr create --draft --base <parent>`; inspect the exact remote head/base before creation and after timeouts.

Run `/build` only through the current unit boundary in a fresh session, closing that unit's slices and combined barrier; the user-supplied per-unit prompt authorizes this bootstrap boundary even though ordinary `/build` normally runs the whole plan. Slice 3 adds unit-scoped `/quality-gate`, so U1 can run it at its boundary. Run that gate with the parent base, save its immutable receipt, run the cached full suite, push the unit branch, open its draft PR, and wait for CI and review before marking it ready. Record the PR, receipt fingerprint, base/head SHAs and next-unit branch in the handover. Do not invoke the existing terminal one-PR `/wrap-up-session` for U1–U3; the manual steps above are their interim closure. Resume the next unit from the preceding published head while the parent PR is under review. After each parent merge, apply the retarget, ancestry, diff and recheck procedure above. U4 uses the finished stacked closure for an intermediate PR; U5 is the final PR and receives the integrated owner review. The Helix stack contract is available to downstream runs after U4 merges; native worker execution remains functional without U5, while `--worker-backend orca` is available only after U5 lands.

Build prompt:

```
Invoke `/build` for `specs/helix-checkpoint-loop.md`.
Plan: `## Plan: helix-checkpoint-loop` in `tasks/todo.md`, 19 slices, ready set 1.
Files: .agents/skills/helix/**, .agents/skills/prototype/**, .agents/skills/go/SKILL.md, .agents/skills/task-registry/lanes/helix.md, .agents/skills/slice/**, .agents/skills/build/**, .agents/skills/wrap-up-session/**, .agents/skills/quality-gate/**, .agents/hooks/session-stop.sh, .claude-plugin/plugin.json, README.md, specs/lane-catalogue.md, tests/**.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing. This bootstrap starts on U1; record a provisional bootstrap ID and base SHA before slice 1 and branch as § Review units specifies.
2. Build only slices 1–3 in the first fresh session. At each later fresh session, build only the next unit's declared range. A slice edits only its Surface in § Build Order. This explicit bootstrap boundary overrides ordinary `/build`'s all-task continuation.
3. At every unit boundary, run the unit-scoped existing quality gate with the exact parent base, cached full suite and CI; preserve the receipt and follow the interim publication/handover runbook in § Review units. Keep child PRs draft until their parent merges. Do not invoke terminal one-PR `/wrap-up-session` for U1–U3.
4. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user. Reopen a slice for an in-unit correction or append a tail unit for new scope; do not change published ranges.
5. Close every slice with a `> Handover:` line; after U5 and integrated owner acceptance, run the new stacked closure in `/wrap-up-session`.
Constraints: Helix is opt-in and this integration is built through ordinary `/build`; use the current Finding Model and GO/HOLD policy; default human review is per slice with explicit next-N delegation; one commit per initial slice closure and linked commits for reopened slices; explicit linear review units U1–U5 use smaller stacked PRs with preserved slice SHAs and no history rewrite; absent review units keep one PR; bounded retries block without bypass; a transition CLI enforces gates across harnesses. Bootstrap U1–U4 with the existing native dispatch. After U5, worker execution defaults to `--worker-backend auto`, selecting verified Orca when available and capable native execution otherwise; explicit `orca` refuses when unavailable and no backend switch bypasses an unsettled attempt.
```
## Decisions

| Decision | Options | Recommended | Wrong when |
|----------|---------|-------------|------------|
| Activation | Opt-in route / replace ordinary build | **Opt-in**, source: user | Replacement is justified only after real downstream runs establish parity |
| Approval cadence | Per slice / batches / final only | **Per slice**, with explicit next-N grants, source: user | A human cannot inspect each slice; they may then delegate named slices |
| UI reference | Prototype for significant new UI / every UI / docs alone | **Approved prototype when significant**, existing reference for migrations and `DESIGN.md`/concept for localized UI, source: user | A prototype would merely duplicate an already runnable reference |
| Review verdict | New all-findings-fixed rule / existing GO-HOLD-STOP | **Existing receipt policy**, with two independent verdicts, source: user | The current policy cannot represent a proven blocker; fix that policy rather than fork it |
| Commit/PR shape | One PR per feature / one PR per slice / grouped linear stack | **Grouped linear stack when review units are declared; otherwise one PR**, source: user | A project disallows merge commits or lacks a GitHub remote; use one PR before publishing a stack |
| Stack merge strategy | Merge commits / squash / rebase merge | **Merge commits preserve slice SHAs**, source: inferred | Commit identity ceases to be part of evidence; that would require a separately reviewed migration of the receipt contract |
| Worker execution | Native only / Orca mandatory / backend selector | **`auto` prefers verified Orca, else capable native; `native` and `orca` may be forced**, source: user | A host cannot provide Git, tests, repository writes or independent reviewers; report missing capabilities instead of claiming a Helix build |
| Unknown worker liveness | Retry after timeout / wait for positive settlement | **Wait for positive stop/failure before retry or fallback**, source: Orca recovery contract and architecture review | A future sandbox can enforce exclusive, revocable shared-write authority and prove old results cannot be integrated |
| Orca base pinning | Atomic new-child start / verified child checkout before dispatch | **Create and verify the child checkout first**, source: architecture review | The installed Orca runtime cannot launch a supervised worker in an existing verified checkout; then explicit Orca mode refuses |
| Cross-host continuation | Infer quiescence / transfer attempt records | **Require original local attempt records and positive settlement**, source: architecture review | A durable shared coordinator store later provides authoritative attempt identity and liveness |
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
- In single-PR mode, after all slices the owner reviews the integrated feature; requested changes become gated slices, and final `/wrap-up-session` waits for acceptance before checking every slice and integrated quality receipt, running the cached full suite, publishing captures, pushing the slice-commit branch and maintaining one PR; ordinary-build closure still works.
- A Helix plan may declare contiguous review units that cover every slice exactly once. Without them it keeps one PR; with them `/slice` rejects gaps, overlaps, reordered slices or mutation of a published unit's ID, range or base. A reopened slice preserves its ID; new scope appends numbered slices in a tail unit while unpublished suffix units may be regenerated. The build prompt and task index carry the reviewed unit boundaries.
- In stack mode, each unit uses a stable branch and one PR against its predecessor, or the default branch for the first unit. Creating or resuming a PR re-queries the remote head/base; a timeout is `unknown`, never permission to create a duplicate. Parent changes merge into descendants without rewriting published slice commits and invalidate affected evidence and checks.
- `/build` changes branches only at declared review-unit boundaries after the unit's slices and combined barrier pass; later units can build while parent PRs are under review, and blocked or stale ancestors keep descendant PRs draft.
- Each unit PR has its own existing GO/HOLD quality receipt, cached full-suite proof, CI, handovers and visual evidence. Intermediate PRs refer to the issue; only the final PR closes it. After each parent merges with a merge commit, descendants retarget to the default branch, prove their slice SHAs are still ancestors, verify the diff contains only their review unit, and rerun changed barriers, receipts, suite and CI. Squash/rebase merge, unknown state or failed checks block advancement. The final PR becomes ready only after all parents merge and the owner accepts the integrated feature; one-PR and ordinary-build closure remain unchanged.
- Unit-scoped `/quality-gate` runs the existing six phases once a unit's own slices and barrier are done, with later units still pending. It uses one explicit parent base for diff, affected tests, fingerprint and receipt write; it retains an immutable receipt per unit and invalidates that receipt on head/base changes without changing ordinary end-of-build gate behavior.
- `/build --worker-backend` accepts `auto`, `native` and `orca`, defaults to `auto`, and records the selected backend for each attempt. `auto` chooses verified Orca orchestration for this worktree when available, otherwise a capable native worker; explicit `orca` refuses before dispatch when unavailable, and hosts missing essential build capabilities block rather than weakening gates. Existing ordinary-build dispatch remains unchanged.
- The optional Orca backend creates and checks a child worktree at the pinned integration SHA before dispatch, then starts a supervised worker in that exact checkout; it refuses when the installed runtime cannot target the verified checkout. It supervises a Dispatch ID rather than a terminal handle and returns only source changes and draft evidence. Unknown or unverifiable liveness blocks retry and native fallback until positive stop/failure, private-change inspection and release. Orchestrator-only Surface checks, integration, receipts, commits, barriers, independent reviewers and host owner grants remain authoritative.

## Implementation Paths

- `.agents/skills/helix/**` — opt-in gate contract, versioned evidence validation, grant scope, advancement and cross-harness orchestration.
- `.agents/skills/prototype/**` — interactive reference authoring and state manifest validation.
- `.agents/skills/go/SKILL.md`, `.agents/skills/task-registry/lanes/helix.md`, `specs/lane-catalogue.md` — explicit Helix route without changing ordinary route precedence.
- `.agents/skills/slice/**` — prototype digest in the build prompt, ready-set gate check and optional review-unit coverage validation.
- `.agents/skills/build/**` — fresh test-planning and implementation contexts, per-slice gates, commit and unit branch boundary; runtime-neutral worker selector, persistent attempts and optional supervised Orca adapter.
- `.agents/skills/quality-gate/SKILL.md`, `.agents/skills/quality-gate/scripts/receipt.py` — optional unit-scoped invocation and base-bound retained receipts using the existing gate phases and policy.
- `.agents/skills/wrap-up-session/**` — single-PR compatibility and per-unit stacked closure over preserved slice commits and retained visual evidence.
- `.agents/hooks/session-stop.sh` — optional Claude Stop reminder without replacing the transition gate.
- `.claude-plugin/plugin.json`, `README.md`, `tests/**` — plugin version, skills table and focused cross-harness, legacy and failure fixtures.
