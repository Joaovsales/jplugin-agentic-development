# install.sh stops copying

<!-- task-registry:begin -->
<!-- Managed by /task-registry. Edit the fields, not the markers. -->
task-id: design.specs-single-instruction-file-md.install-sh-stops-copying
kind: feature
spec: specs/single-instruction-file.md
evidence: design: specs/single-instruction-file.md § Build order, slice 5
<!-- task-registry:end -->

- status: open
- updated: 2026-09-22

## Summary

Slice 5/6: install.sh step 5 removed, one-confirmation removal of stale ~/.claude/CLAUDE.md, ~/.claude/hooks/session-start.sh plus its SessionStart entry and the ~/.codex/AGENTS.md block; install-codex.sh stops rendering the global file; render_global deleted; README Layer 1 rewritten. After: Sync project migration and drift.

## Acceptance Criteria

- [ ] install.sh writes neither ~/.claude/CLAUDE.md nor ~/.claude/hooks/session-start.sh nor a SessionStart entry; y removes the listed copies, N keeps them with Kept(n) and the double-banner note; a personal ~/.claude/CLAUDE.md is never listed
- [ ] install-codex.sh writes no ~/.codex/AGENTS.md and strips a pre-seeded block with personal text intact; render_global is gone
