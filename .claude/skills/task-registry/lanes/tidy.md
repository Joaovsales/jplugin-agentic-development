---
routine: producer
ends: ready PR carrying the session record and the Tier 0 repair commits
---
# Lane: tidy

Runs on a schedule, never on an issue. Lens: harness hygiene. Engine: the eight
`/tidy` checks over the harness surfaces, never product code. Files documentation
drift as `documentation` and structural drift as `task` + `tech-debt`; every
Tier 0 repair is its own commit on the routine branch.

1. `/tidy` — the bar to repair is Tier 0 (the correct text is fully determined by the tree); the bar to file is a finding the report names with its surface and remedy; `--report` never commits — **non-skippable**
2. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

## Reply

The session record path, the Tier 0 commits by check name, every issue filed
(or `Filed: none`), and the PR URL.
