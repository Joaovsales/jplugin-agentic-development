---
name: create-verification-skill
description: Generate a project-local verification skill that drives the real app through its user surface. Use when a repository has no grounded way to prove UI, CLI, desktop, API, mobile, or library behavior.
argument-hint: "[application or surface]"
disable-model-invocation: false
harness: universal
---

# /create-verification-skill — Create a project verification skill

## Overview

Generate a project-local `verify-<app>` skill for the next agent to use cold. It
must launch the real app, diagnose the instance, drive user behavior, preserve
evidence, and clean up only resources created by its own run.

## The Iron Law

```
NO GENERATED SKILL IS COMPLETE UNTIL ITS OWN INSTRUCTIONS PASS ONCE END TO END
```

## 1. Interview the repository

Read the repository before asking questions. Establish:

- **Surface:** Identify what users touch. Choose the primary observable surface,
  record secondary surfaces, and ask only when repository evidence cannot choose.
- **Run:** Find the repository's documented launch/build command, readiness
  signal, ports, environment, seed data, and authentication.
- **Drive:** Reuse an existing Playwright/Cypress suite, PTY helper, CLI, HTTP
  client, or debug protocol before introducing a generic recipe.
- **Observe:** Identify screenshots, accessibility snapshots, transcripts,
  response bodies, logs, exit codes, and persisted side effects available as proof.
- **Isolate:** Determine which ports, profiles, and data directories permit
  concurrent runs. If isolation is impossible, make the generated skill refuse
  to drive shared state concurrently.

If the checkout cannot build or launch as-is, fix that separately or report the
exact blocker. Do not generate instructions against a broken baseline.

## 2. Generate and mirror the skill

Write `verify-<app>/SKILL.md` in the canonical `.agents/skills/` tree, then
mirror that complete directory into the compatibility `.claude/skills/` tree.
Confirm all generated files are byte-identical across the two trees. Use valid universal frontmatter with
`name: verify-<app>`, a grounded description, `disable-model-invocation: false`,
and `harness: universal`.

The generated skill must declare **Surface and capability ceiling** before its
workflow. Name the primary surface, secondary surfaces, driver, and the strongest
proof the driver can produce. A DOM-functional driver cannot satisfy a VISUAL
criterion; record such a check as `BLOCKED`, never `PASS`.

Include these grounded instructions, with no placeholders:

- **Launch:** Exact start command, isolation inputs, readiness signal, and
  teardown ownership. A short-lived CLI launches each drive in an isolated PTY.
- **Doctor:** One read-only check proving this is the expected healthy instance,
  build, port, data directory, and auth context.
- **Drive:** Exact commands and stable handles found in this repository. Prefer
  ARIA labels, data attributes, prompt strings, and route paths over coordinates.
- **Evidence:** Capture the user action and resulting state. Verify persisted
  side effects from a second user-facing view; do not substitute internal setters
  or test-only endpoints. State an artifact path outside disposable run state.
- **Cleanup:** Track process IDs, ports, sessions, profiles, and scratch paths
  created by this run. Never kill by process name. Remove owned runtime state but
  preserve evidence.
- **Helpers:** List each shipped helper, make it executable, and show its exact
  invocation. If no helper is needed, state that the grounded commands above are
  the complete interface rather than creating an empty script.

## 3. Seed the feature map

Create `features/README.md` and one file for each of the top 3-5 user-facing
features found in routes, commands, menus, or documentation. Follow
[`references/feature-map-example/`](references/feature-map-example/).

The README indexes every feature. Each feature file starts with an H1 and a
user-visible summary, followed by exactly these four H2 sections in order:

1. `Sub-features`
2. `How to get to it (user POV)`
3. `Driving it with <harness>`
4. `Gotchas`

List every documented user entry point and its distinct observable proof. Do not
claim an untested entry point passed because a more convenient route worked.

## 4. Prove the generated contract

Run one complete walkthrough using the generated instructions:

1. Launch the isolated application.
2. Run Doctor and require success.
3. Drive one mapped feature through one documented user entry point.
4. Capture the named evidence and observable side effect.
5. Run Cleanup, including after every failed iteration.
6. Confirm the evidence still exists at the named location after cleanup.

Record the command sequence, selected feature and entry point, evidence paths,
doctor result, cleanup result, and surviving-artifact check. A failed or unrun
walkthrough leaves the generated skill a draft and must not be reported complete.

## 5. Hand off maintenance

Point the user to `/maintain-verification-skill --scope changed` after sessions
that alter user-facing behavior and `/maintain-verification-skill` for a full
source-and-live audit. Suggest a schedule only when asked.

## Integration

- Called directly when a target repository has no project-local verification skill.
- Produces the input maintained by `/maintain-verification-skill` and consumed by
  `/verify --scope e2e`.

## Provenance

Adapted from pstack's `create-verification-skill` in `cursor/plugins`, revision
`68836ddaf5697224520f1847d90cdb90ca8babaa`. The upstream MIT notice is bundled
as `LICENSE.pstack`; repository-level provenance is in `THIRD_PARTY_NOTICES.md`.
