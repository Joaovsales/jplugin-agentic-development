---
name: yolo
description: Fully autonomous loop. User describes an idea; the agent runs /plan, /build, and /wrap-up-session in a Ralph-style loop until the backlog is empty or a circuit breaker trips. No user prompts between phases.
argument-hint: "[short idea description]"
disable-model-invocation: false
harness: universal
---


# /yolo — Fully Autonomous Plan → Build → Wrap-Up Loop

> **Dispatching sub-agents?** Read `.agents/skills/build/references/subagent-resilience.md` first. This skill runs unattended, so a hung
> sub-agent has no human watching it: give every agent a tool-call budget with a "write partial
> work and stop" escape hatch, arm a stall monitor, and never retry a deterministic failure
> with an identical prompt.

You-Only-Live-Once mode. The user gives you an idea; you take it from spec through merge with **no user prompts in between**. Modeled after the Ralph Loop pattern: a single prompt drives repeated `plan → build → wrap-up` iterations, with state persisted on disk (not in context) so each phase starts cold and finishes verifiable.

---

## Model Routing

Sub-agent delegations follow the Model Routing table in `/build` (planner tier for planning/architecture, build tier for coding agents, review tier for reviewers, scout tier for exploration).

- **Claude Code** — pass `model` explicitly on every Agent tool call per that table.
- **Pi** — no per-call model params; routing resolves from `subagents.agentOverrides` in `~/.pi/agent/settings.json` (requires the `pi-subagents` extension).

---

## The Iron Law

```
NO USER PROMPTS BETWEEN PHASES.
PLAN AUTO-CONFIRMS. BUILD RUNS TO COMPLETION. WRAP-UP COMMITS AND PUSHES.
THE LOOP ONLY EXITS ON: BACKLOG EMPTY, CIRCUIT BREAKER, OR USER INTERRUPT.
ALWAYS RUN IN A WORKTREE.
```

If you find yourself about to ask "should I proceed?" — you are violating yolo mode. The user already said yes by invoking `/yolo`.

---

## Isolation — mandatory, not a judgement call

Enter a worktree **before the first `/plan`**, and stay in it for the whole loop.
`/build` Step 0.5 treats this as a decision; here it is not one.

The reason is the Iron Law itself. No user prompts means nobody is watching, and
an unattended loop is exactly when another session — or automation on a
schedule — checks out a different branch in the shared clone and rewrites the
files underneath a running edit. Supervised, you notice. Here you do not, and
the loop keeps building against a tree that silently became something else.

**How:** prefer the harness-native `EnterWorktree` tool; this instruction is what
authorises it. Otherwise `.agents/skills/build/scripts/bootstrap-worktree.sh <branch>`.

Never a bare `git worktree add` — no `node_modules`, no `.env*`, and a suite
gated on an env file will skip those tests and report green. An unattended loop
that trusts a false green will happily build on top of it for hours.

`/wrap-up-session` Step 7.5 closes the worktree at the end of each iteration.

---

## When to Use — and When NOT to

| Use `/yolo` when… | Use something else when… |
|---|---|
| User wants a complete feature shipped end-to-end with minimal supervision | Spec is genuinely ambiguous and needs a real interview → use `/plan` |
| Idea is well-scoped (one feature, one bug fix, one refactor) | Architecture decision is unsettled → use `/brainstorm` first |
| The branch is disposable / experimental | Touching production-critical paths without review → use `/auto-push` (requires plan approval) |
| Backlog already exists and user wants it ground through | One-off task that doesn't need the full review machinery → just write the code |

---

## Pre-Flight Checks

Before entering the loop:

1. **Branch safety**: Confirm we are NOT on `main`, `master`, or `develop`. If we are: STOP and ask user for a feature branch name.
2. **Clean tree**: Run `git status --short`. If uncommitted changes exist that aren't from this session, STOP and ask user how to handle them.
3. **Test baseline**: Run the full test suite once. If red before we start, STOP — yolo mode cannot loop on a broken baseline.
4. **Idea capture**: Write the user's idea verbatim to `tasks/yolo-idea.md` (overwrite any previous). This is the source-of-truth prompt that survives context resets.
5. **Initialize log**: Create `tasks/yolo-log.md` if missing, with this header:
   ```markdown
   # Yolo Session Log
   > Append-only. One entry per iteration. State lives here, not in context.
   ```

If any pre-flight check fails, STOP. Do not proceed with partial guards.

---

## The Loop

```
iteration = 0
consecutive_failures = 0
MAX_ITERATIONS = 10
MAX_CONSECUTIVE_FAILURES = 3

while True:
    iteration += 1
    if iteration > MAX_ITERATIONS: HALT (iteration cap)
    if consecutive_failures >= MAX_CONSECUTIVE_FAILURES: HALT (circuit breaker)

    next_item = pick_next_work_item()
    if next_item is None: EXIT (backlog empty, all done)

    result = run_iteration(next_item)
    log_iteration(iteration, next_item, result)

    if result == FAIL:
        consecutive_failures += 1
    else:
        consecutive_failures = 0
```

### Picking the Next Work Item

Order of preference:

1. **First iteration only**: use the idea from `tasks/yolo-idea.md`.
2. **Subsequent iterations**:
   - If `tasks/backlog.md` exists and has `[ ]` items → take the top one.
   - Else if `tasks/todo.md` has `[ ] TDD:` tasks left over → resume those (re-enter `/build` directly, skip plan phase).
   - Else → EXIT loop (no work left).

If no backlog exists and the user's idea is a single feature, the loop is expected to run **once** and exit. That's fine — it's still yolo mode, just short.

---

## Per-Iteration Sequence

Each iteration runs three phases. **No user prompts between them.** Log every phase outcome to `tasks/yolo-log.md`.

### Phase A — Plan (auto-confirmed)

Invoke the `/plan` skill on the current work item, with the following overrides:

| `/plan` step | Yolo override |
|---|---|
| Step 1 — Interview | **Do not interview the user.** Synthesize a spec from the idea (or backlog item) and any context in `tasks/project-context.md`. If genuinely ambiguous: pick the most conservative interpretation and note the assumption in the spec's "Assumptions" section. |
| Step 2 — Write spec | Run normally. Spec file must be written to `specs/<feature-name>.md`. |
| Step 3 — Write plan | Run normally. Tasks appended to `tasks/todo.md`. |
| Step 4 — Present and confirm | **SKIPPED.** No user prompt. Proceed directly to Phase B. |
| Step 5 — Divergence check | Run normally. If divergence found, log it to `tasks/yolo-log.md` and proceed — do NOT prompt user. |

After Phase A: `specs/<feature>.md` and `tasks/todo.md` must exist on disk with the new plan block.

### Phase B — Build

Invoke `/build`. It is already autonomous. Run it to completion.

- Phases 1–5 run as normal (TDD, quality gate, spec validation, backlog update).
- Phase 6 (build report) is required — paste it into `tasks/yolo-log.md`.
- If `/build`'s Phase 4 spec validation HALTS after 3 rounds: this iteration is a FAIL. Increment `consecutive_failures` and continue the outer loop (don't escalate to user yet).
- If `/build`'s architectural circuit breaker trips: same — log as FAIL, continue.

### Phase C — Wrap Up

Invoke `/wrap-up-session` with one override:

| `/wrap-up-session` step | Yolo override |
|---|---|
| Step 6.3 — E2E coverage gate | If a user-facing AC lacks an e2e walkthrough, **do not prompt the user**. Run `/verify --scope e2e` automatically. If verify fails: log gap and continue. |
| Step 7 — Commit gate (any MUST-FIX unresolved → STOP) | If a MUST-FIX cannot be auto-fixed within the wrap-up loop, mark this iteration FAIL and **do not push**. The circuit breaker handles repeated failures. |
| Step 5.1 — Apply Gate | Run normally, **no prompt added**. A `MUST-FIX` that is not `gated_auto` at `confidence >= 75` is not auto-appliable: fix it deliberately inside the wrap-up loop if you can, otherwise it is an unresolved MUST-FIX and this iteration is FAIL. Never widen `autofix_class`, and never downgrade a finding, to get the loop moving. |
| Step 7 — Push | Run normally. Push to the feature branch. |
| Step 8 — Deployment verification | Run normally if configured. |
| Step 8.5 — Terminal PR assertion | **This run is unattended.** Declare it, so the assertion runs: the branch is an ordinary feature branch, and nothing in its name tells wrap-up a human stopped watching. |

After Phase C: commits exist, push attempted (success or logged failure).

---

## Logging Each Iteration

Append to `tasks/yolo-log.md` after every iteration:

```markdown
## Iteration <N> — <YYYY-MM-DD HH:MM> — <PASS|FAIL|HALT>

**Work item**: <name>
**Spec**: specs/<file>.md
**Plan tasks**: <X> added, <Y> completed
**Tests**: <N> passing / <M> failing
**Commits**: <short-sha-range>
**Pushed**: <yes|no — reason>
**Failure mode** (if any): <one line>
**Next**: <next backlog item OR "exit — backlog empty">
```

The log IS the memory. A fresh context can resume the loop by reading this file alone.

---

## Termination Conditions

Exit cleanly when:

- **Backlog empty**: no `[ ]` items remain in `tasks/backlog.md` and no leftover `[ ]` tasks in `tasks/todo.md`.
- **Iteration cap**: 10 iterations completed (prevents runaway loops). User can re-invoke `/yolo` to continue.

HALT (escalate to user) when:

- **Circuit breaker**: 3 consecutive iteration FAILs. Surface the last 3 failure modes from `tasks/yolo-log.md` and stop.
- **Unrecoverable pre-flight**: dirty tree, red baseline, protected branch.
- **Push permanently rejected**: branch protection, permission denied (network errors retry per `/wrap-up-session`).

When halting, write a final entry to `tasks/yolo-log.md` titled `## HALT — <reason>` with diagnostic context. Do not silently exit.

---

## Common Rationalizations — Reject These

| Excuse | Reality |
|---|---|
| "The user might want to review this plan first" | They opted into yolo. Run the plan auto-confirmed. |
| "I'll skip the test suite to save time" | The baseline check is the ONLY thing keeping the circuit breaker honest. |
| "This spec ambiguity needs a clarifying question" | Pick the conservative interpretation, document it in the spec, proceed. |
| "MUST-FIX failed but I'll push anyway" | No. Mark iteration FAIL. Let the circuit breaker decide. |
| "I'll keep the plan + build + wrap state in my head between iterations" | No. Write to `tasks/yolo-log.md`. Context is volatile; disk is not. |
| "I'll just run /build directly without /plan" | Only valid when resuming leftover `[ ]` tasks from a prior iteration. New work items go through Phase A. |
| "The loop already ran once — I'm done" | Check the backlog. If items remain, loop again. |

---

## Red Flags — STOP

- About to send an `AskUserQuestion` between phases → STOP, you're breaking yolo mode.
- About to push to `main`/`master` → STOP, wrong branch.
- About to start iteration N+1 while previous iteration's commits haven't been pushed → STOP, fix push first.
- `tasks/yolo-log.md` missing an entry for the last iteration → STOP, log before continuing.
- About to mark backlog items `[x]` that weren't actually built → STOP, that's lying.

---

## Final Report

When the loop exits (cleanly or via HALT), emit:

```
══════════════════════════════════════
  YOLO COMPLETE — <N> iterations
══════════════════════════════════════

Outcome: <ALL-DONE | ITERATION-CAP | CIRCUIT-BREAKER | HALT-<reason>>
Branch: <branch>
Commits this session: <N>
Tests: <PASS | FAIL — details>

Iterations:
  ✓ Iter 1 — <work item> — <short-sha>
  ✓ Iter 2 — <work item> — <short-sha>
  ✗ Iter 3 — <work item> — FAIL: <one line>

Backlog state:
  Remaining: <N items / 0>
  Completed this session: <N>

Log: tasks/yolo-log.md
Next: <suggested follow-up — re-run /yolo, or /wrap-up-session if HALT, or none>
══════════════════════════════════════
```

---

## Integration

- **Called by**: User directly. Not invoked by other skills.
- **Calls**: `/plan` (with Phase A overrides), `/build`, `/wrap-up-session` (with Phase C overrides), `/verify --scope e2e`.
- **Pairs with**: `/auto-push` — the supervised cousin. Same pipeline, but `/plan` keeps its user-confirmation gate.
- **Persists state via**: `tasks/yolo-idea.md`, `tasks/yolo-log.md`, `tasks/backlog.md`, `tasks/todo.md`, git history.

---

## Key Principles

- **Files are memory, not context** — every iteration must be resumable from disk alone (Ralph Loop principle).
- **Pipeline over prompt** — yolo doesn't reinvent `/plan`, `/build`, `/wrap-up`; it chains them with the confirmation gates lifted.
- **Circuit breaker, not heroics** — 3 consecutive failures → HALT. Don't fight harder; surface to user.
- **The log is non-negotiable** — if it's not in `tasks/yolo-log.md`, it didn't happen.
- **Quality gates stay on** — TDD, spec validation, security scan, e2e verify all still run. Yolo removes prompts, not safeguards.
