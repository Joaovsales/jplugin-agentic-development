---
title: Name the gate outcome file per session in the shared receipt store
date: 2026-10-14
problem_type: process
module: /quality-gate Phase 6; .agents/skills/quality-gate/SKILL.md § Phase 6
tags: [quality-receipt, worktrees, parallel-sessions, receipt-store]
applies_when: /quality-gate Phase 6 writes its outcome JSON while other sessions or worktrees of the same clone may be running a gate
---

`/quality-gate` Phase 6 writes the outcome to one fixed path,
`<git common dir>/quality-receipts/outcome.json`
(`.agents/skills/quality-gate/SKILL.md:291`). The common dir is shared by every
worktree of the clone. The 2026-10-14 session (#168) found an `outcome.json`
and an `outcome-146.json` from other sessions already in the store, so two gates
can share one path at the same time.

Rule: write the outcome to a name that only this session uses, such as
`outcome-<issue or branch>.json`, and pass that path to `receipt.py write
--outcome`. If another session overwrites a shared file between the write and
the mint, `receipt.py` mints from the other session's outcome. Usually that
outcome's `tests.tree` does not match this tree, and the write is refused
(`receipt.py:236`). When both sessions are on the same tree, it is not refused,
and the receipt carries another session's verdict.

Related: [a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md](a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md)
(the same phase, on this machine).
