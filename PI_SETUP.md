# Pi Setup Guide — Global Model Routing Configuration

This guide helps Pi users configure a multi-tier model routing strategy for cost-efficient code generation. Once set up, the routing applies **globally to all Pi projects**.

## Recommended Global Config

### 1. Default Orchestrator Model

**`~/.pi/agent/settings.json`**

Set the default session model to a capable reasoning model that can orchestrate sub-agents:

```json
{
  "defaultProvider": "openrouter",
  "defaultModel": "deepseek/deepseek-v4.1-flash",
  "defaultThinkingLevel": "high",
  "skills": ["~/.agents/skills"]
}
```

**Cost rationale:** The orchestrator handles low-volume, high-value work (planning, architecture, dispatch). An orchestrator session is overwhelmingly *input* — reading files, tool results and context — and barely writes, so it is the one seat where the input rate dominates. `deepseek-v4.1-flash` has the lowest input price on the board ($0.02/M), so it is both the newest DeepSeek and the cheapest one to sit on.

**Alternatives:**
| Model | $/M in → out | Trade-off |
|-------|--------------|-----------|
| `deepseek/deepseek-v4.1-flash` | $0.02 → $1.00 | **Default.** Cheapest input; sparse thinking map (`off`/`low`/`high`/`max`) |
| `deepseek/deepseek-v4-pro` | $0.21 → $0.42 | 10× the input price, half the output price — better once a session writes a lot |
| `~anthropic/claude-sonnet-latest` | $2.00 → $? | Better reasoning, far more expensive; breaks single-provider routing |
| `~anthropic/claude-opus-latest` | $5.00 → $? | Best reasoning, expensive — use as `deep-think` only |

### 2. Model Overrides (Optional)

**`~/.pi/agent/models.json`**

Only needed if you want entries for models not auto-discovered by Pi:

```json
{
  "providers": {
    "openrouter": {
      "modelOverrides": {
        "openrouter/free": {
          "name": "OpenRouter: Free Model Router",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": 128000,
          "maxTokens": 8192,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      }
    }
  }
}
```

### 3. Presets — Model Routing Tiers

**`~/.pi/agent/presets.json`**

Define presets for each role in the routing hierarchy. Switch with `/preset <name>` or `Ctrl+Shift+U` to cycle.

```json
{
  "$schema": "./presets.schema.json",
  "_note": "Multi-tier model routing via OpenRouter, DeepSeek-only.",

  "plan": {
    "provider": "openrouter",
    "model": "deepseek/deepseek-v4-pro",
    "thinkingLevel": "high",
    "tools": ["read", "grep", "find", "ls"],
    "instructions": "You are in PLANNING / ARCHITECTURE mode... [read-only]"
  },

  "code": {
    "provider": "openrouter",
    "model": "deepseek/deepseek-v4-flash",
    "thinkingLevel": "high",
    "tools": ["read", "bash", "edit", "write", "grep", "find", "ls"],
    "instructions": "You are in CODING / IMPLEMENTATION mode..."
  },

  "search": {
    "provider": "openrouter",
    "model": "deepseek/deepseek-v4.1-flash",
    "thinkingLevel": "off",
    "tools": ["read", "grep", "find", "ls"],
    "instructions": "You are in SEARCH / EXPLORATION mode... [read-only]"
  },

  "worker": {
    "provider": "openrouter",
    "model": "deepseek/deepseek-v4-flash",
    "thinkingLevel": "off",
    "tools": ["read", "bash", "edit", "write", "grep", "find", "ls"],
    "instructions": "You are a WORKER agent. Complete focused sub-tasks precisely."
  },

  "deep-think": {
    "provider": "openrouter",
    "model": "deepseek/deepseek-v4-pro",
    "thinkingLevel": "xhigh",
    "tools": ["read", "grep", "find", "ls"],
    "instructions": "Reserved for the hardest problems. Do NOT edit files."
  }
}
```

#### Model Options by Tier

| Tier | Role | Recommended | Cost/M in | Alternative |
|------|------|-------------|-----------|-------------|
| Orchestrator | Planning, dispatch | `deepseek/deepseek-v4.1-flash` | $0.02 | `deepseek/deepseek-v4-pro` ($0.21) |
| Worker | Implementation | `deepseek/deepseek-v4-flash` | $0.0211 | `deepseek/deepseek-v4-pro` ($0.21) |
| Explorer | Search, file reads | `deepseek/deepseek-v4.1-flash` | $0.02 | `deepseek/deepseek-v4-flash` ($0.0211) |
| Deep-think | Circuit breaker | `deepseek/deepseek-v4-pro` | $0.21 | `~anthropic/claude-opus-latest` ($5) |

### 4. Global Agent Rules

**`~/.pi/agent/AGENTS.md`**

Document the delegation strategy so Pi applies it consistently:

```markdown
# Pi Global Agent Configuration

Multi-tier model routing strategy for cost-efficient code generation.

Orchestrator (default): deepseek/deepseek-v4.1-flash — planning, architecture, dispatch
Worker (sub-agents):    deepseek/deepseek-v4-flash   — implementation, test writing
Explorer (search):      deepseek/deepseek-v4.1-flash — grep/read/lint
Deep-think (rare):      deepseek/deepseek-v4-pro     — hardest problems only

Presets: /plan, /code, /search, /worker, /deep-think

The build skill (`/build`) follows the escalation ladder:
1. 2 attempts with worker model
2. 2 attempts with escalated model
3. Circuit breaker → V4 Pro analysis, then halt

skills: ["~/.agents/skills"]
```

### 5. Verify Installation

After configuring, verify Pi loads your settings:

```bash
# Check default model
pi -e "print default model"  # Should show your orchestrator model

# Test preset switching
pi --preset search -e "grep -r 'class.*Handler' src/ | head -3"

# Check presets are recognized
pi --preset plan -e "read specs/*.md"
```

## Sub-Agent Routing in Pi — pi-subagents Extension

Presets route the *parent session*. Routing *sub-agents* requires the [`pi-subagents`](https://github.com/nicobailon/pi-subagents) extension:

```bash
pi install npm:pi-subagents
```

### Agents: workflow personas + builtin gap-fillers

The workflow's own agents live in `.agents/agents/` (canonical, model-agnostic) and are auto-discovered per project: `planner`, `backend-developer`, `frontend-developer`, `code-reviewer`, `code-debugger`, `security-reviewer`, `critic`, `frontend-design-validator`, `context-document-optimizer`, `software-design-expert-review`, `test-engineer`.

The extension's builtins fill roles the workflow does not define — keep these enabled:

| Builtin | Role it fills |
|---------|---------------|
| `scout` | Fast codebase recon (Claude Code's built-in Explore equivalent) |
| `oracle` | Advisory second opinion before risky decisions |
| `researcher` | Web/docs research (needs `pi install npm:pi-web-access`) |
| `context-builder` | Heavy context-gathering pass before planning |

Disable the overlapping builtins so the fleet stays unambiguous: `worker` (≈ backend/frontend-developer), `reviewer` (≈ code-reviewer), `delegate`, `advisor`.

### Settings

Add a `subagents` block to `~/.pi/agent/settings.json` (agent name → model, plus hard caps against runaway fan-out):

> **`defaultModel` is an enforcement surface, not a convenience.** It applies to *every*
> agent without a model in frontmatter or an override. Point it at the cheapest routed
> tier (`deepseek-v4-flash`), never the builder model: a 2026-09-02 incident saw an
> autonomous `/build` spawn 22 backend-developer agents whose long turns re-read ~132k
> context each time — 95% of a $25.45 burn was qwen cache-read tokens ($0.07/M) because
> the blanket default silently made qwen the fallback for unscoped agents.
>
> **Turn caps go in agent `.md` frontmatter, NOT in `agentOverrides`.** The pi-subagents
> override parser (`parseBuiltinOverrideEntry`) silently ignores a `turnBudget` key in
> `agentOverrides` — the config parses clean and the cap never fires. Add it to each
> builder agent file instead (e.g. `.agents/agents/backend-developer.md`):
> `turnBudget: '{"maxTurns": 80, "graceTurns": 5}'` (balanced quotes; the parser strips
> them before `JSON.parse`). Enforcement verified live: a `maxTurns: 2` test run fired
> the budget wrap-up after 2 assistant turns.

```json
"subagents": {
  "defaultModel": "openrouter/deepseek/deepseek-v4.1-flash",
  "globalConcurrencyLimit": 6,
  "maxSubagentDepth": 2,
  "maxSubagentSpawnsPerSession": 30,
  "agentOverrides": {
    "planner":            { "model": "openrouter/deepseek/deepseek-v4-pro", "thinking": "high" },
    "oracle":             { "model": "openrouter/deepseek/deepseek-v4-pro", "thinking": "high" },
    "backend-developer":  { "model": "openrouter/deepseek/deepseek-v4-flash" },
    "frontend-developer": { "model": "openrouter/deepseek/deepseek-v4-flash" },
    "code-debugger":      { "model": "openrouter/deepseek/deepseek-v4-flash" },
    "code-reviewer":      { "model": "inherit", "thinking": "high" },
    "security-reviewer":  { "model": "inherit", "thinking": "high" },
    "software-design-expert-review": { "model": "inherit", "thinking": "high" },
    "critic":             { "model": "openrouter/deepseek/deepseek-v4-pro", "thinking": "high" },
    "test-engineer":      { "model": "openrouter/deepseek/deepseek-v4-flash" },
    "scout":              { "model": "openrouter/deepseek/deepseek-v4.1-flash", "thinking": "off" },
    "context-builder":    { "model": "openrouter/deepseek/deepseek-v4.1-flash" },
    "context-document-optimizer": { "model": "openrouter/deepseek/deepseek-v4.1-flash" },
    "researcher":         { "model": "openrouter/deepseek/deepseek-v4.1-flash" },
    "worker":   { "disabled": true },
    "reviewer": { "disabled": true },
    "delegate": { "disabled": true },
    "advisor":  { "disabled": true }
  }
}
```

**Ceiling cannot be expressed by omission on Pi — every review role keeps an explicit entry.** On
Claude Code, omitting `model` means the sub-agent inherits the session model; that is the whole
mechanism. On Pi, omitting an agent from `agentOverrides` falls through to `subagents.defaultModel`
above — a *fixed* model (`deepseek/deepseek-v4.1-flash`), not the session model — so omission on Pi
*downgrades* rather than inherits. This is the one asymmetry between the two harnesses, and it is why
§ 11 of `tests/test-model-tiers.sh` fails on a deleted entry rather than on a pinned one.

**`"model": "inherit"` is how Pi says Ceiling.** `pi-subagents` 0.82.1 resolves that literal to the
parent session model, which is exactly what Claude Code gets by passing nothing. The three
plain-Ceiling roles use it, so they run at whatever capability the session is paying for: start the
session on the `plan` preset and the design review runs on `deepseek-v4-pro`; leave it on the cheap
default and the review runs there. **That is the point of the tier, not a defect** — but it does mean
their cost and strength are the session's, not a number this table can state.

`critic` is the exception and stays **pinned to a concrete model**, because it carries a planner
*floor* and `inherit` cannot express a conditional. Inheriting would let critic resolve below planner
tier whenever the session is cheaper than `deepseek-v4-pro` — the precise downgrade the floor exists to
block. A floor is a dispatch rule, not a directive, so the pin is satisfied unconditionally; see
`.agents/references/model-routing.md` § *Floors*.

> **The fleet is single-family as of this revision.** Every role resolves to a DeepSeek model, so the
> cross-family property that used to make a reviewer catch a builder's blind spots is **gone**. The
> gate's remaining independence comes only from role separation — a different skill, checklist and
> prompt — not from different model priors. See § *Tier rationale* for what was traded and how to
> restore it.

Dispatch is natural language ("Have backend-developer implement this task") or the `subagent` tool. Do NOT pass per-call model params for routine routing — `agentOverrides` resolves each agent's model automatically.

**There is no fallback model, and the field that used to hold one is now a hard error.**
`fallbackModels` was removed from `pi-subagents`: `parseBuiltinOverrideEntry` throws on it, and because that
runs inside `discoverAgents` the throw takes the whole agent list down — every dispatch in the session
fails, not just the one override. A provider error (HTTP 429 included) is returned from the model that
resolved, and `pi-subagents` does not select another. Escalation is therefore always a *dispatch* decision;
see `.agents/skills/build/references/harness-dispatch.md` § *Pi + OpenRouter routing (Model Routing)* for the per-run override that raises the debugger's
second rung.

Valid override keys are `description`, `advertise`, `output`, `outputMode`, `model`, `fast`, `thinking`,
`systemPromptMode`, `inheritProjectContext`, `tools`, `defaultProvider`, `disabled` and `machine`.
`launcher` is rejected here too — it belongs in a user agent file.

### Tier rationale

| Tier | Model | $/M in → out | Why |
|------|-------|--------------|-----|
| Plan / oracle / circuit breaker | `deepseek/deepseek-v4-pro` | $0.21 → $0.42 | 1M context, thinking off/high/xhigh, `xhigh` available — and 48× cheaper on input than the `openai/gpt-6-astra` it replaced |
| Build / debug | `deepseek/deepseek-v4-flash` | $0.0211 → $0.45 | Cheapest DeepSeek on **output**, which is the dimension a builder actually spends — see the split note below |
| Review / escalation | *inherits the session model* | session | True Ceiling: runs at whatever the session pays for, exactly as on Claude Code |
| Adversarial gate (Ceiling, planner floor) | `deepseek/deepseek-v4-pro` | $0.21 → $0.42 | Same model as the planner, so the floor holds unconditionally — `inherit` cannot express a floor |
| Scout / context / docs | `deepseek/deepseek-v4.1-flash` | $0.02 → $1.00 | Cheapest input on the board; these roles read heavily and write little |

**No cross-family check remains.** The three Ceiling roles were on `openai/gpt-5.6-sol` precisely because
it was a different family from the builder, so a reviewer could not inherit the builder's priors. That
is traded away here — 200× on input and 48× on output — leaving the review gate independent by *role*
only. Restoring it costs one entry: pointing `code-reviewer` alone back at `openai/gpt-5.6-sol` (or at
`moonshotai/kimi-k3`, $0.20 → $10.56) keeps the highest-volume reviewer cross-family without paying it
for all three.

**Cheapest DeepSeek depends on direction, which is why three DeepSeek models are in play.**
`deepseek-v4.1-flash` has the lowest input price ($0.02) but a 2.2× higher output price than
`deepseek-v4-flash` ($1.00 vs $0.45). Read-heavy roles (scout, context-builder, researcher,
context-document-optimizer) take `v4.1-flash`; write-heavy roles (builders, debugger) take `v4-flash`.
Picking one for both silently overpays on whichever dimension dominates.

Thinking levels are **not uniform across the DeepSeek family** and the maps are sparse:
`v4-pro` and `v4-flash` accept `off`/`high`/`xhigh` only; `v4.1-flash` accepts `off`/`low`/`high`/`max`.
Neither accepts `medium`. A preset or override asking for an unmapped level has no defined behaviour.

## How Build Skill Sub-Agent Routing Works

**This file is the single source of concrete model IDs.** `.agents/references/model-routing.md` and `/build` name tiers
only and point here, so a model release touches one file instead of three. If you find an
OpenRouter ID in either of those, delete it rather than updating it.

Model ID per sub-agent role:

| Role | Agent | OpenRouter Model ID | $/M in → out |
|------|-------|--------------------|--------------|
| Planning / circuit breaker | `planner` | `deepseek/deepseek-v4-pro` | $0.21 → $0.42 |
| Second opinion | `oracle` | `deepseek/deepseek-v4-pro` | $0.21 → $0.42 |
| Coding agents | `backend-developer`, `frontend-developer` | `deepseek/deepseek-v4-flash` | $0.0211 → $0.45 |
| Debugger (1-2) | `code-debugger` | `deepseek/deepseek-v4-flash` | $0.0211 → $0.45 |
| Debugger (3-4) | `code-debugger` | `deepseek/deepseek-v4-pro` | $0.21 → $0.42 |
| Highest-stakes review (Ceiling) | `code-reviewer`, `security-reviewer`, `software-design-expert-review` | `"model": "inherit"` on Pi; *omit* on Claude Code; `inherit_model = true` on Codex | session |
| Adversarial gate (Ceiling, planner floor) | `critic` | `deepseek/deepseek-v4-pro` on Pi; *inherit* on Claude Code | $0.21 → $0.42 |
| Search / recon | `scout` | `deepseek/deepseek-v4.1-flash` | $0.02 → $1.00 |

On Claude Code these are passed to the Agent tool when dispatching sub-agents — **except Ceiling-tier
roles, which take no `model` at all** so they inherit the session model (see `.agents/references/model-routing.md`). On Pi they resolve from `subagents.agentOverrides` (see previous section), where Ceiling roles
stay explicitly pinned, because omission there falls through to `defaultModel` rather than to the
session model. Each sub-agent runs
independently with its own model and context.

Ceiling exists because pinning the highest-stakes reviewers *caps* them: an Opus session reviewed by a
cheaper model is a worse review than the session already paid for. `critic` is the one role with a
**floor** as well — never below planner tier, since it is the adversarial gate of last resort.

**Escalation:** If a debugger fails 2 times with the build-tier model (`deepseek-v4-flash`), it escalates to the review-tier model (`deepseek-v4-pro`) for 2 more attempts — a genuine rank increase, satisfying the "must never resolve to the same model" rung rule. If all 4 fail, the circuit breaker trips: `planner` on `deepseek-v4-pro` analyzes every attempt before the user is asked to intervene.

## Cost Estimate

Tokens are per agent, in → out. Prices are the `$/M in → out` column of the table above.

| Build phase | Model | Tokens | Cost |
|------------|-------|--------|------|
| 4 coding agents | `deepseek-v4-flash` | 100K → 20K each | ~$0.045 |
| 1 planner + 1 oracle | `deepseek-v4-pro` | 150K → 20K each | ~$0.08 |
| 5 search calls | `deepseek-v4.1-flash` | 25K → 3K each | ~$0.018 |
| 2 code reviews | *session model* | 50K → 5K each | ~$0.012 |
| **Build total** | | | **~$0.16** |

The review line is now the only one that moves with the session: ~$0.012 on the cheap default
(`deepseek-v4.1-flash`), ~$0.025 on the `plan` preset (`deepseek-v4-pro`), ~$1.20 if you deliberately
run the session on `openai/gpt-5.6-sol`. That variability is Ceiling working as intended — the
reviewer costs what the session costs.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Preset not found | Model ID doesn't exist on OpenRouter | Check `curl -s https://openrouter.ai/api/v1/models \| jq '.data[].id' \| grep <model-id>` |
| Sub-agent fails with "model not found" | Build skill references a model not in Pi's registry | Set the model in `models.json` as an override |
| High costs | Using Opus for everything | Switch default model to V4 Pro, only use deep-think preset for hard problems |
| Slow responses | Thinking level too high on cheap models | Lower thinkingLevel to "low" or "off" for worker/search presets |
