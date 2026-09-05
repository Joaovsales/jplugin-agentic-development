---
title: grep with zero matches aborts hooks under set -eo pipefail
date: 2026-09-05
problem_type: bug
module: .claude/hooks/session-start.sh
tags: [bash, hooks, grep, pipefail, set-e]
symptoms: session-start banner died mid-print whenever the learning store had zero flagged documents — no error, hook just stopped
root_cause: grep exits 1 on no match; inside a pipeline under set -eo pipefail that non-zero status propagates through the command substitution and kills the script
resolution: append `|| true` to the pipeline, and anchor the pattern to line start so only frontmatter counts (.claude/hooks/session-start.sh:156). The original scope-the-glob fix addressed only the README instance and recurred inside a category directory — see Recurrence below
---

## Symptoms

With `set -eo pipefail` active, any counting pipeline of the shape
`COUNT=$(grep -rl PATTERN dir | wc -l)` aborts the whole script the moment
grep finds nothing: grep's exit 1 becomes the pipeline status under
`pipefail`, and `set -e` kills the assignment. The failure mode is silent
truncation — everything after the line simply never runs.

## Root cause

Two independent defects stacked:

1. grep treats "no matches" as exit 1, which `pipefail` surfaces as a
   pipeline failure even though `wc -l` succeeded.
2. The original glob (`tasks/solutions`) also matched the store's own
   `README.md`, whose schema documentation contains the literal string
   `needs_review: true` — inflating the flagged-document count by one.

## Resolution

`.claude/hooks/session-start.sh:103` now reads:

```bash
REVIEW_COUNT=$(grep -rl 'needs_review: true' tasks/solutions/*/ 2>/dev/null | wc -l | tr -d ' ' || true)
```

The `tasks/solutions/*/` glob only descends into category directories
(skipping the top-level README), and `|| true` absorbs the no-match exit.
Regression test: tests/test-session-start.sh:62-88 (zero-flag fixture with a
README that mentions the flag literally).

## Prevention

In any `set -eo pipefail` script, treat every counting/filtering grep as a
command that is *expected* to fail: `grep ... || true` inside pipelines, or
`grep -c` with an explicit exit check. Test the zero-match path — it is the
path that never shows up during development because fixtures always match.

## Recurrence — 2026-09-05

The glob fix was a symptom fix. Scoping to `tasks/solutions/*/` excluded the store
README, but the real defect is that an **unanchored** grep counts every *mention*
of the flag, and a category document may mention it too.

This document is that document. Its prose and its code block both quote
`needs_review: true`, so the counter reported one flagged document when the store
had none — the session-start banner misreported store health, and
`/memory-maintain`'s light pass inherited the same number from the same pattern.

The flag is frontmatter, so the match belongs at the start of a line:

```bash
REVIEW_COUNT=$(grep -rl '^needs_review: true' tasks/solutions/*/ 2>/dev/null | wc -l | tr -d ' ' || true)
```

Fixed in `.claude/hooks/session-start.sh:156` and in both copies of
`skills/memory-maintain/SKILL.md`. Regression test:
`tests/test-session-start.sh` — a fixture document that mentions the flag in prose
must count as zero flagged.

**The general lesson**, which the original entry missed: when a grep asks "which
files *are* X", excluding the one known false positive fixes that instance and
leaves the class open. Anchor or otherwise constrain the pattern to the structural
position the value actually occupies. A store of documents *about* the codebase
will always eventually contain a document about the pattern you are grepping for.
