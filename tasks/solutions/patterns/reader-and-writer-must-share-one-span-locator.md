---
title: Reader and writer must share one span locator
date: 2026-09-15
problem_type: pattern
module: text-backed registries, managed blocks inside human-edited documents
tags: [managed-block, span-ownership, parser-writer-symmetry, stray-marker]
applies_when: A tool owns a delimited region inside a document humans also edit, and one function finds the region to rewrite it while another finds it to read it
---

When a tool manages a marked region inside text a human can also edit, the
question "which span is ours?" has to be answered once. The writer's answer is
already a contract: it decides which of several candidate markers is the real
block, and how an unfinished one is treated, because a wrong answer deletes prose.
A reader that re-derives the span with its own heuristic will disagree on exactly
the inputs the writer's rules exist for — a quoted marker, an interrupted write —
and then reports fields the writer never produced and would preserve on the next
rewrite.

Expose the locator as the single source for both directions: the reader parses
`body[start:end]` from the same bounds the writer replaces, and "no complete
block" means empty metadata, not "everything after the first marker".

Then name the states the rule produces. A shared locator still has to *apply* a
rule when markers are ambiguous, and the party that loses — the quoted pair, the
broken block — loses silently unless the classification is a value the readers
report and the writers refuse on. "Absent" is recoverable; "damaged" (markers
but no complete pair) is not, and a writer that appends over it replaces the
record with blanks.

Two cheap checks make the symmetry visible in tests:

- A phantom field placed in a stray marker must be **absent** from the real
  block, or a later real line overwrites it and the test passes either way.
- Assert the writer's rewrite and the reader's parse agree on one body that has
  a stray marker on both sides of the real block.

Instance: `parse_metadata_block` and `upsert_metadata_block` in
`.agents/skills/task-registry/scripts/registry/model.py`, and `_unmanaged_regions`
in `registry/providers/local.py`, unified in #132 through the public
`metadata_bounds`. The third locator was only found in review — count the
locators before declaring the span question answered once. Cross-link:
[Logical text records must own their rewrite span](logical-text-records-must-own-their-rewrite-span.md),
[Metadata parser read a different span than the writer owned](../bugs/metadata-parser-read-a-different-span-than-the-writer-owned.md).
