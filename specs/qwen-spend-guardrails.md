# Spec: Qwen Spend Guardrails

**Date**: 2026-09-02 · **Mode**: /yolo (auto-confirmed) · **Origin**: usage investigation (see tasks/yolo-idea.md)

## Problem
`subagents.defaultModel: openrouter/qwen/qwen3-coder-next` in `~/.pi/agent/settings.json`
silently enforces qwen on every subagent without an explicit override. An autonomous
`/build` run spawned 22 backend-developer agents; seven runs made 350–550 turns each at
~132k context. 95% of the $25.45 burn was cache-read tokens ($0.07/M × ~350M tokens).
The OpenRouter key has no credit limit (`limit: null`), so there was no tripwire.

## Assumptions (conservative, no user interview per yolo override)
1. Named builder overrides (backend-developer, frontend-developer, code-debugger) keep
   qwen — the AGENTS.md routing table intends qwen as builder tier. Only the *blanket*
   default changes.
2. Turn caps on builders are acceptable despite pi-subagents docs advising against hard
   caps on mutation-capable workers: `maxTurns` warns-then-graces (not instant kill),
   partial output is returned, and the observed failure mode (500+ turn runs) is exactly
   the unbounded case. Cap is set generously (80) to avoid truncating real slices.
3. OpenRouter limit: monthly-resetting, $50 — current monthly usage is $33.48, so this
   gives ~$16.5 headroom this month and caps future months. User can raise/lower at
   openrouter.ai/keys.

## Changes
### C1 — `~/.pi/agent/settings.json` (subagents block)
- `defaultModel`: `openrouter/qwen/qwen3-coder-next` → `openrouter/deepseek/deepseek-v4-flash`
  (Scout tier, $0.14/M — cheapest routed model; unknown/unlisted agents now land cheap).
- `agentOverrides.backend-developer.turnBudget`: `{"maxTurns": 80, "graceTurns": 5}`
- `agentOverrides.frontend-developer.turnBudget`: `{"maxTurns": 80, "graceTurns": 5}`
- `agentOverrides.code-debugger.turnBudget`: `{"maxTurns": 80, "graceTurns": 5}`

### C2 — OpenRouter key credit limit
- `PATCH /api/v1/key` with `{"limit": 50, "limit_reset": "monthly"}`; verify via `GET /api/v1/key`.

## Acceptance criteria
- AC1: settings.json parses as valid JSON and pi-subagents strict parser accepts it
  (verified via `subagent({action:"doctor"})`).
- AC2: a new subagent launch resolves the new defaultModel (doctor/config report or
  spawn smoke test).
- AC3: OpenRouter GET /api/v1/key shows `limit: 50`, `limit_reset: monthly`.
- AC4: no other subagents.* keys changed; builder overrides otherwise untouched.
