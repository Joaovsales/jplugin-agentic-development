# Non-pessimization review

Not optimisation: removing work that never needed to happen. A reviewer reads
the hot paths — the critical paths an audit measured, or the files a quality
gate covers — for the patterns below and reports each as a four-axis finding
(`.agents/references/finding-model.md` § *Emission format*) with `file:line`.

## Candidates the scanner proposes

`python3 .agents/skills/perf/scripts/scan.py <paths>` lists the patterns a
machine can spot. Each is a pattern match at confidence 50 until read:

| Pattern | What it flags | Confirm by reading |
|---|---|---|
| `n-plus-one` | a query or remote call (`execute`, `query`, `fetch`, `findMany`, `requests.get`, …) inside a loop, comprehension or `.map` | the loop runs over data that grows; the call hits the database or network, not a cache |
| `sequential-await` | an `await` inside a `for` or `while` body (not inside a `.map(async …)` callback, which runs concurrently) | the items are independent, so they could run together or in one batch |
| `await-waterfall` | two or more consecutive awaits where none uses an earlier one's result | the calls have no ordering requirement the code does not show (a write before a read) |

Python is parsed with `ast`; JavaScript and TypeScript are scanned with strings
and comments masked. An unparsable file is listed under `skipped`, never
dropped silently.

## Patterns only a reader finds

- **Needless copies and allocations** — copying a collection to iterate it,
  building a list only to take its length, converting back and forth between
  types.
- **Repeated parsing or serialisation** — the same JSON, regex, template or
  config parsed per request or per item instead of once.
- **Layers that do nothing** — a wrapper, adapter or service call that only
  forwards, on the hot path.
- **Re-renders** — a UI component re-rendering on every parent change because
  a prop or callback is recreated each time.
- **Oversized payloads** — selecting every column, returning every field, or
  shipping a library for one function.

## Severity and confidence

- `MUST-FIX` when the waste is on a measured critical path with a gap of 2× or
  more; `SHOULD-FIX` otherwise. `NITPICK` is never filed.
- `confidence: 75` once the code is read and the path is shown to be hot;
  `100` when a measurement moves when the waste is removed.
- A candidate the reader refutes is dropped with a word; one that stays
  unsure goes under the audit's `unverified` list.
