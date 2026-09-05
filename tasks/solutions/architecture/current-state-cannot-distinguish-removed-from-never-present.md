---
title: Current state cannot distinguish removed-upstream from never-present
date: 2026-09-04
problem_type: architecture-decision
module: .agents/skills/sync/scripts/sync-retire.py
tags: [provenance, git-history, set-arithmetic, sync, determinism]
applies_when: computing a difference between two trees where one side's absences carry two different meanings
---

## The rule

`A − B` tells you a path is in A and not in B. It cannot tell you *why*. When the
two reasons demand opposite actions, the current state of B is not enough
information, and no amount of care with the subtraction will recover it. Reach for
B's history, which is a record, not a judgement.

## How it showed up

`/sync` retirement computed `project − template`. A path in that set is either
retired upstream (delete it) or project-specific (keep it) — opposite actions from
one subtraction. The original design resolved this by requiring the project to
record an allowlist first, and deleting nothing until it had.

That was correct but incomplete: a project that never recorded one kept every
retired file forever. The mechanism being replaced — a hardcoded
`for retired in tdd deslop simplify verify-e2e` loop — had deleted those
unconditionally, so the new design was *strictly weaker* for exactly the projects
least likely to notice.

## The fix

The template's git history answers the narrower question on its own:

```
retire (bootstrap) = (project − template) ∩ (paths the template has ever carried)
```

A path the template once shipped and no longer does was template content by
provenance. Verified end-to-end on a real clone: 5 retired paths removed in
bootstrap with no human classification, the project-local skill kept, and the
candidate holding only the path provenance could not settle.

## What generalises

- Provenance is **per-path, not per-name**. A retired skill sitting at a path the
  template never used has no provenance and stays a candidate. Conservative and
  correct — do not match on names.
- History must actually be present. A shallow clone's history *is* its current
  state, which would silently classify every retired path as project-specific.
  Detect it (`git rev-parse --is-shallow-repository`) and say "unknown" rather
  than concluding. `/sync` clones `--filter=blob:none` so the question stays
  answerable cheaply.
- "Unknown" needs to be a distinct third state from "yes" and "no", in the return
  type as well as the report.
