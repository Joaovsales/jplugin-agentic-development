---
routine: producer
ends: ready, docs-only PR carrying the session record
---
# Lane: janitor

Runs on a schedule, never on an issue. Lens: bugs. Engine: the full test suite
plus `/maintain-verification-skill`'s full pass, whose live pass drives every
mapped feature under `/verify --scope e2e` rules. Files as `bug`; the PR body
carries `Refs #N` per filed issue, never `Closes`.

1. `/sweep --routine janitor` — read the backlog, run the engine, verify, file, write the session record. The bar to file is a reproduction **executed this run** (command, observed, expected) at confidence `75` or above; a failing or flaky test is filed with the test command as its reproduction — **non-skippable**
2. `/wrap-up-session` — review passes, tests, commit, push, and the pull request — **non-skippable**

## Reply

The session record path, every issue filed (or `Filed: none`), and the PR URL.
