---
name: auto-improve
description: Autonomous discover-then-fix loop. Triages the existing backlog/bugs first and acts on a ready item when one exists; runs a full parallel discovery scan only when the backlog is dry or on the weekly deep-sweep day. Implements exactly one improvement with TDD and opens a PR. Built for daily unattended cloud runs.
argument-hint: "[optional focus area, e.g. 'router' or 'perf']"
harness: universal
---

# /auto-improve — Triage First, Discover When Dry, Ship One Improvement

> **Dispatching sub-agents?** Read `.agents/skills/build/references/subagent-resilience.md` first. This skill runs unattended, so a hung
> sub-agent has no human watching it: give every agent a tool-call budget with a "write partial
> work and stop" escape hatch, arm a stall monitor, and never retry a deterministic failure
> with an identical prompt.

An unattended cousin of `/auto-push`. Nobody hands you a plan. You **act on already-flagged work first**, fall back to **fresh discovery only when there's nothing ready to act on** (or on the weekly deep-sweep day), then implement the single highest-value improvement with TDD, verify no regressions, and open a PR — all in one run, no user prompts.

Designed to run daily on the cloud. Be conservative: one focused, reviewable change per run beats a sprawling risky diff, and cheap days (act on backlog) should not pay for a full deep scan.

---

## The Iron Law

```
ONE RUN → ONE PR → EXACTLY ONE IMPROVEMENT.
NEVER PUSH TO main/master. PR ONLY.
NO PR IF THE FULL TEST SUITE IS NOT GREEN.
TRIAGE BEFORE YOU DISCOVER — do not run the deep scan when a ready backlog item exists (unless it is the weekly deep-sweep day).
IF NO SAFE IMPROVEMENT EXISTS, LOG FINDINGS TO backlog.md AND OPEN A DOCS-ONLY PR — DO NOT FORCE A CHANGE.
```

The moment you are tempted to bundle a second unrelated fix "while you're here" — stop. Log it to the backlog for the next run.

---

## Pre-Flight — Load Context & Guard Rails

1. **Read the working state**: `tasks/todo.md`, `tasks/backlog.md`, `tasks/history.md`, and grep `tasks/solutions/` frontmatter (`problem_type`, `module`, `tags`) for learnings relevant to the target area. Skip any that don't exist.
2. **Branch safety, in a worktree — mandatory**: create `claude/auto-improve-<date>` and check it out **in its own git worktree**, never in the shared clone. Never work on `main`/`master`/`develop`.

   This is not optional here the way it is in `/build` Step 0.5. A daily cloud run is unattended by definition, so it is precisely the case where another session or a scheduled job checks out a different branch in the shared clone and rewrites files under a live edit — with nobody watching to notice. It also makes step 3 trivially true: a fresh worktree cannot inherit someone else's uncommitted work, so there is nothing to accidentally sweep into the PR.

   Prefer the harness-native `EnterWorktree` tool; this instruction is what authorises it. Otherwise `.agents/skills/build/scripts/bootstrap-worktree.sh claude/auto-improve-<date>`. Never a bare `git worktree add` — no `node_modules`, no `.env*`, and a suite gated on an env file will skip those tests and report green. The Iron Law forbids a PR on a non-green suite; a *falsely* green one defeats it just as thoroughly.
3. **Clean tree**: `git status --short` **in the worktree**. It should be empty by construction; if it is not, stop — something is wrong with the bootstrap. Uncommitted changes in the parent clone are not your concern and must not enter the PR.
4. **Green baseline**: run the full test suite (identify the runner from `package.json` / `Makefile` / `pyproject.toml` / `tests/run.sh`). If the baseline is RED, that failing test *becomes* the improvement to fix. Do not build on top of a broken baseline.

If a guard cannot be satisfied and it is not itself the thing to fix, STOP and report — do not proceed.

---

## Phase 1 — TRIAGE (cheap, always) → discovery gate

First, spend almost nothing deciding whether you even need to discover.

1. **Scan already-flagged work** (read-only, no subagents): from `tasks/backlog.md`, `tasks/todo.md`, and open bug-track documents in `tasks/solutions/` (body status `open`/`investigating`), collect every item that is **ready-to-act** — meaning it is triaged, has enough context to implement cold, is unblocked, and is not marked done/wontfix.
2. **Determine the deep-sweep day**: check today's date. If it is **Sunday** (the weekly deep-sweep day), you will run full discovery regardless, so debt/design/perf still gets found on a regular cadence.
3. **Gate**:
   - **Ready item exists AND it is not the deep-sweep day** → **skip discovery entirely.** Go to Phase 2 and select among the ready backlog/bug items. This is the cheap common path.
   - **No ready item exists, OR it is the deep-sweep day** → run **DISCOVERY** below, then Phase 2.

State in your output which branch of the gate you took and why (e.g. "3 ready backlog items; not Sunday → skipping deep scan").

### DISCOVERY (only when the gate opens)

Dispatch independent read-only sub-agents **in parallel** (one message, multiple Agent calls) to build a candidate list. Each returns findings with `{title, category, file:line, severity, est. effort, risk}`:

| Sub-agent | Model | Charter |
|---|---|---|
| Test health | sonnet | Run full suite + coverage. Report failing tests, flaky tests, coverage gaps < 80%, slowest tests. |
| Design review | *ceiling* | Run `/software-design-expert-review` on recently changed + core files. Report MUST-FIX / SHOULD-FIX APOSD red flags. |
| Performance | sonnet | Scan hot paths (pipeline stages, router, encoders) for obvious inefficiencies — redundant work, N+1 subprocess calls, unbounded loops. |

*ceiling* means pass no `model` at all so the agent inherits the session model
(`CLAUDE.md` § *Model Routing*). The design reviewer is a Ceiling role; naming an
alias in this column pins it just as surely as frontmatter would, and pins it for
exactly the users who chose a stronger session.

The design-review dispatch is a **repo survey**, so it carries the exception in
`CLAUDE.md` § *Review Dispatch Contract*: there is no session diff, no spec and no
closed task list to pass. State that rather than omitting it — pass
`no spec — repo survey, nothing built this run` and `deferrals: none`, plus the
output format. An omitted line reads as "nobody told me" and puts the reviewer back
to guessing, which is what the contract exists to stop.

Do **not** fix anything in this phase. Discovery is read-only. Merge these findings with the ready backlog/bug items for ranking in Phase 2.

---

## Phase 2 — SELECT (rank, pick one)

Rank the candidate pool — either the ready backlog items alone (cheap path) or backlog + freshly-discovered findings (discovery path) — scored on **value ÷ (effort × risk)**:

- **Value**: user-facing bug > flaky test > perf win > design/maintainability > cosmetic.
- **Effort**: prefer changes shippable within one run as a small, reviewable diff.
- **Risk**: prefer changes with existing test coverage or an easy new test. Deprioritize anything touching public interfaces or lacking a safety net.

Pick **exactly one** item (respect `$ARGUMENTS` as a focus filter if given). If discovery ran, write the newly-found unpicked candidates to `tasks/backlog.md` so they persist for future runs. State the pick and the one-line rationale in your output.

If the selected candidate was freshly discovered and has no task-registry
reference, first add one canonical compact row with a stable `task-id` to
`tasks/todo.md` using task-registry's `render_row` library seam. Then resolve that
ID normally. Pass `include_kind=True` so the claim and registered task retain the
same canonical kind. This local registration happens before routing; never invent a
reference or pass an ad-hoc `Task` around the registry.

If the top candidate's risk is high and coverage is thin → drop to the next safe one. If **nothing** is safely actionable → skip to Phase 5 in "findings-only" mode.

---

## Phase 3 — IMPLEMENT (TDD, delegated)

Pass the chosen item's task-registry reference and a structured claim to
`materialize_route` in `.agents/skills/route/scripts/route_issue.py`. After it
returns, execute the materialized lane only through `/build` and its mandatory
`finalize_route` row. Phase 4 owns the lane's verification and reviewer rows;
Phase 5 owns its single `/wrap-up-session` row. Never execute those rows early or
repeat them in both the lane and the outer phases.
The shared engine owns lane policy; `/auto-improve` supplies the unattended channel
grant and must not maintain a second routing table. This deliberately changes the
old behavior: bugs, refactors, and small features no longer branch here, so exactly
one lane decision is written for the repository.

Follow TDD strictly: failing/characterization test → minimal change → refactor. Keep the diff minimal and on-topic (Minimal Impact rule).

---

## Phase 4 — VERIFY (no regressions)

1. Run the **full** test suite. It must be green. If red and you cannot make it green safely in this run → `git reset` your change, revert to findings-only mode (Phase 5), and log why.
2. Confirm `/build` completed its `/quality-gate`, then execute the materialized
   lane's verification and reviewer rows exactly once. Its Apply Gate runs
   normally — **no prompt added**. A `MUST-FIX` that is not `gated_auto` at
   `confidence >= 75` is not auto-appliable: fix it deliberately if you can,
   otherwise carry it into the PR body as an unresolved finding with its `owner`.
   Never widen `autofix_class`, and never downgrade a finding, to get a clean gate.
3. Confirm coverage on new/changed code ≥ 80%.

No green suite → no PR. This is non-negotiable.

---

## Phase 5 — SHIP

**Normal mode (a change was made):**
1. Update the affected bug-track documents in `tasks/solutions/` and `tasks/backlog.md` to reflect what was fixed and what remains.
2. Execute the materialized lane's `/wrap-up-session` row exactly once (commit with
   a conventional message → push branch → open PR).
3. PR body: what was changed, why it was the highest-value pick, the ranked runner-ups deferred to backlog, and the test/coverage evidence.

**Findings-only mode (nothing safe to change):**
1. Commit the enriched `backlog.md` / new bug-track documents in `tasks/solutions/` with newly discovered issues (each with enough context to be fixed cold in a later run).
2. Open a docs-only PR titled `chore(backlog): triage from auto-improve <date>`.
3. Never leave the run with zero output — a triaged backlog is a valid, honest result.

---

## Failure & Honesty Rules

- Report outcomes faithfully: if tests fail, say so with the output; if you reverted, say what and why.
- Never mark an improvement "done" on a red suite or a partial implementation.
- One PR per run. If you discover a second urgent issue mid-run, log it — the next scheduled run will pick it up.
