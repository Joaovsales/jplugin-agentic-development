# Closure actions

> Performed by `/wrap-up-session` when `closure.py step` names the action.
> Design rationale: `specs/quality-receipt-closure.md`. Each section reports the
> observation `closure.py`'s module docstring defines.

## Action map

Each action `closure.py step` can name, the section that performs it, and the
observation it reports back. Sections of `/wrap-up-session` are cited by name;
the rest are below.

| Action | Performed by | Reports |
|--------|---------------|---------|
| `check-receipt` | `/wrap-up-session` § *Quality receipt*, `receipt.py check` | `receipt: valid` \| `receipt: hold` (on `stale verdict HOLD`) \| `receipt: stale`, `scope: delta\|full` |
| `quality-gate` | `/wrap-up-session` § *Quality receipt*, the `/quality-gate` re-entry | `gate: GO\|HOLD-approved\|HOLD\|STOP\|none` |
| `approve-hold` | `/wrap-up-session` § *Quality receipt*, *Approving a HOLD* | `approve: approved\|declined` |
| `run-suite` | `/wrap-up-session` § *Full suite*, `cached-suite.sh` | `suite: green\|red\|blocked` |
| `commit-push` | `/wrap-up-session` § *Commit and push* | `push: ok` \| `push: non-ff` \| `push: denied` |
| `pr-sync` | `/wrap-up-session` § *The Pull Request* | `pr: <n>` \| `pr: failed` |
| `mergeability` | § *Mergeability* | `mergeable: clean\|conflicting\|unknown` |
| `merge-base` | § *Conflict repair* | `merge: resolved\|unresolved` |
| `watch-ci` | § *CI watch and repair* | `ci: pass\|none\|fail\|timeout` |
| `debug-ci` | § *CI watch and repair* | `debug: fixed\|not-fixed` |
| `verify-deploy` | § *Deployment verification* | `deploy: pass\|n/a\|fail` |
| `record-closure` | § *Recording the closure* | `record: recorded\|record-failed` |
| `mark-draft` | § *Marking a partial PR draft* | `partial: drafted\|draft-failed\|no-pr` |

A `terminal` line ends the run: the engine records it, and the next
`/wrap-up-session` on the branch starts a fresh run, while a run interrupted before its
terminal line resumes where it stopped.

## Handovers

When the branch's `## Plan:` block carries `> Handover:` blockquotes, the PR
body gains a `## Handovers` section: one `### Slice n/N — <name>` heading per
slice, followed by that slice's whole blockquote verbatim — the `> Handover:`,
`> Do not re-derive:`, `> Surface:` and `> Open:` lines `/build` § Slice Close
defines. Write this section
before the linkage check below runs on the body — the check has to read the
body as it will actually ship. With no tracker to host a PR, the same
section lands in the commit message instead.

## Issue linkage

When a PR resolves several issues, the body repeats the keyword per issue —
`Closes #A, closes #B` — rather than trailing the rest after a single keyword.
GitHub binds a closing keyword to the one reference that immediately follows
it: `Closes #A, #B` links only the first reference and leaves the rest as
plain mentions, so they stay open after merge with nothing reporting it. The
linkage check in § *PR re-sync* catches the failing form before
the body is written.

## PR re-sync

Creating a PR writes the description once, from the branch as it stood at
that moment. Every later commit can falsify it — a follow-up session, a review fix, a
resolved deferral — and nothing re-reads it. The body is what reviewers act on, so
a stale one is not cosmetic: a PR whose notes still list a defect as "deferred" is
asking for review of work that no longer exists.

Both paths below run the **linkage check** on the body they are about to trust.
It prints every reference that no closing keyword reaches, one per line, and
exits 3; exit 0 prints nothing. Any other exit — 2 is a usage error, 1 a crash
— is the script failing, not a clean body. A listed reference is a claim to
rewrite: repeat the keyword before it, and report `linkage repaired` on the
`PR:` line of `/wrap-up-session` § *Report*.

**No PR for this branch** → `/wrap-up-session` § *The Pull Request* owns
creation; the check it runs on the draft body is:

```bash
python3 .agents/skills/wrap-up-session/scripts/pr_linkage.py check --body-file <draft>
```

**A PR already exists** → reconcile the body against the branch before reporting done:

1. Read it: `gh pr view <n> --json body -q .body`, and run the check on what
   comes back **whether or not anything else looks stale** — an open PR whose
   only defect is a keyword that reaches one reference is exactly the case
   this catches, and it would otherwise take the "already accurate" path:
   `gh pr view <n> --json body -q .body | python3 .agents/skills/wrap-up-session/scripts/pr_linkage.py check`.
   Then list every factual claim —
   counts (files changed, tests, assertions) and every item marked deferred,
   known-gap, unresolved, or not-yet-done.
2. Check each against the branch now. `git log <sha-when-body-was-written>..HEAD`
   names what landed since; anything a later commit resolved is now false.
3. Rewrite every claim that no longer holds.

**Correct, do not erase.** When a later commit resolved something the body called
deferred, say so and name the commit — do not silently delete the bullet. A
reviewer who read the earlier version needs to see what changed, and a description
edited to look as though the gap never existed hides the decision that mattered.
Same rule as a commit that fixes an earlier commit: the history stays visible.

This runs on **every** push to a branch with an open PR, including a
`/wrap-up-session` run that adds a single commit. Report the outcome on the `PR:`
line of the Done report — a sync step with no visible result is one that silently
stops happening.

## Push failures

| Failure | Action |
|---------|--------|
| Network error | Retry up to 4 times with backoff (2s, 4s, 8s, 16s) |
| Non-fast-forward | Report `push: non-ff` to the closure loop, which merges (never rebases) the remote branch — see § *Conflict repair* |
| Permission denied | Report to user — do not retry |
| Branch protection | Report to user — do not retry |

## Mergeability

The `mergeability` action, run once the PR exists: `gh pr view <n> --json
mergeable`. `MERGEABLE` reports `mergeable: clean`. `CONFLICTING` reports
`mergeable: conflicting` with the PR's base branch, which the engine routes
to § *Conflict repair* below. `UNKNOWN` is re-queried up to 3 times inside this
action before it gives up and reports `mergeable: unknown` — GitHub has not
finished computing it, not a real conflict. A branch that is merely behind
its base (`mergeStateStatus: BEHIND`) is not a trigger (Decision 9): the
`mergeable` field still reads `MERGEABLE`, and CI watch proceeds.

## CI watch and repair

The `watch-ci` action: `gh pr checks <n> --watch --required` as a background
task (`run_in_background` on Claude Code — never a foreground `sleep` or poll
loop; wait for its completion notification like `/wrap-up-session` § *Full suite*). When the PR
declares no required checks, watch all of them instead: `gh pr checks <n>
--watch`. Budget 30 minutes; past it, report `ci: timeout`.

The push just landed, so checks may not be registered yet. Give the push a
2-minute registration window before deciding there are none: report `ci:
none` only when that window saw no checks running **and** no
`.github/workflows/*` file triggers on `pull_request`. Otherwise, no checks
within the window is a `ci: timeout`, not a `ci: none` — a workflow that
exists but is slow to start is still expected to run.

All checks green (or none, per the rule above) reports `ci: pass`. A failing
required check reports `ci: fail` with the failing check names.

The `debug-ci` action runs on `ci: fail` with rounds left (2 total): fetch
the failing run's log, `gh run view <run-id> --log-failed`, and hand it to
`/debug`. The fix re-enters `/wrap-up-session` § *Quality receipt* (`check-receipt`) and
`/wrap-up-session` § *Full suite* (`run-suite`) before the next push — the same gates every other commit passes, so a repair
commit is never smuggled past the receipt or the suite. Report `debug: fixed`
once the fix is committed — the engine then routes it through
`check-receipt`, `run-suite` and `commit-push`, so this action never pushes
itself — or `debug: not-fixed` when the round is
spent without a passing push.

**Every repair commit adds a `## Session Summary — <date> [<a>..<b>] —
closure repair <n>` line to `tasks/todo.md` in that same commit.**
`.agents/git-hooks/pre-push`'s `introduces_summary` check recognizes that
line and counts the commit covered, so a CI repair never turns into an entry
in `tasks/wrap-up-debt.md`.

## Conflict repair

The `merge-base` action, entered from a `push: non-ff` or a `mergeable:
conflicting` observation, for at most 1 round: `git merge origin/<base>` (a
conflicting mergeability) or `git merge origin/<branch>` (a non-fast-forward
push) — **never `rebase`, never `--force` or `--force-with-lease`**. This
repository does not rewrite history that may already be on someone else's
machine (Constraint *No history rewrite*).

Resolve every conflict and commit the merge; report `merge: resolved`, which
re-enters `/wrap-up-session` § *Quality receipt* so the merged tree gets checked before
the next push. A
conflict that cannot be resolved in this round is aborted —
`git merge --abort` — and reported as `merge: unresolved`, which ends the run
(stopped while no PR exists, partial with the PR drafted after) rather than
leaving a half-resolved merge in the tree.

## Deployment verification

The `verify-deploy` action, entered once `watch-ci` reports `ci: pass` or a
registration-checked `ci: none`.

**A `## Deployment Targets` row applies to the pushed branch** — the section
below the `AGENTS.md` end marker (or, until `/sync` moves it, still in
`.claude/project.md`, which `/verify-evidence` reads second with a one-line
notice, Claude Code only), matched by `^## Deployment Targets[[:space:]]*$`:
run `/verify-evidence --scope deployment` to poll, fetch logs on failure, and
loop a `code-debugger` fix cycle up to 3 iterations, and record its evidence.

That skill may push its own fix commit, so compare the head it leaves
against the head this loop pushed: `git rev-parse HEAD` differing from the
pushed head is `head-moved: true`, matching it is `head-moved: false`.
Report `deploy: pass` or `deploy: fail` with that flag.

**Accepted exception.** `head-moved: true` re-enters
`/wrap-up-session` § *Quality receipt* (`check-receipt`) at most once — `closure.py` counts it in
`deploy_reentries`. For the length of one deployment fix the remote holds a
tree no receipt covers, and the very next action gates it, so the gap never
outlives that single re-entry. A second `head-moved: true` after the
re-entry is spent ends the run `partial` (`mark-draft`).

**No target applies, or `--skip-deploy` was passed**: report `deploy: n/a`
with a one-line reason — `--skip-deploy`, no `## Deployment Targets`
section, or no row matching the pushed branch — recorded in the Done report
as `Deployments: not applicable — <reason>`. With no section, also scan
`tasks/deployments/*.md` for signal files; when any exist, nudge the user to
run `/setup-deployment`.

## Recording the closure

The `record-closure` action, entered once `deploy` reports `pass` (with
`head-moved: false`) or `n/a`. Re-sync the PR body's `## Closure` section
(`/wrap-up-session` § *The Pull Request*) with every outcome the loop now knows — the CI
result, conflict-repair rounds, the deployment result or its
not-applicable reason, and the `Quality receipt:` line from `/wrap-up-session` § *Quality receipt*,
unchanged:

```bash
gh pr edit <n> --body-file <redrafted body>
```

Report `record: recorded` on success, `record: record-failed` when `gh`
refuses. `tasks/history.md` and `tasks/todo.md` (`/wrap-up-session` § *Task register*) record only facts
known before the push (Decision 7) — CI, conflict and deployment outcomes
are never written there; they live only in the PR body's `## Closure`
section and the report's `Closure:` line.

## Marking a partial PR draft

The `mark-draft` action, entered on every non-`complete` end once a PR is
open (`pr_open: true`):

```bash
gh pr ready <n> --undo
```

Report `partial: drafted` on success, `partial: draft-failed` when `gh`
refuses, or `partial: no-pr` when no PR exists to draft. A partial run
never leaves a ready PR behind.

## Local worktree merge

`/wrap-up-session` § *Worktree integration*, when the repo merges locally (no remote, or the
user asked for a direct merge):

1. Verify clean: `git status --porcelain` empty
2. Switch to the parent worktree, `git pull --ff-only`
3. `git merge --no-ff <branch>`
4. Run the **full** suite on the merged result, through
   `.agents/skills/build/scripts/cached-suite.sh -- <full-suite command>` — this is
   the first time these two lines of history have coexisted, so a green run on
   either side proves nothing about the merge; the merged tree is new, so the
   cache runs it for real
5. Green → `git worktree remove <path>` and delete the branch
6. Red → keep both, report the failures, change nothing else

**Conflicts.** Expect them in `tasks/*.md` — the append-only registers are
touched by nearly every session and are a bigger conflict source than source
code. A `.gitattributes` with `merge=union` on those files removes the mechanical
conflict but not the semantic one: two sessions that each allocate the next
`BUG-NNN` produce duplicate IDs with no marker to catch it. After merging, scan
the register for repeated IDs before trusting it.
