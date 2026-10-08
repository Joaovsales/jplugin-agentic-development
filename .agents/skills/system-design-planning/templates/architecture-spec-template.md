---
implementation_paths:
  - <src/module/**>
  - <tests/test_module.py>
---

# Spec: <Feature Name>

> Origin: <#N | task-id | "prompt"> · Designed <YYYY-MM-DD> · Review status: **draft**
> Visual: specs/<feature>.plan.html

<!-- Guidance comments like this one are removed before the spec is saved.
     Every section is written in the present tense: what the system does once
     the change is in, not what it will do. Ordinary bullets for acceptance
     criteria — a checkbox records an intention, a spec records a fact.
     Write connected sentences, not slash-packed shorthand; cut repetition,
     empty qualifiers and narration of how the session went. -->

## Summary

<!-- Two to four sentences: what changes, for whom, and the one decision the
     reviewer must not miss. The visual plan opens with this as its lead. -->

## Problem

<!-- At most three sentences: who is affected, what changes for them, what is
     out of scope. -->

## Constraints

<!-- Constraints come first because every later section is checked against
     them. One row each. `source` is issue / user / inferred; an inferred row
     is a question for the reviewer, not a fact. `detected by` names the test,
     metric or CI check that would catch a violation. -->

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| <latency at the boundary> | <p99 ≤ N ms> | issue | <perf test name> |
| <consistency for consumer X> | <read-your-writes / eventual ≤ N s> | inferred | <integration test> |
| <compatibility> | <v1 consumers keep working through the release> | user | <contract test against recorded v1 payloads> |
| <rollout / rollback> | <flag-gated; rollback = flag off, no data migration required> | inferred | <deploy runbook step> |

## System design

### Ownership

<!-- Each fact has exactly one source of truth. A component that caches a fact
     is listed as a reader, not an owner. -->

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| <ComponentA> | <fact 1, fact 2> | <fact 3> |
| <ComponentB> | <fact 3> | <fact 1> |

### Interaction

<!-- At least one flow diagram. Every arrow is sync or async, and every arrow
     states what happens on timeout. Existing paths are drawn with their real
     file:line; components this change adds are marked (new), changed ones
     (changed). -->

```flow
caption: <one sentence naming the path drawn>
caller -> ComponentA : (1) sync request
ComponentA --> ComponentB (new) : (2) async event
ComponentB --> ComponentA : (4) ack / retry
```

| Arrow | Mode | On timeout | On duplicate |
|-------|------|------------|--------------|
| (1) | sync | <caller receives Unknown outcome; retries with the same idempotency key> | <idempotent by key> |
| (2) | async | <outbox row remains pending; relay retries> | <consumer de-duplicates by event id> |

### Failure unit

<!-- What else stops when this stops. One sentence per component. -->

## Component contracts

<!-- One block per boundary. The signature is in the project's language.
     Expected failures are outcomes; unexpected ones raise. Every operation
     that can be retried names its idempotency key. -->

### <ComponentA>.<operation>

```python
def operation(request: Request, *, idempotency_key: str) -> Done | Rejected | Unknown: ...
```

| Aspect | Contract |
|--------|----------|
| Inputs | <Request fields and their invariants> |
| Outcomes | `Done(ref)` · `Rejected(reason)` · `Unknown()` — caller must handle all three |
| Raises | <only programmer errors and infrastructure faults> |
| Idempotency | <same key within N h returns the original outcome> |
| Versioning | <n/a — internal / envelope carries schema_version, v1 parser retained> |

<!-- A sequence diagram for each changed external contract or cross-component
     failure path. -->

```sequence
caption: <operation> when ComponentB times out
participant caller
caller -> ComponentA : operation(request, key)
alt ComponentB answers
ComponentA -> ComponentB : publish(event)
ComponentB -->> ComponentA : ack
ComponentA --> caller : Done(ref)
else ComponentB times out
ComponentA --> caller : Unknown()
end
```

## Data models

### Entities

<!-- One block per entity. Each invariant names the construct that enforces it. -->

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| <amount> | `Money(Decimal, Currency)` | <currency present, 2 dp> | <frozen dataclass, check constraint> |
| <status> | `Enum` | <one of the states below> | <enum column> |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| <status = paid with provider_ref = null> | <union type per status / check constraint> |

### Transitions — `<status field>`

<!-- Every status field has one of these. Include the in-doubt state when an
     external call can time out. -->

| From | To | Trigger |
|------|----|---------|
| `pending` | `done` | <outcome Done> |
| `pending` | `rejected` | <outcome Rejected> |
| `pending` | `unknown` | <outcome Unknown> |
| `unknown` | `done` / `rejected` | <reconciliation job> |

### Migration and compatibility

<!-- Forward migration, reverse migration, and what old rows mean to new code. -->

## Risks

<!-- One row per risk; likelihood and impact are H, M or L. A high-impact risk
     with no mitigation is a blocker on the visual plan. With nothing to list,
     replace the table with: None identified — <why>. -->

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|----|------|------------|--------|------------|-------|
| R1 | <the relay falls behind under peak load> | M | H | <alert on outbox age over N s> | <1> |

## Build order

<!-- Left empty here. /slice fills this section's table when it sizes this
     spec into session-sized slices — see .agents/skills/slice/SKILL.md. Its
     table has no separate "contract exposed" column; that fact is stated in
     each slice's Delivers text instead. -->

## Decisions

<!-- Hard-to-reverse choices only. The recommended option and what makes each
     option wrong. A choice the reviewer has not made yet is `open`; while any
     row is open, /slice prints no build prompt. -->

| ID | Decision | Options | Recommended | Wrong when | Status |
|----|----------|---------|-------------|------------|--------|
| D1 | <wire format for the event> | <A, B> | <A> | <B is right if consumers are outside this repo> | settled |

## Open questions

<!-- Facts someone outside the session must supply. `Blocks` names the slices
     (by number, once /slice has written § Build order) that cannot start
     without the answer, or none. -->

| ID | Question | Blocks | Needed from |
|----|----------|--------|-------------|
| Q1 | <which region hosts the queue?> | none | <platform team> |

## Acceptance Criteria

- AC1: <verifiable criterion, present tense>
- AC2: <verifiable criterion, present tense>

## Implementation Paths

- `<src/module/**>` — <what this code does for the feature>
- `<tests/test_module.py>` — <what it verifies>
