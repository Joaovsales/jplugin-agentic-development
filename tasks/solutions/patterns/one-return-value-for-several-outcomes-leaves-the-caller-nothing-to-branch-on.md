---
title: One return value for several outcomes leaves the caller nothing to branch on
date: 2026-09-07
problem_type: pattern
module: .agents/skills/task-registry/scripts/registry/routines.py, .agents/skills/task-registry/scripts/task-registry.py
tags: [api-design, error-design, sentinel, exit-codes, aposd]
applies_when: a predicate returns a bare None/False/empty for situations that a caller must respond to differently
---

## The rule

A function that answers a question with one falsy value answers a *different*
question than the caller is asking. `select_routine()` returns `None` for five
situations — the issue carries no kind label, it carries one no routine selects,
it already carries the claim label, the routine is deferred, or the configuration
is broken. Every one of those wants a different response, and `None` supports
none of them.

Reusing the predicate as-is is what makes this cheap to get wrong: the function
is *correct* for its original caller. `select_routine` was written as a **filter**
(`select_candidates` only needs "is this mine, yes or no"), and a filter is
exactly the caller for which collapsing is free. The cost only appears when a
second caller needs to explain the answer.

Do not widen the predicate. Keep it, and give the explaining caller its own
resolution path built from the same parts.

## What happened

`task-registry workflow <ref>` (`specs/workflow-routing.md` R2) had to tell a
human *and* an unattended wrapper which of those five it was. It resolves the
routine from `matched_label()` + `routine_for_label()` rather than from
`select_routine()`, because `matched_label` reads precedence and ignores the
claim label — so a claimed issue still reports which routine holds it instead of
folding back into the `None`:

```python
matched = matched_label(task, config)
routine = routine_for_label(matched, config) if matched else None
```

`select_routine()` was left unchanged, and `select_candidates` still uses it.

## The exit-code half

Distinguishing in prose is half the job; an unattended caller branches on the
exit code. `workflow` splits them:

- **1** — the command ran and there is no routine to start: unknown reference,
  closed issue, or a tracker that did not answer. A wrapper retries or re-checks.
- **2** — a human must edit a file before this can work at all: a usage error, a
  contradictory `[routines]` block, or a selector label the tracker never
  created. A wrapper pages.

Sharing one non-zero code makes both responses wrong. This cost one deliberate
asymmetry: a `ConfigError` is exit 2 for `workflow` while every other command
keeps its single failure code, because the others predate the split.

**The first cut of this split was wrong, and review caught it.** It read "1 means
the reference does not exist; 2 means the tool is misconfigured", which sounds
symmetric and is not: a *tracker outage* is neither, and it landed on 2 — so a
transient GitHub blip paged a human at 03:00 for a condition no file edit could
clear. The question an exit code answers for a scheduler is not "did it fail" but
**"should I wake someone"**, and that is the axis to split on. `_upstream_verdict`
now returns a fault *kind* alongside the code, because the two callers that read
it want different answers and the code alone could not carry both.

An outcome that is an *answer* still exits 0 — deferred routine, untriaged issue,
already-claimed issue. Making them non-zero would page somebody every night the
backlog was merely tidy.

## Related

- [[a-declared-intent-with-a-broken-target-is-not-an-absent-one]] — the same
  conflation on the configuration side: declared-but-missing folded into absent.
- [[current-state-cannot-distinguish-removed-from-never-present]]
- [[a-null-probe-result-needs-a-control-run]] — "not checked" as a third state.
