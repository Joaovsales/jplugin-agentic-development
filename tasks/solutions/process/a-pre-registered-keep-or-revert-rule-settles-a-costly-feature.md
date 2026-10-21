---
title: A keep-or-revert rule written into the spec before the eval settles a costly feature, and the revert is done by hand
date: 2026-10-21
problem_type: process
module: specs/ acceptance criteria with an /eval slice; /build of a feature with an experimental part
tags: [eval, decision, revert, spec, mode-b]
applies_when: a spec adds an expensive or speculative mechanism whose value is uncertain, or the eval of one comes back unfavourable
---

## The practice

`specs/aposd-first-build.md` AC17 fixed the thresholds before any run: keep design
mode when its AC coverage is at least the baseline's, its design findings are
fewer and its cost is at most 2×; otherwise recommend reverting slices 9 and 11.
D18 had already arranged the build so only those two slices depended on the
outcome. Round 2 (after a routing fix) gave equal AC coverage, no fewer findings
and 3.09× cost, so the rule said revert and the owner agreed (D23). The report is
`tasks/eval-aposd-first-build.md`.

## What it bought

- The decision was quick and did not turn into a debate about the numbers: the
  thresholds were not chosen after seeing the data.
- The experimental slices were isolated by plan order, so the rest of the build
  stood alone.

## What to expect when reverting

Later fix commits (freeze-rule fixes, the routing fix, doc-test pins) mixed the
feature into shared files, so `git revert` of the two feature commits would not
apply cleanly. The revert was done by hand in one commit: remove the feature, then
what it orphans (here `ready`'s `mode=`, the persona's Write job and the gate's
freeze inputs), and record in the spec what was withdrawn and what stays. Keep the
eval fixtures so the feature can be re-tested on a harder case.

Related: [a second skill path loses to the default](../patterns/a-second-skill-path-loses-to-the-default-unless-routed-first.md).
