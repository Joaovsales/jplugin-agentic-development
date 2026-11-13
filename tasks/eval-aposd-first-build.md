# Design-mode `/build` comparison — AC17 report

Slice 14 of `specs/aposd-first-build.md`. `/eval` Mode B (variant lift), run 2026-10-21 on
Windows Git Bash, candidates on Sonnet (`claude -p --model sonnet`), judge on Opus.

**Rule result: revert slices 9 and 11.** Round 1 failed on AC coverage and design
findings, with routing the main cause. The owner chose to fix the routing
(`e95d17f`) and re-run. Round 2, the deciding round, gives equal AC coverage, but
design findings are not fewer and the cost is 3.09× (limit 2×). **Owner's call
(2026-10-21): revert** — spec D23 records what was removed and what stays.

## Round 2 — after the routing fix (deciding)

Arm A `4c2f3c2` (unchanged), arm B `e95d17f`: Phase 1 now opens with
`slice.py ready` for every plan, and a design-mode ready line names its loop. Eight
fresh runs s1–s8, interleaved, same seeds, prompts, probes, freeze check and judge
procedure as round 1. The judge (Opus, blind, new seeded shuffle) was given round 1's
borderline calls in advance so both rounds share one scale.

| Run | Arm | Feature | ACs | Freeze viol. | Gate ran | Gate design findings | Judge pitfalls | Judge R1–R5 | Cost USD |
|-----|-----|---------|-----|--------------|----------|----------------------|----------------|-------------|----------|
| s1 | A | confkit | 10/10 | n/a (0) | yes | 4 | 1 | 9 | 0.73 |
| s4 | A | retrykit | 9/9 | n/a (0) | no (skipped) | — | 0 | 10 | 0.35 |
| s5 | A | retrykit | 9/9 | n/a (0) | no (skipped) | — | 0 | 10 | 0.36 |
| s8 | A | confkit | 10/10 | n/a (0) | no (skipped) | — | 1 | 8 | 0.57 |
| s2 | B | retrykit | 9/9 | 0 | yes | 3 | 0 | 10 | 1.87 |
| s3 | B | confkit | 10/10 | 0 | no (skipped) | — | 2 | 7 | 0.94 |
| s6 | B | confkit | 10/10 | 0 | yes | 8 | 1 | 9 | 1.49 |
| s7 | B | retrykit | 9/9 | 0 | yes | 6 | 0 | 10 | 1.90 |

Judge mapping: run-01 s7, run-02 s8, run-03 s4, run-04 s1, run-05 s2, run-06 s3,
run-07 s5, run-08 s6. Scores: `~/work-logs/v2/judge/scores.json`.

| Comparison (AC17 rule) | Arm A | Arm B | Holds? |
|------------------------|-------|-------|--------|
| B's AC coverage ≥ A's | 1.000 | 1.000 | yes |
| B's design findings fewer (transcript count, mean over runs whose gate ran) | 4.0 (1 run) | 5.67 (3 runs) | **no** |
| B's cost ≤ 2× A's (mean per run) | 0.50 | 1.55 (3.09×) | **no** |

Beside the rule: freeze violations, arm B 0 in every run. The judge's diff count agrees
on design (A 0.50, B 0.75 pitfalls per run; rubric totals A 9.25, B 9.0). In s3 the
loader re-parses INI inside `layered.py` instead of building on `parse.py` (P7).

What round 2 shows:
- **The routing fix works.** All four arm B runs ran stubs → `test-engineer` Write →
  red → `> Frozen:` (`context: fresh`) → implement, with no freeze violation and no
  wasted pass.
- **The loop is expensive.** It costs 0.94–1.90 USD per run against arm A's 0.35–0.73.
  The separate Write dispatch and the depth pass are the extra work.
- **It buys nothing measurable on these features.** Both arms meet every AC, and
  design quality in the final diffs is equal within noise. The independently written
  tests did not catch anything that arm A's tests missed: every arm A run passed every
  probe.

Round 1 is kept below as found; its rule result was revert as well.

## Round 1 — before the routing fix

## Setup

| Arm | Plugin | Plan staged |
|-----|--------|-------------|
| A | merge-base `4c2f3c2` (legacy `/build`, no `mode=`) | `plans/legacy.md` (`TDD:` rows) |
| B | `b2504fe` (design-mode `/build`, `slice.py ready` prints `mode=design`) | `plans/design.md` (bare slice headers) |

- Seeds, specs and prompts: `tests/fixtures/build-eval/`. Two features × two runs per arm =
  8 runs, interleaved r1–r8; neutral run directories under `~/work/`.
- Each run directory gets its arm's committed `.agents/` and `.claude/agents/`
  (`git archive`), as `/sync` installs them. A first wave without them was discarded: the
  skills' project-relative scripts were missing, so `/build` ran inline with no
  `slice.py` and the arms could not differ (runbook fixed in `1833af2`).
- AC coverage: operator probe scripts written from `answer-key.md` Part 3, verified to
  score 0/9 and 0/10 on the unbuilt seeds. Freeze violations: Part 4 procedure.
  Design findings: Part 2. Judge: one blind pass, labels `run-01`…`run-08` from a
  seeded shuffle; patches scanned for arm-revealing words (only `@dataclass(frozen=True)`,
  which the spec requires).

## Per run

| Run | Arm | Feature | ACs | Freeze viol. | Gate ran | Gate design findings | Judge pitfalls | Judge R1–R5 | Cost USD | Minutes* |
|-----|-----|---------|-----|--------------|----------|----------------------|----------------|-------------|----------|---------|
| r1 | A | retrykit | 9/9 | n/a (0) | yes | 2 | 0 | 10 | 0.70 | 6.4 |
| r4 | A | confkit | 10/10 | n/a (0) | yes | 3 | 1 | 9 | 0.64 | 5.1 |
| r5 | A | confkit | 10/10 | n/a (0) | yes (Phase 4 inline) | 1 | 1 | 9 | 0.77 | 10.7 |
| r8 | A | retrykit | 9/9 | n/a (0) | **no** (skipped) | — | 0 | 10 | 0.40 | 4.8 |
| r2 | B | confkit | 10/10 | 0 | yes | 5 | 0 | 10 | 1.70 | 11.6 |
| r3 | B | retrykit | 9/9 | 0 | yes | 3 | 0 | 10 | 1.69 | 15.6 |
| r6 | B | retrykit | **3/9** | **1** (no freeze) | no (stopped) | — | 0 | 7 | 0.47 | 2.2 |
| r7 | B | confkit | 10/10 | **1** (no freeze) | no (skipped) | — | 1 | 8 | 0.51 | 1.7 |

\* longest `result` event's `duration_ms`; a run that resumed on a background-agent
notification emits more than one, so this is a lower bound on wall time.

Judge mapping: run-01 r3, run-02 r6, run-03 r2, run-04 r8, run-05 r4, run-06 r1, run-07 r5,
run-08 r7. Full scores: `~/work-logs/judge/scores.json`.

## The keep-or-revert rule (AC17, verbatim thresholds)

| Comparison | Arm A | Arm B | Holds? |
|------------|-------|-------|--------|
| B's AC coverage ≥ A's (mean fraction, averaged over features) | 1.000 | 0.833 | **no** |
| B's design findings fewer (Part 5: transcript count, mean over runs whose gate ran) | 2.0 (3 runs) | 4.0 (2 runs) | **no** |
| B's cost ≤ 2× A's (mean per run) | 0.63 | 1.09 (1.74×) | yes |

Recommendation by the rule: **revert slices 9 and 11.** Beside the rule: test-freeze
violations, arm B mean 0.5 (r6, r7 recorded no freeze); arm A n/a.

The judge's cross-check of pitfalls left in the final diffs points the other way on
design: arm A 0.50 per run, arm B 0.25 per run (one leaked-internals occurrence each in
r4, r5, r7). Judge rubric totals: A 9.5, B 8.75 (B pulled down by the incomplete r6).

## What drove the result

1. **Arm B routed into design mode in only one run of four.** `slice.py ready` printed
   `mode=design` in every arm B run, but:
   - r3 ran the full loop: stubs → `test-engineer` Write → red → `> Frozen:` → implement
     → depth pass, with `context: fresh` on both freezes and no violation.
   - r2 dispatched one `backend-developer` for the whole slice, as in tdd mode;
     `slice.py check --index` then exited 3 (`missing freeze commit`), the orchestrator
     read `design-mode.md`, reverted and redid the slice through the loop. Correct
     result, one wasted implementation.
   - r6 did the same, was stopped by the same exit 3, and ended the build as
     `design-mode.md` step 7 says: slice 2 never ran (the 3/9).
   - r7 never called `slice.py` (it wrongly reported the scripts missing), built in one
     dispatch and marked the slice done; the freeze gate never ran.
   The gate caught both runs that reached Slice Close; the defect is upstream of it:
   `build/SKILL.md` gives design mode one paragraph, and the default dispatch path wins.
2. **The loop costs about 2.7× when it runs.** The two runs that completed the loop
   cost 1.70 and 1.69 against arm A's 0.63 mean. Arm B's mean stays under 2× only because
   r6 and r7 skipped the loop. A fixed router would likely fail the cost comparison.
3. **No quality gain was measurable on these features.** Every completed run in both arms
   met every AC, and design quality in the final diffs was near the ceiling in both
   (judge totals 9–10 for every complete run).

## Caveats

- N = 2 per arm per feature; one outlier (r6) moves AC coverage and the judge mean.
- The transcript design-finding count is not comparable across runs: three runs did not
  run the gate (r6 stopped, r7 and r8 skipped it), and r2/r3 dispatched a full reviewer
  where r5 ran Phase 4 inline. It is the rule's measure, so the rule uses it.
- Cost is the CLI's cumulative `total_cost_usd`; whether it includes background
  sub-agents could not be confirmed from the stream, for either arm.
- Both seed features are small; a design-mode advantage may need a larger interface to
  show.
- Codex and Pi were out of scope (#331).

## If design mode is kept instead

Fix the routing before relying on it: make `mode=design` the branch point at the top of
Phase 1 in `build/SKILL.md` (not one paragraph among the dispatch rules), and have
`slice.py ready`'s `mode=design` line name `design-mode.md`. Then re-run this comparison;
the cost comparison is the one to watch.
