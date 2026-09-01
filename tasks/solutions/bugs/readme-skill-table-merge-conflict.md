---
title: Resolve concurrent README skill-table insertions additively
date: 2026-09-01
problem_type: build-failure
module: README.md skill catalog
tags: [git, merge-conflict, documentation, skills]
symptoms: PR #84 was marked conflicting with master after PR #83 merged
root_cause: Both branches inserted different skill rows at the same README table anchor from a shared base, so Git could not infer their order
resolution: Merged master and retained both sets of rows, placing route after the autonomous workflow skills to match CLAUDE.md
---

**Status**: fixed — 2026-09-01
**Regression test**: `git merge-tree --write-tree HEAD origin/master` exits cleanly after the resolution commit

The controlled pre-fix reproduction named `README.md` as the sole content
conflict (evidence Level 1). Concurrent edits to the mirrored GitHub provider
and `CLAUDE.md` auto-merged, which disconfirmed semantic incompatibility or a
general stale-worktree problem. The resolved catalog preserves PR #83's
`/auto-push`, `/yolo`, and `/auto-improve` rows alongside PR #84's `/route` row
at `README.md:268`.
