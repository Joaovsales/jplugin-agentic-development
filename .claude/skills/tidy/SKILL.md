---
name: tidy
description: Harness hygiene sweep for a coding-agent-workflow repository — the template, its mirror, and any project that vendored the harness through /sync. Eight checks over the surfaces that duplicate by design (skills tables, the session banner, retired skills, installed copies under ~/.claude and ~/.agents, backticked paths, worktrees, stray files, the task registers). Mechanical drift is fixed and committed one concern per commit, machine-side remedies are printed as commands and never run, larger drift is filed through /task-registry. Use by hand after a retirement or rename, or from a scheduled routine; --report sweeps without writing anything.
argument-hint: "[--report] [--check <name>[,<name>]]"
disable-model-invocation: false
harness: universal
---

# /tidy — Harness hygiene

A harness repository rots in ways an ordinary codebase does not. Its content is
**duplicated by design** — a canonical skill tree, a byte-identical compat tree, a
skills table in more than one document, a session-start banner, and copies
installed into `~/.claude/` and `~/.agents/` — and every retirement, rename, or
addition has to land in all of them. The test suite pins some of those copies;
nothing watches the rest, and nothing at all watches the copies outside the
repository. Each drift is otherwise noticed by a human, by accident, in a
different session. Spec: `specs/tidy-skill.md`.

`/tidy` is a self-contained, agent-driven sweep over those surfaces. It uses
`git`, `grep`, `gh pr list`, and the tools the harness already ships — `install.sh`,
the test suite, `/task-registry` — and adds no script of its own. Guards the suite
already provides (tree parity, syncable-path copies, agent tables, frontmatter,
asset references) are **delegated, not duplicated**: the sweep runs the suite and
reads its failures.

## Position in the routine contract

The contract in `.agents/skills/wrap-up-session/references/routines.md` knows two
shapes: a **producer** verifies and files, editing nothing; a **consumer** selects
an issue and fixes it. `/tidy` is deliberately
**neither a producer nor a consumer**, and says so:

- It **edits** — but only Tier 0 (§ *Risk tiers*): mechanical, reversible,
  tree-content changes that are cheaper to make than to file. Filing "delete
  `hookout.txt`" for a consumer to pick up cold tomorrow costs more than the fix.
- It **files** everything else exactly as a producer does — `task-registry upsert`
  with a derived ID, the dedupe set, a session record — so the `fix` and `improve`
  consumers pick the work up through their normal selectors.
- Every tree edit still ends in a human-reviewed pull request. The skill commits
  onto whatever branch it was given and **opens no pull request**; the host
  routine's `/wrap-up-session` opens it. Review *is* the gate.

`tidy` is registered as a producer-shaped routine on the branch
`routine/tidy/<YYYYMMDD>-sweep` (formatted by `routine_branch.py format tidy
<YYYYMMDD> sweep`) in `.agents/skills/wrap-up-session/references/routines.md`
§ *`tidy` — steps*; the scheduler prompt is
`.agents/skills/wrap-up-session/references/routine-prompts/tidy.md` beside it. The host runs `task-registry doctor`, creates that branch, runs this
skill, then `/wrap-up-session`. Cadence and the `TASK_REGISTRY_TRUSTED_CONFIG=1`
environment are the scheduler's, not this file's.

## Modes

| Invocation | Behaviour |
|---|---|
| `/tidy` | sweep, fix Tier 0, report Tier 1 with commands, file Tier 2 |
| `/tidy --report` | sweep and report only — no commits, no `upsert --apply`, no ledger rows written, no record file — the step ledger and the report are printed instead |
| `/tidy --check <name>[,<name>]` | run a subset, for a human chasing one thing. `suite` is part of the subset only when named; when it is not, no Tier 0 fix is applied (Law 3 has no green suite to rest on) |

## Steps

### 0. Preconditions

1. **Clean tree or stop** (Law 1). `git status --porcelain --untracked-files=no`
   non-empty → STOP, naming what is dirty. A modified or staged tracked file makes
   the recorded sha a lie and risks committing another session's work. Untracked
   files are not a dirty tree here: those matching a stray pattern are the
   `strays` check's input, the rest are WIP and are listed under *Coverage gaps*.
2. **Never on the default branch** (Law 10). `git rev-parse --abbrev-ref HEAD` is
   the default branch — `git symbolic-ref --short refs/remotes/origin/HEAD` minus
   its remote, or `master`/`main` when there is no remote — → STOP before the
   first commit. The literal `HEAD` (detached) STOPs too: a commit made there is
   orphaned the moment the worktree is removed, and the host has no branch to
   push. `--report` may run anywhere.
3. **Record `HEAD`** — the short sha is stamped into every `discovered:` evidence
   line, the report header, and the session record.
4. **Doctor** — `python3 .agents/skills/task-registry/scripts/task-registry.py doctor`
   records which provider resolved and whether unattended writes are permitted:
   that is the destination every Tier 2 finding will take (§ *Filing*).
5. **Ledger rows** — one `[ ]` row per check below under a `## Tidy: <YYYY-MM-DD>`
   heading in `tasks/todo.md`, ticked as checks complete and copied into the
   record at the end. Stage `tasks/todo.md` by explicit path only with the record
   commit, never with a Tier 0 commit.

### 1–8. The checks

Each check names the surfaces it reads. A surface that does not exist in the host
repository — a downstream project has no `README.md` skills table, no `AGENTS.md`
table — is **skipped with a note** in the report, never a finding. One skill serves the
template and its descendants, with one difference. A descendant is any checkout
whose `origin` is not the template repository
(`github.com/Joaovsales/coding-agent-workflow`). There `CLAUDE.md` is
template-managed and overwritten by `/sync`, so `inventory` treats it as
read-only (report, never edit), and the descendant's own allowlist entries live
in `.claude/tidy-allowlist` — one `path — reason` per line, same format — read
in addition to the seed list at the end of this file.

| Check | Reads | Finds |
|-------|-------|-------|
| `suite` | the project's test runner, discovered the way `/wrap-up-session` Step 6 does (`package.json`, `Makefile`, `pyproject.toml`, `TESTING.md`; in this repository, `tests/run.sh`) | a red suite. Ordered first; nothing is fixed on a red baseline. No runner → **inconclusive** |
| `inventory` | `.agents/skills/` ∪ `.claude/skills/` (the canonical tree plus the allowlisted Claude-only extras) ↔ the skills tables in `CLAUDE.md`, `README.md`, `AGENTS.md` (table rows whose first cell is a backticked `/<name>`) ↔ the `SKILLS AVAILABLE` block of `.claude/hooks/session-start.sh` | a skill present in one surface and absent from another, **in either direction**. A directory with no row is Tier 0 in the template repository — the row is determined by its `description` — and Tier 1 in a descendant, where `CLAUDE.md` is `/sync`-managed. A row naming a skill in neither tree is skipped when the *Allowlist* names it (`graphify` is registered on purpose), otherwise Tier 1: it may be a global-only skill the surface's prose still relies on, so the remedy (remove the row, or vendor the skill) is printed, not applied |
| `retired` | `git log --diff-filter=D --name-only --format= -- '.agents/skills/*/SKILL.md' '.claude/skills/*/SKILL.md'` — the retired set is *computed from history* over both trees, never typed — against every file outside `tasks/` and `specs/` | a retired skill still named **as live**: a banner line, a table row, a `/build` delegation, a hook that branches on it, an install or sync copy list. `tasks/` and `specs/` are history and exempt |
| `installed` | `~/.claude/CLAUDE.md`, `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/hooks/session-start.sh`, `~/.agents/` against what `install.sh` would write from `HEAD` | a stale, missing, or retired installed copy. No `~/.claude/` on this machine → **inconclusive** with the note |
| `refs` | paths in backticks in `CLAUDE.md`, `README.md`, `AGENTS.md`, `PI_SETUP.md`, `.claude/project.md`, and every `SKILL.md` | a path that resolves nowhere after trying the literal path, `~` expansion, and a basename search over `git ls-files`, minus the *Allowlist*. Placeholders (`<name>`) and globs are not paths |
| `worktrees` | `git worktree list --porcelain`, `git branch`, `gh pr list --state merged --limit 200 --json headRefName,headRefOid` | a worktree or local branch whose branch is **provably** merged — its name is in the forge's merged set **and** that PR's `headRefOid` is the local tip or reachable from it (`git merge-base --is-ancestor`); a name match with a different tip is *Unverified* (the name was reused). A merged set whose size equals the `--limit` is truncated: unmatched entries are *inconclusive*, not unmerged. Without forge access every worktree is report-only, because a squash-merge leaves no ancestry and is invisible to `git branch --merged` |
| `strays` | `git status --porcelain --untracked-files=all --ignored`; a direct listing of `.claude/worktrees/` (its ignore rule is machine-local, written by the runtime into `.git/info/exclude`, so `status` may or may not show those files) | transient droppings only: `*.log`, `*.tmp`, `*.orig`, `*.rej`, `*.bak`, `*.swp`, `*.pyc`, `__pycache__`, `nul`, `hookout.txt`, `hookerr.txt`. Any other untracked file is WIP and is context, not a finding |
| `registers` | `tasks/todo.md`, `tasks/checkpoint.md` | a closed plan block (every row `[x]`) older than the last two `## Session Summary` headings; a checkpoint whose header date is older than the newest summary. `tasks/solutions/` is **not** read — `/memory-maintain` owns it |

Per-check notes, where the table is not enough:

- **`retired`.** The set is the union over both trees, because a skill retired
  before the canonical tree existed lived only under `.claude/skills/` (`deslop`,
  `simplify`, `verify-e2e` here). A name whose directory exists again at `HEAD`
  in either tree, or that is a parity-allowlisted Claude-only extra, was re-added, not
  retired: drop it from the set. A test that asserts the retirement, or a `/sync`
  step that removes the skill downstream, names it without treating it as live —
  not a finding. `git rev-parse --is-shallow-repository` → `true` makes `retired`
  (and the local-branch half of `worktrees`) **inconclusive: shallow clone**,
  never clean — truncated history is an unread surface. An empty set in a full
  clone (fresh repository) reports clean with the note `no retirements in history`.
- **`installed`.** Compare content, not timestamps: `diff` the file, `diff -r` the
  directory. `install.sh` copies both trees, so `.claude/skills/README.md` and the
  parity extras *are* shipped. An installed skill directory the template does not
  ship has three outcomes, never two: retired (in the `retired` set → finding),
  the operator's own (`installed:<name>` in the *Allowlist* → skipped), or
  neither → finding reported as `unshipped, provenance unknown`, so an unknown
  directory can never pass as clean. The remedy is always the existing tool — `bash install.sh`,
  plus `bash install.sh --prune-skills` for entries the template no longer ships —
  printed, never run. The skill **never modifies** `~/.claude/` or `~/.agents/`
  itself (Law 7).
- **`refs`.** A token that fails literally, carries a directory component, and
  whose basename resolves to exactly one tracked file is a Tier 0 repair — the
  file moved. A bare filename that resolves by basename is *resolved* (the
  table's basename search), not a finding. Two files → Tier 1 with both paths in the report — except that a
  canonical path and its byte-identical copy under `.claude/skills/` are one
  file, not two, or every skill asset would read as ambiguous. None → Tier 1: the
  reference may describe something the project is expected to create. A path
  under the operator's home that is absent here is *Unverified* (outside the
  repository), not a finding.
- **`worktrees`.** The remedy is `git worktree remove <path>` and
  `git branch -D <branch>`, printed per entry. A detached-HEAD worktree is skipped
  with a note. `gh` absent or unauthenticated → the check runs, every entry is
  report-only, and the report says why.
- **`strays`.** A tracked stray is `git rm`'d and committed; an untracked one is
  deleted and recorded under *Scope*, since there is nothing to commit.
- **`registers`.** The remedy is to move the block into `tasks/history.md` under
  its session heading — judgment about what the block meant, so Tier 1, never
  applied here. A stale checkpoint's remedy is `/checkpoint` or removing the file.

Record **every command with its exit status**; the record's *Scope* section is
built from that list, not from memory.

## Risk tiers

Every finding lands in exactly one tier, and the tier decides what the pass may do:

- **Tier 0 — mechanical, reversible, tree content.** Fixed in the pass and
  committed: deleting a stray; adding a table row or banner line whose correct
  text is fully determined by the skill directory and the skill's own
  `description` (removing one is Tier 1 — see `inventory`); repairing a moved
  reference, a directory path whose basename resolves to exactly one file.
- **Tier 1 — needs judgment, or touches the operator's machine.** Reported with
  the exact remedy command, **never executed by the skill**: `git worktree remove
  <path>`, `bash install.sh --prune-skills`, a reference whose basename resolves to
  two files, a closed plan block to archive into `tasks/history.md`.
- **Tier 2 — larger than a tidy pass.** Filed through `/task-registry` (§ *Filing*)
  for a consumer routine: a doc section describing retired behaviour, a hook that
  still branches on a retired skill, a register that needs restructuring.

## Filing a Tier 2 finding

Read the **dedupe set** first: every open row of `tasks/todo.md` through
`task-registry show <id>` (there is no bulk read — the index is the list, the
ticket is the detail). A candidate whose `file:line` already appears in an open
task's summary or evidence updates *that* task's ID instead of minting a new one.
An open task carrying the configured escalation label remains in this dedupe set,
but is human-owned: record its existing reference in the session record and do not
update, reopen, relabel, or create an eligible replacement for the same finding.

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
  `improve`). Structural drift — a hook, a delegation table, a test loop →
  `--label tech-debt` (selected by `fix`). `MUST-FIX` → `--label now`,
  `SHOULD-FIX` → `--label next`. Labels are passed by name and never created here.
- **ID is derived, never typed.** Namespace `tidy`, `--source` the primary file,
  `--fold-title`. The same drift on a later run addresses the same task — updated,
  evidence appended, reopened if closed — never a second issue.
- **Destination follows the project's write policy and is never widened here:**

  | Situation | Result |
  |---|---|
  | `provider = local` or no tracker | local record is canonical |
  | external provider, unattended writes permitted (`require_write_approval = false` in the task-tracking file **and** `TASK_REGISTRY_TRUSTED_CONFIG=1` in the environment) | external issue is the record; the index links it |
  | approval required and not given, or provider unreachable | local record canonical, **publication pending**, reported, never dropped |

  A policy refusal is `publication pending`. A failed **local** write STOPs the run
  naming the path, and so does an external write that fails *after* pre-flight
  passed — that is an outage, not policy, and the STOP names the task ID.
- **`tasks/backlog.md` is not a destination.** It is `/prd`'s artifact and `/plan`'s
  intake; nothing in the routine architecture reads it for discovered work.
- **No tracker CLI or REST call.** `gh pr list` is permitted — pull requests are not
  task state. The tracker's issue subcommands and any tracker HTTP path are not;
  the coupling guard in `tests/test-doc-conventions.sh` applies to this skill as
  to every other.

## Laws

1. **Clean tree or stop.** `git status --porcelain --untracked-files=no` non-empty
   → STOP naming what is dirty. Untracked files are `strays` input or WIP context,
   never a STOP — otherwise the check that exists for them could never run.
2. **Three outcomes, not two** — `clean` / `findings` / `inconclusive`. A check
   that could not run (no `gh`, no `~/.claude/`, suite timed out, no runner)
   reports **inconclusive** and is never folded into `clean`. A surface the host
   lacks is a qualifier on the check's outcome — `clean (AGENTS.md skipped:
   absent)` — not a fourth state, and is listed under *Coverage gaps*.
3. **Red suite first.** A failing suite is finding #1, ordered above everything,
   and no Tier 0 fix is applied until it is green.
4. **The retired set is computed, never typed.** Git history says what was
   removed; a hand-maintained list would itself be the kind of copy this skill
   exists to catch.
5. **Never delete unmerged work.** No forge evidence of a merge → reported, not
   removed. A detached-HEAD worktree is skipped with a note.
6. **Untracked is not junk.** Only the named transient patterns are findings.
7. **The machine is the operator's.** Nothing outside the repository — worktrees,
   `~/.claude/`, `~/.agents/` — is modified by the skill. It prints the command.
8. **Allowlist entries carry a reason** — `path — reason`, kept in this skill's
   own *Allowlist* section. A bare path is not an entry. An installed-only skill
   directory is allowlisted by name as `installed:<name>`, never as a spelled-out
   home path — the reference guard reads `.claude/skills/<name>` as a repository
   path that must exist. Entries here ship with the template; a descendant's own
   entries live in `.claude/tidy-allowlist` — directly under `.claude/`, outside
   every syncable root, the same reasoning as `.claude/sync-keep` — because
   `/sync` overwrites this file.
9. **One concern per commit.** Strays, a table row, a banner line, a reference:
   four findings, four commits, each message naming the check —
   `chore(tidy): <check> — <what>`.
10. **Never on the default branch.** The host supplies the branch; the skill
    verifies before its first commit that it is neither the default branch
    (resolved from `origin/HEAD`; `master`/`main` without a remote) nor a
    detached `HEAD`, and stops if it is either.
11. **A finding is never silently dropped.** Unfilable → local record and
    `publication pending` in the report.
12. **`/tidy` reports; it does not decide what work exists.** Tier 2 output is a
    proposal a consumer routine or a human acts on, never a change the skill made
    on its own authority.

## Outputs

**The report**, printed once at the end — `suite` first, then the other checks in
table order, each on one line with its outcome; then Tier 1 remedies as
copy-pasteable commands, then Tier 2 filings with their IDs or `publication
pending (<reason>)`:

```
tidy @ <sha> on <branch> — <clean|findings|inconclusive>
  suite      : clean | RED (<n> failures, first: <name>) | inconclusive: <reason>
  inventory  : clean | <n> findings | inconclusive: <reason>   [+ (<surface> skipped: absent)]
  ...
Tier 0 — committed: <n>   Tier 1 — remedies below: <n>   Tier 2 — filed: <n>
```

Silence to stdout only when every check is `clean` with no surface skipped and
nothing inconclusive — the record is the proof. A skip or an inconclusive check
always prints, so "clean" and "not checked" never look alike. `--report` always
prints the header and the step ledger: it writes no record, so silence there
would leave no proof at all.

**Tier 0 commits** on the current branch, one per concern (Law 9).

**The session record**, `tasks/sweeps/<YYYY-MM-DD>-tidy.md`, committed as the last
commit together with the ticked ledger rows in `tasks/todo.md`. Six sections as
`/sweep` defines them, all mandatory, `none` written explicitly when empty:

1. **Scope** — every command run with its exit status; surfaces read; strays
   deleted.
2. **Coverage gaps** — checks inconclusive or surfaces skipped, each with the
   prerequisite that would reach it. A clean pass with gaps is not a clean harness.
3. **Filed** — task ID, title, kind, priority, and the issue URL or
   `publication pending (<reason>)`.
4. **Unverified** — candidates below the bar and why (a `refs` hit that may be a
   file the project is expected to create; a worktree without forge evidence).
5. **Independence** — the single-witness statement: no sub-agent was dispatched,
   so no finding was promoted on corroboration.
6. **Step ledger** — the rows from `tasks/todo.md`, ticked.

A clean pass still writes the record (outside `--report`). The skill then stops: it **opens no pull
request**; the host's `/wrap-up-session` does.

## Edge cases

| Situation | Behaviour |
|---|---|
| dirty tree | STOP (Law 1) |
| on `master`/`main` | STOP before the first commit (Law 10); `--report` runs |
| no test runner detected | `suite` inconclusive, not clean |
| `gh` absent or unauthenticated | `worktrees` report-only; `installed` and `inventory` unaffected |
| no `~/.claude/` on this machine | `installed` inconclusive with the note; not a finding |
| downstream project without `README.md`/`AGENTS.md` skills tables | those `inventory` surfaces skipped with a note |
| a skill's description differs between `.agents/` and `.claude/` | not `/tidy`'s finding — the parity test's; reported as a suite failure |
| a reference's basename matches two files | Tier 1, both paths in the report |
| a spec or learning names a retired skill | not a finding — history is exempt (`retired` scope) |
| a test asserts a skill's retirement | not a finding — it names the skill without treating it as live |
| retired set is empty (fresh repository) | `retired` clean with the note `no retirements in history` |
| shallow clone | `retired` and the local-branch half of `worktrees` inconclusive — history is truncated |
| detached `HEAD` | STOP before the first commit (Law 10); `--report` runs |
| merged set size equals the `gh` limit | unmatched worktrees and branches inconclusive, not unmerged |
| branch name in the merged set, tip not the PR's `headRefOid` | *Unverified* — the name was reused; no remedy printed |
| `upsert` refused by write policy | `publication pending`, run continues |
| local record write fails | STOP naming the path |
| external write fails after pre-flight passed | `upsert` exits 1 with the provider's error. STOP naming the task ID: pre-flight passed, so this is an outage, not policy, and a re-run addresses the same derived ID |
| same finding, later run | derived ID matches → task updated or reopened, evidence appended; no second issue |
| same finding, escalated task | keep its reference in the record; do not mutate it or file a replacement. Only human re-triage clears the hold |

## Allowlist

Paths the `refs` check accepts as absent and installed-only skill directories
(`installed:<name>`) the `installed` check accepts as present. Every entry is
`path — reason` (Law 8); a bare path is not an entry and the suite rejects it.

```
CLAUDE.local.md — personal overrides, gitignored by design
graphify-out/graph.json — per-project code graph, generated, optional
tasks/backlog.md — /prd artifact, absent in projects that never ran /prd
docs/task-tracking.md — optional registry configuration; absence selects a provider
~/.pi/agent/models.json — Pi's model registry; lives in the operator's home, never in the repo
graphify — an external per-machine CLI (README § Optional — graphify), registered in CLAUDE.md on purpose (#48); not a tree skill
installed:aws-saml2aws-auth — the operator's own skill under ~/.claude/skills; install.sh is additive by design
installed:prior-year-evidence — the operator's own skill under ~/.claude/skills; install.sh is additive by design
```
