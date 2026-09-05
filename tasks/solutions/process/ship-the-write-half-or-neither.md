---
title: Ship both halves of a guard, or neither — a read-only guard reads as protection
date: 2026-09-05
problem_type: process
module: task-registry routines concurrency
tags: [concurrency, review, guards, claim-label, routines]
applies_when: a design states a runtime guarantee that depends on both a read and a write, and only the read is implemented
---

## The rule

A guard implemented as a read with no corresponding write is worse than no guard:
it appears in the config, in the docstrings, in the CLI output and in the contract
document, so every reader concludes the protection exists. Nothing fails. The
acceptance criteria all pass, because none of them covers the missing half.

Ship both halves, or strike the guarantee from the contract and record it deferred
alongside the rest.

## This session

`specs/category-routines.md` enumerated the registry's blast radius as "exactly
three reads and **one write**: ... the claim label under *Concurrency*". The three
reads shipped. The write did not. `claim_label` appeared in `Config`, in
`select_routine`'s skip check, in the shipped template, and in `select`'s output
line telling the caller to "write it before branching" — with no command that
could. `select_routine`'s exclusion could therefore only ever fire on a label a
human had applied by hand, leaving two overnight runs of one routine free to pick
the same issue and race on one branch.

All 14 acceptance criteria passed while the guarantee was absent. The adversarial
review pass found it by reading the spec's own blast-radius sentence against the
tree, not by reading the ACs.

## How it was closed

`task-registry claim <ref> --routine <name> --apply --approve` — idempotent,
refuses an issue whose winning kind label routes it to a different routine, and
goes through the same `WriteGate` as every other tracker write.

Two sibling failures had the same shape and were fixed with it: the upstream
vocabulary check lived only in `selectors`, a command nothing invokes, and the
`gh`-capability assertion the contract called "asserted once at routine start"
existed nowhere. Both now run inside `select`, which is the command a routine
actually executes.

See [[validate-in-the-loader-not-in-one-optional-command]] — the same defect one
layer down, and the reason to distrust "the check exists" without asking which
path reaches it. See also [[a-bidirectional-map-cannot-be-widened-for-one-direction]].
