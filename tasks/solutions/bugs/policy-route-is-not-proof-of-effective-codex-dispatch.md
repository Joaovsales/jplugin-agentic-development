---
title: A policy route is not proof of an effective Codex dispatch
date: 2026-09-30
problem_type: bug
module: scripts/agent_policy/policy.py, scripts/agent_policy/doctor.py
tags: [codex, model-routing, precedence, doctor]
symptoms: "Doctor reported a Planner floor as an effective spawn even when no spawn override was supplied; a global reasoning-effort default was not diagnosed"
root_cause: "The first implementation treated a resolved policy target as proof of the runtime spawn model and checked only agents.default_subagent_model among global child defaults"
resolution: "Effective-route inspection now reports the visible parent route and required spawn override separately; installer and doctor also detect agents.default_subagent_reasoning_effort"
---

**Status**: fixed — 2026-09-30.

The `critic` and `debug-escalation` files intentionally omit model fields so Ceiling roles can inherit. A resolver may calculate a required stronger model, but that calculation does not show that a caller supplied a spawn override. The doctor must report the model visible from the installed file and config layers, and label the required override separately (`scripts/agent_policy/doctor.py`). The pure effective-route helper does the same (`scripts/agent_policy/policy.py`).

Codex also accepts `agents.default_subagent_reasoning_effort`. Even without a global child model, it can change the effort inherited by an unpinned Ceiling role. The installer refuses this configuration, while the doctor names the winning layer (`scripts/agent_policy/install.py`, `scripts/agent_policy/doctor.py`). Regression assertions are in `tests/test-agent-policy.sh` and `tests/test-codex-install.sh`.

Prevention: keep desired policy routes separate from observed effective routes, and enumerate every provider default that can affect an inherited field.
