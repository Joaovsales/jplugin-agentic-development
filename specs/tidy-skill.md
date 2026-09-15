# Spec — `/tidy`, harness hygiene for a coding-agent-workflow repository

> **Reconstructed and re-scoped.** The original `specs/tidy-routine.md` is lost. This
> spec is rebuilt from the surviving plan (`%TEMP%/tidy-block.md`) and detector
> prototype, then re-scoped twice with the user: ship the **skill only** (the scheduled
> routine that hosts it is built separately), and aim it at **the harness itself** —
> this template repository, its mirror `Joaovsales/jplugin-agentic-development`, and
> any project that vendored the harness through `/sync` — rather than at repositories
> in general.
>
> **Baseline: `bf58555` (#122).** Every check below is anchored to a finding present
> in this tree at that commit; those anchors are the fixtures the build verifies
> against. Reconciled with the routine architecture (#105, #111, #112), the registry
> cuts (#113, #114), automatic publishing (#118) and the `/tdd` retirement (#86).

## Problem

A harness repository rots in ways an ordinary codebase does not. Its content is
*duplicated by design* — a canonical tree, a byte-identical compat tree, a skills
table in three documents, a session-start banner, and copies installed into
`~/.claude/` and `~/.agents/` — and every retirement, rename, or addition has to land
in all of them. The test suite pins some of those copies (tree parity, the seven
syncable-path lists, agent tables, frontmatter) but not all, and nothing at all
watches the copies that live outside the repository. So at `bf58555`:

| Rot | Evidence in this tree |
|-----|-----------------------|
| skills table drift | `verify-task-registry` has a directory and no row. (`CLAUDE.md` also lists `/graphify` with no directory — found during the build to be deliberate, an external CLI registered in #48, so it became an *Allowlist* seed rather than a finding) |
| retired ghosts | `~/.claude/skills/` still holds `tdd` and `auto-improve`, retired in #86 and #112; the banner this session printed advertises both. `HEAD`'s hook does not — the only `SessionStart` entry is in `~/.claude/settings.json`, so the stale installed `~/.claude/hooks/session-start.sh` is what every session on this machine runs |
| installed-copy drift | `~/.claude/CLAUDE.md` differs from the repository's by 918 lines; `~/.claude/skills/` lacks seven current skills |
| dangling references | none at this baseline once the basename rule and allowlist apply — `auto-test-runner.sh` resolves to `.claude/hooks/`, `models.json` is `~/.pi/agent/models.json`. Kept as a check because the August prototype found several, since fixed |
| abandoned worktrees | 32 worktrees; 20 local branches whose pull request is already squash-merged |
| strays | `.claude/worktrees/hookerr.txt`, `hookout.txt` — hook droppings outside git's view |
| register bloat | `tasks/todo.md` is 744 lines and 58 headings, most of them closed plan blocks from August, in a file the rules call an *index* |

Each of these was noticed by a human, by accident, in a different session. Three of
them are recorded in the learning store as recurring wounds
(`repo-fix-does-not-reach-installed-copies`, `global-only-skills-at-risk`,
`current-state-cannot-distinguish-removed-from-never-present`).

## Behavior

`/tidy` is a self-contained, agent-driven sweep over the harness surfaces. It uses
`git`, `grep`, `gh pr list`, and the existing tools the harness already ships —
`install.sh`, the test suite, `/task-registry` — and adds no script of its own.

### Position in the routine contract

The contract in `.agents/skills/wrap-up-session/references/routines.md` knows two
shapes: a **producer** verifies and files, editing nothing; a **consumer** selects
an issue and fixes it. `/tidy` is deliberately **neither**, and says so:

- It **edits** — but only Tier 0 (below): mechanical, reversible, tree-content
  changes that are cheaper to make than to file. Filing "delete `hookout.txt`" as
  an issue for a consumer to pick up cold tomorrow costs more than the fix.
- It **files** everything else exactly as a producer does — `task-registry
  upsert` with a derived ID, the dedupe set, a session record — so the `fix` and
  `improve` consumers pick the work up through their normal selectors.
- Every tree edit still ends in a human-reviewed pull request. The skill commits
  onto whatever branch it was given and **opens nothing**; the host routine's
  `/wrap-up-session` opens the PR. That keeps the consumer-shaped terminal
  (review *is* the gate) without asking a scheduler to re-derive autonomy.

Registering `tidy` as a routine — branch vocabulary in wrap-up's parser table, a
routine prompt, cadence — is the host's work and is out of scope here.

### Checks

Each check names the surfaces it reads. A surface that does not exist in the host
repository (a downstream project has no `README.md` skills table, no `AGENTS.md`)
is **skipped with a note**, never a finding — one skill serves the template and
its descendants.

| Check | Reads | Finds |
|-------|-------|-------|
| `suite` | the project's test runner | a red suite. Ordered first; nothing is fixed on a red baseline |
| `inventory` | `.agents/skills/` ↔ skills tables in `CLAUDE.md`, `README.md`, `AGENTS.md` ↔ the `SKILLS AVAILABLE` block of `.claude/hooks/session-start.sh` | a skill present in one surface and absent from another, **in either direction** |
| `retired` | `git log --diff-filter=D -- '.agents/skills/*/SKILL.md'` (the retired set is *computed from history*, never typed) against every file outside `tasks/` and `specs/` | a retired skill still named as live — a banner line, a table row, a `/build` delegation, a hook. `tasks/` and `specs/` are history and exempt, per the `/auto-improve` retirement in #112 |
| `installed` | `~/.claude/CLAUDE.md`, `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/hooks/session-start.sh`, `~/.agents/` against what `install.sh` would write from `HEAD` | a stale, missing, or retired installed copy. Remedy is always the existing tool: `bash install.sh`, plus `--prune-skills` for entries the template no longer ships |
| `refs` | paths in backticks in `CLAUDE.md`, `README.md`, `AGENTS.md`, `PI_SETUP.md`, `.claude/project.md`, and every `SKILL.md` | a path that resolves nowhere, after trying the literal path and a basename search, minus the allowlist |
| `worktrees` | `git worktree list`, `gh pr list --state merged` | a worktree whose branch is **provably** merged. Without forge access every worktree is report-only, because squash-merge is invisible to `git branch --merged` |
| `strays` | `git status --porcelain --untracked-files=all`; files directly under `.claude/worktrees/` | transient droppings (`*.log`, `*.tmp`, `*.orig`, `*.rej`, `*.bak`, `*.swp`, `*.pyc`, `__pycache__`, `nul`, `hookout.txt`, `hookerr.txt`). Any other untracked file is WIP and is context, not a finding |
| `registers` | `tasks/todo.md`, `tasks/checkpoint.md` | closed plan blocks older than the last two `## Session Summary` headings; a checkpoint older than the newest summary. `tasks/solutions/` is **not** read — `/memory-maintain` owns it |

Guards the suite already provides are **delegated, not duplicated**: tree parity
(`test-skill-parity.sh`), the seven syncable-path copies (`test-syncable-paths.sh`),
agent tables (`test-agents.sh`), frontmatter and asset references. `/tidy` runs
the suite and reads its failures; it does not re-implement them.

### Risk tiers

Every finding lands in exactly one tier, and the tier decides what the pass may do:

- **Tier 0 — mechanical, reversible, tree content.** Fixed in the pass and committed:
  deleting a stray, adding or removing a table row or banner line whose correct text
  is fully determined by `.agents/skills/` and the skill's own `description`,
  repairing a reference whose basename resolves to exactly one file.
- **Tier 1 — needs judgment, or touches the operator's machine.** Reported with the
  exact remedy command, **never executed by the skill**: `git worktree remove
  <path>`, `bash install.sh --prune-skills`, a reference whose basename resolves to
  two files, a closed plan block to archive into `tasks/history.md`.
- **Tier 2 — larger than a tidy pass.** Filed through `/task-registry` (below) for a
  consumer routine: a doc section describing retired behaviour, a hook that still
  branches on a retired skill, a register that needs restructuring.

### Filing a Tier 2 finding

One `upsert` per verified finding, mirroring `/sweep` § *File* so the consumers'
selectors and the dedupe rules apply unchanged:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert --apply \
  --derive-id tidy --source <primary file> --fold-title \
  --title '<short title>' \
  --kind task --label documentation --label next \
  --summary '<one-line impact>' \
  --proposed-fix '<step>' \
  --criterion '<checkable outcome>' \
  --evidence '[SHOULD-FIX | confidence: 100 | autofix_class: manual | owner: agent] <file>:<line> — <why>' \
  --evidence '<verbatim motivating line> (<file>:<line>)' \
  --evidence 'discovered: tidy <YYYY-MM-DD> @ <sha>'
```

- **Kind and labels.** Documentation drift → `--label documentation` (selected by
  `improve`). Structural drift — a hook, a delegation table, a test loop → `--label
  tech-debt` (selected by `fix`). `MUST-FIX` → `now`, `SHOULD-FIX` → `next`.
  Labels are passed by name and never created here.
- **ID is derived, never typed.** Namespace `tidy`, `--source` the primary file,
  `--fold-title`. The same drift on a later run addresses the same task — updated,
  evidence appended, reopened if closed — never a second issue.
- **Dedupe set** — every open row of `tasks/todo.md` read through `task-registry
  show`; a candidate whose `file:line` already appears in an open task updates that
  task's ID instead.
- **Destination follows the project's write policy and is never widened here.**
  `provider = local` or no tracker → the local record is canonical. External
  provider with unattended writes permitted (this repository: `docs/task-tracking.md`
  sets `require_write_approval = false`, and the host supplies
  `TASK_REGISTRY_TRUSTED_CONFIG=1`) → the issue is the record. Approval required and
  absent, or provider unreachable → local record canonical, **publication pending**,
  reported, never dropped. Only a failed *local* write stops the run.
- **`tasks/backlog.md` is not a destination.** It is `/prd`'s artifact and `/plan`'s
  intake; nothing in the routine architecture reads it for discovered work.
- **No tracker CLI or REST call.** `gh pr list` is permitted (pull requests are not
  task state); `gh issue` and `/rest/api/` are not — the coupling guard in
  `tests/test-doc-conventions.sh` applies to this skill as to every other.

### Laws

1. **Clean tree or stop.** `git status --porcelain` non-empty → STOP naming what is
   dirty. A dirty tree makes the recorded sha a lie and risks committing another
   session's work; this clone is dirty with another session's `system-design-planning`
   files as this spec is written, and `/tidy` must refuse to run on it.
2. **Three outcomes, not two** — `clean` / `findings` / `inconclusive`. A check that
   could not run (no `gh`, no `~/.claude`, suite timed out) reports **inconclusive**
   and is never folded into `clean`.
3. **Red suite first.** A failing suite is finding #1, ordered above everything, and
   no Tier 0 fix is applied until it is green.
4. **The retired set is computed, never typed.** Git history says what was removed;
   a hand-maintained list would itself be the kind of copy this skill exists to catch.
5. **Never delete unmerged work.** No forge evidence of a merge → reported, not
   removed. A detached-HEAD worktree is skipped with a note.
6. **Untracked is not junk.** Only the named transient patterns are findings.
7. **The machine is the operator's.** Nothing outside the repository — worktrees,
   `~/.claude/`, `~/.agents/` — is modified by the skill. It prints the command.
8. **Allowlist entries carry a reason** — `path — reason`, kept in the skill's own
   *Allowlist* section. A bare path is not an entry.
9. **One concern per commit.** Strays, a table row, a banner line, a reference: four
   findings, four commits, each message naming the check.
10. **Never on the default branch.** The host supplies the branch; the skill verifies
    it is not `master`/`main` before its first commit and stops if it is.
11. **A finding is never silently dropped.** Unfilable → local record and
    `publication pending` in the report.
12. **`/tidy` reports; it does not decide what work exists.** Tier 2 output is a
    proposal a consumer routine or a human acts on, never a change the skill made on
    its own authority.

## Inputs

- `/tidy` — sweep, fix Tier 0, report Tier 1 with commands, file Tier 2
- `/tidy --report` — sweep and report only; no commits, no `upsert --apply`
- `/tidy --check <name>[,<name>]` — run a subset, for a human chasing one thing

## Outputs

- A tiered report, `suite` first, inconclusive checks called out, Tier 1 remedies
  as copy-pasteable commands
- Tier 0 commits on the current branch, one per concern
- Tier 2 tasks through `upsert`, or `publication pending` with the reason
- `tasks/sweeps/<YYYY-MM-DD>-tidy.md` — the session record, six sections as
  `/sweep` defines them (*Scope*, *Coverage gaps*, *Filed*, *Unverified*,
  *Independence*, *Step ledger*), `none` written explicitly; committed as the last
  commit. A clean pass still writes it
- Silence to stdout when the repository is clean — the record is the proof

## Edge cases

| Situation | Behaviour |
|---|---|
| dirty tree | STOP (Law 1) |
| on `master`/`main` | STOP before the first commit (Law 10) |
| no test runner detected | `suite` inconclusive, not clean |
| `gh` absent or unauthenticated | `worktrees` report-only; `installed` and `inventory` unaffected |
| no `~/.claude/` on this machine | `installed` inconclusive with the note; not a finding |
| downstream project without `README.md`/`AGENTS.md` skills tables | those `inventory` surfaces skipped with a note |
| a skill's description differs between `.agents/` and `.claude/` | not `/tidy`'s finding — the parity test's; reported as a suite failure |
| a reference's basename matches two files | Tier 1, both paths in the report |
| a spec or learning names a retired skill | not a finding — history is exempt (`retired` check scope) |
| retired set is empty (fresh repository) | `retired` reports clean with the note `no retirements in history` |
| `upsert` refused by write policy | `publication pending`, run continues |
| local record write fails | STOP naming the path |

## Allowlist (seed)

```
CLAUDE.local.md          — personal overrides, gitignored by design
graphify-out/graph.json  — per-project graph, generated, optional
tasks/backlog.md         — /prd artifact, absent in projects that never ran /prd
docs/task-tracking.md    — optional registry configuration; absence selects a provider
~/.pi/agent/models.json  — Pi's model registry; lives in the operator's home, never in the repo
graphify — external per-machine CLI registered in CLAUDE.md on purpose (#48)
installed:aws-saml2aws-auth   — user's own skill under ~/.claude/skills; install.sh is additive by design
installed:prior-year-evidence — user's own skill under ~/.claude/skills; install.sh is additive by design
```

## Acceptance criteria

- **AC-1** `.agents/skills/tidy/SKILL.md` exists, is byte-identical to
  `.claude/skills/tidy/SKILL.md`, and both pass the frontmatter guard (`name: tidy`
  matching the directory, `description` present and under 1024 chars).
- **AC-2** The skill defines the eight checks above with the surfaces each reads, and
  states that a missing surface is skipped, not a finding.
- **AC-3** The skill states it is neither a producer nor a consumer under the routine
  contract, names the tiers, and confines edits to Tier 0 tree content.
- **AC-4** The skill's `retired` check derives the retired set from
  `git log --diff-filter=D` over both skill trees (`.agents/skills/` and
  `.claude/skills/` — three skills were retired under the latter alone) and
  exempts `tasks/` and `specs/`.
- **AC-5** The skill's `installed` check names `install.sh` (and `--prune-skills`) as
  the only remedy and never modifies `~/.claude/` or `~/.agents/` itself.
- **AC-6** The skill forbids removing a worktree without forge evidence of a merge and
  names squash-merge as the reason `git branch --merged` is insufficient.
- **AC-7** The skill's filing block uses `upsert --derive-id tidy --source … --fold-title`,
  maps documentation drift to `documentation` and structural drift to `tech-debt`,
  and carries the `discovered: tidy <date> @ <sha>` evidence stamp.
- **AC-8** The skill states the write-policy table verbatim in spirit (local
  canonical / external record / publication pending) and that `tasks/backlog.md` is
  not a destination.
- **AC-9** The skill contains no `gh issue` and no `/rest/api/` — the coupling guard
  in `tests/test-doc-conventions.sh` stays green.
- **AC-10** The skill states Laws 1, 3, 9 and 10: clean tree, red suite first, one
  concern per commit, never on the default branch.
- **AC-11** The skill writes `tasks/sweeps/<date>-tidy.md` with the six `/sweep`
  sections and opens no pull request.
- **AC-12** `/tidy` is registered in the skills tables of `CLAUDE.md`, `README.md`,
  `AGENTS.md` and in the `SKILLS AVAILABLE` block of
  `.claude/hooks/session-start.sh`, each pinned by an assertion in
  `tests/test-doc-conventions.sh`.
- **AC-13** The skill ships no script and references no asset file, so
  `tests/test-skill-references.sh` and `tests/test-syncable-paths.sh` stay green
  with no new path declarations.
- **AC-14** A `/tidy --report` run against this repository at the build's base commit
  lists, at minimum, the six live rows of the *Problem* table above (`refs` reports
  clean; the `suite` row is whatever the baseline run shows). The report is captured into the
  build's evidence, not committed.
- **AC-15** `bash tests/run.sh` is green, assertion count recorded against the
  pre-change baseline.

## Out of scope

- **The host routine**: branch naming under `routine/tidy/`, wrap-up's parser row
  (today an unknown `routine/<name>` falls through to `Closes #N`, which is wrong for
  a filer — the row must say `Refs #N`), the routine prompt, cadence, and the
  `TASK_REGISTRY_TRUSTED_CONFIG` environment. The user builds this separately.
- **Fixing the seven live findings** in the *Problem* table. They are this build's
  fixtures (AC-14) and each belongs in its own commit under Law 9 — not in the
  skill's PR.
- `tasks/solutions/` hygiene (`/memory-maintain`), downstream retirement
  (`/sync` Step 6.4), tree parity and syncable-path copies (the suite).
