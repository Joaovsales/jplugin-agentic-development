# Spec: pstack Verification Skill Integration

## Behavior

The workflow distributes harness-neutral adaptations of pstack's
`create-verification-skill` and `maintain-verification-skill`. The creator
interviews a target repository, generates a project-local `verify-<app>` skill
and feature map, and proves one mapped feature end to end before handing the
skill over. The maintainer supports two modes:

- `--scope changed` reconciles only user-facing behavior changed by the current
  session. `/build` runs it before E2E verification and `/wrap-up-session` runs
  it as an idempotent backstop.
- Full mode retains pstack's complete source-and-live audit of every mapped
  feature and is invoked directly or by scheduled automation.

`/verify --scope e2e` prefers one project-local `verify-<app>` skill when one
exists, while preserving the current fail-closed acceptance-criterion
classifier and generic browser fallback. Session Stop hooks do not run agentic
maintenance; lifecycle integration remains in explicit skill chains.

The adaptation preserves the upstream MIT notice and records pstack, Lauren
Tan, the source files, and the pinned source revision. A general-purpose
upstream registry and scheduled checker monitor pstack and any future declared
source for drift without modifying vendored files.

## Inputs

- Explicit `/create-verification-skill` invocation in a target repository.
- Explicit `/maintain-verification-skill` invocation, optionally with
  `--scope changed`.
- A user-facing acceptance criterion classified by `/build` or
  `/wrap-up-session`.
- The current session's base-to-HEAD diff, touched specs, and completed task
  entries for changed-scope reconciliation.
- Existing project launch commands, user surfaces, driving harnesses, and
  observable proof mechanisms discovered from the target repository.
- A committed upstream registry entry containing a stable ID, Git URL, tracked
  ref, imported baseline commit, and optional path scope.

## Outputs

- Global, installable canonical skills under `.agents/skills/`, with
  byte-identical Claude compatibility copies under `.claude/skills/`.
- A generated project-local `.agents/skills/verify-<app>/SKILL.md`, mirrored to
  `.claude/skills/verify-<app>/SKILL.md`, plus `features/README.md` and the first
  3-5 user-facing feature files.
- Launch, Doctor, Drive, Evidence, Cleanup, and Helpers instructions grounded in
  the target repository, with a stated surface and capability ceiling.
- Preserved evidence after one creation-time live proof.
- Incremental feature-map edits on the active session branch, or a `clean`,
  `changed`, or `blocked` maintenance result.
- Full-audit corrections confined to the generated verification skill, with
  product regressions reported rather than hidden by documentation edits.
- Third-party license and attribution records in this repository.
- A failure-only scheduled/manual upstream-drift report that names every
  registered source whose tracked content changed or became unavailable.

## Design Decisions

### Canonical and generated paths

The imported skills are adapted from Cursor-specific `.cursor/skills/` paths to
this harness's `.agents/skills/` canonical tree. Every generated project-local
skill and asset is copied byte-identically into `.claude/skills/` so the existing
parity contract remains true across Codex, Pi, and Claude Code.

### Resolution and fallback

`/verify --scope e2e` resolves project-local verification skills before its
generic browser backend:

1. Exactly one `verify-<app>` skill: read it and use its grounded launch, doctor,
   drive, evidence, and cleanup contract.
2. More than one: stop and ask which application is in scope; never guess.
3. None: retain the existing Chrome -> Playwright -> Lightpanda -> STOP behavior.

A local skill is a driving recipe, not permission to weaken verification. Its
declared surface and capability ceiling must satisfy the classified AC. In
particular, uncertain browser ACs remain VISUAL, DOM-only drivers cannot pass
VISUAL ACs, and blocked checks remain non-success.

### Two-speed map maintenance

Changed scope runs only when the caller has identified user-facing behavior in
the current session. It reconciles affected and newly introduced behavior,
updates the feature index, and leaves edits on the current branch for the normal
review and commit flow. It does not open a separate PR or re-drive the entire
map. The following `/verify --scope e2e` invocation supplies live evidence for
the changed ACs.

Full mode performs index hygiene, one independent read-only source inspection
per feature, reconciliation against recent user-facing source churn, and one
coordinator-owned live pass over every feature. It may ship at most one PR of
proven corrections and never edits product code.

If no project-local verification skill exists, automatic chains retain generic
E2E behavior and emit one actionable recommendation to run the creator; they do
not generate files or launch an application implicitly. A direct maintenance
invocation with no target stops and points to the creator.

### Lifecycle placement

- `/build` invokes changed-scope maintenance after classifying user-facing ACs
  and before Phase 4 E2E verification.
- `/wrap-up-session` invokes the same idempotent reconciliation before its E2E
  coverage gate, covering debug/manual sessions that did not use `/build`.
- The Stop hook remains limited to cleanup and warnings. It must not edit files,
  launch the application, dispatch agents, or attempt live verification.
- Direct full maintenance is the comprehensive manual or scheduled drift audit.

### Licensing and attribution

This repository currently has no root license, so the change does not imply a
license for the whole repository. It includes the full upstream pstack MIT
notice in a third-party notice, credits `Copyright (c) 2026 Lauren Tan`, links
the original repository and both adapted skills, and pins provenance to upstream
revision `68836ddaf5697224520f1847d90cdb90ca8babaa`. README Sources carries the
human-facing credit.

### General-purpose upstream drift detection

`.github/upstreams.json` is the machine-readable registry for material vendored
or adapted into this repository. Each entry contains:

- `id`: stable unique identifier used in reports.
- `url`: Git remote URL; the checker is not GitHub-specific.
- `ref`: tracked branch or tag reference.
- `baseline`: exact commit whose content was imported or last reviewed.
- `paths`: optional repository-relative path list. Omit it to monitor the whole
  upstream; include it to avoid unrelated monorepo churn.
- `source_notice`: repository-relative attribution or license record associated
  with the import.

The first entry tracks pstack's creator, maintainer, feature-map references, and
license at the pinned baseline. Future imports register another entry rather
than adding source-specific checking code.

`scripts/check-upstream-drift.py` validates the complete registry before network
access, fetches each baseline and tracked ref into an isolated temporary Git
repository without checking out or executing upstream content, verifies that
the baseline is an ancestor of the current ref, and diffs only the registered
paths. It processes every entry so one unavailable source does not hide drift
in another. Results are:

- `clean`: all registered content matches its reviewed baseline; exit 0 and no
  routine output.
- `drift`: at least one registered path changed; non-zero with a bounded report
  containing source ID, baseline, current commit, and changed paths.
- `unavailable`: a ref, baseline, remote, or network lookup failed; non-zero and
  names the failed source without claiming it is clean.
- `history-diverged`: the baseline is no longer an ancestor of the tracked ref;
  non-zero and requires manual review rather than treating a force-push as a
  normal update.

A least-privilege GitHub Actions workflow (`contents: read`) runs the checker on
a weekly schedule and through `workflow_dispatch`. Clean runs are silent.
Drift, unavailable sources, invalid registry data, and rewritten history fail
the job and write the bounded report to the workflow summary, using GitHub's
failed-workflow notification rather than opening or mutating issues. The
workflow never updates a baseline, copies upstream files, executes fetched
content, or opens a PR. Accepting an upstream change remains a separately
reviewed change that updates the vendored files, notice when needed, and
registry baseline together.

This registry monitors every source explicitly declared in it; it does not
pretend to discover undocumented provenance or replace package-manager security
and dependency update tooling. The existing downstream `workflow` remote drift
notice remains separate because it compares a consumer repository with this
template, whereas this checker compares this template's vendored material with
its original sources.

## Edge Cases

- No launchable application or broken baseline: creator reports the exact
  blocker and does not emit an unproved deliverable.
- More than one user surface: creator chooses the primary observable surface,
  records secondary surfaces, and asks only when repository evidence cannot
  resolve the choice.
- More than one generated `verify-*` skill: verification and maintenance stop
  for target selection.
- No generated skill: normal E2E fallback remains backward-compatible; changed
  maintenance is skipped with a creator recommendation.
- Internal-only session changes: feature-map maintenance is skipped silently.
- User-facing bug fix without a touched spec: wrap-up classifies the diff and
  task/session evidence rather than assuming there was no visible change.
- Map lists multiple entry points: verification cannot prove one convenient
  path and report all entry points covered.
- Cleanup failure or failed proof iteration: clean only resources started by
  that run, preserve evidence, and never kill by process name.
- Evidence is removed by cleanup: creation or maintenance is blocked until the
  proof survives teardown.
- Product behavior disagrees with the map: documentation drift is corrected;
  a product regression is reported and product code remains untouched.
- Reduced-fidelity browser driver: it cannot satisfy a VISUAL AC and must record
  `BLOCKED` rather than `PASS`.
- Concurrent verification runs: use isolated ports, profiles, and data
  directories when supported; otherwise refuse to double-drive shared state.
- Full maintenance cannot dispatch independent feature readers: report the lost
  coverage/corroboration and return `blocked`, never imply a complete audit.
- Upstream changes after the pinned revision: no automatic fetch or overwrite;
  the scheduled checker reports drift and future adoption is a separately
  reviewed sync.
- Upstream repository or ref is deleted, made private, or temporarily
  unreachable: the checker reports `unavailable`; vendored skills and notices
  remain usable in this repository.
- Upstream force-push removes the baseline from the tracked history: report
  `history-diverged`, never silently reset the baseline.
- One of several upstreams fails: finish checking the remaining entries and
  report the aggregate non-clean result.
- Upstream monorepo changes outside registered paths: treat the registered
  import as clean; an entry with no `paths` monitors the entire repository.
- Invalid or duplicate registry entries: fail before fetching anything and name
  the exact field error.
- Scheduled runner is offline: fail loudly as `unavailable`; fixture tests never
  rely on public network access.

## Acceptance Criteria

- [x] AC-1: `create-verification-skill` and `maintain-verification-skill` exist
  in both skill trees, use valid harness-universal frontmatter with model
  invocation enabled, and remain byte-identical across canonical and Claude
  copies.
- [x] AC-2: The creator generates a project-local `verify-<app>` skill in both
  trees with grounded Launch, Doctor, Drive, Evidence, Cleanup, and Helpers
  instructions, a declared surface/capability ceiling, no placeholders, and no
  process-name cleanup.
- [x] AC-3: The creator generates an indexed 3-5 entry feature map whose feature
  files use the required four H2 sections and distinguish every documented user
  entry point and observable proof.
- [x] AC-4: The creator's contract requires and records a successful
  launch -> doctor -> one mapped drive -> evidence -> cleanup walkthrough, with
  evidence confirmed to survive cleanup; a failed or unrun proof cannot be
  called complete.
- [x] AC-5: Full maintenance performs index hygiene, separately dispatched
  read-only source coverage per feature, recent-surface reconciliation, one
  coordinator-owned live pass over every feature, and emits exactly `clean`,
  `changed`, or `blocked` while editing only the verification-skill directory.
- [x] AC-6: `--scope changed` consumes current session intent and diff, updates
  only affected/missing feature-map entries on the active branch, is idempotent,
  does not open a separate PR, and skips internal-only changes.
- [x] AC-7: `/verify --scope e2e` uses exactly one project-local verification
  skill when available, stops on ambiguity, falls back unchanged when absent,
  and never allows a local driver to bypass the existing fail-closed
  VISUAL/DOM-functional capability gate.
- [x] AC-8: Both `/build` and `/wrap-up-session` invoke changed-scope maintenance
  before E2E verification for user-facing session changes; the static invocation
  chain is pinned in both trees, and no Stop hook invokes maintenance.
- [x] AC-9: Absence of a project-local verification skill remains
  backward-compatible: generic E2E still runs, automatic creation never occurs,
  and the user receives an actionable creator recommendation.
- [x] AC-10: The full pstack MIT notice, Lauren Tan copyright, source repository,
  original skill links, and pinned upstream revision are preserved; README
  Sources credits pstack without licensing the entire repository implicitly.
- [x] AC-11: README, CLAUDE.md, and the session-start skill list describe both
  skills and the two-speed update mechanism; installation and sync distribute
  them through the existing skill-tree mechanisms without a new dependency.
- [x] AC-12: Focused mutation-capable tests prove registration, feature-map
  contract, resolution/fallback, capability ceiling, lifecycle chains,
  attribution, and tree parity; the complete `bash tests/run.sh` suite passes.
- [x] AC-13: A schema-validated, multi-source upstream registry and
  general-purpose Git checker support whole-repository or path-scoped tracking;
  pstack is registered at the imported baseline, clean checks are silent, and
  drift, unavailable sources, invalid configuration, or rewritten history fail
  with bounded actionable evidence while never changing vendored content or a
  baseline.
- [x] AC-14: A least-privilege weekly and manually dispatchable GitHub workflow
  runs the general checker, exposes non-clean evidence in the workflow summary,
  relies on failed-workflow notification, and never executes upstream content,
  opens issues/PRs, or applies updates automatically.

## Files Likely Involved

- `.agents/skills/create-verification-skill/` — canonical adapted creator and
  feature-map reference assets.
- `.agents/skills/maintain-verification-skill/SKILL.md` — canonical full and
  changed-scope maintenance workflows.
- `.claude/skills/create-verification-skill/` — byte-identical compatibility
  copy.
- `.claude/skills/maintain-verification-skill/SKILL.md` — byte-identical
  compatibility copy.
- `.agents/skills/verify/SKILL.md` and `.claude/skills/verify/SKILL.md` — local
  skill resolution, fallback, and capability-gate integration.
- `.agents/skills/build/SKILL.md` and `.claude/skills/build/SKILL.md` — pre-E2E
  changed-map reconciliation.
- `.agents/skills/wrap-up-session/SKILL.md` and
  `.claude/skills/wrap-up-session/SKILL.md` — session backstop before E2E.
- `tests/test-verification-skill-integration.sh` — focused static and fixture
  contract tests.
- `tests/test-skill-invocation-chain.sh` — lifecycle handoff guards.
- `tests/test-e2e-classifier.sh` — local-driver resolution and fail-closed
  classifier guards.
- `tests/test-skill-parity.sh` — existing byte-parity enforcement.
- `THIRD_PARTY_NOTICES.md` — upstream MIT notice and pinned provenance.
- `.github/upstreams.json` — extensible registry of reviewed upstream baselines
  and optional imported path scopes.
- `scripts/check-upstream-drift.py` — host-neutral Git drift checker with
  failure-only output.
- `.github/workflows/check-upstream-drift.yml` — weekly/manual notification
  workflow with read-only repository permissions.
- `tests/test-upstream-drift.sh` — local Git-fixture coverage for clean, drift,
  unavailable, rewritten-history, multi-source, and invalid-registry outcomes.
- `README.md`, `CLAUDE.md`, `.claude/hooks/session-start.sh` — discoverability,
  credits, and update-mechanism documentation.

## Verification

- Run each focused test red before implementation and green afterward.
- Mutation-probe at least one load-bearing assertion in each area: remove a
  required feature heading, sever a lifecycle invocation, remove the local
  skill fallback, weaken the VISUAL gate, remove the upstream notice, and alter
  a registry baseline/path; each mutation must make the relevant focused test
  fail.
- Exercise upstream checking only against temporary local Git repositories:
  clean and unrelated path churn exit 0 silently; relevant drift, unavailable
  remotes, non-ancestor history, duplicate IDs, and malformed fields exit
  non-zero with the expected source ID and bounded evidence.
- Run `bash tests/test-skill-parity.sh` after canonical-to-compat copies.
- Run `bash tests/run.sh` after all tasks and record test-file/assertion counts.
- During `/build`, run the normal quality gate and validate every acceptance
  criterion against fresh evidence.
