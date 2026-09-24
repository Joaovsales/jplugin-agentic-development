## Plan: routine-run-envelope
> Spec: specs/routine-run-envelope.md
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/127

- [x] TDD: tests/test-routine-run.sh § claude argv — `build_command("claude", prompt, allow=None)` is `claude -p <prompt> --strict-mcp-config`; with an allow file adds `--mcp-config <file>`; unknown routine or harness exits 2 -> launcher arg parsing + prompt file read + claude builder (AC1)
- [x] TDD: tests/test-routine-run.sh § codex argv — fixture config.toml with `linear` and `github`; allowing `github` yields `codex exec` + `-c mcp_servers.linear.enabled=false` only; missing config adds no overrides; allowing an unconfigured server exits 2 -> codex builder reading CODEX_HOME via tomllib (AC2)
- [x] TDD: tests/test-routine-run.sh § retry — fake harness (via `ROUTINE_RUN_HARNESS_BIN` override) prints only the MCP line on attempt 1 and a full envelope on attempt 2: exit 0, silent, no log dir -> single retry before the start line (AC3)
- [x] TDD: tests/test-routine-run.sh § never started — both attempts print only the MCP line: exit 1, stderr names `never started` and `linear`, log dir has stdout.txt, stderr.txt, verdict.json with attempts=2 (AC4)
- [x] TDD: tests/test-routine-run.sh § verdicts — start-only, failure envelope, finish + exit 3, empty output, malformed JSON, other routine's name: each fails with its reason after one attempt (AC5)
- [x] TDD: tests/test-routine-run.sh § silent success — MCP warning then full envelope: exit 0, empty stdout/stderr, no log dir (AC6)
- [x] TDD: tests/test-routine-run.sh § docs — six prompts carry `ROUTINE-ENVELOPE start`, `ROUTINE-ENVELOPE finish`, `ROUTINE-ENVELOPE failure` and the integrations-optional rule; routines.md § Launching a routine and the prompts README name `routine_run.py run --routine` -> edit prompts, contract, README (AC7)

## Plan: plan-slices-and-handover
> Spec: specs/plan-slices-and-handover.md
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/106
> Note: written by hand in the grammar `/slice` will own (slice 2); ids minted by `upsert --derive-id plan --spec specs/plan-slices-and-handover.md --fold-title` dry runs; nothing filed by the planning session, the build session files first (spec § Build Order, build prompt)

### Slice 1/7 — slice script and shared glob matcher
- [x] slice script and shared glob matcher <!-- task-id: plan.specs-plan-slices-and-handover-md.slice-script-and-shared-glob-matcher --> — Slice 1/7 of #106: `slice.py validate`, `ready`, `check`; `registry/globs.py` extracted from `spec-reconcile.py`; fixtu… ([#169](https://github.com/Joaovsales/jplugin-agentic-development/issues/169))
  [x] TDD: tests/test-slice.sh § validate — fixture with an intersecting pair and no blocker exits 1 naming both slices; a cycle exits 1 naming the cycle; a surface path outside `implementation_paths` exits 1 naming the path; the clean fixture exits 0 -> `slice.py validate --spec` parsing § Build Order and the frontmatter (AC 1)
  [x] TDD: tests/test-slice.sh § ready — fixture index with three slices where 2 is blocked by 1: `ready` lists 1 and 3 with surfaces and the intersecting pair `1 ↔ 3`; after 1 is `[x]` it lists 2 and 3; a block with no `### Slice` headings yields one implicit slice whose surface equals `implementation_paths` -> `slice.py ready --index --spec` over `TaskIndex` (AC 2)
  [x] TDD: tests/test-slice.sh § check — fixture repo where the diff touches one declared and one undeclared path: prints `undeclared:` and `untouched:`, exit 1; clean diff exits 0 and prints nothing -> `slice.py check --spec --slice --base` over `git diff --name-only` (AC 3)
  [x] TDD: tests/test-slice.sh § globs — `registry/globs.py` rejects absolute, `..`, backslash and unsupported-glob patterns naming spec and value; tests/test-living-spec-reconciliation.sh stays green with `spec-reconcile.py` importing `_pattern_to_regex` and `match_path` from it -> extract the matcher, repoint `spec-reconcile.py` through `sys.path` (AC 3)

> Handover: landed 27d5ab7 + ec2e62b — `.agents/skills/slice/scripts/slice.py` (`validate`, `ready`, `check`), `.agents/skills/task-registry/scripts/registry/globs.py` (matcher, frontmatter reader, `patterns_intersect`, `pattern_covered_by`), `spec-reconcile.py` repointed to it through `sys.path`, `tests/test-slice.sh` (36 assertions) over `tests/fixtures/slice/**`; `tests/test-living-spec-reconciliation.sh` still 178 green.
> Do not re-derive: two surface patterns intersect by the literalize-and-match heuristic in `globs.patterns_intersect`; headings and tables are read from prose only (`_without_fences`) because this very spec carries a fenced `## Build Order` example above the real section; `ready` prints `ready: <n> <name>` / `  surface: …` and `intersects: a ↔ b (no blocker; serialize in table order)`; `check` exits 1 on either `undeclared:` or `untouched:`, so a plan-only commit shows `tasks/todo.md` as undeclared by design; `sync-retire.py` still carries its own matcher copy (open task `glob-matcher-shared-module`). Plain `python` calls must NOT run under `MSYS_NO_PATHCONV=1` — it stops Git Bash converting POSIX path arguments and every script call breaks; reserve it for `claude -p /skill` prompts.
> Surface: undeclared none; untouched none (`check --slice 1 --base 9e9f104`).

### Slice 2/7 — slice skill
- [x] slice skill <!-- task-id: plan.specs-plan-slices-and-handover-md.slice-skill --> — Slice 2/7 of #106: `SKILL.md`, `references/plan-block.md`, `references/sizing.md`, `references/build-prompt.md`, the th… ([#170](https://github.com/Joaovsales/jplugin-agentic-development/issues/170))
  [x] TDD: tests/test-doc-conventions.sh § slice — `.agents/skills/slice/SKILL.md` has `name: slice`, `disable-model-invocation: false`, `harness: universal`, an `argument-hint`; the three references exist; `CLAUDE.md` and `README.md` skills tables and `.claude/hooks/session-start.sh` list `/slice`; `sizing.md` states `files > 8`, `systems > 2`, `ACs > 3` and contains no `floor`, `S (`, `M (` or `L (` label -> write the skill, the three references and the three rows (AC 4)
  [x] TDD: tests/test-doc-conventions.sh § slice propose — SKILL.md names `slice.py validate`, `✓ Build Order written:`, `✓ Plan written:`, `Spec and plan are ready to be built`, `--derive-id plan`, `--fold-title`, the leading-`/` rule, and the in-place replacement rule; the plan-block example in SKILL.md and `references/plan-block.md` compare equal after flattening; the build-prompt template in SKILL.md and `references/build-prompt.md` compare equal and its instruction lines name `--file --approve`, `Surface`, `§ Decisions`, `[AMBIGUITY]`, `> Handover:`, `/wrap-up-session`; SKILL.md has no `Invoke /build` line and no "meet your requirements" sentence -> document the propose phase against the two references (AC 5)
  [x] TDD: tests/test-doc-conventions.sh § slice file — SKILL.md names the no-plan-block refusal, `--parent`, `--approve` with the `/build` and `/yolo` rule, the idempotent re-run, `local-pending` and `✓ Filed:`; the upsert invocation contains no `--depends-on`; no `> Approved` anywhere in the skill -> document the `--file` phase (AC 6)
> Handover: landed d3e584e — `.agents/skills/slice/SKILL.md` (194 lines), `references/plan-block.md`, `references/sizing.md`, `references/build-prompt.md`, one `/slice` row each in `CLAUDE.md`, `README.md` and `.claude/hooks/session-start.sh`, `# --- slice:` pins appended to `tests/test-doc-conventions.sh` (468 assertions green, 104 in test-skill-references.sh).
> Do not re-derive: the build-prompt fenced block is byte-identical in `SKILL.md` and `references/build-prompt.md` and pinned equal; the plan-block example is pinned equal after `flatten`; `Invoke /build`, "meet your requirements" and `> Approved` are negative pins on the skill — a caller that quotes the prompt cites `references/build-prompt.md` rather than restating it. `sizing.md` is the one place the ceiling lives; `SKILL.md` § Integration already names `/plan` Step 3, `/system-design-planning` Step 3.5 and `/build`'s pre-flight as callers.
> Surface: undeclared none; untouched none.

### Slice 3/7 — upsert parent flag
- [ ] upsert parent flag <!-- task-id: plan.specs-plan-slices-and-handover-md.upsert-parent-flag --> — Slice 3/7 of #106: `--parent` through `link_parent`, disclosure, docs ([#171](https://github.com/Joaovsales/jplugin-agentic-development/issues/171))
  [ ] TDD: tests/test-task-registry.sh § parent — `--parent '#N'` on the local fixture records a native parent; on the github fixture writes `parent:` metadata and prints the disclosure line; the dry run calls no provider; `SKILL.md` documents the flag -> `--parent` on `upsert` wired to `link_parent` (AC 7) — pending: the PR's Linux CI run (the GitHub-mock pins cannot reach the `gh` mock from Python on Windows, #129)
  [x] TDD: tests/test-task-registry.sh § seeded blocked-by — a first `upsert --apply` against an index row that carries `(blocked-by: id)` keeps the marker on the refreshed row, and a second run keeps it too -> carry the index row's `depends_on` into the merge when the incoming task has none (added in `/build` pre-flight: the probe on a local fixture dropped the marker, so filing before this fix would corrupt the plan block)

> Handover: landed c6f5708 — `--parent REF` on `upsert` (refused on any other command), `_preview_parent_line` (dry run, decided from capabilities, no provider call), `_link_parent_line` (apply: `escalation._authoritative_parent` imported lazily to dodge the import cycle, then `target.link_parent` on the provider the body landed on; unreachable tracker prints `parent link pending`), `_sync_index` carries the seeded row's `depends_on` when the task has none; `task-registry/SKILL.md` § upsert documents the flag; two new blocks in `tests/test-task-registry.sh`.
> unfinished: the § parent row — the GitHub-fixture pins are proven only by the PR's Linux CI run (#129); the local fixture and the seeded row pass here
> Do not re-derive: `upsert_task(registry, task, apply, parent_ref=None)` keeps its `(lines, code)` contract and escalation callers are untouched; the disclosure line is `LinkResult.detail` verbatim (`GitHub issues expose no parent link through gh; stored as `parent:` metadata`); the three GitHub-mock apply assertions fail on this Windows host only (real `gh.exe` shadows the mock, #129) and pass nowhere else yet — CI is the proof. The seeded row's status box is NOT carried: a `[x]` header re-filed as a new task reads `[ ]` again, so re-mark done slices after any filing.
> Surface: undeclared none; untouched none (`check --slice 3 --base 7cf4117`).

### Slice 4/7 — plan skill calls slice
- [x] plan skill calls slice <!-- task-id: plan.specs-plan-slices-and-handover-md.plan-skill-calls-slice --> — Slice 4/7 of #106: Step 1 carry-forward without `/grilling`, Step 1.5 escalation, § Decisions template, `Invoke /slice`… ([#172](https://github.com/Joaovsales/jplugin-agentic-development/issues/172)) (blocked-by: plan.specs-plan-slices-and-handover-md.slice-skill)
  [x] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § plan — Step 1 keeps its six questions, has no `Invoke /grilling` line, names `/grill-me` and `/brainstorm` as optional precursors and states `DECISIONS CARRIED`; Step 1.5 has `Escalating to /system-design-planning`; the template lists Behavior, Inputs, Outputs, Edge Cases, Decisions, Acceptance Criteria, Implementation Paths in order with `user`, `assumed`, `open`; Step 3 has an `Invoke /slice` line; "Does this spec and plan meet your requirements" is absent; Step 6 names `Spec and plan are ready to be built`; no `Invoke /build`, no hand-written `## Plan:` template, no `upsert` invocation and no `> Approved` remains -> rewrite `/plan` Steps 3 to 6, delete Step 7 (AC 8)
  [x] TDD: tests/test-doc-conventions.sh § pipelines — `/yolo`'s override table has a Step 1 row naming `assumed` rows, a Step 6 row naming no prompt and `/build` in place, and a Phase B line naming `--file` without `--approve`; `/auto-push` Phase A contains "Does this spec and plan meet your requirements?" as an override on `/plan` Step 6 and Phase B names `--approve`; both name the fresh-session rule they are excepted from -> edit the rows in both pipelines (AC 9)
> Handover: landed 9d3e27f — `/plan` Steps 1, 1.5, 2, 3, 4, 6 rewritten and Step 7 deleted; `/yolo` override table rows for Steps 1, 3, 4, 6 and its Phase B; `/auto-push` Phase A owns the `y` sentence as an override on `/plan` Step 6, Phase B `--approve`s in place. Pins: `# --- plan:` and `# --- pipelines:` blocks in `tests/test-doc-conventions.sh` (502 assertions green); the chain test's `/plan -> /task-registry` block became `/plan -> /slice`; the registry-only loop lists `slice` instead of `plan` and asserts `/plan`'s transitive route. Follow-up b222285: `slice.py` reconfigures stdout and stderr to UTF-8 — the boundary suite ran without `PYTHONUTF8` and `ready` died printing `↔`.
> Do not re-derive: `/plan` names `/slice` only by pointing at `.agents/skills/slice/SKILL.md` and `references/build-prompt.md`, never by restating its grammar; the seven-section template order is pinned through `flatten`; `upsert`, `Invoke /build`, `> Approved` and the gate sentence are negative pins on `/plan`. `/system-design-planning` Step 1 should describe the same `DECISIONS CARRIED: <n> from <spec path | conversation>` line `/plan` Step 1 prints, and its § Decisions column vocabulary is `user` / `assumed` / `open`.
> Surface: undeclared none; untouched none (`slice.py check --slice 4 --base ab3242a` exit 0).

### Slice 5/7 — design planning and brainstorm call slice
- [x] design planning and brainstorm call slice <!-- task-id: plan.specs-plan-slices-and-handover-md.design-planning-and-brainstorm-call-slice --> — Slice 5/7 of #106: Step 1 reads § Decisions, Step 2.5 interviews through `/grilling`, template trimmed, Step 3.5 invoke… ([#173](https://github.com/Joaovsales/jplugin-agentic-development/issues/173)) (blocked-by: plan.specs-plan-slices-and-handover-md.plan-skill-calls-slice)
  [x] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § design planning — Step 1 names § Decisions; Step 2.5 has an `Invoke /grilling` line with its seed questions, `DECISIONS CARRIED` and the empty-frontier rule, pinned in the invocation-chain test beside `/brainstorm`'s; the template has no `| # | Slice |` table and no `### Slice criteria`; Step 3.5 has an `Invoke /slice` line; Step 7 keeps the `[constraints|system-design|contracts|data-models|build-order]` format, names `Spec and plan are ready to be built` and no longer says the bare word is approval; no `File slices` heading, `upsert` invocation, `> Approved` or `TODO(shortcut)` remains; `### 9. Hand off` present; Iron Law and Red Flag name the planning session; the chain pin "files slices through task-registry" moves to `slice/SKILL.md`, the other three (reads issues, renders, hands off) still hold -> rewrite Steps 1, 3, 3.5, 7, 9, the Iron Law, the Red Flags and the description; delete Step 8; trim the template; move one chain pin (AC 10)
  [x] TDD: tests/test-grilling-adoption.sh stays green and tests/test-doc-conventions.sh § brainstorm pins `## Decisions` with a `Source` column in the Step 6 template -> extend Step 6's template by one section (AC 11)
> Handover: landed 75544fc — `/system-design-planning` description, Iron Law, Red Flag and rationalization row name the planning session; Step 1 reads § Decisions; new mandatory §2.5 `Invoke /grilling` with the seed frontier, `DECISIONS CARRIED` and the empty-frontier rule; Step 3 leaves build order to `/slice`; new Step 3.5 `Invoke /slice … --issue #N`; Step 7 is the review loop ending with the build prompt; Step 8 deleted; `### 9. Hand off` says the build session files first. Template lost the slice table and `### Slice criteria`, kept the `## Build order` heading for the nine-section order pin. `/brainstorm` Step 6 template gained § Decisions (`Source` = `user`). Follow-up 00e01a0: `templates/content-model.json` reflection and build-order example, `task-registry/SKILL.md` caller row, spec frontmatter gains `content-model.json`. Pins: `# --- design-planning:` and `# --- brainstorm:` blocks (531 assertions green); chain test pins `^Invoke \`/grilling` and `^Invoke \`/slice` on the design skill and moved "files slices through task-registry" to `slice/SKILL.md`.
> Do not re-derive: a `Shims` guard in `tests/test-doc-conventions.sh` bans the literal `Step 2.5` outside `tasks/` and `specs/`, so the design skill writes `§2.5` in prose and `### 2.5.` as the heading — `/build`'s text must not say `Step 2.5` either. The design skill's Step 9 already states that the build session files first through `/build`'s pre-flight `/slice … --file --approve` and that `/build` claims the `- [ ]` slice header through `/task-registry`; `/build` should describe the same pre-flight, not a different one. `/build`'s existing `slice header` paragraph says the header is written by `/system-design-planning`; it is now written by `/slice`.
> Surface: undeclared none; untouched none (`slice.py check --slice 5 --base 3234de1` exit 0); the follow-up touched `content-model.json` and `task-registry/SKILL.md` outside the slice's surface, reported as `[SURFACE]` by the agent and landed by the orchestrator.

### Slice 6/7 — build and wrap-up on slices
- [x] build and wrap-up on slices <!-- task-id: plan.specs-plan-slices-and-handover-md.build-and-wrap-up-on-slices --> — Slice 6/7 of #106: pre-flight filing through `/slice --file`, implicit slice, `ready`, delegation items, `check`, hando… ([#174](https://github.com/Joaovsales/jplugin-agentic-development/issues/174)) (blocked-by: plan.specs-plan-slices-and-handover-md.slice-script-and-shared-glob-matcher, plan.specs-plan-slices-and-handover-md.design-planning-and-brainstorm-call-slice)
  [x] TDD: tests/test-doc-conventions.sh + tests/test-skill-invocation-chain.sh § build — pre-flight has an `Invoke /slice` line with `--file --approve`, the missing-link condition and the `/yolo` exception, and names the implicit slice; the description no longer says "after `/plan` is confirmed"; Phase 1 names `slice.py ready` and no longer assesses independence from prose; the delegation list has items 5 to 7 with `[SURFACE] +`, `> Handover:` and the budget; slice close names `slice.py check`, `undeclared:`, `untouched:`; the handover rule names the two required facts and `unfinished:`; Phase 6 counts nested `[x]` rows and names the forbidden state; `slice header` still present -> rewrite Phase 1 and Phase 6 (AC 12)
  [x] TDD: tests/test-doc-conventions.sh § wrap-up — the PR body step names `## Handovers` before the linkage check and the commit-message fallback -> add the section rule to Step 7 (AC 13)
> Handover: landed db4055c — `/build` pre-flight step 3 + `### Pre-Flight: File the Slices` (Invoke `/slice … --file --approve`, `lacks a provider link`, `/yolo` omits `--approve`, implicit slice over `implementation_paths`); Parallel Dispatch Assessment reads `slice.py ready`; delegation items 5 to 7; new `### Slice Close` (`slice.py check`, `undeclared:` / `untouched:`, `> Handover:` with `<short-sha>..<short-sha>` and the do-not-re-derive fact, `unfinished:`, forbidden state, boundary checkpoint); Phase 6 proof 4 counts nested rows. `/wrap-up-session` `#### Handovers` before the linkage check with the commit-message fallback. Pins: `# --- build:` and `# --- wrap-up:` blocks (557 assertions green), `/build -> /slice` chain block.
> Do not re-derive: `CLAUDE.md` § Workflow step 3 should point at `/build`'s pre-flight filing and Slice Close by the names above, not restate them; the glossary terms slice, surface, ready set, handover and build prompt are defined by `slice/SKILL.md`, `slice/references/sizing.md` and `/build` § Slice Close — `tasks/concepts.md` entries cite those. The literal `Step 2.5` is banned outside `tasks/` and `specs/` by the Shims guard.
> Surface: undeclared none; untouched none (`slice.py check --slice 6 --base 4822f53` exit 0).

### Slice 7/7 — workflow text and live run
- [ ] workflow text and live run <!-- task-id: plan.specs-plan-slices-and-handover-md.workflow-text-and-live-run --> — Slice 7/7 of #106: `CLAUDE.md` § Workflow with the build prompt replacing the `y` gate, glossary terms through `/learn`… ([#175](https://github.com/Joaovsales/jplugin-agentic-development/issues/175)) (blocked-by: plan.specs-plan-slices-and-handover-md.slice-skill, plan.specs-plan-slices-and-handover-md.upsert-parent-flag, plan.specs-plan-slices-and-handover-md.build-and-wrap-up-on-slices)
  [ ] TDD: tests/test-doc-conventions.sh § workflow — `CLAUDE.md` steps 1 to 3 name `/grill-me` and `/brainstorm` as optional precursors, `/grilling` as mandatory in `/system-design-planning`, `DECISIONS CARRIED`, `/slice`, the build prompt, a fresh session and `> Handover:`; "Confirm with 'y' to begin" and the **approved** parenthetical are gone; `tasks/concepts.md` defines slice, surface, ready set, handover and build prompt; `bash tests/run.sh` green on CI -> rewrite § Workflow 1 to 3; `/learn` the five terms (AC 14) — pending: `bash tests/run.sh` green on the PR's Linux CI run (580 § workflow assertions pass here; Windows carries 159 pre-existing failures)
  [x] Verify: one live two-slice run across two sessions on a fixture feature: the `/plan` session ends with the build prompt and files nothing; the fresh session started with it files the slices in pre-flight, shows `DECISIONS CARRIED`, parallel dispatch of two disjoint slices, a handover read by a blocked slice and a surface report; recorded in tasks/e2e-log.md with the commit sha (AC 15) — observed 2026-09-22 (tasks/e2e-log.md): planning contract, filing before the build, ready set with disjoint surfaces, a `> Handover:` per slice, a surface report per slice; the two clauses below were not
  [ ] Verify: parallel dispatch of two disjoint slices and a handover read by a dispatched blocked slice — rerun under an isolated `CLAUDE_CONFIG_DIR` with two ready slices each large enough for `/build` to dispatch (tasks/backlog.md § From #106)
> Handover: landed f9fc232 — `CLAUDE.md` § Workflow steps 1 to 3 are `### 1. Specify` / `### 2. Slice (Hard Gate)` / `### 3. Build (Fresh Session, Autonomous Execution)`: optional `/grill-me` or `/brainstorm` precursors with `DECISIONS CARRIED`, `/grilling` mandatory in `/system-design-planning`, the planner invokes `/slice` and ends with `Spec and plan are ready to be built. Start a fresh session with this prompt:`, `/auto-push` and `/yolo` the two named exceptions, pre-flight filing through `/slice … --file --approve`, `slice.py ready`, `> Handover:`; the `Confirm with 'y' to begin` line and the **approved** parenthetical are gone; five glossary entries (build prompt, handover, ready set, slice, surface) in `tasks/concepts.md` § Harness vocabulary; `# --- workflow:` block in `tests/test-doc-conventions.sh` (580 assertions green). 4526ff8 — the `/plan` and `/system-design-planning` inventory rows in `CLAUDE.md`, `README.md` and `.claude/hooks/session-start.sh` describe the slice → build-prompt flow. 83e6539 — the living-spec `> Spec:` plan-block pin follows the template from `/plan` to `slice/SKILL.md`. a99d307 + f6e9049 — quality gate (Phase 1 inline, Phase 2 inline, Phase 3 dispatched HOLD → 3 MUST-FIX, 1 SHOULD-FIX and 2 NITPICKs applied; 1 SHOULD-FIX and 1 NITPICK reported, not applied). 51a3af2 — AC 15 walkthrough in `tasks/e2e-log.md`: plan session ee94098b ended with the build prompt and filed nothing; build session d0ac3717 filed four slices in pre-flight (`✓ Filed` × 4), `ready` printed slices 1 and 2 with disjoint surfaces, every slice closed with a `> Handover:` and a `slice.py check` surface report; parallel dispatch NOT OBSERVED (the session built 1–3-file slices inline, five `Agent` calls all reviewers), handover-read PARTIAL (no dispatch boundary for a handover to cross), `DECISIONS CARRIED` shown by the plan session only. Full suite at f6e9049 (`tests/run.sh --jobs 8` in the detached worktree `106-base`): 8/47 files, 162 failing assertions against 159 in the 87ff22c baseline; the 3 new ones are the `upsert --parent` GitHub-mock pins unreachable from Python on Windows (#129), every other failure is in the baseline set.
> unfinished: the § workflow row (CI green on the PR) and the dispatch Verify row (AC 15 rerun) — both stay `[ ]` until their evidence exists; the slice stays in the ready set once slice 3's CI row closes
> Do not re-derive: AC 14's `bash tests/run.sh` green on CI is unverified here — Windows carries 159 pre-existing failures, so the PR's Linux CI is the evidence. Both fixture sessions were routed by the harness to the user-scope `~/.claude/skills/` copies of `/plan`, `/build`, `/quality-gate` and `/wrap-up-session` (only `/slice` resolved project-local) and read the project-local `SKILL.md` themselves; a rerun wants an isolated `CLAUDE_CONFIG_DIR` and two ready slices each large enough to earn a sub-agent. `slice.py check` reports `tasks/todo.md` and the tracker's detail records as `undeclared:` on every slice that files or hands over, so its exit code is 1 by construction there — backlog. The main checkout carries uncommitted single-instruction-file work (`CLAUDE.md` → `@AGENTS.md`, managed block in `AGENTS.md`); this branch edits the old-form `CLAUDE.md` § Workflow, so the PR will conflict with that work when one of them lands — the § Workflow text moves into the managed block, not back into `CLAUDE.md`. The fixture `.claude/worktrees/e2e-106` (own repo, git-excluded, 812bb0d…c6a5b98) and the detached `106-base` worktree are left in place for re-reading.
> Surface: `slice.py check --slice 7 --base 2556d29` exit 1 — `undeclared:` the quality gate's edits (`slice.py`, `globs.py`, `upsert.py`, `spec-reconcile.py`, three slice fixtures, `tests/test-slice.sh`, `tests/test-task-registry.sh`), the two orchestrator follow-ups outside the surface (`README.md`, `.claude/hooks/session-start.sh`, `tests/test-living-spec-reconciliation.sh`) and the spec's own `implementation_paths`; none is slice 7 work and all are named above. No `untouched:` line: `CLAUDE.md`, `tasks/concepts.md`, `tasks/e2e-log.md` and `tests/test-doc-conventions.sh` were all edited.

## Session Summary — 2026-09-22 [87ff22c..828f7f8]
- Completed: 21 rows of `## Plan: plan-slices-and-handover` (#169–#175 under #106), quality gate, AC 15 walkthrough
- Pending: 3 rows — the § parent GitHub pins (slice 3) and the § workflow CI-green row (slice 7) wait for the PR's Linux CI run; the AC 15 dispatch Verify row (slice 7) waits for a rerun with slices sized to dispatch; three follow-ups filed in `tasks/backlog.md` § From #106
- Carry-forward: AC 14's suite-green-on-CI is proven by the PR's Linux run, not locally; the `CLAUDE.md` § Workflow edit will conflict with the pending single-instruction-file work (`CLAUDE.md` → `@AGENTS.md`) — the text moves into the managed block when that lands; fixture `.claude/worktrees/e2e-106` and detached worktree `106-base` left in place

---

# Fix: stdin hang in tests/test-pre-push-gate.sh Banner block
> No issue, no spec — user-directed test-hardening fix from a chat message.

- [x] Add `</dev/null` to the two Banner-block session-start.sh invocations (tests/test-pre-push-gate.sh:218, :224) -> matches the sibling at :262; every other hook call in tests/*.sh already pipes stdin from printf; hook unchanged; both `</dev/null` and `< <(sleep 30)` launches complete with 51 assertions

## Session Summary — 2026-09-21 [0de3f8a..188b7da]
- Completed: 1 task (stdin redirect fix, one commit, rebased onto master after #156 landed)
- Pending: none for this fix; the tidy cloud-routine item below is another session's
- Carry-forward: none. The reviewer advisory (tests/run.sh launched every suite with inherited stdin) was resolved by #166 while this PR was open — the runner now passes `</dev/null` to every file

# Fix: #136 — Full suite takes 20–51 minutes on Windows because every process spawn costs over a second
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/136 (no spec — issue-driven fix via /debug)
> Baseline (clean HEAD 0de3f8a, idle Windows 11, sequential): TOTAL 3051 s; sync-retirement 1275 s, install-sh 296 s, task-registry 236 s, solutions-schema 193 s. Root cause: the suite is process-bound (every spawn 100–500 ms), not Python-bound (launcher delta is 6 % of the slowest file).

- [x] TDD: tests/test-run-sh.sh pins per-file timing -> tests/run.sh prints `--- <file>: <n> s ---` after each file and a `TOTAL:` line with the slowest files; `RESULT:` line unchanged; each file runs with stdin closed
- [x] TDD: tests/test-run-sh.sh pins `--jobs N` / `TEST_JOBS` -> files run concurrently up to N, each file's output is captured and printed as one block on completion, exit status and `RESULT:` identical to sequential; `--jobs 0` or non-numeric is a usage error (exit 2)
- [x] TDD: tests/test-run-sh.sh pins TEST_PYTHON resolution -> tests/lib.sh exports TEST_PYTHON once: a preset value wins; otherwise python3/python not under WindowsApps; otherwise the newest `Programs/Python/Python3*/python.exe`; otherwise python3. Every test invocation of `python3` becomes `"$TEST_PYTHON"`; string pins and comments untouched
- [x] TDD: tests/test-upstream-drift.sh deadline assertion -> millisecond timing relative to the noisy-helper run made just before it (same python+git path), plus a PID-liveness check when the helper was spawned; fails on an outliving helper, not on spawn latency
- [x] TDD: tests/test-sync-retirement.sh fixture helpers spend fewer processes with identical semantics -> `_f` uses `${1%/*}` and skips mkdir when the directory exists; make_template/make_project pre-create their directories in one mkdir; user.name/email written into .git/config instead of two git config calls; run_retire captures via `$(<out)` when stderr is empty; tree_hash hashes in one sha256sum pass. Assertion names and count (365) unchanged; Windows failure set (47) unchanged
- [x] Verify: `bash tests/run.sh` sequential and `--jobs 4` on this machine; compare failing assertion names per file against the baseline; record timings in the bug document
- [x] Record: tasks/solutions/performance/<slug>.md status fixed, regression tests named; process doc gains the virtualized-AppData gotcha; tasks/history.md entry

## Session Summary — 2026-09-21 [0de3f8a..HEAD]
- Completed: 7 tasks — runner timing + `--jobs`, TEST_PYTHON resolution (64 call sites), sync-retirement helpers (1275 s -> 695 s, identical 365 results), upstream-drift relative bound + pid check, Codex adapter bash resolution, learning-store documents. Review pass: 3 MUST-FIX + 5 SHOULD-FIX applied, 1 NITPICK applied.
- Pending: 0 in this plan.
- Carry-forward: the ten-minute acceptance target is not met on this machine (936 s at eight jobs; 3051 s serial baseline) — the spawn throughput ceiling means install-sh (296 s), solutions-schema (193 s), task-registry (236 s), routine-selectors (131 s) and session-start (113 s) need the same builtin-first helper treatment; `scripts/check-upstream-drift.py` cannot kill a helper's process tree on Windows (`process.kill()` reaches git.exe only).
- Tests: `bash tests/run.sh --jobs 8` on Windows: 45 files, wall 936 s, 8 files failing with exactly the baseline's assertion names minus upstream-drift; codex-install and verification-skill-integration re-verified in a CRLF checkout.

# Fix: #123 — A single `Closes #A, #B` list only closes the first issue
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/123 (no spec — issue-driven bug fix via /debug)

- [x] TDD: multi-issue pins in tests/test-routine-wrapup.sh + tests/test-pr-linkage.sh -> wrap-up states `Closes #A, closes #B` and the failing form; `scripts/pr_linkage.py check` runs on the draft before create and on the fetched body during every re-sync (exit 3 lists orphaned refs); Done report `PR:` line gains `linkage repaired`; byte-identical .claude copy
- [x] Follow-up filed as [#146](https://github.com/Joaovsales/jplugin-agentic-development/issues/146) (row in the index below): post-merge closure check for PRs merged by the GitHub Actions app — evidence in tasks/solutions/bugs/bot-merged-pr-leaves-linked-issue-open.md

## Session Summary — 2026-09-18 [2608d0a..35adb24]
- Completed: 48 tasks — specs/claude-plugin-manifest.md slices 1–7 plus 5b (version pinning) and 5c (verify → verify-evidence); slice 6 deleted `.claude/skills/` and the parity test
- Pending: 0 in this plan; two human-owned MUST-FIX review findings hold the push (CI-synced projects keep a frozen `.claude/skills/`; AC3 github-source re-run after merge)
- Carry-forward: decide the CI retired-root question (spec § Decisions, OPEN row), then push `worktree-plugin-manifest` and open the PR closing #148–#154; remove the S4 scratch marketplace/cache and the `s4-clone*` worktrees

## Session Summary — 2026-09-16 [a1d7c84..HEAD]
- Completed: 1 task (#123 root-cause fix, tests, two bug documents)
- Pending: 1 follow-up recorded above; the tidy cloud-routine item below is another session's
- Carry-forward: the second #123 symptom (bot-merged PR leaves linked issue open) needs a registry-owned post-merge check downstream

# Fix: #132 — Align metadata reader with writer when task bodies contain stray or incomplete markers
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/132 (no spec — issue-driven bug fix)

- [x] TDD: regression block in tests/test-task-registry.sh § 12 -> parse_metadata_block reads the span metadata_bounds returns; local _unmanaged_regions takes the same span; metadata_block_state names stray, competing, and damaged bodies, providers note them, writers refuse a damaged or competing one; byte-identical .claude copy

## Session Summary — 2026-09-16 [80e265c..e96a9e3]
- Completed: the scheduled `tidy` routine's first run — 8 checks inline, record at
  `tasks/sweeps/2026-09-16-tidy.md`, 3 findings filed, 1 record commit.
- Pending: the 3 filed tasks are **publication pending** — `gh` is not installed in
  the routine container, so provider `github` is unreachable and the local records
  under `tasks/details/` are canonical until published.
- Carry-forward: **the routine cannot repair anything in this environment.** The
  container runs as uid 0, so the 11 permission-contract assertions in
  test-sync-retirement.sh and test-task-registry.sh can never pass, the suite is
  permanently red, and Law 3 withholds every Tier 0 fix — including the one this
  sweep found (`verify-task-registry` missing from all three inventory surfaces).
  Fixing the uid-0 guard is what unblocks every future run. Two further gaps are
  environmental: the checkout is shallow (`retired` inconclusive) and `install.sh`
  has never run here (`installed` inconclusive). The configured tracker repo
  (`Joaovsales/jplugin-agentic-development`) turns out to be the *same* repository
  as the scoped `coding-agent-workflow` under a rename — PR #140 opened against the
  scoped name landed there — so installing `gh` is the only thing standing between
  these filings and publication.
- Tests: `bash tests/run.sh` → 2/42 files fail locally (11 assertions),
  **pre-existing and unrelated to this diff** — the session changed only
  `tasks/*.md`. Cause proven: a `chmod 000` file is readable by root (rc=0) and
  denied to `nobody` (rc=1). **CI on PR #140 ran the identical command on a
  non-root runner and passed in 52s**, so the repository is sound and the routine
  host is the defect. Preferred remedy is therefore to run the container as
  non-root rather than to add `geteuid()` guards, which would trade away coverage
  CI still has.

## Session Summary — 2026-09-15 [07e1ac0]
- Completed: 1 task — #132 metadata parser reads the span the writer owns
  (three locators unified on `metadata_spans` / `metadata_bounds`; five block
  states noted by both providers, damaged and competing bodies refused as
  rewrite targets; 50 new regression assertions; bug and pattern docs).
- Pending: none for this fix.
- Carry-forward: the configured `in-progress` label does not exist in the
  GitHub repo, so `/task-registry claim` cannot mark issues; 44 registry
  assertions and 8 suite files fail on this Windows host identically on clean
  master (#129, gh mock unreachable from Python; upstream-drift timing
  assertion at one-second clock granularity); pre-existing availability
  advisory — `_to_task` in `providers/github.py` lets a hostile `kind:` raise
  `TaskModelError` uncaught, fix shape is routing through `safe_task`.

---

# Plan: routine reproduction report — escalate, hold, and unblock
> Spec: specs/routine-reproduction-report.md
> Approved by direct `/build` request on 2026-09-12.

- [x] TDD: investigation hold configuration and selector enforcement -> add escalation-label config/default validation, additive label provider operation, authoritative readback, select/claim/workflow exclusion, and rollout guidance; mirror skill files (AC3, AC4, AC8, AC11, AC13)
- [x] TDD: structured blocker upsert outcomes -> expose `UpsertResult` behind the compatible public wrapper, preserve labels and terminal/held blockers, and distinguish unknown creation from confirmed external publication followed by index failure (AC6, AC7, AC12)
- [x] TDD: escalation command and ordered reporting -> add the validated `escalate` CLI/request v1, safe payload parsing, hold/readback/blocker/comment coordination, dry-run behavior, retained run artifact, and every partial-failure result (AC2, AC5–AC10, AC12)
- [x] TDD: routine integration and retained execution evidence -> update every debug/build/verify/wrap-up/sweep entry and stop path, run isolated reproduced/fixable and escalation scenarios, preserve canonical/Claude parity, and record e2e evidence (AC1, AC2, AC9, AC13, AC14)

## Session Summary — 2026-09-12 [ba11f75..7707342]
- Completed: 4 routine reproduction-report tasks, including implementation,
  deterministic regressions, verification-map maintenance, and retained CLI and
  debug-skill execution evidence.
- Pending: none for this plan.
- Carry-forward: live GitHub delivery remains outside the local verifier's
  capability ceiling; provider failure behavior is covered by deterministic
  adapter integration tests.

---

# Fix: #117 — Preserve published issue references across local-pending upserts
> Spec: specs/preserve-published-issue-references.md

- [x] TDD: regression test for local-pending fallback preserving a GitHub reference -> exercise the approval-gated local write and assert the compact index keeps the original issue link
- [x] TDD: regression test for approved publication after fallback -> assert the second upsert updates the original issue and does not create a duplicate
- [x] TDD: local provider preserves incoming external references -> keep the local detail location separate from a previously published tracker address
- [x] Verification: run the focused task-registry tests and full test suite -> confirm all acceptance criteria and parity checks

# Active issue

- [x] Unblock comprehensive verification audits and Git project bootstrap <!-- task-id: verification.full-audit-unblock --> <!-- task-kind: operational --> — Umbrella for #100–#103; bootstrap fixed via `git scaffold`, waves bounded. AC1 reinterpreted (git has no post-init hook, so `newproject` is the one-command path); AC5's `verify-coding-agent-workflow` audit lives outside this repo — re-run it there with the `git init` entry point remapped to `git scaffold`. ([#99](https://github.com/Joaovsales/jplugin-agentic-development/issues/99))
- [x] Replace the unsupported Git post-init bootstrap trigger <!-- task-id: bug.git-post-init-bootstrap --> <!-- task-kind: bug --> — Git has no post-init hook; explicit `git scaffold` alias, loud failure, `newproject` tested as printed. ([#100](https://github.com/Joaovsales/jplugin-agentic-development/issues/100))
- [x] Remove the bootstrap helper's hardcoded HOME checkout path <!-- task-id: bug.bootstrap-template-path --> <!-- task-kind: bug --> — Template installed to `~/.agents/project-template`, resolved relative to the script; spaced/non-default checkout covered. ([#101](https://github.com/Joaovsales/jplugin-agentic-development/issues/101))
- [x] Make automatic and manual project bootstrap complete and preservation-safe <!-- task-id: bug.bootstrap-template-completeness --> <!-- task-kind: bug --> — Full inventory copied, existing files byte-identical, README `cp` block replaced. ([#102](https://github.com/Joaovsales/jplugin-agentic-development/issues/102))
- [x] Allow full verifier maintenance to use bounded independent review waves <!-- task-id: verification.bounded-source-waves --> <!-- task-kind: operational --> — Source wave batched to worker slots, one independent review per feature, per-feature summary accounting. ([#103](https://github.com/Joaovsales/jplugin-agentic-development/issues/103))

## Plan: Memory maintenance history counting
> Spec: specs/memory-maintain-history-count.md
> Approved 2026-09-09; all four tasks completed and independently reviewed.

- [x] TDD: alternate and mixed history fixtures in tests/test-session-start.sh fail on the original hook -> recognize both existing session heading formats in the hook counter.
- [x] TDD: missing/empty history, four/six sessions, unrelated headings, and malformed dates -> preserve the positive-multiple-of-five boundary without false counts.
- [x] TDD: memory-maintain counting contract and skill parity -> align both skill copies with the hook while preserving force, light-pass, and glossary behavior.
- [x] TDD: relevant tests and full suite -> review the change, record hook walkthrough evidence in tasks/e2e-log.md, and update the bug document with verified results.

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

## Session Summary — 2026-09-08 [2bde026..2bde026]
- Completed: create-verification-skill invocation — mirrored verify-task-registry, three feature maps, live local CLI walkthrough and durable evidence.
- Pending: no remaining work for the requested skill creation; GitHub, installation, and full agent routines remain outside verified coverage; derived source/spec entry points passed during wrap-up.
- Carry-forward: use /maintain-verification-skill --scope changed after changes to mapped CLI behavior.

## Session Summary — 2026-09-09 [9017248..3ed5bcb]
- Completed: 5 tasks (#99, #100, #101, #102, #103 — Git bootstrap via `git scaffold`, bounded verifier waves)
- Pending: 0 tasks from this plan
- Carry-forward: `tests/test-task-registry.sh` "Doctor: the refused relaxation is visible to the user" fails on untouched `master` too — pre-existing, not addressed here

## Session Summary — 2026-09-09 [9017248..ca8142d]
- Completed: all four memory-maintenance history-count tasks. Hook and mirrored
  skill recognize canonical and alternate history headings; added boundary and
  pattern-parity regressions.
- Verification: 38 files / 3,589 assertions pass with the inherited
  TASK_REGISTRY_TRUSTED_CONFIG override cleared for tests. Nine live-hook cases,
  four mutation probes, five dispatched review passes; zero findings.
- Pending: none for this fix. Catch-up and duplicate-sweep prevention remain
  outside the approved heading-recognition scope.
- Carry-forward: specs/memory-maintain-history-count.md; diagnosis in
  tasks/solutions/bugs/memory-maintain-history-heading-drift.md;
  walkthrough in tasks/e2e-log.md.

## Plan: /system-design-planning — upstream architecture review skill
> Spec: specs/system-design-planning.md
> Requested 2026-09-11; skill authored for human review of the SKILL.md itself (the plan gate was the review of the delivered skill, not a pre-approval)

[x] Author `.agents/skills/system-design-planning/SKILL.md` -> iron law, when-to-use bar, 9-step process (intake via task-registry show, read-only recon, spec in fixed order, self-review, conditional critic, render, human gate, upsert per slice, /build handoff)
[x] Author `references/review-card.md`, `templates/architecture-spec-template.md`, `templates/content-model.json` -> review card in dependency order; spec skeleton; renderable content model
[x] Copy to `.claude/skills/system-design-planning/` -> byte-identical parity
[x] Register in `CLAUDE.md` (table + Spec First bullet), `README.md`, `.claude/hooks/session-start.sh`
[x] Pin the contract in `tests/test-doc-conventions.sh` (tokens, section order, iron law, registration, live render of the template) and `tests/test-skill-invocation-chain.sh` (task-registry, visual-render.py, /build handoffs)

## Session Summary — 2026-09-11 [bf58555..HEAD]
- Completed: 5 tasks — the /system-design-planning skill (SKILL.md, review card, spec template, content model), its spec, registration in CLAUDE.md/README/session-start, static pins in test-doc-conventions and test-skill-invocation-chain, byte-identical .claude copy. Plus: one worked example run of the skill against its own TODO(shortcut) → specs/upsert-depends-on.md + .plan.html (dispatched critic: 0 MUST-FIX, 9 SHOULD-FIX, 5 NITPICK, all folded in); tests/test-tdd-retirement.sh now excludes .claude/worktrees.
- Pending: filing the three upsert-depends-on slices waits for the reviewer's "approved" on the rendered document (D2 open: refuse or report a dangling dependency id).
- Carry-forward: /system-design-planning Step 8 keeps its TODO(shortcut) until specs/upsert-depends-on.md is built; 31 stale worktrees removed, the live bulk-read-gate worktree kept.

## Plan: /tidy — harness hygiene skill
> Spec: specs/tidy-skill.md
> Branch: feat/tidy-skill off origin/master d6c5e5b — built in the shared clone on feat/system-design-planning (whose PR #125 had already merged), moved to its own worktree at wrap-up
> Base: e7ab8fa. Skill only; the host routine (branch vocabulary, prompt, cadence) is out of scope.

[x] TDD: tests/test-doc-conventions.sh RED — `/tidy` pin block over both tree copies: frontmatter tokens, eight check rows, "skipped with a note", neither-producer-nor-consumer + three tiers, `git log --diff-filter=D` + tasks/ specs/ exemption, `bash install.sh` + `--prune-skills` + never modifies, squash-merge + `git branch --merged`, filing block (`--derive-id tidy`, `--fold-title`, documentation/tech-debt labels, `discovered: tidy`), write-policy table + backlog not a destination, no tracker task API, Laws 1/3/9/10, `tasks/sweeps/` + six sections in order + opens no PR, `--report` and `--check`, allowlist entries carry a reason; registration in CLAUDE.md, README.md, session-start.sh (AC-2..AC-12)
[x] TDD: GREEN -> write .agents/skills/tidy/SKILL.md — position in the routine contract, eight checks with surfaces, risk tiers, filing block, laws, inputs, outputs, edge cases, seed allowlist (AC-1..AC-11, AC-13: no script, no asset reference)
[x] TDD: GREEN -> register `/tidy` in CLAUDE.md skills table, README.md skills table, .claude/hooks/session-start.sh SKILLS AVAILABLE; AGENTS.md carries no skills table at baseline, so that surface is skipped per the skill's own rule (AC-12)
[x] TDD: copy byte-identical to .claude/skills/tidy/SKILL.md; test-skill-parity, test-skill-frontmatter, test-skill-references, test-syncable-paths green (AC-1, AC-13)
[x] Verification: `/tidy --report` executed by hand against a clean detached worktree at the base commit; report captured to the build's evidence (not committed) and checked against the six live Problem-table rows (AC-14)
[x] Verification: bash tests/run.sh — not fully green, but no regression: the changed tree fails the same 8 files / 148 assertions as a clean detached worktree at e7ab8fa (install-sh, routine-selectors, routine-skills, skill-invocation-chain, sync-retirement, task-registry, verification-skill-integration, upstream-drift), zero new failing assertion names; total assertions 3789 → 3903 (doc-conventions 521 → 620) (AC-15)

## Session Summary — 2026-09-15 [d6c5e5b..HEAD]
- Completed: 6 tasks — the /tidy skill (SKILL.md + byte-identical .claude copy), its spec, registration in CLAUDE.md/README/session-start, the static pin block in tests/test-doc-conventions.sh (670 assertions in that file), the AC-14 `--report` evidence run, the AC-15 no-regression check. Wrap-up: four dispatched review passes → 3 MUST-FIX fixed (retired set over both trees; inventory tiers by repository kind; Law 10 resolves origin/HEAD and STOPs on detached HEAD), the remaining applicable findings applied (pass 1: 4, pass 2: 10, pass 3: 8, pass 4: 3), AC-12/AC-15 spec wording and the descendant-allowlist home reported to the human. Suite duration on Windows filed as #136.
- Pending: none for this plan. The branch was moved out of the shared clone into its own worktree; the other session's stash@{0} in the main checkout still carries the pre-review copies of these files together with its own specs/bulk-read-gate.md — that stash is theirs to drop.
- Carry-forward: docs/task-tracking.md declares `tech-debt` and `design-decision` in kind_precedence, but the tracker carries only bug/enhancement/documentation/question, so the `fix` and `plan` selectors have nothing to select until the labels exist (surfaced while filing #136).
- Tests: bash tests/run.sh over the worktree at d6c5e5b + this change: 42 files, 35 pass, 7 fail (install-sh 1/94, routine-selectors 60/196, routine-skills 2/64, sync-retirement 47/329, task-escalation 1/62, task-registry 44/348, verification-skill-integration 2/90 — 157 assertions). Every failing file re-run in a clean detached worktree at d6c5e5b fails the same count with identical assertion names (gh resolved through PATHEXT, mktemp path forms, chmod on Windows): zero regressions. skill-invocation-chain and upstream-drift, failing at e7ab8fa, pass at this base. Guards: doc-conventions 670, parity 96, references 186, frontmatter 272, syncable-paths 10. The full run was killed at file 35 after 38 minutes and the remaining 8 files were run separately (#136).

## Plan: register `tidy` as a producer routine
> Spec: specs/tidy-skill.md § Out of scope (the host routine) — this is that host work
> Branch: feat/tidy-routine off origin/master 4637138 (#138 merged), own worktree
> Requested 2026-09-15 after #138 merged: "set the skill as a routine and run the routine for the first time"

[x] TDD: tests/test-routine-branch.sh RED -> `tidy` in CONTRACT_ROUTINES; `routine/tidy/20260915-sweep` round-trips
[x] TDD: tests/test-routines-contract.sh RED -> routines.md has a `tidy` table row and a `### tidy — steps` section that does not restate /wrap-up-session
[x] TDD: tests/test-routine-selectors.sh -> PRODUCER_ROUTINES names janitor,architect,tidy; `select --routine tidy` exits 2 naming "producer"
[x] TDD: tests/test-sweep-routines.sh -> wrap-up linkage table has the `routine/tidy/<YYYYMMDD>-sweep` row and `chore(tidy):` title; routine-prompts/tidy.md exists (<25 lines, names /tidy, says sub-agent, no repo name, parity copy); README routes tidy
[x] TDD: tests/test-doc-conventions.sh -> tidy SKILL.md names its branch and prompt file
[x] GREEN -> routine_branch.py + registry config.py vocabularies; routines.md (row, producers paragraph, spine step 3, tidy section, edge row); wrap-up parser row; routine-prompts/tidy.md + README row and checklist bullet; tidy SKILL.md host paragraph; tasks/concepts.md counts; byte-identical .claude copies
[ ] Cloud routine: update the existing `tidy` routine (trig_0156hDQVc2Qp5MuUx6j7ttxF) with routine-prompts/tidy.md, Planner-tier model, weekly cron; enable and run once after this PR merges; verify the run opened `chore(tidy): <date>` from `routine/tidy/<YYYYMMDD>-sweep` with the record under tasks/sweeps/

## Session Summary — 2026-09-15 [4637138..HEAD]
- Completed: 6 of 7 tasks — `tidy` is a contract producer routine (branch vocabulary, registry refusal, step ledger, wrap-up linkage row, scheduler prompt, README routing, glossary). Filed #136 (Windows suite duration) earlier this session; #138 merged.
- Pending: the cloud routine's first run waits for this PR to merge — a run against master before that fails at spine step 2 because `routine_branch.py format tidy` refuses a name outside CONTRACT_ROUTINES.
- Carry-forward: the cloud routine API exposes no environment-variable field, so `TASK_REGISTRY_TRUSTED_CONFIG=1` is stated in the scheduler prompt itself; if the cloud `gh` is unauthenticated the first run files everything as *publication pending* and the PR body names both switches. Label gap from the earlier summary still stands (`tech-debt`, `design-decision` absent from the tracker).
- Tests: affected files run in the worktree — routine-branch 21, routines-contract 71, sweep-routines 160, skill-parity 97, skill-frontmatter 272, skill-references 190, syncable-paths 10, doc-conventions 676, all green; routine-selectors 60/200, routine-skills 2/64 and skill-invocation-chain 4/72 fail with exactly the assertion names a clean detached worktree at 4637138 fails (the Windows gh-stub, cp1252 and grep-ordering set) — zero regressions, and every new tidy assertion passes. Full suite deferred to CI (#136).

## Tidy: 2026-09-16

> Record: `tasks/sweeps/2026-09-16-tidy.md`, swept at `80e265c` on
> `routine/tidy/20260916-sweep`. Outcome: **findings**. Tier 0 applied: **0** —
> withheld under Law 3, the suite is red. Tier 2 filed: **3**, all publication
> pending (provider `github` unreachable, `gh` not installed).

- [x] `suite` — RED, 2/42 files (11 assertions); cause established as uid 0
- [x] `inventory` — 3 findings; AGENTS.md surface skipped (absent)
- [x] `retired` — inconclusive (shallow clone)
- [x] `installed` — inconclusive (`install.sh` never run on this host)
- [x] `refs` — clean (17 expected-to-be-created, recorded as Unverified)
- [x] `worktrees` — inconclusive / report-only (no `gh`); nothing removable
- [x] `strays` — clean (no untracked or ignored files)
- [x] `registers` — 2 findings (16 closed plan blocks; checkpoint 6 days stale)

Filed this sweep:

- [ ] Permission-contract assertions cannot pass when the suite runs as uid 0 <!-- task-id: tidy.tests-test-sync-retirement-sh.permission-contract-assertions-cannot-pass-when-the-suite-runs-as-uid-0 --> — Eleven assertions across two test files encode "the OS refuses this write/read"; uid 0 holds CAP_DAC_OVERRIDE, so they… ([#141](https://github.com/Joaovsales/jplugin-agentic-development/issues/141))
- [ ] verify-task-registry is absent from every skills inventory surface <!-- task-id: tidy.claude-md.verify-task-registry-is-absent-from-every-skills-inventory-surface --> — The skill ships in both trees but appears in no skills table and not in the session-start banner, so it is invisible to… ([#142](https://github.com/Joaovsales/jplugin-agentic-development/issues/142))
- [ ] Sixteen closed plan blocks are still in the todo index <!-- task-id: tidy.tasks-todo-md.sixteen-closed-plan-blocks-are-still-in-the-todo-index --> — tasks/todo.md is specified as an index but carries 16 fully-checked plan blocks older than the last two session summari… ([#143](https://github.com/Joaovsales/jplugin-agentic-development/issues/143))
- [ ] Verify issue closure after a PR merged by the GitHub Actions app <!-- task-id: issue-linkage.agents-skills-wrap-up-session-references-routines-md --> — A PR whose body carried a single, correctly linked Closes #N merged into the default branch and the issue stayed open.… ([#146](https://github.com/Joaovsales/jplugin-agentic-development/issues/146))

## Plan: Claude Code plugin manifest over the canonical skill tree
> Spec: specs/claude-plugin-manifest.md
> Visual: specs/claude-plugin-manifest.plan.html
> Approved 2026-09-17 by Joaovsales
> Branch: worktree-plugin-manifest (worktree .claude/worktrees/plugin-manifest) off master 2608d0a. Slice order is the spec's Build order; slice 6 is gated on the S2 spike answer.

### Slice 1/7
- [x] Spike: manifest, routing, declaration <!-- task-id: design.specs-claude-plugin-manifest-md.spike-manifest-routing-declaration --> — Slice 1/7: .claude-plugin/plugin.json and marketplace.json, tests/test-plugin-manifest.sh, and four live answers in tas… ([#148](https://github.com/Joaovsales/jplugin-agentic-development/issues/148))
  [x] TDD: tests/test-plugin-manifest.sh RED — both manifests parse as JSON; `plugin.json.skills == "./.agents/skills"` and the directory exists; `plugin.json.name == marketplace.plugins[0].name == "jplugin"`; no `commands`/`agents`/`hooks` key; exactly one marketplace plugin with `source: "./"` -> write `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` per § Component contracts (slice criterion 1, AC 1, AC 10)
  [x] Spike S1: `claude plugin validate .` then a `claude --plugin-dir .` session lists exactly `basename(.agents/skills/*/)` as `jplugin:<name>` (33 skills) -> record command, output path and PASS/FAIL in tasks/e2e-log.md (slice criterion 3, AC 11)
  [x] Spike S2 (FAIL — `/verify` collides with Claude Code's bundled skill; see tasks/e2e-log.md): `/eval` triggerability for `/quality-gate`, `/verify`, `/task-registry` with the `~/.claude/skills/` template copies removed and the project `.claude/skills/` moved aside, plugin loaded via `--plugin-dir` -> PASS recorded in tasks/e2e-log.md; a FAIL halts the plan here and reopens § Decisions (slice criterion 4, AC 2)
  [x] Spike S3: add a directory-source marketplace named `jplugin-agentic-development`, then a github-source one under the same name -> record refused / replaced / coexisting; on "replaced" fix the directory-source name as `jplugin-agentic-development-dev` in § Decisions before slice 4 (slice criterion 3)
  [x] Spike S4 (PASS on 2.1.277 after a clean-trust re-run — the plugin is cached and loaded when the folder is trusted; `ref` must be a branch/tag and `version` pins; the 2.1.274 FAIL was a contaminated trust dialog; see tasks/e2e-log.md): scratch clone whose `.claude/settings.json` declares the github marketplace at a `ref` and enables the plugin -> record whether the install is offered/auto-registered and whether that ref is what loads; a FAIL rewrites the pinning-model row of § Decisions before slice 5 (slice criterion 4, AC 3)
  [x] Verification: `bash tests/run.sh` — same pass set as the 2608d0a baseline, zero new failing assertion names

### Slice 2/7
- [x] Repository identity <!-- task-id: design.specs-claude-plugin-manifest-md.repository-identity --> — Slice 2/7: every coding-agent-workflow literal in tracked files outside tasks/ and specs/ becomes jplugin-agentic-devel… ([#149](https://github.com/Joaovsales/jplugin-agentic-development/issues/149))
  [x] TDD: tests/test-repo-identity.sh RED — `git grep` (never `grep -r`: stale worktree checkouts under `.claude/worktrees/` carry the old name) for the old repository name and its title-case form over tracked files outside `tasks/` and `specs/` is empty; the needle is built at runtime so the test file itself is not a hit -> rename the literals in the 16 tracked files the census found (install.sh, README.md, sync and tidy SKILL.md in both trees, sync-template.yml, session-start.sh banner and comment, scaffold-project.sh, .agents/git-hooks/pre-push, .claude/deployments/github-actions.md, install-codex.sh, render-codex.py markers, codex/hooks/session_start.py, tests/test-install-sh.sh, tests/test-codex-install.sh); install path becomes `~/jplugin-agentic-development` (slice criterion 1, AC 4)
  [x] TDD: tests/test-codex-install.sh — a fixture `hooks.json` pre-seeded with the three old hook commands ends with exactly three hooks, all carrying `jplugin-agentic-development-*` ids, after one `install-codex.sh` run -> rename the four hook files in install-codex.sh and `session_start.py`; `merge_hooks` in render-codex.py replaces a hook whose command names the same event under the old id instead of appending (slice criterion 2, AC 4)
  [x] TDD: tests/test-repo-identity.sh — README.md contains `git remote set-url origin https://github.com/Joaovsales/jplugin-agentic-development.git` -> README § Keeping It Up to Date gains the one-line existing-clone step (slice criterion 3, AC 4)
  [x] Verification: `.claude/skills/` copies re-synced byte-identical (parity test still live until slice 6); `bash tests/run.sh` green (slice criterion 4)

### Slice 3/7
- [x] Canonical extras <!-- task-id: design.specs-claude-plugin-manifest-md.canonical-extras --> — Slice 3/7: setup-deployment and verify-deployment move to .agents/skills/ with harness: claude; the parity allowlist sh… ([#150](https://github.com/Joaovsales/jplugin-agentic-development/issues/150))
  [x] TDD: tests/test-skill-parity.sh `ALLOWLIST="README.md"` RED; tests/test-skill-frontmatter.sh green with `harness: claude` on the two moved skills -> `git mv` `.claude/skills/setup-deployment` and `verify-deployment` to `.agents/skills/`, add `harness: claude` with a `TODO(shortcut):` noting Pi and Codex installers copy them too, copy back to `.claude/skills/` byte-identical (slice criteria 1–2)
  [x] TDD: tests/test-doc-conventions.sh — `writing-skills/SKILL.md` no longer instructs the Claude-only extras allowlist -> rewrite the authoring instruction to the one-tree layout (spec § Build order slice 3)
  [x] Verification: `bash tests/run.sh` green (slice criterion 3)

### Slice 4/7
- [x] Installer <!-- task-id: design.specs-claude-plugin-manifest-md.installer --> — Slice 4/7: install_claude_plugin and remove_legacy_skill_copies (current plus retired template names, one y/N); step 2… ([#151](https://github.com/Joaovsales/jplugin-agentic-development/issues/151))
  [x] TDD: tests/test-install-sh.sh — a stub `claude` on PATH logs its argv: first run records one `plugin marketplace add <REPO_DIR>` and one `plugin install jplugin@<marketplace> --scope user`; a second run (stub reports the marketplace known and the plugin present) records neither and prints `already`; without `claude` on PATH the step prints the NOTE, exits 0 and touches nothing -> `install_claude_plugin REPO_DIR` replaces step 2 at install.sh:98-118; marketplace name per the S3 answer (slice criteria 1–2, AC 5)
  [x] TDD: tests/test-install-sh.sh — fixture `~/.claude/skills/` holding `aws-saml2aws-auth` (never carried), `plan` (current) and `tdd` (retired in history): `y` deletes `plan` and `tdd` and keeps `aws-saml2aws-auth`; `N` and EOF keep all three and print the manual command; `--prune-skills` exits 1 with the usage text -> `remove_legacy_skill_copies REPO_DIR CLAUDE_HOME` with candidates = current names ∪ `git log --diff-filter=D` names over both trees (shallow history → candidates are current names only, said aloud); delete `extra_global_skills`, `prune_extra_skills`, `PRUNE_SKILLS` and the flag; header comment and usage rewritten (slice criteria 3–4, AC 5)
  [x] TDD: tests/test-install-sh.sh — step 3 still copies `.agents/skills/` to `~/.agents/skills/` unchanged -> no change to step 3 beyond the repository name (AC 6)
  [x] TDD: tests/test-doc-conventions.sh — `/tidy` `installed` row names `~/.claude/plugins/installed_plugins.json` and the legacy-copy list; no `--prune-skills` literal anywhere in tracked files -> tidy SKILL.md `installed` check and remedy text; README install section describes the plugin step (spec § Build order slice 4)
  [x] Verification: `.claude/skills/` copies re-synced; `bash tests/run.sh` green

### Slice 5/7
- [x] Sync contract <!-- task-id: design.specs-claude-plugin-manifest-md.sync-contract --> — Slice 5/7: .claude/settings.json plugin declaration in the template; Syncable Paths RETIRED row; sync-retire.py retired… ([#152](https://github.com/Joaovsales/jplugin-agentic-development/issues/152))
  [x] TDD: tests/test-sync-retirement.sh — `parse_syncable_roots` returns `(live_roots, retired_roots)` with `.claude/skills/` in `retired_roots` only; `usable_roots` never counts a retired root toward the one-empty-root budget -> Syncable Paths row `.claude/skills/ → RETIRED — …`; parser reads the right-hand `RETIRED` marker; three existing callers updated (slice criterion 1, AC 7)
  [x] TDD: tests/test-sync-retirement.sh — fixture project with a history-known `.claude/skills/plan/SKILL.md`: settings lacking `enabledPlugins["jplugin@jplugin-agentic-development"]` exits non-zero naming `.claude/settings.json` and the `/sync` step that writes it; with the key present the path is listed under `retire`; a project-local `.claude/skills/verify-myapp/SKILL.md` appears under neither; unreadable settings JSON raises `RetireError` naming the file -> `retired_root_candidates` (bytes matched against template history, never path membership) and `require_project_plugin` in sync-retire.py (slice criterion 2, AC 7)
  [x] TDD: tests/test-plugin-manifest.sh — template `.claude/settings.json` carries `extraKnownMarketplaces["jplugin-agentic-development"]` as a github source with no `ref`, `enabledPlugins["jplugin@jplugin-agentic-development"] == true`, and the `hooks`/`env` blocks unchanged -> settings.json declaration (slice criterion 3, AC 3)
  [x] TDD: tests/test-syncable-paths.sh — six hand copies pinned (`SYNC_COPY` assertions removed), the `RETIRED` row present in the doc block and excluded from every checkout list; `.claude/hooks/session-start.sh` drift list drops `.claude/skills`; `sync-template.yml` contains no `mirror ".claude/skills"` and its header and PR body name the retirement -> `/sync` diff commands, session-start.sh:356, README, workflow (slice criteria 3–4, AC 7)
  [x] TDD: tests/test-doc-conventions.sh — `/sync` Step 5 states it writes the checked-out sha as `ref` into the project's `extraKnownMarketplaces` entry and merges the two keys rather than overwriting; Step 6.4 states the project-plugin guard; session-start.sh prints one line when `enabledPlugins` names the plugin and `~/.claude/plugins/installed_plugins.json` does not -> SKILL.md Steps 5 and 6.4, session-start.sh (AC 3, AC 7)
  [x] Verification: `.claude/skills/` copies re-synced; `bash tests/run.sh` green

### Slice 5b — Pinning model (decision A, 2026-09-18)
- [x] Release-pinned declaration <!-- task-id: design.specs-claude-plugin-manifest-md.release-pinned-declaration --> — Slice 5b: `/sync` Step 5 writes no `ref`; `plugin.json` `version` pins; `session-start.sh` accepts the versioned cache as the install record (S4 corrections 1 and 2)
  [x] TDD: tests/test-plugin-manifest.sh — `.agents/skills/sync/SKILL.md` Step 5 contains no `["ref"]` write and names `version` as the pin; README § Keeping It Up to Date names the version bump -> rewrite the Step 5 paragraph and snippet to merge the two keys only; README release step (AC 3)
  [x] TDD: tests/test-doc-conventions.sh — the `/sync` token list drops `"ref"` and `Step 5 writes`, gains `version` -> token list (AC 3)
  [x] TDD: tests/test-session-start.sh — enabled + no `installed_plugins.json` record + `plugins/cache/jplugin-agentic-development/jplugin/<version>/` present is silent; enabled with neither prints the line -> session-start.sh checks the cache directory as well (S4: a settings-driven install writes no `installed_plugins.json` record)
  [x] Verification: `.claude/skills/` copies re-synced; `bash tests/run.sh` green

### Slice 5c — Rename `verify` → `verify-evidence` (S2 decision A, 2026-09-18)
- [x] Rename the verify skill <!-- task-id: design.specs-claude-plugin-manifest-md.rename-verify-evidence --> — Slice 5c: `.agents/skills/verify/` becomes `verify-evidence` in both trees; every `/verify` reference outside the historical logs follows; the old name retires through history
  [x] TDD: tests/test-plugin-manifest.sh — `.agents/skills/verify/` absent; `.agents/skills/verify-evidence/SKILL.md` frontmatter `name: verify-evidence`; `git grep -E '(^|[^a-zA-Z0-9_-])/verify([^a-zA-Z0-9_-]|$)' -- .agents .claude/hooks .claude/browsers CLAUDE.md README.md tests` empty -> `git mv` both trees; rewrite the references, the banner line, the CLAUDE.md and README tables, the test paths (AC 2)
  [x] Gate re-probe: `claude -p "/verify-evidence"` with `--plugin-dir` on a tree without `.claude/skills/` expands to `<command-name>/jplugin:verify-evidence</command-name>` -> recorded in tasks/e2e-log.md as the S2 follow-up (AC 2)
  [x] Verification: `.claude/skills/` copies re-synced; `bash tests/run.sh` green

### Slice 6/7
- [x] Remove the copy <!-- task-id: design.specs-claude-plugin-manifest-md.remove-the-copy --> — Slice 6/7: delete .claude/skills/ and tests/test-skill-parity.sh; rewrite the two-tree tests to loop over .agents/skill… ([#153](https://github.com/Joaovsales/jplugin-agentic-development/issues/153))
  [x] Gate: tasks/e2e-log.md holds the S2 follow-up PASS for `/verify-evidence` (slice 5c); otherwise stop here and reopen § Decisions (AC 2)
  [x] TDD: the 23 tests that walk `.claude/skills/` rewritten to loop over `.agents/skills/` only; `tests/test-skill-parity.sh` deleted; `git grep -l test-skill-parity` empty -> `git rm -r .claude/skills` (slice criteria 1, 3, AC 1, AC 10)
  [x] TDD: tests/test-plugin-manifest.sh — `git grep -l 'jplugin:' -- .agents/skills .claude/agents AGENTS.md PI_SETUP.md` empty; CLAUDE.md contains the namespace sentence exactly once -> CLAUDE.md Key Directories loses the `.claude/skills/` row and § Skills gains the sentence from spec § CLAUDE.md — namespace sentence (slice criterion 2, AC 9)
  [x] TDD: tests/test-skill-references.sh premise reworded (the template ships nothing under `.claude/skills/`; executed paths there still forbidden) -> README.md § Skills row, `.agents/agents/README.md:11`, tasks/concepts.md, tidy inventory rows, task-registry `SKILL_ROOTS` comment and `templates/task-tracking.md:119`, project-local-skill wording in `create-verification-skill`, `maintain-verification-skill`, `verify` (spec § Project-local skills)
  [x] Verification: `bash tests/run.sh` green (slice criterion 4)

### Slice 7/7
- [x] Retire legacy shims <!-- task-id: design.specs-claude-plugin-manifest-md.retire-legacy-shims --> — Slice 7/7: /sync Steps 2.5 and 2.6 deleted; session-start.sh CLAUDE.md fallback and deprecation hint deleted; .claude/d… ([#154](https://github.com/Joaovsales/jplugin-agentic-development/issues/154))
  [x] TDD: tests/test-doc-conventions.sh pin block RED — `git grep -l` for `commands.legacy`, `Step 2.5`, `Step 2.6`, `auto-test-runner` is empty; `tests.md` absent; session-start.sh contains no `TARGETS_IN_CLAUDE` -> delete `/sync` Steps 2.5 and 2.6 (SKILL.md:195-262), the session-start.sh CLAUDE.md fallback and deprecation hint (:275-295), `.claude/deployments/README.md:151` sentence, `verify/SKILL.md:65` "primary"; `git rm` `.claude/hooks/auto-test-runner.sh`, `.ps1`, `tests.md` with README.md:345,369,376 (slice criteria 1–2, AC 8)
  [x] Verification: `/tidy --report` `retired` check lists zero live references for auto-improve route tdd deslop simplify verify-e2e aposd-guardrail (slice criterion 3)
  [x] Verification: `bash tests/run.sh` green (slice criterion 4)

## Plan: Grilling Adoption
> Spec: specs/grilling-adoption.md
> Branch: worktree-grilling-adoption (worktree .claude/worktrees/grilling-adoption), rebased onto master 0de3f8a (#156) on 2026-09-21 — one canonical skill tree, no `.claude/skills/` copy, `/verify-evidence`.

[x] TDD: tests/test-grilling-adoption.sh RED — frontmatter pins for `grilling` (`disable-model-invocation: false`) and `grill-me` (`true`), round-format tokens (`❓`, `➡️`, frontier, "Do not act"), the opt-out sentence, brainstorm naming `/grilling` and `references/domain-modeling.md`, the three gates, `tasks/concepts.md` and `tasks/solutions/architecture`, the writing-skills exception naming `/grill-me`, the `c55ee46` baseline in `.github/upstreams.json`, the THIRD_PARTY_NOTICES section, CLAUDE.md / README / banner rows, `LICENSE.mattpocock` present -> write the assertions first; `tests/run.sh` discovers it through its `tests/test-*.sh` glob (AC 1–10)
[x] TDD: grilling pins green -> `.agents/skills/grilling/SKILL.md` adapted from upstream (design tree, frontier rounds, `❓`/`➡️` format, facts via Scout tier, decisions to the user, empty-frontier end, confirmation gate, opt-out in `CLAUDE.local.md` / `~/.pi/agent/AGENTS.md`) + `LICENSE.mattpocock`; no `jplugin:` literal in the body (AC 1, 3)
[x] TDD: grill-me pins green and the writing-skills pin green -> `.agents/skills/grill-me/SKILL.md` (`disable-model-invocation: true`, `argument-hint`, invokes `/grilling`, writes no files, needs no repo, routes repo features to `/brainstorm`) + `LICENSE.mattpocock`; amend the writing-skills frontmatter note (false default, true exception naming `/grill-me`, harness check) (AC 2, 3, 6)
[x] TDD: brainstorm pins green while `tests/test-doc-conventions.sh` (lightpanda), `tests/test-tdd-retirement.sh` and `tests/test-living-spec-reconciliation.sh` stay green -> rewrite Step 3 to invoke `/grilling` with the seed frontier and the domain layer; add `references/domain-modeling.md` (glossary challenge, sharpening, scenarios, code cross-reference, inline `tasks/concepts.md` writes in the `/learn` format, glossary-only rule, three-gate `tasks/solutions/architecture/<slug>.md` offered not assumed, overlap-scored per `/learn`); add the `tasks/concepts.md` read to Step 1; replace the one-question-at-a-time principle with rounds, facts-vs-decisions and glossary-only in Overview and Key Principles (AC 4, 5)
[x] TDD: `tests/test-skill-invocation-chain.sh` asserts `brainstorm` → `/grilling` and `grill-me` → `/grilling` -> add the two chain blocks (AC 10)
[x] TDD: registry pins green and `python3 scripts/check-upstream-drift.py` accepts the registry -> add the `mattpocock-skills` source (url, `refs/heads/main`, baseline `c55ee46073ed923f86ce59a5eb3b6d895095d1b7`, four paths, `source_notice`) to `.github/upstreams.json`; add the THIRD_PARTY_NOTICES.md section with pinned links and MIT text (AC 7, 8)
[x] TDD: inventory pins green and `tests/test-session-start.sh` green -> `/grilling` and `/grill-me` rows in the CLAUDE.md skills table, the README.md skills table, and the `SKILLS AVAILABLE` block of `.claude/hooks/session-start.sh`; `mattpocock/skills` in README § Sources (AC 9)
[x] TDD: `bash tests/run.sh` green with frontmatter, references, plugin-manifest, repo-identity, syncable-paths and solutions-schema included -> fix any drift; no test skipped (AC 10)
[x] e2e: `/jplugin:grill-me <idea>` typed in the desktop harness starts a `❓`/`➡️` round and leaves `git status` unchanged; a refusal flips the flag per the spec's Edge Cases and emits `[AMBIGUITY]` -> `/verify-evidence --scope e2e`, entry in `tasks/e2e-log.md` (AC 11)
[x] e2e: `/brainstorm` on a sample idea produces a first `❓`/`➡️` round and writes one term to `tasks/concepts.md` before the spec step, then the sample term is reverted -> `/verify-evidence --scope e2e`, entry in `tasks/e2e-log.md` (AC 12)
[x] eval: `/eval` Mode A triggerability of `grilling` from at least three organic brainstorm-shaped prompts, hit rate recorded; `UNVERIFIED` with the reason if the eval harness cannot run here -> entry in `tasks/e2e-log.md` (AC 13)

## Session Summary — 2026-09-21 [0de3f8a..HEAD]
- Completed: 11 tasks (Grilling Adoption plan: 7 TDD + suite task + 2 e2e + 1 eval; all 13 ACs evidenced)
- Pending: 1 task (the unrelated `tidy` cloud-routine row above; whole file 158 [x])
- Carry-forward: six `manual`/`advisory` design-review findings on brainstorm Step 3 and `references/domain-modeling.md` (rhythm rule stated in two files, callee format restated in the caller, undeclared seed frontier, glossary rule stated three times, `/learn` overlap rule bug-track shaped, `harness: universal` proven on Claude Code only) — reported in the PR, not applied; the `/plan` Step 1 / `/prd` / `/system-design-planning` follow-up is filed through `/task-registry` only after confirmation (spec § Out of Scope)
- [ ] /learn overlap dimensions are bug-track shaped, so knowledge-track decisions cannot reach the update-in-place branch <!-- task-id: learn.agents-skills-learn-skill-md --> — The five overlap dimensions in /learn Step 4 (problem, root cause, solution, files touched, prevention rule) describe a… ([#168](https://github.com/Joaovsales/jplugin-agentic-development/issues/168))

## Plan: single-instruction-file
> Spec: specs/single-instruction-file.md
> Visual: specs/single-instruction-file.plan.html
> Approved 2026-09-22 by Joaovsales (reviewer decisions recorded in the spec; /build invoked on the spec)

### Slice 1/6
- [x] References move <!-- task-id: design.specs-single-instruction-file-md.references-move --> — Slice 1/6: the three protocol references under .agents/references/ with verbatim text, CLAUDE.md stubs, citations repoi… ([design.specs-single-instruction-file-md.references-move](tasks/details/design.specs-single-instruction-file-md.references-move.md))
  [x] TDD: test-review-context.sh, test-model-tiers.sh, test-agents.sh, test-doc-conventions.sh M1/M2 repointed to `.agents/references/*.md` -> `.agents/references/{finding-model,review-dispatch-contract,model-routing}.md` with verbatim text and the fixed heading set; the CLAUDE.md sections become three-line stubs
  [x] TDD: new tests/test-citations.sh resolves every backticked-path § *Heading* citation under .agents/, .claude/agents/ and AGENTS.md to a heading in that file -> the 11 citing files repointed in both agent trees
  [x] TDD: test-syncable-paths.sh passes with `.agents/references/` in every copy -> doc block, both diff commands, the drift check and the CI mirror gain the root
  [x] TDD: test-review-context.sh requires the reference and the refusal line at every dispatch site -> /quality-gate, /wrap-up-session, /software-design-expert-review, /sweep read finding-model.md § Emission format at dispatch time and refuse when it is missing

### Slice 2/6
- [x] Single AGENTS.md and its delivery <!-- task-id: design.specs-single-instruction-file-md.single-agents-md-and-its-delivery --> — Slice 2/6: the managed block in AGENTS.md, CLAUDE.md reduced to @AGENTS.md, .claude/project.md merged and deleted, sync… ([design.specs-single-instruction-file-md.single-agents-md-and-its-delivery](tasks/details/design.specs-single-instruction-file-md.single-agents-md-and-its-delivery.md))
  [x] TDD: tests/test-sync-managed-block.sh first half (append, replace current and legacy markers, unchanged on re-run, outside-block cmp, exit 2 on unmatched marker with nothing written, --dry-run writes nothing, CLAUDE.md written) -> `.agents/skills/sync/scripts/sync-managed-block.py` without --migrate
  [x] TDD: tests/test-instruction-budget.sh (block ≤ 200 lines, file ≤ 16 KiB, CLAUDE.md byte-equal to `@AGENTS.md`, heading set in order, no `@` line, ≤ 1 H1, no POINTER_RE match, `[AMBIGUITY]` format and `TODO(shortcut):` present) -> the managed block authored in AGENTS.md; Pi AGENTS.md and .claude/project.md project sections merged below the end marker; CLAUDE.md → `@AGENTS.md`; .claude/project.md deleted; project-template seeds
  [x] TDD: every CLAUDE.md / .claude/project.md assertion in the existing tests repointed (doc-conventions, routine-skills AC7, task-registry pointer fixtures gain the legacy notice, session-start Deployment Targets fixture, codex-install) -> readers repointed with the one-line legacy notice: POINTER_FILES, session-start.sh, /setup-deployment (writes AGENTS.md), /verify-deployment, /verify-evidence, /wrap-up-session, .claude/deployments/*.md, /build Ambiguity citation, agents
  [x] TDD: test-syncable-paths.sh passes with the rows `AGENTS.md (managed block)` and `CLAUDE.md (pointer)`; a fixture project synced from this branch ends with a block and the pointer in one run -> /sync Step 5 calls the script instead of checking out CLAUDE.md; sync-template.yml mirrors through it; render_global reads the block from AGENTS.md
  [x] TDD: test-install-sh.sh asserts `~/.claude/CLAUDE.md` is not created -> install.sh step 1 removed
  [ ] /eval triggerability gate on /plan, /build, /quality-gate — manual, before the slice-2 merge; report path goes in the PR body — DEFERRED (manual gate; run before the slice-2 PR merges, not inside /build)

### Slice 3/6
- [x] Plugin hooks, slim banner, hook retirement <!-- task-id: design.specs-single-instruction-file-md.plugin-hooks-slim-banner-hook-retirement --> — Slice 3/6: hooks/hooks.json registers the three events against .agents/hooks/*.sh, .claude/hooks/ retired, .claude/sett… ([design.specs-single-instruction-file-md.plugin-hooks-slim-banner-hook-retirement](tasks/details/design.specs-single-instruction-file-md.plugin-hooks-slim-banner-hook-retirement.md))
  [x] TDD: tests/test-hooks-json.sh (valid JSON, exactly three events, each command starts `bash "${CLAUDE_PLUGIN_ROOT}/.agents/hooks/`, each runs through `bash -c` with a spaced, backslashed root) -> `hooks/hooks.json`; scripts moved to `.agents/hooks/`; plugin `version` bump
  [x] TDD: test-settings-json.sh asserts no SessionStart/PreCompact/Stop; `.claude/hooks/` has no `*.sh` and its row begins RETIRED -> `.claude/settings.json`; syncable-paths block; install-codex.sh copies from `.agents/hooks/`; test-pre-compact.sh and test-session-start.sh run the new path
  [x] TDD: a /sync fixture settings.json carrying `bash .claude/hooks/session-stop.sh` and `pre-compact.sh` ends with neither entry and its other keys byte-identical -> /sync Step 5 settings merge drops matching entries
  [x] TDD: test-session-start.sh: clean fixture prints no ⚠ and no SKILLS AVAILABLE; stale graph prints the stale line; adopting fixture without a block prints the missing-block line, non-adopting prints nothing -> banner without skills list and footer, adoption-gated missing-block line, graphify lines
  [x] TDD: a dispatching skill with the project reference removed resolves it from `${CLAUDE_PLUGIN_ROOT}` before refusing -> D19 fallback chain in the dispatching skills; /tidy gains the `graph` check row

### Slice 4/6
- [x] Sync project migration and drift <!-- task-id: design.specs-single-instruction-file-md.sync-project-migration-and-drift --> — Slice 4/6: sync-managed-block.py --migrate moves everything but the five generic sections below the end marker and dele… ([design.specs-single-instruction-file-md.sync-project-migration-and-drift](tasks/details/design.specs-single-instruction-file-md.sync-project-migration-and-drift.md))
  [x] TDD: test-sync-managed-block.sh second half (--migrate moves pointer, targets table, `## Tech Stack` in order and deletes project.md; the five generic sections stay; exit 2 on a doubled targets table with project.md intact; re-run reports nothing to move) -> `sync-managed-block.py --migrate`
  [x] TDD: a template commit touching only text below the end marker produces no drift line -> /sync Step 6.6 runs --migrate inside the approved run; banner drift compares block hashes

### Slice 5/6
- [x] install.sh stops copying <!-- task-id: design.specs-single-instruction-file-md.install-sh-stops-copying --> — Slice 5/6: install.sh step 5 removed, one-confirmation removal of stale ~/.claude/CLAUDE.md, ~/.claude/hooks/session-st… ([design.specs-single-instruction-file-md.install-sh-stops-copying](tasks/details/design.specs-single-instruction-file-md.install-sh-stops-copying.md))
  [x] TDD: test-install-sh.sh: settings.json gains no session-start.sh; template-headed and pointer-only `~/.claude/CLAUDE.md` listed and removed on y, kept on N with Kept(n) and the double-banner note; a personal one never listed; SessionStart entry and script removed together -> install.sh step 5 removed, removal step with one confirmation
  [x] TDD: test-codex-install.sh: `$CODEX_HOME/AGENTS.md` not created; a pre-seeded block is stripped with personal text intact; render_global absent -> install-codex.sh stops rendering the global file; render-codex.py loses render_global; README Layer 1 rewritten; /tidy `installed` check updated

### Slice 6/6
- [x] README skills table generator <!-- task-id: design.specs-single-instruction-file-md.readme-skills-table-generator --> — Slice 6/6: scripts/render-skills-table.py renders the README skills table from SKILL.md frontmatter between markers; --… ([design.specs-single-instruction-file-md.readme-skills-table-generator](tasks/details/design.specs-single-instruction-file-md.readme-skills-table-generator.md))
  [x] TDD: tests/test-skills-table.sh (--check exits 0 on HEAD, 1 with a diff on a removed row, 2 naming the directory on a skill without description) -> `scripts/render-skills-table.py`, README markers, /tidy `inventory` names the generator with the `<template-clone>` prefix

## Session Summary — 2026-09-22 [dfbbe2b..5d1c595 + bookkeeping]
- Completed: origin/master (#176, dfbbe2b) merged into `feat/single-agents-file` with #176's `CLAUDE.md` § Workflow ported into `AGENTS.md` § Workflow steps 2 to 4 and its inventory pins onto the rendered `README.md` row; spec `implementation_paths` expanded for the shared glob matcher; living-spec reconciliation (17 specs updated, `specs/separate-project-config.md` removed); wrap-up review applied (install.sh exact hook match + atomic settings write + `.pre-plugin.bak`, `sync-managed-block.py` rules-segment keep + migration notes + padded markers + UTF-8 refusals, `/sync` prune by script name, `/system-design-planning` reads the finding model, orphaned `.claude/project.md` banner line, CI mirror body); `tests/lib.sh` exports `PYTHONUTF8=1`
- Pending: 1 row — the `/eval` triggerability gate on `/plan`, `/build`, `/quality-gate` (slice 2, manual, before the PR merges); the 3 `upsert --parent` GitHub-mock pins from #176 wait for the PR's Linux CI run (#129)
- Carry-forward: owner-human decisions reported in the PR body — CI executes the fetched sync script from a mutable ref and interpolates `template_ref` unquoted (pre-existing), the `/tmp` sentinel (pre-existing), whether the CI mirror should ever migrate `.claude/project.md`, the D4 `~/.claude/CLAUDE.md` overwrite policy; the three legacy-format specs received factual path edits only; 12 stale worktrees under `.claude/worktrees/` belong to other sessions

## Plan: fewer-full-suite-runs
> Spec: specs/fewer-full-suite-runs.md
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/178

### Slice 1/4 — Cached suite runner
- [x] Cached suite runner <!-- task-id: plan.specs-fewer-full-suite-runs-md.cached-suite-runner --> — Slice 1/4 of #178: `cached-suite.sh` reuses a green run per working tree and command, and refuses a second concurrent s… ([#183](https://github.com/Joaovsales/jplugin-agentic-development/issues/183))
  [x] TDD: tests/test-cached-suite.sh § reuse — first run passes output and status through; second run on the same tree and command prints `cached-suite: reused green run` without running; a red run is not recorded; an edited file, an untracked new file and a different command each run again -> `.agents/skills/build/scripts/cached-suite.sh`: working-tree key via temporary index (`GIT_INDEX_FILE`, `git add -A`, `git write-tree`) plus the hashed command; records under `$(git rev-parse --git-common-dir)/cached-suite/`; uncached with a stderr note outside a git repo (AC 1)
  [x] TDD: tests/test-cached-suite.sh § lock — a second invocation while one runs exits 3 with `cached-suite: a suite is already running` and starts nothing; a lock naming a dead pid is reclaimed -> `mkdir` lock with pid and start time, removed on exit trap, `kill -0` staleness check (AC 2)

> Handover: landed cddf272..5362005 — `.agents/skills/build/scripts/cached-suite.sh -- <cmd>` (100755) and `tests/test-cached-suite.sh` (32 assertions green)
> Do not re-derive: the lock is taken before the cache lookup, so even a would-be reuse exits 3 while a suite runs; the lock is `<common-dir>/cached-suite/lock/owner` = `<pid> <ISO UTC>`, taken by `mkdir` as the atomic test-and-set with the owner line written right after, removed only by the process the owner line names; an ownerless lock over a minute old is stale (449765d, 1cf575a); key = temp-index `write-tree` (seeded from a copy of the real index) + `git hash-object` of the NUL-joined argv; reuse line is `cached-suite: reused green run of <argv joined by spaces> on tree <sha> from <YYYY-MM-DD HH:MM:SS UTC>`; exit 2 on usage or an unhashable tree
> Surface: none undeclared in cddf272..5362005

### Slice 2/4 — Affected-test selector
- [x] Affected-test selector <!-- task-id: plan.specs-fewer-full-suite-runs-md.affected-test-selector --> — Slice 2/4 of #178: `tests/affected.sh` lists and runs the test files a change touches; `tests/run.sh` takes named files ([#180](https://github.com/Joaovsales/jplugin-agentic-development/issues/180))
  [x] TDD: tests/test-run-sh.sh § named files — `bash tests/run.sh tests/test-alpha.sh` runs only that file; no arguments runs every file as before; a missing named path exits 2 -> positional file arguments in `tests/run.sh` (AC 3)
  [x] TDD: tests/test-affected.sh — in a fixture repo: a changed test file, an added untracked test file and a test naming a changed path verbatim are listed sorted and unique; an unrelated test is not; a change to `tests/lib.sh`, `tests/run.sh` or `tests/affected.sh` lists every file; no change prints `affected: none` and exits 0; `--run` runs the list through `tests/run.sh` -> `tests/affected.sh <base> [--run]` (AC 3)

> Handover: landed 5362005..53f0f94 — `tests/run.sh [--jobs N] [file ...]` (missing path exits 2) and `tests/affected.sh [--run] <base>` (either argument order; unknown base exits 2); `tests/test-affected.sh` 15 and `tests/test-run-sh.sh` 41 assertions green
> Do not re-derive: the declared command for slice 3 is `bash tests/affected.sh --run {base}`; any change to `tests/run.sh`, `tests/lib.sh` or `tests/affected.sh` selects every file, so on this branch the affected run is still the whole suite until the base moves past 53f0f94; `git diff` runs with `core.safecrlf=false` because the Windows CRLF warning otherwise lands in the list
> Surface: none undeclared in 5362005..53f0f94

### Slice 3/4 — Build runs affected tests
- [x] Build runs affected tests <!-- task-id: plan.specs-fewer-full-suite-runs-md.build-runs-affected-tests --> — Slice 3/4 of #178: `/build` runs the full suite only at its cached baseline and the declared affected-test command ever… ([#181](https://github.com/Joaovsales/jplugin-agentic-development/issues/181)) (blocked-by: plan.specs-fewer-full-suite-runs-md.cached-suite-runner, plan.specs-fewer-full-suite-runs-md.affected-test-selector)
  [x] TDD: tests/test-doc-conventions.sh § fewer full runs (build) — pre-flight baseline names `cached-suite.sh` and records the base SHA; Step 3, the slice close, the parallel barrier, Phase 2 and the post-quality-gate step name the `Affected tests:` command with `{base}` and the declared-none fallback; "Full test suite after every task" is gone -> rewrite those `/build` steps and Key Principles (AC 4)
  [x] TDD: tests/test-doc-conventions.sh § affected declaration — `AGENTS.md` below the end marker carries `Affected tests: bash tests/affected.sh --run {base}` -> add the line under § Project-Specific Rules (AC 7)

> Handover: landed 53f0f94..cc18008, amended by 449765d — `/build` pre-flight records the base SHA, runs the baseline through `cached-suite.sh`, and resolves the affected-test command; Step 3, the parallel barrier, Slice Close, Phase 2 (renamed "Affected-Test Validation") and Phase 3 run it; `AGENTS.md` § Test Commands declares `Full suite: bash tests/run.sh` and `Affected tests: bash tests/affected.sh --run {base}`
> Do not re-derive: the design review made the full-suite command a declaration too (the cache key hashes argv, so five skills spelling it by hand would miss) and put the affected run behind the lock; `tests/test-skill-invocation-chain.sh` anchors Phase 2 on `^## Phase 2 .*Validation`
> Surface: +tests/test-skill-invocation-chain.sh (Phase 2 heading anchor), reported as [SURFACE]

### Slice 4/4 — Wrap-up and pipelines use the cache
- [x] Wrap-up and pipelines use the cache <!-- task-id: plan.specs-fewer-full-suite-runs-md.wrap-up-and-pipelines-use-the-cache --> — Slice 4/4 of #178: `/wrap-up-session`, `/yolo` and `/auto-push` run full suites through the cache; `/build` and `/wrap-… ([#182](https://github.com/Joaovsales/jplugin-agentic-development/issues/182)) (blocked-by: plan.specs-fewer-full-suite-runs-md.build-runs-affected-tests)
  [x] TDD: tests/test-doc-conventions.sh § fewer full runs (wrap-up, pipelines) — `/wrap-up-session` Step 6 and the Step 7.5 merged-result run, `/yolo` and `/auto-push` pre-flight baselines name `cached-suite.sh` -> one sentence each (AC 5)
  [x] TDD: tests/test-doc-conventions.sh § one suite, no polling — `/build` and `/wrap-up-session` forbid any test run while a suite runs and forbid foreground `sleep` or poll loops, and launch the full suite in the background waiting on its completion notification -> a shared rule paragraph in each (AC 6)
  [x] Verify: `gh run list --workflow tests.yml --status success --limit 10` — every run under 2 min, so `timeout-minutes: 15` exceeds the Linux suite time; `tests.yml` unedited (AC 8)

> Handover: landed cc18008..73b0944, amended by 449765d — `/wrap-up-session` Step 6 and the Step 7.5 merged-result run, `/yolo` and `/auto-push` baselines go through `cached-suite.sh -- <the declared Full suite: command>`; `/build` pre-flight and `/wrap-up-session` Step 6 carry the "One suite at a time, no polling." paragraph; AC 8: the last ten green `tests.yml` runs took 45–64 s, `tests.yml` unedited
> Do not re-derive: the no-polling paragraph is duplicated in two skills on purpose within this surface (a shared reference file was reported, not applied); red proven by running the new `test-doc-conventions.sh` on the cddf272 tree — exactly the 38 new assertions failed
> Surface: none undeclared in cc18008..73b0944

## Session Summary — 2026-09-23 [cddf272..d1d04eb]
- Completed: 4 slices of `## Plan: fewer-full-suite-runs` (#183, #180, #181, #182 — 8 TDD rows, 1 Verify row); quality-gate portability fixes; design review's `Full suite:` declaration; pre-push review fixes (rename-aware selector, safecrlf-proof hashing, owner-checked lock, no record for a tree edited mid-run, pipelines leave the baseline to `/build`, lock refusal is not a test result, no tree edits during a run, test commands in the managed block, `tasks/*.log` ignored)
- Pending: none in this plan; the issues close on merge through the PR's `Closes` lines
- Carry-forward (reported, not applied): `tests/affected.sh` selects ~17 files whenever `tasks/todo.md` changes (verbatim match on a register every task edits); `cached-suite.sh` is reached by a project-relative path with no `${CLAUDE_PLUGIN_ROOT}` fallback; a hard-killed wrapper leaves its suite orphaned while the lock reads stale; the stale-lock reclaim race is narrowed, not closed; `--path-format=absolute` needs git 2.31; the no-polling paragraph is duplicated in `/build` and `/wrap-up-session`; `/debug` Phase 3 still loops a full suite every 30 s; the AC4 negative pins cover five `/build` sections, not the whole file; cache records are never pruned

## Plan: quality-receipt-closure
> Spec: specs/quality-receipt-closure.md
> Issue: https://github.com/Joaovsales/jplugin-agentic-development/issues/163

### Slice 1/6 — Quality receipt script
- [x] Quality receipt script <!-- task-id: plan.specs-quality-receipt-closure-md.quality-receipt-script --> — Slice 1/6 of #163: `receipt.py` fingerprints the tasks-excluded diff and writes, checks and approves `quality-receipt/1… ([#185](https://github.com/Joaovsales/jplugin-agentic-development/issues/185))
  [x] TDD: tests/test-quality-receipt.sh § fingerprint — in a fixture repo: prints merge-base, tree and fingerprint; unchanged by an edit under `tasks/**`, by committing the same tree and by `diff.noprefix`/`diff.external` config; changed by a tracked edit, an untracked file and a `specs/` edit; base resolved from `origin/main|master|develop` then local when `--base` is omitted -> `receipt.py fingerprint [--base <ref>]`: temp-index `write-tree` with `core.safecrlf=false`, sha256 of the pinned-flag `git diff` in § Component contracts (AC 1)
  [x] TDD: tests/test-quality-receipt.sh § write — stores every § Data models field at `<common-dir>/quality-receipts/<fp>.json` and the branch pointer; unresolved MUST-FIX, design STOP or red tests -> STOP; >3 SHOULD-FIX or design HOLD -> HOLD; else GO; a supplied `verdict` is ignored; a delta receipt counts SHOULD-FIX back to the nearest approved HOLD; schema failure, a delta scope with no stored parent, or `tests.tree` ≠ the computed tree exits 2 and writes nothing -> `receipt.py write --outcome [--parent]` (AC 2)
  [x] TDD: tests/test-quality-receipt.sh § check and approve — valid GO exits 0; each of missing, diff-changed (with parent and delta paths), policy-changed (edit a policy file), schema, verdict, parent-invalid exits 3 with its reason; `approve` sets `hold_approved_by` on HOLD and refuses GO/STOP; approved HOLD checks valid and is a valid chain link; after a base merge the delta excludes files only the base changed -> `receipt.py check`, `receipt.py approve`, policy `qg1-<sha8>` of the seven verdict-deciding files (AC 3)

> Handover: landed d89f76a..69df204 — `receipt.py fingerprint|write|check|approve` and 63 assertions in `tests/test-quality-receipt.sh`
> Do not re-derive: `check` exits 0 valid, 3 stale, 2 error; `stale diff-changed` prints `parent <64-hex> delta <path> ...`, so pass that full fingerprint verbatim as `--parent`; the outcome JSON lives at `$(git rev-parse --path-format=absolute --git-common-dir)/quality-receipts/outcome.json`; SHOULD-FIX carry sums through GO links and stops at, excluding, the nearest approved HOLD
> Surface: none — `slice.py check` diffs base..HEAD for the whole build, so its report lists the other slices' files too

### Slice 2/6 — Gate emits the receipt
- [x] Gate emits the receipt <!-- task-id: plan.specs-quality-receipt-closure-md.gate-emits-the-receipt --> — Slice 2/6 of #163: `/quality-gate` runs security as phase 3 (before APOSD) and tests as phase 5, takes `--parent`, and… ([#186](https://github.com/Joaovsales/jplugin-agentic-development/issues/186)) (blocked-by: plan.specs-quality-receipt-closure-md.quality-receipt-script)
  [x] TDD: tests/test-doc-conventions.sh § quality receipt (gate) — `/quality-gate` names the `/security-scan` checklist over the gate's own file list as phase 3 before the dispatched APOSD phase 4, no edit after phase 4, the `Affected tests:` command through `cached-suite.sh` as phase 5, `receipt.py write` as phase 6, `--parent <fingerprint>` in its argument hint, the `Receipt:` output line and `Receipt: none —` on a write refusal -> rewrite the gate's phases, argument hint and Output block (AC 4)

> Handover: landed 69df204..5772288 — `/quality-gate` runs 1 simplify · 2 deslop · 3 security (the `/security-scan` checklist inline over the gate's own file list) · 4 APOSD (dispatched) · 5 affected tests through `cached-suite.sh` · 6 `receipt.py write`; hint `[--scope <path> ...] [--parent <fingerprint>]`; Output `Receipt: <GO|HOLD|STOP> <fp8> policy <v> [parent <fp8>]` or `Receipt: none — <stderr>`
> Do not re-derive: the gate's file list runs from the merge-base (field 1 of `receipt.py fingerprint`, no `--base`) to the working tree, untracked included, `tasks/**` excluded; `build/SKILL.md` Phase 3 still says "all 3 phases" — no slice's surface owns it
> Surface: none

### Slice 3/6 — Closure engine
- [x] Closure engine <!-- task-id: plan.specs-quality-receipt-closure-md.closure-engine --> — Slice 3/6 of #163: `closure.py step` implements the transition table and bounds, and replays the seven AC-6 scenarios f… ([#187](https://github.com/Joaovsales/jplugin-agentic-development/issues/187))
  [x] TDD: tests/test-closure.sh § transitions — each row of the spec's closure transition table maps its observation to its action; an observation the phase does not accept exits 2 with the state file unchanged; each accepted (phase, observation) pair has exactly one row; a table walk finds no cycle without a counter; bounds (2 CI rounds, 1 conflict round, 1 deploy re-entry, `gated`), CI timeout and unknown mergeability end `stopped` before a PR and `mark-draft` then `terminal partial` after -> `.agents/skills/wrap-up-session/scripts/closure.py step --state --observe` (AC 5)
  [x] TDD: tests/test-closure.sh § scenarios — green CI, CI repair, conflict repair, deployment success, deployment failure, stale receipt and draft partial PR each replay from `tests/fixtures/closure/scenarios.json` to their expected action trace and terminal line -> the fixture file plus a replay loop (AC 6)

> Handover: landed d89f76a..b10ef08 (merged at ce30e1f) — `closure.py step --state --observe` plus `table` for the cycle walk; 101 assertions and seven replayed scenarios in `tests/test-closure.sh`
> Do not re-derive: one observation key per phase — `receipt` (+`scope`), `gate`, `suite`, `push` (+`branch` on non-ff), `pr` (number or "failed"), `mergeable` (+`base` on conflicting), `merge`, `ci` (+`checks`), `debug`, `deploy` (+`head-moved`, +`reason` on n/a), `record` ("recorded"|"record-failed"), `partial` ("drafted"|"draft-failed"|"no-pr"); `pr_open` turns true on the reported PR number; the caller resolves the state path `<git-common-dir>/closure/<sanitized branch>.json`
> Surface: the agent's `tasks/todo.md` edit was dropped at merge; /build wrote this handover

### Slice 4/6 — Wrap-up reuses the receipt
- [x] Wrap-up reuses the receipt <!-- task-id: plan.specs-quality-receipt-closure-md.wrap-up-reuses-the-receipt --> — Slice 4/6 of #163: Wrap-up Step 4 checks the receipt and re-enters the gate once on a miss; Steps 3.5, 5 and the review… ([#188](https://github.com/Joaovsales/jplugin-agentic-development/issues/188)) (blocked-by: plan.specs-quality-receipt-closure-md.gate-emits-the-receipt)
  [x] TDD: tests/test-review-context.sh, tests/test-model-tiers.sh, tests/test-doc-conventions.sh § no wrap-up reviewer — wrap-up is no longer a dispatch site and names no `code-reviewer`, `critic`, `security-reviewer` dispatch, no `/security-scan`, no Review Payload, no Parallel Code Review; model-tiers no longer expects critic's floor in wrap-up; `AGENTS.md` Layer 3 names the receipt -> delete Steps 3.5, 4 (old), 5 and the Claude Code Enhancements section; update the two tests and the taxonomy line (AC 7)
  [x] TDD: tests/test-living-spec-reconciliation.sh, tests/test-doc-conventions.sh § receipt check — `## Step 4 — Quality Gate Receipt` runs `receipt.py check`, reuses on valid, invokes `/quality-gate --scope <delta> --parent <fp>` on diff-changed and full scope otherwise, proceeds only on GO or approved HOLD, approving only on a human answer in an interactive run; spec reconciliation still precedes Step 4; Step 6 keeps `cached-suite.sh`; Step 8.5's exit table names Step 4 in place of Step 5 (tests/test-routine-wrapup.sh) -> new Step 4; placement test drops the Step 3.5 anchor (AC 8)

> Handover: landed 5772288..6006f19 (merged at c3f427a) — wrap-up `## Step 4 — Quality Gate Receipt` runs `receipt.py check`, re-enters `/quality-gate` once at delta or full scope, approves a HOLD only interactively on `stale verdict HOLD`; Steps 3.5, 5 and the Parallel Code Review section are gone; Step 8.5's exit row names Step 4; `AGENTS.md` Layer 3 names the receipt check, full suite and closure loop
> Do not re-derive: Step 4 proceeds to Step 5.5; Step 7's `### Code Review Gate` points at the receipt; the review-context, model-tiers and living-spec pins that encoded wrap-up's reviewer dispatch were inverted, not weakened; affected run 20 files, every failure already on the Windows baseline
> Surface: none

### Slice 5/6 — Closure loop: PR, CI, conflicts
- [x] Closure loop: PR, CI, conflicts <!-- task-id: plan.specs-quality-receipt-closure-md.closure-loop-pr-ci-conflicts --> — Slice 5/6 of #163: Wrap-up drives `closure.py` from Step 4 on, through commit, push, PR, mergeability, CI watch and bou… ([#189](https://github.com/Joaovsales/jplugin-agentic-development/issues/189)) (blocked-by: plan.specs-quality-receipt-closure-md.closure-engine, plan.specs-quality-receipt-closure-md.wrap-up-reuses-the-receipt)
  [x] TDD: tests/test-doc-conventions.sh, tests/test-routine-step-ledger.sh § closure PR — from Step 4 on wrap-up performs the actions `closure.py step` prints, state under the git common dir; commits never use `--no-verify`; the PR body carries `Quality receipt:` and `## Closure` and still passes the linkage check -> Step 7 rewritten around the engine (AC 9)
  [x] TDD: tests/test-doc-conventions.sh § closure CI — `gh pr view --json mergeable`, `gh pr checks <n> --watch --required` as a background task with the all-checks fallback and 30-min budget, `gh run view --log-failed` to `/debug`, re-entry through Step 4 and Step 6, 2 rounds; `ci: none` only after the registration window with no `pull_request` workflow; each repair commit adds a `## Session Summary … — closure repair <n>` line -> CI watch and repair section (AC 10)
  [x] TDD: tests/test-doc-conventions.sh § closure conflicts — on CONFLICTING or a non-fast-forward push wrap-up merges with no `rebase` and no `--force`, 1 round, aborts an unresolved merge -> conflict repair section; Push Failure Handling row no longer says `pull --rebase` (AC 11)

> Handover: landed 6006f19..693e3ed (merged at 5cd65a3) — Step 7 opens with `### The Closure Loop` (the `closure.py step` call, state under the git common dir, an action → section → observation table); `### Commit & Push`, `### The Pull Request` (body carries `Quality receipt:` and `## Closure`), `#### Mergeability`, `#### CI Watch and Repair`, `#### Conflict Repair`; Push Failure Handling's non-ff row routes to Conflict Repair, never `pull --rebase`
> Do not re-derive: `debug: fixed` is reported once the fix is committed and the engine routes it through `check-receipt`, `run-suite`, `commit-push`; `BEHIND` is `mergeStateStatus`, never a trigger; every closure end routes through Step 8.5
> Surface: none

### Slice 6/6 — Closure loop: deploy, record, partial
- [x] Closure loop: deploy, record, partial <!-- task-id: plan.specs-quality-receipt-closure-md.closure-loop-deploy-record-partial --> — Slice 6/6 of #163: Wrap-up verifies deployment or records it as not applicable, writes the closure record, and drafts a… ([#190](https://github.com/Joaovsales/jplugin-agentic-development/issues/190)) (blocked-by: plan.specs-quality-receipt-closure-md.closure-loop-pr-ci-conflicts)
  [x] TDD: tests/test-doc-conventions.sh § closure deploy — `/verify-evidence --scope deployment` when a target applies, `Deployments: not applicable —` otherwise, a moved HEAD re-enters Step 4 once -> deployment step inside the loop (AC 12)
  [x] TDD: tests/test-doc-conventions.sh § closure record — registers record pre-push facts only; the Done report carries `Closure: <complete|partial — state>`; a partial run runs `gh pr ready --undo`; `routines.md` spine step names the quality receipt, not review passes -> Done report, partial path, routines.md (AC 13)
  [x] Verify: this PR's own wrap-up drives the loop to `terminal complete` on green CI and is recorded in `tasks/e2e-log.md` (Decision 13)

> Handover: landed 693e3ed..c0b2c6d (merged) — Step 8 is the `verify-deploy` action (`head-moved` compare, one re-entry, `Deployments: not applicable — <reason>`); `## Done` gains *Recording the closure* (`gh pr edit`) and *Marking a partial PR draft* (`gh pr ready <n> --undo`) and the `Closure:` line; `routines.md` spine names the quality receipt
> Do not re-derive: registers record pre-push facts only (Step 2 says so); the `Closure:` line quotes the engine's `state=`, `reason=` and `draft=`
> Surface: none
> Open: none — PR #191's own `/wrap-up-session` drove the loop to `terminal complete state=record reason=closure recorded` on green CI (entry in `tasks/e2e-log.md`)

## Session Summary — 2026-09-23 [3525c70..5e00630]
- Completed: 6 slices of `## Plan: quality-receipt-closure` (filed as issues, refs #163 and #162), with every TDD row done; slice 6's `Verify:` row stays open because it is this PR's own closure run (Decision 13); quality-gate fixes: receipt.py refuses a non-hex fingerprint; HOLD routes through the `approve` phase and the receipt is re-checked; a closure run ends at `done` and keeps `pr_open`; corrupt state and receipt files are handled
- Pending: none in this plan; the issues close on merge through #191's `Closes` lines
- Carry-forward (reported, not applied; recorded in receipt 39e94696): the base choice duplicated across `check --base`, `write` and Base Branch Detection; the gate's file list rebuilt by hand (no `receipt.py paths`); the `quality-gate` action carries no parent or delta paths; `key=value` output with spaces in values; destination strings parsed twice in closure.py; one shared `outcome.json` path; a corrupt receipt reported as `stale schema`; `build/SKILL.md` Phase 3 still says "all 3 phases"; the installed plugin copy of `/wrap-up-session` predates this branch until the plugin is reinstalled
## Session Summary — 2026-09-24 [2d68d66..834df20]
- Completed: 7 TDD rows of `## Plan: routine-run-envelope` (#127) — `routine_run.py` launcher, envelope verdict, one pre-start retry, six prompts and `routines.md` § Launching a routine
- Pending: none in this plan; #127 closes on merge
- Carry-forward (receipt d7d7a01e → 4f224fd4, GO): Codex `-c mcp_servers.<name>.enabled=false` unverified until the first Orca-host run (marked in `routines.md`); `RunResult.to_json`/`render` assume a failed result; harness validated both by argparse and `build_command`
- Second design round (43cb19a): an escalation is a `failure` line, not a `finish` outcome; collision-proof log dirs; Claude `--mcp-config` validated; typed `RunResult`. Full suite (WSL, 834df20): 58/58; it first caught the README's `routines.md` citation, fixed in 487ae3c/834df20
- Resolved at the HOLD (user asked for the fixes, not an approval): retry now reads `Verdict.retryable`, not the reason string; a retried failure keeps `attempt-1.*` and `attempt_reasons`; `RunReport` replaces the untyped verdict dict; per-routine `ROUTINE_OUTCOMES` is enforced and pinned to each prompt by a test
