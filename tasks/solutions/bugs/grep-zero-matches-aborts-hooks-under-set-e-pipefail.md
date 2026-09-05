---
title: grep with zero matches aborts hooks under set -eo pipefail
date: 2026-08-13
problem_type: bug
module: .claude/hooks/session-start.sh
tags: [bash, hooks, grep, pipefail, set-e]
symptoms: session-start banner died mid-print whenever the learning store had zero flagged documents — no error, hook just stopped
root_cause: grep exits 1 on no match; inside a pipeline under set -eo pipefail that non-zero status propagates through the command substitution and kills the script
resolution: append `|| true` to the pipeline and scope the glob to `tasks/solutions/*/` so the store README's literal mention of the flag is not counted (.claude/hooks/session-start.sh:103)
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

## Recurrence — 2026-09-05: the same defect, one level up

The second half of the resolution above was **incomplete**, and this document is
what proved it. Scoping the glob to `tasks/solutions/*/` excluded the store
README, but not a *document* that quotes the flag in its own prose — and this
document does, twice (lines 28 and 35 above). So the session-start banner
reported `1 needs_review` while zero documents carried the flag, permanently.

Found by running `/memory-maintain`, whose Phase 1 opened this file expecting a
flagged document and found none.

The corrected fix anchors to the frontmatter field rather than narrowing the
search location:

```bash
REVIEW_COUNT=$(grep -rlE '^needs_review: true' tasks/solutions/*/ 2>/dev/null | wc -l | tr -d ' ' || true)
```

`.claude/hooks/session-start.sh:156`, and the same pattern in
`/memory-maintain`'s light pass (both skill copies).

**The generalisable error**: the first fix restricted *where* to look when the
defect was *what* to match. A store of documents about a system will inevitably
quote that system's own markers, so any grep over prose must match structure
(column-0 frontmatter) rather than rely on no document ever mentioning the
string. Same shape as
[[scoping-a-guard-per-item-can-silently-weaken-it]].

## Prevention

In any `set -eo pipefail` script, treat every counting/filtering grep as a
command that is *expected* to fail: `grep ... || true` inside pipelines, or
`grep -c` with an explicit exit check. Test the zero-match path — it is the
path that never shows up during development because fixtures always match.
