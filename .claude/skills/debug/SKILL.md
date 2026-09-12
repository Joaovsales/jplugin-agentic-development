---
name: debug
description: Systematically investigate, diagnose, and fix bugs using root cause analysis. Use when debugging errors, test failures, runtime issues, or when the user reports a bug. Integrates with the typed learning store (tasks/solutions/).
argument-hint: "[bug description | error message | #N | task-id]"
disable-model-invocation: false
harness: universal
---

# /debug — Bug Investigation & Fix

Systematically investigate and fix bugs using root cause analysis, the `code-debugger` agent, and the typed learning store. Iterates with `/loop` to run tests until all regressions are resolved.

## The Iron Law

```
NO FIXES WITHOUT THE ROOT-CAUSE PRELUDE (Phase 0.5) AND REPRODUCTION (Phase 1)
```

You cannot propose fixes until:
1. The **Root-Cause Prelude** (Phase 0.5) has listed 3 candidates and picked one based on disconfirming evidence, AND
2. Phase 1 (Reproduce & Isolate) has produced a minimal failing reproduction.

Symptom fixes are failure. Single-hypothesis tunnel vision is failure.

## Pre-Flight — Load Context

1. **Grep the learning store**:
   - Grep `tasks/solutions/` frontmatter (`problem_type`, `module`, `tags`) for
     documents matching the failing area — bug-track documents are prior
     investigations, knowledge-track documents are patterns and gotchas
   - Check if the current bug matches a known root cause — apply the known fix first
   - If a matching bug document exists, reference and update it rather than
     starting a duplicate investigation
   - **Bulk reads follow the Bulk-Read Handoff** (`CLAUDE.md` § Model Routing →
     *Bulk-Read Handoff*): when a file the investigation needs is over the gate's
     line threshold, ask `bulk-reader` for a source map and inspect the failing
     path, callers, contracts, and tests yourself in bounded reads; expand to
     the whole relevant component when needed, including files you will not edit

2. **Identify the bug**:
   - If `$ARGUMENTS` is an **issue reference** — `#N` or a registry task ID — read
     it through `task-registry show <ref>` (never a tracker CLI). The body a
     `/sweep` filed carries a *Reproduction*, a *Proposed fix*, acceptance
     criteria, and evidence; § *Issue intake* below says what each becomes.
   - Otherwise, if `$ARGUMENTS` provided: use as the bug description
   - If no arguments: ask the user to describe the bug, provide error output, or point to the failing test

### Issue intake

An issue filed by `/sweep` (see `specs/sweep-routines.md`) was written so a
cheaper model can work it cold, and this skill is where that pays off:

| Issue section | Becomes |
|---|---|
| *Reproduction* (numbered steps; last line `observed: … / expected: …`) | the reproduction step of Phase 1 — run it verbatim before anything else |
| *Proposed fix* | **candidate one** in the Phase 0.5 prelude — a hypothesis to be confirmed by disconfirming evidence, never assumed correct because a sweep wrote it |
| *Acceptance Criteria* | the pass condition for Phase 3, and the `[ ] TDD:` tasks Phase 4 writes |
| *Evidence* (four-axis tag, `file:line`, `discovered:` stamp) | the prior for the prelude's ranking; a `75` names what it turns on and the prelude reads that first |

A `tech-debt` task read this way has no reproduction: its proposed fix and
evidence enter the prelude the same way, and Phase 1 writes the failing test
from the acceptance criteria instead.

**Unattended intake.** On a `routine/` branch there is no user to ask. If the
issue's reproduction does not reproduce — the command runs, the observed output
matches the expected one — emit exactly:

```
blocked: reproduction failed — <command>
```

exit **non-zero**, and open no PR. Do not fall back to guessing a different
reproduction and do not prompt. The claim label stays on the issue; releasing it
needs a registry write that does not exist yet.

## Phase 0.5 — Root-Cause Prelude (MANDATORY before any Edit)

Before touching a single file, post this block to the user and wait for confirmation
OR explicitly pick a branch and name the disconfirming evidence. On a `routine/`
branch there is no user: record the block in the turn output, pick a branch, and
proceed. This exists because
the #1 debugging failure mode is committing to hypothesis #1 and editing the wrong
component (see the WhatsApp UserMenu/Banner and dual-SIM sagas in memory).

### Required output — "Top-3 Candidates"

```
🔎 Root-Cause Prelude — [bug summary]

Reproduction confirmed: [YES — <how> | NO — need <screenshot/logs/steps>]

Top-3 candidate root causes (ranked by prior likelihood):

1. [hypothesis] — <component/file:line>
   Supporting: [observation + evidence level 1-6]
   Disconfirming test: [one cheap check that would rule this OUT]

2. [hypothesis] — <component/file:line>
   Supporting: [observation + evidence level]
   Disconfirming test: [cheap check]

3. [hypothesis] — <component/file:line>
   Supporting: [observation + evidence level]
   Disconfirming test: [cheap check]

Picked: #<N> because [disconfirming evidence for others is stronger than for this].
```

### Rules

- **Do not skip this block** even for "obvious" bugs. Obvious bugs are where wrong-component detours happen.
- **Do not collapse to 1 candidate** until disconfirming checks have been run on the other two. Listing one candidate = speculation.
- **If reproduction is `NO`**: STOP and ask the user for a screenshot, log excerpt, or exact repro steps. Do not proceed to Phase 1. On a `routine/` branch there is no user: emit `blocked: reproduction failed — <command>` and exit non-zero instead (§ *Issue intake*).
- **If the bug came from an issue**: its *Proposed fix* is candidate #1, and the other two candidates must be genuinely different components, not paraphrases of it. A sweep's proposal is the strongest prior on the list, not a verdict.
- **If the user redirects** ("look at X instead", "that's not the bug"): re-run this prelude with their new information. Do not continue with the old hypothesis.

Only after the prelude passes do you delegate to Phase 1.

---

## Phase 1 — Reproduce & Isolate

Delegate to the `code-debugger` agent (build tier — see Model Routing in `/build`; on Claude Code pass `model` explicitly, on Pi the `pi-subagents` extension resolves it from settings):

```
Prompt to code-debugger:
─────────────────────────
Bug report: [description from user or $ARGUMENTS]

Known patterns from the learning store:
[relevant tasks/solutions/ documents — knowledge track]

Related prior investigations:
[matching tasks/solutions/bugs/ documents, if any]

Your task:
1. Reproduce the bug — find or write a minimal failing test
2. Read all relevant source files before forming hypotheses
3. Form 2-3 hypotheses ranked by likelihood
4. Rank evidence using the Evidence Strength Hierarchy (see evidence-hierarchy.md):
   - Level 1 (strongest): Controlled reproduction (test that isolates exact cause)
   - Level 2: Primary artifacts (timestamped logs, git history, metrics)
   - Level 3: Multiple independent sources converging on same explanation
   - Level 4: Single code-path inference (plausible but not uniquely discriminating)
   - Level 5: Circumstantial clues (naming, proximity, timing)
   - Level 6 (weakest): Intuition or analogy
   Label each piece of evidence with its level. Down-rank hypotheses supported only by Level 5-6 evidence.
5. Use binary search / state inspection to isolate the root cause
6. Document the root cause clearly

Return:
- Root cause (1-2 sentences)
- Evidence level supporting the conclusion (Level 1-6)
- Affected files and line numbers
- Minimal reproduction (test or steps)
- Recommended fix approach
```

**If the agent cannot reproduce**: ask the user for more context (logs, steps, environment). Do not guess. Unattended (a `routine/` branch), there is nobody to ask: emit `blocked: reproduction failed — <command>`, exit non-zero, no PR.

## Phase 2 — Fix

Delegate the fix to the appropriate coding agent (build tier per Model Routing in `/build`):

| Bug Location | Agent |
|-------------|-------|
| API, database, auth, business logic | `backend-developer` |
| UI components, styling, client state | `frontend-developer` |
| Cross-cutting or unclear | `code-debugger` |

**Fix delegation prompt must include:**
- The root cause from Phase 1
- The affected files and line numbers
- The minimal reproduction test
- Instruction: "Fix the root cause, not the symptom. Keep the change minimal."
- Instruction: "Ensure the reproduction test now passes."

### Architecture Questioning — After 3 Failed Fixes

**If 3+ fix attempts have failed, STOP and question the architecture:**

Pattern indicating architectural problem:
- Each fix reveals new shared state/coupling/problem in a different place
- Fixes require "massive refactoring" to implement
- Each fix creates new symptoms elsewhere

**STOP and question fundamentals:**
- Is this pattern fundamentally sound?
- Are we "sticking with it through sheer inertia"?
- Should we refactor architecture vs. continue fixing symptoms?

**Discuss with the user before attempting more fixes.**

This is NOT a failed hypothesis — this is a wrong architecture. Do NOT attempt fix #4 without the user's explicit direction.

## Phase 3 — Verify with Loop

After the fix is applied, use `/loop` to run all relevant tests iteratively until clean:

```
/loop 30s Run the test suite relevant to the bug fix.
  Files changed: [list from git diff --name-only].
  1. Run the reproduction test — confirm it PASSES
  2. Run the full test suite — check for regressions
  3. If ALL tests pass: report SUCCESS and stop the loop
  4. If any test FAILS: delegate to the `code-debugger` agent (escalation tier after 2 failed attempts) with:
     - The failing test output
     - The files changed so far
     - The original root cause context
     Then re-run tests after the fix
  Loop exits when: all tests pass OR 5 iterations reached
```

**If 5 iterations pass without all tests green**: stop and escalate to the user with:
- What was fixed
- What still fails
- Hypotheses for remaining failures

## Phase 4 — Record & Learn

### Write the Bug Document (`tasks/solutions/bugs/<slug>.md`)

Create or update a bug-track document using the
[bug document template](templates/bug-report-template.md): frontmatter carries
`title`, `date`, `problem_type`, `module`, `tags`, `symptoms`, `root_cause`,
`resolution`; status and the regression-test name go in the body. If a document
for this bug already exists (found in Pre-Flight), update it in place — never
create a sibling. Create `tasks/solutions/bugs/` if absent.

### Write the build tasks (issue intake only)

When the bug came in as an issue that carries a *Proposed fix* and acceptance
criteria, this phase also writes the plan `/build` will execute — one row per
criterion, in the standard shape, under a heading naming the issue:

```
## Fix: #N — <title>

- [ ] TDD: <test that pins criterion 1> -> <the proposed-fix step that satisfies it>
- [ ] TDD: <test that pins criterion 2> -> <step>
```

The proposed fix is decomposed as the prelude confirmed it, not as the issue
wrote it: where Phase 1 disproved a step, the row states the step that replaced
it. The `fix` routine's next step is `/build`, which reads exactly these rows.

### Capture Lesson

If this bug reveals a reusable pattern beyond the fix itself, write a
knowledge-track document (`problem_type: pattern`, with `applies_when`) per the
/learn conventions, cross-linked from the bug document.

Skip if the bug was trivial (typo, missing import, etc.).

## User Signals You're Doing It Wrong

Watch for these redirections from the user — they indicate your debugging approach has gone off track:

| User Signal | What It Means |
|-------------|---------------|
| "Is that not happening?" | You assumed without verifying |
| "Will it show us...?" | You should have added evidence gathering |
| "Stop guessing" | You're proposing fixes without understanding root cause |
| "We're stuck?" (frustrated) | Your approach isn't working — change strategy |
| "Try something different" | You're repeating failed approaches |
| "Did you actually check?" | You claimed something without evidence |

**When you see these signals:** STOP. Return to Phase 1 (Reproduce & Isolate). Re-read error messages. Gather fresh evidence.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question pattern, don't fix again. |
| "I'll write test after confirming fix works" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |

## Phase 5 — Report

```
══════════════════════════════════════
  DEBUG COMPLETE — [Bug Summary]
══════════════════════════════════════

🔍 Root Cause: [1-2 sentence explanation]
🛠️  Fix: [what was changed]
📁 Files Changed:
  [git diff --stat summary]

🧪 Tests:
  - Reproduction test: [PASS]
  - Full suite: [N passing, 0 failing]
  - Loop iterations: [N]

📋 Bug Document: [tasks/solutions/bugs/<slug>.md added/updated]
📝 Lesson: [captured / skipped — trivial bug]

Ready for /wrap-up-session or continued work.
══════════════════════════════════════
```

## Error Handling

- **Cannot reproduce**: Ask user for more context. Do not proceed without reproduction. Unattended, `blocked: reproduction failed — <command>` and a non-zero exit — never a prompt, never a PR.
- **Fix introduces new failures**: Revert and try alternative approach. Max 3 alternative approaches before escalating.
- **Loop timeout (5 iterations)**: Escalate to user with full context of what was tried.
- **Multiple root causes**: Fix one at a time. Each gets its own bug document and loop verification cycle.

## Key Principles

- **Root cause, not symptoms**: Never patch around the bug. Find and fix the actual cause.
- **Reproduce first**: No fix without a failing test that proves the bug exists.
- **Store-informed**: Always grep the learning store before investigating from scratch.
- **Record everything**: Every bug gets a store document. Every non-trivial fix generates a lesson.
- **Loop until clean**: Use `/loop` to iterate on test runs — no manual re-running.
