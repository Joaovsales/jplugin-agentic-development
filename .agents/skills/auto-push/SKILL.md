---
name: auto-push
description: Semi-autonomous pipeline. User describes an idea; agent runs /plan and PAUSES for explicit approval. After approval, /build and /wrap-up-session run autonomously through commit and push.
argument-hint: "[short feature description]"
disable-model-invocation: false
harness: universal
---


# /auto-push — Approve-Once, Ship-Hands-Free

> **Dispatching sub-agents?** Read `.agents/skills/build/references/subagent-resilience.md` first. This skill runs unattended, so a hung
> sub-agent has no human watching it: give every agent a tool-call budget with a "write partial
> work and stop" escape hatch, arm a stall monitor, and never retry a deterministic failure
> with an identical prompt.

A supervised cousin of `/yolo`. The user describes a feature; you produce a spec and plan; you **wait for an explicit `y` approval**; then the rest of the pipeline (build → review → tests → commit → push → deploy) runs autonomously with no further prompts.

The single approval gate is the whole point. After it, you don't ask again.

---

## Isolation — mandatory once the gate is passed

Enter a worktree **before `/plan`**, so the branch the user approves is the
branch that ships. `/build` Step 0.5 treats this as a decision; here it is not.

The approval gate is what makes this unattended. Everything after it — build,
review, tests, commit, push — runs with nobody watching, which is exactly when a
concurrent session or a scheduled job checks out another branch in the shared
clone and rewrites files under a live edit. The user approved a plan; they
should get that plan, not whatever the tree became.

**How:** prefer the harness-native `EnterWorktree` tool; this instruction is what
authorises it. Otherwise `.agents/skills/build/scripts/bootstrap-worktree.sh <branch>`.

Never a bare `git worktree add` — no `node_modules`, no `.env*`, and a suite
gated on an env file will skip those tests and report green. Pushing on a false
green is worse here than in `/yolo`, because the user believes a human approved
this one.

`/wrap-up-session` Step 7.5 closes the worktree after the push.

---

## Model Routing

Sub-agent delegations follow the Model Routing table in `/build` (planner tier for planning/architecture, build tier for coding agents, review tier for reviewers, scout tier for exploration).

- **Claude Code** — pass `model` explicitly on every Agent tool call per that table.
- **Pi** — no per-call model params; routing resolves from `subagents.agentOverrides` in `~/.pi/agent/settings.json` (requires the `pi-subagents` extension).

---

## The Iron Law

```
ONE APPROVAL GATE, AT THE PLAN STEP.
NO USER PROMPTS BETWEEN BUILD AND PUSH.
NO PUSH WITHOUT THE APPROVAL.
```

If you find yourself about to ask the user a second question after they approved the plan — you are violating auto-push mode. The "y" was the only decision they signed up to make.

---

## When to Use — and When NOT to

| Use `/auto-push` when… | Use something else when… |
|---|---|
| User wants the plan reviewed but the build to ship without supervision | Truly autonomous mode — even spec auto-confirmed → `/yolo` |
| Touching production-relevant code where the plan matters | Quick prototype on a throwaway branch → `/yolo` |
| Single feature, single PR | Multi-feature loop through a backlog → `/yolo` |

---

## Pre-Flight Checks

Before starting:

1. **Branch safety**: Run `git rev-parse --abbrev-ref HEAD`. Confirm we are NOT on `main`, `master`, or `develop`. If we are: STOP and ask the user for a feature branch name.
2. **Clean tree**: Run `git status --short`. If unrelated uncommitted changes exist, surface them and ask user how to handle before starting.
3. **Test baseline**: Run the full test suite once. If red: STOP — auto-push will not commit on top of a broken baseline.

If any pre-flight check fails, STOP. Do not proceed past unresolved guards.

---

## The Pipeline (3 Phases, 1 Gate)

### Phase A — Plan (with the approval gate)

Run `/plan` **as-is**. Do not override anything. The user's interview, spec, and confirmation gate all run normally.

The plan phase ends with `/plan` asking:

> "Does this spec and plan meet your requirements? Once you confirm with **'y'**, I'll begin the TDD loop."

This is the **only** user prompt in the entire `/auto-push` flow.

**Approval handling**:

| User response | Action |
|---|---|
| `y` / `yes` / `approved` / `ship it` | Proceed to Phase B immediately. |
| Any change request (e.g. "add X", "split task 3", "use Y instead") | Edit the spec/plan accordingly, re-present, ask again. Loop here until `y` or abort. |
| `n` / `no` / `abort` / `cancel` | STOP. Leave spec/plan files in place. Do not proceed to build. |
| Silence / unclear response | Ask once more, explicitly: "Approve plan and run build+push autonomously? (y/n)". If still unclear, treat as `n`. |

Once `y` is received, **stop asking questions**. The rest is on you.

### Phase B — Build (autonomous)

Invoke `/build`. It is already autonomous — no overrides needed for build itself. Run it to completion.

- All TDD, quality gate, spec validation, backlog update phases run as normal.
- If `/build`'s Phase 4 spec validation HALTS after 3 rounds: stop the auto-push pipeline. Do NOT proceed to wrap-up. Report the HALT to the user with the validation failures.
- If `/build`'s architectural circuit breaker trips: same — stop, report.

Unlike `/yolo`, there is no outer loop. A build failure ends the auto-push pipeline; the user gets the failure report and decides what to do.

### Phase C — Wrap Up (autonomous, with one override)

Invoke `/wrap-up-session` with these overrides:

| `/wrap-up-session` step | Auto-push override |
|---|---|
| Step 6.3 — E2E coverage gate | If a user-facing AC lacks an e2e walkthrough, **do not prompt the user**. Run `/verify --scope e2e` automatically. The approval covered "ship it"; e2e verification is part of shipping. |
| Step 7 — Commit gate (MUST-FIX unresolved → STOP) | If a MUST-FIX cannot be auto-fixed, STOP and report. Do NOT push partial work. The approval did not cover skipping safety gates. |
| Step 5.1 — Apply Gate | Run normally, **no prompt added**. A `MUST-FIX` that is not `gated_auto` at `confidence >= 75` is not auto-appliable: fix it deliberately inside the wrap-up loop if you can, otherwise STOP and report it as unresolved. Never widen `autofix_class`, and never downgrade a finding, to reach the push. |
| Step 7 — Push | Run normally. Push to the feature branch. |
| Step 8 — Deployment verification | Run normally if configured. |

Everything else runs as `/wrap-up-session` defines it: code review (4 parallel passes), security scan, tests, learnings capture.

---

## Termination Conditions

**Success** — pipeline ran end-to-end:
- Plan approved
- Build completed (all ACs verified)
- Wrap-up committed and pushed
- Deployment verified (if configured)

**Stop-and-report** — pipeline halts and surfaces to user:
- User declines plan approval → stop after Phase A, files preserved
- Build spec validation HALT → stop after Phase B, report unmet ACs
- Build circuit breaker → stop after Phase B, report failures
- Wrap-up MUST-FIX can't auto-fix → stop before push, report findings
- Push permanently rejected (branch protection, permission) → stop, report

In every stop case, leave the working tree in a recoverable state. The user can fix whatever's wrong and re-run `/auto-push`, `/build`, or `/wrap-up-session` directly.

---

## Common Rationalizations — Reject These

| Excuse | Reality |
|---|---|
| "The user might want to see this implementation detail before I commit" | They approved the plan. The commit is downstream of "ship it". |
| "I'll skip the E2E gate since the unit tests pass" | No. User-facing ACs need e2e evidence; that's `/verify --scope e2e`, not unit tests. |
| "MUST-FIX is annoying — I'll just push anyway" | No. The approval did not authorize skipping safety gates. STOP and report. |
| "I should ask if they want me to also update the docs" | No. If docs weren't in the plan, they aren't in the build. Mention as a follow-up in the final report. |
| "Let me confirm the branch name before pushing" | The branch was set at pre-flight. Push to that branch. |
| "This is similar enough to /yolo that I'll skip the plan approval" | No. The approval gate is what makes auto-push different from yolo. Honor it. |

---

## Red Flags — STOP

- About to ask the user anything between approval and push → STOP, that's a second gate.
- About to push without an explicit approval recorded → STOP, no approval = no push.
- About to push to `main`/`master` → STOP, wrong branch.
- About to skip `/wrap-up-session`'s test suite to "save time" → STOP, tests gate push.
- User said "y" then immediately said "wait" or "actually…" → treat as withdrawn approval. STOP and re-confirm.

---

## Final Report

When the pipeline completes (success or stop), emit:

```
══════════════════════════════════════
  AUTO-PUSH COMPLETE — <feature name>
══════════════════════════════════════

Outcome: <SHIPPED | STOPPED-AT-<phase> — <reason>>
Branch: <branch>
Spec: specs/<file>.md
Plan: tasks/todo.md
Commits: <short-sha-range>
Tests: <PASS | FAIL — details>
Pushed: <yes | no — reason>
Deployment: <result | SKIPPED | NONE>

Acceptance Criteria:
  ✅✅ <user-facing AC — e2e log entry @ <short-sha>>
  ✅   <logic/integration AC — test: <name>>
  ❌   <unmet AC, if any — reason>

Follow-ups (not in plan, surfaced for user):
  - <one-line item>

Next: <PR review | re-run /auto-push for next feature | manual fix for <stopped phase>>
══════════════════════════════════════
```

---

## Integration

- **Called by**: User directly. Not invoked by other skills.
- **Calls**: `/plan` (unmodified), `/build` (unmodified), `/wrap-up-session` (with Phase C overrides), `/verify --scope e2e`.
- **Pairs with**: `/yolo` — the unsupervised cousin. Auto-push keeps the plan-approval gate; yolo skips it.
- **Differs from default workflow**: same `plan → build → wrap-up` sequence, but chained behind one command and one approval. No prompt between build and wrap-up.

---

## Key Principles

- **One gate, honored** — the plan approval is the only decision the user makes; respect it by not asking again.
- **Approval ≠ override** — saying "ship it" means run the safety gates and push the result, not skip the gates.
- **Stop loudly on real problems** — MUST-FIX, spec HALT, push rejection are stop-and-report events, not silent failures.
- **No loop** — auto-push is single-shot. Multi-feature work belongs in `/yolo` (with a backlog) or repeated `/auto-push` invocations.
- **Preserve state on stop** — every halt leaves spec, plan, and tree in a state the user can resume from.
