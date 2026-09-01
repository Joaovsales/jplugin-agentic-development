---
title: Pin whitespace-normalized text when guarding hard-wrapped prose
date: 2026-08-11
problem_type: pattern
module: documentation-tests
tags: [markdown, whitespace, regression-test]
applies_when: "`tests/test-doc-conventions.sh`-style token greps over markdown."
date_source: git-log
migrated_from: tasks/memory.md
---

## Pin whitespace-normalized text when guarding hard-wrapped prose

**Pattern**: `grep -F` on a multi-word phrase fails when the phrase straddles a newline in hard-wrapped prose, producing a phantom failure on a pure reflow. Collapse first (`tr '\n' ' ' | tr -s ' '`) and assert against that. Single tokens are safe either way.

**Evidence**: Tier 2 — two assertions failed only because "separately dispatched contexts" wrapped mid-phrase.
