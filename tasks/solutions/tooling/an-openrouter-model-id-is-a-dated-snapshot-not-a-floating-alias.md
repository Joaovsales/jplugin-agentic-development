---
title: An OpenRouter model ID is a dated snapshot, not a floating alias
date: 2026-11-15
problem_type: tooling
module: PI_SETUP.md, ~/.pi/agent/settings.json, ~/.pi/agent/presets.json
tags: [openrouter, model-routing, pricing, pi, deepseek, cost]
applies_when: choosing or reviewing a model ID in PI_SETUP.md, a Pi preset, or subagents.agentOverrides
---

## The rule

Two things that look like one thing are separate:

1. **A bare OpenRouter model ID is a frozen snapshot.** `deepseek/deepseek-v4.1-flash` and
   `deepseek/deepseek-v4.1-flash-1017` are two distinct entries in `/api/v1/models`, created
   2026-09-10 and 2026-10-17. The bare ID does **not** follow the vendor's `deepseek-flash`
   endpoint forward. A config left on it stays a release behind indefinitely, and nothing warns.
   Pin the dated snapshot deliberately, and re-check it when a vendor ships a checkpoint.

2. **The catalog price is the cheapest endpoint, not the one your traffic lands on.** OpenRouter
   routes by its own ordering, so the `pricing` block in `/api/v1/models` can be 3–10× off what
   you are actually billed. A one-token call carrying `"usage": {"include": true}` returns the
   serving `provider` and the exact `cost`; that is the only number worth putting in a cost table.

## What happened

A 2026-11-15 review of the Pi routing config found the session default on the September
`v4.1-flash` build while the October `-1017` checkpoint had been live for a month. The catalog made
the comparison look like a wash at best: September at $0.0507 → $0.2028 with a $0.001014 cache-read,
1017 at $0.02 → $0.108 with a **$0.007** cache-read. On those numbers the newer build is cheaper on
input and output but 7× dearer on the one dimension that dominates a cached agent session — which is
how a stale pin survives a price review.

Live one-token calls told the opposite story. Both models routed to **Wafer**, so the comparison was
like-for-like for the first time:

| Model | Routed provider | $/M in | $/M cache-read | $/M out |
|-------|-----------------|--------|----------------|---------|
| `deepseek-v4.1-flash-1017` | Wafer | $0.066 | $0.0065 | $0.50 |
| `deepseek-v4.1-flash` (Sept) | Wafer | $0.19 | $0.012 | $0.65 |

The 1017 build is cheaper on **all three** dimensions — 2.9× on input, 1.8× on cache-read, 1.3×
on output — while scoring +11.1 on Terminal-Bench 4.0 (31.2 → 42.3), +8.8 on ProgramBench and +2.8
on DeepSWE v1.1. It is a Pareto improvement, not a trade. The catalog's cache-read figure was not
merely imprecise; it inverted the sign of the decision.

The catalog's $0.02 input price was Sail Research's fp4 endpoint, which the account never routed
to. Repricing the machine's own recorded traffic (2 137 turns, 22.6 M new input, 422 M cached,
2.3 M output — **94.4 % of tokens are cache-reads**) put the switch at a **50 % cost cut**, not
the ~34 % the catalog prices implied.

## Why it matters here

`PI_SETUP.md` is the single source of concrete Pi model IDs (`tests/test-model-tiers.sh` § 7
forbids them anywhere else), so a stale ID there propagates to every project that follows the
guide. The read-heavy tier is where it bites hardest: with 94.5 % of tokens arriving as cache
hits, the cache-read rate — not the headline input price, and not the thinking level — is what
decides the bill.

## The check

```bash
K=$(python3 -c "import json;print(json.load(open('$HOME/.pi/agent/auth.json'))['openrouter']['key'])")
curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $K" -H 'Content-Type: application/json' \
  -d '{"model":"deepseek/deepseek-v4.1-flash-1017","messages":[{"role":"user","content":"hi"}],
       "max_tokens":1,"usage":{"include":true}}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["provider"], d["usage"]["cost"])'
```

Run it per candidate model before writing a price into a table. Costs a fraction of a cent.

## Related

- `tasks/solutions/tooling/cached-suite-keys-on-the-verbatim-command-so-parallelism-comes-from-the-environment.md`
