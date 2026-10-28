# Harness dispatch notes for /build

Per-harness dispatch rules (Codex, Pi, Pi + OpenRouter) moved from `SKILL.md`, plus the Pi debugger-escalation rule.
Claude Code dispatch and the Ceiling-tier rule stay in `SKILL.md`.

## Codex: debugger escalation (Model Routing)

On Codex, dispatch the managed `debug-escalation` role for attempts 3–4: the
`code-debugger` agent file pins Builder and would win over a spawn override.
Resolve the parent tier before dispatch. For a Builder-or-weaker parent, request
the policy's Planner model and effort so Tier 2 is stronger than Tier 1.
Inherit only when the parent is above Builder. Confirm the effective route is
stronger than Tier 1 before retrying.

## Pi + OpenRouter routing (Model Routing)

On Pi, dispatch `code-debugger` for attempts 3–4 with a **per-run `model`**, e.g.
`subagent({ agent: "code-debugger", model: "<planner-tier provider/id>", task: … })`.
The agent is pinned in `agentOverrides`, and a per-run override is the strongest
precedence level, so it wins over the pin and is the only way to raise the rung —
`pi-subagents` has no fallback field. This is the one sanctioned exception to
§ *Pi Dispatch*'s "no per-call model params", and it applies to the ladder alone.
If the per-run model does not resolve, go to Tier 3 rather than burning two
identical attempts.

> **For Pi + OpenRouter users:** Session-level routing goes in `~/.pi/agent/presets.json` (see `PI_SETUP.md`). **Sub-agent** routing requires the `pi-subagents` extension (`pi install npm:pi-subagents`) — set `subagents.agentOverrides` in `~/.pi/agent/settings.json` (agent name → model). There is no fallback field: `fallbackModels` was removed and now throws inside `discoverAgents`, which disables every subagent rather than just that override. Workflow agents live in `.agents/agents/` and are auto-discovered per project. See `PI_SETUP.md` § Sub-Agent Routing.

### Pi Dispatch

- Requires the `pi-subagents` extension (`pi install npm:pi-subagents`). Workflow agents come from `.agents/agents/` (auto-discovered per project); the extension adds `scout`, `oracle`, `researcher`, `context-builder` for roles the workflow does not define.
- Dispatch with natural language or the `subagent` tool — e.g. "Have backend-developer implement this task" or `subagent({ agent: "backend-developer", task: "..." })`. Use `scout` for recon before planning, `oracle` for a second opinion on risky decisions.
- Do NOT pass per-call model params on Pi for routine routing — it comes from `subagents.agentOverrides` in `~/.pi/agent/settings.json`. The one exception is the per-run debugger override above (§ *Pi + OpenRouter routing (Model Routing)*), used only by `/build` § *Escalation ladder for test regressions* (in `.agents/skills/build/SKILL.md`), which raises the debugger's second rung with a per-run `model`. There is no fallback field to do it for you: `fallbackModels` was removed and now throws, disabling every subagent in the session.
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

