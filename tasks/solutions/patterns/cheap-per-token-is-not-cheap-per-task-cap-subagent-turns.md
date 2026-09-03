---
title: Cheap per-token is not cheap per-task — cap subagent turns and scope defaultModel
date: 2026-09-02
problem_type: pattern
module: pi-subagents / openrouter spend
tags: [cost, subagents, cache-read, model-routing, openrouter]
applies_when: Sizing LLM routing for subagent fleets or investigating a surprise provider bill.
---

## Cheap per-token is not cheap per-task

**Pattern**: A model priced at $0.11–0.14/M looks like the cheap tier, but a
subagent that accumulates ~132k context and runs 350–550 sequential turns
re-reads that context every turn. At qwen3-coder-next's $0.07/M cache-read
rate that is ~$0.0093 per turn *even when the turn does almost nothing* —
~$3–6 per long run, and $25.45 over one autonomous `/build` (22
backend-developer spawns). 95% of the cost was cache-read tokens, not
generation.

**Mechanics observed this session** (pi session logs + OpenRouter key API):
- `subagents.defaultModel` in `~/.pi/agent/settings.json` silently applies to
  *every* agent without a model in frontmatter or an override — one blanket
  line turned all unscoped agents into the builder model.
- Cost per request ≈ `cacheReadTokens × input_cache_read_price`. Long-turn
  runs are cache-read dominated; output was $0.37 of $25.45.
- Headroom compression could not help: it averaged 1.5% on this traffic
  (repeated cached context is already the cheap layer; compressing busts it).

**Prevention rule**:
1. Treat `subagents.defaultModel` as an enforcement surface, not a convenience
   — point it at the cheapest routed tier, and put pricier models only in
   named `agentOverrides`.
2. Give builder agents a `turnBudget` (`{maxTurns, graceTurns}`) in their
   override; a 80-turn cap bounds a worst-case run to ~$0.75 at 132k context
   vs $6.84 unbounded.
3. Set a credit limit on the provider key — an unlimited key turns any runaway
   loop into an unbudgeted bill (this key had `limit: null` while $26.53
   burned in 24h).
4. When estimating cost, multiply by turn count × context size, not by price.
