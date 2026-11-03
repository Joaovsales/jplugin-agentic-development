---
title: Pi expresses the Ceiling tier as model inherit, not as a pinned model
date: 2026-10-25
problem_type: convention
module: .agents/references/model-routing.md § Ceiling and § Rules; PI_SETUP.md § Sub-Agent Routing; ~/.pi/agent/settings.json
tags: [model-routing, ceiling, pi, pi-subagents, agent-overrides, inherit, tiers]
applies_when: writing or reviewing Pi sub-agent routing, adding a Ceiling-tier agent, or reconciling the Ceiling definition across Pi, Claude Code and Codex
---

**Status**: current as of `pi-subagents` 0.82.1

## Claim

`pi-subagents` 0.82.1 accepts the literal `"model": "inherit"` in
`subagents.agentOverrides.<name>.model`, and resolves it to the **parent session
model** — the same thing Claude Code gets by passing no `model` at all, and Codex
by setting `inherit_model = true` on its `Ceiling` tier. Verified in the installed
bundle, not only in its documentation: `bundle/chunk-CIZQXJ5Q.js:7104` defines
`INHERIT_MODEL`, and `inheritsParentModel()` at `:7332` feeds the resolution at
`:7307`. The extension's own `docs/models.md` states it twice.

Before this, `.agents/references/model-routing.md` and `PI_SETUP.md` both said
Ceiling could not be expressed on Pi at all, because **omitting** an agent from
`agentOverrides` falls through to `subagents.defaultModel` — a fixed model, never
the session model. That claim is true of *omission* and false of `"inherit"`, and
the two were conflated. Precedence is per `docs/models.md`: per-run override →
provider-scoped override → `agentOverrides.<name>.model` → agent frontmatter
`model` → `subagents.defaultModel` → the parent session model.

## The rule

- A plain-Ceiling role on Pi carries `"model": "inherit"`, never a pinned model.
- A role with a **floor** cannot use it. `inherit` resolves the session model,
  never a minimum, so `critic` keeps a concrete planner-tier pin and satisfies its
  floor unconditionally. This is the one place the three harnesses genuinely
  differ, because Claude Code expresses a floor as a dispatch rule and Pi has no
  conditional form.
- Deleting a Ceiling entry is a **downgrade**, not an inherit. The entry has to
  exist; only its value is the directive.
- The directive is Pi-only. It must not appear in `.agents/agents/*.md` or
  `.claude/agents/*.md` — those are Claude Code's tree and express Ceiling by
  having no `model:` line at all. `tests/test-model-tiers.sh` §11 pins both the
  directive in `PI_SETUP.md` and the absence of it anywhere under `.agents/`.

## Consequence

Cost and strength of a Pi Ceiling role become the session's, not a number a table
can state: a review runs on whatever preset the session was started in. That is
the tier working as designed, but it means a Ceiling row reading "inherits the
session model" is correct and a row naming a model is the defect this convention
exists to catch.

Related: `specs/model-tier-ceiling-gaps.md` § 3 and its `critic` floor section own
the original rationale; `.agents/references/model-routing.md` § Ceiling owns the
cross-harness statement.
