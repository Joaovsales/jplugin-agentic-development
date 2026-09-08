---
name: sweep
description: Producer routine engine — verify the codebase through one lens (janitor for bugs, architect for design) and file every proven finding as a registry task with a reproduction and a proposed fix. Use unattended from the janitor and architect routines, or by hand for a weekly audit.
argument-hint: "--routine <janitor|architect>"
disable-model-invocation: false
harness: universal
---

# /sweep — Verify, then file

A **producer**: it reads the open backlog so it does not duplicate, runs
extensive verification, and files issues. It never edits product code and never
fixes what it finds — the `fix` and `improve` consumer routines do that later, cold,
from the issue body this skill writes. Contract: `specs/sweep-routines.md` and
`.agents/skills/wrap-up-session/references/routines.md` § *Producers*.

`--routine <name>` picks the lens. Steps 3 and 4 differ per lens and live in
`references/lens-janitor.md` and `references/lens-architect.md`; every other step
is shared and stated once here.

| Routine | Lens | Files as | Priority |
|---|---|---|---|
| `janitor` | bugs — the full test suite plus the verifier full pass | `--kind bug` | `MUST-FIX` → `--label now`, `SHOULD-FIX` → `--label next` |
| `architect` | design — APOSD red flags over the whole tree | `--kind task --label tech-debt`, or `--kind decision` when the proposed fix is a choice between designs | same |

**No sub-agent is dispatched anywhere in a sweep.** The prompt that invokes this
skill is universal across projects and carries no dispatch; the skill runs every
engine inline. The cost is stated, not hidden: per `CLAUDE.md` § *Independence
Accounting*, every finding this run files has a **single witness**, so no
confidence anchor is promoted on agreement. Verification-promotion (reading one
more line) is still available and is how a `75` becomes a `100`.

Tracker access is only ever through `/task-registry`. This skill never calls a
tracker CLI or REST API for task state — the coupling guard in
`tests/test-doc-conventions.sh` applies to it.

## Steps

### 1. Doctor

Run `task-registry doctor` (`python3
.agents/skills/task-registry/scripts/task-registry.py doctor`) and record which
provider resolved and whether unattended writes are permitted — that is the
destination every finding will take (§ *Filing*). Idempotent with the producer
spine's step 1, so running it again here costs nothing and protects a hand-run
sweep. Then:

- **Clean tree** — `git status --porcelain` empty. A dirty tree makes the
  recorded sha a lie; STOP and say what is dirty.
- **Record `HEAD`** — the short sha is stamped into every `discovered:` evidence
  line and the session record.
- `janitor` only — exactly one project-local `verify-<app>` skill must exist. None
  → exit non-zero naming `/create-verification-skill` (human-run: it needs a live
  proof). The routine branch already exists (spine step 2); leave it as it is and
  open no PR.
- Write the **step ledger** rows into `tasks/todo.md` under a `## Sweep: <routine>
  <date>` heading, one `[ ]` row per step below. They are ticked as steps
  complete; the same rows are copied into the session record at step 6.

### 2. Read the backlog

Read the backlog through `/task-registry`: `task-registry show <id>` for each
open row of `tasks/todo.md` (there is no bulk read — the index is the list, the
ticket is the detail) and load every **open** task's title, summary, and evidence. This is the **dedupe set**: a candidate whose
`file:line` already appears in an open task's summary or evidence updates *that*
task at step 5 instead of minting a new one.

### 3. Run the engine — lens file

`references/lens-janitor.md` or `references/lens-architect.md` § *Engine*.
Whatever the lens runs, record **every command with its exit status**; the
record's *Scope* section is built from this list, not from memory.

### 4. Verify each candidate — lens file

The lens file § *Bar* states what a candidate needs before it may be filed. The
shared floor:

- `janitor`: a reproduction **executed this run** — command, observed output,
  expected output — and confidence `75` or above. A failing or flaky test is
  filed with the test command as its reproduction.
- `architect`: an `evidence` line quoting the motivating code with `file:line`,
  and confidence `75` or above. `NITPICK` is never filed.
- Both: a proposed fix as concrete steps, and acceptance criteria as checkable
  outcomes.

A candidate below the bar goes into the record's *Unverified* section with the
reason, and is never filed. A feature the engine could not reach (app would not
launch, fixture missing) is a *Coverage gap* with its prerequisite — it is not a
finding.

### 5. File

One `task-registry upsert --apply` per verified finding:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert --apply \
  --derive-id sweep --source <primary file> --fold-title \
  --title '<short title>' \
  --kind bug --label now \
  --summary '<one-line impact>' \
  --reproduction '<command>' \
  --reproduction 'observed: <what happened> / expected: <what should have>' \
  --proposed-fix '<step>' \
  --criterion '<checkable outcome>' \
  --evidence '[MUST-FIX | confidence: 100 | autofix_class: manual | owner: agent] <file>:<line> — <why>' \
  --evidence '<verbatim motivating line> (<file>:<line>)' \
  --evidence 'discovered: sweep/<routine> <YYYY-MM-DD> @ <sha>'
```

- **ID is derived, never typed.** Namespace `sweep`, the primary file under
  `--source`, and the short title folded in by `--fold-title`, all through the
  registry's `slugify_id` seam. The same file and title on a later run addresses
  the same task — updated, evidence appended, reopened if closed — never a second
  issue. Evidence accretes across runs (each sighting is kept, duplicates
  dropped); reproduction, proposed fix, and criteria are replaced. On GitHub
  the prose sections are seeded once at creation and never rewritten, so a
  later run's evidence reaches the issue through the metadata block only. A candidate already in the dedupe set (step 2) is filed against *that*
  task's ID instead.
- **Kind and labels.** `janitor` → `--kind bug`. `architect` → `--kind task
  --label tech-debt`, or `--kind decision` when the fix is a choice a human must
  make. Severity maps to priority: `MUST-FIX` → `--label now`, `SHOULD-FIX` →
  `--label next`. Labels are passed by name; a label the provider lacks is
  reported by the provider, never created by this skill.
- **Body fields.** `--summary` is the one-line impact. `--reproduction` is
  repeatable and `janitor`-only; its last line is `observed: … / expected: …`.
  `--proposed-fix` and `--criterion` are repeatable. `--evidence` carries the
  four-axis tag, the verbatim motivating line with `file:line`, and the
  `discovered: sweep/<routine> <date> @ <sha>` stamp.
- **Destination** follows the project's write policy and is never widened here:

  | Situation | Result |
  |---|---|
  | `provider = local` or no tracker | local record is canonical |
  | external provider, unattended writes permitted | external issue is the record; the index links it |
  | approval required and not given, or provider unreachable | local record canonical, **publication pending** |

  Pending publication never pauses or fails the run. The record and the PR body
  name the two switches that would publish next time: `require_write_approval =
  false` in the project's task-tracking file **and** `TASK_REGISTRY_TRUSTED_CONFIG=1`
  in the routine's environment. Only a failed **local** write STOPs the run —
  findings must not be lost — and the STOP message names the path that failed.

### 6. Session record

Write `tasks/sweeps/<YYYY-MM-DD>-<routine>.md` and commit it on the routine
branch. It is the sweep's artifact, so the "keep run notes out of the commit"
rule does not apply to it. Six sections, all mandatory; write `none` explicitly
when a section is empty:

1. **Scope** — every command run with its exit status; features driven or
   modules reviewed.
2. **Coverage gaps** — features or paths not reached, each with the prerequisite
   that would reach it. A clean sweep with gaps is not a clean codebase.
3. **Filed** — task ID, title, kind, priority, and the issue URL or
   `publication pending (<reason>)`.
4. **Unverified** — candidates below the filing bar and why.
5. **Independence** — the single-witness statement: no sub-agent was dispatched,
   so no finding was promoted on corroboration.
6. **Step ledger** — the rows from `tasks/todo.md`, ticked.

A clean sweep still writes the record: it is the only place "every mapped feature
was driven and nothing failed" is stated. It still hands off to wrap-up, and the
PR title is suffixed `— clean`.

### 7. Hand off

Stop. This skill commits nothing but the record and opens nothing. The producer
spine's step 4 runs `/wrap-up-session`, which on a `routine/<routine>/<YYYYMMDD>-sweep`
branch opens a **ready** PR titled `chore(sweep): <routine> <YYYY-MM-DD>` whose body
carries the step ledger, the record path, and `Refs #N` for every issue in the
record's *Filed* section — never `Closes`. The number in the branch is a run
stamp, not an issue, and is not looked up as one.

## Edge cases

| Situation | Behavior |
|---|---|
| Same finding, later run | Derived ID matches → task updated or reopened, evidence appended. No second issue. |
| Same defect, new wording | `file:line` already in an open task → that task is updated. |
| `janitor` with no `verify-<app>` skill | Stops at step 1, loud non-zero, names `/create-verification-skill`. No PR; the empty routine branch is left for the operator. |
| App will not launch here | Every unreachable feature is a coverage gap with its prerequisite. Not a finding. |
| Publication pending | Run continues; record and PR body name both switches. |
| Local write fails | STOP naming the path. Findings must not be lost. |
| External write fails after pre-flight passed | `upsert` exits 1 with the provider's error. STOP naming the task ID: pre-flight passed, so this is an outage, not policy, and a re-run addresses the same derived ID. |
| Nothing verified | Record with `Filed: none`; PR still opened, title suffixed `— clean`. |
| Two sweeps file the same `file:line` | The second updates the first's task; kinds differ only if the first was closed. |
