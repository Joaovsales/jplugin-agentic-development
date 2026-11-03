---
title: slice.py check reports sibling slices' files as undeclared in a parallel build
date: 2026-10-06
problem_type: tooling
module: .agents/skills/slice/scripts/slice.py § cmd_check
tags: [slice, surface-check, parallel-dispatch, build]
applies_when: several slices are built from one base, in parallel or before any slice's own commit range is known, and `slice.py check --base <build base>` is run per slice
---

`slice.py check` compares the whole `git diff --name-only <base>..HEAD`
(.agents/skills/slice/scripts/slice.py:482) against one slice's Surface. When
the build dispatched slices in parallel, every slice's report lists the other
slices' files as `undeclared:`. That is noise, not a surface violation. In the
lane-plan-handover build, all five slices printed this.

To read the real signal, commit each slice separately and check each commit's
files against that slice's Surface: pass the commit's parent as `--base` and
check with that commit at HEAD, or list the commit with `git show
--name-only`. Record the outcome in the slice's `> Surface:` handover line.
The report is informational and never blocks (/build § Slice Close).
