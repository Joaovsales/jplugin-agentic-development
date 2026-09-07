---
title: Logical text records must own their rewrite span
date: 2026-09-06
problem_type: pattern
module: text-backed registries and indexes
tags: [logical-records, multiline-parsing, span-ownership, lossless-rewrite]
applies_when: A parser combines multiple physical lines into one record that later code can canonicalize or replace
---

Parsing a multi-line record and rewriting only its first physical line leaves the
old continuation behind. The next read can then duplicate detail or associate
orphaned prose with the wrong record.

Make the parsed record own an explicit source span and let canonical replacement
consume that complete span. If a separate operation intentionally edits only the
header, expose that distinction in the interface rather than teaching callers
which line offsets are safe. Task registry rows follow this split through
`IndexRow.end_line`, `TaskIndex.replace_row`, and `TaskIndex.replace_line`
(`.agents/skills/task-registry/scripts/registry/index.py:80-86` and
`.agents/skills/task-registry/scripts/registry/index.py:200-221`).

Cross-link: [Consume structured records before rendering human summaries](consume-structured-records-before-rendering-human-summaries.md).
