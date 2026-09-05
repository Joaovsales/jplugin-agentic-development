---
title: pkill -f matches the command line of the shell running it
date: 2026-09-05
problem_type: tooling
module: tests/
tags: [bash, process-management, self-inflicted, ci]
applies_when: killing stray processes by command-line pattern from inside a script
---

## The rule

`pkill -f <pattern>` matches full command lines, including the command line of
the shell executing the `pkill`. If the pattern appears anywhere in the invoking
script's own argv — which it does whenever the script was passed inline with
`bash -c` — the script kills itself.

Symptom: the command dies with no output and an exit code of 128 + signal
(`143` for SIGTERM, or a stranger number when the harness re-signals).

## What happened

Two hung test processes needed clearing, so the next command started with
`pkill -f "tests/test-"`. That string was also in the inline script's own argv,
so it terminated its own shell before running anything — twice, costing about
twenty minutes and producing a confusing `exit 144` each time.

## What to do instead

Kill by PID from a prior `ps` (`kill 12345`), or exclude self explicitly:

```bash
pkill -f --older 60 "pattern"     # only long-running matches
pgrep -f "pattern" | grep -v $$ | xargs -r kill
```

## The adjacent lesson

The hang itself was also self-inflicted: the sweep ran the whole suite three
times over, and `tests/run.sh` is itself the runner, so two concurrent instances
of a test that installs git hooks deadlocked on a shared lock. Run the project's
own entry point once rather than iterating `tests/*.sh` — the glob includes the
runner.
