---
title: A precondition that fires after the act it guards reports nothing
date: 2026-09-05
problem_type: process
module: .agents/skills/sync/scripts/sync-retire.py
tags: [ordering, error-handling, data-loss, preconditions, sync]
applies_when: a destructive step and a validation both live in one function
---

## The rule

Order a precondition before the irreversible step it guards, not merely before
the step that *reports* it. A check that raises after the deletion has already
happened discards the record of what was destroyed — and the operator is shown
an error about the thing that did not happen instead of the thing that did.

Nothing may fail between an irreversible act and the report of that act.

## What happened

Bootstrap `--apply` ran `apply_plan` (deletes) and then `write_candidate`, which
refuses to overwrite an existing `.claude/sync-keep.candidate`. So the ordinary
state "a candidate was generated last run and not yet promoted" deleted files,
then raised, and the raise unwound past the accounting that held `removed`. The
run exited 1 having destroyed a skill, printed no `deleted:` line, and the exit
table told the reader that this exit code deleted nothing.

The fix was not a `try`/`finally`. It was extracting the precondition
(`assert_candidate_writable`) and calling it *first*, so the failure mode became
"exits 1, changed nothing" — which is what the documentation already claimed.

## Why it kept recurring

This was the fourth instance of one defect in one file, and each earlier fix was
applied at the call site that had been caught: the `os.remove` loop, then
`os.rmdir`, then `os.listdir`, then this ordering. Each fix was correct and none
generalised, so every new call site reintroduced it.

The generalising question is not "does this call site handle its error?" but
"what is the irreversible act here, and can anything fail after it?" See
[[an-assertion-can-pass-because-a-different-guard-fired]] for the companion
failure — a test that looked like it covered this and did not.
