---
title: A PR merged by the GitHub Actions app did not close its correctly linked issue
date: 2026-09-16
problem_type: bug
module: downstream merge automation; .agents/skills/wrap-up-session/references/routines.md § Issue closure happens on merge
tags: [github, issue-linkage, auto-close, github-actions, routines]
symptoms: image-video-generation-pipeline PR #141 merged into `main` with a literal `Closes #91` and GitHub listed the link, yet #91 stayed open for three hours until closed by hand
root_cause: Not proven. The only discriminator against the control (PR #140, same author, same repo, same base, same keyword form, auto-closed #92 in two seconds) is the merger — PR #141 was merged by `app/github-actions`, PR #140 by a human
resolution: Open. A post-merge closure check belongs in whatever performs the merge; this repository's wrap-up runs before merge and cannot observe it
---

**Status**: open
**Regression test**: none yet — the fix is downstream of this repository

## Evidence

Read on 2026-09-16 with `gh pr view` and `gh api .../issues/N/timeline`:

| | PR #140 (control) | PR #141 (failure) |
|---|---|---|
| head | `routine/fix/92-…` | `routine/improve/91-…` |
| base | `main` (default) | `main` (default) |
| body | `Closes #92` | `Closes #91` |
| `closingIssuesReferences` | `[92]` | `[91]` |
| merged by | `Joaovsales` | `app/github-actions` |
| issue close event | 2 s after merge | none; manual close 3 h later |

Evidence level 3: several independent facts converge on the merger identity
and nothing else differs. Not level 1 — no controlled reproduction was run.

## Why it is not fixed in this change

This repository's `/wrap-up-session` opens the PR and ends. Merge happens in
the downstream repository's automation, which is the only actor that can
observe "merged, issue still open". The routines contract deliberately keeps
`gh issue` out of every skill except `/task-registry` (category-routines AC11),
so any repair must go through the registry, not the wrap-up skill.

## Proposed next step

A registry-owned post-merge check: given a merged PR, read its
`closingIssuesReferences`, and for each still-open issue either close it through
the registry's approved write path or report the mismatch loudly. Wire it into
the downstream merge automation after the merge call. Verify the merger-identity
hypothesis first with one controlled merge by the Actions app.

Origin: second and third comments on issue #123. The first symptom in that
issue is fixed and recorded in [[closing-keyword-binds-to-one-issue-reference]].
