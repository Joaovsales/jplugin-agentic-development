---
name: wrap-up-session
description: Close the session — learnings, spec reconciliation, the quality-receipt check, the full suite, then a clean commit, push and pull request. Use at the end of any coding session.
---

# /wrap-up-session — Session Wrap-Up

Close the session in five phases, in order:

1. **Bookkeeping** — the no-change exit, learnings, registers, the shortcut ledger.
2. **Reconcile** — spec reconciliation, the changed verification map, E2E coverage.
3. **Gate** — the closure loop starts: the quality receipt, then the full suite.
4. **Ship** — commit and push, the pull request and its closure actions, worktrees.
5. **Done** — the terminal PR assertion and the report.

Every tree edit the session needs happens in Bookkeeping or Reconcile. From Gate
on, `closure.py` names each action and this skill performs it; the only later
edits are the loop's own repairs, each re-checked by the receipt and the suite
before it is pushed. **Every early STOP ends through § *Terminal PR
assertion*** — except a completed `routine/fix` investigation escalation
(`references/routines.md` § *Fix-escalation terminal*). What applies only to a
`routine/` branch or an unattended caller is `references/routines.md`
§ *Wrap-up on a routine branch*.

## Bookkeeping

### No-change exit

`<base-branch>` is the first of `main`, `master`, `develop` that
`git show-ref --verify --quiet refs/heads/<name>` finds, else
`git merge-base HEAD origin/HEAD`; if that fails too, warn and ask the user.
When `git diff --name-only`, `git diff --name-only --cached` and
`git log --oneline <base-branch>...HEAD` all print nothing, report
`Session wrapped up (no changes).` — no code changes, so no review, tests,
commit or push — then run § *Terminal PR assertion* and STOP.

### Learnings

Run `/learn` (typed documents under `tasks/solutions/`, the session entry in
`tasks/history.md`); "No patterns captured" and errors are logged, never
blocking. Then run `/memory-maintain` (it self-gates).

### Task register

- Mark completed items `[x]` in `tasks/todo.md`; detect duplicate `## Plan:`
  headings, orphan unchecked tasks and stale plan blocks.
- Read one task's full record only when a decision turns on it
  (`python3 .agents/skills/task-registry/scripts/task-registry.py show <task-reference>`),
  and paste none into the summary or commit message. External writes
  (`upsert --apply`) are a separate, explicitly authorized step.
- **On a `routine/` branch**: write the routine's step list, each skipped step
  keeping its row with `skip: <reason>` — `references/routines.md`
  § *Step-ledger rows*.
- `tasks/history.md` and `tasks/todo.md` record only facts known **before** the
  push (Decision 7). CI, conflict-repair and deployment outcomes are never
  written here — only in the PR body's `## Closure` section and the report.
- Append `## Session Summary — [YYYY-MM-DD] [a1b2c3f..d4e5f6a]` with `Completed:`,
  `Pending:` and `Carry-forward:` bullets, **both endpoints real short SHAs**: the
  pre-push gate validates bare hex, so `HEAD` is rejected and the push recorded
  as uncovered debt. Write the base and the last existing commit.

### Bug documents and project context

A bug found this session gets a `tasks/solutions/bugs/` document (status `open`,
per `/debug`'s template); a bug fixed this session gets `fixed — [YYYY-MM-DD]`.
If `tasks/project-context.md` exists and the manifests, new directories or
`git diff --name-only <base-branch>...HEAD` diverge from its `[ARCHITECTURE]` or
`[CONVENTIONS]`, update it and flag the affected PRD sections for review.

### Shortcut ledger

List every `TODO(shortcut):` marker (`AGENTS.md` § *Code Economy*) —
`grep -rnE '(#|//|--) ?TODO\(shortcut\):' . --exclude-dir={.git,node_modules,dist,build,vendor}`
— one line each, `<file>:<line> — <limit>. upgrade: <trigger>.`, tagging one with
no upgrade path `no-trigger`, then `<N> shortcuts, <M> without a trigger.` No
markers: print nothing. It never blocks the commit.

## Reconcile

### Spec reconciliation

Bring every spec the session affected back into agreement with the code before
any gate runs, so each spec edit ships with the change it documents. The
procedure is `references/spec-reconcile.md`.

```bash
python3 .agents/skills/wrap-up-session/scripts/spec-reconcile.py discover --base <base-branch> --json
```

Take the change set once, before any spec is written. Give each candidate
exactly one outcome — `updated`, `unchanged` or `deferred` — and record each
`deferred` one through `task-registry.py upsert --derive-id spec-reconciliation`.
If that local record cannot be written, STOP wrap-up and end through
§ *Terminal PR assertion*.

### Changed verification map

If any acceptance criterion or bug fix in the session is user-facing:

1. Invoke `/maintain-verification-skill --scope changed` with the session intent,
   base-to-HEAD diff, touched specs, and completed task entries.
2. With no project-local verification skill, recommend `/create-verification-skill`; never generate or launch it.
3. `clean` and `changed` continue; `blocked` STOPS wrap-up, reports the maintainer's evidence and commits nothing — end through § *Terminal PR assertion*.

### E2E coverage

For every user-facing AC in specs touched this session — or, with none touched,
in the session diff and task evidence, so a user-facing bug fix still enters:

1. Check `tasks/e2e-log.md` for a `/verify-evidence --scope e2e` entry matching the spec and current commit short-sha, then run `python3 .agents/skills/verify-evidence/scripts/e2e_evidence.py check --sha <short-sha>`: an entry it names (a VISUAL PASS without its PNG) counts as missing
2. If missing, ask: "AC [ID] is user-facing but has no e2e walkthrough. Run /verify-evidence --scope e2e now, or acknowledge the gap? (run/acknowledge)"
3. On `run`: invoke `/verify-evidence --scope e2e`, then re-check
4. On `acknowledge`: record the gap as a knowledge-track document in `tasks/solutions/process/` (tags: `[e2e-gap]`)

It runs before the receipt and the suite, which then cover what it writes;
internal-only sessions skip it and the map silently. A blocked walkthrough on
`routine/fix/` follows `references/routines.md` § *E2E handoff on `routine/fix`*.

## Gate

### The closure loop

From here on, wrap-up drives `closure.py`, the pure state machine behind the
loop, and performs exactly the action it names, once per naming:

```bash
python3 .agents/skills/wrap-up-session/scripts/closure.py step \
  --state "$(git rev-parse --path-format=absolute --git-common-dir)/closure/<sanitized branch>.json" \
  --observe '<json observation of the last action>'
# stdout: action <name> [key=value ...]  |  terminal <complete|partial|stopped> ...
```

Feed each result back in the observation shape `closure.py`'s module docstring
defines, until a `terminal` line; a fresh state starts in the `receipt` phase.
`<sanitized branch>` replaces every character outside `A-Za-z0-9_.-` with `-`,
as `receipt.py` does. Which section performs each action, and what it reports,
is `references/closure-actions.md` § *Action map* (rationale:
`specs/quality-receipt-closure.md`).

### Quality receipt

`/quality-gate` is the one review pass per diff (`AGENTS.md` § *Review Gate
Taxonomy*, Layer 3). Wrap-up dispatches no `code-reviewer`, `critic`,
`security-reviewer` or `software-design-expert-review` and runs no
`/security-scan`; it reuses the gate's receipt:
`python3 .agents/skills/quality-gate/scripts/receipt.py check`.

| Result | Action |
|--------|--------|
| `receipt: valid <GO\|HOLD-approved> <fp8> policy <v>` | Reuse it. Quote `Quality receipt: <verdict> · <fp8> · policy <v>` for the PR body |
| `receipt: stale verdict HOLD` | The gate already reviewed this tree and left a HOLD — see *Approving a HOLD*. Never re-run the gate for it |
| `receipt: stale diff-changed parent <fp> delta <path> ...` | Invoke `/quality-gate --scope <delta paths> --parent <fp>` **once** |
| any other `receipt: stale <reason>` | Invoke `/quality-gate` **once** at full scope |

Never call `/quality-gate` a second time on an unchanged tree. After a re-entry,
run `receipt.py check` again and trust that second result, not the gate's report:

| Second check | Action |
|--------------|--------|
| `valid GO` or `valid HOLD-approved` | Proceed to § *Full suite* |
| `stale verdict HOLD` | *Approving a HOLD* |
| any other `stale <reason>` (a `STOP` verdict included), or the gate reported `Receipt: none` | STOP wrap-up: report the reason, commit nothing, and end through § *Terminal PR assertion* |

**Approving a HOLD.** **Interactive run**: show the unresolved findings and ask.
A yes runs `receipt.py approve --fingerprint <fp> --by "$(git config user.name)"`
(`<fp>` is the third field of `receipt.py fingerprint`; `check` prints none on a
stale line) and reports `approve: approved` once it exits 0; a no reports
`approve: declined`, ending the run. **Unattended run**: never approves — it
reports `approve: declined`, and the HOLD ends through § *Terminal PR assertion*.

### Full suite

Every claim quotes real command output, and a `git diff` spot-check confirms
the result — no "Done!" before verification. Run lint/typecheck, unit,
integration and e2e; the full suite is the one pre-push full run and always goes
through `.agents/skills/build/scripts/cached-suite.sh -- <full-suite command>`,
with the `Full suite:` line below the `AGENTS.md` end marker verbatim (with none
declared, the exact command `/build`'s baseline ran, so the key matches). The
receipt's `tests` field does not replace it; a tree already proved green prints
`cached-suite: reused green run` and costs nothing.

**One suite at a time, no polling.** Launch the full suite as a background task
(`run_in_background` on Claude Code) and wait for its completion notification.
While it runs, do only work that leaves the working tree alone — drafting the PR
body in a scratch file outside the repository — because `cached-suite.sh` hashed
the tree when the run started. Never wait in a foreground `sleep` or a poll
loop. It refuses a second full run with exit 3, and no test run starts while a
suite is running — no targeted file, no affected-test run — because a test beside
a running suite shares its load and can fake a failure in either.

**A refusal is not a test result.** Exit 3 with `cached-suite: a suite is
already running` means nothing ran: never hand it to `code-debugger` and never
count it as a fix attempt. Wait for this session's own job to finish and re-run;
for another session's, report the pid and start time and stop. If tests fail,
fix the root cause and re-run. Still failing after 2 fix attempts: report, do
not push, and end through § *Terminal PR assertion*.

## Ship

### Commit and push

The `commit-push` action; hooks stay enabled for every commit the loop makes.

1. Stage only relevant changes (`git add -p`); commit with a type prefix (`feat`,
   `fix`, `refactor`, `docs`, `test`, `chore`) and optional `Constraint:`,
   `Rejected:`, `Not-tested:`, `Confidence:` trailers
2. Push: `git push -u origin <branch>`
3. Report `push: ok`; `push: non-ff` with the branch, which the engine routes to
   `references/closure-actions.md` § *Conflict repair*, never a rebase; or
   `push: denied`. Other failures: `references/closure-actions.md` § *Push failures*
4. On `push: ok`, open or re-sync the pull request — § *The Pull Request*
5. A pre-push gate refusal: report it, never bypass it, and end through § *Terminal PR assertion*

### The Pull Request

The `pr-sync` action, and the single description of PR creation in this skill:
§ *Commit and push* and § *Worktree integration* reach *here* rather than
restate an irreversible action whose `--draft` conditional would drift. Report
`pr: <n>`, or `pr: failed` when `gh` is unreachable or linkage keeps refusing.

The body carries the `Quality receipt: <verdict> · <fp8> · policy <v>` line, a
`## Closure` section for CI, mergeability and deployment outcomes, and the stdout
of `python3 .agents/skills/wrap-up-session/scripts/publish_evidence.py` (the
`## Visual evidence` section; its stderr `evidence:` line goes in the report),
run before the PR is created and on every re-sync — a publish failure never
blocks the PR. On a `routine/` branch the flags, title and issue linkage come
from `references/routines.md` § *Draft and linkage*, with the executed step list.

**No PR for this branch**: draft the body with its `## Handovers` section
(`references/closure-actions.md` § *Handovers*), run `pr_linkage.py check
--body-file <draft>` and repair what it lists (§ *PR re-sync* there), then run
`gh pr create --body-file <draft>` (plus `--draft` per § *Draft and linkage*).

**A PR already exists**: re-sync its body on every push (§ *PR re-sync* there).

### Worktree integration

Runs **after** the push; outside a git worktree, skip. When the work goes
through a pull request (the default with an `origin`), confirm the branch is
pushed and the PR open by § *The Pull Request*, then **stop — no local merge,
no branch deletion**: a PR whose branch is gone is dead, and a local merge
bypasses its review. Removing the worktree directory is fine. A repo that merges
locally follows `references/closure-actions.md` § *Local worktree merge*.

## Done

### Terminal PR assertion

Runs last, and **runs even when an earlier gate stopped the run** — the exits it
exists to make loud are exactly the ones that end wrap-up early. **Scope:
unattended runs only**; an **interactive** run is exempt, because a human is
watching. Detection: `references/routines.md` § *Unattended detection*. Then:

```bash
gh pr view "$(git branch --show-current)" --json number,url -q .url
```

| Result | Action |
|---|---|
| A pull request exists | **say nothing** beyond the `PR:` line of the report |
| No pull request | report loudly, name which exit produced no PR, and **exit non-zero** |
| `gh` itself failed — not installed, not authenticated, no network | report loudly as **UNKNOWN**, quote `gh`'s stderr, and **exit non-zero** |

`gh pr view` fails both for "no such pull request" and for "could not ask"; tell
them apart by `gh`'s stderr, or nightly false alarms get the check muted. It
**says nothing when the pull request exists**, and it **does not make every
session end in a pull request** — it turns *silence* about one of the six
legitimate no-PR exits into a non-zero exit:

| Exit | Section |
|---|---|
| No changes detected | § *No-change exit* |
| The local record could not be written | § *Spec reconciliation* |
| A `blocked` maintainer outcome | § *Changed verification map* |
| The quality receipt is not GO or approved HOLD | § *Quality receipt* |
| Tests still failing after 2 fix attempts | § *Full suite* |
| The push gate refused | § *Commit and push* |

### Report

```
Session wrapped up.
- Learnings: [N patterns / none]
- Tasks: [X completed, Y pending]
- Bugs: [N opened, N closed / no changes]
- Quality receipt: [<verdict> · <fp8> · policy <v> — reused / <verdict> · <fp8> · policy <v> — re-entered at <full|delta> scope]
- Tests: [PASS — suite name] or [FAIL] or [SKIPPED — no suite]
- E2E coverage: [N user-facing ACs verified / NONE / GAP — N acknowledged]
- Evidence: [published <n> to <owner/repo> (+ ` — public repo` when public) / local <n> / none / publish failed]
- Routine: [<name> #N — S steps, K skipped / none — not a routine branch]
- Pushed: [yes / no — reason]
- PR: [#N opened / #N description re-synced — what changed / #N already accurate / #N linkage repaired — <refs> / none]
- Deployments: [results / not applicable — <reason> / SKIPPED / NONE]
- Closure: [complete / partial — <state, reason> / partial — closure engine failed]
- Unattended PR assertion: [PASS / FAILED — no PR, reason / N/A — interactive]
```

`Closure:` quotes `closure.py`'s terminal line — `state=`, `reason=`, and `draft=`
when partial (`failed` or `none`: the PR was not drafted; say so). If `closure.py`
crashes after the push, report `Closure: partial — closure engine failed`.
