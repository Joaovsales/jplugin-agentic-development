# Plugin hooks, slim banner, hook retirement

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: design.specs-single-instruction-file-md.plugin-hooks-slim-banner-hook-retirement
kind: feature
spec: specs/single-instruction-file.md
evidence: design: specs/single-instruction-file.md § Build order, slice 3
<!-- task-registry:end -->

- status: open
- updated: 2026-09-22

## Summary

Slice 3/6: hooks/hooks.json registers the three events against .agents/hooks/*.sh, .claude/hooks/ retired, .claude/settings.json without Stop/PreCompact, /sync drops downstream hook entries, banner without skills list and footer plus missing-block and graphify lines, D19 fallback chain, plugin version bump. After: Single AGENTS.md and its delivery.

## Acceptance Criteria

- [ ] hooks/hooks.json is valid JSON with exactly the three events and each command runs through bash -c with a spaced, backslashed CLAUDE_PLUGIN_ROOT
- [ ] .claude/hooks/ holds no scripts, its syncable row begins RETIRED, and .claude/settings.json registers none of the three events
- [ ] a /sync fixture settings.json carrying the old entries ends with neither and its other keys byte-identical
- [ ] the banner prints no skills list or footer, one line for a missing block only in an adopting repository, one for a stale graph, nothing extra when nothing is wrong
