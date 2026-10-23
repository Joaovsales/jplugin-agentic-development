---
status: draft
implementation_paths:
  - tests/lib.sh
  - tests/run.sh
  - tests/affected.sh
  - tests/expected-failures.txt
  - tests/fixtures/**
  - tests/test-*.sh
  - .agents/skills/build/scripts/cached-suite.sh
  - .agents/hooks/session-stop.sh
  - .agents/hooks/cron-quiet-hours.sh
  - .github/workflows/tests.yml
  - AGENTS.md
  - specs/review-load-and-failure-cases.md
---

# Spec: A deep test harness — the suite as an APOSD module

> Origin: a five-reviewer analysis of `tests/` on 2026-10-20 (an Addy Osmani
> test-engineer persona, an APOSD design reviewer, a coverage mapper, an
> adversarial vacuity critic and a runtime reviewer), every claim below
> spot-checked against the tree at `4c2f3c2`.
>
> Facts this spec rests on: 76 `tests/test-*.sh` files, 25,713 lines, ~4,650
> assertions over a 239-line `tests/lib.sh`. Linux CI runs the suite serially
> in about 2 minutes (last five master runs: 100–137 s) under a 15-minute cap;
> the Windows dev host takes ~30 minutes unloaded and carries ~159 failures
> that no file, marker or list records. The suite exercises every Python
> script at least transitively, two hooks are untested, and roughly 14 % of
> assertions pin skill prose.
>
> Scope boundary: `specs/aposd-first-build.md` (building now, slices 1–7 and 9
> landed) owns *who writes tests and when* — the `test-engineer` persona, the
> `> Frozen:` freeze, `/tdd`, the Phase 5 adequacy review. This spec owns the
> *suite itself*: the harness library, selection, fixtures, vacuity, platform
> and coverage. Nothing here changes a skill's process text.

## Problem

The suite is disciplined — most refusal tests pin exit code and message, most
absence sweeps carry a positive control, fixtures are sandboxed — but the
discipline lives in each file's head, not in the library. Ousterhout's
diagnosis applies: `lib.sh` is a shallow module. It exposes nine string
assertions and hides nothing else, so every one of 76 files re-derives the
fixture lifecycle, the run-and-capture idiom, the exit-code check, the
present/absent encoding and the positive control. Where a file forgot one,
the suite has a hole, and five of five mutation probes the critic reasoned
through survive today.

### Findings, ranked

Each carries the four axes of `.agents/references/finding-model.md`.

**F1 · Selection misses the most-tested scripts.** `tests/affected.sh:40`
selects a test by verbatim path mention. `tests/test-task-registry.sh:21-23`
builds `CLI="$SCRIPTS/task-registry.py"` from variables, so a change to the
registry CLI selects only `test-routine-reproduction-e2e.sh` and
`test-sweep-routines.sh`; a change to any `registry/*.py` module selects
nothing. The same shape hides `test-lane-catalogue.sh`, `test-routine-selectors.sh`,
`test-task-escalation.sh`, `test-task-closes.sh`, `test-sweep-handoff.sh`, the
design-stack modules imported via `sys.path`, and the eight visual-plan
`plan_*.py` modules. `/build`'s per-task and per-slice affected runs pass
vacuously for the registry. The header at `affected.sh:17-18` records this as
an edge case; it is the common case for every CLI test.
`[MUST-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F2 · A whole file can report zero assertions and pass.** `tests/lib.sh:232`
`finish` prints `0 assertions passed` and exits 0. `tests/test-plan-page.sh:28-37`
skips the entire file when `playwright` is not importable; `tests.yml`
installs no browser and does not set `REQUIRE_BROWSER=1`, so AC 23 of
`specs/readable-visual-plans.md` (D27 says "which CI sets") has never run in
CI. `run.sh:89` judges by exit status only. `test-agents.sh:243-251`
hand-rolls an assertion floor for exactly this hazard; the floor belongs in
the library.
`[MUST-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F3 · Shadowed-guard refusals, in the file the learning store names.**
`tests/test-sync-retirement.sh:152-170` `assert_invalid_pattern` asserts exit 1,
the pattern and `line 2` but never *which* guard refused. In
`sync-retire.py:125-147` the last guard (`_reaches_a_root`) also names the
pattern and line, so deleting the absolute-path check or the backslash check
leaves three of eight rows green. `tasks/solutions/process/an-assertion-can-pass-because-a-different-guard-fired.md`
documents this class against this file; the fix landed as an instance, not a
primitive. `test-slice.sh:288-295` does it right for the same validator shape.
`[MUST-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent]`

**F4 · "Nothing was called" proven by a file that may not exist.**
`tests/test-task-registry.sh:2560` `assert_eq "" "$(cat "$F_BADGH/gh-bad.log" 2>/dev/null)"`
passes when the mock never ran, when the mock was not on PATH (the Windows
`gh.exe` PATHEXT case) and when the refusal happened for the wrong reason; the
sibling exit check pins no message. Same shape at `test-diagram-skill.sh:251,254`.
`[MUST-FIX | confidence: 75 | autofix_class: gated_auto | owner: agent]`

**F5 · Run-wrappers return through globals read by convention.**
`assert_exit` sets `$output` (`test-agent-policy.sh:8-18`), `guard_run` sets
`guard_rc` (`test-session-start.sh:274-291`), `run_retire` sets
`RUN_OUTPUT`/`RUN_STATUS` consumed at ~40 later sites. One inserted call
between producer and consumer asserts against a stale value with no guard —
APOSD R10 Conjoined Methods, in a suite whose job is to catch exactly that.
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F6 · The library's mechanism leaks into 6 files, 17 sites.** `_TESTS`/`_FAILS`
arithmetic appears in `test-agents.sh` (7 sites — two increment `_FAILS`
without `_TESTS`, so the trailer can report more failures than assertions),
`test-task-registry.sh`, `test-skill-frontmatter.sh`, `test-model-tiers.sh`,
`test-skill-references.sh`, `test-syncable-paths.sh`. `lib.sh:142-144` names the
hazard and closed one instance. The cause is a missing general primitive for
an arbitrary boolean verdict.
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F7 · Booleans encoded as strings to fit `assert_eq`.** The
`$([ -f x ] && echo present || echo gone)` idiom appears 120 times across 20
files; the if/else emulation `assert_eq "absent" "absent"` 42 times in 13
files, and `lib.sh:225` models it inside `assert_precedes`. The failure message
("expected: absent, actual: present") names no file.
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F8 · Fixture lifecycle re-derived 46 times.** `mktemp -d` at 75 sites in 46
files, `trap … EXIT` in 38, 12 `cleanup()` bodies differing in whitespace, 5
`new_fixture()` and 4 `new_repo()` variants, `git init` at 50 sites with 49
inline `git config user.*` calls. One file (`test-sync-retirement.sh:79`)
writes identity straight into `.git/config` to save two spawns; eleven do not.
`test-quality-receipt.sh:29-30` alone disables `gpgsign`/`autocrlf`. Shared
seed content (the `## Syncable Paths` table, the task-tracking ini, `tasks/todo.md`,
the gh-mock `labels.json`) is re-typed inline: 34 `tasks/todo.md` heredocs in
13 files, 33 `Task tracking instructions:` lines in 5, 53 `provider =` configs in
7. `tests/fixtures/` serves 10 of 76 files; `tests/fixtures/review-eval/` is used
by none (orphan of `specs/review-load-and-failure-cases.md`).
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F9 · Prose pins that are change detectors, not contracts.** About 650
assertions grep skill prose; ~210 pin full sentences verbatim
(`test-doc-conventions.sh:1035-1037` pins a 300-character AGENTS.md sentence;
`:1338-1343` pins nine phrases in two skills). Some needles are not
load-bearing at all: `test-diagram-skill.sh:203,210,246` asserts the letter `b`,
satisfied by the word "codebase" in the message; `test-e2e-classifier.sh:96` pins
`never` in a file with twelve of them. The learning store already asks authors
to write prose *for the greps* (`conventions/write-skill-prose-so-the-static-guards-can-read-it.md`),
which is the complexity flowing upward. Contract pins — a skill `name:`, a
`scripts/*.py` path, a `/skill` another skill must invoke, a heading another
skill `section_body`s — are legitimate and stay.
`[SHOULD-FIX | confidence: 90 | autofix_class: manual | owner: agent]`

**F10 · Failure output is a needle without a haystack.** `lib.sh:84` prints
`expected to contain: <needle>` with no actual value, no `file:line`, no
enclosing case. 27 `2>/dev/null` sites in `test-session-start.sh` alone discard
the stderr a failure would need. There is no test-case boundary: the unit of
execution is the file, so a failure deep in the 2,774-line registry test costs
a full rerun (minutes on Windows).
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F11 · The Windows baseline is tribal.** No skip, xfail or baseline marker
exists in `lib.sh` or `run.sh`; the ~159 failures are diffed by hand against a
clean HEAD worktree (`process/windows-suite-failures-compare-against-a-clean-head-worktree.md`).
Consequences: `receipt.py` mints `STOP` on every Windows run, and
`cached-suite.sh` records only green runs (`:115`) so the cache is dead on
Windows. Issues #129, #203, #269 each add files to a list that lives nowhere.
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: human]`

**F12 · Two hooks that run in production have no behavioural test.**
`.agents/hooks/session-stop.sh` runs on every Stop and is smoke-tested for exit 0
only (`test-hooks-json.sh:113`); sentinel removal and the unpushed-commit
warning are unasserted. `.agents/hooks/cron-quiet-hours.sh` decides whether
cron alerts are suppressed and has zero mentions in `tests/`.
`.agents/skills/build/scripts/bootstrap-worktree.sh` runs at every `/build`
worktree pre-flight and is never executed by a test. The pre-push hook's two
blocking `exit 1` branches have no test.
`[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent]`

**F13 · Environment hygiene set per file, not once.** `PYTHONDONTWRITEBYTECODE`
is set in `pyreg` wrappers and three files; six files import repo modules
without it and can write `__pycache__` under `.agents/skills/*/scripts/`, which
trips the byte-parity test. No file sets `LC_ALL`, so `sort` and
`[[:space:]]` vary by locale. `test-task-registry.sh:137-143` exports a mock
`gh` onto PATH for the rest of the file.
`[SHOULD-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent]`

**F14 · Runtime: serial CI, no per-file timeout, spawn-per-item loops.**
`tests.yml:26` runs serially although `run.sh` supports `TEST_JOBS`;
ubuntu-latest has 4 vCPU, so ~70 s of the 2-minute run is recoverable. `run.sh`
has no per-file timeout, so a hang (PR #177's self-exec'ing shim) consumes the
full 15-minute cap as a "cancelled" job with no failing assertion.
`assert_file_contains` spawns `grep` 604 times where `assert_contains` on
`$(<file)` is spawn-free; `test-sync-retirement.sh` builds 61 identical git
repos (`make_project`, 3 spawns each) where one template and `cp -r` would do.
`cached-suite.sh` keys on tree and argv but not platform or interpreter.
`[SHOULD-FIX | confidence: 90 | autofix_class: manual | owner: agent]`

## Behavior

`tests/lib.sh` becomes a deep module: a test file states *what* it checks and
the library owns *how* — fixtures, capture, verdicts, counting, platform, and
the string `tests/affected.sh` selects on. A file that forgets a discipline
cannot create a hole, because the discipline is not in the file.

- A test names the artefact it covers once, through `under_test <repo-relative path>`,
  which prints the absolute path *and* is the literal `affected.sh` matches
  (prefix match, so a directory covers its scripts). One mention serves both
  purposes, so they cannot drift.
- A refusal is asserted in one call that owns exit code and reason:
  `assert_refused <exit> <reason-fragment> -- cmd…`. A reason fragment shorter
  than 6 characters is itself a failure.
- An absence sweep runs through `assert_sweep_empty <label> <control-file> -- grep-args…`,
  which fails when a swept root is missing or the control does not match, then
  asserts empty.
- `finish` fails a file with zero assertions unless the file called
  `skip <reason>`; `skip` counts, prints `SKIP`, and under `REQUIRE_ALL=1` (set
  by `tests.yml`) fails the file. The silent half of F2 is gone; the loud half is
  visible in CI.
- Every failure prints the first 20 lines of the actual value (truncated with a
  pointer, per § Large-Artifact Handoff) and `${BASH_SOURCE[1]}:${BASH_LINENO[0]}`.
- `tests/expected-failures.txt` lists `<file> <platform-glob> <assertion message>`;
  `lib.sh` loads the rows for `$0` on the matching platform, prints `XFAIL`
  for a listed failure without counting it, and fails the file on `XPASS` so the
  list can only shrink. Linux CI loads no rows.
- Fixtures come from two primitives, `fixture_dir` and `fixture_repo`, with one
  library-owned EXIT cleanup, identity written to `.git/config`, `gpgsign` and
  `autocrlf` off, and shared seed content copied from `tests/fixtures/<area>/`
  through `fixture_copy`.
- `lib.sh` exports `LC_ALL=C` and `PYTHONDONTWRITEBYTECODE=1` beside
  `PYTHONUTF8=1`. `run.sh` wraps each file in `timeout "${TEST_FILE_TIMEOUT:-300}"`.
  `tests.yml` sets `TEST_JOBS=4` and `REQUIRE_ALL=1`.

## Inputs

- The 76 existing test files, migrated in place; no test is deleted for being
  prose-based unless F9's rule says its needle is not a contract.
- `tests/fixtures/` as the home for shared seed content.
- The Windows baseline, captured once from a clean-HEAD run on the dev host
  into `tests/expected-failures.txt` with each row's cause from #129/#203/#269.

## Outputs

- A `lib.sh` interface of ~18 functions (the nine existing plus `fixture_dir`,
  `fixture_repo`, `fixture_copy`, `run`, `assert_exit`, `assert_refused`,
  `assert_true`/`assert_false`, `assert_file_exists`/`assert_file_absent`,
  `assert_sweep_empty`, `under_test`, `py_module`, `skip`, `pass`/`fail`,
  `begin_case`/`end_case`).
- `tests/expected-failures.txt` and `XFAIL`/`XPASS`/`SKIP` lines in the trailer.
- Behavioural tests for `session-stop.sh`, `cron-quiet-hours.sh`,
  `bootstrap-worktree.sh` and the pre-push hook's blocking branches.

## Edge Cases

- A file whose every assertion is inside a loop that iterates zero times now
  fails at `finish`; that is the intended verdict (F2).
- A `pass`-only file written for a smoke check must call `skip` or assert
  something; the migration audits each file whose count drops.
- `under_test` with a path that does not exist fails the file at source time —
  a renamed script cannot silently drop a test from selection.
- `XPASS` on a row whose cause was fixed upstream (#269 lands) fails the Windows
  run until the row is removed: deliberate, so the list reflects reality.
- `assert_refused` on a command that prints the fragment and exits 0 fails on
  the exit half; one that exits non-zero for a different reason fails on the
  fragment half (closes F3 structurally).
- `cp -r` of a template repo copies `.git/index`; a scenario that runs
  `git status` re-hashes, which is correct and cheaper than three spawns.
- Parallel CI: every write already lands in a `mktemp` dir; `__pycache__` is
  the one shared-tree hazard and `PYTHONDONTWRITEBYTECODE=1` closes it.
- A test file that migrates to the primitives but still names its artefact by
  a variable-built path is caught by its area slice's selection criterion, not
  by the suite-wide sweep: each area slice proves `affected.sh` selects its
  files on the artefact's path.

## Decisions

| ID | Decision | Options | Recommended | Wrong when | Status |
|----|----------|---------|-------------|------------|--------|
| D1 | How selection learns what a test covers | A) `under_test <path>` in lib.sh — the resolved path *is* the match string; B) a `# covers:` header `affected.sh` parses; C) keep inference | A; verbatim inference stays as the fallback union during migration | a test drives a skill by name and touches no path; then it names the skill directory through `under_test` | settled |
| D2 | Windows baseline | A) `xfail` rows in `tests/expected-failures.txt`, platform-keyed, `XPASS` fails; B) fix the ~159 at the root first (#129/#203/#269, the `gh` mock shim); C) Windows CI (#130) | A now, B as the list shrinks, C when A is green | the team would rather not carry a list at all; then B alone, at the cost of every Windows run staying red meanwhile | settled |
| D3 | Prose pins | A) keep only contract pins (a `name:`, a script path, a `/skill` invocation, a heading another skill reads, the AGENTS.md end marker, a build-prompt line); replace sentence pins with marker tokens or heading pins; B) keep all, lint needles ≥ 3 chars; C) delete prose tests | A | a sentence *is* the contract another artifact consumes; those stay verbatim | settled |
| D4 | Test-case boundary | A) `begin_case <name>`/`end_case` with `TEST_CASE=<glob>` filtering, then split the two 2,000-line files at their section seams; B) split only; C) neither | A, stopping at header, count and filter — no setup/teardown semantics | — | settled |
| D5 | In-process Python tests | A) keep bash as the driver, batch per-section heredocs; B) move CLI-matrix tests to the `unittest` shape of `test-pr-linkage.sh` | A for this spec; B is a per-file call later | a file spends most of its time in interpreter starts (test-slice.sh ≈ 45) — then B for that file | settled |
| D6 | CI parallelism | A) `TEST_JOBS=4` in `tests.yml`; B) a matrix job per file group | A | a load-sensitive test (upstream-drift's relative bound) flakes under 4 jobs; then pin it to run last or widen the bound | settled |
| D7 | Scope vs `aposd-first-build` | A) this spec changes harness and test files only, never skill text; B) fold into that spec's slice 12 | A | — | settled |
| D8 | Migration granularity | A) one slice per area of related test files (registry, sync and install, hooks and wrap-up, doc guards, skill scripts), each over the file ceiling and named on the `Sizing:` line; B) one slice per file | A | — | settled |
| D9 | CI browser check for the plan page | A) `tests.yml` installs `playwright` with chromium and sets `REQUIRE_BROWSER=1`, so `tests/test-plan-page.sh` runs its browser checks in CI and D27 of `specs/readable-visual-plans.md` stays true; B) amend D27 to say CI does not browser-check | A — the owner's answer to Q1 on 2026-10-21 | the chromium download pushes the CI suite step past its wall-time bound; then cache `~/.cache/ms-playwright` keyed on the `playwright` version before falling back to B | settled |

## Open questions

| ID | Question | Blocks | Needed from |
|---|---|---|---|

## Acceptance Criteria

1. `finish` exits non-zero on zero assertions unless the file called `skip`; `skip <reason>` prints `SKIP`, counts, and under `REQUIRE_ALL=1` fails the file; the trailer prints `passed`, `failed`, `xfail` and `skipped` counts and `tests/run.sh` sums them. `tests/test-lib.sh` pins every clause.
2. Every `assert_*` failure prints `file:line` and up to 20 lines of the actual value; `assert_file_contains` reads the file once and matches with builtins; `fixture_dir`, `fixture_repo`, `fixture_copy`, `run`, `assert_exit`, `assert_refused` (a fragment under 6 characters fails), `assert_true`/`assert_false`, `assert_file_exists`/`assert_file_absent`, `assert_sweep_empty`, `under_test` (a missing path fails at source), `py_module`, `pass`/`fail` exist with tests in `tests/test-lib.sh`.
3. `lib.sh` exports `LC_ALL=C` and `PYTHONDONTWRITEBYTECODE=1` beside `PYTHONUTF8=1`; `assert_precedes` no longer uses the `assert_eq "ordered" "ordered"` emulation; `_TESTS` and `_FAILS` are written only through `pass`/`fail`.
4. `tests/affected.sh` selects a test whose `under_test` argument is a prefix of a changed path; `tests/test-affected.sh` pins that a fixture test naming `under_test .agents/skills/x/scripts/` is selected by a change to `.agents/skills/x/scripts/y.py`, that verbatim inference still selects, and that the runner rule is unchanged.
5. `assert_invalid_pattern` in `test-sync-retirement.sh` takes the reason fragment and goes through `assert_refused`, so deleting `sync-retire.py:125-126` makes the "absolute" and "windows drive letter" rows fail; no `assert_eq "" "$(cat … 2>/dev/null)"` remains in `test-task-registry.sh` or `test-diagram-skill.sh`; `tests/fixtures/task-registry/gh` creates its log on start; the sweeps in `test-model-tiers.sh`, `test-tdd-retirement.sh` and `test-doc-conventions.sh` go through `assert_sweep_empty` with a positive control.
6. No needle shorter than 3 characters remains in `tests/`; `test-diagram-skill.sh` pins `"b" has no sources`; `test-e2e-classifier.sh:96` pins the sentence; sentence pins in `test-doc-conventions.sh` that are not contracts per D3 are replaced by marker or heading pins, with the count recorded in the PR body.
7. `tests.yml` runs with `TEST_JOBS=4` and `REQUIRE_ALL=1`; `run.sh` wraps each file in a timeout (default 300 s, `TEST_FILE_TIMEOUT`) and reports `FAIL … timed out after N s`; `tests/test-run-sh.sh` pins it; `cached-suite.sh` includes `uname -s`, `$TEST_PYTHON --version` and `command -v gh` in its key and `tests/test-cached-suite.sh` pins it.
8. `tests/test-plan-page.sh` under a Python without `playwright` prints `SKIP` and, with `REQUIRE_ALL=1`, exits non-zero; `tests.yml` installs `playwright` with chromium and sets `REQUIRE_BROWSER=1`, so the file's browser checks run in CI (D9); the CI suite step's wall time, the browser install excluded, is below today's 100–137 s.
9. The registry-area files — `test-task-registry.sh`, `test-routine-selectors.sh`, `test-routine-skills.sh`, `test-routines-contract.sh`, `test-routine-reproduction-e2e.sh`, `test-lane-catalogue.sh`, `test-sweep-handoff.sh`, `test-sweep-routines.sh`, `test-task-closes.sh`, `test-task-escalation.sh`, `test-closure.sh`, `test-go-lanes.sh` — use the lib primitives: no private `cleanup`, `new_fixture`, `new_repo`, `pyreg` or `run_*` wrapper that sets a global, no `_TESTS`/`_FAILS` arithmetic, no present/gone encoding, no `export PATH=`, no per-file `PYTHONDONTWRITEBYTECODE`; shared seed (`tasks/todo.md`, `docs/task-tracking.md`, `labels.json`, `issues.json`) lives under `tests/fixtures/task-registry/` and is reached through `fixture_copy`; `bash tests/affected.sh` on a change to `registry/model.py` selects every file in this list.
10. The sync-and-install-area files — `test-sync-retirement.sh`, `test-sync-managed-block.sh`, `test-sync-settings-merge.sh`, `test-syncable-paths.sh`, `test-install-sh.sh`, `test-codex-install.sh`, `test-living-spec-reconciliation.sh`, `test-migrate-learning-store.sh`, `test-solutions-schema.sh` — meet the same bar; the `## Syncable Paths` table seed lives under `tests/fixtures/sync/`; `make_project` and `make_template` build one template and copy it, and `test-sync-retirement.sh`'s Windows wall time is at least 2 minutes lower than the #179 baseline; `affected.sh` on a change to `sync-retire.py` selects `test-sync-retirement.sh`.
11. The hooks-and-wrap-up-area files — `test-session-start.sh`, `test-pre-compact.sh`, `test-hooks-json.sh`, `test-plugin-manifest.sh`, `test-upstream-drift.sh`, `test-quality-receipt.sh`, `test-publish-evidence.sh`, `test-gh-pr.sh` — meet the same bar, and `test-session-start.sh` never runs the hook against the live checkout.
12. The doc-guard-area files — `test-agents.sh`, `test-model-tiers.sh`, `test-skill-frontmatter.sh`, `test-skill-references.sh`, `test-skills-table.sh`, `test-instruction-budget.sh`, `test-grilling-adoption.sh`, `test-doc-conventions.sh` — meet the same bar; `test-doc-conventions.sh`'s five private heading extractors are replaced by `section_body`; `test-agents.sh`'s hand-rolled assertion floor is removed in favour of AC 1.
13. The skill-script-area files — `test-slice.sh`, `test-plan-render.sh`, `test-agent-policy.sh`, `test-make-it-simpler.sh`, `test-visual-render.sh`, `test-html-presentation.sh`, `test-e2e-evidence.sh`, `test-eval-skill.sh`, `test-diagram-skill.sh`, `test-design-stack-brief.sh`, `test-design-stack-catalog.sh`, `test-design-stack-evidence.sh`, `test-design-stack-install.sh`, `test-design-stack-video.sh` — meet the same bar; `tests/fixtures/review-eval/` is either used by a test or removed with a note in `specs/review-load-and-failure-cases.md`; `affected.sh` on a change to a visual-plan `plan_*.py` module selects `test-plan-render.sh`.
14. `tests/expected-failures.txt` exists with one row per Windows baseline failure and its cause cross-referenced to #129, #203 or #269; a clean-HEAD Windows run exits 0 with `XFAIL` lines; an `XPASS` fails the file; Linux CI output is byte-identical to before; `AGENTS.md` names the file in one line below the end marker; `receipt.py` and `cached-suite.sh` see exit 0 on such a run.
15. `tests/test-session-stop.sh` asserts sentinel removal and the unpushed-commit warning; `tests/test-cron-quiet-hours.sh` asserts `cron_should_suppress` on both sides of the window and `record_metric`'s output; `tests/test-bootstrap-worktree.sh` runs the script in a fixture repo; `test-pre-push-gate.sh` covers the hook's two `exit 1` branches.
16. `begin_case <name>`/`end_case` print a header, count per case and honour `TEST_CASE=<glob>`; `test-task-registry.sh` and `test-sync-retirement.sh` are split at their section seams into files `affected.sh` selects on the same artefact paths.
17. Suite-wide: `grep -c '_TESTS=\$((\|_FAILS=\$((' tests/test-*.sh` is zero; `grep -c 'echo present || echo' tests/test-*.sh` is zero; no literal `assert_eq "<x>" "<x>"` pair remains; `mktemp -d` appears only in `lib.sh`; `git init` appears in `tests/test-*.sh` only inside a test *of* git behaviour; `bash tests/run.sh` is green on Linux CI and a Windows full run shows no failure outside `tests/expected-failures.txt`.

## Build Order

Sizing: 12 slices. Ceiling: per `slice/references/sizing.md`. Over: slices 5, 6, 7, 8 and 9 (files: each migrates one area of related test files to the lib primitives and, by D8, an area lands whole so the suite-wide sweep in AC 17 can be stated once; splitting by file would leave a slice whose fixture seed another slice still re-types); slice 12 (files: the two split files and their successors change together or `affected.sh` selects neither).

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Deep lib | the new primitives, `file:line` and actual-value failures, zero-assertion `finish`, `skip`, `pass`/`fail`, env exports, builtin `assert_file_contains`; every existing test untouched and green | `tests/lib.sh`, `tests/test-lib.sh`, `tests/run.sh`, `tests/test-run-sh.sh` | — | 1, 2, 3 | `bash tests/test-lib.sh && bash tests/test-run-sh.sh` | 4 files · 1 system · 3 ACs |
| 2 | Selection by declaration | `affected.sh` prefix-matches `under_test` literals beside verbatim inference | `tests/affected.sh`, `tests/test-affected.sh` | 1 | 4 | `bash tests/test-affected.sh` | 2 files · 1 system · 1 AC |
| 3 | Vacuity closures | `assert_refused` at every refusal site, `assert_sweep_empty` at every sweep, the mock log created on start, the non-load-bearing needles replaced | `tests/test-sync-retirement.sh`, `tests/test-task-registry.sh`, `tests/test-diagram-skill.sh`, `tests/test-e2e-classifier.sh`, `tests/test-model-tiers.sh`, `tests/test-tdd-retirement.sh`, `tests/test-doc-conventions.sh`, `tests/fixtures/task-registry/gh` | 1 | 5, 6 | `bash tests/run.sh tests/test-sync-retirement.sh tests/test-task-registry.sh tests/test-diagram-skill.sh tests/test-e2e-classifier.sh tests/test-model-tiers.sh tests/test-tdd-retirement.sh tests/test-doc-conventions.sh` | 8 files · 2 systems · 2 ACs |
| 4 | Runtime | `TEST_JOBS=4` and `REQUIRE_ALL=1` in CI, the per-file timeout, the cached-suite key, the `playwright` install for the plan-page check | `.github/workflows/tests.yml`, `tests/run.sh`, `tests/test-run-sh.sh`, `.agents/skills/build/scripts/cached-suite.sh`, `tests/test-cached-suite.sh`, `tests/test-plan-page.sh` | 1 | 7, 8 | `bash tests/test-run-sh.sh && bash tests/test-cached-suite.sh && bash tests/test-plan-page.sh`; CI green | 6 files · 4 systems · 2 ACs |
| 5 | Registry area | the twelve registry-area tests on the lib primitives, shared seed under `tests/fixtures/task-registry/`, selected by artefact path | `tests/test-task-registry.sh`, `tests/test-routine-selectors.sh`, `tests/test-routine-skills.sh`, `tests/test-routines-contract.sh`, `tests/test-routine-reproduction-e2e.sh`, `tests/test-lane-catalogue.sh`, `tests/test-sweep-handoff.sh`, `tests/test-sweep-routines.sh`, `tests/test-task-closes.sh`, `tests/test-task-escalation.sh`, `tests/test-closure.sh`, `tests/test-go-lanes.sh`, `tests/fixtures/task-registry/**`, `tests/fixtures/closure/**` | 2, 3 | 9 | `bash tests/affected.sh --run HEAD~1` after the migration commit | 14 files · 1 system · 1 AC |
| 6 | Sync and install area | the nine sync-and-install tests on the lib primitives, the Syncable Paths seed under `tests/fixtures/sync/`, the template-repo copy | `tests/test-sync-retirement.sh`, `tests/test-sync-managed-block.sh`, `tests/test-sync-settings-merge.sh`, `tests/test-syncable-paths.sh`, `tests/test-install-sh.sh`, `tests/test-codex-install.sh`, `tests/test-living-spec-reconciliation.sh`, `tests/test-migrate-learning-store.sh`, `tests/test-solutions-schema.sh`, `tests/fixtures/sync/**` | 2, 3 | 10 | `bash tests/affected.sh --run HEAD~1` after the migration commit | 10 files · 1 system · 1 AC |
| 7 | Hooks and wrap-up area | the eight hook and wrap-up tests on the lib primitives; the SessionStart hook always run in a fixture repo | `tests/test-session-start.sh`, `tests/test-pre-compact.sh`, `tests/test-hooks-json.sh`, `tests/test-plugin-manifest.sh`, `tests/test-upstream-drift.sh`, `tests/test-quality-receipt.sh`, `tests/test-publish-evidence.sh`, `tests/test-gh-pr.sh` | 2 | 11 | `bash tests/affected.sh --run HEAD~1` after the migration commit | 8 files · 1 system · 1 AC |
| 8 | Doc guard area | the eight doc-guard tests on the lib primitives; `section_body` replaces the private extractors; the assertion floor retired | `tests/test-agents.sh`, `tests/test-model-tiers.sh`, `tests/test-skill-frontmatter.sh`, `tests/test-skill-references.sh`, `tests/test-skills-table.sh`, `tests/test-instruction-budget.sh`, `tests/test-grilling-adoption.sh`, `tests/test-doc-conventions.sh` | 2, 3 | 12 | `bash tests/affected.sh --run HEAD~1` after the migration commit | 8 files · 1 system · 1 AC |
| 9 | Skill script area | the fourteen skill-script tests on the lib primitives; the review-eval orphan resolved | `tests/test-slice.sh`, `tests/test-plan-render.sh`, `tests/test-agent-policy.sh`, `tests/test-make-it-simpler.sh`, `tests/test-visual-render.sh`, `tests/test-html-presentation.sh`, `tests/test-e2e-evidence.sh`, `tests/test-eval-skill.sh`, `tests/test-diagram-skill.sh`, `tests/test-design-stack-brief.sh`, `tests/test-design-stack-catalog.sh`, `tests/test-design-stack-evidence.sh`, `tests/test-design-stack-install.sh`, `tests/test-design-stack-video.sh`, `tests/fixtures/review-eval/**`, `specs/review-load-and-failure-cases.md` | 2, 3 | 13 | `bash tests/affected.sh --run HEAD~1` after the migration commit | 16 files · 2 systems · 1 AC |
| 10 | Windows baseline | `tests/expected-failures.txt` from a clean-HEAD run, `XFAIL`/`XPASS` in lib.sh, the AGENTS.md pointer | `tests/lib.sh`, `tests/expected-failures.txt`, `tests/test-lib.sh`, `AGENTS.md` | 1 | 14 | `bash tests/test-lib.sh`; a Windows full run exits 0 | 4 files · 2 systems · 1 AC |
| 11 | Hook coverage | behavioural tests for session-stop, cron-quiet-hours, bootstrap-worktree and the pre-push exit branches | `tests/test-session-stop.sh`, `tests/test-cron-quiet-hours.sh`, `tests/test-bootstrap-worktree.sh`, `tests/test-pre-push-gate.sh`, `.agents/hooks/session-stop.sh`, `.agents/hooks/cron-quiet-hours.sh` | 1 | 15 | `bash tests/test-session-stop.sh && bash tests/test-cron-quiet-hours.sh && bash tests/test-bootstrap-worktree.sh && bash tests/test-pre-push-gate.sh` | 6 files · 2 systems · 1 AC |
| 12 | Case boundaries | `begin_case`/`end_case` with `TEST_CASE` filtering; the two 2,000-line files split at their seams; the suite-wide sweep green | `tests/lib.sh`, `tests/test-lib.sh`, `tests/test-task-registry.sh`, `tests/test-sync-retirement.sh`, `tests/test-task-registry-*.sh`, `tests/test-sync-retirement-*.sh` | 5, 6, 7, 8, 9, 10 | 16, 17 | `bash tests/run.sh` | 6 files · 1 system · 2 ACs |

Left to other work, deliberately: the `test-engineer` persona and Phase 5
adequacy review (`specs/aposd-first-build.md` slices 10 and 12); Windows CI
(#130) once slice 10 makes a Windows run meaningful; the root-cause fixes for
baseline rows (#129, #203, #269, and the `gh` mock shim that would retire ~100
of them) which slice 10 makes visible rather than solving; per-file wall-time
targets (#179), which slices 1 and 6 advance but do not close.

Build prompt:

```
Invoke `/build` for `specs/test-suite-aposd.md`.
Plan: `## Plan: test-suite-aposd` in `tasks/todo.md`, 12 slices, ready set <1>.
Files: tests/lib.sh, tests/run.sh, tests/affected.sh, tests/expected-failures.txt, tests/fixtures/**, tests/test-*.sh, .agents/skills/build/scripts/cached-suite.sh, .agents/hooks/session-stop.sh, .agents/hooks/cron-quiet-hours.sh, .github/workflows/tests.yml, AGENTS.md, specs/review-load-and-failure-cases.md.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints:
- D1: a test names its artefact once through `under_test`, whose argument is the literal `affected.sh` prefix-matches; verbatim inference stays as the fallback union, never a `# covers:` header.
- D2: the Windows baseline is `tests/expected-failures.txt` loaded by `lib.sh`; an `XPASS` fails the file; no root-cause fix for a baseline row is in scope.
- D3: a prose pin survives only when another artifact consumes the string; every other sentence pin becomes a marker or heading pin, and the replaced count goes in the PR body.
- D4: `begin_case`/`end_case` stop at header, count and `TEST_CASE` filter — no setup or teardown semantics.
- D5: bash stays the driver; no test file moves to the in-process `unittest` shape in this build.
- D7: no skill's SKILL.md or reference text changes; the surface is the harness, the tests, the two hooks, CI and the review-eval spec reconciliation.
- D8: an area slice lands whole, every file in its list migrated in the same slice.
- D9: `tests.yml` installs `playwright` with chromium and sets `REQUIRE_BROWSER=1`; D27 of `specs/readable-visual-plans.md` is not amended.
```

## Implementation Paths

- `tests/lib.sh` — the deep interface; `tests/test-lib.sh` — its own tests, new.
- `tests/run.sh`, `tests/affected.sh`, `tests/test-run-sh.sh`, `tests/test-affected.sh`.
- `tests/expected-failures.txt` — new.
- `tests/fixtures/<area>/` — shared seed content; `tests/fixtures/review-eval/` resolved.
- `.agents/skills/build/scripts/cached-suite.sh`, `tests/test-cached-suite.sh`.
- `.github/workflows/tests.yml`.
- `tests/test-session-stop.sh`, `tests/test-cron-quiet-hours.sh`, `tests/test-bootstrap-worktree.sh` — new.
- The 76 existing `tests/test-*.sh`, migrated by area slice.
- `specs/review-load-and-failure-cases.md` — a one-line reconciliation of the review-eval fixture.
- `AGENTS.md` below the end marker — an `Expected failures: tests/expected-failures.txt` line.
