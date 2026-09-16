# Lane: perf

Owned by the go front door. Runs when the goal reports slowness, latency,
memory, "takes N seconds", or attaches a profile.

1. Baseline: measure the reported path with a repeatable command and record the command and the number before any edit
2. `/debug <goal>` — the baseline is the reproduction; find the cause, not the first hot spot
3. `/build` — the fix, with a test or measurement that fails at the baseline and passes after
4. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran)
5. `/wrap-up-session` — the PR body quotes the baseline and the after number from the same command

## Reply

Baseline and after numbers from the same command, the cause with its
`file:line`, and the PR URL.
