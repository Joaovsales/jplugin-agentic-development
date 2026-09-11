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
     criteria — a checkbox records an intention, a spec records a fact. -->

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

<!-- Every arrow is sync or async, and every arrow states what happens on
     timeout. Existing paths are drawn with their real file:line; paths this
     change adds are marked NEW. -->

```text
 caller                      ComponentA                  ComponentB
   │  (1) sync request  ───►  │                            │
   │                          │  (2) async event  ──────►  │  NEW
   │  ◄──── (3) outcome ───   │                            │
   │                          │  ◄── (4) ack / retry ────  │
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

## Build order

<!-- Slices are ordered so contracts and data models land before their
     consumers, every slice leaves the suite green, and the largest unknown is
     first. A slice that depends on a later slice is a defect in the order. -->

| # | Slice | Delivers | Depends on | Contract exposed | Size |
|---|-------|----------|------------|------------------|------|
| 1 | <spike or riskiest slice> | <what is known at the end> | — | <none / a stub> | S |
| 2 | <data model + migration> | <entities and transitions above> | 1 | <repository interface> | M |
| 3 | <contract + component> | <ComponentA.operation> | 2 | <signature above> | M |
| 4 | <consumer wiring> | <caller uses the outcome type> | 3 | — | S |

### Slice criteria

<!-- Criteria a test can pin. No "works correctly", no "handles errors". -->

- Slice 1: <criterion>
- Slice 2: <criterion>; <criterion>
- Slice 3: <criterion>; <criterion>
- Slice 4: <criterion>

## Decisions

<!-- Hard-to-reverse choices only. The recommended option and what makes each
     option wrong. Open questions to the reviewer live here too, tagged open. -->

| Decision | Options | Recommended | Wrong when |
|----------|---------|-------------|------------|
| <wire format for the event> | <A / B> | <A> | <B is right if consumers are outside this repo> |

## Acceptance Criteria

- <verifiable criterion, present tense>
- <verifiable criterion, present tense>

## Implementation Paths

- `<src/module/**>` — <what this code does for the feature>
- `<tests/test_module.py>` — <what it verifies>
