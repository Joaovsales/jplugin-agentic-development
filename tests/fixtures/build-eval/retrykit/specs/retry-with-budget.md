---
implementation_paths:
  - retrykit/bucket.py
  - retrykit/retrying.py
  - tests/test_bucket.py
  - tests/test_retrying.py
---

# Retry with a shared budget

## Behavior

Callers of flaky services need one call that retries a function with exponential
backoff, gives up within a deadline, and stops hammering a struggling service when
too many retries happen across the whole process. The retry budget is a token
bucket: it holds up to `capacity` tokens, refills at a steady rate, and every retry
(never the first attempt) spends one token.

Two new modules sit beside the existing `backoff.py` (the delay sequence) and
`clock.py` (`SystemClock`, `ManualClock`):

- `retrykit/bucket.py` — `TokenBucket`.
- `retrykit/retrying.py` — `call_with_retry`, `RetryPolicy`, `RetryError`.

Callers never see timestamps, elapsed-time arithmetic or the backoff generator.
Time comes only from a clock object (default `SystemClock`), so every behavior is
checkable with `ManualClock` and no real waiting.

## Inputs

- `TokenBucket(capacity, refill_per_second, clock=None)`: `capacity` is a positive
  int, `refill_per_second` a positive float, `clock` any object with `now()`.
- `TokenBucket.try_take(count=1)`: an int.
- `call_with_retry(fn, *, policy=RetryPolicy(), budget=None, clock=None)`: `fn` is a
  zero-argument callable; `budget` an optional shared `TokenBucket`; `clock` any
  object with `now()` and `sleep(seconds)`.
- `RetryPolicy(max_attempts=3, base=0.1, factor=2.0, cap=5.0, deadline=None,
  retry_on=(Exception,))`, a frozen dataclass. `deadline` is seconds since the first
  attempt began, or `None` for no deadline.

## Outputs

- `try_take` returns `True` when it took the tokens, `False` otherwise.
- `call_with_retry` returns whatever `fn` returned on the first successful attempt.
- When it gives up it raises `RetryError` with `.reason` (`"attempts"`,
  `"deadline"` or `"budget"`), `.attempts` (how many times `fn` ran) and
  `__cause__` set to the last exception `fn` raised.

## Edge Cases

- `try_take` with a `count` larger than the bucket's `capacity` returns `False` and
  takes nothing; it never raises.
- `try_take` with a `count` of zero or less returns `True` and takes nothing.
- A partial take never happens: when fewer than `count` tokens are available the
  bucket is left as it was.
- Refill never lifts the bucket above `capacity`, however long the clock jumps.
- `max_attempts` of zero or less behaves as one attempt.
- An exception that is not an instance of `retry_on` propagates unchanged after one
  call, with no sleep and no token spent.
- When the next sleep would end after the deadline, `call_with_retry` raises
  `RetryError` with reason `"deadline"` without sleeping.
- When the budget has no token for a retry, `call_with_retry` raises `RetryError`
  with reason `"budget"` without sleeping; the failed attempt's exception is the
  `__cause__`.

## Interfaces

### Token bucket

- **Path:** `retrykit/bucket.py`
- **Hides:** how elapsed time becomes tokens (the refill arithmetic, fractional
  tokens, the cap at capacity) and which clock is read.
- **Interface:** `TokenBucket(capacity: int, refill_per_second: float, clock=None)`
  with `try_take(count: int = 1) -> bool`.
- **Alternative considered:** `try_take(now)` with the caller passing a timestamp; it
  lost because every caller would then own a clock and repeat the same arithmetic.
- **Depth:** one call refills for the time that has passed, decides, and takes the
  tokens or nothing; no caller computes time or handles an error for a bad count.

### Retrying call

- **Path:** `retrykit/retrying.py`
- **Hides:** the backoff sequence, the sleeping, the deadline arithmetic, the budget
  check and the choice of which failure ends the loop.
- **Interface:** `call_with_retry(fn, *, policy=RetryPolicy(), budget=None, clock=None)`
  returning `fn`'s result or raising `RetryError`.
- **Alternative considered:** a `Retrier` class with `should_retry()` and
  `next_delay()` methods the caller loops over; it lost because every caller would
  rewrite the same loop and could get the order of checks wrong.
- **Depth:** one call runs the whole retry loop; the caller supplies a function and a
  policy and learns only the result or why it stopped.

## Decisions

| # | Question | Decision | Source | Why |
|---|----------|----------|--------|-----|
| 1 | Where does time come from? | an injected clock with `now()` and `sleep()`, default `SystemClock` | user | checkable without real waiting |
| 2 | What does a bad `count` do? | greater than capacity returns `False`; zero or less returns `True` and takes nothing | user | callers never handle an exception for it |
| 3 | Does the first attempt spend a token? | no, only retries do | user | a healthy service never touches the budget |
| 4 | How is exhaustion reported? | one `RetryError` carrying reason, attempts and the last exception as `__cause__` | user | one thing to catch |
| 5 | Is the budget required? | no, `budget=None` means unlimited retries | user | simple default |
| 6 | Where do sleeps come from? | `backoff.delays(policy.base, policy.factor, policy.cap)`, reused as is | user | existing code |
| 7 | Do existing modules change? | no; `backoff.py` and `clock.py` stay as they are | user | minimal change |

## Acceptance Criteria

- AC1: A new `TokenBucket(capacity=3, refill_per_second=1.0, clock=ManualClock())` accepts three `try_take()` calls and refuses the fourth, returning `False`.
- AC2: After the clock advances by `1 / refill_per_second` seconds a drained bucket accepts one more take; however far the clock jumps the bucket never holds more than `capacity` tokens.
- AC3: `try_take(count)` is all or nothing: with 2 tokens available `try_take(3)` returns `False` and a following `try_take(2)` still returns `True`; a `count` above `capacity` returns `False` and does not raise; a `count` of zero or less returns `True` and takes nothing.
- AC4: `call_with_retry(fn)` returns `fn()`'s value when the first attempt succeeds, calls `fn` once and never sleeps.
- AC5: With a failing `fn` and `ManualClock`, `call_with_retry` retries on exceptions matching `policy.retry_on` and sleeps the `backoff.delays` sequence between attempts (0.1 then 0.2 for the defaults), observable as the clock's reading afterwards.
- AC6: When `max_attempts` attempts all fail it raises `RetryError` with `reason == "attempts"`, `attempts == max_attempts` and `__cause__` the last exception; `max_attempts` of zero or less makes exactly one attempt.
- AC7: An exception outside `retry_on` propagates unchanged after one call, with no sleep and no token spent.
- AC8: With `policy.deadline` set, when the next sleep would end after the deadline (measured on the clock from the first attempt) it raises `RetryError` with `reason == "deadline"` without sleeping.
- AC9: With a `budget`, each retry takes one token and the first attempt takes none; when the budget has no token for a retry it raises `RetryError` with `reason == "budget"` without sleeping, and one budget shared by two calls is drawn down by both.

## Implementation Paths

- `retrykit/bucket.py` (new), `tests/test_bucket.py` (new)
- `retrykit/retrying.py` (new), `tests/test_retrying.py` (new)
- `retrykit/backoff.py` and `retrykit/clock.py` are used, not changed.

## Build Order

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Token bucket | `TokenBucket` with refill, all-or-nothing takes and the capacity cap | `retrykit/bucket.py`, `tests/test_bucket.py` | — | 1, 2, 3 | `python scripts/run_tests.py` | 2 files · 1 system · 3 AC |
| 2 | Retrying call | `call_with_retry`, `RetryPolicy` and `RetryError` using the bucket as the shared budget | `retrykit/retrying.py`, `tests/test_retrying.py` | 1 | 4, 5, 6, 7, 8, 9 | `python scripts/run_tests.py` | 2 files · 1 system · 6 AC |
