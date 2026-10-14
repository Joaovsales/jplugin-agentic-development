---
title: gh lists an issue's closing pull requests without their state
date: 2026-10-13
problem_type: tooling
module: .agents/skills/task-registry/scripts/registry/providers/github.py § _read_pr_states, _linked_pr_state
tags: [github, gh-cli, closedByPullRequestsReferences, linked-pr, graphql, task-registry, select]
applies_when: code reads `closedByPullRequestsReferences` from `gh issue list` or `gh issue view` and needs to know whether a linked pull request is open, merged or closed
---

`gh issue list --json closedByPullRequestsReferences` and `gh issue view` return
each closing pull request's `id`, `number`, `url` and `repository`, but never
its `state`. This session checked that against gh 2.76.2 on 2026-10-13, with
live reads of `Joaovsales/image-video-generation-pipeline` #155 and #91.
A fixture such as `[{"state": "OPEN"}]` therefore models a field that does not
arrive.

Before #146 the in-flight exclusion read `reference.get("state")` and counted
every state other than MERGED or CLOSED as open. Against real `gh`, the state
was always the empty string, so every linked issue counted as in flight. Its
tests passed only because the fixtures supplied a `state`. In practice the
exclusion hid more than it should have:

- an issue whose PR had closed unmerged stayed hidden, though the contract
  makes it selectable;
- an issue its merged PR left open stayed hidden too, so no output ever
  showed it as stranded.

The states come from one GraphQL read, with the node ids passed as variables:

```bash
gh api graphql -f 'query=query($ids: [ID!]!) { nodes(ids: $ids) { ... on PullRequest { id state } } }' \
  -f 'ids[]=PR_kwDO…' -f 'ids[]=PR_kwDO…'
```

`nodes(ids:)` accepts at most 100 ids per call. An id that no longer resolves
comes back as a null node.

How the registry uses it:

- `_read_pr_states` batches the lookup (`github.py:373`, query at
  `github.py:66`).
- `_linked_pr_state` treats a state it could not read as open
  (`github.py:350`).
- Only `select`'s read pays for the lookup, through
  `list_tasks_with_linked_prs` (`github.py:131`, called at
  `task-registry.py:532`). `closes`, `show` and `escalate` never depend on it.
- `stateReason == "REOPENED"` distinguishes an issue a human reopened from one
  a merge never closed (`IssueStateReason` also has COMPLETED, NOT_PLANNED and
  DUPLICATE).

When a fixture or stub models a `gh` field, copy the shape from a live read, not
from the GraphQL schema.

Related: [../bugs/bot-merged-pr-leaves-linked-issue-open.md](../bugs/bot-merged-pr-leaves-linked-issue-open.md)
