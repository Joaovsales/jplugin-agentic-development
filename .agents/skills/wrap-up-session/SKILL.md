---
name: wrap-up-session
description: Close session with code review, testing, fixes, and a clean commit. Use at the end of any coding session.
---

# /wrap-up-session — Session Wrap-Up

Close out the session by syncing learnings, updating registers, running code review, testing, and pushing changes.

---

## Step 0 — Pre-Flight Check

If a `routine/fix/` caller supplies a completed investigation escalation result,
preserve that non-zero terminal result and STOP: open no PR, write no PR ledger,
and do not repeat the registry command. Do not run Step 8.5; the escalation is
already the retained, loud no-PR result. This exception applies only to the fix
routine's investigation path. Interactive wrap-up and deployment verification
keep their existing contracts.

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
- **On a `routine/` branch**: write the routine's executed step list into
  `tasks/todo.md`, one row per mandatory step. A step that could not run **keeps
  its row**, carrying `skip: <reason>` — retained, never deleted. Silent omission
  is the one thing that is never allowed here, because a deleted row reads as a
  routine that never had that gate, and an absent gate leaves no trace in the
  diff a reviewer reads. The same list goes in the PR body (Step 7). Step lists
  are in `.agents/skills/wrap-up-session/references/routines.md` § *Step ledger*.
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

A spec describes the repository's **current, tested behavior**. Git history keeps
the earlier intent, so a reader should never have to reconcile historical
amendments or a stale implementation plan to learn what the code does now. This
step is what makes that true: it brings every spec the session actually affected
back into agreement with the code, and commits the spec edit atomically with the
change it documents.

It runs **after** the task register (Step 2) so completed task intent is
available, and **before** verification-map maintenance, security, review, and
tests (Steps 3.3 onward) so every spec edit passes through all of them.

### Discover candidates

```bash
python3 .agents/skills/wrap-up-session/scripts/spec-reconcile.py discover \
  --base <base-branch> --json
```

When discovery selects something surprising, `changeset` prints the same snapshot
without the matching step, which separates "the change set is wrong" from "the
patterns are wrong":

```bash
python3 .agents/skills/wrap-up-session/scripts/spec-reconcile.py changeset \
  --base <base-branch>
```

Each candidate arrives with `spec`, `source`, `reasons`, and ready-to-use
`evidence` lines. Pass those `evidence` strings through **verbatim** when a
candidate defers — the script owns their shape, so retyping them is how the two
drift apart.

The script captures one immutable change set — committed `<base>...HEAD`, staged,
and unstaged, with both endpoints of a rename and the old path of a deletion —
and returns every spec that change set selects, with the reason for each match.
It is taken **once, before any spec is written**: a change set re-derived
afterwards would contain this step's own edits.

Discovery is deterministic and ordered:

1. the spec named by the completed plan's `> Spec:` line, whether or not it
   carries path metadata;
2. specs whose `implementation_paths` frontmatter intersects the change set;
3. legacy specs, through their `## Files Likely Involved` section;
4. deduplicated, with every match reason retained.

Paths inside `specs/` are excluded from matching, so the step cannot select its
own output. **Invalid or unsafe metadata exits non-zero naming the spec and the
value** — it is never ignored and never treated as "no match", because a
pattern that matches nothing is indistinguishable from a spec nobody touched.

### Assign an outcome

A path match is a *candidate*, not a verdict. For each candidate, read the
relevant diff, the full affected code flow, its callers, and the deterministic
tests, then assign **exactly one outcome**:

| Outcome | When | Action |
|---------|------|--------|
| `updated` | observable behavior or the current implementation surface changed | rewrite the affected contract sections and refresh path metadata |
| `unchanged` | the path changed but the spec's behavior and surface remain accurate | **leave the file byte-identical** |
| `deferred` | the behavioral effect cannot be determined from repository evidence | leave the spec unchanged, persist a reconciliation task (below), continue |

The comparison is **semantic rather than keyword-based**. Formatting-only
changes, internal refactors with no contract or surface change, and edits to a
shared file unrelated to this spec all produce `unchanged`. Grepping the diff for
words that appear in the spec is not this step: it rewrites specs that did not
change and misses the ones that did.

For `updated`, trace the **complete current feature flow** rather than copying
paths out of the diff, then replace stale metadata with the smallest accurate set
of paths covering that surface. This is what repairs old mappings when files move
or new implementation paths appear.

Updated prose describes behavior directly. It **must not mention the session**,
the diff, the fact that an update occurred, or the behavior it supersedes. That
history belongs in Git, and a spec carrying it becomes a changelog that rots on
the next commit.

### Migrate a legacy spec, but only when it changed

When a candidate **without** metadata is `updated`:

1. add valid `implementation_paths` frontmatter;
2. replace `## Files Likely Involved` with `## Implementation Paths`;
3. rewrite prospective descriptions into current factual ones;
4. convert Acceptance Criteria checkboxes into ordinary bullets;
5. leave unrelated accurate content intact.

An `unchanged` legacy candidate is **not** rewritten merely to migrate its
format. Migration rides on behavioral change so the diff stays readable —
reformatting a spec in the same commit that alters it would bury the part a
reviewer needs to see.

### Persist deferred work

An uncertain behavioral effect is **documentation debt, not a wrap-up blocker**.
For each `deferred` candidate, record one durable task through `/task-registry`
before continuing — workflow code never calls the tracker itself:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert --apply \
  --derive-id spec-reconciliation --spec <spec-path> \
  --title 'Reconcile <spec> with current <area> behavior' \
  --kind research \
  --summary '<the behavior question repository evidence could not resolve>' \
  --evidence '<each selected-by: line from the candidate, verbatim>' \
  --evidence 'inspected: <what was read>' \
  --evidence 'missing: <what was not available>' \
  --evidence 'revision: <branch> @ <short-sha>' \
  --criterion 'Determine the current behavior' \
  --criterion 'Update <spec> and its implementation_paths to match' \
  --criterion 'Add deterministic coverage where the gap came from a missing test'
```

**Use `--derive-id`, never a hand-typed ID.** The ID is
`spec-reconciliation.<normalized-spec-path>`, derived from the **complete**
repository-relative spec path so each spec has at most one live reconciliation
task. Both `spec-reconciliation.feature-c` and
`spec-reconciliation.specs-feature-c-md` are *valid* IDs, so a hand-typed one
that normalizes differently mints a second task instead of updating the first —
silently, and only on the second session. `--derive-id` computes it from the
`--spec` path you already have, which makes that mismatch unrepresentable.

A recurring unresolved change updates that task with new evidence; if it had been
completed, the new uncertainty **reopens** it. Re-running wrap-up over the same
change set is therefore idempotent.

Where the canonical body lands follows the project's **existing** write policy —
this step never widens it:

| Situation | Result |
|-----------|--------|
| No tracker configured | the local Markdown record is canonical |
| External provider and its policy already permits unattended writes | the external issue is the record; the index links it |
| Approval required and not given, or provider unreachable | the local record stays canonical, and **publication is pending** |

In the last case wrap-up **does not pause or fail**. Pausing would hang an
unattended run, and publishing anyway would breach the policy the project set;
keeping the work locally and reporting the pending publication loses neither.

If the local record itself cannot be written, **STOP wrap-up: the documentation
debt would otherwise be lost** — which is the one thing this step exists to
prevent. Run Step 8.5 before ending.

The **PR description** lists every deferred reconciliation task, so a reviewer
sees that the affected spec was deliberately left alone rather than missed.

### Report

```text
Spec reconciliation: 5 candidates, 2 updated, 2 unchanged, 1 deferred
Candidates: specs/feature-a.md, specs/feature-b.md, specs/feature-c.md, specs/feature-d.md, specs/feature-e.md
Updated:    specs/feature-a.md, specs/feature-b.md
Unchanged:  specs/feature-d.md, specs/feature-e.md
Deferred:   spec-reconciliation.specs-feature-c-md (tasks/details/spec-reconciliation.specs-feature-c-md.md)
```

Every category that has members is listed by path, `unchanged` included. Naming
what was compared and found accurate is the only trace the cheapest outcome
leaves: a reviewer who cannot see which specs were examined cannot tell a
deliberate `unchanged` from a comparison that never happened. Bound each line at
20 paths, then a count.

No candidates is a **successful outcome** and stays one line. So is all-unchanged — but it still names the specs it compared.

Updated specs then join the code in the verification, security, review, test,
commit, and push gates that follow — and a **failing gate blocks both**. A spec
committed while the code it documents was rejected would publish a description of
behavior that does not exist, which is worse than the stale spec it replaced.

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
fingerprint on a stale line), then re-checks; a no stops as above. **Unattended
run** (a routine branch, or a caller declaring Step 8.5 unattended): never
approves — the HOLD stops the run through Step 8.5.

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

On a `routine/fix/` branch, if `/verify-evidence --scope e2e` returns a structured blocked
outcome, return its exact command, evidence, and reproduction state to `/debug`'s
§ *Canonical unattended escalation owner*. That owner invokes the registry once;
the escalation is terminal for this run, so do not offer acknowledgement or
continue to the PR assertion.

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
pointer. This table maps
each action to the step or section that performs it and the observation it
reports back:

| Action | Performed by | Reports |
|--------|---------------|---------|
| `check-receipt` | Step 4, `receipt.py check` | `receipt: valid` \| `receipt: stale`, `scope: delta\|full` |
| `quality-gate` | Step 4, the `/quality-gate` re-entry | `gate: GO\|HOLD-approved\|HOLD\|STOP\|none` |
| `run-suite` | Step 6, `cached-suite.sh` | `suite: green\|red\|blocked` |
| `commit-push` | § Commit & Push below | `push: ok` \| `push: non-ff` \| `push: denied` |
| `pr-sync` | § The Pull Request below | `pr: <n>` \| `pr: failed` |
| `mergeability` | § Mergeability below | `mergeable: clean\|conflicting\|unknown` |
| `merge-base` | § Conflict Repair below | `merge: resolved\|unresolved` |
| `watch-ci` | § CI Watch and Repair below | `ci: pass\|none\|fail\|timeout` |
| `debug-ci` | § CI Watch and Repair below | `debug: fixed\|not-fixed` |
| `verify-deploy` | Step 8 — Deployment Verification | `deploy: pass\|n/a\|fail` |
| `record-closure` | § Done, *Recording the closure* | `record: recorded\|record-failed` |
| `mark-draft` | § Done, *Marking a partial PR draft* | `partial: drafted\|draft-failed\|no-pr` |

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
   *Conflict Repair* below, never to a rebase; `push: denied` on a permission
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

#### What the branch tells you

A routine encodes the routine name and the issue number in the branch, under a
reserved namespace, because this step runs in a context that never saw the issue:

```bash
python3 .agents/skills/wrap-up-session/scripts/routine_branch.py parse "$(git branch --show-current)"
```

Exit 0 prints `<routine> <issue>`. **Exit 3** means the branch is **outside the
`routine/` namespace** — no routine, no issue, and wrap-up behaves exactly as it
does today. That is the ordinary case and not an error; the convention is opt-in
by shape, so no existing workflow changes behavior.

Treat only 3 that way. Any other non-zero code is the script failing to run, and
reading that as "not a routine branch" is how a routine silently ships a PR with
no `Closes #N` and no `--draft`. The full contract, including
each routine's mandatory step list, is
`.agents/skills/wrap-up-session/references/routines.md`.

#### Draft, and issue linkage

| Branch | Flags | Title | Body carries |
|---|---|---|---|
| `routine/plan/<n>-<slug>` | `--draft` | conventional | `Refs #N` |
| `routine/janitor/<YYYYMMDD>-sweep` | none | `chore(sweep): janitor <YYYY-MM-DD>` (`— clean` suffix when nothing was filed) | step ledger, the record path `tasks/sweeps/<YYYY-MM-DD>-janitor.md`, and `Refs #N` for **every** issue in the record's *Filed* section — never `Closes` |
| `routine/architect/<YYYYMMDD>-sweep` | none | `chore(sweep): architect <YYYY-MM-DD>`, same suffix rule | as `janitor`, with the record at `tasks/sweeps/<YYYY-MM-DD>-architect.md` |
| `routine/tidy/<YYYYMMDD>-sweep` | none | `chore(tidy): <YYYY-MM-DD>` (`— clean` suffix only when nothing was filed **and** no Tier 0 repair was committed) | as `janitor`, with the record at `tasks/sweeps/<YYYY-MM-DD>-tidy.md` and the Tier 0 repair commits listed by check name |
| any other `routine/<name>/<n>-<slug>` | none | conventional | `Closes #N` |
| outside `routine/` | none | conventional | whatever the session warrants |

When a PR resolves several issues, the body repeats the keyword per issue —
`Closes #A, closes #B` — rather than trailing the rest after a single keyword.
GitHub binds a closing keyword to the one reference that immediately follows
it: `Closes #A, #B` links only the first reference and leaves the rest as
plain mentions, so they stay open after merge with nothing reporting it. The
linkage check in § *Creating and re-syncing* catches the failing form before
the body is written.

A producer branch's number is a **run stamp** (`YYYYMMDD`), not an issue. It is
never looked up as one, so the "issue is missing or closed" report below does
not apply to it; the issues a producer PR references are the ones the session
record's *Filed* section lists, read from that file. When the record says
`Filed: none`, the body carries no `Refs` line and says so.

`--draft` is passed **when and only when the routine is `plan`**. A plan is a
proposal, so it opens as a draft; every other routine ends at a ready PR because
human review *is* the gate that the deleted policy lattice tried to compute.

The body carries the linkage and the tracker closes the issue **on merge**. No
step here closes an issue itself: that keeps the provider coupling guard intact
so every tracker keeps working, removes "PR created but close failed" as a
failure mode,
and stops an abandoned PR from leaving a closed issue with no fix. `plan` uses
`Refs #N` rather than `Closes #N` precisely so a merged plan leaves the issue
open for the routine that builds it.

**If the branch is a routine branch but the issue is missing or closed**: report
it loudly, non-zero, naming the issue — and **open the PR anyway**. A bad link
must not discard the session's work.

The routine's executed **step list** goes in the body, the same list Step 2 wrote
to `tasks/todo.md` — every mandatory step, and every skipped one retained with
`skip: <reason>`. See § *Step ledger* in the contract for each routine's list.

#### Handovers

When the branch's `## Plan:` block carries `> Handover:` blockquotes, the PR
body gains a `## Handovers` section: one `### Slice n/N — <name>` heading per
slice, followed by that slice's whole blockquote verbatim — the `> Handover:`,
`> Do not re-derive:`, `> Surface:` and `> Open:` lines `/build` § Slice Close
defines. Write this section
before the linkage check below runs on the body — the check has to read the
body as it will actually ship. With no tracker to host a PR, the same
section lands in the commit message instead.

#### Creating and re-syncing

`gh pr create` writes the description once, from the branch as it stood at that
moment. Every later commit can falsify it — a follow-up session, a review fix, a
resolved deferral — and nothing re-reads it. The body is what reviewers act on, so
a stale one is not cosmetic: a PR whose notes still list a defect as "deferred" is
asking for review of work that no longer exists.

Both paths below run the **linkage check** on the body they are about to trust.
It prints every reference that no closing keyword reaches, one per line, and
exits 3; exit 0 prints nothing. Any other exit — 2 is a usage error, 1 a crash
— is the script failing, not a clean body. A listed reference is a claim to
rewrite: repeat the keyword before it, and report `linkage repaired` on the
`PR:` line of the Done report below.

**No PR for this branch** → draft the body to a file, run the check on the
draft, repair what it lists, then create the PR from that file:

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

#### Mergeability

The `mergeability` action, run once the PR exists: `gh pr view <n> --json
mergeable`. `MERGEABLE` reports `mergeable: clean`. `CONFLICTING` reports
`mergeable: conflicting` with the PR's base branch, which the engine routes
to *Conflict Repair* below. `UNKNOWN` is re-queried up to 3 times inside this
action before it gives up and reports `mergeable: unknown` — GitHub has not
finished computing it, not a real conflict. A branch that is merely behind
its base (`mergeStateStatus: BEHIND`) is not a trigger (Decision 9): the
`mergeable` field still reads `MERGEABLE`, and CI watch proceeds.

#### CI Watch and Repair

The `watch-ci` action: `gh pr checks <n> --watch --required` as a background
task (`run_in_background` on Claude Code — never a foreground `sleep` or poll
loop; wait for its completion notification like Step 6's suite). When the PR
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
`/debug`. The fix re-enters Step 4 (`check-receipt`) and Step 6 (`run-suite`)
before the next push — the same gates every other commit passes, so a repair
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

#### Conflict Repair

The `merge-base` action, entered from a `push: non-ff` or a `mergeable:
conflicting` observation, for at most 1 round: `git merge origin/<base>` (a
conflicting mergeability) or `git merge origin/<branch>` (a non-fast-forward
push) — **never `rebase`, never `--force` or `--force-with-lease`**. This
repository does not rewrite history that may already be on someone else's
machine (Constraint *No history rewrite*).

Resolve every conflict and commit the merge; report `merge: resolved`, which
re-enters Step 4 so the merged tree gets checked before the next push. A
conflict that cannot be resolved in this round is aborted —
`git merge --abort` — and reported as `merge: unresolved`, which ends the run
(stopped while no PR exists, partial with the PR drafted after) rather than
leaving a half-resolved merge in the tree.

### Push Failure Handling

| Failure | Action |
|---------|--------|
| Network error | Retry up to 4 times with backoff (2s, 4s, 8s, 16s) |
| Non-fast-forward | Report `push: non-ff` to the closure loop, which merges (never rebases) the remote branch — see § Conflict Repair |
| Permission denied | Report to user — do not retry |
| Branch protection | Report to user — do not retry |

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

## Step 8 — Deployment Verification

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

**Accepted exception.** `head-moved: true` re-enters Step 4
(`check-receipt`) at most once — `closure.py` counts it in
`deploy_reentries`. For the length of one deployment fix the remote holds a
tree no receipt covers, and the very next action gates it, so the gap never
outlives that single re-entry. A second `head-moved: true` after the
re-entry is spent ends the run `partial` (`mark-draft`).

**No target applies, or `--skip-deploy` was passed**: report `deploy: n/a`
with a one-line reason — `--skip-deploy`, no `## Deployment Targets`
section, or signal files found under `tasks/deployments/*.md` naming
`/setup-deployment` — recorded in the Done report as `Deployments: not
applicable — <reason>`.

---

## Step 8.5 — Terminal PR Assertion (unattended runs)

Runs last, and **runs even when an earlier gate stopped the run** — the exits
this exists to make loud are exactly the ones that end wrap-up early.

**Scope: unattended runs only.** An **interactive** run is exempt: a human is
watching the transcript, which is the thing this step substitutes for. A run is
unattended when either holds:

```bash
# 1. The branch is a routine branch. Exit 0 means yes; exit 3 means no.
#    `routine/` is a prefix, but only the parser knows which names under it are
#    real -- `routine/plna/90-x` is nobody's branch, and matching the prefix
#    would read it as a routine run.
python3 .agents/skills/wrap-up-session/scripts/routine_branch.py \
  parse "$(git branch --show-current)"
```

2. The caller declared it. `/yolo` and `/auto-push` each carry a
   **Step 8.5 — unattended** row in the override table they pass to this skill.
   Their branches are ordinary feature branches, so nothing about the branch name
   says a human stopped watching; only the caller knows, so only the caller can
   say.

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

### Recording the closure

The `record-closure` action, entered once `deploy` reports `pass` (with
`head-moved: false`) or `n/a`. Re-sync the PR body's `## Closure` section
(§ *The Pull Request*) with every outcome the loop now knows — the CI
result, conflict-repair rounds, the deployment result or its
not-applicable reason, and the `Quality receipt:` line from Step 4,
unchanged:

```bash
gh pr edit <n> --body-file <redrafted body>
```

Report `record: recorded` on success, `record: record-failed` when `gh`
refuses. `tasks/history.md` and `tasks/todo.md` (Step 2) record only facts
known before the push (Decision 7) — CI, conflict and deployment outcomes
are never written there; they live only in the PR body's `## Closure`
section and the `Closure:` line below.

### Marking a partial PR draft

The `mark-draft` action, entered on every non-`complete` end once a PR is
open (`pr_open: true`):

```bash
gh pr ready <n> --undo
```

Report `partial: drafted` on success, `partial: draft-failed` when `gh`
refuses, or `partial: no-pr` when no PR exists to draft. A partial run
never leaves a ready PR behind.

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

The `Closure:` line quotes `closure.py`'s terminal line — its `state=` and
`reason=` fields — rather than restating them in prose, so the report
cannot drift from what the engine actually decided. When `closure.py`
itself fails after the push (a crash, not a `terminal partial` line), the
commit and PR still exist; report `Closure: partial — closure engine
failed` rather than waiting for a terminal line that will never print
(§ *Failure unit*).

