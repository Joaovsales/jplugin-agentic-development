---
title: Metadata reader and writer select different marker pairs
date: 2026-09-12
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/model.py
tags: [task-registry, metadata, parsing, preservation]
symptoms: Stray metadata markers inject phantom task fields into local and GitHub reads
root_cause: Reader splits on the first BEGIN while writer selects the last complete innermost pair
resolution: Open issue 132; production fix deferred, isolated coding runs establish a candidate approach
---

## Status

Open — [#132](https://github.com/Joaovsales/jplugin-agentic-development/issues/132).

`parse_metadata_block` uses the first BEGIN and accepts content without an END
(`.agents/skills/task-registry/scripts/registry/model.py:255-256`). The writer's
`_metadata_bounds` selects a complete innermost pair (same file, lines 298–314).
A leading incomplete example containing `parent: phantom` therefore leaks that
field into a later real task block.

## Evidence and proposed correction

The retained check set at `tasks/eval-results/bulk-read-context/held-out-checks.py`
fails 7 of 14 cases against the unchanged package, including parser selection
and local/GitHub consumers. Isolated coding runs reuse the existing bounds
helper and pass those cases; those implementations are evaluation artifacts,
not a production fix. Add permanent regression coverage and update both skill
trees when implementing #132.
