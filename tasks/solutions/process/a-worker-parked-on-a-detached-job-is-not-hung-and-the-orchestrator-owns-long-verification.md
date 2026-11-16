---
title: A worker parked on a detached job is not hung; the orchestrator owns long verification
date: 2026-11-16
problem_type: process
module: .agents/references/subagent-resilience.md § Worker liveness
tags: [orchestration, worker-liveness, orca, dispatch, stall-triage]
applies_when: briefing a dispatched worker whose task includes a full suite, a benchmark or another long-running check, or triaging a worker that has gone quiet
---

The doctrine is `.agents/references/subagent-resilience.md`
§ *Worker liveness: three failures that are not a hang* (landed in #424,
moved to `.agents/references/` in #430). Do not restate it; this document
records the evidence behind it and the remedy that worked.

All three modes were seen in the 2026-11-15/16 session:

1. **Detached-job park.** The worker started a background job and ended its
   turn. A worker cannot wake itself, so ending the turn is the report the
   coordinator receives, and it looks like a hang. **Writing the instruction
   more forcefully did not work.** One worker parked after two explicit
   warnings, and one of those warnings was in the very brief it parked on.
   **What worked:** the orchestrator ran the long verification itself and
   gave the worker a decided verdict to act on.
2. **Usage-limit window.** A provider's usage window ran out mid-run, and
   every worker on that provider stopped at the same time. Wait for the
   reset or switch provider. Do not message the workers or retry them as-is.
3. **start_unknown.** A dispatched worker never ran a single turn but kept
   its task indefinitely, and a `send` did not revive it. Dispatch it again
   fresh.

**Rule.** Tell the three apart before choosing a remedy. Keep anything a
worker must wait on out of the worker's own turn.
