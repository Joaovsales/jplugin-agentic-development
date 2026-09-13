---
implementation_paths:
  - .agents/skills/task-registry/**
  - .claude/skills/task-registry/**
  - .agents/skills/debug/SKILL.md
  - .claude/skills/debug/SKILL.md
  - .agents/skills/build/SKILL.md
  - .claude/skills/build/SKILL.md
  - .agents/skills/verify/SKILL.md
  - .claude/skills/verify/SKILL.md
  - .agents/skills/wrap-up-session/SKILL.md
  - .claude/skills/wrap-up-session/SKILL.md
  - .agents/skills/sweep/SKILL.md
  - .claude/skills/sweep/SKILL.md
  - .agents/skills/verify-task-registry/**
  - .claude/skills/verify-task-registry/**
  - .agents/skills/wrap-up-session/references/routines.md
  - .claude/skills/wrap-up-session/references/routines.md
  - .agents/skills/wrap-up-session/references/routine-prompts/fix.md
  - .claude/skills/wrap-up-session/references/routine-prompts/fix.md
  - docs/task-tracking.md
  - specs/sweep-routines.md
  - specs/category-routines.md
  - specs/workflow-routing.md
  - tests/test-sweep-routines.sh
  - tests/test-sweep-handoff.sh
  - tests/test-routines-contract.sh
  - tests/test-routine-selectors.sh
  - tests/test-routine-skills.sh
  - tests/test-task-registry.sh
  - tests/test-task-escalation.sh
  - tests/test-routine-escalation-handoff.sh
  - tests/test-routine-reproduction-e2e.sh
  - tests/fixtures/task-registry/**
---

# Spec: Escalate blocked routine investigations

> Origin: [#126](https://github.com/Joaovsales/jplugin-agentic-development/issues/126) and user review · Revised 2026-09-11 · Review status: **awaiting human review — critic ACCEPT after 2 revision-review safeguards (D10/D11), 0 declined; no implementation applied**
> Visual: specs/routine-reproduction-report.plan.html

## Problem

An unattended fix routine needs different outcomes for a reproduced defect, an inconclusive reproduction, and an investigation blocked by an unavailable test or environment. Reproduced defects follow the normal fix pipeline; unresolved investigations receive an explicit escalation on the originating task that prevents automatic reselection. A proven, independently actionable blocker can receive its own linked task, while the original issue stays open for human investigation.

User-review interpretation: “when it can be reproduced” is answered by the normal path below; the requested escalation applies when the investigation cannot proceed, including after a successful reproduction if verification cannot run.

## Constraints

| Constraint | Value | Source | Detected by |
|---|---|---|---|
| Positive path | A reproduced defect continues through root-cause analysis, failing regression test, implementation, verification and fix PR when those steps can run | existing routine contract; user question | Positive-path scenario |
| Escalation | Unresolved investigation is visibly flagged on its originating task, with timestamp, command, observation, evidence and disposition | issue; user | Label readback and exact comment assertions |
| Reselection | Every consumer routine excludes an escalated issue even when its claim label is absent | user | select, claim and workflow tests across all configured routines |
| Terminal safety | Escalation exits non-zero, creates no fix PR, and never closes the originating issue | issue; user | Failure-path scenario and provider call trace |
| Blocker filing | Only concrete, actionable blockers become separate tasks; the parent references their actual publication outcome | user; inferred D3 | Filing threshold, linkage, pending/failure and duplicate tests |
| Human resumption | No timeout, blocker closure, routine or producer removes the escalation flag; a human explicitly re-triages and removes the hold | inferred D1 | Resumption and producer-preservation regressions |
| Write authority | All external mutations pass existing WriteGate; dry-run writes nothing and never silently opts into approval | existing user workflow | Denied-policy and dry-run tests |
| Persistence | Label is the exclusion source of truth; comment is history; blocker task owns the actionable work | inferred D2 | Partial-write outcomes and unchanged unrelated fields |
| Bounded attempts | One attempt per write stage; no blind retry after an ambiguous comment or task creation | inferred D4 | Failure-injection call counts |
| Evidence | Retained run artifact or explicit evidence-unavailable reason; no invented accessible transcript URL | prior review; inferred D5 | Artifact-unavailable scenario |
| Compatibility | Existing CLI commands keep their contracts; new config defaults require an explicit rollout preflight | inferred D6 | Legacy CLI tests and label-provisioning checks |

No design can guarantee a remote comment or label during a tracker outage. The existing claim is retained as a second exclusion; the result must state whether an authoritative hold is confirmed. An invocation with neither a confirmed claim nor escalation label reports that automatic exclusion is unconfirmed and requires operator intervention; it never claims the issue is safely queued for human review.

## System design

### Current state and ownership

Read paths below are under `.agents/skills/` unless stated otherwise.

```text
fix prompt (wrap-up-session/references/routine-prompts/fix.md:12-17)
  -- sync --> /debug (debug/SKILL.md:59,108,154,303)
  -- reproduced --> /build --> verification --> /wrap-up-session --> PR
  -- inconclusive --> blocked output, non-zero, no PR; claim retained

registry/routines.py:49-64 excludes claim label only at label-selection seam
task-registry.py:456 returns early when an issue is already claimed
task-registry.py:581-614 reports claimed work as IN FLIGHT
providers/base.py:188 exposes comment; no label-only mutation operation
providers/github.py:191-210 update_task also rewrites the issue body
registry/upsert.py:183 exposes idempotent task filing with local-pending fallback
```

Registry file names above are relative to `task-registry/scripts/`. The original issue was read through `show` and its web page because the normalized CLI output omitted the free-form Required fix section.

| Component | Owns | Reads |
|---|---|---|
| /debug and fix routine | Reproduction verdict, blocker diagnosis, evidence and terminal decision | Original issue, command results |
| NEW escalation operation | Validation; hold → optional blocker → comment ordering; truthful stage results | Fresh parent task, write policy, structured request |
| Routine selection/config | Configured escalation label and exclusion on every entry path | Provider labels |
| Provider adapters | Label-only mutation, comments, identity and durable acknowledgements | Exact task reference, payload |
| Existing upsert engine | Stable-ID blocker filing and publication outcome | Proven blocker fields, existing task/index |
| Originating task | Escalation label and investigation history | Related blocker references |
| Blocker task | Work needed to remove the practical obstacle | Parent reference, evidence, acceptance criterion |

### Behavior and interaction

| Observation | Routine action | Separate blocker task |
|---|---|---|
| Defect reproduced; investigation and verification available | Continue normal fix pipeline; PR only after verification passes | No escalation task just because the defect exists |
| Reproduction runs but does not establish the symptom or named acceptance | Escalate as inconclusive; hold parent; stop | Only if a specific inadequacy is demonstrated and has a concrete remedy |
| Reproduction cannot run because test/environment is broken | Escalate as execution-blocked; retain reproduction verdict as unverified | Yes when a repairable prerequisite is identified |
| Defect reproduced, but a necessary later test cannot run | Escalate as verification-blocked; preserve “reproduced” evidence | Yes when the verification obstacle is independently actionable |
| Credentials, access, missing context, or transient timeout with no established remedy | Escalate for human investigation; stop | No speculative engineering ticket |

```text
/debug
  (1) sync: retain evidence and classify outcome
  (2) sync: NEW task-registry escalate <parent> <request>
       (3) sync: authoritative parent read and write-policy validation
       (4) sync: add escalation label, read it back; retain existing claim
       (5) sync: optional proven blocker upsert; capture structured outcome
       (6) sync: post parent comment including hold and blocker outcome
  (7) sync: persist stage results in run artifact; terminate non-zero
```

| Arrow | Timeout/failure behavior | Duplicate behavior |
|---|---|---|
| 1 | Use a verifiable retained harness artifact, or explicit evidence-unavailable reason | Keep this run's artifact |
| 2–3 | No remote mutation on usage, identity or policy failure; caller still stops | Read-only |
| 4 | Attempt bounded readback after ambiguous label acknowledgement; do not file blocker without confirmed hold; still attempt an honest parent comment if authorized | Additive set operation; same label is a no-op |
| 5 | Failure/pending publication is included in the parent comment; never discard the parent escalation | Stable blocker ID; no blind retry after unknown external creation |
| 6 | Comment failure is delivery-unknown after dispatch; hold and blocker are retained | Append-only, non-idempotent; one attempt |
| 7 | No build/wrap-up/PR after escalation, even if earlier stages crash | No task-state release |

GitHub calls have a 60-second per-subprocess limit (`providers/github.py:457-473`); this is not a total-duration promise. The sequential writes are not atomic. Safety is monotonic: the hold lands first and is never compensated away because a later step failed. Each stage reports its own result; “held” does not mean “comment delivered” or “blocker published.”

### Failure unit and callers

Only this investigation stops. Other unrelated candidates remain available. The short fix prompt and all four /debug stop sites route to one canonical escalation procedure. Its no-PR terminal path explicitly overrides the generic mandatory wrap-up and PR-ledger rules (`wrap-up-session/references/routines.md:176-210,231-238`); downstream skips remain in the local ledger. The short prompt stays under 25 lines.

When the defect has already been reproduced, later verification failures use the same escalation procedure only when a practical obstacle prevents further safe progress. A regression failure showing the implementation is wrong remains part of the normal debugging loop; it is not relabeled as an environment blocker to evade verification.

Later failure owners are explicit: `build/SKILL.md:241,264-294` receives blocked verification, `verify/SKILL.md:194-197,243-251` reports it to the caller, and `/wrap-up-session` receives pre-PR verification results. On a fix-routine branch these callers invoke the canonical escalation procedure with the originating issue, last confirmed reproduction verdict and actual failing verification command. Add scoped handoffs to their mirrored SKILL.md files. `/verify` returns evidence and a blocked outcome; its caller files exactly once, avoiding double escalation. Ordinary interactive sessions and post-push deployment monitoring retain their existing contracts.

## Component contracts

### NEW CLI and request

```text
python3 .agents/skills/task-registry/scripts/task-registry.py escalate <parent-ref>
  --reason <inconclusive|execution-blocked|verification-blocked>
  --reproduction-state <reproduced|not-reproduced|unverified>
  --run-at <timezone-aware ISO-8601 timestamp>
  --repro-command <exact attempted command>
  --observed <actual result and remaining verification gap>
  (--evidence <reference> [--evidence <reference>] | --evidence-unavailable <reason>)
  [--blocker-file <JSON request path>]
  [--apply] [--approve] [--dry-run] [--repo <root>]
```

The earlier draft's `reproduction-failed` name was never shipped; `escalate` reflects the broader user-requested outcome. `--repro-command` avoids collision with the existing positional command. The reporter never executes it. Required fields are nonblank; timestamp normalizes to UTC seconds with Z; exactly one evidence alternative is mandatory. Execution-blocked requires unverified reproduction; verification-blocked requires reproduced; inconclusive accepts not-reproduced or unverified. “Reproduced and verified” is not an escalation request.

Reject the shared `--report` option before dispatch for this command only. Its common epilogue writes outside the operation (`task-registry.py:102,252-253,689`). Default/explicit dry-run previews hold, optional blocker and comment, performs zero writes and exits 0. Applied escalation always exits 1, even when every stage succeeds; usage errors exit 2. The caller always terminates non-zero and opens no PR, independently of the CLI's result.

All untrusted report strings are inside a fenced JSON object encoded with `json.dumps(..., ensure_ascii=True, indent=2)`, replacing literal less-than characters with JSON escape `\u003c`. Static prose states escalation, no verified fix, and human resumption requirements. This prevents multiline input from becoming fields in the local reader (`providers/local.py:108,159-161`) while JSON decoding recovers exact command text. No secrets or evidence files are uploaded automatically; necessary redaction is disclosed.

```python
def escalate_task(registry: Registry, request: EscalationRequest, apply: bool) -> Tuple[str, int]: ...
```

NEW `registry/escalation.py` owns this operation and its validated frozen request. Resolve exact provider reference, or stable index ID with recorded reference; require provider/repository agreement and a fresh owning-provider read. Exact-ID listing fallback is allowed only with complete successful results, followed by a direct read. Missing, ambiguous, truncated, mismatched or degraded reads refuse writes. Do not use the read-oriented local fallback in `Registry.resolve_task` as proof of a successful external read.

An already-closed parent is not reopened: refuse the escalation and file no blocker. A concurrent human closure is never overwritten. Comments describe the observed open state, not a promise about a later snapshot.

### NEW label-only provider seam

```python
def add_labels(self, task: Task, labels: Sequence[str]) -> None: ...
```

GitHub adds only named labels to the exact issue through argv; it sends no body/title/state replacement. Local updates only the canonical header labels field and preserves unrelated bytes. It does not reuse GitHub `update_task`, which rewrites the issue body. Both retain existing labels, validate requested labels, honor WriteGate, and treat repeated additions as idempotent. Missing label/capability is a loud failure, never the existing best-effort “written without it” behavior. Success requires a fresh readback showing the escalation label; a label write returning None is not sufficient proof.

No remove-label operation is introduced. The operator can re-triage in the tracker and remove both escalation and stale claim labels after recording a corrected reproduction, new evidence or repaired prerequisite. This is a human action, not something child closure or a routine performs.

### Selection and configuration

NEW `[routines] escalation_label = needs-investigation`, with that shipped default. It is nonblank and distinct from the claim label, all routine selector/kind-precedence labels and configured status/priority/kind mapping labels; comparison follows the provider's case-insensitive label semantics where applicable. Validate in the loader, not only in doctor.

`select_routine` excludes escalation before ordinary kind matching. `select_candidates` inherits that exclusion. `claim` checks escalation before its already-claimed success return and refuses even when invoked explicitly. `workflow` checks escalation before kind matching or deferred-routine reporting: even an unclassified, already-claimed or deferred-build task reports ESCALATED / human investigation required and returns 1, without a runnable chain. All routine hosts use these seams, including future build. Existing claim bypasses of unrelated linked-PR/truncation checks are outside this change; the new escalation check uses a fresh exact-target read rather than the stale selection snapshot.

Producers keep escalated tasks in their deduplication set but neither update/reopen them nor create eligible replacement tasks for the same finding. They record the existing held reference in their sweep record and leave human-owned investigation intact. Upsert also preserves existing labels defensively so a separately authorized direct update cannot accidentally erase the hold; the producer guard is explicit in `sweep/SKILL.md`, whose current dedup/read and filing sites are at lines 60-66,111-119,179-180.

On providers with a label vocabulary, selector preflight requires the configured escalation label to exist and be readable; otherwise no consumer starts. Local labels have no external provisioning step. NEW label creation is an explicit rollout action; ordinary sync does not create it. A read-only provider vocabulary check in this planning revision confirmed that `needs-investigation` does not yet exist in this repository; D6 is a real rollout prerequisite. Runtime escalation still attempts the explanatory comment if label application fails, accurately stating whether the old claim supplies a confirmed fallback hold.

### Conditional blocker creation

The operation accepts at most one independently actionable blocker per escalation; additional unproven symptoms remain observations. The optional file is a JSON object with `version: 1`, `source` (repository-relative path), `title`, `summary`, `handling` (routine or human), `reproduction` (nonempty list of single-line steps), `proposed_fix` (nonempty list), and `criteria` (nonempty list). This is a new input envelope, not a persisted Task schema.

Blocker schema v1 deliberately accepts plain single-line descriptive fields. Every string (including title and summary) must be nonblank, have no line-boundary character recognized by Python str.splitlines (including Unicode separators), contain neither task-registry metadata sentinel, and not begin with a Markdown heading or a field-shaped line matching `^(?:-\s*)?(?:status|priority|labels|area|updated|created)\s*:`. Validate case-insensitively after trimming. This catches the valid single-line proposed-fix value `status: done`, which the writer would otherwise turn into a real `- status: done` field. Reject those shapes instead of silently rewriting them; raw command/output remains in the parent's safe JSON report and retained artifact. Version, field-name, source containment and enum validation are also mandatory. Safe representable prose can describe the remedy while pointing to the exact command in the artifact. This bounded v1 format avoids changing the entire existing Markdown parser (D10).

Validate the optional blocker independently of the parent request. An unreadable file or invalid blocker produces blocker-failed with the exact field/reason, zero blocker writes, and still proceeds with the valid parent's hold and comment. Only invalid required parent fields prevent the entire request from dispatching. Read/render/read tests must demonstrate that all accepted blocker fields preserve task identity, labels, status and criteria on local and local-pending paths, and the hazardous shapes above are refused before blocker persistence.

Filing requires an observed concrete obstacle, evidence from this run, a separate remediation and a measurable unblock criterion. Example: test launch fails because the committed runner references a missing fixture; unblock criterion is that the named test starts and reaches its assertions. “Tests cannot run” alone, a single unexplained timeout or lack of credentials is not enough. The agent owns this evidence judgment; field validation alone cannot establish that a blocker is real.

Derive identity through existing `derive_id("routine-blocker", source, title)`, omitting run timestamp and parent number so one shared blocker is not cloned for every parent. Reuse an existing matching task/reference when known, freeze the source/title identity after first filing, and preserve all unrelated labels including escalation and claims. If that known blocker is already escalated or terminal, reuse its reference without updating, reopening or cloning it; the parent comment requests human review of its recurrence. A new routine-handled blocker must be a proven defect: use kind bug with its configured kind-label mapping and validate that it has a runnable consumer. A new human-handled prerequisite uses kind operational plus the escalation label. An existing blocker keeps its established kind/routing labels; this report never reclassifies it to make it eligible.

Automatic blocker reopening is explicitly outside this change (D11). Existing upsert's `_merge` reports reopened at `registry/upsert.py:127`, but GitHub `update_task` sends only issue edit at `providers/github.py:201`, so that legacy report is not authoritative state. The escalation-specific upsert result path refuses terminal/held updates at its own fresh existing-task lookup immediately before persistence, returning the existing reference with a human-review outcome; the legacy wrapper retains its existing behavior for other callers. Read back any blocker that was written before describing it as open or independently selectable. If it is now closed/held, report human review required; do not reopen, create another task or retry. This is a read-snapshot guarantee, not cancellation of a concurrent human edit.

Include a canonical originating-parent reference in accumulated blocker evidence and its summary. The parent comment includes the actual blocker ref, or the stable local task ID with “publication pending,” or the filing failure/unknown outcome. No native dependency is claimed: `upsert` has no dependency flag. Resolving the blocker does not clear the parent hold.

Reuse the existing upsert implementation and its write policy rather than create a second filing engine. Its current return is human-oriented lines plus exit code (`registry/upsert.py:183`), so expose a structured internal outcome and retain the existing public wrapper and CLI formatting:

```python
def upsert_task_result(registry: Registry, task: Task, apply: bool) -> UpsertResult: ...
def upsert_task(registry, task: Task, apply: bool) -> Tuple[List[str], int]: ...
```

NEW UpsertResult carries disposition (preview, external, local, local-pending, existing-held, existing-terminal, failed, unknown), the persisted or reused Task/reference when confirmed, authoritative readback state, stage detail and legacy lines/code. The structured helper defaults to preserving held/terminal tasks; its compatible legacy wrapper opts into the old merge behavior through an internal policy argument, not a new CLI flag. A provider creation exception is conservatively unknown; an external success followed by index failure retains the confirmed external ref and separately reports index failure. The escalation caller never parses prose or treats a preserved historical external ref in a local-pending result as proof this run published.

Blocker failure never prevents the parent comment attempt. Comment fields include exact stage outcomes. No recursive blocker filing and no automatic replay after an ambiguous create.

## Data models

| Entity | Invariant | Enforcement |
|---|---|---|
| Parent escalation | Existing label is authoritative; issue remains open; prior claim retained | Dedicated additive label operation and selection exclusion |
| EscalationRequest | Valid reason/reproduction pair, UTC time, command/observation and evidence alternative | Frozen validated request; no caller-supplied fixed disposition |
| Blocker request | Optional, versioned v1; one concrete remediation with criterion and safe source | Schema checks plus evidence threshold in /debug |
| Blocker Task | Stable identity; original parent in accumulated evidence; existing labels retained | Existing registry ID derivation and upsert merge |
| Hold outcome | confirmed / claim-only / unconfirmed | Fresh authoritative read, never inferred from a requested write |
| Comment delivery | not-sent / recorded / unknown | Provider acknowledgement vs dispatch failure |
| Blocker publication | none / preview / external / local / local-pending / existing-held / existing-terminal / failed / unknown | Structured upsert result, not exit-code or link guessing |
| Run artifact | Timestamp, host/run identity, evidence, intended and actual stage outcomes | NEW exclusive per-run document under tasks/routine-runs/ |

### Transitions and illegal states

| State | From → To | Trigger |
|---|---|---|
| Investigation | investigating → fixing | Defect reproduced; progress remains possible |
| Investigation | investigating/fixing → escalated | Inconclusive or practical execution/verification obstacle |
| Investigation | fixing → verified → fix PR | Regression plus required verification pass |
| Escalation label | absent → present | Authorized label add confirmed by readback |
| Escalation label | present → present | Repeat escalation, blocker closure, producer rediscovery |
| Escalation label | present → absent | Explicit human re-triage only |
| Claim | present → present | Escalation, including partial failure |
| Claim | present → absent | Human releases stale claim before deliberate resumption |
| Hold result | pending → confirmed / claim-only / unconfirmed | Label attempt and readback |
| Comment result | pending → not-sent / recorded / unknown | Preflight failure, acknowledgement or post-dispatch exception |
| Blocker result | pending → external / local / local-pending / existing-held / existing-terminal / failed / unknown | Upsert stages |
| Applied escalation | any stage outcome → terminated non-zero | No automatic continuation or replay |
| Parent status | open → open | Escalation never closes/reopens it |
| Blocker status | absent → open; open/in_progress/blocked → same; done/cancelled → same | Create/update eligible task or reuse held/terminal reference without mutation |

Illegal combinations: “escalated but selectable” is prevented at selection and explicit claim/workflow seams; “comment failed therefore hold released” has no removal operation; “test did not run therefore defect fixed” has no success escalation disposition. A held parent is not made selectable by a repaired or closed blocker. Reporting strings cannot set parsed local fields because they are losslessly encoded. Blocker publication cannot be called confirmed merely because an old external link survived a local-pending write.

A read/write race with another run is not a new global lock guarantee: a worker that selected earlier must recheck at claim, and a routine entering debug rechecks the hold before work. A human bypass or an already-running worker is not cancelled by a label; the guarantee covers subsequent routine selection/entry.

### Artifacts, migration and rollback

The routine retains `tasks/routine-runs/<UTC timestamp>-<unique run id>.md` or an already verifiable harness artifact. If neither survives, use evidence-unavailable with the actual reason and attempt the parent notification anyway. No PR publishes this file automatically.

No new Task status enum or database is introduced. Labels are persisted policy state; comments are historical records; the optional JSON file is a v1 request. Deploy exclusion/read support before enabling escalation writers. Provision the configured label before enabling the new consumer preflight, with explicit operator authorization under normal label policy; verify it exists. Mirror every skill change.

Rollback disables escalation writers but retains exclusion support and the persisted labels until humans clear the holds. Rolling readers back to code that ignores escalation is unsafe unless every held parent still has the old claim exclusion; verify that before rollback. Do not automatically delete comments, blockers or run artifacts.

## Build order

| # | Slice | Delivers | Depends on | Contract | Size |
|---|---|---|---|---|---|
| 1 | Persist and enforce investigation holds | Config/default validation, label-only adapter operation, readback, select/claim/workflow exclusion, rollout guidance | none | add_labels and escalation_label | M |
| 2 | Expose honest blocker filing outcomes | Structured upsert result behind unchanged public wrapper; label preservation and partial-index-failure detail | 1 | UpsertResult | M |
| 3 | Record escalation with optional blocker | Validated escalate CLI, safe payload, ordered writes and all failure branches | 1, 2 | escalate CLI + request v1 | M |
| 4 | Wire and verify both routine outcomes | Canonical stop procedure, positive path, later verification blocker, short prompt, ledger exceptions and real isolated scenarios | 3 | Routine behavior | M |

Each slice leaves existing tests green and mirrors its skill files. Slice 1 covers the largest safety unknown first: a visible hold must actually exclude a task without rewriting its issue body.

- Slice 1: AC3, AC4, AC8, AC11 and AC13; explicit claim, missing label, label-only mutation and human resumption tests.
- Slice 2: AC6, AC7 and AC12; preserve existing CLI outputs/exit codes, unknown creation and confirmed external write followed by index failure.
- Slice 3: AC2, AC5–AC10 and AC12; public CLI against local and fake-GitHub adapters, no writes in dry-run, no reporter-output overwrite, safe multiline payload.
- Slice 4: AC1, AC2, AC9 and AC14; actual isolated skill execution plus static coverage of every stop/entry caller. A shell script imitating the desired behavior is not evidence that the agent skill follows it.

## Decisions

| ID | Status and choice | Recommended behavior | Trade-off / when wrong |
|---|---|---|---|
| D1 | User-directed: explicit escalation and exclusion; inferred resumption policy | needs-investigation plus retained claim; human clears both after re-triage | Automatic resumption would need a separate proof and scheduling contract |
| D2 | Inferred: partial-write ordering | Confirm hold → attempt blocker → post parent comment; never compensate hold away | Requires per-stage results because these stores cannot form one transaction |
| D3 | User-directed: practical blocker tasks; inferred filing threshold | File only concrete remediable obstacles; one blocker per attempt; stable shared identity | A reproducible symptom without independent remedy belongs in the parent investigation |
| D4 | Retained: bounded retry policy | No blind comment/create retry; additive label operation may be reconciled by one readback | Guaranteed delivery during outages needs a separate queue/reconciliation system |
| D5 | Retained: evidence access | Retained artifact or explicit unavailable reason | Operator must supply a shared URL when host artifacts cannot be retrieved |
| D6 | NEW rollout decision | Provision configured label before activating consumer preflight; deploy exclusions first | Requires coordinated rollout; ordinary sync must not silently create labels |
| D7 | Prior critic safeguards retained | Safe JSON report; reject --report for escalate before dispatch | Directly copyable raw multiline commands need a real local-parser boundary first |
| D8 | Retained: applied escalation exit | Always non-zero; stage fields distinguish successful notification from failure | Integrations wanting notification-only exit 0 must adapt to stage results |
| D9 | NEW blocker routing decision | Independently repairable blocker receives normal routing; human-only blocker is held; original parent stays held | Avoids recursive attempts at inaccessible credentials or human-only work |
| D10 | Revision critic: blocker serialization (MUST-FIX, confidence 100, manual) | Plain single-line v1 blocker fields; reject metadata/heading/field-shaped input, preserve exact raw evidence in safe parent report | Rich arbitrary Markdown blocker content needs a separately designed parser/encoding change |
| D11 | Revision critic: closed blocker recurrence (MUST-FIX, confidence 100, manual) | Reuse closed/held reference and request human review; do not auto-reopen or duplicate | Automatic recurrence handling needs a real gated reopen operation and state readback |

Self-review: constraints have sources and checks; every cross-boundary stage has failure and duplicate semantics; all new status values have transitions. The review card's atomic-dual-write ideal is not met literally: D2 explicitly uses a monotonic hold with visible partial results and no rollback, because issue labels, comments and blocker creation have no shared transaction. Money/tenant models are n/a; provider/repository identity is checked. Human review approves these choices; no issue has been filed and no implementation has begun.

Prior critic history: the first report-only draft exposed unsafe local Markdown interpretation and shared --report file writes. Both proposed safeguards remain. Revision review identified two further MUST-FIX / confidence 100 / manual / agent findings, addressed as proposals in D10/D11: blocker fields bypassing parent-comment encoding (`providers/local.py:147,161`) and the unimplemented GitHub reopening operation (`registry/upsert.py:127,149`, `providers/github.py:201`). Two incorporated, zero declined; no implementation applied. The focused follow-up accepted the revised design with no remaining findings in that scope; this is design acceptance, not implementation verification.

Planning validation: all nine sections, contract signatures, fourteen acceptance criteria and eleven decision rows are present in the HTML; relative links and self-contained assets pass checks. In-memory probes against the existing local parser preserve exact parent-report inputs and Task fields, reject eight hazardous blocker strings, and round-trip three accepted blocker records without changing task identity/status/labels/criteria. These validate the proposed formats only; actual routine behavior and all implementation ACs remain to be built and verified.

## Acceptance Criteria

- AC1: A reproduced defect with usable investigation and verification proceeds through the normal fix pipeline; no escalation or blocker is created merely because the bug reproduces.
- AC2: An inconclusive reproduction or practical execution/verification blocker escalates the original issue with timestamp, command, observed result, evidence or explicit unavailable reason, and an accurate reproduced/not-reproduced/unverified verdict.
- AC3: The escalation label excludes the parent from every consumer routine even without the claim label; explicit claim refuses it and workflow reports human escalation rather than a runnable chain.
- AC4: Escalation retains the original claim and issue state; only its designated label and comment are added, with no issue-body/title/criteria replacement or loss of unrelated labels.
- AC5: Hold application is read back before optional blocker filing; failures retain existing holds, still attempt authorized parent notification, and report confirmed, claim-only or unconfirmed exclusion honestly.
- AC6: A proven independently actionable obstacle creates or updates one stable eligible blocker with evidence, reproduction, remedy, unblock criteria and parent reference; existing closed/held blockers are referenced for human review without mutation or duplication; speculative failures create none.
- AC7: The parent comment names the blocker's confirmed reference, local-pending identity, failed or unknown outcome; upsert preserves claim/escalation labels and does not duplicate a known blocker on ordinary replay.
- AC8: Neither blocker closure nor producer rediscovery clears a parent escalation; only explicit human re-triage and removal of escalation/stale claim permit later routine selection.
- AC9: Every escalation terminates non-zero and creates no fix PR, including unavailable CLI, denied writes, provider failure, missing artifact and later verification blockers.
- AC10: Dry-run makes zero writes; escalation rejects --report before dispatch; parent report input is safely encoded, unsafe blocker fields are refused before blocker persistence without preventing valid parent escalation, and accepted content round-trips without changing parsed identity/status/labels/criteria.
- AC11: Missing or conflicting escalation-label configuration prevents consumer startup with actionable diagnostics; label creation is an explicit rollout operation and no unknown label is silently dropped.
- AC12: Comment/creation exceptions are reported as unknown after dispatch without automatic retry; a successful external blocker write followed by index failure preserves the known reference and reports the separate failure.
- AC13: Rollout installs exclusions before writers and rollback retains holds/read support; legacy commands retain their contracts and canonical/Claude copies remain identical.
- AC14: Retained isolated skill runs cover reproduced-and-fixable, inconclusive, test-cannot-start and reproduced-but-verification-blocked cases, proving subsequent selection skips escalated parents and independent actionable blockers remain eligible.

## Implementation Paths

- NEW `.agents/skills/task-registry/scripts/registry/escalation.py` — validated request, hold/blocker/comment coordination, stage output; mirror under `.claude/skills/`.
- `.agents/skills/task-registry/scripts/task-registry.py` — escalate flags/dispatch, explicit claim/workflow handling and preflight diagnostics.
- `.agents/skills/task-registry/scripts/registry/config.py`, `routines.py` — configured escalation exclusion and loader validation.
- `.agents/skills/task-registry/scripts/registry/providers/base.py`, `github.py`, `local.py` — narrow additive label seam, with local-only header update and no GitHub body replacement.
- `.agents/skills/task-registry/scripts/registry/upsert.py` — structured result behind compatible wrapper, preserve labels and report partial publication accurately.
- `.agents/skills/task-registry/SKILL.md`, `references/configuration.md`, `templates/task-tracking.md`, `docs/task-tracking.md` — escalation/hold/blocker policy and staged label provisioning.
- `.agents/skills/debug/SKILL.md`, `.agents/skills/wrap-up-session/references/routines.md`, `routine-prompts/fix.md` — canonical escalation, positive continuation and all entry/stop paths; mirror every skill edit.
- `.agents/skills/build/SKILL.md`, `.agents/skills/verify/SKILL.md`, `.agents/skills/wrap-up-session/SKILL.md` and mirrors — pass practical pre-PR verification blockers to the single canonical escalation owner on fix-routine branches.
- `.agents/skills/sweep/SKILL.md` and its mirror — retain held tasks in deduplication, skip their mutation and forbid eligible replacement clones; no expansion of producer coverage-gap filing policy.
- `specs/sweep-routines.md`, `specs/category-routines.md`, `specs/workflow-routing.md` — reconcile existing exclusion, consumer and workflow contracts during implementation.
- `tests/test-task-registry.sh`, `tests/test-routine-selectors.sh`, `tests/test-routine-skills.sh`, `tests/test-routines-contract.sh`, `tests/test-sweep-handoff.sh`, `tests/test-sweep-routines.sh`, `tests/fixtures/task-registry/` — behavior and failure regressions.
- NEW `tasks/routine-runs/`, existing `tasks/e2e-log.md` — retained implementation-time evidence; no records from a pretend routine execution during planning.
