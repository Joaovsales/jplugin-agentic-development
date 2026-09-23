# Model Routing

Which tier every sub-agent runs on, what Ceiling and a floor mean, the persona table
with its Model column, and the dispatch rules per harness. Concrete provider model IDs
live in `PI_SETUP.md` § Sub-Agent Routing, never here.

## Tiers

Canonical tiers. Concrete provider model IDs are deliberately **not** repeated here — `PI_SETUP.md` § Sub-Agent Routing is their single source, so a model release updates one file instead of three:

| Tier | Used for | Claude Code |
|------|----------|-------------|
| Ceiling | correctness, security, design, and adversarial review — the highest-stakes judgment | *inherit* |
| Planner | `/plan`, architecture, oracle, circuit breaker | `opus` |
| Builder | `/build` coding, debugging (attempts 1–2) | `sonnet` |
| Reviewer | doc compression, debugging (attempts 3–4 — see the floor below) | `sonnet` |
| Scout | search, recon, context building | `haiku` |

## Ceiling

**`Ceiling` means: omit the model override entirely so the sub-agent inherits the
session model.** It is not a model name and must never be written as one. If the
user is running Opus, a ceiling-tier reviewer runs on Opus.

Ceiling exists because pinning a tier to a concrete model *caps* it. A rule that
says "always pass `model` explicitly" silently downgrades the highest-stakes
review to the pinned tier for exactly the users who chose a stronger session
model — the reviewers most worth running at full capability. Inheriting is also
the correct cross-harness fallback: where a harness cannot select a model per
agent, omit the override rather than guessing a name, because a working review on
the parent model beats a failed dispatch on an unrecognized one.

## Floors

### Floors

`ceiling (<tier> floor)` means: inherit the session model, but never resolve
*below* `<tier>`. Omit the override when the session model is at `<tier>` or
above; pass `<tier>`'s alias when it is lower. A floor is always a **dispatch
rule, not frontmatter** — a `model:` pin would satisfy the floor on a weaker
session but *cap* the agent on a stronger one, the same defect Ceiling exists to
remove. Nothing mechanically enforces a floor; `tests/test-model-tiers.sh` pins
the rule's presence and the absence of a pin, which is as far as a static guard
reaches. Two roles carry one:

**`critic` — `*ceiling (planner floor)*`, so it never resolves below planner
tier.** It is the adversarial gate of last resort, and a plain ceiling would
silently drop it beneath planner tier on a Builder- or Scout-tier session — downgrading the one reviewer whose job is
catching what the others missed.

**Debugger attempts 3–4 — `ceiling (builder floor)`.** This is the escalation
rung of the regression ladder, and on Claude Code it had nothing to escalate *to*:
**Reviewer and Builder both resolve to `sonnet`**, because Claude Code offers no
alias between them. So attempts 3–4 re-ran the exact model that had just failed
twice, and "graduated escalation" was a no-op until the circuit breaker. The floor
makes the rung strictly stronger than attempts 1–2 on every session — planner
alias on a Builder-or-weaker session, inherited model above that — without
capping an Opus-or-stronger session at a fixed alias. Pi is unaffected: it has a
genuine three-model ladder already (see `PI_SETUP.md`).

## Agents

Canonical persona definitions live in `.agents/agents/` (model-agnostic — never pin `model:` there).
- **Claude Code** reads `.claude/agents/` (may pin built-in aliases like `sonnet`).
- **Pi** discovers `.agents/agents/` automatically via the `pi-subagents` extension; routing comes from `subagents.agentOverrides` in `~/.pi/agent/settings.json`. Extension builtins `scout`, `oracle`, `researcher`, `context-builder` fill roles the workflow does not define; overlapping builtins are disabled in settings.

| Agent | Model | Best For |
|-------|-------|---------|
| `planner` | `opus` | Spec writing, task breakdown, architecture decisions |
| `backend-developer` | `sonnet` | APIs, databases, auth, performance, security |
| `frontend-developer` | `sonnet` | React/Vue/Angular components, responsive UI |
| `frontend-design-validator` | `sonnet` | Validate UI against design specs |
| `code-reviewer` | *ceiling* | Post-implementation quality review |
| `code-debugger` | `sonnet` | Debugging failing tests and runtime errors |
| `security-reviewer` | *ceiling* | OWASP checks, auth flows, injection vectors |
| `critic` | *ceiling (planner floor)* | Adversarial quality gate for plans, code, specs |
| `context-document-optimizer` | `sonnet` | Compress large docs for token efficiency |
| `software-design-expert-review` | *ceiling* | Read-only APOSD design audit — depth, leakage, error design (dispatched by `/quality-gate`) |

**Rule**: One focused task per subagent. Resolve each agent's model through the
tier in *Tiers* above — on Claude Code pass `model` explicitly for the
Planner, Builder, Reviewer, and Scout tiers, and pass **nothing** for *ceiling*
agents so they inherit the session model; on Pi, never pass per-call model params
(agentOverrides resolves them).

## Rules

- Never use the planner tier for code writing; never use the scout tier for coding
  or planning.
- **Claude Code**: pass `model` explicitly for the Planner, Builder, Reviewer, and
  Scout tiers. Pass **nothing** for Ceiling — an override there is the regression
  this tier exists to prevent. `critic` is the one exception, and only downward,
  per its floor above.
- **Pi**: never pass per-call model params; `subagents.agentOverrides` resolves
  them. Ceiling-tier agents stay **explicitly pinned** there. Omitting an agent
  from `agentOverrides` falls through to `subagents.defaultModel` — a fixed
  builder-tier model, not the session model — so omission on Pi *downgrades*
  rather than inherits. Ceiling-by-omission is a Claude Code property; see
  `PI_SETUP.md` § Sub-Agent Routing for the Pi equivalent.
