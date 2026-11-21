---
routine: producer
ends: ready, docs-only PR carrying the session record
---
# Lane: workflow

Runs on a schedule, never on an issue — and the first run is by hand: schedule
it only after a manual run's findings were reviewed. Lens: agent workflow
efficiency and reliability. Engine: `workflow-incidence.py` over completed
sessions after a cursor, bounded to 50 sessions and a configured token budget,
reusing the transcript parser and the read-incidence row. Files reproduced
reliability defects as `bug`, proven waste as `task` + `tech-debt`, and a
tradeoff needing an owner as `decision`; the PR body carries `Refs #N` per
filed issue, never `Closes`.

1. `/sweep --routine workflow` — read the backlog, run the engine, verify, file, write the session record, then advance the cursor. The bar to file is a verbatim `file:line` or session/event anchor with its source digest, the four Finding Model axes at confidence `75` or above, never `NITPICK`, no boost for single-agent agreement; a repeat-pattern optimisation needs two distinct completed sessions and a claimed cost improvement needs `/eval` Mode C — **non-skippable**
2. `/wrap-up-session` — checks the quality receipt, tests, commit, push, and the pull request — **non-skippable**

## Reply

The session record path, the sessions examined and left unexamined, every
issue filed (or `Filed: none`), and the PR URL.
