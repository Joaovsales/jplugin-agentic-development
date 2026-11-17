---
title: Parallel work serializes on the plugin version, the todo index and the GPU
date: 2026-11-16
problem_type: process
module: .claude-plugin/plugin.json, tasks/todo.md, local GPU
tags: [parallelism, merge-conflict, plugin-version, todo-index, gpu]
applies_when: planning how many PRs or workers to run at once, or diagnosing why parallel branches keep conflicting or failing
---

Three shared serialization points, all found in the 2026-11-15/16 session by
running into them:

1. **The plugin version line** (`.claude-plugin/plugin.json`, now `1.8.15`).
   Every payload PR must raise the version above its base's, so whichever
   payload PR merges second has to bump again. Payload PRs therefore merge
   one at a time (#417/#419: bump helper and a clearer guard message). See
   [the version guard reads origin/master](the-plugin-version-guard-is-only-as-current-as-origin-master-in-the-tree-that-runs-it.md).
2. **The `tasks/todo.md` index.** Every branch that files an issue or
   appends a session summary edits the end of this file, so open PRs
   conflict with each other. Open issue #381 tracks this. Resolve the
   conflicts by merging, never by rebasing.
3. **The GPU.** One fully offloaded Bonsai 27B v1 `Q1_0` server held 5,004 MiB
   of the 5,790 MiB free on the 6 GB RTX 3050 (`docs/bonsai-2-27b/eval/README.md`).
   A second model of the same class does not fit beside it (the session
   reported about 4.6 GiB per model). Concurrent GPU work must queue.

**Rule.** Before running work in parallel, count how many branches touch
each of these three points. Order payload PRs one after another. Expect
one merge per open PR on `tasks/todo.md`. Run GPU jobs one at a time.
