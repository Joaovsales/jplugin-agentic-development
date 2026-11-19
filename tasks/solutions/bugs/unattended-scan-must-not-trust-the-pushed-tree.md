---
title: An unattended scanner cannot load its own protection from the pushed tree
date: 2026-11-19
problem_type: bug
module: .agents/git-hooks/pre-push
tags: [unattended-scan, trust-boundary, pre-push, git-ranges, security]
symptoms: A routine push could replace its scanner with exit zero or empty the built-in rules, allowing a dangerous script to reach the remote.
root_cause: The hook let the pusher's working tree or mutable local refs choose the scanner, built-ins and diff lower bound.
resolution: Extract both files with git show from the negotiated remote SHA for updates or a server-queried fully qualified base ref for new refs, run isolated Python, and check pushed scanner/rule changes independently; refuse missing anchors or built-ins.
date_source: session
---

PR #450's first review reproduced successful real pushes with removed rules.
Its re-review found that using a local `origin/master` merge base still let the
pusher choose both the scan's lower bound and its supposedly trusted scanner:
tracking refs can be rewritten and a local branch can shadow a short name.

Correction from N1: `.agents/git-hooks/pre-push:37` takes an update's anchor
from Git's server-negotiated remote SHA; `:41` queries fully qualified server
base refs using the push URL for new refs. The exact anchor commit must exist
locally (`:63`), and lookup/object failure refuses instead of falling back to a
local ref. The snapshot (`:83`) stays at that SHA; a new ref's diff and integrity
range use its merge base with the pushed commit (`:71`), while updates retain
the negotiated remote tip. Installed-hook edits, Git configuration, `PATH` and
`--no-verify` remain outside what a local hook can protect.

Correction from N2: diffing a stale branch directly against a newer server tip
attributed server-side CI/scanner edits or removed example lines to the clean
branch. Keep policy trust separate from range ancestry: derive the fork point
from the server anchor for new refs, then scan only the branch's changes. The
four Fork point actual-push cases cover a README control, server CI edits,
server scanner edits and a removed flagged doc line; the scanner case also
proves the newer server snapshot still executes.

Regression: `tests/test-pre-push-gate.sh` Remote anchor cases drive actual pushes
through the installed hook for tracking-ref rewrites, branch shadowing, a
replacement scanner, failed `ls-remote`, a missing anchor object and an existing
ref update without a local baseline or policy lookup. Original tampering,
empty-built-in, framing and transcript regressions remain in place.
