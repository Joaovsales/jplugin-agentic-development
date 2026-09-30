---
title: A new default selector label must reach every GitHub label fixture
date: 2026-09-29
problem_type: process
module: tests/test-routine-selectors.sh, tests/test-task-registry.sh; registry/config.py DEFAULT_KIND_PRECEDENCE
tags: [routines, selectors, fixtures, windows, wsl]
applies_when: a change adds a label to DEFAULT_KIND_PRECEDENCE or a lane's `selects:` (a new consumer routine)
---

Every default selector label is checked upstream: `task-registry select` and
`workflow` exit 2 when the tracker lacks one. So adding `simplify` (specs/make-it-simpler.md)
broke each GitHub label fixture that spells out the full default vocabulary. That
includes `write_labels` lines whose label *order* differs from the rest
(`$F_WF_CLOSED`, `$F_WF_TRUNC` in test-routine-selectors.sh). It also includes
the `labels.json` heredocs in test-task-registry.sh (#124's selection fixture).

On Windows the damage is invisible. Both files are already in the failure
baseline, because the `gh` mock is unreachable from Python there. The new
failures landed under names that were already red, so a name-for-name `comm`
against the baseline showed nothing new. Under WSL Ubuntu (clean clone, `gh`
wrapper on PATH, see [a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md](a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md))
they showed as 11 failures across 2 files. Adding the label to the four
fixtures made both suites green: 40/40 affected and 61/61 full.

When adding a selector label, grep both files for every fixture that carries
`tech-debt`, whatever its order: `grep -n 'tech-debt' tests/test-routine-selectors.sh tests/test-task-registry.sh`.
Then add the label to each fixture meant to satisfy the upstream check, and
leave out the ones that test a deliberately missing label (`$F_MISSING`,
`$F_SEL_GAP`, `$F_WF_GAP`). Prove the result under WSL, never by the Windows
name diff.
