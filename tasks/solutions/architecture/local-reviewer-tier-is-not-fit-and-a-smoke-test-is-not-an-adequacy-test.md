---
title: The local reviewer tier is not fit, and a smoke test is not an adequacy test
date: 2026-11-16
problem_type: architecture-decision
module: docs/bonsai-2-27b/ (runbook, container, eval) and the local provider tier
tags: [local-model, bonsai, eval, reviewer, no-go]
applies_when: proposing a local or small model for any agent role, or treating a successful smoke test or a high tok/s figure as evidence that a model can do the role
---

**Verdict (#432, `docs/bonsai-2-27b/eval/README.md`): Bonsai 27B v1 `Q1_0` on
this hardware is NOT fit to be a read-only reviewer.** In a blind test
against the 26 findings the Layer-2 gates labelled on #409, #410, #411 and
#419:

- **Recall:** 0/26 strict, 1/26 lenient. It caught 0 of the 9 APPLIED
  SHOULD-FIX findings.
- **Precision:** 0–4 %. 26–27 of its 27 findings were noise, and each one
  was checked against the code.
- One false positive was refuted. With reasoning enabled it produced no
  output at all.
- Issue #405 (local personas) was closed on this evidence.

**What is proven is the plumbing, not the capability.** Stock llama.cpp
serves Bonsai 2 `Q2_0` and 27B v1 `Q1_0` correctly at about 20 tok/s on a
6 GB laptop GPU (#411). The provider resolves (#425). The container is
hardened and its egress sealed (#411, #426).

**Why a smoke test does not settle the role.** A smoke test checks that the
server answers, the output parses and tool calls round-trip. Being an
adequate reviewer means finding the defects a reference reviewer finds
without inventing others. Only an eval scored against a labelled set can
show that. Here every smoke test passed and recall was zero.

**Rule.** Adopting any model for a role requires recall and precision
measured against a labelled set for that role. Throughput and a passing
smoke test only show the model can be served.

The label set comes from gates that ran Phase 4 inline, so it reflects one
reviewer's judgement, not ground truth (eval README caveat). That caveat
does not rescue a 0/26 result.
