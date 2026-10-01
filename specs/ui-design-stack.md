---
implementation_paths:
  - .agents/skills/design-stack/**
  - .agents/skills/prd/SKILL.md
  - .agents/skills/plan/SKILL.md
  - .agents/skills/system-design-planning/SKILL.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/verify-evidence/**
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/agents/frontend-developer.md
  - .agents/agents/frontend-design-validator.md
  - .claude/agents/frontend-developer.md
  - .claude/agents/frontend-design-validator.md
  - README.md
  - tests/test-design-stack-install.sh
  - tests/test-design-stack-catalog.sh
  - tests/test-design-stack-brief.sh
  - tests/test-design-stack-workflow.sh
  - tests/test-design-stack-evidence.sh
  - tests/test-design-stack-3d.sh
---

# Spec: UI design stack for projects built with jplugin

> Origin: user discussion · Designed 2026-10-01 · Review status: **draft; critic: 4 applied, 0 declined**
> Visual: specs/ui-design-stack.plan.html

## Problem

People building visual products with jplugin need a project-chosen design direction, the full set of available upstream design references and tools, and browser evidence that the finished UI works and looks intentional. The harness currently routes UI implementation and E2E checks, but does not persist a project design brief or require screenshot review. Redesigning jplugin's own visual-plan and recap renderer is a separate issue.

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Applicability | Design orchestration runs for visual UI projects; CLI-only and backend-only work stays on its existing path. | user | UI/non-UI fixture runs in `tests/test-design-stack-workflow.sh` |
| Direction choice | One primary direction from the full installed catalog, optional references and custom brief; `spatial` is the default for a new project with no answer. | user | Catalog and brief fixture tests |
| Existing project | A project without `DESIGN.md` keeps its current visual language until its owner selects a direction; unattended work cannot silently apply spatial. | user | Existing-project fixture in `tests/test-design-stack-brief.sh` |
| Distribution | Upstream packages install once at user scope; no upstream repository is copied into each project and normal design runs make no network fetch. | user | Setup/update tests with isolated home and offline run |
| Updates | A deliberate update checks current upstream, records revisions, validates the candidate, and preserves the last working installation on failure. Existing project rules never change solely because tools update. | user | Failed-update and stable-brief fixtures |
| Project choice | The project owner can browse all installed Taste styles/archetypes and awesome-design-md references, choose custom, and override a suitability warning. Impeccable commands and img2threejs are capabilities, not style entries. | user | Catalog enumeration and suitability fixtures |
| Major UI review | A new screen/route or a substantial redesign has a reviewable concept before build; a localized UI change follows the approved brief. | user | Planning-skill contract tests and concept fixture |
| Concept approval | A major-UI build starts only from an owner-started build prompt that names the reviewed concept digest; build records a receipt tied to that digest, and unattended runs wait for owner approval. | user | Concept-digest and approval-receipt fixture |
| Production 3D | img2threejs runs only when requested or called for by the brief; production image-to-3D output passes its strict gates, while incomplete work is labeled prototype. | user | 3D gate fixture and skill contract test |
| UI verification | Every completed UI change has desktop and mobile Playwright captures, interaction checks and visual review, with reviewer-visible links. | user | Browser fixture and E2E log assertions |
| Evidence retention | GitHub-backed PRs run a committed project-specific visual check in CI and link that run's authenticated GitHub Actions artifact retained for 30 days; local-only projects link retained workspace artifacts. A missing or inaccessible review link blocks UI closure. | inferred | CI-workflow fixture, live fixture run and PR closure check |
| Browser prerequisite | The Playwright CLI integration is merged before the browser-verification slice begins; this branch's verifier still names MCP backends. | user | Pre-flight check in the browser-verification slice |
| Renderer boundary | The visual-plan/recap renderer and its design are unchanged by this feature. | user | Changed-path check against `html-presentation`, `visual-plan`, `visual-recap` |

## System design

### Current state and ownership

The canonical skill tree is `.agents/skills/`; Claude's plugin manifest points at it (`.claude-plugin/plugin.json:10`), `install.sh:432-450` copies it to user scope for Pi/Codex, and `/sync` copies it into downstream projects (`.agents/skills/sync/SKILL.md:17-20,88-96`). `/prd` writes project context without a design brief (`.agents/skills/prd/SKILL.md:203-226`). `/plan` and `/system-design-planning` write specs and build prompts (`.agents/skills/plan/SKILL.md:118-179`; `.agents/skills/system-design-planning/SKILL.md:120-155`). `/build` dispatches frontend work and invokes `/verify-evidence --scope e2e` (`.agents/skills/build/SKILL.md:190-215,392-410`); the verifier distinguishes visual criteria but this branch has no Playwright CLI backend (`.agents/skills/verify-evidence/SKILL.md:146-197`).

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| Shared design installation (NEW) | Installed upstream source revisions, verified tool paths and rollback target | Upstream sources, explicit setup/update request |
| Design catalog (NEW) | Available direction/reference/tool entries discovered from the installed sources | Shared installation; built-in `spatial` and `custom` entries |
| Project `DESIGN.md` (NEW) | Chosen direction, optional references, and stable project-specific visual rules | Catalog at selection time; existing UI at adoption time |
| `/prd`, `/plan`, `/system-design-planning` | Project requirements, UI concept and reviewed spec | `DESIGN.md`, catalog |
| Project `tasks/design-approvals/<feature>.json` (NEW) | The owner-started build prompt's approved concept path and SHA-256 digest | Reviewed spec and `design/concepts/<feature>.html` |
| `/build` and frontend agents | Implemented UI | Approved spec, concept and `DESIGN.md` |
| Project `tests/visual/<feature>.sh` (or existing executable suite) and `.github/workflows/jplugin-ui-evidence.yml` (NEW) | Reproducible app launch, changed-state browser checks and CI capture upload | Project verification skill, Playwright CLI, reviewed commit |
| `/verify-evidence` and `/wrap-up-session` | Append-only E2E record and completion gate | Changed UI, local and CI Playwright captures, review artifact links |

### Interaction

```text
install.sh / sync ── existing copy ──► jplugin design skill (NEW)
                                                │
first UI use ── sync setup ────────────────────► shared user-scope tools (NEW)
explicit update ── sync network request ──────► staged tools ── validate/promote
                                                │
project owner ── sync selection ───────────────► DESIGN.md (NEW)
                                                │
UI plan ── sync read ───────────────────────────► concept + digest + spec (NEW)
owner starts digest-bearing build prompt ──────► approval receipt (NEW)
build ── sync receipt/brief read ───────────────► implemented UI
verify ── sync Playwright CLI ──────────────────► captures + append-only E2E log (NEW)
push ── async GitHub Actions visual check ─────► fresh CI captures + upload (NEW)
wrap-up ── sync artifact metadata check ───────► review artifact URL (NEW)
```

| Arrow | Mode | On timeout or unavailability | On duplicate |
|-------|------|------------------------------|--------------|
| Setup/update → upstream | sync network, only on explicit setup/update | Return `Unavailable` or `UpdateRejected`; keep last working installation and leave non-UI work usable. | Same verified revision is a no-op. |
| Catalog → project selection | sync local | Missing installation returns `SetupRequired`; missing selected entry does not rewrite an existing brief. | Re-selecting the same direction preserves the existing authored rules. |
| Plan → concept/spec | sync local | Missing design brief in an existing UI project returns `SelectionRequired`; planning does not fall back to spatial. | Re-run replaces the same concept/spec paths and changes the digest, invalidating any older approval. |
| Owner prompt → approval receipt | sync local, only after explicit owner input | No owner-started digest-bearing prompt returns `ConceptReviewRequired`; unattended runs wait. | Same spec and digest reuse one receipt. |
| Build → UI | sync local | Missing or stale concept approval for a major UI stops that slice before edits. | Existing build task idempotency and tests govern re-run. |
| Verify → Playwright CLI | sync local browser process | Missing CLI/browser or timed-out capture fails UI verification with a diagnostic and no completion claim. | Each retry uses a new run ID and appends to the E2E log; prior captures and walkthroughs remain. |
| Push → CI visual check | async GitHub Actions workflow runs the committed project visual script on the PR commit | Failed app launch, browser run or upload returns `PublicationUnavailable`; wrap-up waits or blocks UI closure. | Workflow and artifact names include task ID and commit SHA. |
| Wrap-up → review artifact | sync authenticated GitHub Actions artifact lookup for a GitHub PR; sync retained workspace link for local-only | Timeout, expired or inaccessible URL returns `PublicationUnavailable` and blocks UI closure until a valid link exists. | Same task/commit/run resolves to one artifact record; duplicate lookup does not duplicate E2E entries. |

### Failure unit

An upstream setup/update failure blocks design setup or refresh only; the prior verified installation and all non-UI harness work remain usable. A missing design choice or owner concept approval blocks new UI work for the affected project, not its unrelated tasks. A local browser, CI browser/upload, publication or strict 3D gate failure blocks completion of the affected UI task, not unrelated slices. The CI visual check runs the same committed project script that the local check proved, against the PR commit; it does not need access to local screenshots.

## Component contracts

### Shared design installation

```text
design-stack setup|update -> Ready(revisions, catalog_path)
                          | SetupRequired(reason)
                          | UpdateRejected(previous_revisions, reason)
```

| Aspect | Contract |
|--------|----------|
| Inputs | User-scope install path, official Taste/Impeccable installers, shared awesome-design-md and img2threejs sources; `update` is explicit. |
| Outcomes | A verified revision set becomes current, or the prior current set remains intact with a named reason. First-time offline setup reports `SetupRequired`. |
| Raises | Programmer/configuration faults; expected network and validation failures are outcomes. |
| Idempotency | The upstream revision set is the key; an already-current set is a no-op. |
| Versioning | A small manifest records source revisions and a schema version. One prior manifest version remains readable during upgrades. |

### Catalog and project brief

```text
catalog list(installation) -> Entries(directions, archetypes, references, tools)
                            | SetupRequired(reason)
select(project, direction_id, reference_ids) -> Brief(path) | SelectionRejected(reason)
```

| Aspect | Contract |
|--------|----------|
| Inputs | Installed Taste skill frontmatter/archetypes, installed awesome-design-md `DESIGN.md` files, local spatial/custom recipes; explicit owner selection. |
| Outcomes | All discovered options appear in a browsable catalog. A fit warning is advisory and overrideable. Impeccable commands and img2threejs are listed as tools, not directions. |
| Raises | Invalid catalog schema or unsafe path outside the shared install. |
| Idempotency | Listing is read-only; selection of an unchanged brief is a no-op. |
| Versioning | `DESIGN.md` carries a v1 heading/field contract; later readers keep accepting v1. |

### Planning and build

```text
plan_ui(project, change) -> ProposedSpec(brief, concept_path?, concept_sha256?)
                         | SelectionRequired
approve_ui(proposed_spec, owner_build_prompt) -> ApprovedReceipt | ConceptReviewRequired
build_ui(approved_spec) -> ImplementedUI | Blocked(reason)
```

| Aspect | Contract |
|--------|----------|
| Inputs | A project brief; for a new route/screen or substantial redesign, `design/concepts/<feature>.html`, its SHA-256 in the spec/build prompt, and an owner-started build prompt. |
| Outcomes | Build pre-flight writes `tasks/design-approvals/<feature>.json` with spec path, concept path/digest, prompt digest and approval time; it rejects a missing/stale digest before UI edits. Localized UI edits use the brief without a new concept gate. |
| Raises | Existing planning/build errors only. |
| Idempotency | Replanning changes the digest and invalidates an old receipt; an unchanged spec/digest reuses one receipt; building follows existing slice/task IDs. |
| Versioning | Existing projects without `DESIGN.md` remain valid but require owner selection before UI planning. |

### UI verification

```text
verify_ui(changed_surfaces, reviewed_spec) -> Captured(run_id, local_paths)
                                           | Failed(defects, capture_paths)
                                           | BackendUnavailable(reason)
publish_ui_evidence(task_id, commit_sha, review_context) -> Published(url, expires_at)
                                                         | PublicationUnavailable(reason)
```

| Aspect | Contract |
|--------|----------|
| Inputs | Every changed UI route/state and its acceptance criteria; Playwright CLI after the prerequisite merge; committed `tests/visual/<feature>.sh` or an existing executable suite that launches the app using the project verification skill's grounded commands. |
| Outcomes | Local desktop/mobile captures, interaction result and visual defect disposition append to `tasks/e2e-log.md`. For a GitHub PR, the one-time generated `.github/workflows/jplugin-ui-evidence.yml` runs the committed check on the PR commit, uploads its own captures with `actions/upload-artifact@v4` and 30-day retention, and links the authenticated artifact from the task/PR. Local-only projects retain workspace artifacts with resolvable paths. |
| Raises | Unexpected runner faults; missing CLI/browser is `BackendUnavailable`. |
| Idempotency | A task/run key names one local capture set; retries use new run IDs and append records, preserving prior walkthroughs. CI artifacts are keyed by task ID and commit SHA; a publication retry links the matching artifact. |
| Versioning | Existing E2E log entries remain readable; visual entries add artifact links. |

## Data models

### Shared installation manifest

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `schema_version` | integer | Supported version, initially `1` | Manifest parser |
| `sources` | source → revision map | One verified revision per required installed source | Setup/update validation |
| `catalog_path` | local path | Inside the selected verified installation | Path containment check |
| `current` | pointer to verified release | Either absent or complete; never points at staging | Promote only after validation |

### Catalog entry

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `id` | stable namespaced string | Unique within installed catalog | Catalog validator |
| `kind` | `direction`, `archetype`, `reference`, `tool` | Impeccable commands and img2threejs are tools, not primary directions | Catalog constructor |
| `source_revision` | revision string | Matches the manifest source | Catalog validator |
| `fit` | use-case description | Warning never silently removes an owner-selectable direction | Selection flow |

### Project `DESIGN.md`

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `version` | integer | Initially `1` | Brief validator |
| `direction` | one catalog ID or `custom` | Exactly one primary direction; `spatial` is the new-project default | Brief validator and setup flow |
| `references` | zero or more reference IDs | Optional; each selected ID is recorded | Brief validator |
| Visual rules | Markdown sections for palette, typography, layout, motion, accessibility and any 3D intent | Authored project rules remain stable across upstream updates | Planning/build read, brief tests |

### Concept approval receipt

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `spec_path` and `concept_path` | project-local paths | Both exist and the concept is cited by the spec | Build pre-flight |
| `concept_sha256` | digest | Matches the concept bytes named in the owner-started build prompt | Build pre-flight and receipt validator |
| `approval_source` and `prompt_sha256` | owner prompt reference and digest | An unattended agent cannot generate an owner approval; the prompt includes the concept digest | Build pre-flight |
| `approved_at` | UTC timestamp | Records when the owner-started prompt was received | Receipt writer |

There is no mutable approval status: a receipt exists for one digest or does not; changing the concept makes the old receipt invalid by digest comparison.

### Visual evidence set

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `run_id` | unique task/run key | New for each retry | Verifier |
| `commit_sha` | Git commit ID | A PR artifact comes from the reviewed commit, not a different local working tree | CI workflow and wrap-up lookup |
| `captures` | desktop/mobile paths per changed state | Files exist in retained local or CI artifact | Capture and publication validation |
| `review_link` | artifact URL or local path | GitHub PR URL resolves for reviewers, or local-only path remains readable | Wrap-up link check |
| `expires_at` | UTC timestamp or local retention policy | GitHub Actions artifact retains at least 30 days from publication | Artifact metadata check |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| Current install points to unverified or partial sources | Stage-and-validate before pointer promotion |
| Two primary design directions in one project brief | One `direction` field in the v1 brief parser |
| A command or 3D pipeline is selected as a visual direction | Catalog `kind` check |
| Existing UI with no brief is automatically restyled as spatial | `SelectionRequired` outcome in existing-project path |
| A major UI builds from an unapproved or modified concept | Digest-bound owner approval receipt checked before edits |
| Production 3D marked complete with a failed strict sculpt/spec or later forge gate | Gate result required by build/verification contract |
| UI task marked complete without desktop/mobile screenshots or a resolvable reviewer-visible link | Visual E2E and publication completion gates |

### Migration and compatibility

New UI projects create `DESIGN.md` during setup. Existing projects remain valid with no file until their owner chooses a direction; adoption infers current visual rules for review before writing the brief and never rewrites UI merely to install the stack. The shared install uses a verified release pointer, so update rollback selects the previous release without rewriting project briefs. Existing E2E log entries remain valid and append-only; visual tasks created after this feature require links. A concept digest changes whenever the concept changes, so a previous approval receipt cannot authorize the revised concept. GitHub-backed UI projects add `.github/workflows/jplugin-ui-evidence.yml` from the verifier's template and a committed project-specific visual check; they never commit captured screenshots or upstream source trees. If the project cannot run its app in CI, publication is unavailable and the UI task cannot close until CI is configured.

## Build Order

Sizing: 9 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 1–4 and 7 touch the canonical skill and tests together; slices 5, 6 and 9 cross caller and verification systems whose contract must move atomically. Each slice remains below three ACs except slice 1, which carries exactly three.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Shared setup | One user-scope setup/update with verified revisions and rollback, distributed through the existing skill path. | `.agents/skills/design-stack/**`, `README.md`, `tests/test-design-stack-install.sh` | — | 1, 2, 12 | `bash tests/test-design-stack-install.sh` | 6 planned files · 3 systems · 3 ACs; skill/test atomic |
| 2 | Complete catalog | Discovery of every installed style, archetype and reference, plus selection and fit warnings. | `.agents/skills/design-stack/**`, `tests/test-design-stack-catalog.sh` | 1 | 3, 4 | `bash tests/test-design-stack-catalog.sh` | 4 planned files · 3 systems · 2 ACs; skill/test atomic |
| 3 | Stable brief | A versioned `DESIGN.md` contract whose authored rules survive tool updates. | `.agents/skills/design-stack/**`, `tests/test-design-stack-brief.sh` | 2 | 6 | `bash tests/test-design-stack-brief.sh` | 4 planned files · 3 systems · 1 AC; skill/test atomic |
| 4 | Project onboarding | New UI selection with spatial preselected, existing UI preservation, and non-UI bypass. | `.agents/skills/design-stack/**`, `.agents/skills/prd/SKILL.md`, `tests/test-design-stack-brief.sh`, `tests/test-design-stack-workflow.sh` | 3 | 5 | `bash tests/test-design-stack-brief.sh` | 5 planned files · 4 systems · 1 AC; brief/PRD contract atomic |
| 5 | Concept review | UI plans carry the brief, concept digest and owner approval receipt contract before the build prompt. | `.agents/skills/plan/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md`, `tests/test-design-stack-workflow.sh` | 4 | 7 | `bash tests/test-design-stack-workflow.sh` | 3 files · 3 systems · 1 AC; both planners share one gate |
| 6 | Frontend dispatch | Builders and design validators receive the approved brief/concept and stop on missing selection. | `.agents/skills/build/SKILL.md`, `.agents/agents/frontend-developer.md`, `.agents/agents/frontend-design-validator.md`, `.claude/agents/frontend-developer.md`, `.claude/agents/frontend-design-validator.md`, `tests/test-design-stack-workflow.sh` | 5 | 8 | `bash tests/test-design-stack-workflow.sh` | 6 files · 4 systems · 1 AC; dispatch/mirror contract atomic |
| 7 | Strict 3D | Opt-in img2threejs execution with production gates and explicit prototype labeling. | `.agents/skills/design-stack/**`, `.agents/skills/build/SKILL.md`, `tests/test-design-stack-3d.sh` | 6 | 9 | `bash tests/test-design-stack-3d.sh` | 4 planned files · 4 systems · 1 AC; skill/consumer gate atomic |
| 8 | Browser QA | A locally proven project visual check with Playwright CLI desktop/mobile captures, interactions and visual review. | `.agents/skills/verify-evidence/**`, `tests/test-design-stack-evidence.sh` | 7 | 10 | `bash tests/test-design-stack-evidence.sh` | 3 planned files · 2 systems · 1 AC |
| 9 | Evidence closure | Append-only E2E records and a CI workflow that reruns the committed visual check and uploads its own captures, or retained local-only links. | `.agents/skills/verify-evidence/**`, `.agents/skills/wrap-up-session/SKILL.md`, `tests/test-design-stack-evidence.sh` | 8 | 11 | `bash tests/test-design-stack-evidence.sh` plus one GitHub fixture CI run | 4 planned files · 3 systems · 1 AC; verify/wrap-up contract atomic |

The Playwright CLI branch is a prerequisite for slice 8; the user will merge it before this plan is built. Each slice leaves the affected tests green; the full suite runs at the build baseline and wrap-up as specified by the harness.

Build prompt:

```
Invoke `/build` for `specs/ui-design-stack.md`.
Plan: `## Plan: ui-design-stack` in `tasks/todo.md`, 9 slices, ready set 1.
Files: .agents/skills/design-stack/**, .agents/skills/prd/SKILL.md, .agents/skills/plan/SKILL.md, .agents/skills/system-design-planning/SKILL.md, .agents/skills/build/SKILL.md, .agents/skills/verify-evidence/**, .agents/skills/wrap-up-session/SKILL.md, .agents/agents/frontend-developer.md, .agents/agents/frontend-design-validator.md, .claude/agents/frontend-developer.md, .claude/agents/frontend-design-validator.md, README.md, tests/test-design-stack-install.sh, tests/test-design-stack-catalog.sh, tests/test-design-stack-brief.sh, tests/test-design-stack-workflow.sh, tests/test-design-stack-evidence.sh, tests/test-design-stack-3d.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/ui-design-stack.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: UI projects only; spatial is a new-project default; existing visual rules remain stable until owner selection or refresh; shared setup and explicit update only; all installed directions and references remain browsable; major UI concepts require a digest-bound owner approval from this build prompt; 3D is opt-in and strict for production; Playwright CLI screenshot evidence gates UI completion, with CI rerunning a committed project visual check and publishing its own captures for GitHub PRs; visual-plan/recap redesign is out of scope.
```

## Decisions

| Decision | Options | Recommended | Wrong when |
|----------|---------|-------------|------------|
| Scope | UI projects / all artifact generation | UI projects (`user`) | Harness visual-plan/recap redesign belongs to a separate issue. |
| Default and selection | Spatial default with project choice / fixed style | Spatial default, full catalog and custom (`user`) | An existing project with no brief must preserve its current UI. |
| Distribution | Shared user-scope install with explicit update / copies per project / per-run fetch | Shared install and update (`user`) | Network is unavailable on first setup: report `SetupRequired`, do not claim readiness. |
| Existing project stability | Stable brief / automatic restyle on upstream update | Stable brief (`user`) | Owner explicitly asks to refresh the project design. |
| Major UI concept | Review before build / build first | Review new screen/route or substantial redesign (`user`) | A localized UI fix follows the existing brief. |
| Concept approval evidence | Digest-bound owner build prompt / unversioned consent | Digest-bound receipt (`user`) | An unattended run has no owner prompt, so it waits. |
| Production 3D | Strict img2threejs gates / plausible browser model | Strict gates, prototype label for incomplete work (`user`) | 3D was neither requested nor named in the brief. |
| Evidence | Playwright desktop/mobile gate / optional captures | Mandatory gate and review artifact links (`user`) | Non-UI work has no visual surface to capture. |
| Artifact destination | CI-created GitHub Actions artifact for PRs, retained workspace for local-only / commit screenshots | CI or local review artifacts (`inferred`) | A project cannot run a committed visual check or provide a resolvable reviewer-visible link; UI closure then waits. |

## Acceptance Criteria

- AC 1. A one-time user-scope setup makes the upstream Taste and Impeccable skills/commands, awesome-design-md references, and img2threejs capability available through jplugin without copying upstream repositories into projects; normal UI runs work offline after setup.
- AC 2. An explicit update discovers upstream revisions, validates a candidate installation and catalog, records the revisions, and keeps the prior verified installation usable when the candidate fails or times out.
- AC 3. The catalog lists every installed Taste style and archetype plus every installed awesome-design-md reference without a fixed three-prototype or reference count; `spatial` and `custom` are available; Impeccable commands and img2threejs are tools rather than primary styles.
- AC 4. A project owner can select one direction, optional references and a custom brief from the browsable catalog; unsuitable combinations show an overrideable fit warning.
- AC 5. New UI projects save their choice in `DESIGN.md` with spatial preselected; existing UI projects without a brief retain their current look and require one owner choice before UI planning; backend/CLI projects do not enter the design flow.
- AC 6. A project's approved palette, type, layout and motion rules remain in `DESIGN.md` across tool updates; a design refresh changes them only through an explicit owner choice.
- AC 7. `/prd`, `/plan` and `/system-design-planning` carry the project design brief into UI requirements; a new route/screen or substantial redesign produces a reviewable concept and digest before the build prompt, and only an owner-started prompt for that digest yields a recorded approval receipt; a localized change uses the existing brief.
- AC 8. `/build` supplies the approved brief and concept to frontend implementation and review; an unattended existing UI project without a brief stops with a named selection requirement instead of applying spatial.
- AC 9. img2threejs runs only when the task or brief requests 3D; production completion requires its strict quality gates, and an incomplete model is labeled prototype with failed/open gates recorded.
- AC 10. Every changed UI route/state gets a locally proven, executable project visual check with Playwright CLI desktop and mobile captures, interaction checks and a visual defect review; a missing browser/backend or failed check prevents a completion claim.
- AC 11. UI verification appends retained screenshot links and defect disposition to `tasks/e2e-log.md`; a GitHub PR workflow reruns the committed project visual check on the PR commit, uploads its own captures as a validated 30-day Actions artifact and links it from the task/PR; local-only projects link readable retained workspace artifacts; missing publication blocks UI closure while non-UI verification continues on its existing path.
- AC 12. Harness installation and `/sync` distribute only the jplugin adapter and small project-owned brief template; no new upstream payload copy or automatic upstream fetch is introduced per project or per design run, and the existing visual-plan/recap renderer is untouched.

## Implementation Paths

- `.agents/skills/design-stack/**` — canonical design adapter, shared setup/update/catalog tooling and references, distributed by the existing plugin/install/sync paths.
- `.agents/skills/prd/SKILL.md`, `.agents/skills/plan/SKILL.md`, `.agents/skills/system-design-planning/SKILL.md` — project choice and concept before build.
- `.agents/skills/build/SKILL.md`, `.agents/agents/frontend-developer.md`, `.agents/agents/frontend-design-validator.md`, `.claude/agents/frontend-developer.md`, `.claude/agents/frontend-design-validator.md` — implementation and design review context.
- `.agents/skills/verify-evidence/**`, `.agents/skills/wrap-up-session/SKILL.md` — Playwright evidence and UI completion gate after CLI merge.
- `README.md` — discoverability; the brief template lives inside the design skill and is written only for UI projects.
- `tests/test-design-stack-install.sh`, `tests/test-design-stack-catalog.sh`, `tests/test-design-stack-brief.sh`, `tests/test-design-stack-workflow.sh`, `tests/test-design-stack-evidence.sh`, `tests/test-design-stack-3d.sh` — behavioral and integration checks.
