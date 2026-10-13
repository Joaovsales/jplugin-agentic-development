---
title: A PR merged by the GitHub Actions app did not close its correctly linked issue
date: 2026-09-16
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/closure.py; .agents/skills/task-registry/scripts/registry/providers/github.py; .agents/skills/task-registry/scripts/registry/routines.py; .agents/skills/wrap-up-session/references/routines.md § Issue closure happens on merge; downstream auto-merge workflows
tags: [github, issue-linkage, auto-close, github-actions, github-token, routines, task-registry]
symptoms: image-video-generation-pipeline PR #141 merged into `main` with a literal `Closes #91` and GitHub listed the link, yet #91 stayed open for three hours until closed by hand
root_cause: GitHub does not fire closing keywords for a merge made with a workflow's `GITHUB_TOKEN` (the `github-actions` app), and granting that token `issues: write` does not restore it. The routines contract promised the tracker closes the issue on merge, and nothing checked the promise after a bot merge
resolution: In progress. `task-registry closes '#<pr>'` reads a merged PR's closing references and closes each still-open issue through the registry's gated `close_task`, or exits 1 naming every one it could not close. The routines contract tells any `GITHUB_TOKEN` merger to run it after the merge call. As a backstop, `select` never offers an open issue whose closing PR merged, and names each one in a `stranded:` line that carries the `closes` command
---

**Status**: in progress — issue #146
**Regression test**: tests/test-task-closes.sh § command, § select

## Evidence

The merger-identity hypothesis was confirmed by a natural experiment recorded on
2026-10-13, not by a new controlled merge. Its basis is GitHub's own records
(evidence level 2). The search covered every merged PR with closing references
in three of the owner's repositories (`image-video-generation-pipeline`,
`pix-receipt-extractor-application`, `private-knowledge-base`) since 2026-07-13,
when their auto-merge workflows were added. For each linked issue, the last
`ClosedEvent`'s `closer` was read:

| Merger | Linked issues | Closed by the merging PR (`closer` = the PR) |
|---|---|---|
| a person | 103 | 102. The exception, `jplugin-agentic-development` #103, was closed by hand a minute before its PR merged |
| `github-actions` (`GITHUB_TOKEN`) | 47 | 0 |

The original pair, read on 2026-09-16:

| | PR #140 (control) | PR #141 (failure) |
|---|---|---|
| head | `routine/fix/92-…` | `routine/improve/91-…` |
| base | `main` (default) | `main` (default) |
| body | `Closes #92`, never edited | `Closes #91`, last edited 11 h before merge |
| `closingIssuesReferences` | `[92]` | `[91]` |
| merged by | `Joaovsales` | `github-actions` (scheduled `auto-merge.yml`, `gh pr merge --squash`) |
| issue close event | 2 s after merge, actor = the merger | none; manual close 3 h later |

## Alternatives ruled out

- **Missing `issues` permission on the token.** The human control's close event
  is recorded as the merger's, which suggested GitHub closes the issue as the
  merger and silently fails without write access. The image-video workflow's
  `permissions:` block grants `contents` and `pull-requests` only. But
  `pix-receipt-extractor-application` added `issues: write` on 2026-10-08
  (3ce3d5c). Its PR #532 then merged at 13:58:36 on 2026-10-09, and #472 was
  still open at 13:58:40, when the workflow's explicit close step commented on
  it. Human merges close within 2 s, and #472's only `ClosedEvent` has no
  `closer`. The permission is necessary for a workflow to close the issue
  itself, but it does not bring back the keyword close.
- **Malformed linkage on the PR.** All 47 bot-merged links appear in
  `closingIssuesReferences`, across many authors, keyword forms and PR bodies.
  The split follows the merger and nothing else.

## Resolution

This repository's `/wrap-up-session` opens the PR and ends. Merge happens in
the downstream repository's automation, the only actor that can observe
"merged, issue still open". The routines contract keeps `gh issue` out of every
skill except `/task-registry` (category-routines AC11), so the repair is a
registry command the downstream workflow calls after its merge call:
`task-registry closes '#<pr>' --apply --approve`. The workflow's token then needs
`issues: write`. `pix-receipt-extractor-application` already closes the
references inline in its workflow. `image-video-generation-pipeline` and
`private-knowledge-base` did not as of 2026-10-13. Issues still open there after
a bot merge: image-video #94, #101, #155, #156; private-knowledge-base #86;
pix #357, #493 (merged before its fix).

### The `select` backstop

A merger that skips `closes` would leave the issue for `select` to offer again,
and the next routine run would redo merged work. Building the backstop exposed
a second gap. `gh issue list --json closedByPullRequestsReferences` lists each
linked PR's id, number and URL, but never its state (checked against gh 2.76.2 on
2026-10-13). `_linked_pr_state` read a `state` that never arrives, so every
linked issue counted as in flight. Stranded issues were hidden for good rather
than re-picked, and so was an issue whose PR closed unmerged. The provider now
reads the states with one `gh api graphql` `nodes(ids:)` call per 100 PRs. A
PR whose state cannot be read still counts as in flight. An open issue with a
merged closing PR, nothing else in flight and a `stateReason` other than
`REOPENED` is marked `merged_linked_pr`. A live read on 2026-10-13 named exactly
the stranded issues listed above: image-video #94, #101, #155, #156 and
private-knowledge-base #86.

Origin: second and third comments on issue #123. The first symptom in that
issue is fixed and recorded in [[closing-keyword-binds-to-one-issue-reference]].
