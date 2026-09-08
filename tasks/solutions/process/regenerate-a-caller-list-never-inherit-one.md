---
title: Regenerate a caller list before a deletion cut, never inherit one
date: 2026-09-08
problem_type: process
module: specs/workflow-routing.md, tasks/handover-workflow-routing.md, task-registry deletion cuts
tags: [deletion, callers, grep, stale-documentation, handover]
applies_when: a plan, spec, or handover hands you a table of the callers a deletion must repoint
---

## The rule

A caller list is a **measurement**, and it decays the moment anything moves. Treat
one written by an earlier session — even one written by you, even one carrying
line numbers — as a hint about where to look, never as the set to work from.
Regenerate it with `grep` against the current tree before the first deletion, and
diff the regenerated list against the inherited one. The delta is the finding.

## What happened — three occurrences, escalating cost

**Phase A.** Two hand-surveys of `reconcile`/`publish` callers each missed
entries; the second missed `plan/SKILL.md:200`, five lines below the `:195` it had
just cited correctly.

**Cut 1 (2026-09-07).** The handover listed the Jira surface as 3 files. It was
17.

**Cut 2 (2026-09-08).** The spec's caller table had 10 rows. The regenerated list
had 12, and *every* line number in the inherited 10 had moved. The two extra rows
were not cosmetic:

- `specs/wrap-up-gate-and-tdd-fold.md:173` — a **shipped, checked** acceptance
  criterion requiring `session-start.sh` to print the debt banner with a
  `/task-registry` invocation naming a command this cut deletes.
- `tests/test-pre-push-gate.sh:226` — that AC pinned **live**, so the miss would
  have shipped a green suite asserting a banner that names a deleted command.

## Why the inherited list is always wrong

Three independent decay paths, and a cut hits all three:

1. **Line numbers move** — any edit above a citation invalidates it, and nothing
   in the repo re-derives it.
2. **Surfaces are added between sessions** — the survey is a snapshot of a tree
   that has since grown callers.
3. **Non-code callers are under-counted** — a hand survey looks at imports. Specs,
   acceptance criteria, banner strings, and test needles reference a command by
   *name*, so they never appear in an import graph and are exactly what a
   deletion breaks silently.

Path 3 is the expensive one. A missed import fails at run time; a missed spec
assertion ships.

## How to apply

- Grep for the **bare name**, not the import: `grep -rn '\breconcile\b'` across
  `specs/`, `tests/`, `*.md`, and hooks — not just `from .reconcile import`.
- Diff regenerated against inherited and **explain every delta** before deleting.
  A row that vanished means something already moved; a row that appeared means the
  plan under-scoped.
- In a repo with living-spec reconciliation, a spec asserting a deleted command
  does not sit dormant — `/wrap-up-session` reconciles specs actively, so the
  stale assertion *fires*. Search specs first, not last.
- Record the regenerated list back into the spec, replacing the inherited table.
  Leaving both is how a fourth occurrence starts.

Related: [[a-skill-may-not-name-a-path-sync-does-not-deliver]],
[[construct-retired-paths-at-runtime-to-keep-literal-sweeps-strict]]
