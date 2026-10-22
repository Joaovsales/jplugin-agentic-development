# Reconcile specs/read-shunt-baseline.md with the build's [AMBIGUITY] decisions

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: spec-reconciliation.specs-read-shunt-baseline-md
kind: task
spec: specs/read-shunt-baseline.md
<!-- task-registry:end -->

- status: open
- updated: 2026-10-22

## Summary

The excluded column now also counts null-result Read notes (unchanged-file, empty-file, image, PDF); D14 sizes a shell/Grep routing-around by a path already read large in the run; Mode C and the grader docstring describe a results layout claude plugin eval does not leave (arranged by hand from --keep-temp). Ratify or reverse each in the spec.

## Added 2026-10-22

- The arranging step is now `arrange-plugin-eval-results.py` (`<keep-temp>` is the directory of `claude-eval-<id>` homes, or the one home a run's `tracePath` names); the spec's § Behavior › Eval harness should say so.
- An Agent result without `totalTokens` / `totalToolUseCount` is drift only when its `status` is `completed` (`async_launched` carries none).
- `cat -n f` / `cat -b f` / `cat -s f` count as shell reads (per-command option grammar); the 2026-10-21 baseline's shell figures were undercounted and are revised in the report.
- The gate's `shunt.jsonl` record shape (`decision`, `tool`, `input`, the literal `deny`) is known only to the grader's hook columns, and `arrange` never places the log beside a transcript; specs/read-shunt.md names the hook's log at `tasks/.shunt/<session>.jsonl`. Add a D7 note: when the hook is built, the parser owns a `ShuntDecision` reader/writer beside `SHUNT_LOG` and `arrange` copies the log (quality-gate finding, advisory, 2026-10-22).
