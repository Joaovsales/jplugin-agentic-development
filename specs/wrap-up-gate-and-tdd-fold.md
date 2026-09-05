# Spec: Wrap-Up Push Gate + `/tdd` Fold-and-Retire

Two workstreams, one spec, because they share a root cause: workflow doctrine
that lives only in prose is unenforceable, and duplicated prose drifts. **A**
makes wrap-up mechanically checkable at the one point every code-producing
session converges on. **B** removes the duplicate TDD doctrine that made
"which skill owns this rule?" ambiguous in the first place.

They are independently shippable and must land as separate commits.

---

## Background — why the push, not the build

An audit of every skill (2026-09-01) found that `/build` is not a chokepoint for
code production. These paths write code and never invoke `/build`:

| Path | Evidence |
|---|---|
| **No skill at all** — a plain conversational request | no boundary to hook |
| `/debug` | `debug/SKILL.md:123` delegates the fix directly; its two `/build` mentions are Model Routing pointers |
| `/tdd` | zero `/build` references; own loop |
| `/wrap-up-session` Step 5 | auto-applies `gated_auto` findings — **the gate writes code itself** |
| `/receive-review` standalone | `:216` "PR review cycles" — *accepted as out of scope, see Non-Goals* |

Rows 1 and 4 cannot be gated at a skill boundary by construction: one has no
boundary, the other *is* the boundary. Every row, however, converges on a push.

Enforcement today is zero. `tests/test-skill-invocation-chain.sh:142` asserts the
*string* `/wrap-up-session` appears in a SKILL.md; `tests/test-route-skill.sh:32`
asserts a `[ ]` row exists in a playbook file. Both pass for a session that
pushed with no gates run. `.claude/hooks/pre-push-guard.sh:2` is
`# DEPRECATED — no longer registered`.

---

## A — Wrap-Up Push Gate (warn + record, never block)

### Behavior

When `git push` carries code commits that no recorded wrap-up covers, the push
**proceeds** and the gate emits a warning naming the uncovered commits, then
records the gap as wrap-up debt on disk. The debt becomes a tracker issue at the
next session start, through `/task-registry`, with a human present to approve it.

The gate never blocks. A developer mid-work is not interrupted; the omission is
made visible and durable instead of silent.

The check runs from the existing harness-agnostic git hook, so it fires
identically for Claude Code, Pi, Codex, a manual push, and CI — including
sessions that invoked no skill at all.

The evidence already exists on disk and is currently read by nothing:
`/wrap-up-session` Step 2 appends a fingerprinted line to `tasks/todo.md`.

```markdown
## Session Summary — [YYYY-MM-DD] [a1b2c3f..d4e5f6a]
```

The gate reads those ranges. No new artifact, no new schema, no self-report.

### Why the issue is not created by the hook

Two constraints, both verified, forbid the hook from reaching a tracker:

1. **The approval floor is non-relaxable.** `task-registry.py:126` builds a
   `WriteGate` from `config.require_write_approval`, and `:197` reports
   `"configuration asked to drop it; ignored — approval is a floor"`. External
   task creation needs `--apply --approve`. A hook passing `--approve` would be
   self-authorizing an outward-facing write on every push, which is what the
   floor exists to prevent — and `CLAUDE.md` § *Task Tracking* states external
   creation requires explicit authorization.
2. **The hook never invokes `/task-registry`.** It runs on every push, including
   offline and in CI, but its path only detects and records wrap-up debt. With no
   registry invocation, it cannot reach any provider.

So the hook does the part that must be immediate and offline (detect, warn,
record), and the part needing judgement and authorization (file the issue)
happens where a human already is: the session-start banner.

### Inputs

- Git pre-push hook stdin: `<local-ref> <local-sha> <remote-ref> <remote-sha>` per ref.
- `tasks/todo.md` as it exists at `<local-sha>`, read via `git show`, never from
  the working tree — the working tree can differ from what is being pushed.
- Env: `SKIP_WRAPUP_GATE=1` kill switch, matching the existing `SKIP_PREPUSH=1`
  convention in `.agents/git-hooks/pre-push`.

### Outputs

- **Covered push** — exit `0`, silent. Observability Discipline: success is quiet.
- **Uncovered push** — exit `0`, and:
  - stderr: the uncovered short-SHAs, the fix (`run /wrap-up-session`), and the kill switch.
  - `tasks/wrap-up-debt.md`: one entry per uncovered range, keyed on
    `<branch> <first-sha>..<last-sha>`. Re-pushing the same range updates the
    existing entry rather than appending a duplicate.
- **Session start** — `session-start.sh` reads the ledger and prints an
  outstanding-debt line beside the existing learning-store and task counts, with
  the `/task-registry publish` invocation needed to file it.

Exit `0` on the failure path is a deliberate departure from Observability
Discipline's "exit non-zero", recorded here because a reviewer will otherwise
flag it: this gate reports, it does not gate. The ledger is what makes the
report durable rather than a line that scrolls past.

### Contract

Let `C` = commits in `<remote-sha>..<local-sha>` that modify at least one
non-documentation file. Let `S` = the set of commit ranges parsed from every
`## Session Summary — [date] [start..end]` line in `tasks/todo.md` at
`<local-sha>`.

A commit in `C` is **covered** when it is either:
1. contained in the union of `S` (membership via `git rev-list start..end`, plus
   `start` itself), or
2. the commit that *introduced* a session-summary line — the wrap-up commit
   cannot appear inside a range it is in the act of writing.

Every uncovered commit is warned about and recorded. Nothing is ever blocked.

Clause 2 resolves a real chicken-and-egg: wrap-up writes the fingerprint, then
commits, so the range it records necessarily ends before itself.

### Edge Cases

- **No `tasks/todo.md` at `<local-sha>`** → pass silently, record nothing. The
  repo does not use this workflow; the gate must not spam unrelated projects.
- **Documentation-only push** → pass. `*.md`, `LICENSE*`, `.gitignore`, and
  `tasks/**` are non-code. `/auto-improve` findings-only mode depends on this.
- **New branch** (`<remote-sha>` all zeros) → range is `merge-base(HEAD, default-branch)..<local-sha>`.
- **Branch deletion** (`<local-sha>` all zeros) → pass, record nothing.
- **Merge commits** → exempt; they introduce no new authored code.
- **Malformed / unparseable fingerprint** → ignored for coverage, and named on
  stderr. Live example already in this repo: `## Session Summary — 2026-09-01
  [907ac6d..worktree]`, where `worktree` is not a SHA. Strict parsing would warn
  on every push over a formatting slip; lenient parsing would silently treat the
  range as covering everything.
- **Repeat push of the same uncovered range** → ledger entry updated in place,
  never duplicated. Without this the ledger grows one entry per `git push` and
  the session-start line becomes noise people learn to ignore.
- **Force push** → out of scope for this gate. Note: `.agents/git-hooks/pre-push:13-20`
  intends to block force pushes by scanning `"$@"` for `--force`, but git invokes
  the hook as `pre-push <remote-name> <remote-url>` and never passes push flags,
  so that block is dead code and has never fired. Pre-existing defect, discovered
  while extending the hook; recorded here and **not** fixed in this change —
  a force-push guard is a separate concern with its own blast radius.
- **Worktrees** share `--git-common-dir`, so one installed hook covers all of them.

### Deployment (load-bearing — the gate is inert without it)

`install.sh:257` copies `pre-push` into `$GIT_TEMPLATE_DIR/hooks/` only, and
`install.sh:301` sets `init.templateDir`. Git templates apply to repositories
created *after* installation. **Existing repositories never receive the hook** —
verified: this repository has only `pre-push.sample` in its
`--git-common-dir/hooks`, so even the current typecheck/lint gate is not running
here.

Shipping A without fixing this reproduces exactly the failure mode of the
deprecated `pre-push-guard.sh`: a gate that exists and never fires.

### Acceptance Criteria

- [ ] A push of code commits with no covering session summary exits **zero**, names the uncovered short-SHAs on stderr, and writes a ledger entry.
- [ ] A push of code commits fully covered by a session-summary range exits zero and prints nothing.
- [ ] The wrap-up commit that introduces a session-summary line is treated as covered.
- [ ] A documentation-only push passes silently and records nothing.
- [ ] A push in a repository with no `tasks/todo.md` passes silently and records nothing.
- [ ] A new-branch push resolves its range from the merge-base with the default branch.
- [ ] Re-pushing the same uncovered range updates the existing ledger entry instead of appending a duplicate.
- [ ] `SKIP_WRAPUP_GATE=1` bypasses the gate; the existing `SKIP_PREPUSH=1` still bypasses the whole hook.
- [ ] A malformed fingerprint is reported on stderr and neither widens coverage nor suppresses the warning.
- [ ] The hook performs no network calls and invokes no tracker command.
- [ ] `session-start.sh` prints outstanding wrap-up debt with the `/task-registry publish` invocation, and prints nothing when the ledger is empty or absent.
- [ ] `install.sh` installs the hook into the current repository's `--git-common-dir/hooks` when run inside one, not only into the git template dir.
- [ ] `/sync` installs or refreshes the hook in an already-cloned downstream repository.

### Files Likely Involved

- `.agents/git-hooks/pre-push` — extend; the gate lives beside the typecheck/lint gate.
- `tasks/wrap-up-debt.md` — **new**; the ledger. Committed, not gitignored: debt that vanishes on clone is not debt.
- `.claude/hooks/session-start.sh` — surface the ledger beside the existing counts.
- `install.sh:256-259` — also install into the current repo.
- `.agents/skills/sync/SKILL.md` — refresh the hook downstream.
- `tests/test-pre-push-gate.sh` — **new**; no test covers this hook today.
- `.claude/hooks/pre-push-guard.sh` — delete; its header already says "safe to delete", and leaving a second dormant pre-push script next to a live one invites editing the wrong file.

---

## B — Fold `/tdd` into `/build`, then retire it

### Behavior

`/build` reimplements the TDD loop rather than delegating to `/tdd`; the two hold
duplicate doctrine and neither calls the other. `README.md:215` draws a
`delegates to` edge that does not exist in `build/SKILL.md`. The user's default
path is `/build`, and `/tdd`'s only distinct capability — a user checkpoint
between tasks (`tdd/SKILL.md:70-72`) — has no user.

Retire it the way `simplify` and `deslop` were retired: fold the content in
first, keep the label. Precedent lives at `quality-gate/SKILL.md:78`
(`Phase 1 — Structural Quality (simplify)`) and `:108`
(`Phase 2 — AI Anti-Patterns (deslop)`).

### What must survive the fold

`/build`'s entire TDD doctrine is one instruction line (`:136`). `/tdd` carries
what `/build` lacks, and a learning document cites it by line number:

- The Red Flags list — `tdd/SKILL.md:74-88` ("Test written after implementation", "Delete code. Start over with TDD.")
- The 15-row rationalization table — `:90-102`, including "Tests-after ≠ TDD. You get coverage, lose proof."
- The When Stuck table — `:104-111`
- `tdd/testing-anti-patterns.md` → `build/references/`, joining `subagent-resilience.md`

`tasks/solutions/architecture/tdd-enforcement.md:16-17` cites
`.agents/skills/tdd/SKILL.md:77-102`. Deleting the file without repointing the
citation orphans a learning document.

### Reference repointing (all verified present)

| Location | Current | Becomes |
|---|---|---|
| `plan/SKILL.md:188` | "proceed with `/tdd` or begin the TDD loop directly" | `/build` |
| `auto-push/SKILL.md:73` | routes to `/tdd` for supervised TDD | `/build`, or drop the row |
| `project-template/tasks/todo.md:4` | "executed by `/tdd`" — **ships downstream** | `/build` |
| `README.md:215` | `delegates to` → `/tdd` in the diagram | remove the edge |
| `README.md:272` | skills table row | remove |
| `CLAUDE.md:441` | skills table row | remove |
| `.claude/hooks/session-start.sh:383` | banner line | remove |
| `prd/SKILL.md:24`, `brainstorm/SKILL.md:17` | "DO NOT invoke /plan, /build, /tdd" | drop `/tdd` from the list |
| `tasks/solutions/architecture/tdd-enforcement.md:5,16-17` | `module:` + line citation | repoint to `/build` |

### Edge Cases

- **Downstream projects have `/tdd` installed.** `/sync` removes retired skills
  (precedent: the `deslop`/`simplify`/`verify-e2e` removals). Retirement must not
  silently leave a stale copy that still says "or at minimum … commit".
- **`tdd/SKILL.md:129-131`** — "Run `/wrap-up-session` **or at minimum**: … Commit
  with a clear message" — is the repo's only written authorization to commit code
  without wrap-up. It dies with the file and must **not** be carried into `/build`.
- **Both skill trees** — `.agents/skills/tdd/` and `.claude/skills/tdd/` are
  byte-identical; `tests/test-skill-parity.sh` fails if only one is removed.

### Acceptance Criteria

- [ ] `/build` Phase 1 contains the Red Flags list, the rationalization table, and the When Stuck table.
- [ ] `build/references/testing-anti-patterns.md` exists and `/build` links it.
- [ ] No `TODO`-free prose anywhere authorizes committing code without wrap-up (the `:129` escape hatch is gone, not relocated).
- [ ] `grep -rn "/tdd" --include=*.md --include=*.sh .` returns no hit outside `tasks/` history and `specs/`.
- [ ] Both `.agents/skills/tdd/` and `.claude/skills/tdd/` are removed; `tests/test-skill-parity.sh` passes.
- [ ] `tasks/solutions/architecture/tdd-enforcement.md` cites a line range that exists in `build/SKILL.md`.
- [ ] `/sync` removes `tdd/` from a downstream project that still has it.
- [ ] `README.md` architecture diagram has no `delegates to /tdd` edge.
- [ ] Full suite green (`tests/run.sh`).

---

## Non-Goals

- **`/receive-review` standalone.** Its "PR review cycles" entry
  (`receive-review/SKILL.md:216`) writes code outside build and wrap-up. Accepted
  as-is by explicit decision — responding to PR comments is not a session that
  needs a wrap-up. A's push gate covers it anyway if those edits are ever pushed
  as new code commits.
- **`/create-verification-skill`** writing project-local skill scripts without
  build or wrap-up — accepted.
- **`/auto-improve` findings-only mode** committing a docs-only PR outside
  wrap-up — permitted by A's documentation-only exemption.
- **Restoring a supervised-TDD rung.** `/tdd` is retired, not replaced. If
  per-task checkpoints are ever wanted again, that is a `/build` flag, not a
  revived skill.
