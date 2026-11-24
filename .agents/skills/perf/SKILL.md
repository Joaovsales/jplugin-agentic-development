---
name: perf
description: "Performance work in two modes, with numbers that survive noise. Audit (proactive) inventories an app's critical paths, measures each as N runs with min/median/spread, estimates how fast each should be, reviews the hot paths for wasted work (N+1 queries, awaits in loops, await waterfalls), and writes a ranked report that files one task per finding. Debug (reactive) measures one slow path's baseline and expected number before /debug and /build, then proves the after from the same command — a change inside the noise is not an improvement. Use from the perf lane, or directly. Triggers on: 'audit the performance of', 'how fast is this app', 'performance audit', 'this is slow', 'takes N seconds', 'latency'."
argument-hint: "audit <app | flow> | debug <ref | slow path>"
disable-model-invocation: false
harness: universal
---

# /perf — Measure, estimate, then act

Performance work goes wrong in two ways: optimising a number that was noise,
and optimising without knowing how fast the path should be. This skill refuses
both. Every number is **N runs of one repeatable command** summarised as min,
median and spread; every path carries an **expected** number estimated before
anything changes. Spec: `specs/perf-audit-and-debug.md`.

Two modes. The `perf` lane's step 1 picks one from the goal's words:

| Mode | When | Ends with |
|---|---|---|
| **Audit** | "audit the performance of X", "how fast is this app", a whole app or flow named with no symptom | a ranked report in `tasks/perf/` and one filed task per finding; no code changed |
| **Debug** | one slow path reported: "slow", "latency", "takes N seconds", memory, a profile attached | baseline and expected recorded, handed to `/debug`; after the fix, the comparison the PR quotes |

## Noise control — the one rule both modes share

```bash
python3 .agents/skills/perf/scripts/measure.py run --runs 10 -- <command ...>
python3 .agents/skills/perf/scripts/measure.py summarize --unit ms --command '<what produced them>' <sample ...>
python3 .agents/skills/perf/scripts/measure.py compare <baseline.json> <after.json> --expected <X> --format markdown
```

- `run` times a command with no shell (pass a pipeline as `bash -c '…'`),
  after one warmup, and prints `runs`, `samples`, `min`, `median`, `max`,
  `spread` and `spread_pct`. Fewer than **5 runs** is refused: a single-run
  number is not a measurement. A run that exits non-zero is refused too.
- `summarize` takes numbers another tool produced — per-endpoint latencies, N
  lab traces, `hyperfine --export-json` times — under the same five-sample floor.
- `compare` refuses a baseline and an after from different commands, units or
  run counts. Its verdict: **`improved` only when every after run is faster than
  every baseline run** (after max < baseline min), `regressed` for the mirror,
  `within-noise` otherwise. `within-noise` is never reported as an improvement.
  Disjoint ranges happen by chance for unchanged code once in C(2N, N) — 1 in
  252 at N = 5, 1 in 184756 at N = 10 — while a median judged against the
  other batch's range is fooled by ordinary drift between batches.

Keep the machine quiet while measuring, and say so when it is not (a shared CI
runner, a laptop on battery): the spread is how the reader judges it. A verdict
other than `within-noise` on a change that cannot move the number (a comment, a
rename) means the machine drifted between batches: measure both again, back to
back.

## Audit mode — `/perf audit <app | flow>`

1. **Inventory the critical paths** — startup, the main user flows, the top
   routes or endpoints, the heavy jobs. Take them from the project's
   `verify-<app>` skill or its route table when one exists, else the README and
   the entry points; record which as `inventory_source`. A path you cannot drive
   with a repeatable command is a coverage gap, never a guess.
2. **Measure each path** with `measure.py run` (or `summarize`). Backends also
   get per-endpoint latency and the query count per request. Web paths also get
   a lab trace — LCP, INP, CLS, long tasks — and the JavaScript and CSS bytes,
   through the backend order in `references/web-lab.md`, every number labelled
   **lab data**.
3. **Estimate how fast it should be** — `references/estimate.md`: the work the
   path really needs against what the hardware or network does, in one
   sentence of arithmetic. Record the gap (measured median ÷ expected) and its
   likely source: waste, cache misses, serial work that could be parallel,
   waterfalls, N+1 queries, oversized payloads.
4. **Review the hot paths for wasted work** — run
   `python3 .agents/skills/perf/scripts/scan.py <files on the hot paths>` and
   read every candidate it prints, then walk the rest of
   `references/non-pessimization.md` by hand. Each candidate starts at
   confidence 50; reading the loop and finding it on a measured path makes it
   75, a measurement that moves when you remove it makes it 100. Below 75 it
   goes under `unverified` with the reason.
5. **Write the report** — `tasks/perf/<YYYY-MM-DD>-<slug>.json` in the
   `perf-audit/1` schema (`references/audit-schema.md`), then:

   ```bash
   python3 .agents/skills/perf/scripts/audit.py validate tasks/perf/<file>.json --repo .
   python3 .agents/skills/perf/scripts/audit.py render tasks/perf/<file>.json --repo . > tasks/perf/<file>.md
   ```

   `validate` refuses a single-run or hand-typed number, a path without an
   expected number, a web path without lab LCP/INP/CLS marked `"data": "lab"`,
   and a finding below confidence 75 or without `file:line` or a fix. The
   report ranks findings by **impact × confidence ÷ effort** (impact and effort
   on 1–3).
6. **File one task per finding** through the registry:

   ```bash
   python3 .agents/skills/perf/scripts/audit.py file tasks/perf/<file>.json --repo .           # dry run
   python3 .agents/skills/perf/scripts/audit.py file tasks/perf/<file>.json --repo . --apply   # write
   ```

   Each task is `--kind task --label performance` plus `now` (impact 3) or
   `next`, with an id derived under the `perf` namespace from its file and
   title — a re-run updates, never duplicates. Its reproduction is the measure
   command and the observed and expected numbers. The project's write policy
   decides whether it lands locally or on the tracker; this skill never widens
   it. A filed finding is fixed later in Debug mode:
   `/go "<finding title> #N is slow"`.

Audit mode changes no product code and opens no PR.

## Debug mode — `/perf debug <ref>`

1. Name the slow path and **one repeatable command** that exercises it.
2. **Baseline** before any edit:
   `measure.py run --runs 10 -- <command> > tasks/perf/<slug>-baseline.json`.
3. **Expected** — the estimate from `references/estimate.md`, with its basis.
4. Hand both to `/debug <ref>` as the reproduction; `/build` makes the fix with
   a test or measurement that fails at the baseline and passes after.
5. **After** — the same command and the same `--runs`, into
   `<slug>-after.json`, then
   `measure.py compare <baseline> <after> --expected <X> --format markdown`.
   That table — baseline, expected, after and the verdict, one command — goes
   into the PR body verbatim. A `within-noise` or `regressed` verdict means the
   fix is not a performance win: say so, and keep it only if it is worth
   having for another reason.

## Integration

- **Lane**: `perf` (`.agents/skills/task-registry/lanes/perf.md`) names this
  skill as its first skill step in both modes.
- **Quality gate**: `/quality-gate` Phase 3 runs `scan.py` over its file list;
  the candidates are scale findings at confidence 50.
- **Filing**: only through `task-registry upsert`, via `audit.py file`.
- **References**: `references/estimate.md`, `references/non-pessimization.md`,
  `references/web-lab.md`, `references/audit-schema.md`.
