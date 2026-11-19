---
title: A pathlib glob reads a crashed write's dot-temp file as a record
date: 2026-11-19
problem_type: bug
module: .agents/skills/build/scripts/run_ledger.py
tags: [run-ledger, atomic-write, pathlib, glob]
symptoms: A temp file left in tasks/runs/ by an interrupted record made every later `run_ledger.py stats` exit 1 on an "unreadable record"
root_cause: The atomic write puts its temp file (`.tmp-*.json`) in the ledger directory, and `Path.glob("*.json")` matches dot-files, unlike a shell glob
resolution: load_ledger skips dot-files (a run id can never start with "."), and write_record removes its temp file when the write or rename fails — fixed — 2026-11-19
---

`/quality-gate` on #442 found it: an atomic temp-then-rename write keeps the
final record safe but leaves its temp behind on a crash. A reader that
expects `*.json` to mean "records only" then breaks on every later run.

The rule: when a writer puts temp files in the directory its reader globs,
make the two name spaces disjoint (here, record names cannot start with
`.`) and filter on that, rather than relying on the shell's dot-file
convention, which `pathlib` does not follow.

Pinned by `tests/test-run-ledger.sh` § stats, "a temp file a crashed write
left behind is not a record".
