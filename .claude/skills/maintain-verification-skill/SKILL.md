---
name: maintain-verification-skill
description: Reconcile a project verification skill after changed user behavior or run a full source-and-live feature audit. Use after user-facing changes or when auditing a verify-app feature map.
argument-hint: "[--scope changed]"
disable-model-invocation: false
harness: universal
---

# /maintain-verification-skill — Maintain verification knowledge

## Overview

Keep a project-local `verify-<app>` skill and its feature map aligned with the
real user experience. `--scope changed` is a cheap session reconciliation; the
default is a comprehensive source-and-live audit.

## The Iron Law

```
NEVER CLAIM COVERAGE FOR A FEATURE OR ENTRY POINT THAT WAS NOT ACTUALLY CHECKED
```

## Outcomes

Emit exactly one outcome word and its evidence:

- **clean** — required coverage completed and no verification content changed,
  or changed scope proved maintenance not applicable without claiming coverage.
- **changed** — proven verification-skill corrections remain on the active branch.
- **blocked** — required coverage or a safe correction could not finish; name the blocker.

## Locate and protect the target

Find every `verify-*` directory in the canonical `.agents/skills/` tree and
count candidates before validating their contents. This must use the same
candidate set as `/verify --scope e2e`.

- Exactly one candidate: require its `SKILL.md` to have Launch, Doctor, Drive,
  Evidence, and Cleanup instructions plus `features/README.md`, then use it and
  require a byte-identical mirror under the `.claude/skills/` compatibility tree.
- Several candidates: stop and ask which application is in scope; never guess.
- None in changed scope: return `clean` with evidence that no project-local
  target exists and one recommendation to run `/create-verification-skill`.
- None in full mode: return `blocked` and point to `/create-verification-skill`.

Only edit the selected verification skill's own directory in both skill trees:
its `SKILL.md`, `features/`, and owned helpers. Never edit product code. Treat a
behavior mismatch as documentation drift, a harness gap, or a product regression;
report product regressions instead of rewriting the map to hide them.

## Changed-scope pass

Run this pass only for `/maintain-verification-skill --scope changed`.

1. Read the current session intent: touched specs, completed task entries, and
   session notes. Read the session's base-to-HEAD diff, including user-facing bug
   fixes that touched no spec.
2. Classify whether behavior visible through the selected skill's declared
   surface changed. For internal-only changes, skip silently and emit `clean`.
3. Map each visible change to affected feature files and user entry points.
   Require a concrete changed source path before adding a missing feature.
4. Reconcile only affected or missing entries. Preserve the four required H2
   sections and the feature index; do not drive unrelated features or regenerate
   the whole map.
5. Mirror the `verify-<app>` files byte-identically under `.claude/skills/` and
   leave edits on the active branch for the caller's normal review and commit.
   This mode does not open a separate PR.
6. Re-read the same session evidence and map. If a second pass would change
   anything, reconcile again before returning; the result must be idempotent.

Do not launch the app in this pass. The caller's immediately following
`/verify --scope e2e` supplies live evidence for changed acceptance criteria.
Return only `clean`, `changed`, or `blocked` with affected feature IDs and paths.

## Full pass

Run this pass when no scope argument is supplied.

1. **Index hygiene.** Compare `features/README.md` with sibling feature files.
   Correct missing, extra, duplicate, and dead entries.
2. **Source wave.** Dispatch one read-only subagent per feature concurrently.
   Each independently explains the user-visible behavior from source, cites
   entry points, reports likely drift or none, and returns one concise live
   recipe. Subagents never drive the app or edit files. If independent dispatch
   is unavailable, return `blocked` and state the lost coverage.
3. **Reconcile.** Require a returned summary for every feature. Spot-check cited
   drift and inspect recent user-facing source churn for missing mapped features.
   Merge recipes into as few app states as practical without dropping entry points.
4. **Live pass.** The coordinator launches and doctors the target through its
   own verification skill. Exercise every feature at least once. Doctor each
   fresh session, doctor again after surprising failures, and reset a wedged UI
   even when the process is healthy. Record concrete prerequisites for unreachable
   paths. A skipped entry point is not covered by another route.
5. **Evidence and cleanup.** Preserve evidence already captured across every
   cleanup. Remove only processes and state owned by the run, including residue
   after failed drives. After the final teardown, confirm all named evidence paths
   still exist.
6. **Triage.** Fix verified map drift and harness gaps inside edit scope, then
   re-drive any harness correction. Report product regressions without editing
   product code.
7. **Ship or stop.** For `changed`, re-read all edits and create at most one PR
   containing proven verification corrections. For `clean` or `blocked`, create
   no PR. Keep run notes in scratch storage, never in the commit.

## Integration

- Called with `--scope changed` by `/build` and `/wrap-up-session` before their
  E2E verification gate for user-facing session changes.
- Called directly or by approved scheduling for a complete audit.
- Maintains output from `/create-verification-skill`; live driving follows the
  selected project skill and `/verify --scope e2e` capability rules.

## Provenance

Adapted from pstack's `maintain-verification-skill` in `cursor/plugins`, revision
`68836ddaf5697224520f1847d90cdb90ca8babaa`. The upstream MIT notice is bundled
as `LICENSE.pstack`; repository-level provenance is in `THIRD_PARTY_NOTICES.md`.
