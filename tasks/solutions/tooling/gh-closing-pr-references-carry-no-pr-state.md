---
title: gh lists an issue's closing pull requests without their state
date: 2026-10-13
problem_type: tooling
module: .agents/skills/task-registry/scripts/registry/providers/github.py § linked_pr_state, _closes_here
tags: [github, gh-cli, closedByPullRequestsReferences, linked-pr, rest-timeline, task-registry, select]
applies_when: code needs to know whether a pull request linked to an issue is open, merged or closed, and is tempted to read `closedByPullRequestsReferences` from `gh issue list` or `gh issue view`
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

## Where the state comes from now (#294)

**Correction, 2026-10-19.** The GraphQL `nodes(ids:)` read this document
described (#146's `_read_pr_states`) is gone: sandboxed runners answer the
GraphQL endpoint with HTTP 403 (`specs/github-rest-in-sandboxes.md`), and
`closedByPullRequestsReferences` is itself a GraphQL-backed field. The registry
no longer reads it at all. The state comes from the issue's REST timeline:

```bash
gh api 'repos/<owner>/<repo>/issues/<n>/timeline?per_page=100'
```

Each `cross-referenced` event whose `source.issue` carries a `pull_request` key
is a pull request that mentions the issue; the event's `source.issue` carries the
PR's `state` (lower-case `open`/`closed`), its `body`, its `repository_url`, and
`pull_request.merged_at` (null unless merged). An issue that mentions the issue
has no `pull_request` key and is skipped.

How the registry uses it:

- `linked_pr_state` (`github.py:131`) pages the timeline through `_paged` up to
  `TIMELINE_LIMIT` (300, `github.py:56`) and answers `None` when the timeline
  runs past it (`github.py:146`); `select` then refuses rather than guess.
- Only `cross-referenced` events with a `pull_request` source count
  (`github.py:152`). A PR whose `state` is missing counts as open.
- `unresolved_linked_pr` is `"true"` while any such PR is not `closed`; otherwise
  `merged_linked_pr` names the first PR with `merged_at` set whose
  `repository_url` is this repository and whose body closes the issue per
  `closing_references_in` (`github.py:161-166`), the same parser `closes '#N'`
  uses — skipped when the issue's `state_reason` is `reopened`
  (`github.py:158`).
- Only `select` pays for the read: `routines.py:160-175` folds the answer into
  `task.extra` after the kind and claim filters, so a repository's whole backlog
  is never paged. `closes`, `show` and `escalate` never depend on it.
- `state_reason` (REST, lower-case: `completed`, `not_planned`, `reopened`,
  `duplicate`) distinguishes an issue a human reopened from one a merge never
  closed.

When a fixture or stub models a `gh` field, copy the shape from a live read, not
from the GraphQL schema — and for the timeline, from a REST read: the mock's
event shape is
`{"event":"cross-referenced","source":{"type":"issue","issue":{"number":N,"state":"open","body":"Fixes #n","repository_url":"https://api.github.com/repos/<owner>/<repo>","pull_request":{"merged_at":null}}}}`
(`tests/fixtures/task-registry/gh`).

Related: [../bugs/bot-merged-pr-leaves-linked-issue-open.md](../bugs/bot-merged-pr-leaves-linked-issue-open.md)
