---
title: Current state cannot distinguish removed-upstream from never-present
date: 2026-09-30
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

## The first fix, and its correction

The template's git history answers the narrower question on its own:

```
retire (bootstrap) = (project − template) ∩ (paths the template has ever carried)
```

History narrows the candidate set, but a path the template once shipped is not
proof that the project's current file came from the template. A project may
have written its own file at that path or edited a synced copy. The current
bootstrap compares the on-disk file's blob with blobs the template held at that
path (`.agents/skills/sync/scripts/sync-retire.py:338-349`,
`:352-397`, `:802-810`). The original path-only rule was corrected after the
initial end-to-end run; see [path membership is not proof of provenance](path-membership-is-not-proof-of-provenance.md).

## What generalises

- History is **per-path, not per-name**, and a matching content blob supplies
  the proof needed for automatic deletion. A retired skill sitting at a path
  the template never used stays a candidate.
- History must actually be present. A shallow clone's history *is* its current
  state, which would silently classify every retired path as project-specific.
  Check whether the fetched template revision's apparent roots have missing
  parents and say "unknown" when they do (`.agents/skills/sync/scripts/sync-retire.py:311-335`).
  The earlier repository-wide `--is-shallow-repository` check was replaced;
  see [a repository-level flag does not describe one revision](a-repository-level-flag-does-not-describe-one-revision.md).
- "Unknown" needs to be a distinct third state from "yes" and "no", in the return
  type as well as the report.
