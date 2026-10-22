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
- `ToolResult` keeps the whole `toolUseResult` (a Read's full file content) until the classify pass at the end of `parse_transcript`, so one session's memory scales with its read volume rather than its line count, and the Read-only `numbered` / `non_file` fields sit on the generic result record. The module docstring's "only metadata is kept" overstates it. Upgrade path: classify each tool use at result time (uses precede results) and keep only `(bytes, sidechain)` on the result; the parent call order then follows append order. Left for a later change — the 301-session baseline ran within minutes, and a per-session transcript is dropped after parsing (quality-gate finding, SHOULD-FIX manual, 2026-10-22).
- `Transcript` answers two frames of reference with look-alike predicates: `ToolUse.sidechain` is session-relative (a sub-agent's call) while the `own_*` accessors are file-relative (this file's context), so on a `subagents/` file `own_reads()` and `sidechain_reads()` return the same list and on a parent file they partition `reads()`; a caller summing across files must know `is_subagent`. Upgrade path: rename the session-relative accessors (`subagent_reads()`), or let `SessionReads` be the only object that answers session-frame questions. Left as is — `SessionReads.session_sidechain_reads` already carries the cross-file union both CLIs use (quality-gate finding, SHOULD-FIX advisory, 2026-10-22).
- Real roots repeat a tool use: `api-request-blob` records copy the request's `tool_use` blocks (no uuid, no isSidechain) and a resumed session re-logs assistant records verbatim; the parser reads only `assistant` / `user` / `system` records and absorbs a tool-use id — and its result — once, first record wins. The spec's § Edge Cases should name the two shapes (found 2026-10-22; baseline revised).
