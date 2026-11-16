---
title: Code graph native usage placeholders need delta normalization
date: 2026-11-16
problem_type: runtime-error
module: tasks/eval-results/code-graph/admission_gateway.py
tags: [code-graph, claude-code, usage-stream, budget, compatibility]
symptoms: Controlled native placeholder streams were rejected and the original paid smoke stopped with inconsistent_usage
root_cause: Strict cumulative-counter validation rejected source-supported null and zero placeholders in native message deltas
resolution: Normalize supported delta placeholders before monotonic validation while preserving reservations and fail-closed accounting
---

Status: fixed — 2026-11-16.

The original smoke stopped after `A/invoice-rounding/1/0/1`, retaining nominal
$0.149272 and accounted upper $1.660241. Its raw SSE event was not retained,
so its unique triggering shape is **not established**. The
[compatibility proof](../../eval-results/code-graph/usage-compatibility-proof.json)
instead demonstrates a narrower interoperability defect through controlled
offline streams and pinned Claude Code 2.1.325 source semantics.

Native `message_delta` input/cache counters can use null or integer zero to
mean no update. Null/all-zero cache breakdowns likewise retain prior values.
Treating those placeholders as cumulative replacement values can falsely
report a decrease. `delta_usage` removes only the enumerated placeholders
before merging (`tasks/eval-results/code-graph/admission_gateway.py:162`).
Booleans, floats, unknown fields/pricing, genuine positive declines and
unsupported credits still reject (`admission_gateway.py:188`). Output-token
evidence must remain cumulative and terminal stream ordering must validate
(`admission_gateway.py:254`).

Normalize at the native transport boundary without weakening the spending
contract. Request reservation still checks settled plus held amounts against
$4 under a lock (`admission_gateway.py:325`). Compatibility regressions cover
native placeholders and thinking details, plus bounded redacted diagnostics
(`tasks/eval-results/code-graph/test_admission_gateway.py:252`). The retained
offline proof reports 16 passing gateway tests; it does not assert the lost
paid trigger or authorize another payment.

Recovery used a separately reviewed operational manifest and a guarded state
migration. It pinned old/new manifest hashes, saved the exact prior state and
an append-only apply intent, and preserved attempts, retry counts and charges
(`tasks/eval-results/code-graph/prepare-usage-compatibility.py:118`). The sole
same-slot retry subsequently completed; the final
[report](../../eval-results/code-graph/2026-11-16/results.md) retains both
attempts. The frozen protocol and initial manifest were not rewritten.

When adapting native usage streams, reproduce documented delta semantics
offline before changing reconciliation. Keep unknown usage reserved and retain
failed evidence; a compatibility fix must not reset budget or retry state.
