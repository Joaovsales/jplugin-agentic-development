---
status: draft
implementation_paths:
  - .agents/skills/build/scripts/cached-suite.sh
  - .agents/skills/build/SKILL.md
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/yolo/SKILL.md
  - .agents/skills/auto-push/SKILL.md
  - AGENTS.md
  - tests/run.sh
  - tests/affected.sh
  - tests/test-cached-suite.sh
  - tests/test-affected.sh
  - tests/test-run-sh.sh
  - tests/test-doc-conventions.sh
  - tests/test-skill-invocation-chain.sh
---

# Spec: A build session runs the full suite at most twice

> Origin: [#178](https://github.com/Joaovsales/jplugin-agentic-development/issues/178).
> Its stretch criterion (the two slowest test files under 5 min each) is
> [#179](https://github.com/Joaovsales/jplugin-agentic-development/issues/179)
> and is out of scope here.
>
> Facts this spec rests on: the full suite takes ~30 min on the Windows dev
> machine and ~1 min on Linux CI. The last ten successful `tests.yml` runs took
> 45–64 s. The one CI cancellation (PR #177) was the self-exec'ing `python3`
> shim fixed in `89acf9c`, not the suite's duration. A build session today runs
> the full suite about five times: `/build` baseline, every task, every slice
> close, Phase 2, after the quality gate, then `/wrap-up-session` Step 6.

## Behavior

A build session pays for the full suite at most twice: once for the green
baseline and once pre-push in `/wrap-up-session` Step 6. Every other
verification point runs only the **affected** test files. A second full-suite
request on a tree that already passed, for the same command, is answered from
a cached record instead of re-running.

- **Cached full runs.** Every full-suite run in `/build`, `/wrap-up-session`,
  `/yolo` and `/auto-push` goes through
  `.agents/skills/build/scripts/cached-suite.sh -- <full-suite command>`.
  The command is the `Full suite: <command>` line below the `AGENTS.md` end
  marker, used verbatim by every skill (in this repository,
  `bash tests/run.sh`); a project that declares none uses the runner `/build`
  identified. The script hashes the working tree (tracked and untracked, not ignored)
  together with the command. When a green record exists for that key, it
  prints `cached-suite: reused green run of <command> on tree <hash> from <UTC time>`
  and exits 0 without running anything. Otherwise it runs the command,
  passes its output and exit status through, and records the result only
  when the run is green. The `/yolo` or `/auto-push` pre-flight baseline and
  `/build`'s baseline therefore cost one run between them. So does a
  `/wrap-up-session` Step 6 on a tree the build already proved green.
- **One suite at a time.** While a `cached-suite.sh` run is in progress for
  the repository, a second invocation refuses. It prints
  `cached-suite: a suite is already running (pid <n>, since <UTC time>)` and
  exits 3, starting nothing. A lock whose pid is no longer alive is reclaimed.
  The skills extend the same rule to every test run: no targeted file or
  affected-test run starts while a full suite is running.
- **No poll loops.** The skills launch the full suite as a background task
  (`run_in_background` on Claude Code) and wait for its completion
  notification. While it runs they do non-conflicting work: learnings, PR
  body, handover. They never wait in a foreground `sleep` or poll loop.
- **Affected tests between checkpoints.** After each task, at each slice
  close, at the parallel-dispatch barrier, in `/build` Phase 2 and after the
  quality gate, `/build` runs the project's declared affected-test command
  against the build's base SHA. A project declares it below the end marker
  of `AGENTS.md` as `Affected tests: <command with {base}>`. In this
  repository that is `bash tests/affected.sh --run {base}`. `/build` runs it
  through `cached-suite.sh` as well, so the lock refuses it beside a running
  suite and an unchanged tree reuses its green run. When a project
  declares none, the builder runs the test files that cover the changed
  paths and names them in its log line.
- **This repository's selector.** `tests/affected.sh <base>` prints one
  `tests/test-*.sh` path per line, sorted and unique. It includes every test
  file changed or added since `<base>` (committed, staged, unstaged or
  untracked), and every test file whose text contains a changed path verbatim.
  When a runner file changed (`tests/run.sh`, `tests/lib.sh` or
  `tests/affected.sh`), it prints every test file. `--run` passes the list to
  `tests/run.sh`. When the list is empty, it prints `affected: none` and
  exits 0 without running anything.
- **Named test files in `tests/run.sh`.** `bash tests/run.sh [--jobs N] [file ...]`
  runs only the named files. With no file arguments it runs every
  `tests/test-*.sh` as today. A named path that does not exist is a usage
  error (exit 2).

## Inputs

- The `Full suite:` line below the `AGENTS.md` end marker, passed after `--`
  on `cached-suite.sh` (in this repository, `bash tests/run.sh`).
- The build's base SHA, recorded by `/build` before its first task, passed
  to the affected-test command as `{base}`.
- The `Affected tests:` line below the `AGENTS.md` end marker.

## Outputs

- Records under `$(git rev-parse --git-common-dir)/cached-suite/`, one file
  per green key. The records are shared across the repository's worktrees and
  never committed.
- A lock directory `$(git rev-parse --git-common-dir)/cached-suite/lock`
  holding the running pid and start time, removed on exit.
- The wrapped command's stdout, stderr and exit status, unchanged, when the
  command runs.

## Edge Cases

- **Red run.** Not recorded. The next invocation on the same tree runs again.
- **Tree changes between runs.** Any edit, including an untracked new file,
  changes the key, so the run is real.
- **Ignored files** (`node_modules`, `.env*`) are not in the key. A change
  that only touches an ignored file can reuse a green record. This is
  accepted: `/build` Step 0.5 already treats env-file drift as a worktree
  bootstrap concern, not a suite concern.
- **Same tree, different command** (for example `--jobs 4` against serial):
  different key, real run.
- **Killed run.** The lock names a dead pid, so the next invocation reclaims
  it. No record was written, because only a finished green run writes one.
- **Not a git repository.** `cached-suite.sh` runs the command uncached and
  prints `cached-suite: not a git repository, running uncached` to stderr.
- **Selector miss.** A test that builds paths dynamically (for example by
  looping over every skill) is not selected by a verbatim-path match. The
  pre-push full run and PR CI catch what the selector misses. This is the
  risk #178 accepted.
- **Local-merge path** (`/wrap-up-session` Step 7.5, no remote). The full
  run on the merged result is a new tree and runs for real. It is the one
  third full run, and it happens only when there is no PR to run CI.
- **CI timeout.** `tests.yml` keeps `timeout-minutes: 15`. It already
  exceeds the measured Linux suite time about 14×, so nothing changes in
  this spec.

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Where the one pre-push full run happens | Locally, `/wrap-up-session` Step 6; `/build` Phase 2 and the post-quality-gate re-run become affected-test runs; PR CI stays the clean-checkout backstop | user | Matches #178's ACs; a push never goes out without a local green full run |
| 2 | How the baseline is cached | A script keyed on a hash of the working tree plus the command, records under the git common dir | user | Enforced key instead of an agent-written file; shared across worktrees |
| 3 | How affected files are chosen | A script, `tests/affected.sh`, with a full-suite fallback when a runner file changed | user | Deterministic and testable |
| 4 | The two slowest files (stretch AC) | Out of scope, filed as #179 | user | Keeps this change to rules plus small scripts |
| 5 | Where `cached-suite.sh` lives | `.agents/skills/build/scripts/`, beside `bootstrap-worktree.sh`, wrapping any command | assumed | `/build` ships to projects without `tests/run.sh`; the cache has to be generic, the selector does not |
| 6 | How a project names its affected-test command | An `Affected tests:` line below the `AGENTS.md` end marker, with `{base}` | assumed | Same pattern as `Task tracking instructions:`; survives `/sync` |
| 7 | Key on a clean `HEAD^{tree}` or on the working tree | Working tree, through a temporary index (`GIT_INDEX_FILE`, `git add -A`, `git write-tree`) | assumed | `/wrap-up-session` Step 6 runs on an uncommitted tree; a clean-tree-only key would never hit there |
| 8 | Enforce "one suite at a time" in code or prose | Both: the lock refuses a second full run; the skills forbid targeted runs beside a running suite | assumed | Only full runs pass through the script; the load-contention cost (2.4×) came from targeted loops beside a suite |
| 9 | CI timeout | Unchanged at 15 min | assumed | Linux suite runs in ~1 min; the cancellation had another cause, already fixed |
| 10 | How every skill spells the full-suite command | A `Full suite:` line beside `Affected tests:`, used verbatim; the affected-test command also runs through `cached-suite.sh` | assumed | The key hashes the command, so a hand-spelled variant is a silent cache miss; the lock then covers affected runs too |

## Acceptance Criteria

1. `cached-suite.sh -- <cmd>` runs `<cmd>` and passes its output and exit
   status through. The second invocation on the same working tree with the
   same command prints `cached-suite: reused green run` and exits 0 without
   running `<cmd>`. A red run is not recorded. An edited or added file, or a
   different command, runs again (`tests/test-cached-suite.sh`).
2. A second `cached-suite.sh` invocation while one is running exits 3 with
   `cached-suite: a suite is already running` and starts nothing. A lock
   left by a dead pid is reclaimed (`tests/test-cached-suite.sh`).
3. `tests/affected.sh <base>` prints the changed or added test files plus the
   test files that contain a changed path verbatim. It prints every test file
   when a runner file changed. With no changes it prints `affected: none`.
   `--run` executes the list through `tests/run.sh`, and `tests/run.sh file ...`
   runs only the named files (`tests/test-affected.sh`, `tests/test-run-sh.sh`).
4. `/build` runs the full suite only in its pre-flight baseline, through
   `cached-suite.sh`. The per-task run, the slice close, the parallel barrier,
   Phase 2 and the post-quality-gate run use the declared affected-test
   command against the base SHA, and Key Principles no longer says "Full test
   suite after every task" (`tests/test-doc-conventions.sh`).
5. `/wrap-up-session` Step 6 and the Step 7.5 merged-result run go through
   `cached-suite.sh`, and `/yolo` and `/auto-push` pre-flight baselines do too
   (`tests/test-doc-conventions.sh`).
6. `/build` and `/wrap-up-session` forbid starting any test run while a suite
   is running, and forbid foreground `sleep` or poll loops. The full suite is
   launched in the background and waited on through its completion
   notification (`tests/test-doc-conventions.sh`).
7. `AGENTS.md` below the end marker declares
   `Full suite: bash tests/run.sh` and
   `Affected tests: bash tests/affected.sh --run {base}`; `/build`, `/yolo`,
   `/auto-push` and `/wrap-up-session` read the `Full suite:` line, and
   `/build` runs the affected-test command through `cached-suite.sh`
   (`tests/test-doc-conventions.sh`).
8. `tests.yml`'s `timeout-minutes: 15` exceeds the measured Linux suite time:
   the last ten successful `tests.yml` runs each take under 2 min
   (`gh run list --workflow tests.yml --status success --limit 10`).

## Implementation Paths

- `.agents/skills/build/scripts/cached-suite.sh` — the tree-keyed cache and the one-suite lock around any full-suite command
- `.agents/skills/build/SKILL.md` — baseline through the cache; affected tests at every other checkpoint; the concurrency and no-poll rules
- `.agents/skills/wrap-up-session/SKILL.md` — Step 6 and the merged-result run through the cache; the concurrency and no-poll rules
- `.agents/skills/yolo/SKILL.md`, `.agents/skills/auto-push/SKILL.md` — pre-flight baseline through the cache, so `/build`'s baseline reuses it
- `AGENTS.md` — this repository's `Affected tests:` declaration below the end marker
- `tests/run.sh` — optional named-file arguments
- `tests/affected.sh` — this repository's affected-test selector
- `tests/test-cached-suite.sh` — AC 1 and 2
- `tests/test-affected.sh`, `tests/test-run-sh.sh` — AC 3
- `tests/test-doc-conventions.sh` — AC 4 to 7

## Build Order

Sizing: 4 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 2: its four `tests/` files count as four systems under the container rule, but they are one runner, its selector and their two tests; slice 4: three skills plus the tests file, because each skill edit is one or two sentences naming `cached-suite.sh`.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Cached suite runner | `cached-suite.sh` reuses a green run per working tree and command, and refuses a second concurrent suite | `.agents/skills/build/scripts/cached-suite.sh`, `tests/test-cached-suite.sh` | — | 1, 2 | `bash tests/test-cached-suite.sh` | 2 files · 2 systems · 2 ACs |
| 2 | Affected-test selector | `tests/affected.sh` lists and runs the test files a change touches; `tests/run.sh` takes named files | `tests/affected.sh`, `tests/run.sh`, `tests/test-affected.sh`, `tests/test-run-sh.sh` | — | 3 | `bash tests/test-affected.sh && bash tests/test-run-sh.sh` | 4 files · 4 systems · 1 AC |
| 3 | Build runs affected tests | `/build` runs the full suite only at its cached baseline and the declared affected-test command everywhere else | `.agents/skills/build/SKILL.md`, `AGENTS.md`, `tests/test-doc-conventions.sh` | 1, 2 | 4, 7 | `bash tests/test-doc-conventions.sh` | 3 files · 3 systems · 2 ACs |
| 4 | Wrap-up and pipelines use the cache | `/wrap-up-session`, `/yolo` and `/auto-push` run full suites through the cache; `/build` and `/wrap-up-session` forbid concurrent test runs and poll loops | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/yolo/SKILL.md`, `.agents/skills/auto-push/SKILL.md`, `.agents/skills/build/SKILL.md`, `tests/test-doc-conventions.sh` | 3 | 5, 6, 8 | `bash tests/test-doc-conventions.sh && gh run list --workflow tests.yml --status success --limit 10` | 5 files · 5 systems · 3 ACs |

Build prompt:

```
Invoke `/build` for `specs/fewer-full-suite-runs.md`.
Plan: `## Plan: fewer-full-suite-runs` in `tasks/todo.md`, 4 slices, ready set 1, 2.
Files: .agents/skills/build/scripts/cached-suite.sh, .agents/skills/build/SKILL.md, .agents/skills/wrap-up-session/SKILL.md, .agents/skills/yolo/SKILL.md, .agents/skills/auto-push/SKILL.md, AGENTS.md, tests/run.sh, tests/affected.sh, tests/test-cached-suite.sh, tests/test-affected.sh, tests/test-run-sh.sh, tests/test-doc-conventions.sh.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/fewer-full-suite-runs.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: `cached-suite.sh` wraps any command and knows nothing about `tests/run.sh` (Decision 5).
Constraints: the cache key is the working tree through a temporary index, never a clean `HEAD^{tree}` (Decision 7).
Constraints: `tests.yml` is not edited (Decision 9).
```
