---
title: Code graph routing remains optional after the measured no-go
date: 2026-11-16
problem_type: architecture-decision
module: code-graph routing treatment and .agents/skills/eval/scripts/grade-code-graph.py
tags: [code-graph, eval, adoption, claude-code, no-go]
applies_when: considering automatic graph routing or interpreting an evaluation in which graph tools were not adopted
---

The 2026-11-16 registered evaluation returned **Verdict: no-go — rule 2
(cost); rule 4 (adoption); rule 6 (graceful degradation)**. Keep code graphs
optional; do not promote this routing/hint treatment. Phase A's independent
installer and reporting corrections remain merged through PR #416.

The [results](../../eval-results/code-graph/2026-11-16/results.md) cover Claude
Code 2.1.325 only, requested model `claude-opus-5-5`, synthetic seeded fixtures,
and N=3: 90 selected completed runs across A/B/D, with zero selected errors.
Codex, Pi, Cursor and LSP lift were not measured.

| Measure | Observed result |
|---|---|
| Localization correctness | A/B/D all 100%; no case drop |
| Localization median tokens | A 79,198; B 97,425 (1.230145× A); D 100,621 (1.270499× A) |
| B graph/LSP adoption | 0/21 localization runs, below the 60% rule |
| Control overhead | A/B correctness 100%; token ratio 1.005253, within 1.15 |
| All-case median wall time | A 11.8285 s; B 11.8380 s; ratio 1.000803, within 1.30 |

These are the report's six-rule inputs
(`tasks/eval-results/code-graph/2026-11-16/results.md:13`). Rules 1, 3 and 5
passed. Rule 6 failed on token overhead; D correctness remained 100%.

Both B and D recorded zero graph/LSP calls. This measures an unadopted
treatment's overhead, not graph utility when used or an independently
demonstrated query-failure fallback. Availability probes are not adoption
([classifier learning](../bugs/code-graph-adoption-counts-executed-commands-not-probes.md)).

Selected nominal cost was $12.45952240. The program retained 91 paid attempts,
including the original errored smoke: total nominal $12.60879440 and
conservative accounted upper $20.58969660, below $320. The sole same-slot
retry preserved the failed attempt and all charges. No extra samples or
threshold changes were used; simultaneous failures 2/4/6 permit neither a
rule-4-only nor a rule-6-only retry.

Apply the preregistered rule literally, retain the negative evidence, and
separate adoption from efficacy before claiming lift. Related:
[a preregistered keep-or-revert rule](../process/a-pre-registered-keep-or-revert-rule-settles-a-costly-feature.md).
