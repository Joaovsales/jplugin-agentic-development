# Active issue

- [x] task-registry publish: a legacy prose row becomes an issue with a truncated title and an empty body <!-- task-id: task-registry-publish-a-legacy-prose-row-becomes-an-issue-with-a-truncated-title-and-an-empty-body --> <!-- task-kind: bug --> — Preserve legacy multi-line plan detail, derive a clean title, and refuse unpublishable rows. ([#90](https://github.com/Joaovsales/jplugin-agentic-development/issues/90))

# Plan: sweep routines — `janitor` and `architect` producers, cheap-model consumers
> Spec: specs/sweep-routines.md (supersedes specs/auto-improve-findings-to-registry.md, deleted)
> Branch: Joaovsales/routine-issue-creation-fix (worktree)
> Why: nothing in the routine contract produces issues; `/auto-improve` conflates discover+fix and sinks findings to backlog.md (downstream PR #407: 15 findings, 0 issues)

- [x] TDD: `tests/test-sweep-routines.sh` RED — static assertions for AC1, AC3, AC5, AC6, AC7, AC8, AC9, AC10 across both trees (sourcing `tests/lib.sh`); confirm it fails today
- [x] TDD: `tests/test-routine-branch.sh` + `tests/test-routine-selectors.sh` + `tests/test-routines-contract.sh` extended RED — producers in `CONTRACT_ROUTINES`, run-stamp round-trip, `PRODUCER_ROUTINES`, `select`/`claim` exit 2 naming "producer", selector for a producer refused at load, producer rows/spine/sections in routines.md (AC2 + AC1 shape)
- [x] TDD: AC2 GREEN -> `routine_branch.py` `CONTRACT_ROUTINES += ("janitor","architect")`, docstring on run stamp; `config.py` `PRODUCER_ROUTINES`, load-time refusal; `task-registry.py` `_select`/`_claim` producer refusal
- [x] TDD: AC1 GREEN -> `references/routines.md`: producer table rows, "Producer spine" section, `### \`janitor\` — steps` / `### \`architect\` — steps`, "never edit product code", `fix` 4a row → `/debug #N`
- [x] TDD: `tests/test-sweep-handoff.sh` RED (Python) -> AC4 GREEN: `model.Task.reproduction`/`proposed_fix`, metadata block round-trip, `upsert --reproduction`/`--proposed-fix`, github + jira `_seed_body` five sections in order (summary, Reproduction, Proposed fix, Acceptance Criteria, Evidence), local provider managed sections, `show` renders both; confirm `--derive-id` folds the title (extend if it only folds `--spec`)
- [x] TDD: AC3 GREEN -> write `.agents/skills/sweep/SKILL.md` (7 steps, Filing, Session record, edge cases) + `references/lens-janitor.md` + `references/lens-architect.md`
- [x] TDD: AC5 GREEN -> `.agents/skills/debug/SKILL.md`: issue-ref intake via `task-registry show`, candidate-one rule, unattended `blocked:` non-zero path replacing "ask the user" on routine branches, final phase writes `[ ] TDD:` tasks from the issue
- [x] TDD: AC6 GREEN -> `maintain-verification-skill/SKILL.md` inline source-wave fallback + sweep-owned shipping bullet; `software-design-expert-review/SKILL.md` `--scope tree` + inline fallback
- [x] TDD: AC7 GREEN -> `wrap-up-session/SKILL.md` linkage table producer row, `chore(sweep): <routine> <date>` title, `Refs` per filed issue read from the record
- [x] TDD: AC8 GREEN -> `references/routine-prompts/{README,janitor,architect,fix,improve,plan}.md` (<25 lines each, project-agnostic, one skill each; README: tiers, cadence, environment checklist)
- [x] TDD: AC9 GREEN -> delete `.agents/skills/auto-improve` + `.claude/skills/auto-improve` + `tests/test-auto-improve-rewire.sh`; repoint CLAUDE.md (skills table + repo-survey exception → `/sweep --routine architect`), README.md, session-start.sh, build SKILL.md, subagent-resilience.md; update loops in test-doc-conventions.sh, test-model-tiers.sh, test-review-context.sh, test-skill-invocation-chain.sh, test-routines-contract.sh
- [x] TDD: AC10 GREEN -> `task-registry/references/configuration.md` "Unattended routines" section
- [x] TDD: AC11 -> copy every edited/new file byte-identical into `.claude/`; `tests/test-skill-parity.sh` + `bash tests/run.sh` fully green; record output
- [x] Wrap-up: `/wrap-up-session` — commit `feat(routines): add janitor and architect sweep routines, retire /auto-improve`, push, open PR against master

---

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
[x] TDD: test asserts the verification path (read dependency → promote to 100 with evidence, drop, or hold and say what stopped it) and that verification-promotion is NOT agreement-promotion -> extend § Finding Model
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
- [x] Finalizing reviewers regenerates the lane block and discards its completion state — **obsolete: `finalize_route` deleted with `/route`** <!-- task-id: route.finalize-discards-lane-completion --> — a demotion re-renders the checklist from the playbook template, so every `[x]` reverts to `[ ]` at exactly the moment the record matters most ([route.finalize-discards-lane-completion](tasks/details/route.finalize-discards-lane-completion.md))
- [x] Bootstrap projects never remove the four legacy retired skills <!-- task-id: sync.bootstrap-skips-legacy-retirements --> — the only mechanism that deleted tdd/deslop/simplify/verify-e2e is gone; the one case the new design is strictly weaker ([sync.bootstrap-skips-legacy-retirements](tasks/details/sync.bootstrap-skips-legacy-retirements.md))
- [x] A root legitimately emptied upstream disables the whole retirement pass <!-- task-id: sync.emptied-root-blocks-retirement --> — assert_roots_present conflates a wrong source with a root emptied upstream ([sync.emptied-root-blocks-retirement](tasks/details/sync.emptied-root-blocks-retirement.md))
- [ ] The bootstrap candidate protects a generated skill file-by-file <!-- task-id: sync.candidate-emits-per-file-patterns --> — one exact rule per file, so anything added to a project-local skill is a fresh retire candidate ([sync.candidate-emits-per-file-patterns](tasks/details/sync.candidate-emits-per-file-patterns.md))


## Session Summary — 2026-09-04 [c3809a1..HEAD]
- Completed: issue #95 via `/debug`; corrected five documentation surfaces and added regression coverage.
- Pending: 0 tasks for issue #95.
- Carry-forward: none; the route radius prediction miss (declared scope overflowed, reviewer finalization ran before the runtime tripwire passed) was recorded in `tasks/route-decision.md`, which now carries the sync-retirement lane — see PR #96 for that record.

<!-- route-lane:begin -->
## Routed lane — gated-at-plan-and-pre-push

[x] prelude: skip: not needed for this kind
[x] /plan (auto-confirm: no) — spec + 12-task plan approved before any code
[x] /build — 12/12 tasks, /quality-gate run on completion
[x] route radius tripwire: finalize_route ran; recorded overflow — 4 paths outside declared scope (the spec, checkpoint, two task details). status: failed
[x] /verify (evidence: tests) — 33/33 files, 2937 assertions; e2e walkthrough in tasks/e2e-log.md
[x] reviewers: code-reviewer, security-reviewer — finalize_reviewers run: both completed, 0 unresolved, independently dispatched. Demoted on the tripwire, which had already failed (`critic` was also dispatched but is not in the decision's reviewer list, so it cannot be recorded there)
[x] /wrap-up-session — user authorized the pre-push gate; pushed, PR #104 open, CI green
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
- [ ] task-registry: provider-selection docs claim "no config = local + offline"; a GitHub remote actually selects github <!-- task-id: task-registry.provider-selection-docs-drift --> — Two documents state that a project without docs/task-tracking.md resolves to the offline local provider. The real order… ([#95](https://github.com/Joaovsales/jplugin-agentic-development/issues/95))

---

## Plan: Category Routines (specs/category-routines.md)

Detail lives in the spec (revision 3, internally reconciled). These rows are the
index.

- [x] Routine branch parser + formatter <!-- task-id: routines.branch-parser --> — TDD `tests/test-routine-branch.sh`: `parse_routine_branch` yields `(routine, issue)` for the four namespaced forms and `None` for `fix/2024-refactor`, `feature/2024-refactor`, `routine/fix/no-number`, `routine/fix/90`, `master`, `routine//90-x`; `format_routine_branch` round-trips every contract name -> `.agents/skills/wrap-up-session/scripts/routine_branch.py` + `.claude` parity copy (AC3, AC4, AC5)
- [x] Routine contract document <!-- task-id: routines.contract-doc --> — TDD `tests/test-routines-contract.sh` asserts four routines (three active, `build` marked deferred naming #97/#98), kind selectors, precedence chain, branch convention, and each active routine's mandatory step list with its non-skippable gates -> `.agents/skills/wrap-up-session/references/routines.md` + parity copy (AC8)
- [x] Selector vocabulary + claim label from configuration <!-- task-id: routines.selector-config --> — TDD: configured selector label absent upstream exits non-zero naming it; `tech-debt`/`documentation` resolve; claim label defaults to `in-progress` and an already-claimed issue is skipped -> extend the kind vocabulary and add a precedence + claim reader to task-registry config; update `templates/task-tracking.md` (AC12, concurrency, folded selector-vocabulary gap) (blocked-by: routines.contract-doc)
- [x] Wrap-up PR procedure convergence <!-- task-id: routines.wrap-up-pr --> — TDD `tests/test-routine-wrapup.sh`: PR creation described in exactly one place, Step 7 and Step 7.5 both reach it, `--draft` iff routine is `plan`, body carries `Closes #N` (`Refs #N` for `plan`), branch outside `routine/` keeps today's behavior -> `.agents/skills/wrap-up-session/SKILL.md` + parity copy (AC6, AC7) (blocked-by: routines.branch-parser)
- [x] Step ledger in todo.md and PR body <!-- task-id: routines.step-ledger --> — TDD: an executed step list with skipped rows and `skip: <reason>` appears in both sinks; silent omission fails the test -> wrap-up PR procedure + contract doc (AC9) (blocked-by: routines.wrap-up-pr)
- [x] Delete /route and its assertions <!-- task-id: routines.route-deletion --> — TDD: replace the three `/route` presence assertions in `tests/test-doc-conventions.sh`, drop `skills/route/SKILL.md` from `DISPATCH_SITE_FILES` in `tests/test-review-context.sh`, replace the `route_issue.py` assertion in `tests/test-skill-invocation-chain.sh`; coupling guard passes unmodified -> delete both route skill trees, `user-prompt-route.sh`, its `UserPromptSubmit` entry, the session-start banner line, `tests/test-route-{decision,hook,skill}.sh`, `specs/issue-lane-routing.md` (AC1, AC2, AC11)
- [x] Rewire /auto-improve Phases 3, 4, 5 <!-- task-id: routines.auto-improve-rewire --> — TDD: no phase names a routing engine or "materialized lane"; Phase 4 names its reviewer set directly and carries all seven Review Dispatch Contract items; one PR per run preserved -> `.agents/skills/auto-improve/SKILL.md` + parity copy (AC10) (blocked-by: routines.route-deletion)
- [x] Reconcile two learning-store documents <!-- task-id: routines.learning-reconcile --> — cite the routine contract instead of deleted paths -> `tasks/solutions/architecture/hard-gate-on-tasks-todo-md.md`, `tasks/solutions/patterns/consume-structured-records-before-rendering-human-summaries.md` (AC13) (blocked-by: routines.route-deletion)
- [x] Skill tables + full suite <!-- task-id: routines.tables-and-suite --> — no `/route` row in the `CLAUDE.md` or `README.md` skill tables; `bash tests/run.sh` green (AC14) (blocked-by: routines.auto-improve-rewire)

## Session Summary — 2026-09-05 c3809a1..HEAD (sha range closes at commit)
- Completed: 9 tasks — the whole Category Routines plan except the deferred `build` routine
- Pending: 1 in this plan (`routines.build-routine`, tracked as #98, blocked on #97)
- Branch: `analysis/simplify-routing`, outside the `routine/` namespace — so no routine
  step ledger applies to this session, per the contract's opt-in-by-shape rule
- Carry-forward: `build` needs #97's `blockedBy` provider capability first.
- Wrap-up review (4 dispatched passes) found 6 MUST-FIX, all fixed: the linked-PR
  exclusion failed *open* on a degraded `gh`; the claim label escaped the upstream
  vocabulary check; `known_labels()` conflated "unsupported" with "failed"; a
  backtick in `test-routine-step-ledger.sh` ran `tasks/todo.md` as a command
  instead of matching it; the AC12 vocabulary check lived only in `selectors`,
  which nothing invokes; and the claim label was read but never written.
- Shipped in response: `task-registry claim`, the contract's missing write. Both
  spec claims found unsound are now corrected in specs/category-routines.md, which
  was also migrated to `implementation_paths` frontmatter (Step 3.2).
- Skipped, deliberately (3 SHOULD-FIX, all needing a routine host that does not yet
  exist): `/auto-improve` does not run the routine spine; `select` emits prose with
  no machine-readable form; no assertion pins that categorization lives only in the
  contract. All three belong with #98.

## Deferred — tracked externally, not part of this build

Not executed by `/build`. Listed so the frontier shows the real dependency graph.

- [ ] task-registry: github provider reports native_hierarchy/native_dependencies false, but gh now exposes parent, subIssues, blockedBy and blocking <!-- task-id: task-registry.github-native-hierarchy-and-dependencies --> — The github provider hardcodes native_hierarchy=False and native_dependencies=False, so link_parent and add_dependency d… ([#97](https://github.com/Joaovsales/jplugin-agentic-development/issues/97))
- [ ] routines: implement the `build` routine (deferred from the first category-routines PR) <!-- task-id: routines.build-routine --> — specs/category-routines.md defines four routines. Three (plan, fix, improve) ship in the first PR. `build` is deferred… ([#98](https://github.com/Joaovsales/jplugin-agentic-development/issues/98)) (blocked-by: task-registry.github-native-hierarchy-and-dependencies)

## Session Summary — 2026-09-06 [fb41c7a..18ac574]
- Completed: 0 planned tasks — `/debug 82` session, no todo plan; fix shipped on
  branch `Joaovsales/task-tracking-config-a-pointer-to-a-missing-file`
- Pending: 0 active; 2 deferred externally (#97, #98) unchanged
- Carry-forward: none from this session
- [x] route/debug: bug lanes should enter TDD directly after root-cause confirmation <!-- task-id: route.debug-bug-lane-plan-gate --> — resolved by PR #105: `/route` was deleted and the `fix` routine now runs `/debug` directly into `/build`/TDD ([#107](https://github.com/Joaovsales/jplugin-agentic-development/issues/107))

## Session Summary — 2026-09-07 [bbef230..7aedccb]
- Completed: 1 bug fix — issue #90 preserves complete legacy-row detail and clean
  provider titles through publication and canonical rewrite.
- Pending: 0 tasks from this session; issue #107 was closed as superseded by PR #105.
- Carry-forward: pre-existing task-registry reconciliation findings remain outside
  this session's scope.

## Session Summary — 2026-09-07 [d1b4b14..db07dcd]
- Completed: 13/13 plan tasks for specs/sweep-routines.md plus the wrap-up row;
  rebased onto #110 before push (register conflicts only)
- Pending: 0 active; 2 deferred externally (#97, #98) unchanged
- Carry-forward: `/plan` has no issue-reference intake (prompts hand it
  `task-registry show` output by hand); follow-up scope call for a human

---

## Plan: Phase A — the `workflow` command (specs/workflow-routing.md)

> Spec: `specs/workflow-routing.md` (R2, R3, R6). Handover: `tasks/handover-workflow-routing.md` — **read it first.**
> **Gate: satisfied.** #82 merged as PR #109 (`bbef230`, 2026-09-07). This branch is off `master` at that commit.
> Phase B (Cut 1) and Phase C (Cut 2) are deliberately **not** rows here — one phase per `/build`, one PR per phase, because the spec's rollback story requires each cut to be a single revertable commit. Their rows live in the handover, §§ 7–8.

- [x] TDD: `tests/test-routine-skills.sh` — a config with no `[routines.skills]` yields the shipped default chain for each of `plan`/`fix`/`improve`/`build`; a chain naming a skill absent from disk is refused naming the skill (AC4); a chain whose last element is not `/wrap-up-session` is refused (AC5); an override supplying one chain replaces all of them rather than merging per key (AC8); a routine carrying a selector but no chain is refused naming the routine (AC9) -> `registry/config.py`: `DEFAULT_ROUTINE_SKILLS` beside `DEFAULT_KIND_PRECEDENCE`, a `routine_skills` field on `Config`, its reader, and three validators beside the existing selector validators <!-- task-id: routines.skill-chains -->
- [x] TDD: `tests/test-routine-selectors.sh` gains a `workflow` block asserting all six outcomes of spec § 3 are distinguishable in **both** stdout and exit code — routine found, resolves to deferred `build`, no kind label, claim label present (names the claimant), unknown reference (exit 1), config or upstream-label fault (exit 2); `workflow` takes exactly one required argument (AC13) -> `task-registry.py`: `workflow` subcommand + `_workflow()` over the existing `select_routine()` (`routines.py:49`), which today collapses five of these into one `None` (AC1, AC2) <!-- task-id: routines.workflow-command --> (blocked-by: routines.skill-chains)
- [x] TDD: `select --routine <name>` orders candidates by `(priority rank: now < next < unset, then ascending issue number)`; a shuffled provider response yields the same head; two runs on an unchanged backlog return the same issue (AC3) -> `registry/model.py` `by_priority` — today it tie-breaks on `task.id`, a title-derived slug (`model.py:305`, `fallback_id=""` at `github.py:262`), **not** the issue number; change the key and amend spec § *Ordering* + AC3 in the same commit. Both callers (`routines.py:105`, `reconcile.py`) change together <!-- task-id: routines.total-order --> <!-- see handover § 5 -->
- [x] TDD: `doctor` reports this project's configured path rather than `configuration: none`; `.claude/project.md` carries the declaration and `/sync`'s syncable-paths block does not cover it; `CLAUDE.md` emits no bare parseable pointer (AC7's project half, AC12) -> create `docs/task-tracking.md` from `.agents/skills/task-registry/templates/task-tracking.md` with a `[routines.skills]` section, and declare it in `.claude/project.md`. **The engine half — declared-but-missing refused loudly — belongs to #82's worktree. If that agent already did this half, drop this task and say so** <!-- task-id: routines.project-config --> (blocked-by: routines.skill-chains)
- [x] TDD: `tests/test-routine-wrapup.sh` — a **scheduled** run whose branch has no PR at completion reports it loudly and exits non-zero; an unattended run producing no PR is never silent (AC11). Do not assert that every session ends in a PR: `/wrap-up-session` has six documented no-PR exits and the spec restates R4 as "attempts a PR, and says so loudly when it fails" -> `.agents/skills/wrap-up-session/SKILL.md` terminal assertion (`gh pr view` on the branch) + parity copy <!-- task-id: routines.pr-assertion --> (blocked-by: routines.workflow-command)
- [x] TDD: assertions pinning the two ACs that are **already shipped** — AC6 (a workflow label absent upstream is refused naming it, `task-registry.py:436` `_selector_upstream_check`) and AC10 (`claim` without `--apply` writes nothing and says so; idempotent; refuses an issue claimed by another routine). Verify, do not reimplement. Every new assertion in this plan must be falsifiable by mutation — break it, watch it go red, restore -> no new implementation <!-- task-id: routines.pin-shipped-acs --> (blocked-by: routines.workflow-command)
- [x] TDD: `tests/test-skill-parity.sh` green (AC15); `bash tests/run.sh` fully green -> byte-identical copies of every edited `.agents/skills/**` file into `.claude/skills/**` <!-- task-id: routines.parity-suite --> (blocked-by: routines.pr-assertion)

## Session Summary — 2026-09-07 [40f6b5e..15a6c29] Phase A complete (specs/workflow-routing.md), base bbef230
- Completed: 7 of 7 Phase A rows. Branch `feat/workflow-routing-phase-a` off `bbef230`.
- Gate: #82 merged as PR #109 before any Phase A work began, per the handover's Step 0.
- Delivered: `task-registry workflow <ref>` (R2, the only real gap), `[routines.skills]`
  configuration layer, issue-number tie-break, this project's `docs/task-tracking.md`,
  and wrap-up Step 8.5.
- Phase A owns AC1-AC13 and AC15; all have falsifiable assertions. AC14 and AC16
  belong to Phase B/C.
- Suite: 37 files green. Every new gate verified falsifiable by mutation; four
  assertions that could not fail were found and narrowed rather than kept.
- Next: Phase B (Cut 1) — rows in `tasks/handover-workflow-routing.md` § 7. Do not
  start it on this branch; one phase per `/build`, one PR per phase.

## Session Summary — 2026-09-07 [15a6c29..31edf29] Phase A review fixes
- Applied the four dispatched review passes: 7 MUST-FIX and 16 SHOULD-FIX, none skipped.
- `workflow` rewritten to resolve through `provider.resolve_reference` +
  `get_task`. That one change closed four defects: `workflow '#11'` refusing a
  live issue, the 500-issue page-limit blind spot, a closed issue routed as
  runnable, and a tracker outage exiting on the code a scheduler pages on.
- Two previously-green assertion sets were reproduced as vacuous and rebuilt: the
  AC4 traversal guard (the bait file now exists, so refusing and traversing
  diverge) and the wrap-up early-exit routing (derived from Step 8.5's own table).
- `AGENTS.md` had no task-tracking pointer while `.claude/project.md` claimed it
  did — this repository was loading defaults on Pi. Both halves now pinned.
- Suite: 39 files green. Every new guard mutation-tested red-then-restored.
- Carry-forward: four `owner: human` findings recorded in
  `tasks/handover-workflow-routing.md` § 11, led by AC2 being unsatisfiable as
  worded against spec § 3's own table.
- Next: Phase B (Cut 1), handover § 7 — which now carries what Phase A changed
  for it, including an eleventh `Registry` caller Cut 2's table does not list.

## Plan: Phase B — Cut 1, the two dead modules (`specs/workflow-routing.md`, handover § 7)

> Base `f6bb43c` (Phase A, PR #111 merged). Branch `feat/workflow-routing-phase-b`.
> **Ships as one commit** — the spec's rollback story requires Cut 1 to be a single
> `git revert`. No interleaved changes.
> Caller lists below were regenerated with grep on this branch (trap 1); the handover's
> § 7 row named three doc files and the live surface is seventeen.

- [x] TDD: `tests/test-task-registry.sh` — `--provider jira` is refused naming the available providers; `PROVIDERS` is `("github","local")`; a Jira-shaped URL classifies as `local` via `FALLBACK_PROVIDER` rather than a Jira adapter; sections 4/5/8 and the `:1823` regression block retire with their subject -> delete `registry/providers/jira.py` (437) and `tests/fixtures/task-registry/fake-jira.py`; drop `JiraProvider` from `providers/__init__.py` (`PROVIDER_CLASSES`, import, `__all__`) <!-- task-id: cut1.jira-module -->
- [x] TDD: `load_config` on a `[jira.issuetype]`/`[jira.priority]` section leaves no `jira_*` attribute on `Config`; `JIRA_BASE_URL`/`JIRA_EMAIL`/`JIRA_API_TOKEN` are not read; `redactor_for` still scrubs a generic `token=...` via `_PATTERNS` with no configured secret -> `registry/config.py`: remove `DEFAULT_JIRA_ISSUE_TYPES`, `DEFAULT_JIRA_PRIORITIES`, the five `jira_*` `Config` fields, their readers (`:402`, `:453`, `:472`), `Secret`, `is_secure_transport`, `INSECURE_TRANSPORT_ENV` and the insecure-transport guard; `registry/redaction.py`: `redactor_for` keeps its two callers (`github.py:85`, `task-registry.py:193`) and returns `Redactor([])`, `_url_credentials` retires with the only config field that fed it; `registry/__init__.py` drops `Secret` <!-- task-id: cut1.jira-config --> (blocked-by: cut1.jira-module)
- [x] TDD: `grep -rni jira` over `CLAUDE.md README.md .agents .claude tests specs` returns only Phase-B provenance lines; `tests/test-doc-conventions.sh:374`'s "Jira is never selected implicitly" assertion retires with the sentence it pins -> provider vocabulary becomes `github`/`local` in `CLAUDE.md:420,439,444,478`, `README.md:291`, `task-registry/SKILL.md` (frontmatter `description`, `:142`, `:206`, `:211`), `references/configuration.md`, `templates/task-tracking.md` (`[jira.issuetype]`, `[jira.priority]`), `.claude/hooks/session-start.sh:418`, and the four boundary-prose sites that name Jira as the tracker workflow code must not call directly (`wrap-up-session/SKILL.md:223,604`, `verify/SKILL.md:212`, `build/SKILL.md:173`, `wrap-up-session/references/routines.md:158`) — the boundary argument survives, the dead provider name does not <!-- task-id: cut1.jira-docs --> (blocked-by: cut1.jira-config)
- [x] TDD: `task-registry migrate` exits non-zero as an unknown command; `scripts/migrate-task-registry.py` mints stable ids on the same ascii_video_pipeline-shaped fixture section 10 uses, imports nothing from the skill, and still runs with `registry/index.py` and `registry/reconcile.py` absent (the Cut 2 precondition); `reconcile`'s `missing-id` text names a path that exists on disk -> delete `registry/migrate.py` (437), its `migrate` subcommand in `task-registry.py`, `references/migration.md`, and the `apply_migration`/`plan_migration` exports in `registry/__init__.py`; ship the self-contained one-shot under `scripts/` (precedent: `scripts/migrate-learning-store.py`) vendoring the slice it needs — index row parse/replace, `slugify_id`, `TERMINAL_STATUSES`, `_scan_specs`; **repoint section 10's assertions at the one-shot rather than deleting them**, so the remedy keeps a falsifiable test <!-- task-id: cut1.migrate-oneshot --> (blocked-by: cut1.jira-docs)
- [x] TDD: `SKILL.md:207` and `references/progressive-disclosure.md:48` name the one-shot's real path, not `migrate`; `references/configuration.md:258`'s `missing-id` remedy resolves to a shipped file; no `references/migration.md` link dangles in `tests/test-skill-references.sh` -> the `migrate` documentation surface, repointed rather than dropped (trap 6: never delete it silently) <!-- task-id: cut1.migrate-docs --> (blocked-by: cut1.migrate-oneshot)
- [x] TDD: `tests/test-skill-parity.sh` green — `.agents/` and `.claude/` byte-identical (AC15); `bash tests/run.sh </dev/null` fully green; AC16 recorded as a **measured delta** against this branch's base rather than the spec's stale absolute (see the ambiguity below) -> parity copies of every edited `.agents/skills/**` file; amend spec § *Honest accounting* + AC16 in this same commit so the spec never states a number the tree contradicts <!-- task-id: cut1.parity-suite --> (blocked-by: cut1.migrate-docs)

## Session Summary — 2026-09-07 [f6bb43c..HEAD] Phase B / Cut 1 complete (specs/workflow-routing.md)
- Completed: 6 of 6 Phase B rows. Branch `feat/workflow-routing-phase-b` off `f6bb43c` (PR #111).
- Deleted: `providers/jira.py` (437), `registry/migrate.py` (437),
  `references/migration.md`, `tests/fixtures/task-registry/fake-jira.py`, and the
  configuration the Jira adapter orphaned — `DEFAULT_JIRA_*`, five `Config`
  fields, `Secret`, `is_secure_transport`/`INSECURE_TRANSPORT_ENV`,
  `_url_credentials`. 991 lines off the scripts tree (5,539 -> 4,548).
- Shipped: `scripts/migrate-task-registry.py`, a self-contained one-shot (689 LOC)
  replacing `task-registry migrate`. It imports nothing from the skill — pinned by
  an assertion — because Cut 2 deletes the `index.py` and `reconcile.py` it used
  to read through. Test section 10 was repointed at it rather than deleted, so the
  `missing-id` remedy keeps a falsifiable test instead of only a mention.
- The Jira sweep ran to 17 files, not the 3 the handover listed (trap 1 again).
- Every new guard mutation-tested red-then-restored. One assertion set was found
  vacuous mid-run (`--provider jira` pinned `PROVIDER_CLASSES`, never
  `config.PROVIDERS`) and a config-file assertion was added to cover the path a
  downstream project actually hits.
- Suite: 37 files green. `.agents`/`.claude` byte-identical (AC15).
- Next: Phase C (Cut 2), handover § 8. Regenerate the caller list — `workflow`,
  `select` and `claim` are callers the § 8 table predates.

## Plan: Phase C — Cut 2, the todo.md sync engine (specs/workflow-routing.md)

> Branch `feat/workflow-routing-phase-c` off `6c5fe6f` (Phase B / PR #113).
> Ships as **one commit**: the spec's rollback story requires the module deletions
> and their caller repoints to revert together.
> Caller list below was **regenerated by grep** (trap 1), not taken from handover § 8.

- [x] TDD: `show` survives with its local half — `task-registry show <id>` renders an index-row-only task (no external ref) and a provider-only task, on both providers; `grep -n 'from .index\|from .reconcile' registry/*.py task-registry.py` names only the new home -> rehome the surviving read surface (`Registry` + `show` + `_render_detail` + the `index.py` row **parser**) into a module Cut 2 does not delete; `reconcile.py`, `index.py`, `upsert.py` then go whole. See decision **D1** below <!-- task-id: cut2.rehome-show -->
- [x] TDD: `for c in reconcile publish pull frontier; do` each exits non-zero as an unknown command; `registry/__init__.py` exports no `Registry`/`Report` from a deleted module; `python3 task-registry.py --help` lists only the surviving commands -> delete `registry/reconcile.py` (797), `registry/index.py` (394), the `publish`/`pull`/`frontier` dispatch entries in `task-registry.py:262-269`, and `_dependency_order`/`_cycles` <!-- task-id: cut2.delete-modules --> (blocked-by: cut2.rehome-show)
- [x] TDD: the wrap-up debt ledger's remedy resolves to a command that exists — `session-start.sh` banner + `tests/test-pre-push-gate.sh:227` + `specs/wrap-up-gate-and-tdd-fold.md:173` (a **shipped AC**) agree with the shipped CLI; `wrap-up-session/SKILL.md:226`'s deferred-work recorder still runs -> resolve decision **D2** below on `upsert.py`, then repoint every surface in this same commit <!-- task-id: cut2.debt-remedy --> (blocked-by: cut2.rehome-show)
- [x] TDD: `grep -rn` over `.agents .claude tests specs CLAUDE.md README.md docs` finds no live `reconcile`/`publish`/`pull`/`frontier` task-registry invocation (AC14) -> repoint the regenerated caller list: `plan/SKILL.md:195,200`, `wrap-up-session/SKILL.md:81,85`, `task-registry/SKILL.md` (18 refs incl. frontmatter `argument-hint:4`, the command table `:59-64`, `:43-52`, `:173,177,184,217`), `references/progressive-disclosure.md` (4 refs), `CLAUDE.md:480`, `session-start.sh:214,418` <!-- task-id: cut2.repoint-callers --> (blocked-by: cut2.delete-modules)
- [x] TDD: no living spec asserts a deleted command — `/wrap-up-session`'s spec reconciliation (`b157369`) fires **actively** on these, so they are amended in the cut commit, not after -> `specs/task-registry.md`: **AC-18 (`frontier`)** at `:188`, the command table `:78-83`, and `:52,118,122,129,138,173,190,201`; `specs/workflow-routing.md`: AC14/AC16 + § *Honest accounting* per D1's measured delta; `specs/wrap-up-gate-and-tdd-fold.md:99,173` per D2 <!-- task-id: cut2.spec-amendments --> (blocked-by: cut2.repoint-callers)
- [x] TDD: every retired assertion is retired **with the behavior it pinned**, never silenced — `tests/test-task-registry.sh` § 9 (reconcile/frontier/progressive-disclosure, `:1058-1205`), the publish blocks (`:908-1052`, `:1814`, `:1895-1969`), the CLI sweep `:1493` (trims to `doctor`), `:2002,2041` frontier; `tests/test-routine-selectors.sh:456`; `tests/test-skill-invocation-chain.sh:146,152` (wrap-up→`reconcile` chain); `tests/test-pre-push-gate.sh:227` -> retire or repoint each; **`scripts/migrate-task-registry.py` must still run** — § 10's "imports nothing from the skill" assertion going red means the fix is in the script, never in the assertion <!-- task-id: cut2.test-retirement --> (blocked-by: cut2.spec-amendments)
- [x] TDD: `tests/test-skill-parity.sh` green (AC15); `tests/test-syncable-paths.sh` green (no `SKILL.md` names a `scripts/…` path — use the `<template-clone>/scripts/…` prefix); `bash tests/run.sh </dev/null` fully green against the 37-file / 3362-assertion baseline -> parity copies of every edited `.agents/skills/**` file into `.claude/skills/**`; record AC16 as a measured delta against `6c5fe6f` <!-- task-id: cut2.parity-suite --> (blocked-by: cut2.test-retirement)

### Decisions this plan needs before it builds

**D1 — `show` keeps a local half, so `index.py` cannot go whole.**
Handover § 8 states every surviving command "uses only those three attributes and
none of the methods." Regenerated evidence says otherwise: `show` is a `Registry`
method (`reconcile.py:587`) that calls `self.local_index()` (`:141` → `index.py`),
`_resolve_task`, and `_render_detail`. `index.py`'s write half is only **71 LOC**;
its read/parse half is **~320**.
- (a) **Recommended** — rehome `Registry` + `show` + the row parser into a module
  the cut does not touch, then delete all three files whole. Keeps the cut boundary
  at module ownership, which is what "one revertable commit" is built on.
- (b) Keep `reconcile.py`/`index.py` as files, delete only the sync methods.
  Smaller diff; both files keep names that no longer describe them.
- (c) Make `show` provider-only and delete `index.py` whole. Only option that hits
  AC16's literal 1,395, but drops detail for a row never published.
Independent corroboration for keeping the parser: the spec's own #90 row calls
`_split_title_summary` (`index.py:127`) a function that "runs on every row parse"
and marks #90 **not affected** by this work — which only holds if the parser survives.
**Consequence either way:** AC16's "a further 1,395" becomes ~**1,075**. AC16 already
prefers measured deltas over absolutes, so this is an amendment, not a miss.

**D2 — deleting `upsert` leaves the repo with no task-creation command.**
Cut 2 as specced deletes `upsert.py` (204). But `upsert` is not a todo.md *mirror* —
it is runtime task creation, and two surfaces depend on it existing:
- `specs/wrap-up-gate-and-tdd-fold.md:173` is a **shipped, checked AC** requiring
  `session-start.sh` to print the filing invocation, pinned by
  `tests/test-pre-push-gate.sh:227`.
- `wrap-up-session/SKILL.md:226` records deferred spec-reconciliation work with it.
- (a) **Recommended** — keep `upsert`, delete only its index-sync side effect
  (`from .index import load_index, render_row`, `_sync_index`). The mirror dies; the
  create-one-task capability stays.
- (b) Delete it and repoint both surfaces at `gh issue create` — but that puts a
  tracker call in a hook banner and in wrap-up prose, crossing the "workflow code
  never calls the tracker itself" boundary `SKILL.md:222` states.
- (c) Delete it and retire the debt-ledger remedy, amending the other spec's AC.

## Session Summary — 2026-09-08 [6c5fe6f..314f007] Phase C / Cut 2 complete (specs/workflow-routing.md)
- Completed: 7 of 7 Phase C rows. Branch `feat/workflow-routing-phase-c` off `6c5fe6f` (PR #113).
- Deleted: `registry/reconcile.py` (797) and with it the `reconcile`, `publish`,
  `pull` and `frontier` commands and the local `_dependency_order`/`_cycles`
  topological solver. 591 lines off the scripts tree (4,562 -> 3,971).
- Added: `registry/detail.py` (199) — reconcile.py's surviving half, so `show`
  keeps working after the module it lived in went away.
- **Cut 2 came in at 591, not the projected 1,395**, and that is the session's
  main finding. `index.py` and `upsert.py` were both slated for deletion; both
  have a reader that survives the cut. `show` resolves against the local index,
  and `upsert._published_ref` reads the link row `_sync_index` writes — the only
  memory of a GitHub publication, because `providers/local.py:86,93` overwrites
  `external` with its own local ref. Deleting the write while keeping the read
  would have re-opened the duplicate-issue bug the read exists to prevent.
- Trap 1 paid a third time: the spec's caller table listed 10 callers, every line
  number had moved, and it missed four surfaces — including a **shipped AC** in
  `specs/wrap-up-gate-and-tdd-fold.md:173` (pinned live by
  `tests/test-pre-push-gate.sh:227`) requiring the debt banner to name a command
  Cut 2 deletes. The banner now names `upsert`.
- Resolved during the APOSD gate (was recorded here as an accepted consequence):
  `index.py`'s `problems` list briefly had no reader once `reconcile` was gone, so
  a malformed row reached no CLI surface. `load_index_strict` + `IndexUnreadable`
  (`index.py:369,373`) restored it — every command that resolves by id or rewrites
  a row now refuses and renders the failing rows, while `doctor` keeps the
  permissive `load_index`. This also closes a duplicate-append that reproduces on
  base `6c5fe6f`, i.e. pre-dates the cut.
- Suite: 37 files green, 3340 assertions total; 318 in the registry suite (was 307 — ~200
  retired with their commands, the survivors repointed rather than deleted).
- Every new guard mutation-probed red-then-restored. One probe came back green:
  `assert_contains "$gh_degraded" "degraded"` matched the limitation's own text
  ("reads degraded to local-only") with the `degraded:` header deleted. Rescoped to
  the block and re-probed red (`tests/test-task-registry.sh:1924`).
- Next: `/wrap-up-session`. Downstream re-scoping (#97, #93, #98) per handover § 9.

### Review round — 4 dispatched passes (2026-09-08)

All four passes independently found the same defect: `upsert --apply` reached the
provider **before** the strict index load, so on the GitHub path a malformed
`tasks/todo.md` let the issue be created and only then refused — an orphaned
upstream issue, reported to the operator as a failure. AC-19 says "before any
provider write"; it was not delivered on the only path that writes. Fixed by
hoisting one `load_index_strict` above `provider.discover()`, which also makes
the dry run refuse identically.

Pass 4 found a second one nobody else did: `tests/test-task-registry.sh:1690`
still invoked the deleted `frontier`, so argparse exited 2, the suite has no
`set -e`, and `assert_not_contains` passed on the error text. A green assertion
proving nothing — the exact failure closed task 6 claims to have prevented.

Pass 3 mutation-proved two more surfaces had lost their only guard when the
`publish` assertions were retired: the legacy-row publish diagnostics, and
`Report.exit_code` / the `failures:` render / `offline_reads = fail`.

Corrected while fixing: `show` was made permissive again. It writes nothing, so
refusing there denied every task over one unrelated bad row — and left no command
able to diagnose the file, because `doctor` never reads the index. The
`load_index_strict` docstring had justified the permissive variant by naming a
reader that did not exist. The code now matches the comment rather than the
reverse.

- Suite: 37 files, 3340 assertions, green. 9 mutation probes this round, all red
  then restored.
- Deferred, reported not applied: `backlog_path` and `dependency_strategy` are
  orphaned config knobs, but were already orphaned before this cut — out of scope
  under the orphan rule. `spec_dir` *was* orphaned by this cut and was removed.
- [ ] Preserve published issue references across local-pending upserts <!-- task-id: task-registry-local-pending-upsert-shadows-published-reference --> — When an approval-gated upsert falls back to the local provider for a task already linked to GitHub, the local provider… ([#117](https://github.com/Joaovsales/jplugin-agentic-development/issues/117))
