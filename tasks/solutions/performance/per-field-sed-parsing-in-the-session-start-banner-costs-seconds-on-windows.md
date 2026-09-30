---
title: Per-field sed parsing in the session-start banner costs seconds on Windows
date: 2026-09-29
problem_type: performance
module: .agents/hooks/session-start.sh § Stale Plugin Install Check
tags: [windows, process-spawn, hooks, banner, awk, json]
symptoms: "The first draft of the stale-plugin block raised the startup banner from ~8.5 s to ~16.6 s on this Windows machine (hook timed before/after in the same checkout)"
root_cause: "The real installed_plugins.json holds one jplugin record per worktree (7 here). The draft extracted each field with its own `$(printf | sed | head)` and normalised each projectPath with another pipeline, so every record paid roughly ten process spawns, at about a second each on Windows"
resolution: "One `tr | sed | awk` pipeline parses every record, filters by scope and projectPath, and prints `<scope> <sha> <version>` (.agents/hooks/session-start.sh:471-490). The per-record bash loop then spawns only git, and only for records that load here. Template candidates are computed only when a record survives. Measured over four alternating runs: +2 s over base (8.5 s -> 10.4 s)"
---

**Status**: fixed — 2026-09-29 (this session, #210)

When a banner block iterates over records, do the parsing in one process and
leave the loop only the calls that must be per-record. Measure on Windows
before and after, over several alternating runs, because single timings here
swing by 3 s.

Related: performance/windows-suite-takes-20-to-38-minutes-because-every-process-spawn-costs-over-a-second.md
(the same spawn cost, in the test suite).
