---
title: A repository-level flag does not describe a single revision inside it
date: 2026-09-05
problem_type: architecture-decision
module: .agents/skills/sync/scripts/sync-retire.py
tags: [git, provenance, shallow-clone, ci, sync]
applies_when: testing whether some history is deep enough to answer a question
---

## The rule

When the question is about one revision, measure that revision. Repository-wide
git flags (`--is-shallow-repository`, `core.bare`, `--is-inside-work-tree`)
describe the container, and a container can hold revisions with different
properties — most obviously after a `fetch` from a second remote.

## What happened

`template_history_paths` asked whether provenance was readable by running
`git rev-parse --is-shallow-repository`. In `--from-dir` mode that was roughly
right: the checkout *is* the template. In `--from-ref` mode — the mode the skill
actually prescribes — the template ref is fetched into the **project** repo, so
the flag answered "is the project a shallow clone?"

A project cloned with `--depth 1`, which is what CI does by default, therefore
reported `provenance: unavailable` and retired nothing, no matter how complete
the fetched template ref was. The feature silently no-opped in its recommended
mode, in exactly the environment least likely to have a human reading the output.

`git rev-list --count --max-count=2 <revision>` asks the question being asked, in
both modes, and removed the mode-dependent branch rather than adding one.

## The direction of the error matters

A truncated-but-not-single-commit history still misreports, but conservatively:
paths retired beyond the horizon fall out of the history set and are held as
candidates for a human. Unknown provenance must fail toward "ask", never toward
"delete" — and the repo-level flag failed toward "never delete anything at all",
which reads as safe and is how the no-op went unnoticed.

Related: [[current-state-cannot-distinguish-removed-from-never-present]].
