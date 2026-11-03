## Plan: retry-with-budget
> Spec: specs/retry-with-budget.md
- [ ] retry-with-budget <!-- task-id: plan.specs-retry-with-budget-md -->

### Slice 1/2 — Token bucket
- [ ] Token bucket — `TokenBucket` with refill, all-or-nothing takes and the capacity cap

### Slice 2/2 — Retrying call
- [ ] Retrying call — `call_with_retry`, `RetryPolicy` and `RetryError` using the bucket as the shared budget
