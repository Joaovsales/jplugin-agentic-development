---
title: Agent isolation worktrees start from master, not the session branch
date: 2026-10-16
problem_type: tooling
module: /build § Parallel Dispatch Assessment; Agent tool `isolation: "worktree"`
tags: [build, parallel-dispatch, worktree, isolation, sub-agent, cherry-pick]
applies_when: /build dispatches slice agents with `isolation: "worktree"` from a feature branch, and a later slice depends on commits that exist only on that branch
---

## Agent isolation worktrees start from master, not the session branch

**Claim** (this session observed, 2026-10-16, HyperFrames build): the Agent
tool's `isolation: "worktree"` cut both slice-1 and slice-2 worktrees from
master's tip (`080484d`), not from the session branch's HEAD (`59e1d4c`, two
commits ahead with the spec and plan). Each agent reported that
`specs/design-stack-hyperframes.md` was absent from its tree and read it from the
orchestrator's worktree path instead; their commits had master as parent.

**Rule**:
- Commit plan artifacts before dispatching, and still expect an isolated agent not
  to see them — name the spec by the orchestrator's absolute path in the prompt.
- Integrate isolated agents' work with `git cherry-pick <sha>` onto the session
  branch (the ready set's slices are disjoint by construction, so the picks are
  clean); a merge would carry master's parent chain instead.
- A slice with `blocked-by` needs its blockers' code: dispatch it **without**
  isolation into the session worktree by absolute path (one writer at a time), or
  tell the agent to cherry-pick the branch's commits first.
- The agent's `.output` transcript file in the scratchpad stayed 0 bytes for the
  whole run, so a stall monitor on it fires false alarms; watch the agent
  worktree's file mtimes or its `git log -1 --format=%ct` instead
  (`.agents/skills/build/references/subagent-resilience.md` asks for a stall monitor).

**Consequence of ignoring it**: a dependent slice builds against stale code and
re-derives or contradicts its blockers' handover; a merge pulls an unrelated base
into the feature branch.

Related: [check-git-worktree-list-before-declaring-a-prerequisite-miss](../patterns/check-git-worktree-list-before-declaring-a-prerequisite-miss.md),
[slice-check-reports-sibling-slices-in-a-parallel-build](slice-check-reports-sibling-slices-in-a-parallel-build.md).
