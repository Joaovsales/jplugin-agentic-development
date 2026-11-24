# Estimate — how fast should this be?

Estimate before you optimise. The expected number is not a target someone
wished for: it is the time the work the path *really needs* takes on this
hardware and network, worked out on the back of an envelope. The gap between it
and the measured median tells you whether there is anything to win, and its
likely source tells you where.

## Method

1. **Name the work the path must do** — the rows it must read, the bytes it
   must move, the round trips it cannot avoid, the pixels it must paint.
   Ignore how the code does it today.
2. **Price each piece** with the reference costs below, and add them.
3. **Write the basis as one sentence of arithmetic** — "2000 rows from one
   indexed query (~2 ms) plus JSON for 200 KB (~2 ms) ≈ 5 ms". The audit schema
   requires it; a number with no basis cannot be checked.
4. **Record the gap**, measured median ÷ expected. Under about 2× there is
   little to win; 10× and above almost always means waste, not tuning.
5. **Name the likely source** from the list in § *Where a gap comes from*.

## Reference costs

Orders of magnitude, not benchmarks — enough to tell 5 ms from 500 ms.

| Operation | Rough cost |
|---|---|
| Main-memory read, cache miss | ~100 ns |
| Read 1 MB sequentially from memory | ~50 µs |
| SSD random read | ~100 µs |
| Read 1 MB sequentially from SSD | ~0.5 ms |
| Round trip inside one data centre / to a local database | 0.2–1 ms |
| Simple indexed database query, server side | 0.1–1 ms |
| Process start-up: a compiled binary / Python / Node | ~1 ms / 20–50 ms / 40–80 ms |
| Round trip across a continent | 30–80 ms |
| One 60 Hz frame | 16.7 ms |
| Download 1 MB over a fast mobile connection | 100–300 ms |

## Where a gap comes from

The performance-aware view (Casey Muratori, *Performance-Aware Programming*)
names five multipliers between what the hardware can do and what code gets:
**waste**, instructions per clock, SIMD, **caching** and **multithreading**.
Waste is the first and largest, and the one an audit finds by reading. In
application code the gap is usually one of:

- **waste** — work whose result nobody needs: copies, re-parsing, layers that
  only forward, re-renders (`references/non-pessimization.md`);
- **cache misses** — the same answer computed or fetched again;
- **serial work that could be parallel** — independent calls one after another;
- **waterfalls** — request B waits for request A only because of code order;
- **N+1 queries** — one round trip per item instead of one per set;
- **oversized payloads** — bytes moved that the caller never reads.
