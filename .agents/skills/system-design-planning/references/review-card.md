# Review card — the upstream architecture review

Run top to bottom in this order. The order is a dependency order: a constraint
changes which system design is right, the system design decides which
boundaries exist, the boundaries decide which contracts are needed, and the
contracts decide which data has to be shaped. A question answered "no" is a
defect in the spec until the spec changes or the answer lands in *Decisions*.

Finding format — the same one the human reviewer uses in Step 7:

```
[constraints|system-design|contracts|data-models|build-order] <finding> — <evidence: spec section, or file:line>
```

## Constraints — which correct designs are wrong here?

| # | Question | A "no" means |
|---|----------|--------------|
| C1 | Is every constraint written as a value, not an adjective ("p99 under 300 ms", not "fast")? | the agent will pick its own number |
| C2 | Does every constraint name a source — `issue`, `user`, or `inferred`? | an invented requirement is about to be built |
| C3 | Does every constraint name how a violation would be detected — a test, a metric, a check in CI? | it cannot be enforced, so it will be violated silently |
| C4 | Is the consistency requirement stated per consumer (who may read stale data, who may not)? | read-your-writes bugs surface only in production |
| C5 | Is the rollout and rollback path stated for every persisted change? | the first deployment is the first test |

## System design — who owns what, and what fails together?

| # | Question | A "no" means |
|---|----------|--------------|
| S1 | Does every fact have exactly one source of truth in the ownership table? | two components will disagree and both will be "right" |
| S2 | Is every arrow in the sketch marked sync or async? | the caller's latency and failure behaviour are undefined |
| S3 | For every arrow, is the behaviour on timeout written down? | the in-doubt case is unhandled |
| S4 | Is every dual write (two stores, or a store plus a message) either eliminated or made atomic (outbox, transaction)? | a crash between the writes leaves the system inconsistent |
| S5 | Is the change's failure unit named — what else stops when this stops? | a small feature can take down an unrelated path |

## Component contracts — can the caller ignore a case it must handle?

| # | Question | A "no" means |
|---|----------|--------------|
| K1 | Does every boundary have a signature in the project's language, not prose? | the builder will invent one, and the tests will pin the invention |
| K2 | Are expected failures returned as outcomes and only unexpected ones raised? | callers will catch broad exceptions or none |
| K3 | Does every outcome type include the in-doubt case when the operation crosses a network? | "declined" and "unknown" will be conflated |
| K4 | Is every operation that may be retried idempotent, with the key named? | duplicate delivery becomes duplicate side effects |
| K5 | Is the versioning strategy for every external contract stated, including how a v1 consumer reads a v2 message? | the first schema change is a breaking change |

## Data models — which field combinations are nonsense, and does the type forbid them?

| # | Question | A "no" means |
|---|----------|--------------|
| D1 | Is every illegal state listed with the construct that makes it unrepresentable (enum, union, non-null, check constraint)? | validation lives in prose and in `if` statements that will be skipped |
| D2 | Does every status field have a transition table listing the legal moves? | any code path can set any status |
| D3 | Does every amount carry its unit or currency, and every timestamp its zone? | the arithmetic is wrong and the tests do not know |
| D4 | Is every tenant- or owner-scoped entity scoped structurally (a repository fixed to the tenant), not by remembering a filter? | one forgotten `WHERE` leaks data |
| D5 | Is the migration reversible, and is the compatibility of old rows with new code stated? | rollback is impossible after the first write |

## Build order — can each slice ship alone, and is the riskiest unknown first?

| # | Question | A "no" means |
|---|----------|--------------|
| B1 | Does every slice depend only on earlier slices? | the order is a wish list, not a plan |
| B2 | Do contracts and data models land before the components that consume them? | the consumer is built against a guess |
| B3 | Does every slice leave the suite green and the system deployable? | the review checkpoints between slices are fiction |
| B4 | Is the slice with the largest unknown first — a spike slice if the unknown is technical? | the expensive surprise arrives last |
| B5 | Does every slice carry criteria a test can pin — no "works correctly", no "handles errors"? | `/build` has nothing to write a failing test against |

## Using the card

- Step 4 of the skill: the agent runs the card against its own spec. A "no" is
  fixed in the spec or recorded in *Decisions* with the reason it stays open.
- Step 7 of the skill: the human reviewer may use the same card. The agent
  answers every finding by editing the spec and re-rendering, not by replying
  in chat.
- A question that does not apply is marked `n/a` with the reason in one clause
  ("n/a — no external call on this path"). Unmarked questions are unanswered.
