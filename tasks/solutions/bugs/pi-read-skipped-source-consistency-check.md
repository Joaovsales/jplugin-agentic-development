---
title: Pi read skipped source-consistency check after a file changed
date: 2026-09-28
problem_type: bug
module: scripts/context-read.py, pi/extensions/bulk-read-gate.ts
tags: [pi, hooks, source-verification, race, regression-test]
symptoms: "A Pi read could receive a source map for file content that differed from the original tool result after the file changed before routing."
root_cause: "The shared original_matches check recognized Claude's Read spelling but omitted Pi's lowercase read spelling, so Pi bypassed the pre-worker comparison."
resolution: "Include lowercase read in original_matches and pin both mismatched and matching Pi results with regression tests."
---

## Root cause

Pi emits `tool_name: read`; the post-read adapter forwards that name to the
shared CLI. The source-consistency comparison now includes both `Read` and
`read` (`scripts/context-read.py:342-346`). Before this fix, the lowercase name
returned `True` before comparing the original tool result to the file on disk.
A file modified between the native read and the hook could therefore produce a
map for content the main model had not actually read.

## Verification

`tests/context_read_cases.py:219-228` reproduces the mismatch: it passed a Pi
result from the original file after changing the file on disk. The test failed
before the fix because a map was delivered, then passed with a
`changed_source` metadata-only fallback and no worker call. A matching-source
Pi test and a fresh installed Pi 0.85.1 live stub run confirmed one replacement
without a retry or fallback. The focused 26-case suite and full 41-file suite
passed.

## Prevention

For cross-harness hook routing, test each host's actual tool-name spelling on
both the success path and any source-identity guard. A common read concept does
not imply a common event name.
