---
name: wrap-up-session
description: Close session with code review, testing, fixes, and a clean commit. Use at the end of any coding session.
---

# /wrap-up-session — Session Wrap-Up

Close out the session by syncing learnings, updating registers, running code review, testing, and pushing changes.

---

## Step 0 — Pre-Flight Check

1. Run `git diff --name-only` and `git diff --name-only --cached` to check for uncommitted changes
2. Run `git log --oneline <base-branch>...HEAD` to check for commits on this branch

**If no changes exist** (no uncommitted changes AND no commits beyond base branch):

```
Session wrapped up (no changes).
- No code changes detected this session.
- Skipped: code review, tests, commit, push.
```
Then **STOP**.

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
- Reconcile the index against the project's tracker — **read-only, summary only**:

  ```bash
  python3 .agents/skills/task-registry/scripts/task-registry.py reconcile
  ```

  Surface the summary block; do not paste per-task detail into the session
  summary or the commit message. External writes (`publish --apply`) are a
  separate, explicitly authorized step — wrap-up never creates or closes an
  external task on its own. With no tracker configured this reconciles the local
  index alone and still reports stale and superseded entries.
- Append session summary with idempotency fingerprint (commit range short-SHAs)

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

## Step 3.5 — Security Scan

Run `/security-scan` on files changed this session (`git diff --name-only <base-branch>...HEAD`).
Address any MUST-FIX findings before proceeding to commit.

---

## Step 3.7 — Shortcut Ledger

`CLAUDE.md` § *Code Economy* marks deliberate shortcuts with `TODO(shortcut):`
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
`CLAUDE.md` § *Observability Discipline*). This step reports only — it never
blocks the commit, and shortcuts are not bugs, so they do not get bug-track
documents in `tasks/solutions/`.

---

## Step 4 — Code Review (4 passes)

Run the 4 review passes. For each pass:
- Use `git diff --name-only <base-branch>...HEAD` to scope to changed files
- Focus on issues **introduced** by this session, not pre-existing patterns
- Classify every finding on all four axes below

### Review Payload

Every dispatched pass carries all seven items in `CLAUDE.md` § *Review Dispatch
Contract*. Assemble once, reuse for all four — they differ by lens, not by input:

1. The `<base-branch>...HEAD` diff (truncated-plus-path per *Large-Artifact Handoff* if large)
2. The spec path and its acceptance criteria verbatim, checkbox state stripped — or `no spec — <reason>`
3. The `tasks/todo.md` entries closed this session
4. The `[AMBIGUITY]` batch `/build` surfaced — or `deferrals: none`
5. The `TODO(shortcut):` markers from Step 3.7 touching changed files — or `deferrals: none`
6. The boundary from the bullets above, stated **to the agent**, not just here
7. The four-axis format from *Finding Classification* below

Pass the intent, not the conclusions: no builder rationale, and never one pass's
findings to another. Both would import the priors *Independence Accounting* exists
to keep out, and the promotion in *Dispatch Disclosure* would then count an echo as
a witness.

### Dispatch Disclosure

These 4 passes run either as separately dispatched agents (see *Claude Code
Enhancements*) or sequentially inline in this context. **The output must state
which**, because it decides what the passes' agreement is worth:

| How they ran | Disclosure | Promotion |
|-------------|-----------|-----------|
| 4 dispatched agents | `dispatched` | Two passes independently finding the same defect is corroboration: promote `confidence` by exactly one anchor. |
| Sequentially inline | `inline` | **No promotion.** Four lenses in one context share its priors and blind spots, so agreement is one perspective repeated. Name the corroboration lost. |

Per `CLAUDE.md` § *Independence Accounting*, same-context agreement is never
promotion evidence. An inline run is complete and still applies findings under
5.1 — it simply may not report a promoted confidence, and must say so. Record the
answer in the `Review independence:` line of the Done report.

### Finding Classification

Four orthogonal fields. Rationale lives in `CLAUDE.md` § *Finding Model*; the
operational contract is here, where findings get enforced.

| Field | Answers | Values |
|-------|---------|--------|
| `severity` | how urgent | `MUST-FIX` / `SHOULD-FIX` / `NITPICK` |
| `confidence` | how sure | `50` / `75` / `100` |
| `autofix_class` | what shape the fix is | `gated_auto` / `manual` / `advisory` |
| `owner` | who acts | `agent` / `human` / `release` |

| Severity | Definition |
|----------|-----------|
| `MUST-FIX` | Correctness, security, silent failures, data loss |
| `SHOULD-FIX` | Quality, maintainability, coverage gaps |
| `NITPICK` | Purely cosmetic — zero logic/behavior impact |

`NITPICK` is ONLY for cosmetic issues. Any logic, architecture, or security finding is `SHOULD-FIX` or higher.

**Confidence anchors** — behavioral criteria, not a feeling:

| Anchor | Criterion |
|--------|-----------|
| `100` | You read the defect in the diff and can quote the line that proves it. Reproducible from the evidence alone. |
| `75` | You located the defect and can cite the line, but correctness turns on a caller, config, or runtime value outside the reviewed scope. |
| `50` | Pattern-matched or inferred. No line proves it, or you never read the path it depends on. |

A finding at `75` or `100` **must** carry `evidence` — the verbatim motivating
line with `file:line`. Missing evidence **demotes** it to `50`; the finding
survives, its authority does not.

**Output format for each finding**:
```
[MUST-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent] file.py:42 — Description and impact
  evidence: `except Exception: pass` (file.py:42)
[SHOULD-FIX | confidence: 75 | autofix_class: manual | owner: human] handler.py:120 — Description and impact. Correctness turns on `settings.CACHE_TTL`.
  depends-on: `settings.CACHE_TTL` — set at deploy time, not readable from the tree
  evidence: `return cached or {}` (handler.py:120)
[NITPICK | confidence: 50 | autofix_class: advisory | owner: human] utils.py:30 — Description
```

### Pass 1: Codebase Consistency
- Duplicated logic that already exists elsewhere in the codebase
- Inconsistencies where the same fix should be applied in similar locations
- Missed opportunities to reuse existing utilities

### Pass 2: Defensive Code Audit
- Silent exception swallowing or overly broad catch blocks
- Fallback values that mask real errors
- Null-safe chains hiding broken assumptions
- Patterns that make production debugging harder

### Pass 3: Test Coverage
- Changed code paths that lack test coverage
- Missing edge case tests, error path tests, boundary conditions
- Existing tests that no longer align with changed behavior

### Pass 4: Adversarial Critic
- Read the specs touched this session and every AC
- Ask "what AC is this missing?" and "what user-facing behavior would break?"
- Hunt for: response-shape mismatches, declared-done-without-e2e patterns, duplicate todo blocks
- Check API contract changes against any clients (frontend, tests, docs)

---

## Step 5 — Reconcile & Apply Fixes

### 5.1 — Apply Gate (Enforcement)

Enforcement is keyed on the **combination** of `severity`, `autofix_class`, and
`confidence` — not on severity alone. Severity says how much the finding matters;
`autofix_class` and `confidence` say whether this loop has earned the right to
edit code over it.

| Severity | `autofix_class` + `confidence` | Action |
|----------|-------------------------------|--------|
| `MUST-FIX` | `gated_auto` **and** `confidence >= 75` | Auto-apply in the fix loop. |
| `MUST-FIX` | `manual` or `advisory`, `confidence >= 75` | Cannot be auto-applied — and cannot be skipped. Fix it deliberately, one finding at a time, and record the diff in 5.2. If it cannot be fixed here, it reaches Step 7 unresolved and **STOPS the commit**. |
| `MUST-FIX` | `confidence` `50` | **Verify it first — do not fix it and do not block on it.** Read the path the finding depends on. Evidence found → it is now `75`+ and takes the row above. Refuted → record the refutation in 5.2 and drop it. |
| `SHOULD-FIX` | `gated_auto` **and** `confidence >= 75` | Apply by default. |
| `SHOULD-FIX` | anything else | Report. May skip ≤3 total with code-specific justification. |
| `NITPICK` | any | Auto-skip. |

Overriding rules:

- **Never auto-apply at `confidence` `50`.** An unproven fix costs more than an
  unfixed finding: it edits code on a guess and consumes the review budget that
  would have proven it.
- **`owner: human` or `owner: release` is never auto-applied**, at any severity or
  confidence. It is carried to the Done report under that owner.
- **A finding arriving with no `confidence`** — an older single-axis reviewer —
  is read as `50` / `autofix_class: manual`: reported, never auto-applied, never
  discarded. No reviewer output is thrown away for failing to use this schema.
- **On disagreement between passes**, synthesis takes the **more conservative**
  `autofix_class` (`advisory` > `manual` > `gated_auto` in conservatism) and the
  **higher** severity. It never widens. Two passes disagreeing is information
  about uncertainty, not a vote to be averaged.
- **Do not downgrade a finding to clear the gate.** Reclassifying a `MUST-FIX` as
  `NITPICK`, or dropping a `confidence` to make it reportable rather than
  fixable, defeats the entire mechanism. If it must be resolved and cannot be,
  STOP.

### 5.2 — Review Reconciliation Table

After processing all findings (skip if total findings ≤ 3):

```markdown
### Review Reconciliation

| # | Pass | Severity | Confidence | Autofix class | Owner | Finding | Action | Justification |
|---|------|----------|-----------|---------------|-------|---------|--------|---------------|
```

### 5.3 — Review-Fix-Recheck Loop (max 2 iterations)

After applying fixes, re-check only modified files. If new issues found: apply fixes (iteration 2). Stop after iteration 2.

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

If tests fail: fix root cause (not workaround), re-run. Max 2 fix attempts; if still failing, report and do not push.

---

## Step 6.3 — E2E Coverage Gate

For every user-facing AC in specs touched this session:

1. Confirm a `/verify --scope e2e` walkthrough ran by checking `tasks/e2e-log.md` for an entry matching the spec and current commit short-sha
2. If missing: ask:
   > "AC [ID] is user-facing but has no e2e walkthrough. Run /verify --scope e2e now, or acknowledge the gap? (run/acknowledge)"
3. On `run`: invoke `/verify --scope e2e`, then re-check
4. On `acknowledge`: record the gap as a knowledge-track document in `tasks/solutions/process/` (tags: `[e2e-gap]`)

If no specs were touched: skip this gate silently.

---

## Step 7 — Commit & Push

### Code Review Gate

| Review Status | Action |
|---------------|--------|
| All MUST-FIX resolved AND ≤3 SHOULD-FIX skipped | Proceed |
| Any MUST-FIX unresolved — skipped, or held back by the Apply Gate and not fixed deliberately | STOP — ask user for explicit approval |
| More than 3 SHOULD-FIX skipped | STOP — present skipped items, ask for approval |

### Commit & Push

1. Stage changes: `git add -p` — stage only relevant changes
2. Commit with type prefix: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
3. Append optional trailers: `Constraint:`, `Rejected:`, `Not-tested:`, `Confidence:`
4. Push: `git push -u origin <branch>`
5. Open the PR, or re-sync its description if one already exists — see *PR Description Sync*

**Do not push if**: any test is failing, uncommitted changes unreviewed, MUST-FIX skipped.

### PR Description Sync

`gh pr create` writes the description once, from the branch as it stood at that
moment. Every later commit can falsify it — a follow-up session, a review fix, a
resolved deferral — and nothing re-reads it. The body is what reviewers act on, so
a stale one is not cosmetic: a PR whose notes still list a defect as "deferred" is
asking for review of work that no longer exists.

**No PR for this branch** → create it.

**A PR already exists** → reconcile the body against the branch before reporting done:

1. Read it: `gh pr view <n> --json body -q .body`. List every factual claim —
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

### Push Failure Handling

| Failure | Action |
|---------|--------|
| Network error | Retry up to 4 times with backoff (2s, 4s, 8s, 16s) |
| Non-fast-forward | `git pull --rebase`, resolve conflicts, push again |
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
2. Open the PR (`gh pr create`) or confirm one is already open
3. **Stop here. Do not merge locally and do not delete the branch** — an open PR
   whose source branch is gone is a dead PR, and a local merge to `main` bypasses
   the review the PR exists to get
4. Removing the *worktree directory* is fine once pushed
   (`git worktree remove <path>`); the branch must survive until the PR lands

**If the repo merges locally (no remote, or the user asked for a direct merge):**

1. Verify clean: `git status --porcelain` empty
2. Switch to the parent worktree, `git pull --ff-only`
3. `git merge --no-ff <branch>`
4. Run the **full** suite on the merged result — this is the first time these two
   lines of history have coexisted, so a green run on either side proves nothing
   about the merge
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

After push, verify deployment services if `## Deployment Targets` section exists in `.claude/project.md` (Claude Code only).

Use `/verify --scope deployment` to poll, fetch logs on failure, and loop a `code-debugger` fix cycle up to 3 iterations.

If `--skip-deploy` flag was passed: skip this step entirely.

If no `## Deployment Targets` section: scan `tasks/deployments/*.md` for signal files. If found, nudge user to run `/setup-deployment`. If not found: skip silently.

---

## Done

```
Session wrapped up.
- Learnings: [N patterns / none]
- Tasks: [X completed, Y pending]
- Bugs: [N opened, N closed / no changes]
- Code Review: [PASS / INCOMPLETE — N unresolved issues]
  - Review independence: [4 passes dispatched / inline — no promotion; lost corroboration: <what>]
  - MUST-FIX: [N found, N auto-applied, N fixed deliberately, N unresolved]
  - SHOULD-FIX: [N found, N applied, N skipped]
  - NITPICK: [N found, skipped]
  - Reported, not applied: [N — with autofix_class and owner, or none]
- Security Scan: [PASS / N issues addressed]
- Tests: [PASS — suite name] or [FAIL] or [SKIPPED — no suite]
- E2E coverage: [N user-facing ACs verified / NONE / GAP — N acknowledged]
- Pushed: [yes / no — reason]
- PR: [#N opened / #N description re-synced — what changed / #N already accurate / none]
- Deployments: [results or SKIPPED / NONE]
```

## Claude Code Enhancements

### Step 4 — Parallel Code Review
Launch all 4 review passes as parallel agents in a SINGLE message with multiple Agent tool calls.

`code-reviewer` and `critic` are **Ceiling** tier (`CLAUDE.md` § *Model Routing*):
pass **no** `model` parameter so each inherits the session model. `critic` is the one exception: it carries a **planner floor**, so pass the planner
alias when the session model is below planner tier and omit `model` otherwise. Pinning them
downgrades the highest-stakes review for exactly the users running a stronger
model.

This path is what makes the 4 passes separately dispatched contexts, so it is the
only path that licenses confidence promotion. Record it as `dispatched` and
disclose it per *Dispatch Disclosure*.

Every one of the four calls carries the *Review Payload* assembled in Step 4, which
implements `CLAUDE.md` § *Review Dispatch Contract* — including its `deferrals: none`
and `no spec — <reason>` markers, which are stated even when there is nothing to state.
Identical input, different lens —
identical input, different lens. A pass dispatched without it reviews the diff
against its own priors about what code should look like, which is where
re-litigated shortcuts come from.

Agent assignments:
- Agent 1: `code-reviewer` — Codebase Consistency (Pass 1)
- Agent 2: `code-reviewer` — Defensive Code Audit (Pass 2)
- Agent 3: `code-reviewer` — Test Coverage (Pass 3)
- Agent 4: `critic` — Adversarial Critic (Pass 4)
