---
title: A single Closes before a comma list closes only the first issue
date: 2026-09-16
problem_type: bug
module: .agents/skills/wrap-up-session/SKILL.md, .agents/skills/wrap-up-session/scripts/pr_linkage.py
tags: [wrap-up-session, pull-request, issue-linkage, github, silent-failure]
symptoms: PR #121 merged with `Closes #99, #100, #101, #102, #103`; only #99 closed, the other four stayed open until closed by hand
root_cause: GitHub binds a closing keyword to the one reference immediately after it; the wrap-up skill documented only the singular `Closes #N` and nothing inspected the body before the write
resolution: The skill states the per-issue form and names the failing one; `pr_linkage.py check` runs on the draft before create and on the fetched body during every re-sync, listing every reference a keyword does not reach, exit 3
---

**Status**: fixed — 2026-09-16
**Regression test**: tests/test-pr-linkage.sh (script + CLI); the multi-issue prose pins in tests/test-routine-wrapup.sh

## Reproduction

`gh pr view 121 --json closingIssuesReferences,body` on this repository returns
`closingIssuesReferences=[99]` for the body line
`Closes #99, #100, #101, #102, #103`. The issue timelines show #99 closed two
seconds after the merge and #100–#103 closed by a human six minutes later.

Evidence level 2 (primary artifact: GitHub's own linkage record) for the
mechanism, level 1 for the repository defect: a grep of the wrap-up skill and of
`tests/test-routine-wrapup.sh` and `tests/test-routines-contract.sh` found only
the literal singular `Closes #N`, and the new assertions failed before the fix.

## Root cause and alternatives

- `.agents/skills/wrap-up-session/SKILL.md` § *Draft, and issue linkage* gave
  `Closes #N` in the singular for every routine row and "whatever the session
  warrants" for a human branch. § *Creating and re-syncing* reconciled factual
  claims in the body but never inspected keyword linkage. A malformed list
  therefore passed every gate and failed only after merge, where nothing reports
  it: the PR merges, the issues stay open, `gh pr checks` has no state for it.
- Ruled out: GitHub accepting comma lists and PR #121 failing for another
  reason. The PR's base was `master`, the default branch, and GitHub linked
  exactly one of five references.
- Ruled out as cause: the routine branch parser allowing one issue per branch.
  PR #121 came from a human branch outside `routine/`, so the routine guard was
  never in scope. The single-issue design is why no guard existed, not why the
  list failed.

## Resolution and verification

- The skill states the working form `Closes #A, closes #B` directly after the
  linkage table and names the failing form and what it silently drops.
- New `.agents/skills/wrap-up-session/scripts/pr_linkage.py` (mirrored to
  `.claude/`) exposes `orphaned_references(body)` and a `check` command. Exit 0
  prints nothing; exit 3 prints one orphaned reference per line. Three is
  deliberate: 1 is a crash and 2 is argparse's usage error, so neither can be
  mistaken for a finding, the same reasoning as `routine_branch.py`'s exit 3.
  The chain detector accepts every reference form GitHub binds (`#N`,
  `owner/repo#N`, `GH-N`, issue URLs) and every list separator people write
  (comma, semicolon, ampersand, slash, whitespace, line breaks onto bullets,
  `and`, `also`); prose between two references ends the chain, and code spans
  are ignored because GitHub does not autolink inside them.
- § *Creating and re-syncing* runs the check on the draft before `gh pr create`
  and on the fetched body of an already-open PR **whether or not anything else
  looks stale**, so a PR opened before this fix is caught on its next re-sync
  instead of taking the "already accurate" path. The Done report's `PR:` line
  gained a `linkage repaired — <refs>` alternative so a repair is visible.
- Wrap-up review (four dispatched passes) widened the separator set, moved the
  exit code off argparse's 2, made the re-sync check unconditional, and pinned
  both paths and the Done-report wording in tests.

Targeted files green after the fix: test-pr-linkage (14), test-routine-wrapup
(71), test-skill-parity (98), test-routines-contract (71), test-routine-branch
(21), test-skill-references (192), test-doc-conventions, test-solutions-schema
(31).

Full suite on Windows Git Bash: 35 of 43 files green. The eight failing files
(install-sh, routine-selectors, routine-skills, skill-invocation-chain,
sync-retirement, task-registry, task-escalation, verification-skill-integration)
fail with the identical assertion set on a clean `origin/master` export run
sequentially on the same machine, so they are the pre-existing Windows failures
tracked by issue #129, not regressions. Linux CI is the authority for those.

Related, not fixed here: [[bot-merged-pr-leaves-linked-issue-open]] — the same
issue's second comment, where a correctly linked single `Closes` did not close
on a merge performed by the GitHub Actions app.

Prevention: a rule that only lives in prose fails silently when it is dropped.
Pin the prose in a test and put the check in front of the irreversible write.
