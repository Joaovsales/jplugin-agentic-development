---
title: OpenRouter key management needs a management key — inference keys get 404/403
date: 2026-09-02
problem_type: tooling
module: openrouter-api
tags: [openrouter, api-keys, cost-control, api-limits]
applies_when: Scripting OpenRouter key limits, daily usage, or account activity from automation.
---

## OpenRouter key management needs a management key

**Pattern**: The key stored in `~/.pi/agent/auth.json` is an *inference* key.
This session observed:
- `PATCH/PUT/POST /api/v1/key` → `404 Not Found` (the endpoint does not exist
  for inference keys).
- `GET /api/v1/activity?date=...` → `403` "Only management keys can fetch
  activity for an account".
- What inference keys CAN do: `GET /api/v1/key` (own key: usage, usage_daily,
  limit) and `GET /api/v1/credits`.

**To change a key's limit** (`PATCH /api/v1/keys/{hash}` with
`{"limit": 50, "limit_reset": "monthly"}`) or pull per-day activity, create a
**management key** first (openrouter.ai → Settings → API Keys → management
key), then authenticate with it. Per OpenRouter docs, a Connect client secret
can only reach keys the same client created.

**Workaround without a management key**: `GET /api/v1/key`'s `usage_daily` /
`usage_weekly` fields are a sufficient spend tripwire for monitoring; local
pi session logs (`~/.pi/agent/sessions/**/*.jsonl`, `usage.cost.total` per
entry) reconcile with the provider total within cents and give per-project,
per-model, per-subagent breakdowns the API does not offer.
