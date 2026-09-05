# Yolo iteration 1 — qwen spend guardrails

- [x] TDD: spec written (specs/qwen-spend-guardrails.md) — config task, no test suite; validation = JSON parse + doctor + API GET
- [x] C1 — settings.json defaultModel + builder turnBudget caps
- [ ] C2 — OpenRouter key limit PATCH + GET verify — **DEFERRED: requires a management key only the user can create (inference-key PATCH → 404). Pending user action.**
- [x] verify — subagent doctor + AC checks + yolo log entry

## Session Summary — 2026-09-02 d6b0bbe (wrap-up adds review fixes; sha updated at commit)
- Completed: 2 tasks (C1 settings + frontmatter turn caps, verification) — C2 reopened after review caught the premature [x]
- Pending: 1 (OpenRouter key limit — needs user-created management key)
- Carry-forward: verify AC3 after user sets key limit

---

## Task 1 — Store schema + validator guard

[x] TDD: `tests/test-solutions-schema.sh` fails on fixture docs with (a) unknown `problem_type`, (b) missing track-required field (bug track without `root_cause`; knowledge track without `applies_when`), (c) a date in the filename; passes on valid fixtures and on the real (initially empty) `tasks/solutions/` tree -> write `tasks/solutions/README.md` (frontmatter schema, `problem_type` enum, category map, two tracks, `needs_review`), `tasks/solutions/.gitkeep`, and the validator test sourcing `tests/lib.sh`, excluding `.claude/worktrees/`

## Task 2 — Migration script + fixture-driven tests

[x] TDD: `tests/test-migrate-learning-store.sh` covers: absent inputs (exit 0, no output files), 8-column and 5-column `bugs.md` schemas (header-name mapping, unknown column carried into body), free-form `lessons.md` (split on headings else blank-line blocks, `needs_review: true`), slug collision (numeric suffix), missing date (fallback chain recorded), re-run idempotency (second run exits 0, changes nothing), dirty-tree refusal without `--force`, existing `tasks/project-context.md` conflict (`.migrated.md` written, exit 0), unrecognized `##` section (archived verbatim, reported unmigrated), dry-run default writes nothing, `--apply` archives originals to `tasks/archive/<UTC-timestamp>/` and deletes nothing, non-zero exit on failure naming the source -> write `scripts/migrate-learning-store.py` (stdlib only, Python 3) with interpreter probing `python3`/`python`/`py` in the test harness

## Task 3 — Migrate this repo with --apply

[x] TDD: dry run prints a plan naming every document; `--apply` produces `tasks/solutions/<category>/<slug>.md` docs for the 7 Architecture Decisions rows + 2 `- Pattern:` bullets leaked into the 2026-07-08 session-history entry, `tasks/history.md` retaining the narrative entry (cross-linked), `tasks/project-context.md` (does not pre-exist here), originals moved to `tasks/archive/<UTC-timestamp>/`; `tests/test-solutions-schema.sh` green over the migrated docs; second run exits 0 no-op -> run the script on this worktree

## Task 4 — Hooks cutover

[x] TDD: `tests/test-session-start.sh` asserts the hook reports store counts in one line, dumps no document bodies, banner grows ≤1 line, and references none of the retired files; `tests/test-pre-compact.sh` asserts flush targets the new destinations -> edit `.claude/hooks/session-start.sh` + `.claude/hooks/pre-compact.sh`

## Task 5 — CLAUDE.md / README / install.sh cutover

[x] TDD: `tests/test-doc-conventions.sh` `tasks/memory.md` assertion INVERTED (asserts /build and /checkpoint do NOT reference it) and green; `tests/test-install-sh.sh` green with new seeds -> CLAUDE.md Session Start Checklist + Key Directories describe `tasks/solutions/`, `tasks/history.md`; CLAUDE.md names the migration script; README store description; install.sh seeds `tasks/solutions/README.md` + `tasks/history.md`, stops seeding `lessons.md`/`bugs.md`

## Task 6 — Skills cutover (canonical tree)

[x] TDD: grep across `.agents/skills/` finds zero references to `tasks/memory.md`, `tasks/lessons.md`, `tasks/bugs.md` -> `/learn` writes typed docs with date in frontmatter, five-dimension overlap scoring (High=update, Moderate=create+cross-link, Low=create), grounding rule (file:line or attribute; PR numbers not SHAs); `/memory-maintain` sweeps `tasks/solutions/` for stale/contradicted/`needs_review` docs; `/debug` + bug-report template emit bug-track documents; `/sync` detects an unmigrated store and points at the script; path-reference updates in auto-improve, brainstorm, build, checkpoint, prd, refresh, start-qa, wrap-up-session

## Task 7 — project-template seeds

[x] TDD: `project-template/tasks/` carries `solutions/README.md` + `history.md`, no longer carries `lessons.md`/`bugs.md`; template `.gitattributes`/docs consistent -> add/remove the seed files

## Task 8 — Parity copies

[x] TDD: `tests/test-skill-parity.sh` green -> byte-identical copy of every edited `.agents/skills/**` file into `.claude/skills/**`

## Task 9 — Full validation + reference sweep proof

[x] TDD: `bash tests/run.sh` fully green; `grep -rn "tasks/(memory|lessons|bugs)\.md"` across both trees, hooks, CLAUDE.md, README.md, install.sh returns hits only under `tasks/archive/` and `specs/` -> record the sweep output as evidence

## Session Summary — 2026-08-13 [128952c..18e3304]
- Completed: 9 tasks (M3 typed learning store + M3-MIG migration script, all ACs evidenced)
- Pending: 0 tasks
- Carry-forward: M4 (Tier 3.3 concepts glossary) — picked up below on `feat/compound-engineering-tier-3.3-glossary`

---

## Plan: M4 — Accreting Concept Glossary (Tier 3.3)
> Spec: specs/compound-engineering-adoption.md § M4 / Tier 3.3, plus delta addendum specs/compound-engineering-m4-concept-glossary.md (both live untracked on the main clone, per the convention noted at the top of this file)
> Branch: feat/compound-engineering-tier-3.3-glossary (worktree off worktree-m3-typed-learning-store)

[x] Setup: worktree on `feat/compound-engineering-tier-3.3-glossary` off `worktree-m3-typed-learning-store` @ 53db64d; baseline `tests/run.sh` green (15 files)
[x] TDD: doc-conventions asserts both glossary seeds exist, define the six terms (tier, gate, register, drift, ceiling, store) as anchored bullets, and carry exactly one legal-state sweep marker (template must be `pending`) -> `tasks/concepts.md` + `project-template/tasks/concepts.md` written
[x] TDD: test-install-sh asserts `copy_if_missing "tasks/concepts.md"` -> install.sh seeds the glossary
[x] TDD: doc-conventions asserts both `learn/SKILL.md` copies reference `tasks/concepts.md` + the pending marker -> /learn Step 7 concept capture (side effect, refine-in-place, seed-shape bootstrap when absent)
[x] TDD: doc-conventions asserts both `memory-maintain/SKILL.md` copies carry Phase 0, both marker states, and the pruning rule -> Phase 0 bootstrap sweep fires from the light pass (exempt from the empty-store no-op), pruning in Phase 4, glossary line in Output
[x] TDD: doc-conventions asserts CLAUDE.md Key Directories + project-template/CLAUDE.md list the glossary -> both registered; Session Start Checklist gained the read path (consult glossary for unknown project terms)
[x] Evidence: Phase 0 dogfooded on this repo — swept 10 project terms into `## Project vocabulary`, marker flipped to `> Sweep: done 2026-08-13`; second run: `grep -c '^> Sweep: pending'` = 0 → no-op. README scaffold lists (post-init, manual copy, repo tree) and template `.gitattributes` exclusion list updated after critic review.
[x] TDD: full `tests/run.sh` green + parity green; critic dispatched (ceiling tier), verdict HOLD → all MUST-FIX/SHOULD-FIX findings fixed (empty-store/Phase 0 interaction, legal-state marker guard, README drift, CLAUDE.md wording, .gitattributes, read path); re-run green

## Session Summary — 2026-08-13 [53db64d..HEAD]
- Completed: 8 tasks (M4 Tier 3.3 — glossary, bootstrap sweep, capture/prune hooks, guards, dogfood evidence)
- Pending: 0 tasks
- Carry-forward: stacked on unmerged `worktree-m3-typed-learning-store` — M3 PR merges first, then this branch's PR retargets/merges


## Plan: Codex Harness Adapter
> Spec: specs/codex-harness-adapter.md
> Branch: agent/codex-harness-adapter-pr

[x] TDD: `tests/test-codex-install.sh` covers isolated installation, personal-content preservation, valid rendered agents/hooks, and idempotence -> add the failing integration/static test
[x] TDD: renderer tests cover shared AGENTS block, Markdown-agent-to-TOML conversion, and hooks JSON merge -> add the stdlib renderer/merger
[x] TDD: Codex adapter installs canonical skills, agents, hooks, and managed global rules from any working directory -> add `scripts/install-codex.sh` and hook adapters
[x] TDD: project scaffold test requires neutral `AGENTS.md` -> add template seed and copy it from the git `post-init` hook
[x] TDD: documentation test requires Codex setup/update instructions and harness-neutral language -> update README and installer help text
[x] Full validation: `bash tests/run.sh`, shell syntax checks, Python compile/parse checks, and security review of changed scripts

## Session Summary — 2026-08-14
- Completed: 6 tasks (Codex harness adapter, renderer, hooks, neutral project seed, docs, and validation)
- Pending: 0
- Carry-forward: review and merge the draft PR

## Plan: Review Context Contract
> Spec: specs/review-context-contract.md
> Base: origin/master @ 23f0d7d — branch feat/review-context-contract (worktree)

[x] TDD: `tests/test-review-context.sh` fails on master because `CLAUDE.md` has no § Review Dispatch Contract -> add the section with the 7-item payload table and the absent-vs-empty rule
[x] TDD: same test asserts the intent-shared / conclusions-withheld split names Independence Accounting as the reason -> add the split to the new section
[x] TDD: test asserts a finding at `75` must name its dependency and that an unnamed one reads as `50` -> extend `CLAUDE.md` § Finding Model
[x] TDD: test asserts the verification path (read dependency -> promote to 100 with evidence, drop, or hold and say what stopped it) and that verification-promotion is NOT agreement-promotion -> extend § Finding Model
[x] TDD: test asserts all four dispatch sites (wrap-up Step 4 + Parallel Code Review, quality-gate Phase 3, software-design-expert-review Phase 2) cite the contract by section name, in BOTH trees -> edit 3 skills canonical-first, then byte-identical copy
[x] TDD: test asserts each dispatch site states the absent-vs-empty rule for spec and deferrals -> add the payload lines at each site
[x] TDD: test asserts all 8 reviewer persona files (4 personas x 2 trees) carry a `## Context Intake` section naming given / fetch-yourself / out-of-scope -> add the section; `tests/test-agents.sh` must stay green (frontmatter untouched)
[x] TDD: `tests/test-model-tiers.sh` §8 widened to fail when a Ceiling role is pinned in a bare table cell -> widen the guard, then unpin `auto-improve`'s design-review charter to *ceiling* (both trees)
[x] TDD: mutation probes — delete the contract section, remove one site's pointer, remove one persona's intake, delete the anchor-75 rule; each must turn the suite red. Commit first, then probe -> record counts in the spec
[x] TDD: `bash tests/test-skill-parity.sh` green over every edited skill; `bash tests/run.sh` green with assertion count recorded against the 1108-assertion baseline -> run both, then `/quality-gate`

---

## Session Summary — [2026-08-18] [25999b1..f96255d]
- Completed: 0 planned tasks (direct bug-fix request; no /plan run this session)
- Pending: 0 — the plan blocks above belong to earlier worktrees and are all closed
- Carry-forward: decide whether the no-session_id guard fallback should exist at all
  (the critic argued for "no session_id -> just print", since the guard suppresses a
  cosmetic duplicate but fails by losing a functional banner); ~290 unreaped
  `.ccw-session-start-*` sentinels in /tmp with nothing reaping them

---

## Plan: UTF-8 at every Python IO boundary
> No /plan — direct user bug report: `generate-presentation.py` decoded stdin with the platform default codec.
> Branch: claude/vibrant-chaum-2cad9b (worktree off master @ 25999b1)

[x] Fix the reported stdin decode in both mirror copies -> `tests/test-html-presentation.sh` (26 assertions) pins the `--markdown -` path, and asserts PYTHONIOENCODING took effect so the pin cannot go vacuous
[x] Review-driven: `utf-8-sig` on both markdown branches -> a retained BOM defeated the H1 match and silently dropped the title and every section at exit 0
[x] Review-driven: pin stdout in `generate-presentation.py`; explicit encoding on `visual-render.py`'s subprocess capture (`text=True` left `result.stderr` as `None` on a failing child)
[x] Learnings: encoding-class pattern doc

## Session Summary — 2026-08-18 [25999b1..HEAD]
- Completed: 3 items (1 as reported, 2 surfaced by the review gate)
- Pending: 0
- Carry-forward: none. This branch also fixed the Codex adapter and diagnosed the
  session guard; both were superseded by #66 and #68, which landed on master first.
  Taken from upstream at merge — see the history entry for what my diagnosis got wrong.
## Plan: Lightpanda Optional E2E Browser Tier
> Spec: specs/lightpanda-browser-adoption.md
> Branch: `feat/lightpanda-e2e-tier` off master @ 25999b1 (PR #65 merged, so
> `tests/test-syncable-paths.sh` is now on master — Task 2's dependency is satisfied
> and its red-then-green runs normally).
> Status: Complete — rebased onto master @ 8828ba0 (#66/#67/#68 landed mid-session,
> which cleared the pre-existing Windows red baseline this plan's Task 8 was blocked on)
>
> **Decision:** lightpanda enters as an optional, capability-scoped e2e tier gated by a
> fail-closed AC classifier. agent-reach declined (spec §2). `/start-qa` and `install.sh`
> unmodified.

[x] Setup: branch `feat/lightpanda-e2e-tier` created off master @ 25999b1

## Task 1 — Runbook: `.claude/browsers/lightpanda.md` (AC-1)

[x] TDD: new `tests/test-browser-runbook.sh` asserts `.claude/browsers/lightpanda.md` exists; frontmatter carries `name`, `display_name`, `fidelity`, `detect_command`, `mcp_command`, `platforms`, `license`; `name` equals the filename stem; `fidelity` is `dom` or `full`; body contains the capability-ceiling tokens (`screenshot`, `Canvas`, `Flexbox`, `Service Worker`), the Windows gap, `AGPL-3.0`, the pinned release tag, and the MCP registration one-liner -> write the runbook per spec §4.6: per-platform install (Homebrew, AUR, `.deb`, pinned `0.3.6` binary, Docker), registration command, ceiling from §1.1, Windows→WSL2/Docker note, AGPL unmodified-binary constraint, troubleshooting

## Task 2 — Declare `.claude/browsers/` syncable (AC-9)

[x] TDD: `tests/test-syncable-paths.sh` green with `.claude/browsers/` present in all seven enumerations, and red when any single one is perturbed (demonstrate by temporary edit + revert, capture output); INVARIANT 2 resolves the runbook to a declared syncable path -> add `.claude/browsers/` to the § Syncable Paths doc block, the `git diff --stat` arg list, and the full `git diff` arg list in `.agents/skills/sync/SKILL.md`; copy byte-identical into `.claude/skills/sync/SKILL.md`; add it to the drift-check arg list in `.claude/hooks/session-start.sh`

## Task 3 — Tier resolution + fail-closed classifier in `/verify --scope e2e` (AC-2, AC-3, AC-4 static)

[x] TDD: new `tests/test-e2e-classifier.sh` asserts BOTH tree copies of `verify/SKILL.md` contain the four-row resolution-order table (Chrome MCP, Playwright MCP, Lightpanda, none→STOP), both tier definitions (VISUAL, DOM-FUNCTIONAL), the fail-closed sentence **verbatim** (`when classification is uncertain, the AC is VISUAL`), the `BLOCKED` outcome row, and the Iron Law 1 cross-reference; `tests/test-skill-parity.sh` green -> edit `.agents/skills/verify/SKILL.md` Pre-Flight + Failure Handling per spec §4.1–§4.4, then copy byte-identical to `.claude/skills/verify/SKILL.md`

## Task 4 — Evidence records the backend and fidelity (AC-6)

[x] TDD: `tests/test-e2e-classifier.sh` asserts both tree copies' Evidence Format block includes a `Browser:` line carrying backend and fidelity tier -> add the line to the `tasks/e2e-log.md` template in § Evidence Format, both trees byte-identical

## Task 5 — `lightpanda fetch` as an optional research fallback (spec §3.6)

[x] TDD: `tests/test-doc-conventions.sh` asserts both tree copies of `prd/SKILL.md` and `brainstorm/SKILL.md` name `lightpanda fetch` as an optional fallback for JS-heavy pages AND state that its absence is not an error -> add one paragraph to each skill's research step; four files, parity-copied

## Task 6 — Guards: agent-reach absent, `/start-qa` untouched (AC-10, AC-11)

[x] TDD: `tests/test-doc-conventions.sh` asserts no `agent-reach` token outside `specs/`, and that `.agents/skills/start-qa/SKILL.md` is byte-identical to its `.claude/` copy (base-commit check done via git diff, not encoded as a test — "base" has no meaning post-merge; the durable pin is that start-qa never routes to the DOM tier) -> assertions only; no implementation

## Task 7 — Behavioural evidence for AC-4 (the one static tests cannot cover)

[x] TDD: `tasks/e2e-log.md` gains an entry with `Browser: lightpanda 0.3.6 (DOM-tier)` showing one VISUAL AC as `BLOCKED` and one DOM-functional AC as `PASS`, run with lightpanda as the only available backend -> run against a throwaway two-AC spec via the pinned Docker image (no Windows binary exists). **If lightpanda cannot be run in this environment, mark this task BLOCKED and report it — do not mark AC-4 satisfied on static assertions alone**

## Task 8 — Full suite + quality gate

[x] TDD: `bash tests/run.sh` green with a 600s timeout; new test-file count recorded against the Setup baseline -> run, fix fallout, then `/quality-gate`; verify every AC in `specs/lightpanda-browser-adoption.md` including the AC-4 evidence from Task 7

## Session Summary — [2026-08-18] [8828ba0..HEAD]
- Completed: 8 planned tasks (all of the Lightpanda plan above) + 1 review-driven fix
- Pending: 0
- Carry-forward: `.claude/deployments/` has the same syncable-path gap `.claude/browsers/`
  just closed, and `/verify --scope deployment` names `tasks/deployments/<service>.md`
  while the directory in this repo is `.claude/deployments/` — a pre-existing mismatch,
  left alone under the orphan rule rather than folded into this change. Lightpanda `0.3.7`
  is published upstream; the pin stays at `0.3.6`, the version AC-4 evidence was taken on.

---

## Plan: Provider-Agnostic Task Registry
> Spec: specs/task-registry.md
> Branch: feat/task-registry-provider-adapters off master @ 2022b10
> Note: implementation lives under `.agents/skills/task-registry/scripts/` because
> `tests/test-syncable-paths.sh` INVARIANT 2 requires every skill-named asset to sit
> inside a syncable path — repo-root `scripts/` is not one.

[x] TDD: `tests/test-task-registry.sh` model block — canonical kinds/statuses/priorities accepted, unknown value rejected by name, IDs never provider numbers -> `scripts/registry/model.py`
[x] TDD: config block — ini config parsed from `docs/task-tracking.md`, pointer indirection from AGENTS.md/CLAUDE.md/.claude/project.md, selection precedence (explicit > github+gh auth > local; jira never implicit) -> `scripts/registry/config.py`
[x] TDD: index block — compact row parse/render, `<!-- task-id: -->` identity, legacy checkbox-only rows, malformed row reported with file:line, byte-preserving rewrite -> `scripts/registry/index.py`
[x] TDD: provider contract block run against all three adapters — capabilities declared, write gate refuses without `--apply`, dependency reported native vs inferred -> `scripts/registry/providers/base.py` + `__init__.py`
[x] TDD: local adapter — fully offline create/update/close/comment/parent/dependency, detail files under the configured dir -> `scripts/registry/providers/local.py`
[x] TDD: github adapter with a `gh` PATH mock — label→kind/priority mapping, every label preserved, open/closed→open/done, no status-label creation, no title-only matching, dry-run vs apply -> `scripts/registry/providers/github.py`
[x] TDD: jira adapter against a stdlib fake HTTP server — auth, capability degradation, credential/Authorization redaction on failure, loud offline write failure -> `scripts/registry/providers/jira.py`
[x] TDD: reconcile/frontier block — unlinked local, unlinked external, stale/completed/superseded specs, duplicate detection without title equality, idempotence, summary-first output, `show` progressive disclosure, partial-failure exit 1 -> `scripts/registry/reconcile.py`
[x] TDD: migration block against an ascii_video_pipeline-shaped fixture — classification, ID generation, spec links, grouping (no issue per historical checkbox), operational work preserved, dry-run report, audit trail -> `scripts/registry/migrate.py`
[x] TDD: CLI block — `reconcile|publish|pull|frontier|show|migrate`, exit codes 0/1/2, dry-run default -> `scripts/task-registry.py`
[x] TDD: docs block — SKILL.md, configuration/migration/progressive-disclosure references, `docs/task-tracking.md` template, GitHub/Jira/local examples, offline+auth troubleshooting, kind guidance, index-not-source-of-truth statement
[x] TDD: integration block — CLAUDE.md skills table + Task Tracking pointer, README, session-start banner, `/plan` `/build` `/verify` `/quality-gate` `/wrap-up-session` route through the registry and call no provider directly
[x] TDD: parity — `tests/test-skill-parity.sh` green over byte-identical `.claude/skills/task-registry/`
[x] Full validation: `bash tests/run.sh` green, security review of the new scripts, `/quality-gate`

## Session Summary — 2026-08-29 [2022b10..HEAD]
- Completed: 14 tasks (three-layer task registry, three adapters, CLI, migration, docs, integration)
- Pending: 0
- Evidence: `bash tests/run.sh` green — 23 test files; `tests/test-task-registry.sh` 202
  assertions; `tests/test-doc-conventions.sh` 388; parity 66; invocation chain 30.
  Mutation probes: title-matching restored -> 1 failure, write gate forced open -> 4,
  redaction disabled -> 1; all restored green. ruff clean, flake8 clean at the repo's
  existing line-length style. Migration dry-run against this repository: 60 rows,
  46 completed-history, 14 active, 1 proposed group, nothing written.
- Carry-forward: IDs minted from long TDD row titles are truncated at 80 chars and read
  poorly (`provider-agnostic-task-registry.tdd-jira-adapter-against-a-stdlib-fake-http-serv`).
  Migration is a proposal a human edits, so this is cosmetic — but a shorter minting
  strategy (leading words plus a hash) would be an improvement.


---

## Plan: Task Registry — Review Gate Remediation
> Spec: specs/task-registry.md
> Follows the `critic` and `security-reviewer` gates run against PR #76.
> Scope: fix every finding, add a regression test per fix, replace the PR.

[x] Security: strip `Authorization`/`Cookie` on cross-origin redirects — `_CredentialStrippingRedirectHandler` + a single built opener in `HttpTransport` -> `providers/jira.py`
[x] Security: reject a reference id that could become a second `gh` flag, and pass `--` before every positional -> `index.py` `REF_ID_RE`, `providers/github.py` `_number`
[x] Security: validate and percent-encode Jira issue keys before they become a request path -> `providers/jira.py` `_key`
[x] Security: redact the Jira base URL (which can carry userinfo) everywhere it is printed; mask the whole Authorization value, not just the scheme word -> `providers/jira.py`, `redaction.py`
[x] Security: a top-level handler that scrubs an unexpected traceback before printing it, and still exits 1 -> `task-registry.py`
[x] Security: confine the config pointer, `index_path`, and `local_detail_dir` to the project root -> `config.py` `confine`
[x] Security: `require_write_approval` is a floor — a repository file may raise it, only `TASK_REGISTRY_TRUSTED_CONFIG` lowers it -> `config.py`
[x] Security: refuse Basic auth over plain http to a remote host; loopback and an env override remain -> `config.py` `require_secure_transport`
[x] Correctness: a foreign vocabulary value defaults and reports instead of raising -> `model.py` `safe_task`
[x] Correctness: the local provider merges an incoming record with what is on disk — no more deleted Summary/Acceptance Criteria/kind, and loose prose survives -> `providers/local.py`
[x] Correctness: never overwrite a local `in_progress`/`blocked` from a provider that cannot express it -> `reconcile.py` `_reconciled_status`
[x] Correctness: a declared config section layers over the shipped defaults instead of replacing them -> `config.py`
[x] Correctness: migration rewrites `blocked-by:` prose to the id it minted, and reports what it could not resolve -> `migrate.py`
[x] Correctness: `publish` reports rows it skipped for having no id, and never claims agreement while skipping -> `reconcile.py`
[x] Correctness: minting is seeded with the ids already in the index, so it cannot collide -> `migrate.py`
[x] Correctness: approval gates external writes only; the offline provider is not blocked by a message about a tracker -> `providers/base.py` `WriteGate.authorize`
[x] Correctness: `allow_label_creation` actually creates the label through `gh label create`; AC-6 corrected -> `providers/github.py`, `specs/task-registry.md`
[x] Correctness: `migrate --apply` exits 1 when rows could not be read -> `task-registry.py`
[x] Correctness: a truncated provider read refuses to publish rather than duplicating -> `providers/github.py`, `providers/jira.py`, `reconcile.py`
[x] Correctness: `_link_dependencies` sees the tasks published this run, and skips links already recorded -> `reconcile.py`
[x] Correctness: `frontier` orders by dependency, reports cycles, and reports dependencies naming no task -> `reconcile.py` `_dependency_order`
[x] Correctness: an unbalanced metadata marker never eats the body — the innermost pair is the one replaced -> `model.py`
[x] Correctness: a title beginning with a dash is no longer trimmed -> `index.py`
[x] Design: URL and reference-label classification moves behind the provider registry -> `providers/base.py`, `providers/__init__.py`
[x] Design: row indentation is preserved on rewrite -> `index.py`, `reconcile.py`
[x] Design: the closed-plan marker is configurable and its absence is reported -> `migrate.py`, `config.py`
[x] Design: the spec lookback stops at its own heading block -> `migrate.py`
[x] Design: dead `Registry.backlog_index()` removed; `_note`/`limitations` pulled up to the base provider -> `reconcile.py`, `providers/base.py`
[x] Tests: the `gh` mock validates `--label` against `labels.json` and refuses a positional without `--`; the fake Jira site can redirect and echo auth
[x] Tests: weak assertions replaced — `missing-id` counted rather than pattern-excluded, idempotence proves the first apply changed something
[x] Tests: `tests/test-skill-parity.sh` skips git-ignored paths so build residue is not read as drift
[x] Tests: section 12 — one regression block per defect, each verified to fail without its fix

## Session Summary — 2026-08-29 [review remediation]
- Completed: 32 fixes across 8 security findings, 22 critic findings, and 1 self-found defect.
- Evidence: `bash tests/run.sh` green — 23 test files. `tests/test-task-registry.sh` grew
  202 -> 277 assertions. flake8 clean at the repo's existing style, ruff clean.
  24 mutation probes run: reverting each fix produces 1-7 failing assertions, so every
  fix has a test that bites. Migration dry-run against this repository: 60 rows, nothing
  written, exit 0.
- Two defects were found while writing the regression tests rather than by either gate:
  a malformed Jira base URL escaped as an unredacted `InvalidURL`, and pattern 1 of the
  redactor masked the word `Basic` while leaving the payload beside it.
- Carry-forward (unchanged): minted ids from long TDD row titles read poorly; a shorter
  minting strategy would be an improvement, and migration output is a human-edited
  proposal, so it stays cosmetic.

---

## Plan: pstack Verification Skill Integration
> Spec: specs/pstack-verification-skill-integration.md
> Upstream: cursor/plugins pstack @ 68836ddaf5697224520f1847d90cdb90ca8babaa

[x] TDD: `tests/test-verification-skill-integration.sh` rejects missing or invalid creator/maintainer frontmatter, required workflow sections, feature-map reference headings, unsafe process-name cleanup, and absent provenance -> add the focused red contract test, the full pstack MIT notice in `THIRD_PARTY_NOTICES.md`, and README source credit
[x] TDD: creator contract assertions require instructions that generate canonical `.agents/skills/verify-<app>/` output mirrored byte-identically to `.claude/skills/`, grounded Launch/Doctor/Drive/Evidence/Cleanup/Helpers sections, a declared surface/capability ceiling, a 3-5 entry indexed map, and creation-time proof whose evidence survives cleanup -> adapt `create-verification-skill` and its reference assets from the pinned upstream revision
[x] TDD: maintainer contract assertions require full mode's index/source/live coverage and exact `clean|changed|blocked` outcomes plus idempotent `--scope changed` reconciliation that consumes session intent/diff, edits only the verification skill on the active branch, skips internal-only changes, and never opens its own PR -> adapt `maintain-verification-skill`
[x] TDD: `tests/test-e2e-classifier.sh` fails when project-local resolution, ambiguity STOP, absent-skill fallback, or capability-ceiling enforcement is removed -> integrate exactly-one `verify-*` discovery into `/verify --scope e2e` without weakening the Chrome/Playwright/Lightpanda fail-closed classifier
[x] TDD: `tests/test-skill-invocation-chain.sh` fails unless both skill trees route user-facing changes from `/build` and `/wrap-up-session` through `/maintain-verification-skill --scope changed` before `/verify --scope e2e`, and the Stop hook remains free of maintenance invocation -> add the two idempotent lifecycle handoffs and backward-compatible no-skill recommendation
[x] TDD: documentation/distribution assertions require both skills and the two-speed update mechanism in README, CLAUDE.md, and the session-start banner while existing install/sync paths remain sufficient -> update only those discoverability surfaces and preserve canonical/compat parity
[x] TDD: `tests/test-upstream-drift.sh` uses temporary local Git repositories to cover schema validation, multiple registered sources, whole-repo and path-scoped clean/drift detection, unavailable refs/remotes, rewritten history, aggregate checking, silent success, and bounded failure evidence -> add `.github/upstreams.json` with the pinned pstack import, a stdlib-plus-Git `scripts/check-upstream-drift.py`, and a read-only weekly/manual `.github/workflows/check-upstream-drift.yml` that reports non-clean results without applying updates
[x] TDD: mutation probes make each load-bearing contract fail, including a registry baseline/path mutation; `bash tests/test-skill-parity.sh` and `bash tests/run.sh` pass with recorded counts -> run focused mutations, full validation, `/quality-gate`, and acceptance-criterion evidence review

Build evidence: 10/10 mutation probes rejected after tightening one false-green
heading assertion. Wrap-up review resolved all 13 findings and strengthened the
focused gates to 82 verification-integration assertions, 64 upstream-drift
assertions, and 51 parity assertions. Initial quality gate: APOSD GO.

## Session Summary — [2026-08-29] [2022b10..HEAD]
- Completed: 8 planned tasks
- Pending: 0
- Carry-forward: none; wrap-up review fixes completed 2026-08-30

---

## Plan: Living Spec Reconciliation During Wrap-Up
> Spec: specs/living-spec-reconciliation.md
> Branch: Joaovsales/wrap-u (Orca-managed worktree off master @ 907ac6d)
> Baseline: `bash tests/run.sh` green — 26 test files

[x] TDD: `tests/test-living-spec-reconciliation.sh` requires workflow-created specs to use valid `implementation_paths` frontmatter, factual `## Implementation Paths` prose, ordinary-bullet Acceptance Criteria, and one exact `> Spec: specs/<name>.md` plan association -> update `/plan`, `/brainstorm`, and `specs/README.md`
[x] TDD: change-set fixtures cover committed, staged, unstaged, added, modified, copied, renamed, and deleted paths while retaining both rename endpoints -> add a stdlib-only wrap-up reconciliation helper that captures one immutable pre-reconciliation snapshot
[x] TDD: path-matcher fixtures pin whole-path case-sensitive `*`, `?`, and `**` semantics and reject malformed frontmatter, absolute paths, traversal, and unsupported glob syntax with spec/value evidence -> implement metadata parsing, validation, and matching in the reconciliation helper
[x] TDD: candidate-discovery fixtures always include the completed plan's exact spec association, prefer metadata over legacy `## Files Likely Involved`, retain rename/deletion reasons, support overlapping specs, and deduplicate without losing reasons -> implement deterministic ordered discovery
[x] TDD: semantic reconciliation fixtures require exactly one `updated|unchanged|deferred` outcome per candidate for behavior change, unrelated shared-file change, and insufficient evidence without a keyword classifier -> add the evidence-reading and outcome protocol to `/wrap-up-session`
[x] TDD: updated legacy-spec fixtures add accurate metadata, replace prospective path prose, convert AC checkboxes to bullets, remove stale/change-log language, and preserve unrelated accurate content while unchanged legacy specs remain byte-identical -> add the legacy migration contract to reconciliation
[x] TDD: task-registry fixtures create, update, and reopen one `research` task keyed by `spec-reconciliation.<normalized-full-spec-path>` with required evidence, revision, criteria, and compact-index linkage -> add a provider-neutral idempotent reconciliation-task upsert
[x] TDD: deferred-publication fixtures use the configured external provider only when its existing write policy permits, otherwise persist one canonical local Markdown record and report publication pending without duplicate canonical bodies -> integrate local fallback orchestration through `/task-registry`
[x] TDD: invocation-order assertions place snapshot, task-register update, discovery, reconciliation, and deferral persistence before verification-map maintenance, security, review, and deterministic tests, with downstream failures blocking both code and spec commits -> integrate reconciliation into `/wrap-up-session`
[x] TDD: review/PR assertions pass every relevant spec and stripped AC list through `CLAUDE.md`, `project-template/CLAUDE.md`, and wrap-up review payloads, and link every deferred task in the PR while retaining the introduced-this-session boundary -> generalize downstream context from one spec to many
[x] TDD: summary/parity assertions cover zero-candidate and all-unchanged success, bounded candidate/updated/unchanged/deferred counts and paths, and byte-identical canonical/compatibility skill trees -> finish reporting, mirror `.agents/skills/**` changes to `.claude/skills/**`, and run the full suite

## Session Summary — 2026-09-02 [907ac6d..c000b04]
- Completed: 11 tasks (all of the Living Spec Reconciliation plan)
- Pending: 0
- Carry-forward: one `owner: human` design question from the adversarial critic —
  whether an `unchanged` reconciliation outcome should require evidence beyond
  naming the spec it compared. Answered in part (the report now lists candidate
  and unchanged paths, per the AC); the residual is a contract change to
  `specs/living-spec-reconciliation.md` and needs a human decision.
- Resolution: put to the user at the Step 7 gate and approved — the current
  contract stands. Shipped as c000b04, PR #88. The gate defect the finding
  exposed is filed as `review-gate.define-finding-resolution`.
- [ ] Define finding resolution per owner, and remove the owner carve-out from every gate <!-- task-id: review-gate.define-finding-resolution --> — The word "unresolved" is load-bearing in four commit gates and defined nowhere, so each gate re-derives it and two deri… ([review-gate.define-finding-resolution](tasks/details/review-gate.define-finding-resolution.md))
- [x] /sync is non-deterministic: retired-vs-project-specific is re-judged every run <!-- task-id: sync.deterministic-retirement --> — record the keep/retire decision as data (`.claude/sync-keep`) so `/sync` is reproducible instead of re-judged per run ([#89](https://github.com/Joaovsales/jplugin-agentic-development/issues/89))
- [ ] Collapse the seven-region syncable-path enumeration into script-owned data <!-- task-id: sync.syncable-paths-single-source --> — the list is retyped in seven regions across three files; deterministic retirement made it machine-read for the first time ([sync.syncable-paths-single-source](tasks/details/sync.syncable-paths-single-source.md))
- [ ] Extract the shared path-glob matcher out of spec-reconcile.py <!-- task-id: glob-matcher-shared-module --> — two scripts implement the same three-token whole-path glob semantics; they agree today, which is the dangerous state ([glob-matcher-shared-module](tasks/details/glob-matcher-shared-module.md))
- [ ] A syncable root retired upstream leaves permanent orphans <!-- task-id: sync.retired-root-orphans --> — retirement works within declared roots; removing a whole root from the doc block leaves the project's copy forever ([sync.retired-root-orphans](tasks/details/sync.retired-root-orphans.md))
- [ ] Bound the retirement blast radius before --apply deletes <!-- task-id: sync.retire-blast-radius-cap --> — the plan is printed but nothing acts on it; a cap bounds defects that inflate the set ([sync.retire-blast-radius-cap](tasks/details/sync.retire-blast-radius-cap.md))
- [ ] A root retired upstream turns a valid sync-keep into a hard failure <!-- task-id: sync.stale-root-blocks-retirement --> — a pattern naming a root the template dropped exits 1 and blocks every unrelated retirement ([sync.stale-root-blocks-retirement](tasks/details/sync.stale-root-blocks-retirement.md))
- [ ] Adjacent unbounded quantifiers make the glob matcher hang <!-- task-id: glob-matcher-redos --> — `**`/`*?` runs compile to catastrophic backtracking; fix belongs with the shared-matcher extraction ([glob-matcher-redos](tasks/details/glob-matcher-redos.md))
- [ ] Step 6.4 deletes after Step 6 already asked the user to commit <!-- task-id: sync.retirement-lands-after-commit --> — pre-existing ordering, amplified now the deletion set is computed rather than four fixed paths ([sync.retirement-lands-after-commit](tasks/details/sync.retirement-lands-after-commit.md))
- [x] Bootstrap projects never remove the four legacy retired skills <!-- task-id: sync.bootstrap-skips-legacy-retirements --> — the only mechanism that deleted tdd/deslop/simplify/verify-e2e is gone; the one case the new design is strictly weaker ([sync.bootstrap-skips-legacy-retirements](tasks/details/sync.bootstrap-skips-legacy-retirements.md))
- [x] A root legitimately emptied upstream disables the whole retirement pass <!-- task-id: sync.emptied-root-blocks-retirement --> — assert_roots_present conflates a wrong source with a root emptied upstream ([sync.emptied-root-blocks-retirement](tasks/details/sync.emptied-root-blocks-retirement.md))
- [ ] The bootstrap candidate protects a generated skill file-by-file <!-- task-id: sync.candidate-emits-per-file-patterns --> — one exact rule per file, so anything added to a project-local skill is a fresh retire candidate ([sync.candidate-emits-per-file-patterns](tasks/details/sync.candidate-emits-per-file-patterns.md))

<!-- route-lane:begin -->
## Routed lane — gated-at-plan-and-pre-push

[ ] prelude: skip: not needed for this kind
[ ] /plan (auto-confirm: no; wait for approval)
[ ] /build (runs /quality-gate on completion)
[ ] route radius tripwire: finalize_route before verification or push
[ ] /verify (evidence: tests)
[x] reviewers: code-reviewer, security-reviewer — round 2 on the fixed diff: 1 MUST-FIX + 1 HIGH reproduced and fixed, 5 more applied, 4 filed; 191 assertions
[ ] /wrap-up-session (wait at pre-push gate)
<!-- route-lane:end -->

---

## Plan: Deterministic Retirement in /sync
> Spec: specs/sync-deterministic-retirement.md
> Task: sync.deterministic-retirement (#89) — routed gated-at-plan-and-pre-push
> Branch: Joaovsales/sync-is-non-deterministic-retired-vs-project-spe (worktree off master @ c3809a1)
> Baseline: `bash tests/run.sh` green before Task 1

[x] TDD: `tests/test-sync-retirement.sh` covers pattern parsing and validation — blank lines and `#` comments ignored; empty, absolute, `..`-traversing, backslash-separated, `[ab]`-globbed, and outside-every-syncable-root patterns each fail non-zero naming the offending pattern and its line, deleting nothing -> `.agents/skills/sync/scripts/sync-retire.py`: argparse CLI, `.claude/sync-keep` reader, pattern validator, `_pattern_to_regex`/`match_path` with `TODO(shortcut):` naming the spec-reconcile.py duplication
[x] TDD: syncable roots are parsed from the `## Syncable Paths` doc block — a fixture SKILL.md with an added root changes what is scanned, file roots (`CLAUDE.md`, `.claude/settings.json`) are excluded from retirement, a root absent from the project is empty rather than an error, and a root absent from the template is an error -> doc-block parser + root resolution
[x] TDD: `--from-ref` and `--from-dir` yield identical retirement sets for the same template content; supplying both or neither is a usage error (exit 2) -> template inventory via `git ls-tree -r --name-only` and via directory walk
[x] TDD: retirement set is project − template − allowlist; the default run lists every retire path in full (no truncation) and deletes nothing -> plan computation + report rendering
[x] TDD: `--apply` deletes exactly the retirement set, prunes emptied directories, prints the same full list before deleting, and leaves non-retired paths untouched -> apply step
[x] TDD: a path matched by `sync-keep` survives and is reported `kept: <path> (matched <pattern>)`; an empty `sync-keep` is distinct from an absent one and permits deletion -> allowlist wiring
[x] TDD: absent `.claude/sync-keep` retires nothing, reports `bootstrap: required` with every project-only path as a candidate, and under `--apply` writes `.claude/sync-keep.candidate` and never `.claude/sync-keep` -> bootstrap mode
      ↳ **amended on the user's call**: "retires nothing" left every bootstrap project keeping retired skills forever. Bootstrap now retires files that are byte-identical to something the template's history shows it shipped at that path, and holds everything else — customised, uncommitted, or same-name-different-file — as a candidate. Kept as an amendment rather than a rewrite: the original scope is what the earlier commits implement.
[x] TDD: two `--apply` runs against an unchanged template leave a byte-identical tree and the second reports zero retirements -> idempotency assertions over a tree hash
[x] TDD: two project branches with different project-only sets converge to the same harness path set against one template ref -> branch-independence fixture
[x] TDD: `.claude/sync-keep` appears in the § Syncable Paths never-sync list, the retirement pass is documented in the procedure, and it applies for options 1 and 2 but not 3 or 4 -> edit `.agents/skills/sync/SKILL.md`
[x] TDD: `tests/test-skill-parity.sh`, `tests/test-syncable-paths.sh`, `tests/test-skill-references.sh` and full `bash tests/run.sh` green -> byte-identical mirror of `.agents/skills/sync/**` into `.claude/skills/sync/**`
[x] Follow-ups filed as registry tasks + GitHub issues: (a) collapse the seven-region syncable-path enumeration into script-owned data; (b) extract the shared `match_path` glob matcher out of spec-reconcile.py -> `/task-registry upsert --apply` for each, then publish

## Session Summary — 2026-09-05 [c3809a1..101cdfc]
- Completed: deterministic retirement in `/sync` — all 12 planned tasks, plus two
  behaviour changes the user requested mid-session (bootstrap provenance; empty
  roots skipped rather than fatal).
- Review: 6 dispatched reviewers across two rounds this session. Round 2 found
  4 MUST-FIX (2 corroborated by both contexts) — all reproduced, fixed, and
  mutation-probed. 11 fixes total, every one pinned by an assertion that goes
  red when the fix is reverted.
- The load-bearing correction: bootstrap deleted on **path identity**, so a file
  the project authored at a colliding path — or a synced file it had edited, or
  one with uncommitted changes — was destroyed. Provenance is now content:
  the working-tree hash must match a blob the template actually shipped there.
- Tests: 33/33 files, 2911 → 315 assertions in the retirement suite alone.
- Pending: nothing carried forward from this plan.
