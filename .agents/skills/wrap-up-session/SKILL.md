---
name: wrap-up-session
description: Close session with code review, testing, fixes, and a clean commit. Use at the end of any coding session.
---

# /wrap-up-session — Session Wrap-Up

Close out the session by syncing learnings, updating registers, running code review, testing, and pushing changes.

---

## Step 0 — Pre-Flight Check

A completed `routine/fix` investigation escalation is its own terminal:
`references/routines.md` § *Fix-escalation terminal*.

1. Run `git diff --name-only` and `git diff --name-only --cached` to check for uncommitted changes
2. Run `git log --oneline <base-branch>...HEAD` to check for commits on this branch

**If no changes exist** (no uncommitted changes AND no commits beyond base branch):

```
Session wrapped up (no changes).
- No code changes detected this session.
- Skipped: code review, tests, commit, push.
```
Then **run Step 8.5 and STOP**.

Except for the completed fix-routine investigation escalation above, **every
STOP in this skill routes through Step 8.5 first.** That step asserts an
unattended run produced a pull request, and the exits it exists to catch are
exactly the ones that end wrap-up early — so a STOP that jumps straight to the
end skips the check on precisely the runs that need it. This applies to all six
no-PR exits Step 8.5 enumerates; each one names the route again below.

**If changes exist**: proceed normally.

### Base Branch Detection

1. Check for `main`: `git show-ref --verify --quiet refs/heads/main`
2. If not found, check for `master`
3. If not found, check for `develop`
4. If none found: `git merge-base HEAD origin/HEAD`
5. If that also fails: warn the user and ask them to specify

Store the detected base branch as `<base-branch>` for all later steps.

---

## Step 0.5 — Project Context Staleness Check

If `tasks/project-context.md` exists:

1. Compare `package.json` / `pyproject.toml` / `go.mod` against `[ARCHITECTURE]` — new libraries added?
2. Check for new directories or modules not reflected in `[ARCHITECTURE]` or `[CONVENTIONS]`
3. Look for changed patterns via `git diff --name-only <base-branch>...HEAD`

**If divergence found**: auto-update `tasks/project-context.md`, then flag affected PRD sections to the user for optional review.

---

## Step 1 — Capture Learnings

Run `/learn` to extract learnings into typed documents under `tasks/solutions/`
and append the session entry to `tasks/history.md`.

If `/learn` produces no patterns: log "No patterns captured" and continue.
If `/learn` errors: log the error, continue. Learnings are valuable but not blocking.

---

## Step 1.5 — Memory Maintenance

Run `/memory-maintain` (it self-gates on the session count — runs every 5 sessions automatically).

---

## Step 2 — Update Task Register (`tasks/todo.md`)

- Mark completed items `[x]`
- Detect duplicate `## Plan:` headings, orphan unchecked tasks, stale plan blocks
- Read one task's full record only when a decision turns on it — **summary only**
  otherwise:

  ```bash
  python3 .agents/skills/task-registry/scripts/task-registry.py show <task-reference>
  ```

  Do not paste per-task detail into the session summary or the commit message.
  External writes (`upsert --apply`) are a separate, explicitly authorized step —
  wrap-up never creates or closes an external task on its own.
- **On a `routine/` branch**: write the routine's step list into `tasks/todo.md`,
  each skipped step keeping its row with `skip: <reason>` —
  `references/routines.md` § *Step-ledger rows*.
- `tasks/history.md` and `tasks/todo.md` record only facts known **before**
  the push (Decision 7). CI, conflict-repair and deployment outcomes are
  decided after Step 7 pushes, so they are never written here — they land
  only in the PR body's `## Closure` section and the Done report's
  `Closure:` line (§ Done).
- Append session summary with idempotency fingerprint (commit range short-SHAs)
  - **Resolve both endpoints to real short SHAs.** The pre-push wrap-up gate
    validates them as bare hex, so `HEAD` — the obvious thing to write in this
    step, since Step 7 has not committed yet — is rejected, and every commit in
    the push is recorded as uncovered debt. Write the base and the last existing
    commit; the bookkeeping commit that lands this summary touches only
    `tasks/`, which the gate does not count as code.

```markdown
## Session Summary — [YYYY-MM-DD] [a1b2c3f..d4e5f6a]
- Completed: [X tasks]
- Pending: [Y tasks]
- Carry-forward: [brief description]
```

---

## Step 3 — Update Bug Documents (`tasks/solutions/bugs/`)

- New bugs discovered this session get a bug-track document (status `open` in
  the body) — see `/debug`'s bug document template
- Bugs fixed this session: update their document's body status to
  `fixed — [YYYY-MM-DD]`
- Create `tasks/solutions/bugs/` on first write

---

## Step 3.2 — Living Spec Reconciliation

A spec describes the repository's current, tested behavior. This step brings
every spec the session affected back into agreement with the code, before any
gate runs, so each spec edit is committed with the change it documents. The
procedure — outcomes, the semantic-comparison rule, legacy migration, deferred
tasks, the write policy and the report — is
`references/spec-reconcile.md`.

```bash
python3 .agents/skills/wrap-up-session/scripts/spec-reconcile.py discover \
  --base <base-branch> --json
```

Take the change set once, before any spec is written. Give each candidate
exactly one outcome — `updated`, `unchanged` or `deferred` — and record each
`deferred` one through `task-registry.py upsert --derive-id spec-reconciliation`.
If that local record cannot be written, STOP wrap-up and run Step 8.5 before
ending.

---

## Step 3.3 — Changed Verification Map

Classify the session diff, touched specs, and completed task entries. If any
acceptance criterion or bug fix is user-facing:

1. Invoke `/maintain-verification-skill --scope changed` with the session intent,
   base-to-HEAD diff, touched specs, and completed task entries.
2. If no project-local verification skill exists, skip maintenance, recommend
   `/create-verification-skill`, and never generate or launch it automatically.
3. Handle the maintainer outcome: `clean` and `changed` continue; `blocked` STOPS
   wrap-up and reports the maintainer's evidence without committing. Run Step 8.5
   before ending.

Internal-only sessions skip this step silently. This step runs before security,
review, and tests so any verification-map edits are included in every gate.

---

## Step 3.7 — Shortcut Ledger

`AGENTS.md` § *Code Economy* marks deliberate shortcuts with `TODO(shortcut):`
naming a limit and an upgrade path. Collect them so a deferral cannot quietly
become permanent:

```bash
grep -rnE '(#|//|--) ?TODO\(shortcut\):' . \
  --exclude-dir={.git,node_modules,dist,build,vendor} 2>/dev/null || true
```

One line per marker: `<file>:<line> — <limit>. upgrade: <trigger>.` Tag any
marker naming no upgrade path `no-trigger` — those are the ones that rot. Close
with `<N> shortcuts, <M> without a trigger.`

No markers found: print nothing and move on (failure-only reporting, per
`AGENTS.md` § *Observability Discipline*). This step reports only — it never
blocks the commit, and shortcuts are not bugs, so they do not get bug-track
documents in `tasks/solutions/`.

---

## Step 4 — Quality Gate Receipt

`/quality-gate` is the one review pass per diff (AGENTS.md § Review Gate
Taxonomy, Layer 3). Wrap-up dispatches no `code-reviewer`, `critic`,
`security-reviewer` or `software-design-expert-review`, and runs no
`/security-scan` — it reuses the gate's receipt instead of re-reviewing the
same tree.

```bash
python3 .agents/skills/quality-gate/scripts/receipt.py check
```

| Result | Action |
|--------|--------|
| `receipt: valid <GO\|HOLD-approved> <fp8> policy <v>` | Reuse it. Quote `Quality receipt: <verdict> · <fp8> · policy <v>` for the PR body |
| `receipt: stale verdict HOLD` | The gate already reviewed this tree and left a HOLD — see *Approving a HOLD*. Never re-run the gate for it |
| `receipt: stale diff-changed parent <fp> delta <path> ...` | Invoke `/quality-gate --scope <delta paths> --parent <fp>` **once** |
| any other `receipt: stale <reason>` | Invoke `/quality-gate` **once** at full scope |

Never call `/quality-gate` a second time on an unchanged tree. After a re-entry
above, run `receipt.py check` again and read that second result — not the
gate's own report — as the source of truth:

| Second check | Action |
|--------------|--------|
| `valid GO` or `valid HOLD-approved` | Proceed to Step 5.5 |
| `stale verdict HOLD` | *Approving a HOLD* |
| any other `stale <reason>` (a `STOP` verdict included), or the gate reported `Receipt: none` | STOP wrap-up: report the reason, commit nothing. Run Step 8.5 before ending |

**Approving a HOLD.** **Interactive run**: show the receipt's unresolved
findings and ask the human to approve. A yes runs
`receipt.py approve --fingerprint <fp> --by "$(git config user.name)"`, where
`<fp>` is the third field `receipt.py fingerprint` prints (`check` prints no
fingerprint on a stale line), and reports `approve: approved` once it exits 0
— the engine then re-checks the receipt; a no reports
`approve: declined`, which ends the run. **Unattended run** (a routine branch,
or a caller declaring Step 8.5 unattended): never approves — it reports
`approve: declined`, and the HOLD stops the run through Step 8.5.

Spec reconciliation (Step 3.2) still runs before this step, so a reconciled
spec is part of the tree the gate reviewed. Step 6's full suite still runs
unconditionally through `cached-suite.sh` — the receipt's `tests` field is
evidence the gate already recorded, not a substitute for wrap-up's own
pre-push run.

---

## Step 5.5 — Verification Gate

Before tests, verify all claims have direct evidence:
- No premature satisfaction — no "Great!" or "Done!" before verification
- Every code state claim must reference actual command output
- Check that review results are genuinely clean (spot-check with `git diff`)

---

## Step 6 — Run Tests

Discover test commands from `package.json`, `Makefile`, `pyproject.toml`, or `TESTING.md`.

Run in order: lint/typecheck, unit, integration, e2e.

The full suite is the session's one pre-push full run and goes through the
cache: `.agents/skills/build/scripts/cached-suite.sh -- <full-suite command>`,
with the `Full suite:` line below the `AGENTS.md` end marker verbatim, as
`/build` ran it — or, when a project declares none, the exact command `/build`'s
baseline ran, so the key matches. On a tree already proved green it prints
`cached-suite: reused green run` and costs nothing; any edit since runs it for
real. Make every tree edit this wrap-up needs before this run, not after it.

**One suite at a time, no polling.** Launch the full suite as a background
task (`run_in_background` on Claude Code) and wait for its completion
notification. While it runs, do only work that leaves the working tree alone —
drafting the PR body in a scratch file outside the repository — because
`cached-suite.sh` hashed the tree when the run started, and an edit made now
would be pushed without a full run. Never wait in a foreground `sleep` or a
poll loop. `cached-suite.sh` refuses a second full run with exit 3, and the
rule extends to every test run: no test run starts while a suite is running —
no targeted file, no affected-test run — because a test beside a running suite
shares its load, slows both and can fake a failure in either.

**A refusal is not a test result.** Exit 3 with `cached-suite: a suite is
already running` on stderr means nothing ran: never hand it to `code-debugger`
and never count it as a fix attempt. When the running suite is this session's
own background job, wait for its completion notification and run again; when
it belongs to another session or worktree, report the pid and start time the
line names and stop, rather than wait on a job this session cannot see finish.

If tests fail: fix root cause (not workaround), re-run. Max 2 fix attempts; if still failing, report, do not push, and end through Step 8.5.

---

## Step 6.3 — E2E Coverage Gate

For every user-facing AC in specs touched this session:

1. Confirm a `/verify-evidence --scope e2e` walkthrough ran by checking `tasks/e2e-log.md` for an entry matching the spec and current commit short-sha
2. If missing: ask:
   > "AC [ID] is user-facing but has no e2e walkthrough. Run /verify-evidence --scope e2e now, or acknowledge the gap? (run/acknowledge)"
3. On `run`: invoke `/verify-evidence --scope e2e`, then re-check
4. On `acknowledge`: record the gap as a knowledge-track document in `tasks/solutions/process/` (tags: `[e2e-gap]`)

On a `routine/fix/` branch, a blocked walkthrough follows
`references/routines.md` § *E2E handoff on `routine/fix`*.

If no specs were touched, classify the session diff and task evidence so a
user-facing bug fix still enters this gate. Skip silently only when the session
is internal-only.

---

## Step 7 — Commit & Push

### The Closure Loop

From Step 4 on, wrap-up does not decide what happens next by reading this
skill top to bottom — it drives `closure.py`, the pure state machine behind
this loop, and performs exactly the action it names, once per naming:

```bash
python3 .agents/skills/wrap-up-session/scripts/closure.py step \
  --state "$(git rev-parse --path-format=absolute --git-common-dir)/closure/<sanitized branch>.json" \
  --observe '<json observation of the last action>'
# stdout: action <name> [key=value ...]  |  terminal <complete|partial|stopped> ...
```

Perform the named action, turn its result into the observation shape
`closure.py`'s module docstring defines, feed that back on the next call, and
repeat until a `terminal` line. The first call reports Step 4's
`receipt.py check` result, since a fresh state starts in the `receipt` phase.
`<sanitized branch>` is the current branch with every character outside
`A-Za-z0-9_.-` replaced by `-`, the rule `receipt.py` uses for its branch
pointer. A `terminal` line ends the run: the engine records it, and the next
`/wrap-up-session` on the branch starts a fresh run, while a run interrupted
before its terminal line resumes where it stopped. This table maps
each action to the step or section that performs it and the observation it
reports back:

| Action | Performed by | Reports |
|--------|---------------|---------|
| `check-receipt` | Step 4, `receipt.py check` | `receipt: valid` \| `receipt: hold` (on `stale verdict HOLD`) \| `receipt: stale`, `scope: delta\|full` |
| `quality-gate` | Step 4, the `/quality-gate` re-entry | `gate: GO\|HOLD-approved\|HOLD\|STOP\|none` |
| `approve-hold` | Step 4, *Approving a HOLD* | `approve: approved\|declined` (an unattended run always reports `declined`) |
| `run-suite` | Step 6, `cached-suite.sh` | `suite: green\|red\|blocked` |
| `commit-push` | § Commit & Push below | `push: ok` \| `push: non-ff` \| `push: denied` |
| `pr-sync` | § The Pull Request below | `pr: <n>` \| `pr: failed` |
| `mergeability` | `references/closure-actions.md` § *Mergeability* | `mergeable: clean\|conflicting\|unknown` |
| `merge-base` | `references/closure-actions.md` § *Conflict repair* | `merge: resolved\|unresolved` |
| `watch-ci` | `references/closure-actions.md` § *CI watch and repair* | `ci: pass\|none\|fail\|timeout` |
| `debug-ci` | `references/closure-actions.md` § *CI watch and repair* | `debug: fixed\|not-fixed` |
| `verify-deploy` | `references/closure-actions.md` § *Deployment verification* | `deploy: pass\|n/a\|fail` |
| `record-closure` | `references/closure-actions.md` § *Recording the closure* | `record: recorded\|record-failed` |
| `mark-draft` | `references/closure-actions.md` § *Marking a partial PR draft* | `partial: drafted\|draft-failed\|no-pr` |

### Code Review Gate

Step 4's quality receipt is the gate: reaching Step 7 already means it read
`valid GO` or `valid HOLD-approved`. Any other result stopped at Step 4 and
routed through Step 8.5 before this step could run, so there is nothing further
to check here.

### Commit & Push

The `commit-push` action. Hooks stay enabled for every commit this loop
makes, here and in every repair commit — skipping them is never an option,
because the hooks are the gate this whole loop exists to satisfy, not an
obstacle to it.

1. Stage changes: `git add -p` — stage only relevant changes
2. Commit with type prefix: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
3. Append optional trailers: `Constraint:`, `Rejected:`, `Not-tested:`, `Confidence:`
4. Push: `git push -u origin <branch>`
5. Report the observation: `push: ok` on success; `push: non-ff` (with the
   branch name) on a non-fast-forward rejection — the engine routes that to
   `references/closure-actions.md` § *Conflict repair*, never to a rebase; `push: denied` on a permission
   or branch-protection refusal
6. On `push: ok`, open or re-sync the pull request — see *The Pull Request*
   below. That section is the only description of PR creation in this skill,
   and Step 7.5 reaches the same one.

**Do not push if**: any test is failing, uncommitted changes unreviewed, MUST-FIX skipped.

### The Pull Request

The `pr-sync` action, and the single description of PR creation in this
skill. Step 7 above and Step 7.5 below both reach *here* rather than
restating it — this action is irreversible and outward-facing, and it now
carries a conditional (`--draft`) that would eventually be true in one copy
and false in the other. Report `pr: <n>` on success or `pr: failed` when
`gh` is unreachable or the linkage check keeps refusing.

The body carries the `Quality receipt: <verdict> · <fp8> · policy <v>` line
Step 4 produced, and a `## Closure` section reporting what the loop has done
so far — CI, mergeability and deployment outcomes belong there, never in
`tasks/history.md` or `tasks/todo.md` (Decision 7). The linkage check below
still reads the whole body, `## Closure` included, before every create or
re-sync.

#### Routine branches

On a `routine/` branch the flags, the title and the body's issue linkage come
from `references/routines.md` § *Draft and linkage*, read from the branch by
`routine_branch.py parse` (§ *What the branch tells you*), and the body carries
the executed step list (§ *Step-ledger rows*).

**No PR for this branch**: draft the body to a file, with the `## Handovers`
section (`references/closure-actions.md` § *Handovers*); run
`pr_linkage.py check --body-file <draft>` on it and repair what it lists
(`references/closure-actions.md` § *PR re-sync*); then create the PR from that file:

```bash
gh pr create --body-file <draft>   # plus --draft per § Draft and linkage
```

**A PR already exists**: re-sync its body on every push —
`references/closure-actions.md` § *PR re-sync*. Push failures are `references/closure-actions.md` § *Push failures*.

---

## Step 7.5 — Worktree Integration (if applicable)

Runs **after** Step 7, not before it. Merging can only follow committing — the
previous version of this step ran before the commit, so it either found a dirty
tree or merged a branch that did not yet contain the session's work.

If NOT in a git worktree: skip. Otherwise check which flow this repo uses.

**If the work goes through a pull request (default when `origin` exists):**

1. Confirm Step 7 pushed the branch: `git status -sb` shows no `ahead`
2. Open the PR by the procedure in *The Pull Request* (Step 7), or confirm one is
   already open. Do not restate it here — the draft flag and the issue linkage
   have exactly one definition
3. **Stop here. Do not merge locally and do not delete the branch** — an open PR
   whose source branch is gone is a dead PR, and a local merge to `main` bypasses
   the review the PR exists to get
4. Removing the *worktree directory* is fine once pushed
   (`git worktree remove <path>`); the branch must survive until the PR lands

**If the repo merges locally (no remote, or the user asked for a direct merge):**

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

---

## Step 8.5 — Terminal PR Assertion (unattended runs)

Runs last, and **runs even when an earlier gate stopped the run** — the exits
this exists to make loud are exactly the ones that end wrap-up early.

**Scope: unattended runs only.** An **interactive** run is exempt: a human is
watching the transcript, which is the thing this step substitutes for. How a
run is detected as unattended — the branch parser or the caller's declaration
— is `references/routines.md` § *Unattended detection*.

Then:

```bash
gh pr view "$(git branch --show-current)" --json number,url -q .url
```

| Result | Action |
|---|---|
| A pull request exists | **say nothing** beyond the `PR:` line of the Done report |
| No pull request | report loudly, name which exit produced no PR, and **exit non-zero** |
| `gh` itself failed — not installed, not authenticated, no network | report loudly as **UNKNOWN**, quote `gh`'s stderr, and **exit non-zero** |

The third row is the one an assertion usually forgets. `gh pr view` exits
non-zero both for "no such pull request" and for "could not ask", and collapsing
them reports a missing PR that may well exist — a false alarm every night `gh`
is unhappy, which is how a nightly check gets muted. Distinguish them by the
stderr `gh` prints, and never let "could not ask" render as "no PR".

It **says nothing when the pull request exists**. A terminal check that prints on
every green run is one readers learn to skip, and then the loud case is no longer
loud.

### What this does and does not assert

This **does not make every session end in a pull request**, and must not be read
as claiming so. Wrap-up has six documented no-PR exits, every one of them a
legitimate outcome:

| Exit | Where |
|---|---|
| No changes detected | Step 0 |
| Tests still failing after 2 fix attempts | Step 6 |
| The quality receipt is not GO or approved HOLD | Step 4 |
| The push gate refused | Step 7 |
| The local record could not be written | Step 3.2 |
| A `blocked` maintainer outcome | Step 3.3 |

None is removed here. The failure this closes is narrower and worse: an
unattended run that reaches one of them at 03:00, produces nothing, and reports
that to nobody — indistinguishable, the next morning, from a run that worked. The
assertion converts *silence* into a named reason and a non-zero exit; it does not
convert a legitimate stop into a PR.

---

## Done

### Report

```
Session wrapped up.
- Learnings: [N patterns / none]
- Tasks: [X completed, Y pending]
- Bugs: [N opened, N closed / no changes]
- Quality receipt: [<verdict> · <fp8> · policy <v> — reused / <verdict> · <fp8> · policy <v> — re-entered at <full|delta> scope]
- Tests: [PASS — suite name] or [FAIL] or [SKIPPED — no suite]
- E2E coverage: [N user-facing ACs verified / NONE / GAP — N acknowledged]
- Routine: [<name> #N — S steps, K skipped / none — not a routine branch]
- Pushed: [yes / no — reason]
- PR: [#N opened / #N description re-synced — what changed / #N already accurate / #N linkage repaired — <refs> / none]
- Deployments: [results / not applicable — <reason> / SKIPPED / NONE]
- Closure: [complete / partial — <state, reason> / partial — closure engine failed]
- Unattended PR assertion: [PASS / FAILED — no PR, reason / N/A — interactive]
```

The `Closure:` line quotes `closure.py`'s terminal line — its `state=`,
`reason=` and, on a partial run, `draft=` fields (`draft=failed` or
`draft=none` means the PR was not drafted; say so) — rather than restating
them in prose, so the report
cannot drift from what the engine actually decided. When `closure.py`
itself fails after the push (a crash, not a `terminal partial` line), the
commit and PR still exist; report `Closure: partial — closure engine
failed` rather than waiting for a terminal line that will never print
(§ *Failure unit*).

