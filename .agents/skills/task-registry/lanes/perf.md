---
cues: audit performance, how fast is this app, performance audit, slow, latency, memory, takes N seconds, a profile attached
ends: Audit — a ranked audit report and one filed task per finding; Debug — PR whose body quotes baseline, expected and after numbers from the same command
---
# Lane: perf

Runs when the goal is about speed, in one of two modes. **Audit** is
proactive: the goal asks to audit performance or how fast an app or flow is,
with no symptom. **Debug** is reactive: the goal reports one slow path —
slowness, latency, memory, "takes N seconds", or an attached profile. Outranks
`refactor` and is outranked by `fix` when both match; a how-fast question is
`perf`, not `investigate`, because its answer is a measurement.

1. Pick the mode from the goal: **Audit** for "audit performance", "how fast is", "performance audit", or a whole app or flow named with no symptom; **Debug** for one slow path ("slow", "latency", "takes N seconds", memory, a profile attached). Name the mode in the reply
2. `/perf <mode> <ref>` — Audit: inventory the critical paths, measure each as N runs (min, median, spread), estimate the expected number, review the hot paths for wasted work, write the ranked report and file one task per finding; the lane ends here and every later step is kept with ` — skip: audit mode`. Debug: the baseline (N runs of one repeatable command) and the expected number, recorded before any edit
3. `/debug <ref>` — Debug only: the baseline is the reproduction; find the cause, not the first hot spot
4. `/build` — Debug only: the fix, with a test or measurement that fails at the baseline and passes after
5. Debug only: re-measure with the baseline's command and run count, then `measure.py compare` with the expected number; `improved` only when the after median is below the baseline's minimum, and a `within-noise` result is never reported as an improvement
6. `/quality-gate` — structural, anti-pattern, and APOSD passes, with the Phase 3 waste scan (runs inside the build's Phase 3; the row records where it ran) — **non-skippable** in Debug mode
7. `/wrap-up-session` — Debug only: the PR body quotes the `measure.py compare` table — baseline, expected and after from the same command, and the verdict

## Reply

The mode taken. Audit: the report path, the measured, expected and gap per
critical path, the ranked findings with `file:line`, and every filed task (or
`Findings: none`). Debug: baseline, expected and after numbers from the same
command with the verdict, the cause with its `file:line`, and the PR URL.
