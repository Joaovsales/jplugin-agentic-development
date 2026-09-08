---
implementation_paths:
  - .agents/skills/sweep/SKILL.md
  - .agents/skills/sweep/references/lens-janitor.md
  - .agents/skills/sweep/references/lens-architect.md
  - .agents/skills/wrap-up-session/references/routines.md
  - .agents/skills/wrap-up-session/references/routine-prompts/README.md
  - .agents/skills/wrap-up-session/references/routine-prompts/janitor.md
  - .agents/skills/wrap-up-session/references/routine-prompts/architect.md
  - .agents/skills/wrap-up-session/references/routine-prompts/fix.md
  - .agents/skills/wrap-up-session/references/routine-prompts/improve.md
  - .agents/skills/wrap-up-session/references/routine-prompts/plan.md
  - .agents/skills/wrap-up-session/scripts/routine_branch.py
  - .agents/skills/wrap-up-session/SKILL.md
  - .agents/skills/task-registry/scripts/registry/config.py
  - .agents/skills/task-registry/scripts/registry/model.py
  - .agents/skills/task-registry/scripts/registry/providers/github.py
  - .agents/skills/task-registry/scripts/registry/providers/local.py
  - .agents/skills/task-registry/scripts/task-registry.py
  - .agents/skills/task-registry/references/configuration.md
  - .agents/skills/debug/SKILL.md
  - .agents/skills/maintain-verification-skill/SKILL.md
  - .agents/skills/software-design-expert-review/SKILL.md
  - .agents/skills/auto-improve/ (deleted)
  - CLAUDE.md
  - README.md
  - .claude/hooks/session-start.sh
  - tests/test-sweep-routines.sh
  - tests/test-sweep-handoff.sh
  - tests/test-routine-branch.sh
  - tests/test-routine-selectors.sh
  - tests/test-routines-contract.sh
  - tests/test-auto-improve-rewire.sh (deleted)
---

# Sweep routines: `janitor` and `architect`

Supersedes `specs/auto-improve-findings-to-registry.md`, whose upsert wiring
becomes § *Filing* below.

## Problem

Every routine in `references/routines.md` is a **consumer**: it selects an issue
by kind label and ends at a PR that closes it. Nothing in the contract
**produces** issues. The closest producer, `/auto-improve`, discovers findings and
then fixes one itself, sinks the rest into `tasks/backlog.md` (downstream PR #407
filed 15 findings and zero issues), and needs sub-agent dispatch its cloud
routine does not have. The verifier full pass in `/maintain-verification-skill`
"reports product regressions" to nowhere durable and keeps its run notes out of
the commit. `/software-design-expert-review` audits a diff, never the tree.

On the consumer side, `/debug` takes a free-text bug report and asks the user
when it cannot reproduce, and an issue body has no place for the reproduction
steps or the proposed fix that a cheaper model would need to work cold.

## Design constraints

1. **A routine is a prompt that invokes a skill.** No sub-agent dispatch is
   required anywhere in a sweep. The prompt is universal across projects; the
   skill carries all logic.
2. **A producer does three things:** reads the open backlog so it does not
   duplicate, runs extensive verification, and files issues. Tracker access is
   through `/task-registry`, never a tracker CLI.
3. **Project-agnostic.** The lens engines are harness skills; each project owns
   its `verify-<app>` skill and its task-tracking configuration.
4. **One discover loop per lens.** `/auto-improve` is retired; its discovery
   becomes `/sweep`, its fix becomes the `fix` routine.

## Behavior

### B1 — Two producer routines join the contract

| Routine | Lens | Engine | Files as | Terminal artifact |
|---|---|---|---|---|
| `janitor` | bugs | full test suite + `/maintain-verification-skill` full pass (live pass drives every mapped feature under `/verify --scope e2e` rules) | `bug` | ready, docs-only PR carrying `Refs #N` per filed issue |
| `architect` | design | `/software-design-expert-review --scope tree` (APOSD red flags over the whole tree) | `task` + `tech-debt`, or `design-decision` when the fix needs a human decision | same |

Producers run on the **Planner** tier; consumers (`fix`, `improve`) on the
**Builder** tier. Cadence is the operator's: weekly for producers, daily for
consumers. Neither producer edits product code. `janitor` may carry verification
map corrections the full pass proved, nothing else.

**Producer spine** (states once, like the consumer spine):

| # | Step | Gate |
|---|---|---|
| 1 | `task-registry doctor` — records the destination policy findings will take. `janitor` additionally requires exactly one project-local `verify-<app>` skill; missing → loud non-zero naming `/create-verification-skill`, no branch, no PR | — |
| 2 | Branch: `routine_branch.py format <name> <YYYYMMDD> sweep` | — |
| 3 | `/sweep --routine <name>` | **non-skippable** — the sweep is the routine's entire artifact |
| 4 | `/wrap-up-session` | **non-skippable** |

The branch number is a **run stamp**, not an issue. `CONTRACT_ROUTINES` in
`routine_branch.py` gains both names (the formatter's membership check). The
registry's `config.py` gains `PRODUCER_ROUTINES = ("janitor", "architect")`:
`select` and `claim` refuse a producer with exit 2 ("producer routine — it files
issues, it does not select them"), and a `[routines.selectors]` key naming a
producer is refused at load like any unknown routine.

### B2 — One skill, `/sweep --routine <name>`

Seven steps. Steps 3 and 4 differ per lens and live in
`references/lens-<name>.md`; the rest is shared.

1. **Doctor.** Spine step 1 again (idempotent), plus clean tree and recorded
   `HEAD` sha. Write the step ledger rows into `tasks/todo.md`.
2. **Read the backlog.** Read it through `/task-registry` (`show` per open
   index row — there is no bulk read) and load every open task's title, summary,
   and evidence. This is the dedupe set. No `gh issue list`, no direct tracker
   call — the coupling guard in `tests/test-doc-conventions.sh` applies to this skill.
3. **Run the engine** (lens file). Everything the engine runs is recorded with
   its command and exit status. No sub-agents are dispatched; the run states, per
   *Independence Accounting*, that every finding has a single witness.
4. **Verify each candidate** (lens file). The bar to file:
   - `janitor`: a reproduction **executed this run** — the command, observed
     output, expected output — and confidence `75` or above. A failing or flaky
     test is filed with the test command as its reproduction.
   - `architect`: an `evidence` line quoting the motivating code with
     `file:line`, and confidence `75` or above. `NITPICK` is never filed.
   - Both: a proposed fix as concrete steps, and acceptance criteria as checkable
     outcomes.
   Candidates below the bar are recorded in the session record as *unverified*
   and never filed.
5. **File** — see § *Filing*.
6. **Session record** — see § *Session record*.
7. Hand off to `/wrap-up-session`. The skill itself commits nothing.

### Filing

One `task-registry upsert --apply` per verified finding.

- **ID** is derived, never typed: namespace `sweep`, the primary `file` path, and
  the short title, through the registry's `slugify_id` seam. Same file and title
  on a later run → the same task is *updated* (evidence appended, reopened if
  closed), never a second issue. A candidate whose `file:line` already appears in
  an open task's summary or evidence updates *that* task instead of minting one.
- **Kind and labels:** `janitor` → `--kind bug`; `architect` → `--kind task
  --label tech-debt`, or `--kind decision` when the proposed fix is a choice
  between designs. `MUST-FIX` → `--label now`; `SHOULD-FIX` → `--label next`.
  Labels are passed by name; a missing label is reported by the provider, never
  created by the skill.
- **Body fields:** `--summary` (one-line impact), `--reproduction` (repeatable,
  `janitor` only; the last line is `observed: … / expected: …`), `--proposed-fix`
  (repeatable), `--criterion` (repeatable), `--evidence` (repeatable: the
  four-axis tag, the verbatim motivating line with `file:line`, and
  `discovered: sweep/<routine> <date> @ <sha>`).
- **Destination** follows the project's write policy, never widened by the skill:

  | Situation | Result |
  |---|---|
  | `provider = local` or no tracker | local record is canonical |
  | external provider, unattended writes permitted | external issue is the record; index links it |
  | approval required and not given, or provider unreachable | local record canonical, **publication pending** |

  Pending publication never pauses or fails the run; the record and the PR body
  name the two switches (`require_write_approval = false` in the project's
  task-tracking file **and** `TASK_REGISTRY_TRUSTED_CONFIG=1` in the routine's
  environment). Only a failed **local** write STOPs the run.

### The handoff schema

`Task` gains two fields, `reproduction` and `proposed_fix` (tuples of lines),
carried by `upsert --reproduction` / `--proposed-fix`, rendered by `show`, and
round-tripped through the metadata block so a re-run replaces them rather than
accreting; evidence alone accretes, each run's sightings appended and
duplicates dropped. Every metadata entry is one line — a newline inside one is
refused, since it would end the entry and read its tail as a new key. The
seeded provider body (GitHub) is written once at creation and never
rewritten, so a later run reaches the issue through the metadata block only.
It renders, in order:
summary, `## Reproduction` (numbered), `## Proposed fix`,
`## Acceptance Criteria`, `## Evidence`, spec link. Evidence becomes visible in
the body because a consumer and a human both need the confidence anchor; today
it lives only inside the HTML-comment metadata block.

### Session record

`tasks/sweeps/<YYYY-MM-DD>-<routine>.md`, committed on the routine branch. It is
the sweep's artifact, so "keep run notes in scratch" does not apply to it.
Sections, all mandatory, `none` written explicitly when empty:

1. **Scope** — commands run with exit status; features driven / modules reviewed.
2. **Coverage gaps** — features or paths not reached, each with the prerequisite
   that would reach it. A clean sweep with gaps is not a clean codebase.
3. **Filed** — task ID, title, kind, priority, issue URL or
   `publication pending (<reason>)`.
4. **Unverified** — candidates below the filing bar and why.
5. **Independence** — the single-witness statement.
6. **Step ledger** — the same rows written to `tasks/todo.md`.

A clean sweep still writes the record and still opens the PR: the record is the
only place "every mapped feature was driven and nothing failed" is stated.

### Wrap-up on a producer branch

`/wrap-up-session`'s linkage table gains a row: a producer routine opens a
**ready** PR, title `chore(sweep): <routine> <date>`, body carrying the step
ledger, the record path, and `Refs #N` for every issue in the record's *Filed*
section — never `Closes`. The number the branch carries is not looked up as an
issue.

### Consumer intake

- `/debug` accepts an issue reference (`#N` or a task ID) as `$ARGUMENTS`. It
  reads `task-registry show`, runs the issue's *Reproduction* as the reproduction
  step, and enters the *Proposed fix* into the root-cause prelude as **candidate
  one**, to be confirmed rather than assumed. On a `routine/` branch, "cannot
  reproduce" emits `blocked: reproduction failed — <command>`, exits non-zero,
  and opens no PR; it never asks the user. When the issue carries a proposed fix
  and criteria, `/debug`'s final phase writes the `[ ] TDD:` tasks for `/build`
  from them.
- The `fix` routine's step 4a row becomes `/debug #N`; for `tech-debt` it reads
  the proposed fix and evidence through `show`.

### Routine prompts ship with the harness

`.agents/skills/wrap-up-session/references/routine-prompts/<name>.md` for
`janitor`, `architect`, `fix`, `improve`, `plan`. Each is under 25 lines,
project-agnostic (no repository names, no paths outside the harness), names the
routine and the one skill it invokes, and says sub-agent dispatch is not
required. The sibling `README.md` gives the operator recipe: model tier per
routine, suggested cadence, and the environment checklist (the two write
switches, an authenticated `gh` because the GitHub provider is `gh`-only, the
mapped labels pre-existing unless `allow_label_creation` is on, and for `janitor`
an app that launches in the routine's environment). The same checklist is the
"Unattended routines" section of `task-registry/references/configuration.md`.

### Engine amendments

- `/maintain-verification-skill` full pass, source wave: when dispatch is
  unavailable, run the wave **inline**, one feature at a time, and state the lost
  corroboration; `blocked` is reserved for source that cannot be read. Its
  ship-or-stop step defers to the caller when invoked from `/sweep`: the sweep
  owns the PR.
- `/software-design-expert-review` gains `--scope tree` (every source file,
  excluding tests and vendored paths, batched by directory) and an inline path
  when dispatch is unavailable, reported as "single batch — no promotion
  available".

### Retirement of `/auto-improve`

Both trees deleted, `tests/test-auto-improve-rewire.sh` deleted, and every
reference outside `tasks/` and `specs/` history repointed: `CLAUDE.md` skills
table and the repo-survey exception in *Review Dispatch Contract* (now `/sweep
--routine architect`), `README.md`, `session-start.sh`, `/build` and
`subagent-resilience.md`, the `/wrap-up-session` Step 8.5 caller list, and the
test loops in `test-doc-conventions.sh`, `test-model-tiers.sh`,
`test-review-context.sh`, `test-skill-invocation-chain.sh`,
`test-routines-contract.sh`, `test-routine-wrapup.sh` (`/sweep` runs on a
routine branch, so the parser rule covers it and it needs no declaration) and the
`test-routine-skills.sh` reconfiguration fixture. The reference list was
regenerated with `git grep` against the merged tree after master's Phase A and
Cuts 1–2 landed, not inherited from the plan. Downstream `/sync` retires the directory from the
template's history record; no allowlist entry is needed.

## Inputs / Outputs

- **In:** the project's task-tracking configuration and write gate; its
  `verify-<app>` skill and feature map (`janitor`); the source tree
  (`architect`); the open backlog through `/task-registry`.
- **Out:** one registry task per verified finding (issue or local record), the
  committed session record, synced index rows, and a docs-only PR.

## Edge Cases

| Situation | Behavior |
|---|---|
| Same finding, later run | Derived ID matches → task updated/reopened, evidence appended. No second issue. |
| Same defect, new wording | `file:line` already in an open task → that task is updated. |
| `janitor` with no `verify-<app>` skill | Stops at doctor, loud non-zero, names `/create-verification-skill` (human-run: it needs a live proof). No PR. |
| App will not launch in the environment | Features recorded as coverage gaps with the prerequisite. They are not findings. |
| Publication pending | Run continues; record and PR body name both switches. |
| Local write fails | STOP; findings must not be lost. |
| Second run same day | Branch already exists → loud non-zero, no second branch. |
| Consumer cannot reproduce | `blocked`, non-zero, no PR. The claim label stays — releasing it needs a registry write that does not exist yet and is filed as follow-up, not built here. |
| Nothing verified | Record with `Filed: none`, PR opened, title suffixed `— clean`. |
| Two sweeps file the same file:line | Second updates the first's task; kinds differ only if the first was closed. |

## Acceptance Criteria

- AC1 — `routines.md` has table rows for `janitor` and `architect`, a producer
  spine section with four steps of which `/sweep` and `/wrap-up-session` are
  non-skippable, a `### \`<name>\` — steps` section per producer, and states that
  producers never edit product code.
- AC2 — `routine_branch.CONTRACT_ROUTINES` carries both producers and
  `format janitor 20260907 sweep` round-trips; `config.PRODUCER_ROUTINES` exists;
  `select --routine janitor` and `claim --routine architect` exit 2 naming
  "producer"; a `[routines.selectors]` entry for a producer is refused at load.
- AC3 — `.agents/skills/sweep/SKILL.md` and both lens files exist, byte-identical
  in `.claude/`; the skill names `task-registry doctor`, reads the backlog via
  `/task-registry`, never mentions `gh issue`, uses `upsert --apply` with
  `--reproduction`, `--proposed-fix`, `--criterion`, `--evidence`, states the
  kind/label and priority mapping, the destination table, the never-pause and
  STOP rules, `tasks/sweeps/`, the six record sections, `Refs #`,
  `chore(sweep):`, the single-witness statement, and that no sub-agent is
  dispatched.
- AC4 — `Task` has `reproduction` and `proposed_fix`; `upsert` accepts both
  flags; the GitHub seeded body renders the five sections in order; the
  local provider and the metadata block round-trip both fields; `show` renders
  them. Pinned by a Python test in `tests/test-sweep-handoff.sh`.
- AC5 — `/debug` documents issue-reference intake via `task-registry show`, the
  candidate-one rule, the unattended `blocked:` path with non-zero exit and no
  user prompt, and writing `[ ] TDD:` tasks from the issue; `routines.md` `fix`
  step 4a reads `/debug #N`.
- AC6 — `/maintain-verification-skill` states the inline source-wave fallback
  and sweep-owned shipping; `/software-design-expert-review` documents
  `--scope tree` and an inline fallback.
- AC7 — `/wrap-up-session` linkage table has the producer row (`Refs` per filed
  issue, ready PR, run stamp not an issue) and the PR title format.
- AC8 — Five routine prompts exist, each under 25 lines, naming its skill,
  containing no repository name; the README states tiers, cadence, and the
  environment checklist.
- AC9 — No file outside `tasks/` and `specs/` mentions `auto-improve`; the
  `CLAUDE.md` repo-survey exception names `/sweep`; `README.md` and
  `session-start.sh` list `/sweep` in its place.
- AC10 — `task-registry/references/configuration.md` has an "Unattended
  routines" section naming both switches, `gh`, and `allow_label_creation`.
- AC11 — `tests/test-skill-parity.sh` and `bash tests/run.sh` are fully green.

## Out of scope

- Releasing a claim label when a consumer is blocked (needs a registry write).
- Bounded review waves for large feature maps (#103, #99) — the inline fallback
  makes the sweep run today; parallel corroboration returns when those land.
- Native dependencies and the `build` routine (#97, #98).
- Downstream operator actions: enabling the two switches, installing `gh`,
  generating `verify-<app>`, and rewriting the existing "Bug fixing" cloud
  routine (`trig_018RktpiXBTWSZ8dC2AUBpwf`) to the `fix` prompt on the Builder
  tier, plus creating the two weekly producer routines on the Planner tier.
