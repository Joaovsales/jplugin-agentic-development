---
title: An unattended scanner cannot load its own protection from the pushed tree
date: 2026-11-19
problem_type: bug
module: .agents/git-hooks/pre-push
tags: [unattended-scan, trust-boundary, pre-push, rules, security]
symptoms: A routine push could replace its scanner with exit zero or empty the built-in rules, allowing a dangerous script to reach the remote.
root_cause: The hook executed the scanner and loaded built-ins from the mutable working tree, so the pushed code chose the protection applied to itself.
resolution: Extract both files with git show from a trusted remote merge base into a temporary directory, run isolated Python, and check pushed scanner/rule changes independently in the hook; refuse missing or empty built-ins.
date_source: session
---

PR #450's independent review reproduced successful real pushes with removed
rules. The review fixes separate the trusted baseline from the diff range:
`.agents/git-hooks/pre-push:35` resolves the remote merge base;
`.agents/git-hooks/pre-push:53` checks scanner/rule edits outside the scanner;
`.agents/git-hooks/pre-push:65` extracts the baseline snapshot. A baseline
without the scanner refuses unattended pushes until a human bootstraps it.

Regression: `tests/test-pre-push-gate.sh` § unattended trust covers committed
and dirty scanner/rule tampering, selective removal and scanner-only edits.
`tests/test-unattended-scan.sh` § fixtures refuses empty built-ins; independent
regressions pin threat payloads separately from mutable rule fixtures.
