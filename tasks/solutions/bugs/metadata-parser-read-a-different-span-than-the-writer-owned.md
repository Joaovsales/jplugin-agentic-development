---
title: Metadata parser read a different span than the writer owned
date: 2026-09-15
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/model.py
tags: [task-registry, metadata-block, parser, stray-marker, phantom-dependency]
symptoms: A stray or unfinished `<!-- task-registry:begin -->` marker in a task body injected a phantom `parent:` or `depends-on:` into every local and GitHub read, and an unfinished-only body read as a real block
root_cause: parse_metadata_block split on the FIRST begin marker and kept everything after it when the end marker was missing, and the local provider's prose scan flipped a flag on the first begin marker, while upsert_metadata_block located the last complete innermost pair through metadata_bounds — three locators for one span
resolution: parse_metadata_block and the local provider's _unmanaged_regions both take the span from the now-public metadata_bounds; metadata_block_state names stray, competing, and damaged bodies so readers note them and writers refuse a damaged or competing one
---

**Status**: fixed — 2026-09-15
**Regression test**: `tests/test-task-registry.sh` § 12 — "the parser reads the span the writer owns (#132)"

## Reproduction (Level 1)

```
PYTHONPATH=.agents/skills/task-registry/scripts python3 -c 'from registry.model import *; print(parse_metadata_block(METADATA_BEGIN + "\nparent: phantom\n" + render_metadata_block(Task("real.task", "Real task"))))'
```

Before: `{'parent': 'phantom', 'task-id': 'real.task', 'kind': 'task'}`.
After: `{'task-id': 'real.task', 'kind': 'task'}`.

## Investigation

Three candidates were listed before any edit:

1. **Parser and writer use different locators** — confirmed. The parser (pre-fix
   `registry/model.py:255-256`) split on the first BEGIN and, absent an END, kept the
   rest of the body. The writer delegated to what is now `metadata_bounds`
   (`model.py:306-327`), which walks BEGIN positions backwards and returns the
   first complete pair with no BEGIN inside it.
2. **The writer emits a nested or duplicate marker** — ruled out by reading
   `render_metadata_block` (`model.py:234-248`): exactly one BEGIN and one END.
3. **A caller pre-selects a region** — ruled out: `providers/local.py:193`,
   `providers/local.py:269` and `model.py:369` all pass the whole body in.

## A subtlety the first test fixture missed

The leak only shows when the **real block lacks the phantom field**. The old parser
read both the stray lines and the real lines in one pass, and a later `parent:` line
overwrote an earlier one, so a fixture whose real block carried its own `parent`
passed before the fix. The regression fixture therefore renders a task with no
parent and no dependencies, exactly like the issue's reproduction.

## The third locator, found in review

The consistency review pass found that `_unmanaged_regions` in
`providers/local.py` located the block a third way: a flag flipped on the first
line containing BEGIN and cleared on the next END. With a quoted marker above the
real block, every human line between them was classed as metadata and dropped on
the next `update_task`. That scan now takes its span from `metadata_bounds` too,
and scenario 8 of the regression block rewrites next to a quoted marker and
asserts the prose survives.

## A damaged record is not an absent one, found in review

The defensive-audit and critic passes showed that "no complete pair reads as
empty" had a destructive corner and a silent one. Destructive: a block whose END
a human deleted used to be read field by field, so the next local rewrite kept
the fields; read as `{}`, `_merged_with_existing` rebuilt the block from blanks and
the GitHub path re-minted a title slug and appended a competing block. Silent: a
complete pair a human quotes *after* the real block is, by the shared rule, the
one read, and nothing said so.

`metadata_block_state` now names five states — absent, intact, stray-markers,
competing-blocks, damaged. Both providers note every state but the first two
through their limitation channel (surfaced under `limitations:` by `show`);
`upsert_metadata_block` and `LocalMarkdownProvider.update_task` refuse to rewrite
over a damaged or competing body, reading the reasons from one map. Which pair
is read did not change; a write that would have to guess is refused instead.
The round-2 recheck is what made competing its own state: with only the chosen
span dropped from the local prose scan, a rewrite over a quoted complete pair
leaked the real block's field lines into prose and downgraded the record.

## Why it mattered

`task_from_metadata` feeds the GitHub reader and `LocalMarkdownProvider._read` the
local one. Both took `parent` and `depends-on` straight from the parsed dict, so a
human quoting the marker format in an issue body, or a write interrupted before END,
produced a task whose hierarchy and dependency graph the registry then reported as
fact, and `_merged_with_existing` (`providers/local.py:269`) would carry the phantom
values into the next write.

Related: [Reader and writer must share one span locator](../patterns/reader-and-writer-must-share-one-span-locator.md),
[Logical text records must own their rewrite span](../patterns/logical-text-records-must-own-their-rewrite-span.md).
