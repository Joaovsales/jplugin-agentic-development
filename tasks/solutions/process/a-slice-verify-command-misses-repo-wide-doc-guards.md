---
title: A slice's Verify command misses the repo-wide doc guards a new citation can break
date: 2026-10-06
problem_type: process
module: tests/test-citations.sh, tests/test-go-lanes.sh § AC3 host sweep; /build slice dispatch
tags: [build, slices, citations, go, doc-pins, affected-tests]
applies_when: a slice adds a `<file>` § *Heading* citation or mentions a skill by its slash name in skill prose, and its § Build Order Verify column names only the slice's own pin files
---

In the lane-plan-handover build, every slice passed the test files in its own
Verify column, but the affected-test run failed on two guards that no slice
listed:

- `tests/test-citations.sh` resolves every code-spanned `` `<path>.md` § *Heading* ``
  citation (`CITE`, tests/test-citations.sh:41) from the repository root. A
  short `` `wrap-up-session/references/routines.md` `` reads as "file not
  found". Write the full `.agents/skills/...` path. A bare, un-backticked
  `routines.md § *X*` is never checked at all, so it can rot silently.
- `tests/test-go-lanes.sh` sweeps `HOST_ROOTS` (tests/test-go-lanes.sh:145,
  which includes `.agents/skills/wrap-up-session/references` and the lanes)
  with `GO_INVOCATION` (tests/test-go-lanes.sh:144) and allows zero
  matches. Prose there that describes an interactive run cannot write `/go`.
  This session wrote "the `go` skill" instead.

Prevention: before closing a slice, run the affected-test command, not just
the Verify column. In this repository it is the declared
`bash tests/affected.sh --run <base>`, and it picks up both guards. When a
sub-agent writes citations, tell it to use the full path.
