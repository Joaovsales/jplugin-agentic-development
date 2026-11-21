---
title: Atomic replace does not serialize ledger writers
date: 2026-11-19
problem_type: bug
module: .agents/skills/build/scripts/run_ledger.py
tags: [run-ledger, concurrency, atomic-write, final-decision]
symptoms: Concurrent record and decide calls erased a merged result; concurrent decide calls could replace a final result
root_cause: Atomic replacement protected file completeness while each command checked and modified an unprotected stale snapshot
resolution: Hold the same per-run OS lock across load, validation, finality checks and atomic replacement in both commands
---

PR #456's review reproduced both races with a writer paused immediately after
the real read. Locking only the write would still publish that stale snapshot.
`run_lock` owns the full transaction and uses kernel ownership, so a crashed
process releases its lock without age-based stale-lock deletion
(`.agents/skills/build/scripts/run_ledger.py:205`). Never unlink the persistent
lock file: a waiter could still hold the old inode while a new arrival locks
its replacement.

`tests/run-ledger-regressions.py` pins record-vs-decide and decide-vs-decide
with two actual processes and an observed contended lock attempt, and checks
bounded waiting and recovery after killing a lock owner.

Related: [crashed atomic-write temp files](a-pathlib-glob-reads-a-crashed-writes-dot-temp-as-a-record.md)
concerns record discovery rather than transaction ownership.
