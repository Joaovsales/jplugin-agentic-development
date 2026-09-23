---
implementation_paths:
  - .agents/skills/quality-gate/scripts/receipt.py
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/wrap-up-session/scripts/closure.py
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/wrap-up-session/references/routines.md
  - tests/test-quality-receipt.sh
  - tests/test-closure.sh
  - tests/fixtures/closure/scenarios.json
  - tests/test-review-context.sh
  - tests/test-model-tiers.sh
  - tests/test-living-spec-reconciliation.sh
  - tests/test-routine-wrapup.sh
  - tests/test-routine-step-ledger.sh
  - tests/test-doc-conventions.sh
  - AGENTS.md
---

# Spec: Wrap-up reuses the quality receipt and closes the PR loop

> Origin: [#163](https://github.com/Joaovsales/jplugin-agentic-development/issues/163), with the minimal slice of
> [#162](https://github.com/Joaovsales/jplugin-agentic-development/issues/162) it consumes (receipt schema, `/quality-gate` emits it).
> #162's risk-fact extractor, bounded classifier and review profiles are out of scope; #162 stays open.
> Seam with [#178](https://github.com/Joaovsales/jplugin-agentic-development/issues/178) (merged as `3525c70`): see Decision 6.
> Designed 2026-09-23 · Review status: **draft, critic pass applied**. A dispatched `critic` reported 8 MUST-FIX, 11 SHOULD-FIX and 5 NITPICK. All 24 were applied as spec edits and none were declined. Decisions C1–C12 record the ones that change the design, and C1, C5 and C6 refine rows you settled (8, 7 and 12), so they are flagged for your confirmation.
> Visual: specs/quality-receipt-closure.plan.html

## Problem

Every build session pays for review twice. `/quality-gate` reviews the diff, then
`/wrap-up-session` sends three `code-reviewer` passes and a `critic` over the same diff
(`.agents/skills/wrap-up-session/SKILL.md:352-465`, `:895-922`), plus an inline
`/security-scan` (`:323-326`). Over 2026-09-21 → 09-23 that came to 18 reviewer
sub-agents and 2.94M tokens (median 157k tokens and 7.4 min each). Wrap-up reviewer
batches took 9–25 min of wall time, and Step 6's full suite waited on the slowest reviewer
(23 min once). After this change there is exactly one review pass per diff, and
`/quality-gate` owns it. The gate records the pass as a receipt bound to the diff.
Wrap-up checks the receipt and re-enters the gate only for a diff the receipt does not
cover. Wrap-up then runs the closure loop: commit, push, PR, mergeability, CI, bounded
repair, deployment, and an honest closure record. Out of scope: risk-scaled review
depth (#162) and the two slow test files (#179).

**Current state** — every path below was read.

```text
 /build Phase 3 (build/SKILL.md:375-381)
   │ invokes /quality-gate on base..working-tree (committed slices + uncommitted tail)
   ▼
 /quality-gate (quality-gate/SKILL.md)           Phase 1 simplify · Phase 2 deslop · Phase 3 APOSD
   │ prints a text report (:229-252)             (dispatched software-design-expert-review)
   │ persists NOTHING a later step can read
   ▼
 /build Phase 3.3 re-runs affected tests         (through cached-suite.sh, #178)
   ▼
 /wrap-up-session
   Step 1-3.3  learnings, todo, bugs, spec reconciliation (edits tasks/**, specs/**)
   Step 3.5    /security-scan inline            ◄── second review of the same diff
   Step 4      4 dispatched reviewers           ◄── third review (code-reviewer ×3 + critic)
   Step 5      apply gate, reconciliation table, recheck loop
   Step 6      full suite via cached-suite.sh   (waits for Step 4 to return)
   Step 7      commit, push, open/re-sync PR    ── ends here: no CI watch, no conflict check
   Step 8      /verify-evidence --scope deployment (pushes its own fix commits)
   Step 8.5    unattended PR assertion
```

Facts the design rests on:

- `/build` gives no commit instruction (its only commit mentions are `build/SKILL.md:242`,
  the checkpoint flush, and the `Commits this build:` report line), yet in practice build
  sessions commit per slice (for example, #178's handovers, "landed cddf272..5362005").
  The gate therefore reviews committed slices plus an uncommitted tail, and wrap-up commits
  the rest in Step 7. The fingerprint has to be commit-independent.
- `/build` records its base as `git rev-parse HEAD` at pre-flight (`build/SKILL.md:83`),
  while wrap-up detects `main`/`master`/`develop` (`wrap-up-session/SKILL.md:42-52`). The
  two callers do not agree on a base today.
- `.agents/git-hooks/pre-push:95-106` counts a pushed code commit as covered only when it
  falls inside a `## Session Summary … [a..b]` range, or itself adds a `## Session Summary`
  line (`introduces_summary`, `:73-76`).
- `tests/test-routine-wrapup.sh:124-131` reads Step 8.5's exit table and requires every step
  it names to route through Step 8.5. `tests/test-routine-step-ledger.sh:28-35` cuts
  wrap-up by the `## Step 2` and `### The Pull Request … ### Push Failure` headings.
- `AGENTS.md:23` (managed block) describes Layer 3 as "consistency, defensive audit,
  coverage, adversarial critic".
- Wrap-up edits `tasks/**` (Steps 1–3) and `specs/**` (Step 3.2) *after* the gate has run.
- `.agents/git-hooks/pre-push:62` already classes `tasks/*` as non-code.
- `cached-suite.sh` keys a green run on the working-tree object plus the command
  (`build/scripts/cached-suite.sh:58-69`). It already makes Step 6 free on a tree that was
  proved green.
- `master` has no branch protection (`gh api …/branches/master/protection` → 404), so this
  repository has **no required checks**.
- No skill watches CI today: `gh pr checks` and `gh run` appear nowhere under `.agents/`.
- `/security-scan` is an inline checklist and dispatches no agent (`security-scan/SKILL.md`).
- Tests that pin wrap-up's reviewer dispatch: `tests/test-review-context.sh:22-137` (two
  dispatch sites) and `tests/test-model-tiers.sh:173-182` (critic's planner floor at the
  dispatch). Tests that pin its heading order: `tests/test-living-spec-reconciliation.sh:845-866`
  (`## Step 3.5`, `## Step 4`) and `tests/test-skill-invocation-chain.sh:108`
  (`Step 4 .*Quality Gate|Code Review`).

## Constraints

| Constraint | Value | Source | Detected by |
|------------|-------|--------|-------------|
| Review passes per diff | Exactly one: `/quality-gate`'s. Wrap-up dispatches no `code-reviewer`, `critic`, `security-reviewer` or `software-design-expert-review`, and runs no `/security-scan` | issue #163 AC2, user | `tests/test-review-context.sh` asserts wrap-up is not a dispatch site; `tests/test-doc-conventions.sh` asserts no reviewer persona or `/security-scan` in wrap-up |
| Receipt reuse | Only a receipt whose fingerprint, policy and chain all match the current tree, and whose verdict is GO (or HOLD with a recorded approval) | issue #163 AC1 | `tests/test-quality-receipt.sh` staleness cases |
| Verdict integrity | The verdict is computed from findings by `receipt.py`, never supplied by the caller | user (Q4) | `tests/test-quality-receipt.sh`: outcome with an unresolved MUST-FIX yields STOP whatever else it says |
| Bookkeeping does not invalidate | Edits under `tasks/**` leave the fingerprint unchanged | user (Q2) | `tests/test-quality-receipt.sh` |
| Commit does not invalidate | The same tree gives the same fingerprint uncommitted and committed | inferred: build sessions leave an uncommitted tail | `tests/test-quality-receipt.sh` |
| One pre-push full suite (#178) | Step 6 still runs the full suite through `cached-suite.sh`. The receipt's test record never skips it | user (Q6) | `tests/test-doc-conventions.sh` fewer-full-runs needles stay green |
| Bounded closure | ≤ 2 CI repair rounds, ≤ 1 conflict repair round, ≤ 30 min per CI watch, ≤ 1 deployment re-entry, ≤ 1 gate run per tree. Every cycle in the transition table consumes one of these counters, so no global step budget is needed | user (Q8), critic C1 | `tests/test-closure.sh` bound cases, plus a cycle check that walks the table and fails on any cycle with no counter |
| Every run terminates | Every accepted (phase, observation) pair has exactly one row, and each terminal is reached with the PR drafted whenever one is open | critic C3 | `tests/test-closure.sh` enumerates the accepted set and asserts one row each |
| No history rewrite | Conflict and non-fast-forward repair merge; nothing force-pushes | user (Q9) | `tests/test-doc-conventions.sh`: wrap-up has no `--force`, no `rebase` |
| Hooks enabled | Commits never pass `--no-verify` | issue #163 AC3, AGENTS.md | `tests/test-doc-conventions.sh` |
| No polling (#178) | CI watch runs as a background task and completes on its notification | #178 | `tests/test-doc-conventions.sh` |
| Honest closure | Nothing is recorded as passed before its evidence exists; a run that did not finish ends `Closure: partial — <state>` with the PR as a draft | issue #163 AC7, user (Q7) | `tests/test-closure.sh` partial cases |
| Provider coupling | Wrap-up uses `gh pr` / `gh run` only; task state goes through `/task-registry` | `tests/test-doc-conventions.sh:622-630` | existing guard |
| Engine files outside the tree | The closure state file and the gate's outcome JSON live under `$(git rev-parse --git-common-dir)/`, never in the worktree, so writing them cannot change the fingerprint | critic C9 | `tests/test-quality-receipt.sh`: fingerprint unchanged across a `closure.py step` |
| Repair pushes stay covered | Every repair commit adds a `## Session Summary … — closure repair <n>` line, so `pre-push` counts it covered and writes no `tasks/wrap-up-debt.md` entry | critic C5 | `tests/test-doc-conventions.sh` |
| Rollout / rollback | Documentation plus two scripts, and no persisted data outside `$(git rev-parse --git-common-dir)/quality-receipts/` and `…/closure/`. Rollback is a revert, and a stale store is ignored because every read re-validates | inferred | revert leaves the suite green |

## System design

### Ownership

| Component | Owns (source of truth for) | Reads |
|-----------|----------------------------|-------|
| `receipt.py` (NEW) | fingerprint algorithm, policy version, verdict rule, receipt schema, receipt store, staleness verdict | the working tree, the merge-base, the three policy files |
| `/quality-gate` | which reviewers run and what they found; the gate's affected-test run | `receipt.py check` (to learn the delta and parent on re-entry) |
| `cached-suite.sh` (#178, unchanged) | "this command was green on tree X" | — |
| `closure.py` (NEW) | closure state, transition rules, repair counters, bounds | observations the skill reports |
| `/wrap-up-session` | performing the actions `closure.py` names, and the PR body | `receipt.py check`, `closure.py` actions |
| GitHub | PR state, check results, mergeability | — |
| `/debug`, `/verify-evidence --scope deployment` | diagnosing a failed check; deployment outcome | — |

### Interaction

```text
 /build Phase 3 ──(1) sync──► /quality-gate ── phases 1-4 ──(2) sync──► receipt.py write ──► store/<fp>.json
                                                                                          └─► store/branch-<b>.json (latest pointer)
 /wrap-up-session  Steps 0–3.7 (learnings, registers, specs, map, ledger) run first and are not in the loop.
   From Step 4 on, closure.py drives: every later step is an action it names, run once per naming.
   ──(5) loop──► closure.py step --state <common-dir>/closure/<branch>.json --observe <json>
                              │ prints: action <name> [args] | terminal <outcome>
   check-receipt ──(3) sync──► receipt.py check            (Step 4 describes this action)
   quality-gate  ──(4) sync──► /quality-gate [--scope <delta> --parent <fp>]   (Step 4)
   run-suite     ── full suite through cached-suite.sh, #178                   (Step 6)
                              ▼
            wrap-up performs the action:  commit · push · pr-sync · mergeability ──(6) gh pr view
                                          watch-ci ──(7) async── gh pr checks --watch (background)
                                          debug-ci ── /debug   merge-base ── git merge origin/<base>
                                          verify-deploy ── /verify-evidence --scope deployment
                                          re-gate ── back to Step 4 (receipt check)   mark-draft ── gh pr ready --undo
```

| Arrow | Mode | On timeout | On duplicate |
|-------|------|------------|--------------|
| (1) gate run | sync | n/a (in-session skill); a hung Phase 3 agent follows `subagent-resilience.md` | a second run on the same tree overwrites the same `<fp>.json` with its own result |
| (2) `receipt.py write` | sync, local | n/a | idempotent: same inputs → byte-identical file apart from `written_at` |
| (3) `receipt.py check` | sync, local, read-only | n/a | pure: same tree and store → same answer |
| (4) gate re-entry | sync | as (1) | the delta is recomputed from the store, so a repeat reviews the same delta |
| (5) `closure.py step` | sync, local | n/a | not idempotent by design: each call consumes one observation. The state file carries the counters, and replaying a state file is how the fixtures test it |
| (6) mergeability | sync, network | `gh` failure → observation `mergeable: unknown`; re-queried ≤ 3 times inside the action, then `unknown` → partial | read-only |
| (7) CI watch | async (background task, completion notification) | 30 min → observation `ci: timeout` → partial, state `ci-pending`. Checks not registered yet: the action gives the push a 2-min registration window, and reports `ci: none` only when that window saw no checks **and** no `.github/workflows/*` file triggers on `pull_request`. Otherwise it reports `ci: timeout` | re-watching a finished run returns the same result |

### Failure unit

A broken `receipt.py` or a store it cannot read makes `check` report `stale missing`, so
wrap-up runs the gate once. The failure costs one review, never a skipped one. A broken
`closure.py` stops wrap-up after the push. The commit and PR still exist, and the Done report
says `Closure: partial — closure engine failed`. GitHub being unreachable leaves the PR
unsynced and the run partial, and loses no work.

`write` makes two writes: the receipt, then the branch pointer. It writes them in that
order, each through a temp file and a rename. A crash between the two leaves the pointer
naming an older receipt. The next delta is then computed from that older tree, so it is
larger than needed but still covers everything, and nothing goes unreviewed.

## Component contracts

### `receipt.py fingerprint`

```bash
python3 .agents/skills/quality-gate/scripts/receipt.py fingerprint [--base <ref>]
# stdout: <merge-base-sha> <tree-sha> <fingerprint>
```

| Aspect | Contract |
|--------|----------|
| Inputs | `--base`: optional. Omitted, `receipt.py` resolves it itself as the first ref that exists among `origin/main`, `origin/master`, `origin/develop`, `main`, `master`, `develop`. Merge-base = `git merge-base HEAD <ref>`. **Every caller omits it**, so `/build` and wrap-up agree on one base (critic C4) |
| Algorithm | Tree = `git write-tree` over a temporary index after `git -c core.safecrlf=false add -A` (tracked + untracked, not ignored), as `cached-suite.sh` does. Fingerprint = sha256 of `git -c core.quotepath=false diff --binary --full-index --no-ext-diff --no-textconv --no-renames --no-color --src-prefix=a/ --dst-prefix=b/ <merge-base> <tree> -- . ':(exclude)tasks/**'`, so no user diff config can change it |
| Outcomes | exit 0 with the line above |
| Raises | exit 2 `receipt: <reason>` when the tree cannot be hashed or there is no merge-base |
| Idempotency | pure |

### `receipt.py write`

```bash
python3 .agents/skills/quality-gate/scripts/receipt.py write --outcome <common-dir>/quality-receipts/outcome.json [--parent <fingerprint>]
# stdout: receipt: written <fp8> verdict <GO|HOLD|STOP> policy <qg1-xxxxxxxx>
```

| Aspect | Contract |
|--------|----------|
| Inputs | outcome JSON (schema below): `reviewers`, `unresolved`, `tests`, `design_verdict`, `scope`. `--parent` only when `scope` is a path list. The outcome file is written under the git common dir, never in the worktree (critic C9) |
| Outcomes | exit 0, receipt stored at `<common-dir>/quality-receipts/<fingerprint>.json`, branch pointer `branch-<sanitized branch>.json` updated (`{fingerprint, tree, base}`) |
| Raises | exit 2 `receipt: invalid outcome — <field>: <why>` and nothing written, when the outcome fails the schema, `--parent` names no stored receipt, or `tests.tree` differs from the tree `write` computes (test evidence from another tree, critic C8) |
| Idempotency | same tree + same outcome → same file content except `written_at`; written via temp file + rename |
| Versioning | `schema: "quality-receipt/1"`. A reader that meets any other schema reports `stale schema` |

### `receipt.py check`

```bash
python3 .agents/skills/quality-gate/scripts/receipt.py check [--base <ref>]
# exit 0 — receipt: valid <GO|HOLD-approved> <fp8> policy <v>
# exit 3 — receipt: stale <reason>  [parent <fp>]  [delta <path> ...]
```

| Aspect | Contract |
|--------|----------|
| Reasons (exit 3) | `missing` (no receipt for this fingerprint and no branch pointer) · `diff-changed` (no receipt for this fingerprint, but the branch pointer names one; prints `parent <fp>` and `delta`) · `policy-changed` · `schema` · `verdict <HOLD|STOP>` · `parent-invalid <fp>` (a chain link is missing, has another policy or schema, or is neither GO nor approved HOLD, critic C2) |
| Delta | the paths that differ between the pointer's tree and the current tree (`git diff --name-only <pointer tree> <current tree> -- . ':(exclude)tasks/**'`), **intersected with** the paths of the current `<merge-base>..<tree>` diff. After a base merge this drops the files that only the base branch changed, so the gate never reviews other people's merged code (critic C10). A file the branch touches that the merge changed stays in. A file of ours the delta leaves out was reviewed by the chain, and its content is unchanged since |
| A `parent` with a failed chain | `diff-changed` is printed only when the pointer's receipt is itself valid. Otherwise the reason is `missing`, so the re-entry is a full-scope gate run |
| Raises | exit 2 as `fingerprint` |
| Idempotency | read-only, pure |

### `receipt.py approve`

```bash
python3 .agents/skills/quality-gate/scripts/receipt.py approve --fingerprint <fp> --by <name>
```

Sets `hold_approved_by` on a HOLD receipt; exit 0. Refuses a GO or STOP receipt with exit 2 `receipt: only HOLD can be approved`. Idempotent. **Only a human answer in an interactive session calls it**: wrap-up Step 4 asks, and runs `approve --by "<git config user.name>"` on a yes. An unattended run (a routine branch, or a caller declaring Step 8.5 unattended) never calls it, and a HOLD then stops. The script cannot tell a human from an agent, so the rule lives in the skill and is pinned by a doc needle (critic C11).

### `/quality-gate` (changed public contract)

```text
/quality-gate [--scope <path> ...] [--parent <fingerprint>]
```

| Aspect | Contract |
|--------|----------|
| Phases | 1 simplify · 2 deslop · **3 security**: the `/security-scan` checklist, run inline over **the gate's own file list** (untracked files included, `--scope` honoured), not the skill's `git diff --name-only`. Its MUST-FIX fixes are applied under the Apply Gate · **4 APOSD**: dispatched `software-design-expert-review`, unchanged, and now after every edit phase, so it reviews the security fixes too · **5 tests**: the `Affected tests:` command through `cached-suite.sh` (or the covering test files when none is declared), run after every fix and recorded as `tests` · **6 receipt**: `receipt.py write`. No phase after 4 edits the tree. A phase-5 failure is a red `tests` record, never a silent fix (critic C7) |
| Outcomes | report as today plus the line `Receipt: <verdict> <fp8> policy <v> [parent <fp8>]` |
| On a `receipt.py write` refusal | the gate reports `Receipt: none — <stderr>`, and the caller treats that as a stale receipt. It is never reported as GO |
| Callers | `/build` Phase 3 (full scope, unchanged call) and `/wrap-up-session` Step 4 (delta scope on `diff-changed`, full scope on every other reason) |

### `closure.py step`

```bash
python3 .agents/skills/wrap-up-session/scripts/closure.py step --state <state.json> --observe '<json>'
# stdout: action <name> [key=value ...]   |   terminal <complete|partial|stopped> state=<phase> reason=<text>
```

| Aspect | Contract |
|--------|----------|
| Inputs | `--state`: `<git-common-dir>/closure/<sanitized branch>.json`, created with `{"phase":"receipt","pr_open":false,"gated":false,"ci_rounds":0,"conflict_rounds":0,"deploy_reentries":0}` when absent. `--observe`: the result of the last action, e.g. `{"receipt":"stale","scope":"delta"}`, `{"ci":"fail","checks":["tests"]}` |
| Outcomes | writes the new state and prints exactly one line. Actions: `check-receipt`, `quality-gate`, `run-suite`, `commit-push`, `pr-sync`, `mergeability`, `merge-base`, `watch-ci`, `debug-ci`, `verify-deploy`, `record-closure`, `mark-draft` |
| Raises | exit 2 `closure: observation <x> not valid in phase <p>` for an observation the phase does not accept. The state file is left unchanged. The accepted set per phase is exactly the observation column of § Transitions, and each accepted pair has exactly one row |
| Bounds | enforced from the counters in the state file (Constraints row *Bounded closure*). A bound reached turns the next repair into `mark-draft` → `terminal partial`. There is no global step budget (critic C1): every cycle consumes a counter |
| Terminals | `stopped` is printed only while `pr_open` is false. Once a PR exists, every non-`complete` end goes through `mark-draft` and ends `terminal partial` (critic C6). `partial` accepts `drafted`, `draft-failed` and `no-pr`, all → `terminal partial`, the last two carrying `draft=<failed\|none>` so the Done report can say the PR was not drafted |
| Idempotency | none (see arrow 5); deterministic given the state and the observation |

## Data models

### Entity — quality receipt (`quality-receipt/1`)

| Field | Type | Invariant | Enforced by |
|-------|------|-----------|-------------|
| `schema` | const `"quality-receipt/1"` | exact | `write` sets it; `check` refuses any other value |
| `fingerprint` | 64-hex | equals the file name; sha256 of the tasks-excluded diff | `write` computes it and never accepts it as input |
| `base` | 40-hex | the merge-base at write time | computed |
| `head` | 40-hex | `HEAD` at write time; provenance only, not a validity key (the fingerprint subsumes it and survives the Step 7 commit) | computed |
| `tree` | 40-hex | the working-tree object that was reviewed | computed |
| `policy` | `qg1-<8 hex>` | sha256 of every file that decides a verdict: `receipt.py` itself (the verdict rule), `quality-gate/SKILL.md`, `security-scan/SKILL.md`, `software-design-expert-review/SKILL.md`, `.agents/agents/software-design-expert-review.md`, `references/finding-model.md` and `references/review-dispatch-contract.md`. All are resolved relative to `receipt.py`, and a missing one is hashed as its path plus `<missing>` (critic C12) | computed |
| `scope` | `"full"` or a non-empty path list | a path list requires `parent` | schema check in `write` |
| `parent` | null or 64-hex | non-null iff `scope` is a list; names a stored receipt | schema check + store lookup |
| `reviewers` | list of `{phase, lens, dispatch: "dispatched"\|"inline", verdict?}` | non-empty; phases 1–4 each present | schema check |
| `tests` | `{command, exit, tree}` | `tree` is the tree the tests ran on, and equals the receipt's `tree` | `write` refuses a mismatch (exit 2) |
| `unresolved` | list of four-axis findings `{severity, confidence, autofix_class, owner, location, summary}` | every field in its enum | schema check |
| `design_verdict` | `GO`\|`HOLD`\|`STOP` | Phase 3's own verdict | schema check |
| `verdict` | `GO`\|`HOLD`\|`STOP` | derived, never input: STOP if any `unresolved` is MUST-FIX or `design_verdict` is STOP or `tests.exit ≠ 0`; else HOLD if more than 3 SHOULD-FIX are unresolved or `design_verdict` is HOLD; else GO. On a delta receipt the SHOULD-FIX count includes the chain's unresolved SHOULD-FIX back to the nearest approved HOLD, whose findings the human accepted. Three per link can therefore never pile up unnoticed (critic, NITPICK on the per-receipt threshold) | `write` computes it and ignores any `verdict` key in the outcome |
| `hold_approved_by` | null or string | non-null only when `verdict` is HOLD | `approve` refuses other verdicts |
| `written_at` | UTC ISO-8601 `Z` | — | computed |

### Illegal states

| Illegal combination | Made unrepresentable by |
|---------------------|-------------------------|
| `verdict = GO` with an unresolved MUST-FIX | verdict derived in `write`; input `verdict` ignored |
| `verdict = GO` with red tests | same derivation (`tests.exit ≠ 0` → STOP) |
| approval on a GO or STOP receipt | `approve` refuses |
| delta receipt with no parent, or a full receipt with one | schema check in `write` |
| receipt reused whose parent chain has a stale link | `check` walks the chain; any bad link → `parent-invalid` |
| receipt reused after the gate's rules changed | `policy` recomputed on every `check` |
| closure `complete` with CI red or unknown | `closure.py` reaches `record-closure` only from `ci: pass` or a registration-checked `ci: none` |
| a push by wrap-up of a tree with no valid receipt | `closure.py` reaches `commit-push` only after `receipt: valid` and `suite: green` |
| a repair beyond its bound | counters in the state; the bound turns the repair into `mark-draft` |
| a second gate run on an unchanged tree | the `gated` flag: `receipt: stale` while `gated` is true → the run ends (the gate ran but wrote no matching receipt). A tree-changing repair resets `gated` |
| a `stopped` run that leaves a ready PR behind | `stopped` only while `pr_open` is false; afterwards the same causes route to `mark-draft` |
| an open PR whose closure outcome is unrecorded | every terminal after `pr` prints the state the Done report's `Closure:` line quotes |

**Accepted exception (critic C6b, Decision 12).** `/verify-evidence --scope deployment` pushes
its own fix commits outside `closure.py`, so for the length of one deployment fix the remote
holds a tree no receipt covers. The exception is bounded: at most one re-entry, and the
very next action is `check-receipt` on that tree, which gates the delta before anything
else happens. If that re-entry is already used, the run ends partial with the PR drafted.
It is listed here because the illegal-states table above does not forbid it.

### Transitions — closure `phase`

"→ end(*r*)" means: while `pr_open` is false, `terminal stopped reason=r`; once a PR is
open, `partial` (`mark-draft`) with reason *r*. Counters and flags are in the state file.
A tree-changing return to `receipt` (from `merge`, `repair` or `deploy`) resets `gated`.

| From | Observation | To (action printed) |
|------|-------------|---------------------|
| `receipt` | `receipt: valid` | `suite` (`run-suite`) |
| `receipt` | `receipt: stale`, `scope: delta\|full`, `gated` false | `gate` (`quality-gate scope=…`); `gated` ← true |
| `receipt` | `receipt: stale`, `gated` true | → end(`receipt not written after gate`) |
| `gate` | `gate: GO` or `gate: HOLD-approved` | `receipt` (`check-receipt`), which confirms the new receipt |
| `gate` | `gate: HOLD` (not approved), `gate: STOP` or `gate: none` | → end(`review <verdict>`) |
| `suite` | `suite: green` | `push` (`commit-push`) |
| `suite` | `suite: red` (after Step 6's own 2 fix attempts) | → end(`tests`) |
| `suite` | `suite: blocked` (another session's suite holds the lock) | → end(`suite lock held`) |
| `push` | `push: ok` | `pr` (`pr-sync`) |
| `push` | `push: non-ff`, conflict rounds left | `merge` (`merge-base ref=origin/<branch>`) |
| `push` | `push: non-ff`, no conflict rounds left | → end(`push non-fast-forward`) |
| `push` | `push: denied` | → end(`push denied`) |
| `pr` | `pr: <n>` | `mergeable` (`mergeability`); `pr_open` ← true |
| `pr` | `pr: failed` (gh unreachable, linkage refused) | → end(`pr-sync failed`) |
| `mergeable` | `mergeable: clean` | `ci` (`watch-ci`) |
| `mergeable` | `mergeable: conflicting`, conflict rounds left | `merge` (`merge-base ref=origin/<base>`) |
| `mergeable` | `mergeable: conflicting`, no conflict rounds left | `partial` (`mark-draft`) |
| `mergeable` | `mergeable: unknown` (after the action's 3 re-queries) | `partial` (`mark-draft`) |
| `merge` | `merge: resolved` | `receipt` (`check-receipt`); `conflict_rounds` +1 |
| `merge` | `merge: unresolved` (merge aborted) | → end(`merge unresolved`) |
| `ci` | `ci: pass` or `ci: none` (registration-checked, arrow 7) | `deploy` (`verify-deploy`) |
| `ci` | `ci: fail`, CI rounds left | `repair` (`debug-ci checks=…`) |
| `ci` | `ci: fail`, no CI rounds left | `partial` (`mark-draft`) |
| `ci` | `ci: timeout` | `partial` (`mark-draft`), state `ci-pending` (in doubt: the run may still pass) |
| `repair` | `debug: fixed` | `receipt` (`check-receipt`); `ci_rounds` +1 |
| `repair` | `debug: not-fixed` | `partial` (`mark-draft`) |
| `deploy` | `deploy: pass`, `head-moved: false` | `record` (`record-closure`) |
| `deploy` | `deploy: pass`, `head-moved: true`, re-entry unused | `receipt` (`check-receipt`); `deploy_reentries` +1 |
| `deploy` | `deploy: pass`, `head-moved: true`, re-entry used | `partial` (`mark-draft`) |
| `deploy` | `deploy: n/a` | `record` (`record-closure`), which records `not applicable — <reason>` |
| `deploy` | `deploy: fail` | `partial` (`mark-draft`) |
| `record` | `recorded` | terminal `complete` |
| `record` | `record-failed` | `partial` (`mark-draft`) |
| `partial` | `drafted`, `draft-failed` or `no-pr` | terminal `partial` reason=`<cause>` draft=`<yes\|failed\|none>` |

Cycles, each consuming one counter: `receipt → gate → receipt` (`gated`),
`merge → receipt → … → push/mergeable → merge` (`conflict_rounds`),
`ci → repair → receipt → … → ci` (`ci_rounds`), `deploy → receipt → … → deploy`
(`deploy_reentries`). The longest legal run is the initial pass plus 2 CI rounds, 1
conflict round and 1 deployment re-entry. `tests/test-closure.sh` walks the table and
fails on any cycle that does not consume a counter.

### Migration and compatibility

The store is new and lives outside the tree, so there is nothing to migrate. A session on an
older plugin copy writes no receipt, and wrap-up then sees `stale missing` and runs the gate
once. That matches today's cost, less the four extra reviewers. A receipt with another
`schema` is `stale schema` and is never read as valid.

## Build Order

Sizing: 6 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 4 (7 files, 7 systems) and slice 5 (4 files, 4 systems). Removing wrap-up's dispatch sites and rewriting Step 7 break existing tests that pin wrap-up's headings and sites, and those tests must move in the same slice so the suite stays green. Every system past the first is a `tests/` file, plus the one-line `AGENTS.md` taxonomy fix.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Quality receipt script | `receipt.py` fingerprints the tasks-excluded diff and writes, checks and approves `quality-receipt/1` receipts (the #162 schema contract) | `.agents/skills/quality-gate/scripts/receipt.py`, `tests/test-quality-receipt.sh` | — | 1, 2, 3 | `bash tests/test-quality-receipt.sh` | 2 files · 2 systems · 3 ACs |
| 2 | Gate emits the receipt | `/quality-gate` runs security as phase 3 (before APOSD) and tests as phase 5, takes `--parent`, and writes the receipt as phase 6 | `.agents/skills/quality-gate/SKILL.md`, `tests/test-doc-conventions.sh` | 1 | 4 | `bash tests/test-doc-conventions.sh` | 2 files · 2 systems · 1 AC |
| 3 | Closure engine | `closure.py step` implements the transition table and bounds, and replays the seven AC-6 scenarios from fixtures | `.agents/skills/wrap-up-session/scripts/closure.py`, `tests/test-closure.sh`, `tests/fixtures/closure/scenarios.json` | — | 5, 6 | `bash tests/test-closure.sh` | 3 files · 2 systems · 2 ACs |
| 4 | Wrap-up reuses the receipt | Wrap-up Step 4 checks the receipt and re-enters the gate once on a miss; Steps 3.5, 5 and the reviewer dispatch are gone; Step 8.5's exit table and `AGENTS.md` Layer 3 follow | `.agents/skills/wrap-up-session/SKILL.md`, `AGENTS.md`, `tests/test-review-context.sh`, `tests/test-model-tiers.sh`, `tests/test-living-spec-reconciliation.sh`, `tests/test-routine-wrapup.sh`, `tests/test-doc-conventions.sh` | 2 | 7, 8 | `bash tests/test-review-context.sh && bash tests/test-model-tiers.sh && bash tests/test-living-spec-reconciliation.sh && bash tests/test-routine-wrapup.sh && bash tests/test-skill-invocation-chain.sh && bash tests/test-doc-conventions.sh` | 7 files · 7 systems · 2 ACs |
| 5 | Closure loop: PR, CI, conflicts | Wrap-up drives `closure.py` from Step 4 on, through commit, push, PR, mergeability, CI watch and bounded CI and conflict repair | `.agents/skills/wrap-up-session/SKILL.md`, `tests/test-routine-wrapup.sh`, `tests/test-routine-step-ledger.sh`, `tests/test-doc-conventions.sh` | 3, 4 | 9, 10, 11 | `bash tests/test-routine-wrapup.sh && bash tests/test-routine-step-ledger.sh && bash tests/test-doc-conventions.sh` | 4 files · 4 systems · 3 ACs |
| 6 | Closure loop: deploy, record, partial | Wrap-up verifies deployment or records it as not applicable, writes the closure record, and drafts a partial PR; the routine contract names the receipt | `.agents/skills/wrap-up-session/SKILL.md`, `.agents/skills/wrap-up-session/references/routines.md`, `tests/test-doc-conventions.sh` | 5 | 12, 13 | `bash tests/test-doc-conventions.sh` | 3 files · 2 systems · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/quality-receipt-closure.md`.
Plan: `## Plan: quality-receipt-closure` in `tasks/todo.md`, 6 slices, ready set 1, 3.
Files: .agents/skills/quality-gate/scripts/receipt.py, .agents/skills/quality-gate/SKILL.md, .agents/skills/wrap-up-session/scripts/closure.py, .agents/skills/wrap-up-session/SKILL.md, .agents/skills/wrap-up-session/references/routines.md, tests/test-quality-receipt.sh, tests/test-closure.sh, tests/fixtures/closure/scenarios.json, tests/test-review-context.sh, tests/test-model-tiers.sh, tests/test-living-spec-reconciliation.sh, tests/test-routine-wrapup.sh, tests/test-routine-step-ledger.sh, tests/test-doc-conventions.sh, AGENTS.md.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/quality-receipt-closure.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions. An `open` row is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: the verdict is computed by `receipt.py` from findings, never accepted as input (Decision 4).
Constraints: the fingerprint excludes `tasks/**` only; `specs/**` stays in it (Decision 2).
Constraints: every caller omits `--base`; `receipt.py` resolves it (Decision C4).
Constraints: no global step budget; every cycle in the closure table consumes a counter (Decision C1).
Constraints: Step 6 still runs the full suite through `cached-suite.sh`; the receipt's test record never skips it (Decision 6).
Constraints: repair merges, never rebases or force-pushes (Decision 9).
Constraints: #162's risk-fact extractor, classifier and review profiles are not built (Decision 14).
Constraints: the PR body carries `Closes #163` and `Refs #162`, never `Closes #162`.
```

## Decisions

| # | Decision | Options | Recommended / chosen | Source | Wrong when |
|---|----------|---------|----------------------|--------|------------|
| 1 | Receipt storage | A) `<git-common-dir>/quality-receipts/` · B) committed `tasks/receipts/` · C) PR comment | A. Wrap-up quotes `Quality receipt: <verdict> · <fp8> · policy <v>` in the PR body. No signing: the threat is staleness, not forgery, and the fingerprint is the content address | user (Q1) | a receipt must survive to another machine (for example, a cloud wrap-up of a local build) |
| 2 | Fingerprint scope | A) whole diff · B) exclude `tasks/**` · C) exclude `tasks/**` and `specs/**` | B, the same class as `pre-push` `touches_code`. Spec edits from Step 3.2 stay reviewable | user (Q2) | C is right if spec reconciliation stops being a contract change |
| 3 | Re-entry scope | A) full diff again · B) delta since the branch's latest receipt, `--scope` + `parent` chain | B. A two-line CI fix gets a two-line review | user (Q3) | the delta interacts with unchanged code the reviewer does not see (accepted: Phase 3 reads whole changed files, not hunks) |
| 4 | Verdict rule and HOLD | computed from findings; HOLD → A) interactive approval recorded / unattended stop · B) always stop | A, via `receipt.py approve` | user (Q4) | — |
| 5 | Policy version | A) hand-bumped constant · B) content hash of the three policy files, script-relative | B, `qg1-<sha8>`. Without it, a receipt minted under old rules (for example, before this change moved `/security-scan` into the gate) stays valid under new ones, and the installed plugin copy and the project copy can differ | user (Q5) | a typo fix in `finding-model.md` invalidates live receipts, costing one gate run. Accepted |
| 6 | #178 seam: does the receipt's test record skip Step 6? | A) yes · B) no; `cached-suite.sh` stays the sole owner of "green on tree X" | B. The receipt records test **evidence** (`{command, exit, tree}`, an affected-test run). `cached-suite.sh` decides **reuse**, and Step 6 is free on a tree already proved green. Removing Step 4's reviewers is what lets Step 6 start without waiting | user (Q6) | the gate starts running the full suite itself, and then cached-suite already reuses it with no receipt logic needed |
| 7 | Where closure outcomes are recorded | A) a final `tasks/`-only commit + one more CI cycle · B) pre-push registers record only pre-push facts; CI, conflict and deploy outcomes go in the PR body's `## Closure` and the Done report | B | user (Q7) | the project needs closure outcomes in `tasks/history.md` for later sessions to read |
| 8 | Loop bounds | 2 CI rounds · 1 conflict round · 30 min per watch · all checks when none are required · 1 deployment re-entry · 1 gate run per tree | as listed; the 12-step global budget first proposed is dropped (C1) | user (Q8) | a project whose CI takes longer than 30 min; the watch budget is then a project setting (not built: YAGNI) |
| 9 | Conflict repair | A) `git merge origin/<base>`, no force-push · B) rebase + `--force-with-lease`; trigger on `CONFLICTING` only, not `BEHIND` | A, `CONFLICTING` only | user (Q9) | a repository requires up-to-date branches (branch protection); `BEHIND` then becomes a trigger |
| 10 | How the state machine is tested | A) a pure `closure.py` driven by observation fixtures · B) prose needles | A. No `gh` calls inside the engine, which also avoids the Windows gh-mock trap | user (Q10) | — |
| 11 | `/security-scan` | A) moves into the gate as phase 4, recorded in `reviewers` · B) stays in wrap-up | A | user (Q11) | #162's profiles make security depth risk-scaled; phase 4 is then where the profile plugs in |
| 12 | Deployment fix commits | A) HEAD moved after deploy → re-enter at the receipt check (≤ 1) · B) stop `/verify-deployment` pushing | A | user (Q12) | a deployment runbook pushes more than once per verification |
| 13 | AC-8 evidence | A) fixture scenarios + this PR's own wrap-up recorded in `tasks/e2e-log.md` · B) also live scratch-repo runs | A | user (Q13) | — |
| 14 | How much of #162 | receipt schema + gate emission only; extractor, classifier and profiles deferred; #162 stays open (`Refs #162`) | as listed | user (prompt) | — |
| 15 | Fingerprint vs head as validity key | the fingerprint is the key; `head` is provenance | fingerprint | inferred: build sessions commit per slice and leave an uncommitted tail | wrap-up starts receiving already-committed trees from elsewhere; still correct, because the fingerprint is commit-independent |
| 16 | Tree hashing duplicated in `receipt.py` and `cached-suite.sh` | A) share a helper · B) each keeps its own five-line temp-index hash | B. Different languages, and the two hashes need not be equal (different keys, different stores) | inferred | the two start disagreeing about which files are in the tree; then extract `tree-hash.sh` |
| C1 | Global step budget (refines 8) | A) 12 steps · B) no global budget; every cycle consumes a named counter, checked by a table walk | B. With 12 steps, one CI repair already exhausted the budget before its CI watch, so the bounds in row 8 were unreachable | critic MUST-FIX — **confirm** | — |
| C2 | Chain validity vs approved HOLD | a chain link counts as valid when it is GO **or** approved HOLD. Delta receipts count unresolved SHOULD-FIX back to the nearest approved HOLD | as listed | critic MUST-FIX | — |
| C3 | Transition holes | add rows: non-ff with no rounds left, `pr: failed`, deploy re-entry used, `suite: blocked`, `record-failed`, `partial` on `draft-failed`/`no-pr`; the `gated` flag stops a second gate run on an unchanged tree | as listed | critic MUST-FIX | — |
| C4 | Base agreement | `receipt.py` resolves the base itself (the first existing of `origin/main`, `origin/master`, `origin/develop`, `main`, `master`, `develop`) and every caller omits `--base` | as listed | critic MUST-FIX | a repository whose integration branch has another name; `--base` is then the override |
| C5 | Repair commits vs the pre-push gate (refines 7) | each repair commit adds a `## Session Summary … — closure repair <n>` line (a fact known before that push), so `introduces_summary` covers it | as listed | critic MUST-FIX — **confirm** | the pre-push gate's coverage rule changes |
| C6 | Stopped vs partial after a PR exists; the deployment exception (refines 12) | `stopped` only before a PR exists, `partial` + draft after. The deployment fix push is listed as an accepted, bounded exception, not claimed impossible | as listed | critic MUST-FIX ×2 — **confirm** | — |
| C7 | Gate phase order | security becomes phase 3, before the dispatched APOSD phase 4, so the reviewer sees the security fixes. No phase after 4 edits the tree | as listed | critic SHOULD-FIX | — |
| C8 | Test evidence bound to the tree | `write` refuses when `tests.tree` differs from the reviewed tree | as listed | critic SHOULD-FIX | — |
| C9 | Engine files outside the worktree | the state and the outcome JSON live under the git common dir | as listed | critic SHOULD-FIX | — |
| C10 | Delta after a base merge | intersect the tree-to-tree delta with the branch's own `merge-base..tree` paths | as listed | critic SHOULD-FIX | — |
| C11 | Who may approve a HOLD; `ci: none` race; test surfaces; `AGENTS.md` taxonomy; diff flags pinned | as written in the contracts, Build Order and ACs | as listed | critic SHOULD-FIX / NITPICK | — |
| C12 | Policy hash coverage | hash every verdict-deciding file (`receipt.py`, the gate, security-scan, the APOSD skill and persona, the two references) | as listed | critic SHOULD-FIX | — |

## Acceptance Criteria

1. `receipt.py fingerprint --base <ref>` prints the merge-base, the tree and a fingerprint. The fingerprint is unchanged by an edit under `tasks/**` and by committing the same tree. It changes on any other edit, an untracked file included (`tests/test-quality-receipt.sh`).
2. `receipt.py write` stores `quality-receipt/1` at `<git-common-dir>/quality-receipts/<fingerprint>.json` with every field in § Data models. It derives the verdict (an unresolved MUST-FIX, a design STOP or red tests → STOP; more than 3 unresolved SHOULD-FIX or a design HOLD → HOLD; else GO) and ignores any supplied `verdict`. It refuses an outcome that fails the schema, or a delta scope with no stored parent, with exit 2 and writes nothing (`tests/test-quality-receipt.sh`).
3. `receipt.py check` exits 0 for a GO or approved-HOLD receipt matching the current fingerprint and policy with a valid chain. Otherwise it exits 3 with `receipt: stale <missing|diff-changed|policy-changed|schema|verdict|parent-invalid>`. `diff-changed` prints `parent` and the delta paths. Editing a policy file yields `policy-changed`. `approve` sets `hold_approved_by` on HOLD only (`tests/test-quality-receipt.sh`).
4. `/quality-gate` runs the `/security-scan` checklist over its own file list (untracked files included) as phase 3, before the dispatched APOSD phase 4. It runs the affected-test command through `cached-suite.sh` as phase 5, and no phase after 4 edits the tree. It takes `--scope <path> … --parent <fingerprint>`, runs `receipt.py write` as phase 6, and prints `Receipt: <verdict> <fp8> policy <v>`. A write refusal prints `Receipt: none — …`, never GO (`tests/test-doc-conventions.sh`).
5. `closure.py step` implements every row of § Transitions — closure `phase`. It rejects an observation its phase does not accept with exit 2 and an unchanged state file. Each accepted (phase, observation) pair has exactly one row. It turns a repair past its bound, a CI timeout, an unknown mergeability and a second stale receipt after a gate run into an end: `terminal stopped` before a PR exists, and `mark-draft` → `terminal partial` after. Every cycle in the table consumes a counter (`tests/test-closure.sh`).
6. Fixture scenarios in `tests/fixtures/closure/scenarios.json` replay green CI, CI repair, conflict repair, deployment success, deployment failure, stale receipt and a draft partial PR, each to its expected action trace and terminal line (`tests/test-closure.sh`).
7. `/wrap-up-session` dispatches no reviewer and runs no `/security-scan`. The review payload, the Step 5 apply and reconciliation loop and the *Parallel Code Review* enhancement are gone. `tests/test-review-context.sh` no longer lists wrap-up as a dispatch site and asserts it has none, and `tests/test-model-tiers.sh` no longer expects critic's floor there. `AGENTS.md`'s Layer 3 line names the receipt, not reviewer passes (`tests/test-review-context.sh`, `tests/test-model-tiers.sh`, `tests/test-doc-conventions.sh`).
8. Wrap-up `## Step 4 — Quality Gate Receipt` runs `receipt.py check`. On `valid` it reuses the receipt. On `diff-changed` it invokes `/quality-gate --scope <delta> --parent <fp>` once, on any other stale reason `/quality-gate` once at full scope, and it proceeds only on GO or approved HOLD. It approves a HOLD only after a human answer in an interactive run. It still reconciles specs before Step 4 and runs Step 6's full suite through `cached-suite.sh`. Step 8.5's exit table names Step 4's review stop in place of Step 5, and every closure end routes through Step 8.5 (`tests/test-living-spec-reconciliation.sh`, `tests/test-routine-wrapup.sh`, `tests/test-doc-conventions.sh`).
9. Wrap-up commits with hooks enabled (no `--no-verify`), pushes, and creates or re-syncs the PR with the existing linkage check. The body carries the `Quality receipt:` line and a `## Closure` section. From Step 4 on, wrap-up performs the actions `closure.py step` prints, with its state file under the git common dir (`tests/test-doc-conventions.sh`, `tests/test-routine-step-ledger.sh`).
10. Wrap-up checks mergeability with `gh pr view --json mergeable` and watches checks with `gh pr checks <n> --watch --required` as a background task (all checks when none are required), with a 30-min budget. A failed check's log (`gh run view --log-failed`) goes to `/debug`. The fix re-enters Step 4 and Step 6 before the push, for at most 2 rounds. `ci: none` is reported only when the 2-min registration window saw no checks and no workflow triggers on `pull_request`. Every repair commit adds a `## Session Summary … — closure repair <n>` line so the pre-push gate counts it covered (`tests/test-doc-conventions.sh`).
11. On `CONFLICTING`, or on a non-fast-forward push, wrap-up merges the base (or the remote branch) with no rebase and no force-push, for at most 1 round. A clean resolution re-enters Step 4. An unresolved merge is aborted and the run goes partial (`tests/test-doc-conventions.sh`).
12. When a `## Deployment Targets` row applies to the pushed branch, wrap-up invokes `/verify-evidence --scope deployment` and records its evidence. Otherwise it records `Deployments: not applicable — <reason>`. A deployment fix that moved HEAD re-enters Step 4 once (`tests/test-doc-conventions.sh`).
13. `tasks/history.md` and `tasks/todo.md` record only facts known before the push. CI, conflict and deployment outcomes go in the PR body's `## Closure` and the Done report's `Closure: <complete|partial — state>` line. A partial run marks the PR draft with `gh pr ready --undo`. `routines.md` names the receipt in place of review passes (`tests/test-doc-conventions.sh`).

## Implementation Paths

- `.agents/skills/quality-gate/scripts/receipt.py` — fingerprint, receipt schema, write, check, approve
- `.agents/skills/quality-gate/SKILL.md` — phases 4–6, `--parent`, the `Receipt:` output line
- `.agents/skills/wrap-up-session/scripts/closure.py` — the closure transition function and its bounds
- `.agents/skills/wrap-up-session/SKILL.md` — Step 4 receipt check, the removed review steps, the closure loop, the Done report
- `.agents/skills/wrap-up-session/references/routines.md` — step 5 of the routine spine names the receipt
- `tests/test-quality-receipt.sh` — AC 1–3
- `tests/test-closure.sh`, `tests/fixtures/closure/scenarios.json` — AC 5–6
- `tests/test-review-context.sh`, `tests/test-model-tiers.sh` — AC 7
- `AGENTS.md` — the Layer 3 line of the Review Gate Taxonomy names the receipt (AC 7)
- `tests/test-routine-wrapup.sh` — Step 8.5's exit table and routing (AC 8)
- `tests/test-routine-step-ledger.sh` — the Step 7 PR section it cuts (AC 9)
- `tests/test-living-spec-reconciliation.sh` — AC 8 heading order
- `tests/test-doc-conventions.sh` — AC 4, 7–13
