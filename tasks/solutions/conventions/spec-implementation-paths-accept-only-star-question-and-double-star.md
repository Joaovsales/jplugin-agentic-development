---
title: Spec implementation_paths accept only *, ? and ** — expand brace groups per member
date: 2026-09-22
problem_type: convention
module: specs/*.md frontmatter · .agents/skills/task-registry/scripts/registry/globs.py
tags: [specs, glob, frontmatter, spec-reconcile, slice]
applies_when: Writing or editing the implementation_paths list in a spec's frontmatter, or when spec-reconcile.py or slice.py refuses with "unsupported glob syntax"
---

## Convention

`implementation_paths` entries are matched by `registry/globs.py`, which accepts
`*`, `?` and `**` and refuses every other glob character
(`.agents/skills/task-registry/scripts/registry/globs.py` § `_tokens`, error
`unsupported glob syntax ... — only *, ? and ** are accepted`). Brace groups
(`tests/{a,b}.sh`), character classes and extglob are not accepted, and the
refusal is a hard exit: `spec-reconcile.py discover` names the spec and the value
and stops without reporting any candidate, because a pattern that matches nothing
is indistinguishable from a spec nobody touched.

Write one entry per member instead:

```yaml
implementation_paths:
  - project-template/CLAUDE.md
  - project-template/AGENTS.md
  - .agents/skills/quality-gate/**
  - .agents/skills/wrap-up-session/**
```

The lists get long (this spec went from 27 to 56 entries) but stay greppable, and
`slice.py check` can count the expanded surface per slice, which a brace group
would hide.

## Why it surfaced

The spec was written before PR #176 introduced the shared matcher; the older
matcher in `spec-reconcile.py` was more permissive. Merging master after a long
build is when this class of tightened contract shows up — check the branch's own
specs against master's new validators, not only master's files against the
branch's retirements (see [[port-master-edits-onto-the-successor-surface-when-a-branch-retires-one]]).
