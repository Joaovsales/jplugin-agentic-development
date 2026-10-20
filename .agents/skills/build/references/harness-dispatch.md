# Harness dispatch notes for /build

Per-harness dispatch rules (Codex, Pi, Pi + OpenRouter) moved verbatim from `SKILL.md`.
Claude Code dispatch and the Ceiling-tier rule stay in `SKILL.md`.

## Codex: debugger escalation (Model Routing)

On Codex, dispatch the managed `debug-escalation` role for attempts 3–4: the
`code-debugger` agent file pins Builder and would win over a spawn override.
Resolve the parent tier before dispatch. For a Builder-or-weaker parent, request
the policy's Planner model and effort so Tier 2 is stronger than Tier 1.
Inherit only when the parent is above Builder. Confirm the effective route is
stronger than Tier 1 before retrying.

## Pi + OpenRouter routing (Model Routing)

> **For Pi + OpenRouter users:** Session-level routing goes in `~/.pi/agent/presets.json` (see `PI_SETUP.md`). **Sub-agent** routing requires the `pi-subagents` extension (`pi install npm:pi-subagents`) — set `subagents.agentOverrides` in `~/.pi/agent/settings.json` (agent name → model, plus `fallbackModels` for provider failures). Workflow agents live in `.agents/agents/` and are auto-discovered per project. See `PI_SETUP.md` § Sub-Agent Routing.

### Pi Dispatch

- Requires the `pi-subagents` extension (`pi install npm:pi-subagents`). Workflow agents come from `.agents/agents/` (auto-discovered per project); the extension adds `scout`, `oracle`, `researcher`, `context-builder` for roles the workflow does not define.
- Dispatch with natural language or the `subagent` tool — e.g. "Have backend-developer implement this task" or `subagent({ agent: "backend-developer", task: "..." })`. Use `scout` for recon before planning, `oracle` for a second opinion on risky decisions.
- Do NOT pass per-call model params on Pi — routing comes from `subagents.agentOverrides` in `~/.pi/agent/settings.json`; `fallbackModels` absorbs provider failures.
- For 2+ independent tasks: ask for a parallel run ("run backend-developer and frontend-developer in parallel for tasks A and B") and respect `globalConcurrencyLimit`.
- If the extension is not installed, run Phase 1 inline in the main context (single-agent).

### Codex Dispatch

Use the managed `explorer` role for read-only code reconnaissance. Use the
managed `scout` role when an investigation needs MCP access, and instruct it
to read without editing. Named roles obtain their model, effort, and permissions
from `config/agent-policy.toml`; do not set a global Scout model default because
it can cap Ceiling roles. For `critic`, resolve the parent tier against its
planner floor and request the policy's planner model and effort only when
the parent falls below that floor.

## Design-mode Write dispatch: the writer's `context:`

The `test-engineer` Write job records how it was dispatched on the `> Frozen:` line
(`.agents/skills/build/references/design-mode.md` step 4).

- Claude Code: `Agent` starts a fresh context; write `context: fresh`.
- Pi: `pi-subagents` defaults to `context: "fresh"`; write `context: fresh`.
- Codex: Codex records `forked` until Q1 of `specs/aposd-first-build.md` shows a
  `spawn_agent` child starts with only its message (probe: the parent states a
  marker phrase, spawns the `test-engineer` role and asks it to repeat the phrase;
  a repeat means forked). When Q1 is answered fresh, record that here and write
  `context: fresh`.
- No sub-agents (inline run): write `context: inline`.
