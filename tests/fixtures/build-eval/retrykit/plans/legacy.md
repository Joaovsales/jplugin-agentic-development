## Plan: retry-with-budget
> Spec: specs/retry-with-budget.md

### Slice 1/2 — Token bucket
- [ ] Token bucket <!-- task-id: plan.specs-retry-with-budget-md.token-bucket --> — Slice 1/2: `TokenBucket` with refill, all-or-nothing takes and the capacity cap
  [ ] TDD: tests/test_bucket.py § fill-and-refill — a bucket of 3 accepts three takes and refuses the fourth; after `1 / refill_per_second` seconds one take succeeds again and the bucket never exceeds capacity -> retrykit/bucket.py (AC 1, 2)
  [ ] TDD: tests/test_bucket.py § all-or-nothing — `try_take(3)` with 2 tokens returns False and leaves both; a count above capacity returns False without raising; a count of zero or less returns True and takes nothing -> retrykit/bucket.py (AC 3)

### Slice 2/2 — Retrying call
- [ ] Retrying call <!-- task-id: plan.specs-retry-with-budget-md.retrying-call --> — Slice 2/2: `call_with_retry`, `RetryPolicy` and `RetryError` using the bucket as the shared budget (blocked-by: plan.specs-retry-with-budget-md.token-bucket)
  [ ] TDD: tests/test_retrying.py § success-and-retries — a first-attempt success returns the value with one call and no sleep; failures retry and sleep 0.1 then 0.2 on a `ManualClock` -> retrykit/retrying.py (AC 4, 5)
  [ ] TDD: tests/test_retrying.py § giving-up — exhausted attempts raise `RetryError` reason "attempts" with the last exception as `__cause__`; zero `max_attempts` makes one attempt; an exception outside `retry_on` propagates unchanged -> retrykit/retrying.py (AC 6, 7)
  [ ] TDD: tests/test_retrying.py § deadline-and-budget — a sleep that would pass the deadline raises reason "deadline" without sleeping; an empty shared budget raises reason "budget" and the first attempt takes no token -> retrykit/retrying.py (AC 8, 9)
