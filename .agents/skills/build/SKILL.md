---
name: build
description: Execute the task plan from tasks/todo.md autonomously using TDD with sub-agent delegation. Use in the session the build prompt starts.
argument-hint: ""
---

# /build — Autonomous Build Orchestrator

Execute the full plan from `tasks/todo.md` autonomously using TDD.
Bridges the gap between `/plan` (design) and `/wrap-up-session` (close).

## Model Routing

Sub-agent model assignment for build orchestration. The Tier column is canonical;
concrete provider model IDs live in `PI_SETUP.md` § Sub-Agent Routing for Pi and
`config/agent-policy.toml` for Codex — do not copy them back here.

| Role | Agent | Tier | Claude Code |
|------|-------|------|-------------|
| Planning / architecture / circuit breaker | `planner` | Planner | `opus` |
| Second opinion (advisory) | `oracle` (extension builtin) | Planner | `opus` |
| Coding agents | `backend-developer`, `frontend-developer` | Builder | `sonnet` |
| Debugger (attempts 1-2) | `code-debugger` | Builder | `sonnet` |
| Debugger (attempts 3-4, escalation) | `code-debugger` | Reviewer | `ceiling (builder floor)` |
| Highest-stakes review (correctness, security, design, adversarial) | `code-reviewer`, `security-reviewer`, `software-design-expert-review`, `critic` | Ceiling | *inherit* (`critic`: planner floor) |
| Search / recon | `scout` (extension builtin) | Scout | `haiku` |
| Context / docs | `context-builder` (builtin), `context-document-optimizer` | Scout | `haiku` |

**Escalation ladder for test regressions:**
1. 2 attempts at builder tier
2. 2 attempts at reviewer tier — on Claude Code that resolves to `ceiling (builder floor)`, because Reviewer and Builder both map to `sonnet` there, so a plain reviewer-tier retry would re-run the model that just failed twice. The floor makes this rung strictly stronger than step 1 on every session. See `.agents/references/model-routing.md` § *Floors*.
3. Circuit breaker — `planner` at planner tier analyzes all 4 attempts; then halt and escalate to user

Steps 1 and 2 must never resolve to the same model. If they do, the ladder has no middle rung and the first genuine escalation is the circuit breaker — four failed attempts later than intended.

On Codex, dispatch the managed `debug-escalation` role for attempts 3–4; the rule is
`.agents/skills/build/references/harness-dispatch.md` § *Codex: debugger escalation (Model Routing)*.

> **For Pi + OpenRouter users:** attempts 3–4 dispatch `code-debugger` with a per-run `model`; the rule is
> `.agents/skills/build/references/harness-dispatch.md` § *Pi + OpenRouter routing (Model Routing)*.

## Step 0.5 — Isolation

Decide **before** the green baseline whether this build runs in a git worktree.
Pairs with `/wrap-up-session` § *Worktree integration*, which merges and removes it.

**Enter a worktree if ANY of these hold:**

- Invoked from `/yolo`, `/auto-push`, or an unattended routine run — nobody
  is watching to notice a stray checkout
- Another agent session is active in this clone
- The plan regenerates committed fixtures or snapshots
- `tasks/todo.md` has more than 6 open tasks (long enough to straddle a merge)

**Otherwise stay in the clone** and say so in one line. A short supervised build
does not earn the setup cost.

**How:** prefer the harness-native `EnterWorktree` tool where available — this
skill instructing it is what authorises that tool. Otherwise:

```bash
.agents/skills/build/scripts/bootstrap-worktree.sh <branch>
```

Do not use a bare `git worktree add`. A fresh worktree has no `node_modules` and
no `.env*`, and a suite that gates on an env file will **skip** those tests and
report green. The script symlinks and copies both, and warns when it cannot.
Count the tests, not the exit code.

**What a worktree does and does not buy you.** It prevents *interference* — one
agent's `checkout` rewriting files under another's running session. It does
nothing for *merge conflicts*, which come from two branches editing the same
lines and are identical however many directories were involved. It can even make
them larger, since agents in separate trees never see each other's work in
progress and drift further before finding out. Merge `main` in frequently.

## Pre-Flight Checks

1. Verify `tasks/todo.md` exists and has pending `[ ]` tasks
   - If empty or missing: **STOP** — run `/plan` first
2. Read the spec from `specs/` that matches the current plan
   - If no spec found: **STOP** — run `/plan` first
   - For UI work, run the UI brief and concept-approval checks in
     `.agents/skills/build/references/design-stack-gates.md` § *Pre-Flight: UI brief and concept approval* before any source edit.
3. **Link the feature issue** when `slice.py link` prints `unlinked <id>` — see
   *Pre-Flight: Link the Feature Issue* below. Do this before the green baseline.
4. Grep `tasks/solutions/` frontmatter (`problem_type`, `module`, `tags`) for learnings relevant to the plan's target area
5. Load `tasks/project-context.md` if it exists (architecture, protection list, conventions)
6. Identify the project's test runner (check `package.json`, `Makefile`, `pyproject.toml`, etc.)
7. Record the **base SHA** (`git rev-parse HEAD`) and run the full test suite
   once, through the cache, to establish a **green baseline**:
   `.agents/skills/build/scripts/cached-suite.sh -- <full-suite command>`.
   The command is the `Full suite: <command>` line below the `AGENTS.md` end
   marker, verbatim — the cache key hashes the command, so every skill must
   spell it the same way; when a project declares none, use the runner step 6
   identified. A green run of that command on this tree is reused, not
   repeated; `/yolo` and `/auto-push` leave their baseline to this step. This
   is the build's only full run; the pre-push one belongs to
   `/wrap-up-session` § *Full suite*.
   - If tests fail before you start: fix or flag to user before proceeding
   - Resolve the **affected-test command** every later checkpoint runs: the
     `Affected tests: <command with {base}>` line below the `AGENTS.md` end
     marker, with `{base}` replaced by the base SHA (in this repository,
     `bash tests/affected.sh --run {base}`). Run it through
     `cached-suite.sh -- <affected-test command>` too, so the lock refuses it
     beside a running suite and an unchanged tree reuses its green run. When a
     project declares none, run the test files that cover the changed paths
     and name them in the log line.
8. **Classify acceptance criteria** — for each AC in the spec, tag as `logic | integration | user-facing`:
   | AC type | Signals |
   |---------|---------|
   | `logic` | Pure functions, validators, transforms, utilities — no I/O |
   | `integration` | API endpoints, DB queries, service-to-service calls, background jobs |
   | `user-facing` | Auth flows, form submissions, navigation, UI state, anything a user sees or clicks |
   When an AC mixes types, classify by the highest tier (`user-facing` > `integration` > `logic`).

**One suite at a time, no polling.** Launch the full suite as a background
task (`run_in_background` on Claude Code) and wait for its completion
notification. While it runs, do only work that leaves the working tree alone —
reading the spec, classifying the ACs — because `cached-suite.sh` hashed the
tree when the run started, and an edit made now would be pushed without a full
run. Never wait in a foreground `sleep` or a poll loop. `cached-suite.sh`
refuses a second full run with exit 3, and the rule extends to every test run:
no test run starts while a suite is running — no targeted file, no
affected-test run — because a test beside a running suite shares its load,
slows both and can fake a failure in either.

**A refusal is not a test result.** Exit 3 with `cached-suite: a suite is
already running` on stderr means nothing ran: never hand it to `code-debugger`
and never count it as a fix attempt. When the running suite is this session's
own background job, wait for its completion notification and run again; when
it belongs to another session or worktree, report the pid and start time the
line names and stop, rather than wait on a job this session cannot see finish.

### Pre-Flight: Link the Feature Issue

This session exists because a human started it with the build prompt, which
is the authorization the planning session did not have. Run
`python3 .agents/skills/slice/scripts/slice.py link --index tasks/todo.md --spec specs/<feature>.md`
and act on the first word of its `link:` line (`issue <ref>`, `linked <id> <ref>`,
`unlinked <id>`, `legacy` or `none`; `<ref>` is `owner/repo#N` for a URL or a
qualified ref, `#N` for a bare number; a feature row linked only to a local task reads `unlinked`). A malformed link (two feature links, a feature row with no
task-id, an `> Issue:` ref no provider can close, two plan blocks for one spec) exits 2 with the refusal: stop and report it. Only `unlinked <id>` runs
one upsert, of the `<id>` the line printed, never one re-derived from the spec;
`issue`, `linked`, `legacy` and `none` mean there is nothing to do:

```bash
python3 .agents/skills/task-registry/scripts/task-registry.py upsert <id> --spec specs/<feature>.md --title "<feature>" --apply --approve
```

`--approve` is passed when the build prompt authorized the build; `/yolo` and
an unattended lane run
(`.agents/skills/wrap-up-session/references/routines.md` § *Crossing the plan
handover*) omit `--approve`, so the write lands like every other unattended
write on a project that requires approval. A result of `local-pending` prints
`feature issue pending: <reason>`; a failure prints
`feature issue not filed: <reason>`; the build continues on both.

A `## Plan:` block with no `### Slice` headings is one **implicit slice**
whose surface is the spec's `implementation_paths` frontmatter, so every
plan written before this spec still builds.

## Phase 1 — Slice Execution (TDD Loop)

Process every open slice in `tasks/todo.md` without pausing for user confirmation between slices.

The `- [ ]` row under each `### Slice n/N` heading (written by `/slice`) is the
**slice header**: the registry's row for that slice, not a task of its own.
Mark it `[x]` at Slice Close and never dispatch a coder against it. For an
older plan block see *Legacy block* at the end of this phase.

**Route every slice before its first dispatch** — one slice or many: run
`slice.py ready` (below) first. `.agents/` is a dot-directory that a bare `ls`
hides: a script `test -f` cannot find stops the build, never a reason to skip
the step it serves.

### Parallel Dispatch Assessment

Get the ready set instead of guessing independence from prose:

```bash
python3 .agents/skills/slice/scripts/slice.py ready --index tasks/todo.md --spec <spec>
```

This prints each ready slice with its surface and every intersecting pair.
Disjoint ready slices dispatch in parallel; an intersecting pair with no
blocker between them is a plan defect — serialized in table order and
reported, never guessed. Re-run `ready` after every slice closes to pick up
the next batch.

**If 2+ ready slices are disjoint**:
1. Dispatch one sub-agent per slice, passing
   `isolation: "worktree"` on each `Agent` call **when the slice writes files**.
   Independence assessed at plan time is a prediction; worktree isolation makes
   it structurally true, so a mis-grouping surfaces as a merge conflict you can
   see rather than two agents silently overwriting each other.
2. Before dispatching, give every sub-agent a tool-call budget with an explicit
   "stop and write partial work" escape hatch, and arm a stall monitor. A hung agent
   returns nothing, so null-check fallbacks never fire and this barrier never releases.
   See `.agents/skills/build/references/subagent-resilience.md`.
3. Wait for all to return; check for file conflicts.
4. Run the affected-test command **centrally, once** — never instruct the sub-agents to
   run it themselves. Fanning verification out to every agent multiplies context
   for no added signal and is a known way to lose a whole fleet to autocompact
   thrashing. Isolate the *edits*, centralise the *verification*.

In every session, every slice dispatches to a sub-agent: `/build`
implements nothing itself. A lone ready slice, and each slice of a serialized
pair (an intersecting pair with no blocker between them), runs one at a time
in table order through Steps 1–3 below, in the main tree. Verification stays
central. Where the harness has no sub-agents, `/build` runs inline and says so
in one line.

### Step 1 — Implement the Slice

Choose the agent or approach based on the slice's work type:

| Work Type | Agent |
|-----------|-------|
| API, database, auth, business logic | `backend-developer` |
| UI components, styling, client state | `frontend-developer` |
| Cross-cutting or unclear | `backend-developer` |

**Delegation prompt must include**:
- The slice's Delivers (§ Build Order) and the acceptance criteria its row
  lists, copied from the spec
- The relevant spec section from `specs/`
- Paths to related source files
- Instruction: "Run each acceptance criterion of the slice through `/tdd`: failing test first, then minimal implementation, then refactor"
- The slice's Surface from § Build Order, with the rule: edit only inside
  it; a file you must touch outside it is reported as
  `[SURFACE] +<path> | reason: <one sentence>` and the work continues
- The `> Handover:` blockquote (every `>` line) of each slice this one is blocked by, verbatim
- For frontend implementation and `frontend-design-validator`: the context in
  `.agents/skills/build/references/design-stack-gates.md` § *Delegation context*
- The tool-call budget and escape hatch from `subagent-resilience.md` Rule
  1, and the instruction to list unfinished acceptance criteria under
  `## Not finished`

**Role-based context injection from `tasks/project-context.md`** (if it exists):

| Agent | Sections to include |
|-------|---------------------|
| `backend-developer` | `[ARCHITECTURE]` + `[PROTECTION]` + relevant functional requirements |
| `frontend-developer` | `[ARCHITECTURE]` + `[PROTECTION]` + `[CONVENTIONS]` + relevant requirements |
| `code-debugger` | Failing test + relevant code only |

Do not pass the full project-context to every agent — extract only relevant sections. For bulk artifacts (logs, long command output), follow `AGENTS.md` § *Large-Artifact Handoff* — truncate-with-pointer, never inline.

### Step 2 — Per-Slice Spec Compliance Check (inline, no agent)

After implementation, run this check inline in the main context:

1. Re-read the slice's acceptance criteria from `specs/`
2. Run `git diff --cached` (or `git diff HEAD`) to see the actual changes
3. Report:
   - **PASS** if the change addresses the acceptance criteria
   - **MISMATCHES** — list each specific gap between spec and implementation

If mismatches found: send feedback to the implementing agent for fixes, then re-check.

### Step 3 — Fix Failures

If the dispatch reports a failing criterion, fix it with the `code-debugger`
agent and the full failure context; repeat until the slice's criteria are green.
The affected-test command runs once, at Slice Close. A slice blocked by a
previous failure is noted and skipped for the next unblocked one. Then go to
Slice Close, the only place a header is marked `[x]`.

### Slice Close

Slice Close fires when the dispatch returns with every acceptance criterion of
the slice green through `/tdd`:

```bash
python3 .agents/skills/slice/scripts/slice.py check --spec <spec> --slice <n> --base <sha>
```

This matches `git diff --name-only <base>..HEAD` against the slice's
declared surface and prints `undeclared: <paths>` and `untouched: <globs>`,
exiting 0 only when both are empty. Informational — nothing stops on a
non-empty report; fold the result into the handover below and the Phase 4.5
batch; exit 2 is bad input.

Write a `> Handover:` blockquote under the slice heading, after its rows —
one to four blockquote lines, each with its own prefix:

```markdown
> Handover: landed <short-sha>..<short-sha> — what landed
> Do not re-derive: the facts the next slice must not rediscover
> Surface: the `check` report (`undeclared:` / `untouched:`, or none)
> Open: one open question (optional)
```

The first two lines are required; the blockquote is the unit every reader
consumes — the delegation prompt and `/wrap-up-session` § Handovers carry
the whole blockquote, never the `> Handover:` line alone. Write it for a
one-slice plan too: it is what an interrupted build's next session reads.

**Unfinished slice**: when the agent returns criteria under `## Not finished`
or the escape hatch fired, leave the header `[ ]`, write
`unfinished: <AC ids>` in the handover, and leave the slice in the next
`ready` set. Never renumber and never open a remainder slice. A header
marked `[x]` with no `> Handover:` is the **forbidden state** — Phase 6 checks
every `[x]` header for its handover and reports a miss as a build failure.

The slice boundary is the checkpoint, in this order: run the affected-test
command once against the base SHA, centrally; write the handover; mark the
header `[x]`; log `✓ slice <n> — <one-line summary>`.
**Task-boundary checkpoint**: silently refresh `tasks/checkpoint.md` via the
shared flush (`bash .agents/hooks/pre-compact.sh </dev/null`) — no prompt, no
commit — so a context compaction or `/refresh` loses at most one slice of
work. Then call
`slice.py ready` again and start the next batch immediately, with no user prompt.

**Slice status**: a new block's header carries no task id; its status lives in
the one feature issue (pre-flight links it, `/wrap-up-session` closes it).
Never call `gh` or a tracker API directly; any status write goes through
`/task-registry`, gated like every other external write — dry-run unless
`--apply` and the project's approval setting allow it.

### Legacy block

A block `slice.py link` classifies as `legacy` is defined in
`.agents/skills/slice/references/plan-block.md` § *Legacy block*. Its `TDD:`
rows run through `/tdd` and, when unfinished, go under `## Not finished`; each
row is marked `[x]` as it passes; Slice Close fires when
its last `TDD:` row passes, and an unfinished slice writes `unfinished: <rows>`;
the forbidden state also covers a header `[x]` with a `[ ]` child row, and
Phase 6 counts nested rows.

## Phase 1.5 — Changed Verification Map

After every slice header is `[x]`, classify the completed work. If ANY acceptance
criterion is `user-facing`:

1. Invoke `/maintain-verification-skill --scope changed` with the session intent,
   base-to-HEAD diff, touched specs, and completed task entries. This idempotently
   reconciles the project-local feature map on the active branch.
2. If no project-local verification skill exists, skip maintenance, recommend
   `/create-verification-skill`, and never generate or launch it automatically.
3. Handle the maintainer outcome: `clean` and `changed` continue; `blocked` STOPS
   the build and reports the maintainer's evidence. On a `routine/fix/` branch,
   return the exact blocked evidence to `/debug`'s § *Canonical unattended
   escalation owner*; that owner invokes the registry once.

Internal-only changes skip changed-scope maintenance silently. This phase runs
before Phase 2 and the quality gate so any map edits receive both checks.

## Phase 2 — Affected-Test Validation

UI tasks with 3D or video deliverables run the design-stack gates in
`.agents/skills/build/references/design-stack-gates.md` § *Phase 2: 3D and video gates*
before the steps below.

After every slice header is `[x]`:

1. Run the **affected-test command** against the base SHA — every test file the
   build touched, in one run. The pre-push full run is `/wrap-up-session` § *Full suite*.
   This run is not a "tests pass" claim under `/verify-evidence`, which wants
   the full suite; that claim is made after Step 6's run, never from here.
2. Run linter / type checker if configured
3. Confirm all tests pass and no errors
4. If anything fails: fix with `code-debugger`, then re-run

A failing assertion is a regression and stays in this repair loop. If the test
cannot start because of a practical obstacle (missing service, credential,
runtime, or fixture) after reproduction was confirmed on a `routine/fix/`
branch, return the exact command and evidence to `/debug`'s canonical owner as
`verification-blocked` with `reproduction-state=reproduced`; do not treat the
environment as broken product code.

## Phase 3 — Quality Gate

Invoke `/quality-gate` on all files changed during this build:

1. Identify changed files via `git diff --name-only` (against baseline before build started)
2. Run `/quality-gate` on those files
3. Re-run the affected-test command after quality gate completes to confirm no regressions

## Phase 4 — Spec Validation (Persistence Loop)

Compare what was built against the original spec. Loops up to 3 rounds.

```
max_rounds: 3
previous_failures: []
```

### Evidence Required by AC Type

| AC type | Evidence required |
|---------|-------------------|
| `logic` | Unit test passes (covers the function in isolation) |
| `integration` | Integration test passes (real API/DB/service interaction) |
| `user-facing` | E2E walkthrough via `/verify-evidence --scope e2e` — entry in `tasks/e2e-log.md` for current commit short-sha |

If ANY AC is classified `user-facing`:

1. Invoke `/verify-evidence --scope e2e` before declaring Phase 4 complete.

**For each round**:

1. Re-read `specs/[feature-name].md`
2. For every `user-facing` AC, invoke `/verify-evidence --scope e2e` (skip if already run this round with PASS entry for current commit)
3. Walk through each AC:
   - Mark: `✅` (unit/integration test), `✅✅` (e2e walkthrough), `❌` (missing)
4. **If all criteria are `✅` or `✅✅`**: proceed to Phase 5
5. **If any criterion is `❌`**:
   - Compare against `previous_failures`
   - **Same failures as last round** → HALT with circular-fix message, escalate to user
   - **Different failures** → record in `previous_failures`, add tasks, loop to Phase 1
6. **After round 3 with remaining `❌`**: HALT with full status report, escalate to user

On a `routine/fix/` branch, a verification tool or environment that cannot run
is a practical obstacle: return its command, evidence, and the already-confirmed
reproduction verdict to `/debug`'s canonical owner as `verification-blocked`.
An AC that ran and failed remains in the normal loop above.

## Phase 4.5 — Ambiguity Batch Review

Per `AGENTS.md` § *Ambiguity Protocol*, sub-agents emit a single line
when they hit a question whose answer changes the implementation:

```
[AMBIGUITY] <description> | options: A) ... B) ... | picked: <letter> | reason: ...
```

After Phase 4 passes:

1. **Grep every agent output captured this build** for lines starting with `[AMBIGUITY]`.
2. If zero hits: skip this phase silently.
3. If one or more hits: surface them to the user as a single batch in this format:

   ```
   ⚠ Ambiguities resolved during build (please confirm):

   1. <description>
      Picked: <letter> (<reason>)
      Alternatives: <other options>
      Touched: <file paths>
   2. ...
   ```

4. **Do not block** on user response — proceed to Phase 5. The batch is informational;
   the user can request changes in a follow-up turn if a pick was wrong.

## Phase 5 — Backlog Update

If `tasks/backlog.md` exists:
1. Identify which backlog item this build corresponds to
2. Mark the item as `[x]` in `tasks/backlog.md`
3. Update `tasks/project-context.md` `[CURRENT-PHASE]` if the phase is now complete

## Phase 6 — Build Report

End your turn with this report populated from **real command output**:

### Required persistence proofs (run these, paste their output)

1. `git status --short`
2. `git log --oneline <base>..HEAD`
3. `ls specs/ | grep <feature>`
4. `grep -cE '^\s*(- )?\[x\]' tasks/todo.md` vs `grep -cE '^\s*(- )?\[ \]' tasks/todo.md` —
   then confirm every `[x]` slice header has its `> Handover:`

```
══════════════════════════════════════
  BUILD COMPLETE — [Feature Name]
══════════════════════════════════════

Tasks: [X] completed, [Y] added during build
Tests: [N] total, [N] passing, [0] failing
Spec Validation: [all criteria met / N gaps remain]
Quality Gate: [N improvements applied]

Files on disk (persistence proof):
  Spec: /absolute/path/to/specs/<feature-name>.md
  Plan: /absolute/path/to/tasks/todo.md
  Source changes: [git diff --stat summary]

Git state:
  Branch: <branch>
  Commits this build: [N]
  Uncommitted changes: [Y/N]
  Pushed: [NOT YET — /build does not push. /wrap-up-session handles push.]

Acceptance Criteria:
  ✅✅ [user-facing criterion — e2e log entry @ <short-sha>]
  ✅   [logic/integration criterion — test: <test-name>]

Next: /wrap-up-session
══════════════════════════════════════
```

### Forbidden completion patterns

- Claiming "build complete" without the persistence proof block
- Stating a file was "created" or "updated" without showing its absolute path
- Omitting the `Pushed:` line
- A slice header marked `[x]` with no `> Handover:` — the **forbidden state** Slice Close defines; report it as a build failure,
  never as a cosmetic mismatch

## Error Handling


### Sub-Agent Failure (hangs, silent stops, compaction conflicts)

A sub-agent that **crashes** returns null and your fallback catches it. One that **hangs**
returns nothing — no result, no error, no event — so every null-check fallback is downstream of
a return that never happens. Under parallel dispatch this holds the entire phase.

Most common cause: output-compression / compaction layers replace a large tool result with a
placeholder, the agent loops on a failing retrieval call, and it is killed rather than erroring.
This selects agents doing heavy source reading, so the most load-bearing agent is the one that
dies while its siblings complete normally.

Read `.agents/skills/build/references/subagent-resilience.md` before dispatching. Minimum bar:

- Tool-call budget with a "write partial work and stop" escape hatch — converts a hang into a
  degraded return your fallbacks can see
- Symbol-level tools over whole-file `Read` for anything above ~400 lines
- Retry only with a **changed strategy**; an identical prompt fails identically
- Monitor **progress** (results landed, retries started), not file activity — a retry loop
  writes constantly and looks perfectly healthy to an idle-time check
- Budget for the **return**, not just the work — an agent that writes its artifact and dies
  before returning looks identical to total failure, and gets retried from scratch
- Cap the artifact size in the prompt, and never ask for the artifact back in the return
  schema — emitting it twice lands the second copy when context is tightest
- If the output is a mechanical transform (merge, reformat, de-dup), use a **script**, not an
  agent — an LLM re-emitting text verbatim is the most expensive way to run `cat`
- Report what was dropped when a fallback fires
- **Implementation failure**: Retry once with additional context. If still failing, surface to user and pause.
- **Test regression**: Fix with `code-debugger`. Max 3 fix attempts per regression (see circuit breaker).
- **Spec gap found late**: Add tasks dynamically and loop back. Do not silently skip criteria.
- **Build tool missing**: Ask user for the correct command rather than guessing.

### Architectural Circuit Breaker (Graduated Escalation)

When `code-debugger` fails on the same regression, escalate through two tiers before halting:

**Tier 1 — Worker (2 attempts):** Standard debugging at builder tier.
**Tier 2 — Escalation (2 attempts):** Upgrade to reviewer tier for deeper analysis. On Claude Code that resolves to `ceiling (builder floor)` — inherit the session model, but never at or below builder tier — so the retry genuinely escalates instead of re-running the model that just failed twice. Confirm it resolved to something stronger than Tier 1; if it did not, go straight to Tier 3 rather than burning two identical attempts.

**Tier 3 — Circuit breaker (planner tier):**

1. **STOP** fixing symptoms — the design may be the problem.
2. Spawn a `planner` with: the failing test output (all 4 attempts), the files changed across all attempts, the original spec and task description.
   Prompt: "Four fix attempts failed across two model tiers. Analyze whether the implementation approach or spec is flawed. Return (a) a revised approach to try, or (b) 'ARCHITECTURE PROBLEM' with a diagnosis."
3. Revised approach → apply once, re-run tests. `ARCHITECTURE PROBLEM` or another failure → halt and escalate to the user with the full diagnosis. Do NOT attempt further fixes without explicit user direction.

```
⛔ HALTED — Architectural circuit breaker triggered
Regression: [test name]
2 worker + 2 escalated attempts failed; planner analysis: [diagnosis]
User input required before proceeding.
```

> **Backstop first:** before invoking Tier 3, run `/refresh` to snapshot working state to `tasks/checkpoint.md`, so escalation — and any context reset — resumes from a clean, durable record rather than a context that is already saturated with failed attempts.

## Key Principles

- **Autonomous**: No user prompts between tasks. Run to completion or until blocked.
- **Observable**: Log every task completion so progress is visible.
- **Safe**: The affected-test command after every task; the full suite only at the cached baseline and pre-push. Never let regressions accumulate.
- **Spec-faithful**: The spec is the contract. Build is not done until every AC has evidence.

## Claude Code Enhancements

### Task Dispatch
Dispatch sub-agents (`backend-developer` or `frontend-developer`, model as configured in Model Routing table) for each task in Phase 1.
For 2+ independent tasks: dispatch in parallel (multiple Agent tool calls in a single message).

On Claude Code, these resolve via built-in model name resolution (`sonnet`, `haiku`, `opus`).
On Pi + OpenRouter, explicit model IDs from the Model Routing table are used.

**Ceiling-tier agents take no `model` at all.** `code-reviewer`, `security-reviewer`,
`software-design-expert-review`, and `critic` inherit the session model — passing an
override caps the highest-stakes review below the model the user chose.
`critic` is the one exception: it carries a **planner floor**, so pass the planner
alias when the session model is below planner tier and omit `model` otherwise.
See `.agents/references/model-routing.md`.

### Pi and Codex Dispatch

See `.agents/skills/build/references/harness-dispatch.md` § *Pi Dispatch* and § *Codex Dispatch*.

### Per-Task Review
Phase 1 Step 2 remains inline (no agent). Spec compliance check is a read + compare, not a coding task.

### Quality Gate
In Phase 3, invoke `/quality-gate` normally. The quality-gate skill dispatches `software-design-expert-review` on Claude Code.
