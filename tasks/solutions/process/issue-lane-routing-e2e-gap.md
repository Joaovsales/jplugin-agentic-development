---
title: Record a formal E2E gap when no project verification surface exists
date: 2026-09-01
problem_type: process
module: issue-lane-routing wrap-up verification
tags: [e2e, verification, route, wrap-up]
applies_when: wrapping up user-facing workflow behavior in a repository with no project-local verification skill or browser-backed user surface
---

## The rule

Do not relabel unit, integration, or blinded evaluation evidence as formal E2E.
Record the missing verification surface, obtain explicit user acknowledgement
before committing, and recommend `/create-verification-skill` as the upgrade path.

## This session

Issue-lane routing was exercised by the full 29-file automated suite and a blinded
Mode A/Mode B evaluation. The repository had no `.agents/skills/verify-*` skill and
no browser-backed user surface, so `/verify --scope e2e` could not produce a formal
user-surface walkthrough. The user acknowledged that gap on 2026-09-01 before the
session proceeded to commit and push.

## How to close the gap

Run `/create-verification-skill` to define a project-owned verification surface,
then replay the route hook, materialization, runtime tripwire, and reviewer
finalization through that surface and record the walkthrough in `tasks/e2e-log.md`.

**Correction — 2026-09-06.** The `/route` skill this gap was recorded against no
longer exists: fb41c7a (#105) replaced it with the four category routines in
`.agents/skills/wrap-up-session/references/routines.md`, selected by label rather
than by a route hook. The gap itself still stands — the repository has no
project-local verification skill — but the replay target is now the routine
spine (select → claim → branch → routine step → review → PR), not the retired hook.
