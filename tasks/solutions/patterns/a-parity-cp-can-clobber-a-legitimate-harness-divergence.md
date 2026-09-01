---
title: A parity `cp` can clobber a legitimate harness divergence
date: 2026-08-11
problem_type: pattern
module: skill-parity
tags: [agents, claude, parity, frontmatter]
applies_when: Any time an edit to `.agents/**` is copied to the matching `.claude/**` path.
date_source: git-log
migrated_from: tasks/memory.md
---

## A parity `cp` can clobber a legitimate harness divergence

**Pattern**: `.claude/` copies are byte-identical *except* for allowlisted Claude-only frontmatter — `.claude/agents/software-design-expert-review.md` carries `model: sonnet` by design (Reviewer tier, not Ceiling). A blind `cp` from `.agents/` silently drops it, and `test-skill-parity.sh` cannot catch it because parity is what the `cp` just enforced. After any parity copy, run `git diff .claude/agents/ | grep -E '^[-+]model:'` and confirm it is empty.

**Evidence**: Tier 2 build — the `cp` loop dropped that pin; caught only by an explicit frontmatter diff, not by the 13-file green suite.
