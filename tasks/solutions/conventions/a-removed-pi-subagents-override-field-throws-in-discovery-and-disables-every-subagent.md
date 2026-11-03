---
title: A removed pi-subagents override field throws inside discovery, so one bad override disables every subagent
date: 2026-10-25
problem_type: convention
module: ~/.pi/agent/settings.json subagents.agentOverrides; pi-subagents bundle parseBuiltinOverrideEntry
tags: [pi-subagents, agent-overrides, fallback-models, config, discovery, fail-fast, removed-field]
applies_when: editing Pi sub-agent routing, reviewing a Pi settings block, or diagnosing a session where every subagent dispatch fails at once
---

**Status**: current as of `pi-subagents` 0.82.1

## Claim

`pi-subagents` 0.82.1 removed the `fallbackModels` override field, and
`parseBuiltinOverrideEntry` (`bundle/chunk-CIZQXJ5Q.js:4827`) **throws** on it:

```
Builtin override 'backend-developer' in '/…/settings.json' uses removed field
'fallbackModels'; configure one model instead.
```

That parse runs inside `discoverAgents`, so the throw does not degrade the one
override — it aborts agent discovery for the session. Every dispatch fails, including
agents whose overrides are valid. The blast radius of a single stale key is the whole
fleet, and the error names only the offending key, not the consequence.

`launcher` is rejected the same way. The accepted keys are `description`, `advertise`,
`output`, `outputMode`, `model`, `fast`, `thinking`, `systemPromptMode`,
`inheritProjectContext`, `tools`, `defaultProvider`, `disabled`, `machine`.

There is no fallback model. The extension's own `docs/models.md` says a provider error,
HTTP 429 included, "is returned from that model rather than selecting another one", and
the only same-model continuation is a lifecycle recovery after a verified compaction
abort.

## Consequence

**Escalation is always a dispatch decision, never a config one.** A ladder that raises a
rung by switching models — `/build`'s debugger attempts 3–4 — has to do it with a
per-run `model` on the launch, which is the strongest precedence level
(per-run → provider-scoped → `agentOverrides.<name>.model` → agent frontmatter → `subagents.defaultModel`
→ parent session model) and therefore beats the pin. On Pi that is the one sanctioned
exception to "no per-call model params"; without it the rung collapses back onto the
model that had just failed twice, which `tests/test-model-tiers.sh` § 12 exists to catch.

`PI_SETUP.md` § Sub-Agent Routing owns the concrete block and the accepted-key list;
`/build` § *Escalation ladder for test regressions* owns the per-run override.

Related: `pi-expresses-ceiling-as-model-inherit-not-a-pinned-model.md` is the other
routing fact this session established — `"model": "inherit"` is a valid value, and
unlike a removed key it is accepted silently, so the two failure modes are opposites:
one throws loudly and wide, the other works and changes where a role runs.
