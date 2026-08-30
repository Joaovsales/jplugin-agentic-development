---
name: build
description: Execute the task plan from tasks/todo.md autonomously using TDD with sub-agent delegation. Use after /plan is confirmed.
argument-hint: ""
---

# /build — Autonomous Build Orchestrator

Execute the full plan from `tasks/todo.md` autonomously using TDD.
Bridges the gap between `/plan` (design) and `/wrap-up-session` (close).

## Model Routing

Sub-agent model assignment for build orchestration. The Tier column is canonical; concrete provider model IDs live in `PI_SETUP.md` § Sub-Agent Routing, which is their single source — do not copy them back here.

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
2. 2 attempts at reviewer tier — on Claude Code that resolves to `ceiling (builder floor)`, because Reviewer and Builder both map to `sonnet` there, so a plain reviewer-tier retry would re-run the model that just failed twice. The floor makes this rung strictly stronger than step 1 on every session. See `CLAUDE.md` § Model Routing → Floors.
3. Circuit breaker — `planner` at planner tier analyzes all 4 attempts; then halt and escalate to user

Steps 1 and 2 must never resolve to the same model. If they do, the ladder has no middle rung and the first genuine escalation is the circuit breaker — four failed attempts later than intended.

> **For Pi + OpenRouter users:** Session-level routing goes in `~/.pi/agent/presets.json` (see `PI_SETUP.md`). **Sub-agent** routing requires the `pi-subagents` extension (`pi install npm:pi-subagents`) — set `subagents.agentOverrides` in `~/.pi/agent/settings.json` (agent name → model, plus `fallbackModels` for provider failures). Workflow agents live in `.agents/agents/` and are auto-discovered per project. See `PI_SETUP.md` § Sub-Agent Routing.

## Step 0.5 — Isolation

Decide **before** the green baseline whether this build runs in a git worktree.
Pairs with `/wrap-up-session` Step 7.5, which merges and removes it.

**Enter a worktree if ANY of these hold:**

- Invoked from `/yolo`, `/auto-improve`, or `/auto-push` — unattended, so nobody
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
3. Grep `tasks/solutions/` frontmatter (`problem_type`, `module`, `tags`) for learnings relevant to the plan's target area
4. Load `tasks/project-context.md` if it exists (architecture, protection list, conventions)
5. Identify the project's test runner (check `package.json`, `Makefile`, `pyproject.toml`, etc.)
6. Run the full test suite once to establish a **green baseline**
   - If tests fail before you start: fix or flag to user before proceeding
7. **Classify acceptance criteria** — for each AC in the spec, tag as `logic | integration | user-facing`:
   | AC type | Signals |
   |---------|---------|
   | `logic` | Pure functions, validators, transforms, utilities — no I/O |
   | `integration` | API endpoints, DB queries, service-to-service calls, background jobs |
   | `user-facing` | Auth flows, form submissions, navigation, UI state, anything a user sees or clicks |
   When an AC mixes types, classify by the highest tier (`user-facing` > `integration` > `logic`).

## Phase 1 — Task Execution (TDD Loop)

Process every `[ ]` task in `tasks/todo.md` without pausing for user confirmation between tasks.

### Parallel Dispatch Assessment

Before processing tasks sequentially, assess if any can run in parallel.

**Tasks are independent when**:
- They modify different files/modules
- They have no data dependencies on each other
- They don't share state or resources

**If 2+ independent tasks found**:
1. Group tasks by independence
2. Dispatch one sub-agent per independent group, passing
   `isolation: "worktree"` on each `Agent` call **when the groups write files**.
   Independence assessed at plan time is a prediction; worktree isolation makes
   it structurally true, so a mis-grouping surfaces as a merge conflict you can
   see rather than two agents silently overwriting each other.
3. Wait for all to return; check for file conflicts
   Before dispatching, give every sub-agent a tool-call budget with an explicit
   "stop and write partial work" escape hatch, and arm a stall monitor. A hung agent
   returns nothing, so null-check fallbacks never fire and this barrier never releases.
   See `.agents/skills/build/references/subagent-resilience.md`.
4. Run the full test suite **centrally, once** — never instruct the sub-agents to
   run it themselves. Fanning verification out to every agent multiplies context
   for no added signal and is a known way to lose a whole fleet to autocompact
   thrashing. Isolate the *edits*, centralise the *verification*.

**If tasks are sequential/dependent**: process one at a time (Steps 1–4 below).

### Step 1 — Implement the Task

Choose the agent or approach based on task type:

| Task Type | Agent |
|-----------|-------|
| API, database, auth, business logic | `backend-developer` |
| UI components, styling, client state | `frontend-developer` |
| Cross-cutting or unclear | Main context directly |

**Delegation prompt must include**:
- The exact task description from `tasks/todo.md`
- The relevant spec section from `specs/`
- Paths to related source files
- Instruction: "Follow TDD — write failing test first, then minimal implementation, then refactor"

**Role-based context injection from `tasks/project-context.md`** (if it exists):

| Agent | Sections to include |
|-------|---------------------|
| `backend-developer` | `[ARCHITECTURE]` + `[PROTECTION]` + relevant functional requirements |
| `frontend-developer` | `[ARCHITECTURE]` + `[PROTECTION]` + `[CONVENTIONS]` + relevant requirements |
| `code-debugger` | Failing test + relevant code only |

Do not pass the full project-context to every agent — extract only relevant sections. For bulk artifacts (logs, long command output), follow the **Large-Artifact Handoff** convention in `.claude/project.md` — truncate-with-pointer, never inline.

### Step 2 — Per-Task Spec Compliance Check (inline, no agent)

After implementation, run this check inline in the main context:

1. Re-read the task's acceptance criteria from `specs/`
2. Run `git diff --cached` (or `git diff HEAD`) to see the actual changes
3. Report:
   - **PASS** if the change addresses the acceptance criteria
   - **MISMATCHES** — list each specific gap between spec and implementation

If mismatches found: send feedback to the implementing agent for fixes, then re-check.

### Step 3 — Run Tests

1. Run the new test — confirm it **passes**
2. Run the **full test suite** — confirm no regressions
3. If failures: fix with `code-debugger` agent and full failure context
4. Repeat until green

### Step 4 — Mark Complete and Continue

- Change `[ ]` to `[x]` in `tasks/todo.md`
- Log: `✓ [Test Name] — [one-line summary]`
- **Task-boundary checkpoint**: silently refresh `tasks/checkpoint.md` via the shared flush (`bash .claude/hooks/pre-compact.sh </dev/null`) — no prompt, no commit. This keeps on-disk state current at each semantic (task) boundary, so a context compaction or `/refresh` loses at most one task of work.
- **Task status**: when the project tracks tasks externally, claim the task and
  update its status through `/task-registry` (never by calling `gh` or Jira
  directly). Status writes are gated the same way every other external write is —
  dry-run unless `--apply` and the project's approval setting allow it.
- Move to the next `[ ]` task immediately (no user prompt)
- If a task is blocked by a previous failure, note it and skip to the next unblocked task

## Phase 1.5 — Changed Verification Map

After all tasks are `[x]`, classify the completed work. If ANY acceptance
criterion is `user-facing`:

1. Invoke `/maintain-verification-skill --scope changed` with the session intent,
   base-to-HEAD diff, touched specs, and completed task entries. This idempotently
   reconciles the project-local feature map on the active branch.
2. If no project-local verification skill exists, skip maintenance, recommend
   `/create-verification-skill`, and never generate or launch it automatically.
3. Handle the maintainer outcome: `clean` and `changed` continue; `blocked` STOPS
   the build and reports the maintainer's evidence.

Internal-only changes skip changed-scope maintenance silently. This phase runs
before the full suite and quality gate so any map edits receive both checks.

## Phase 2 — Full Suite Validation

After all tasks are `[x]`:

1. Run the **complete test suite**
2. Run linter / type checker if configured
3. Confirm all tests pass and no errors
4. If anything fails: fix with `code-debugger`, then re-run

## Phase 3 — Quality Gate

Invoke `/quality-gate` on all files changed during this build:

1. Identify changed files via `git diff --name-only` (against baseline before build started)
2. Run `/quality-gate` — this executes all 3 phases (structural, AI anti-patterns, APOSD design)
3. Re-run full test suite after quality gate completes to confirm no regressions

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
| `user-facing` | E2E walkthrough via `/verify --scope e2e` — entry in `tasks/e2e-log.md` for current commit short-sha |

If ANY AC is classified `user-facing`:

1. Invoke `/verify --scope e2e` before declaring Phase 4 complete.

**For each round**:

1. Re-read `specs/[feature-name].md`
2. For every `user-facing` AC, invoke `/verify --scope e2e` (skip if already run this round with PASS entry for current commit)
3. Walk through each AC:
   - Mark: `✅` (unit/integration test), `✅✅` (e2e walkthrough), `❌` (missing)
4. **If all criteria are `✅` or `✅✅`**: proceed to Phase 5
5. **If any criterion is `❌`**:
   - Compare against `previous_failures`
   - **Same failures as last round** → HALT with circular-fix message, escalate to user
   - **Different failures** → record in `previous_failures`, add tasks, loop to Phase 1
6. **After round 3 with remaining `❌`**: HALT with full status report, escalate to user

## Phase 4.5 — Ambiguity Batch Review

Per `.claude/project.md` § *Ambiguity Protocol*, sub-agents emit a single line
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
4. `grep -c '^\[x\]' tasks/todo.md` vs `grep -c '^\[ \]' tasks/todo.md`

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
- **Safe**: Full test suite after every task. Never let regressions accumulate.
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
See `CLAUDE.md` § Model Routing.

### Pi Dispatch

- Requires the `pi-subagents` extension (`pi install npm:pi-subagents`). Workflow agents come from `.agents/agents/` (auto-discovered per project); the extension adds `scout`, `oracle`, `researcher`, `context-builder` for roles the workflow does not define.
- Dispatch with natural language or the `subagent` tool — e.g. "Have backend-developer implement this task" or `subagent({ agent: "backend-developer", task: "..." })`. Use `scout` for recon before planning, `oracle` for a second opinion on risky decisions.
- Do NOT pass per-call model params on Pi — routing comes from `subagents.agentOverrides` in `~/.pi/agent/settings.json`; `fallbackModels` absorbs provider failures.
- For 2+ independent tasks: ask for a parallel run ("run backend-developer and frontend-developer in parallel for tasks A and B") and respect `globalConcurrencyLimit`.
- If the extension is not installed, run Phase 1 inline in the main context (single-agent).

### Per-Task Review
Phase 1 Step 2 remains inline (no agent). Spec compliance check is a read + compare, not a coding task.

### Quality Gate
In Phase 3, invoke `/quality-gate` normally. The quality-gate skill dispatches `software-design-expert-review` for Phase 3 on Claude Code.
