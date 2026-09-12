# History

> Migrated from the Session History section of tasks/memory.md.

### [2026-08-13] — Typed learning store (M3 + M3-MIG)

- Key changes: Built the typed learning store and cut the harness over to it.
  New `tasks/solutions/<category>/<slug>.md` schema (`tasks/solutions/README.md`),
  stdlib-only `scripts/migrate-learning-store.py` (dry-run default, `--apply`,
  archive-never-delete, conflict diversion to `.migrated.md`), and this repo's own
  migration applied (15 documents, originals in `tasks/archive/20260811T183743Z/`).
  Session-start banner reduced to one-line store counts; `/learn`, `/memory-maintain`,
  `/debug`, `/sync` rewritten for the store; retired-file references swept from both
  skill trees, hooks, CLAUDE.md, README, install.sh, project-template. New suites:
  test-migrate-learning-store.sh (78 asserts), test-solutions-schema.sh (31, incl.
  enum-sync across script/validator/README). Branch `worktree-m3-typed-learning-store`.
- Learnings captured: tasks/solutions/bugs/grep-zero-matches-aborts-hooks-under-set-e-pipefail.md,
  tasks/solutions/patterns/construct-retired-paths-at-runtime-to-keep-literal-sweeps-strict.md

### [2026-08-10] — Compound engineering Tier 2 (review epistemics)

- Key changes: Added `CLAUDE.md` § *Finding Model* (four axes — `severity`,
  `confidence`, `autofix_class`, `owner` — with three behavioral confidence anchors) and
  § *Independence Accounting*. `/quality-gate` and `/wrap-up-session` now enforce an apply
  gate (`gated_auto` **and** `confidence >= 75`) and must disclose whether their review
  passes ran `dispatched` or `inline`; inline runs may never promote confidence. The four
  review personas emit all four axes with a `file:line` evidence gate at anchor 75+.
  Guards: +71 lines in `test-doc-conventions.sh`, +22 in `test-agents.sh` (242 + 112
  assertions). Branch `feat/compound-engineering-tier-2`, stacked on Tier 1.
- Pattern: Confidence and severity are independent. Severity says how much a finding
  matters if real; confidence says whether it is real. Collapsing them is what lets an
  unproven guess be auto-applied with the authority of a proven defect. (extracted: tasks/solutions/patterns/confidence-and-severity-are-independent-severity-says-how-mu.md)
- Pattern: A `MUST-FIX` at `confidence: 50` must be *verified*, not fixed and not blocked
  on — otherwise a speculative finding deadlocks every commit. Caught in this session's own
  Phase 3 gate, in the very rule being written. (extracted: tasks/solutions/patterns/a-must-fix-at-confidence-50-must-be-verified-not-fixed.md)
- Lessons added: 4 patterns above
- Deferred: Tier 3.1/3.2/3.3 (typed learning store, harness cutover, concept glossary) —
  27 open tasks in `tasks/todo.md`. `tasks/lessons.md` deliberately NOT created; Tier 3
  retires it, so adding it now only gives the migration another file to archive.

### [2026-07-08] — Visual plan/recap skills

- Key changes: Added `/visual-plan` + `/visual-recap` (opt-in) that render self-contained HTML visual docs locally by wrapping the existing `html-presentation` generator; new `visual-render.py` post-processor injects diff coloring + tabsets. No external MCP/hosted service (adapted from BuilderIO/skills' hosted model).
- Pattern: To extend a `/sync`-managed skill's output without editing it, wrap it — a new skill owns a post-processor that operates on the managed skill's OUTPUT. Keeps the managed file untouched so `/sync` never clobbers the work. (extracted: tasks/solutions/patterns/to-extend-a-sync-managed-skill-s-output-without-editing-it-w.md)
- Pattern: The bash test suite enforces `.agents/` ↔ `.claude/` byte-identical skill parity (`test-skill-parity.sh`) + doc-convention token greps (`test-doc-conventions.sh`). Any new skill must be authored in BOTH trees identically and wired into both tests. (extracted: tasks/solutions/patterns/the-bash-test-suite-enforces-agents-claude-byte-identical-sk.md)
- Lessons added: none (captured as patterns above)

### [2026-08-13] — M4 concept glossary

- Key changes: Added `tasks/concepts.md` (accreting concept glossary) + template seed; `/memory-maintain` Phase 0 one-time bootstrap sweep keyed on a `> Sweep: pending` marker, fired from the light pass; `/learn` Step 7 concept capture; pruning rule in Phase 4; install.sh seed; guards in test-doc-conventions.sh + test-install-sh.sh. Dogfooded the sweep on this repo (10 terms admitted, marker flipped).
- Learnings captured: tasks/solutions/patterns/first-run-triggers-must-precede-every-early-exit-above-them.md

### [2026-08-14] — Agent registration repair

- Key changes: Three documented personas (`code-reviewer`, `context-document-optimizer`,
  `frontend-design-validator`) were absent from the harness agent registry despite existing
  in both trees with correct names and a green suite. Cause was a YAML parse error — their
  `description:` values were unquoted plain scalars carrying `": "` from auto-generated
  `<example>` prose. Rewrote all three colon-free (both trees), added `tests/test-agents.sh`
  § 4 (frontmatter constructs that break registration, with nine negative self-test fixtures)
  and § 5 (CLAUDE.md § Agents -> counterpart file, with a count floor so the check cannot
  fail open). Documented the constraint as rule 5 in `.agents/agents/README.md`.
- Verified live: all three personas registered on the next session start, and the four
  `/wrap-up-session` review passes dispatched — three of them `code-reviewer`, the exact
  pass that was broken.
- Learnings captured: tasks/solutions/bugs/unquoted-yaml-scalar-silently-deregisters-an-agent-persona.md
- Review: 4 parallel passes (3x code-reviewer, 1x critic), separately dispatched, so
  corroboration between them is independent. 4 MUST-FIX and 8 SHOULD-FIX raised; the
  vacuity findings (checks passing when their input vanished) were found independently by
  three of the four passes and all were fixed. One critic claim was disproven on check —
  a "lossless" single-quoted restore of the original description raises ParserError on its
  own apostrophes.
- Deployment: the broken copies in `~/.claude/agents/` were refreshed by hand the same day.
  Fixing the repo does not fix the machine - an installed persona has its own copy, so
  "repo is green" and "harness is fixed" are separate claims.

### [2026-08-18] — Windows session-guard key collapse

- Fixed a Windows-only defect in `.claude/hooks/session-start.sh`: the double-invocation
  guard fell back to `$PPID`, which is `1` for bash spawned from a native Windows parent,
  so every session in every repo shared one sentinel and a second repo opened inside the
  5-minute window got no banner at all. Confirmed in the wild — `/tmp/.ccw-session-start-1-*`
  was being rewritten by live sessions. Now keys on `session_id` parsed with sed (the `jq`
  branch is gone, and `jq` is absent on this machine so it was never the live path), falling
  back to a `cksum` of `$PWD`.
- Added seven guard assertions to `tests/test-session-start.sh`. The load-bearing detail is
  that they redirect to a file instead of capturing with `$(...)`: command substitution forks
  a fresh subshell per call, so `$PPID` varied per invocation and the old guard was **inert
  under test** — which is why the defect shipped. Three pre-existing assertions had to take
  `CCW_SESSION_GUARD=0`; they were green only because the guard never fired.
- The 4-pass review then found a MUST-FIX **in the fix**: the new `cksum` pipeline had no
  `|| true`, so under `set -eo pipefail` a missing `cksum` killed the hook at exit 127 with
  zero output — a worse silent-banner loss than the original bug, with the documented
  degradation unreachable. All four passes found it independently; reproduced directly.
  A second MUST-FIX explained why it was invisible: the "stays silent" assertions checked
  stdout only, and a crash also prints nothing.
- Also fixed from review: extracted a shared `json_string_field` helper (the sed idiom had
  been cloned, with two divergent character classes), widened the `session_id` capture to
  `[^"]*`, bounded the raw-path fallback, added expiry/empty-payload/cksum-absent coverage,
  and set `CCW_SESSION_GUARD=0` in `codex/hooks/session_start.py` — Codex registers once, and
  the now-stable cwd key would have suppressed its second session in a repo.
- Learnings captured: `tasks/solutions/bugs/ppid-is-1-on-windows-so-a-ppid-keyed-guard-collapses.md`,
  `tasks/solutions/patterns/command-substitution-forks-a-subshell-so-ppid-varies-per-call.md`
- Review: 4 parallel passes (3x code-reviewer, 1x critic), separately dispatched, so
  corroboration is independent. 2 MUST-FIX and 13 SHOULD-FIX raised; 1 SHOULD-FIX skipped
  (`pre-compact.sh` still requires `jq` — pre-existing line, advisory/human).
- Open, not acted on: the critic argued the fallback should be dropped entirely (no
  `session_id` -> just print), since the guard suppresses a cosmetic duplicate but fails by
  losing a functional banner. That deletes several findings rather than fixing them. Left to
  the user, because the requested fix shape was explicitly a stable-and-distinct *key*.
- Merged `origin/master` mid-wrap-up: #66 (`fix(codex): restore SessionStart output on
  Windows`) landed after this worktree branched and fixed the red baseline that was treated
  as out of scope here. It made the same `CCW_SESSION_GUARD=0` change to the Codex wrapper,
  so that edit and its test assertion were dropped in favour of master's -- master's pins the
  property behaviourally (invokes the adapter twice) rather than statically.
- Corrected: this session twice reported the Codex guard-disable as absent from the repo.
  It was absent from *this branch's base*, not from the repo. `master` advances mid-session;
  check it before concluding something does not exist.
- Not fixed, pre-existing: ~290 unreaped `.ccw-session-start-*` sentinels accumulating in
  `/tmp` since 30 July.

### [2026-08-18] — UTF-8 at every Python IO boundary

- Key changes: a one-line stdin decode fix (`--markdown -` used the platform default
  codec, cp1252 on Windows) expanded to four instances of one defect class after the
  review gate swept for siblings. `generate-presentation.py` now uses `utf-8-sig` on both
  markdown branches and pins stdout; `visual-render.py` decodes its subprocess capture
  explicitly (`text=True` swallows the decode error inside subprocess's reader thread and
  leaves `result.stderr` as `None` exactly when the child failed). New
  `tests/test-html-presentation.sh` (26 assertions) pins the previously untested stdin path.
- Two of the four failed *silently*, which is worse than the loud mojibake that prompted
  the fix: the BOM case loses the title and every section at exit 0, and the subprocess
  case discards the child's diagnostics.
- Superseded mid-wrap-up: this branch also fixed `codex/hooks/session_start.py` and
  diagnosed the long-red `tests/test-codex-install.sh`. #66 and #68 landed on master first
  and did both properly, so all Codex- and guard-related changes here were dropped in
  favour of upstream at merge.
- **My guard diagnosis was wrong about the mechanism.** I concluded the `$PPID` fallback
  collided by *PID recycling* inside the 300s sentinel window — which never explained why
  the failure was deterministic. #66 has the real answer: `$PPID` is **1** for bash spawned
  from a native Windows parent, so every invocation collapses onto a single sentinel by
  construction. I had the evidence for this (the same script emitting 2568 bytes under one
  parent and 0 under another) and read a stochastic story into it instead of measuring
  `$PPID`. Lesson: when a "race" reproduces deterministically, stop and measure the key.
- Review: 4 passes separately dispatched (3x code-reviewer, 1x critic), so corroboration
  between them is independent. The BOM defect and the stdout-print defect were each found
  by three passes independently and promoted on that basis. Every pass verified by
  reproduction rather than inspection.
- Reviewer limits worth recording: two passes confidently gave the encoding bug as the
  whole root cause of the red test. It was half — applying it left the test red. Each had
  reproduced `UnicodeEncodeError` in isolation rather than through the installed hook, and
  neither saw the guard. Agreement between reviewers is evidence about the defect they
  found, not about the absence of a second one behind the same symptom.
- Two process traps hit directly: `bash tests/run.sh | tail` returns **`tail`'s** exit
  status, so a red suite reported exit 0 alongside `RESULT: 1/19 test files FAILED`; and the
  first full suite run overlapped tree edits, so it was discarded and re-run on a settled
  tree with before/after `git status` snapshots as proof.
- Learnings captured: `tasks/solutions/patterns/explicit-encoding-at-every-python-io-boundary.md`

### [2026-08-18] — Lightpanda optional e2e browser tier

- Key changes: Evaluated two candidate repos and adopted one. Lightpanda enters as an
  optional, capability-scoped e2e backend behind a **fail-closed AC classifier**;
  `agent-reach` was declined outright (spec §2) rather than adopted partially. New
  `.claude/browsers/lightpanda.md` adapter runbook mirroring the `.claude/deployments/`
  frontmatter-plus-troubleshooting precedent; `.claude/browsers/` declared syncable across
  all 7 enumerations in 3 files; `/verify --scope e2e` gained backend resolution, the
  VISUAL / DOM-FUNCTIONAL tiers, and the `BLOCKED` outcome; `/prd` and `/brainstorm` gained
  `lightpanda fetch` as an optional research fallback that never blocks when absent.
  `/start-qa` and `install.sh` deliberately untouched (AC-10, AC-11).
- Design decision worth keeping: the load-bearing element is a single sentence —
  "when classification is uncertain, the AC is VISUAL". Reverse it and the gate inverts
  from *refuse to guess* to *guess and pass*, silently, with every test still green,
  because nothing else in the suite reads it. `tests/test-e2e-classifier.sh` therefore
  pins that sentence **verbatim in both skill trees** rather than paraphrasing it.
- Why a routing gate and not a runtime check: lightpanda's `getBoundingClientRect()` is
  *stubbed*, not absent — it returns plausible constants, so the standard visibility guard
  passes for an element 9999px off-screen. A capability gap that lies cannot be caught by
  the caller's feature detection, so it has to be refused before dispatch. Captured as
  `tasks/solutions/patterns/a-stubbed-web-api-is-more-dangerous-than-an-absent-one.md`.
- Investigation error worth recording: the first geometry probe returned nothing, which
  supported the tidy and wrong conclusion "the API is absent". A control run showed
  `console.log` never reaches stdout in `fetch` mode. Re-probing through the DOM inverted
  the finding. The method note stayed in `tasks/e2e-log.md` rather than being tidied away.
  Captured as `tasks/solutions/patterns/a-null-probe-result-needs-a-control-run.md`.
- Review: 4 passes run **inline**, not dispatched — the session operated under a standing
  no-subagent constraint. Per `CLAUDE.md` § *Independence Accounting* that forfeits
  corroboration-based promotion, so no finding here was promoted on agreement; naming the
  loss is the floor. Two real defects found and fixed: passing walkthroughs were not
  recording their tier (only blocked ones were), and a `harness: universal` skill pointed
  at a Claude-only `.claude/browsers/` path that `scripts/install-codex.sh:50` never copies.
- Process failure, self-caught: I argued the >6-task worktree trigger did not apply and
  worked in the shared clone. A `git add tasks/todo.md` then swept a parallel session's
  plans into my commit, which had to be rebuilt with `--amend`. The trigger was right and
  my exception was wrong; the shared register is exactly what the worktree isolates.
- AC-4 could not be satisfied by static assertions, and was not claimed on them. It needed
  a real lightpanda run, no Windows binary exists, and Docker Desktop was down — repaired
  first (stale AF_UNIX socket at `%LOCALAPPDATA%\Docker\run\dockerInference`, unremovable
  by `Remove-Item`, `del`, or `fsutil reparsepoint delete`; fixed by rotating the directory)
  and the walkthrough then ran container-to-container.
- Learnings captured: `tasks/solutions/patterns/a-stubbed-web-api-is-more-dangerous-than-an-absent-one.md`,
  `tasks/solutions/patterns/a-null-probe-result-needs-a-control-run.md`

### [2026-08-29] — Verification skill integration

- Key changes: Adapted pstack's MIT-licensed verification-skill creator and
  maintainer into both harness skill trees; integrated changed-scope maintenance
  into `/build`, `/wrap-up-session`, and `/verify`; added complete provenance;
  and added a general-purpose registry, checker, and weekly GitHub workflow for
  detecting path-scoped upstream drift without mutating downstream content.
- Verification: all 24 test files passed, including 64 verification-integration
  assertions and 32 upstream-drift assertions; 10/10 load-bearing mutation probes
  were rejected; the live registered upstream check exited cleanly.
- Wrap-up review: three independently dispatched review lenses plus one inline
  adversarial pass found 13 issues, all resolved. The fixes aligned candidate
  discovery across maintenance and E2E, made the example a fully indexed
  three-feature contract, closed false-green tests, and hardened the external Git
  checker with ref validation, bounded resources and diagnostics, process-tree
  timeout cleanup, safe workflow summary rendering, and an immutable
  checkout-action pin.
- Learnings captured: `tasks/solutions/patterns/markdown-heading-contracts-must-match-heading-levels-exactly.md`,
  `tasks/solutions/patterns/count-candidates-before-validating-the-selected-target.md`

### [2026-09-01] — Issue lane routing

- Key changes: Added a shared issue-routing policy engine, `/route` skill, three
  materialized lane playbooks, `UserPromptSubmit` hook, task-registry autonomy
  configuration, structured task resolution, exhaustive monotonicity tests, real-issue
  fixtures, runtime scope demotion, and `/auto-improve` delegation.
- Verification: all 29 test files passed; route triggerability fired 3/3 organic
  prompts. The blinded suppression comparison found no measurable hook advantage and
  retained that negative result in `tasks/eval-results/issue-lane-routing.md`.
- Review: the independent APOSD pass found six design findings across two rounds; all
  were remediated. One critic attempt hit its usage ceiling, but its retry and the other
  dispatched consistency, defensive, and coverage lenses completed independently. They
  exposed unsafe lifecycle, identity, and transaction edges; the fixes made diff/reviewer
  transitions monotonic, non-following, and recoverable.
- Formal user-surface E2E remained unavailable without a project verification skill;
  the user acknowledged the recorded gap before commit and push.
- Learnings captured: `tasks/solutions/architecture/hard-gate-on-tasks-todo-md.md`,
  `tasks/solutions/patterns/consume-structured-records-before-rendering-human-summaries.md`

### [2026-09-02] — qwen spend investigation + guardrails (yolo)
Investigated a $26.53/24h OpenRouter burn: pi session logs traced it to 6,006 qwen3-coder-next requests from one autonomous /build in PROJECT-pix-receipt-tracker (22 backend-developer spawns; 95% cache-read at $0.07/M). Root cause: `subagents.defaultModel` blanket-enforced qwen on all unscoped agents. Applied: defaultModel → deepseek-v4-flash, 80-turn caps on builder agents, key-limit deferred (needs management key). Verified via live smoke spawn. Docs: tasks/solutions/patterns/cheap-per-token-is-not-cheap-per-task-cap-subagent-turns.md

### [2026-09-05] — category routines replace the /route lattice (build)
Executed `specs/category-routines.md` (revision 4): deleted the issue-routing policy
engine shipped on 2026-09-01 — 923 LOC of lattice plus 728 LOC of tests, the
`UserPromptSubmit` hook, three lane playbooks and the radius tripwire — and replaced it
with four scheduled routines selecting on one label axis.
- Key changes: `routine_branch.py` (parse + format, round-trip tested); the routine
  contract at `.agents/skills/wrap-up-session/references/routines.md`; `registry/
  routines.py` plus `task-registry select` and `selectors` commands; `[routines]` and
  `[routines.selectors]` configuration; wrap-up's two PR procedures converged into one;
  `/auto-improve` Phases 3-5 rewired to name their reviewer set directly.
- Verification: 35 test files / 2,734 assertions green (was 32 / ~2,000 at baseline).
  Six new test files. AC12 and the branch convention additionally proven live against
  the `gh` mock and the CLI, not only through the suite.
- Review: the dispatched APOSD pass returned HOLD with three MUST-FIX. The most serious
  was a live regression this session introduced and the suite did not catch — widening
  `DEFAULT_KIND_LABELS` for the precedence chain made the GitHub provider stamp
  `tech-debt` on every published task, which is the `fix` routine's own selector. Root
  cause was a false premise in the spec (it assumed selection reads `[labels.kind]`; the
  implementation had correctly given selection its own section). Reverted with a
  regression guard. All ten findings resolved.
- Deferred: the `build` routine (#98, blocked on #97). Its selector deliberately ships
  absent so a deferred capability cannot fail a live gate; the branch parser is general
  over routine names, so `routine/build/...` already round-trips.
- Learnings captured: `tasks/solutions/architecture/a-bidirectional-map-cannot-be-widened-for-one-direction.md`,
  `tasks/solutions/patterns/validate-in-the-loader-not-in-one-optional-command.md`,
  `tasks/solutions/patterns/shape-validation-cannot-catch-a-membership-error.md`
### [2026-09-04] — Provider documentation drift

- Key changes: Corrected task-registry provider precedence in `CLAUDE.md` and both
  shipped configuration templates, replaced the wrap-up hook's false local-provider
  rationale with its actual no-registry-call boundary, and added focused regression
  assertions.
- Verification: `tests/test-doc-conventions.sh` passed 439 assertions after
  review-driven coverage fixes; all 32 test files passed in the debug suite.
- Learnings captured: `tasks/solutions/bugs/task-registry-provider-selection-docs-drift.md`

### [2026-09-04] — Deterministic retirement in /sync (routed: gated-at-plan-and-pre-push)
Replaced `/sync`'s per-run model judgement of "retired upstream vs project-specific"
with set arithmetic over a recorded `.claude/sync-keep` allowlist:
`retire = project paths under syncable roots − template paths under the same roots
− paths matching a sync-keep pattern`. New stdlib-only `sync-retire.py` (mirrored
byte-identically into `.claude/skills/`), 103 lines of rewritten `/sync` procedure,
a spec, and a 230-assertion behavioural suite.
- Verification: 33/33 test files, 2828 assertions, 0 failures; ruff and py_compile
  clean; both skill trees byte-identical.
- Review: three rounds, six dispatched reviewers. Round 1 (APOSD) returned HOLD.
  Round 2 (code + security) returned FAIL on a reproduced command-execution defect:
  an untrusted `--from-dir` template's `core.fsmonitor` ran during the pre-approval
  dry run. Round 3 (consistency, defensive, coverage, adversarial critic) returned
  REVISE and found the round-2 fixes incomplete — `_as_pattern` still let a newline
  escape its own comment, and three of the new assertions survived mutation.
- Every MUST-FIX was reproduced before being fixed and pinned by a mutation probe.
  Four probes exposed assertions that certified nothing; all four were rewritten.
- Ten follow-ups filed; two were then fixed in-session on the user's call. The
  regression (bootstrap projects keeping retired skills forever) and the fragility
  (one upstream file deletion disabling retirement everywhere) shared a root cause:
  the script only ever consulted the template's *current* state. Both were closed by
  reading the template's git history for provenance, and by scoping an empty root to
  itself while still refusing a source missing several roots.
- Learnings captured: `tasks/solutions/security/running-git-in-an-untrusted-checkout-executes-its-config.md`,
  `tasks/solutions/process/an-assertion-can-pass-because-a-different-guard-fired.md`,
  `tasks/solutions/tooling/mawk-has-no-interval-expressions.md`

### Round 2 review (2026-09-05)

Re-dispatched `code-reviewer` and `critic` against the fix batch. Both independently
found the record-loss survivor and the depth probe — separately dispatched contexts,
so that agreement counts.

- **The one that mattered**: bootstrap retired on *path identity*. A file the project
  wrote itself at a path the template once used (`.claude/hooks/pre-commit.sh` is a
  name both reach for), a synced file the project later edited, and a file with
  uncommitted changes were all deleted as "template content". Provenance is now the
  working-tree hash against every blob the template held at that path. Hashing the
  working tree rather than the index is what saves the uncommitted case, which
  `git checkout` could never restore.
- The precondition reordering closed one call site of the record-loss class, not the
  class: `write_candidate` could still fail after `apply_plan` for any reason other
  than "already exists". Folded into `_deletion_outcome` as a fourth category.
- The shallow probe was wrong in both directions in turn — repository-scoped (broke
  `--from-ref` for CI's `--depth 1` projects), then commit-count (caught only depth 1,
  so a `--depth 5` clone produced a different retirement set from the same SHA). Now
  detects a graft boundary, which is depth- and mode-independent.
- Four of my own assertions certified nothing and were rewritten: a probe aimed at an
  unreachable branch, a fixture appending after the block terminator, a symlink test
  whose target existed, and a `Traceback` check that `main` had always caught.
- Process: dispatching write-capable reviewers against the live worktree raced my own
  test runs. Use `isolation: "worktree"` next time.
- Learnings: `architecture/path-membership-is-not-proof-of-provenance.md`,
  `architecture/a-repository-level-flag-does-not-describe-one-revision.md`,
  `process/a-precondition-that-fires-after-the-act-reports-nothing.md`,
  `tooling/pkill-f-matches-the-shell-that-runs-it.md`

### [2026-09-06] — A task-tracking pointer to a missing file is no longer silent (#82)
`/debug 82`. `find_config_path()` fell through `os.path.isfile` to the default
path whenever a `Task tracking instructions:` pointer named a file that did not
exist, and its `except ConfigError: continue` did the same for a pointer that
escaped the project root — so "declared and broken" and "never declared" printed
the same `doctor` line and ran on the same defaults. The template's own
`CLAUDE.md` was the live instance: a bare pointer to `docs/task-tracking.md`,
a file that never shipped and cannot (`docs/` is not syncable).
- Root-Cause Prelude ranked three candidates; the regex (#2) was disconfirmed by
  running `POINTER_RE` over `CLAUDE.md`, and the doctor renderer (#3) by the
  absence of any declared-path field in `Config` for it to have dropped.
- Fix: a `ConfigPointerError` raised from the loader, naming the declaring file,
  the declared path, and the template to start from; `load_config(strict=)`
  replaces `validate_routines`, and `doctor` alone loads non-strict so it can
  render `configuration:  BROKEN — …` and exit 1 while every other command
  refuses in the preamble. `CLAUDE.md` now carries the convention as prose with
  a `<path>` placeholder — the issue's proposed backtick-wrap was tested and
  found insufficient, since `POINTER_RE` stops at a backtick without needing one.
- Tests: a three-state block (no pointer / pointer resolves / pointer missing,
  plus precedence and escape) written RED first; the doc-conventions guard now
  asserts the convention is documented and that any live pointer in `CLAUDE.md`
  resolves to a shipped file. 36/36 test files green.
- Two decisions recorded as `[AMBIGUITY]`: refuse rather than warn-and-run
  (spec AC7 in the issue's comment, and the malformed-config precedent), and
  make the escaping pointer loud too (same defect, same function, already
  documented as refused).
- Learnings captured: `tasks/solutions/bugs/task-tracking-pointer-to-a-missing-file-was-indistinguishable-from-no-pointer.md`,
  `tasks/solutions/patterns/a-declared-intent-with-a-broken-target-is-not-an-absent-one.md`
### [2026-09-07] — Legacy row publishing
- Key changes: task-registry now parses and rewrites complete multi-line logical rows, derives clean legacy titles, rejects malformed or oversized provider-bound rows, and ships naming-convention guidance.
- Key changes: issue #107 recorded the redundant routed `/plan` gate; after the session rebased, merged PR #105 had deleted `/route` and defined the `fix` routine as `/debug` directly into `/build`/TDD, so #107 was closed as superseded.
- Learnings captured: [task-registry publish lost legacy row detail](solutions/bugs/task-registry-publish-lost-legacy-row-detail.md) and [logical text records must own their rewrite span](solutions/patterns/logical-text-records-must-own-their-rewrite-span.md).

### [2026-09-07] — Phase A of the task-registry shrink: the `workflow` command (40f6b5e..15a6c29, base bbef230)

- Built `tasks/handover-workflow-routing.md` § 4 (Phase A, 7 rows) against
  `specs/workflow-routing.md`. Branch `feat/workflow-routing-phase-a` off
  `master` at `bbef230`.
- **Gate honoured first.** The handover's Step 0 requires #82 merged before any
  Phase A work, because both edit `CLAUDE.md`. #82 was still open as PR #109
  (green, mergeable); it was merged on the user's explicit authorization, then
  this branch was cut from the updated `master`. The spec + handover commit
  existed only locally on `analysis/simplify-routing` (whose remote was deleted
  when #105 squash-merged) and was cherry-picked across.
- Delivered: R2's `task-registry workflow <ref>` — the only real gap the spec
  found — plus the `[routines.skills]` configuration layer, an issue-number
  tie-break for selection, this repository's own `docs/task-tracking.md`, and
  `/wrap-up-session` Step 8.5.
- Two handover claims checked and corrected: A4 was **not** already done by #82's
  agent (#109 shipped the `CLAUDE.md` half only), and the spec's § *Ordering* /
  AC3 amendment the handover asks for in § 5 was **already present** in the
  committed spec, so A3 needed only the code change.
- Two `[AMBIGUITY]` decisions recorded: shipped default chains follow
  `references/routines.md` rather than the spec's illustrative ini block (they
  disagree on whether `plan` runs `/build`), and AC4's on-disk skill check is
  scoped to project-*declared* chains, since checking shipped defaults would make
  `load_config` raise in every existing fixture.
- **Four assertions were found to be unfalsifiable by mutation probing and
  narrowed** — none by reading. Captured as
  `tasks/solutions/process/a-config-equal-to-its-defaults-cannot-prove-it-was-read.md`,
  `tasks/solutions/process/a-stable-sort-hides-a-missing-final-tie-break.md`, and a
  second occurrence appended to
  `tasks/solutions/process/assertion-must-be-scoped-to-the-half-it-tests.md`.
- Phase A owns AC1–AC13 and AC15; AC14/AC16 belong to Phases B and C. 37/37 test
  files green.

## 2026-09-07 — Phase A review reconciliation [15a6c29..31edf29]

- Four review passes were dispatched separately (`code-reviewer`, defensive audit,
  test coverage, adversarial critic), so their agreement promoted confidence by
  one anchor where two independently found the same defect. Two findings promoted
  that way: the missing `result_truncated` guard and the closed-issue routing.
- **The highest-value finding came from mutation probing, not from reading.** Pass
  3 claimed the AC4 traversal assertions could not fail; deleting the shape guard
  and watching all 52 assertions stay green confirmed it. The same probe found the
  wrap-up early-exit routing was prose with a prose-matching test.
- Two claims in dispatched output were checked before acting rather than taken at
  face value, and both held: `AGENTS.md` genuinely had no pointer, and
  `get_task` genuinely exists on all four providers.
- Four findings were surfaced under `owner: human` rather than applied, all
  turning on what the spec means rather than what the code does. They are written
  up in the handover's new § 11 so Phase B does not rediscover them.
- The exit-code decision worth remembering: an outage and a misconfiguration both
  used to exit 2. They are now 1 and 2, because the question a scheduler asks is
  not "did it fail" but "should I wake someone".
- The pre-push wrap-up gate recorded 12 uncovered commits, and it was right. The
  earlier session summary's fingerprint read `[40f6b5e..15a6c29, base bbef230]`;
  the gate parses the bracket contents as `<sha>..<sha>` and validates both
  endpoints as bare hex, so the annotation made the whole entry unparseable and
  the run it recorded counted as no coverage at all. The base now sits outside
  the brackets. A fingerprint is a machine-read field — annotate around it, never
  inside it.

## 2026-09-07 — Phase B / Cut 1: retire the Jira adapter and the migration engine

Branch `feat/workflow-routing-phase-b` off `f6bb43c` (Phase A, PR #111). Two
commits: `9b686fe` (the whole cut, one revertable unit) and `5cc470b` (handover).

Deleted `providers/jira.py` (437) and `registry/migrate.py` (437), plus the
configuration the Jira adapter orphaned — `DEFAULT_JIRA_*`, five `Config` fields,
`Secret`, the insecure-transport floor and its env hatch, and redaction's
`_url_credentials`. 991 lines off the scripts tree (5,539 -> 4,548).

`migrate` became `scripts/migrate-task-registry.py`, a self-contained one-shot
that imports nothing from the skill — Cut 2 deletes the `index.py` and
`reconcile.py` it used to read through, so a replacement importing them would
break one phase later. Test section 10 was repointed at it rather than deleted.

Three things the session turned up that were not in the plan:

- The Jira surface was 17 files, not the 3 the handover listed (trap 1 again).
- `--provider jira` assertions pinned `PROVIDER_CLASSES` and never reached
  `config.PROVIDERS`; caught by mutation, fixed with a config-file assertion.
- `tests/test-syncable-paths.sh` refused a `SKILL.md` naming `scripts/…`, because
  `/sync` does not copy `scripts/`. Fixed with the `<template-clone>/` prefix.

AC16 was restated as a measured delta: its 4,090 absolute came from a baseline
Phase A had already moved, and `cloc` is not installed here.

Suite: 37 files green. Trees byte-identical. Revert verified by running it.

## 2026-09-08 — Phase C / Cut 2: delete the `tasks/todo.md` sync engine

Branch `feat/workflow-routing-phase-c` off `6c5fe6f` (`master` was held by
another worktree, so the branch came from `origin/master`).

Deleted `registry/reconcile.py` (797) — `reconcile`, `publish`, `pull`,
`frontier`, `_dependency_order`, `_cycles` — and extracted its surviving read
half into `registry/detail.py` (199): `Registry`, `show`, `_render_detail`,
`_matching_task`, `_combine_task`. `COMMANDS` lost four entries; the CLI gained a
terminal `AssertionError` guard so a missing dispatch is loud.

Two modules the plan had slated for deletion survived, and both for the same
reason — a surviving reader:

- `index.py` — `show` resolves against the local index, so `Registry` reads
  through it. Three genuinely dead members went (`collect_problems`, `row_text`,
  `replace_line`); `write_text` was deleted by mistake and restored, because the
  external-reference count had excluded `save()`'s internal call.
- `upsert.py` — `_published_ref` reads the link row `_sync_index` writes, and
  `providers/local.py:86,93` overwrites `external` with a local ref, so that row
  is the only memory of a GitHub publication. Deleting the write would have
  reintroduced duplicate-issue minting.

Cut 2 therefore measured **608 LOC** (4,562 -> 3,954 against `6c5fe6f`), not the
projected 1,395. The projection was left in `specs/workflow-routing.md` with the
miss recorded beside it rather than rewritten.

Trap 1 paid a third time: the spec's 10-row caller table had every line number
moved and missed four surfaces, including a shipped, checked AC in
`specs/wrap-up-gate-and-tdd-fold.md:173` pinned live by
`tests/test-pre-push-gate.sh:227` — a banner naming a deleted command would have
shipped green.

APOSD Phase 3 returned HOLD. Its MUST-FIX ("AC-19 lost its implementation") was
partly misattributed — the duplicate-append reproduces on base `6c5fe6f` too, so
that bug is pre-existing and what this session removed was the reporting that
surfaced it. Fixed at the load seam: `IndexUnreadable` + `load_index_strict`
(`index.py:369,373`), which closes the pre-existing path as well. Also applied:
the debt banner now derives its filing id instead of asking for one, three inert
`_annotate_resolution` keys deleted, `limitations` rendered under `degraded:`.

Deferred to Cut 3, reported not applied: split the three-field `Registry` context
out of `detail.py` so the write modules stop importing the read module; drop the
unconsumed `Report` from `__init__.__all__`.

Suite: 37 files, 3317 assertions, green. 12 mutation probes; one assertion came
back vacuous and was repaired.

- Learnings captured: `tasks/solutions/process/regenerate-a-caller-list-never-inherit-one.md`,
  `tasks/solutions/architecture/a-read-and-the-write-that-feeds-it-are-one-unit.md`,
  `tasks/solutions/patterns/inspection-and-action-need-two-loaders-not-one.md`,
  `tasks/solutions/process/assertion-must-be-scoped-to-the-half-it-tests.md` (third occurrence)

### [2026-09-07] — Sweep routines shipped
- Key changes: `/sweep` producer routine (`--routine janitor|architect`) with two
  lens references; `janitor` and `architect` added to the routine contract as
  producers (`PRODUCER_ROUTINES`, refused by `select`/`claim`, run-stamp branches);
  `Task.reproduction`/`proposed_fix` carried through all three providers with
  five ordered body sections; `/debug` takes an issue ref and has an unattended
  `blocked:` exit; `/software-design-expert-review --scope tree` and the
  verification-skill source-wave fallback; six project-agnostic routine prompts
  under `wrap-up-session/references/routine-prompts/`; `/auto-improve` retired and
  every reference repointed; `task-registry` configuration gains an "Unattended
  routines" section. 13/13 plan tasks, 37 test files green.
- Quality gate (Phase 3 dispatched) applied three changes: a `_section` helper in
  the local provider, section-authoritative reproduction/proposed-fix with a
  hand-edit regression test, and a corrected `--derive-id` usage line.
- Learnings captured:
  `tasks/solutions/bugs/grep-end-of-options-before-exclude-dir-drops-the-exclusions.md`,
  `tasks/solutions/bugs/test-suite-hangs-when-stdin-is-an-open-pipe.md`,
  `tasks/solutions/architecture/managed-section-is-the-field-home-and-the-metadata-block-a-projection.md`

### [2026-09-08] — Task registry verification
- Added a project-local verify-task-registry skill and three feature maps, mirrored in both skill trees.
- Exercised actual local CLI writes and read-back through isolated PTYs; retained command/output/exit evidence after owned-runtime cleanup.
- Coverage excludes GitHub, installation, and complete agent routines; derived source/spec entry points passed after correcting an unsupported source read-back expectation during wrap-up.
- Learnings captured: updated [stdin ownership](solutions/bugs/test-suite-hangs-when-stdin-is-an-open-pipe.md).

### [2026-09-09] — Published reference fallback
- Key changes: preserved published external references through local-pending upserts; made approved publication resolve the preserved reference before provider metadata matching; added regression coverage, specification, and E2E evidence.
- Learnings captured: [local-pending upserts must preserve published references](solutions/bugs/preserve-published-refs-when-local-pending-upserts-fall-back.md).

## Session Summary — 2026-09-09 [ba11f75..9017248]
- Completed: 4 issue 117 plan tasks, including implementation, regression coverage, specification updates, verification mapping, and evidence capture.
- Pending: none.
- Carry-forward: live GitHub publication E2E remains blocked because the local verifier has no external-provider driver; the mocked-provider regression covers the approved-reference update path.

### [2026-09-09] — Maintenance heading count

- Key changes: memory maintenance and its startup reminder count canonical and
  alternate session headings; added mixed-history, boundary, and pattern-parity
  regressions. Preserved the positive-multiple-of-five cadence.
- Verification: 38 test files / 3,589 assertions passed; nine isolated live-hook
  scenarios, four mutation probes, and five dispatched review passes completed.
- Learnings captured: [History heading drift](solutions/bugs/memory-maintain-history-heading-drift.md).

### [2026-09-09] — Git bootstrap fixed, verifier waves bounded (#99–#103)
- Root cause via `/debug`: Git has no `post-init` hook, so the installer's
  template-dir hook was copied into every new repo and never executed; the
  helper behind it also hardcoded `$HOME/coding-agent-workflow` with a silent
  exit and omitted three template files. Reproduced at Level 1 in an isolated HOME.
- Replaced with an explicit entry point: `scripts/scaffold-project.sh`,
  installed under `~/.agents/bin` beside a copy of `project-template/` and
  registered as the global `git scaffold` alias; `newproject` calls it after
  `git init`. README Layer 2 and the existing-project instructions rewritten
  (overwriting `cp` block gone).
- `maintain-verification-skill` full pass: source wave batched to worker slots
  with one independent review per feature and per-feature summary accounting.
- Tests: install test evaluates `newproject` as printed, installs through a
  symlinked spaced path, diffs output against the template inventory.
  37/38 files green; `test-task-registry.sh` "approval is a floor" doctor
  assertion fails identically on the untouched HEAD (pre-existing).
- Learnings captured: `tasks/solutions/bugs/git-post-init-hook-never-fires.md`

### [2026-09-11] — system-design-planning skill

- Key changes: new `/system-design-planning` skill (upstream architecture review → HTML approval gate → one issue per slice → /build), its spec, registration, static pins; worked example run producing specs/upsert-depends-on.md with a dispatched critic pass; tests/test-tdd-retirement.sh excludes .claude/worktrees; 31 stale worktrees removed.
- Learnings captured: tasks/solutions/bugs/recursive-grep-over-dot-claude-hits-stale-worktree-checkouts.md, tasks/solutions/tooling/claude-code-bash-tool-collapses-backslash-escapes.md, tasks/solutions/process/windows-suite-failures-compare-against-a-clean-head-worktree.md

### [2026-09-11] — Bulk-read gate shipped

- Key changes: mechanical `PreToolUse` gate (`.claude/hooks/bulk-read-gate.py`
  + `bulk-read-gate.sh` shim) denying whole-file reads over 350 lines on
  Claude Code and Codex, with a Pi `tool_call` mirror; new Scout-tier
  `bulk-reader` persona (haiku / gpt-5.6-luna via PI_SETUP.md's Codex column /
  deepseek-v4-flash); Codex renderer emits Scout `model` from the tier table,
  installer merges the hook once; Bulk-Read Handoff documented in CLAUDE.md,
  PI_SETUP.md, README and four skills.
- Verification: 304-case hook matrix (grown from 192 by the wrap-up review,
  which found and fixed a `;`/`&&`/`2>&1` bypass) plus 8 owned test files
  green; post-merge suite 33/40 files — the 7 red files fail with identical counts on a clean
  `bf58555` checkout (pre-existing, `tasks/e2e-log.md` § AC9). Live
  measurement: direct Read ≈8,400 parent tokens vs ≈200 via `bulk-reader`
  (24.2 s); the gate fired live on the resumed session's first `Read`.
  `/quality-gate` HOLD → 10 findings applied, 2 reported (tier membership
  hard-coded in the renderer; `context-document-optimizer` tier differs per
  harness).
- Learnings captured:
  [admit-a-cross-harness-hook-by-input-shape-not-tool-name](solutions/patterns/admit-a-cross-harness-hook-by-input-shape-not-tool-name.md),
  [worktree-sessions-refuse-compound-bash-and-sub-agents-read-the-shared-checkout](solutions/tooling/worktree-sessions-refuse-compound-bash-and-sub-agents-read-the-shared-checkout.md).

### [2026-09-12] — Bulk-read context validation
- Revised PR #128 handoffs to require anchored source maps, coverage/unknowns, direct dependency inspection, and bounded whole-component reading. Updated Python/Pi deny wording and mirrored skills.
- Ten retained blinded coding runs passed 14 held-out checks each. Mixed cost, partial direct caller inspection, and inaccurate scout maps prevent general token-saving or context-preservation claims. Full Linux suite: 40 files / 4,194 assertions.
- Independent code, design/security, and evidence reviews completed; evidence narrative findings corrected. Report: tasks/eval-results/bulk-read-context/README.md.
- Recorded Windows failures #129, Windows CI #130, Doctor environment leak #131, and independently reproduced fixture parser defect #132 for later work. Candidate parser fixes remain isolated artifacts.
- Learnings captured: updated tasks/solutions/architecture/subagents-for-research.md; created tasks/solutions/bugs/metadata-reader-writer-pairing.md.
