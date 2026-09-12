# Bulk-read context: measured implementation results

2026-09-12. Exploratory workflow-variant comparison on one real cross-file correction. See [frozen protocol](protocol.md), [requests](request.txt), [requested-handoff prompt](handoff-request.txt), [machine metrics](metrics.json), and [source hashes](snapshots.json).

**All completed implementations pass the same 14 held-out behavioral checks. This does not establish a general context guarantee or consistent token savings.** The experiment extracts the handoff policy/persona/hook and disables unrelated skills equally; it does not validate the complete `/build` workflow. The underlying pre-existing parser defect is tracked separately as [#132](https://github.com/Joaovsales/jplugin-agentic-development/issues/132). Candidate fixes are isolated artifacts, not production changes.

## Per-run measurements

Accumulated tokens sum input, cache creation, cache hits, and output over all model requests. They are **not** unique context occupancy. USD is the CLI's list-price-equivalent accounting (`costBasis: list`), not an invoice. Parent/reader totals come from authoritative `modelUsage`; incomplete streamed actor counters are retained under an explicitly partial field and never used as totals.

| Run | Scenario | Policy | Scout calls | Checks | Parent tokens | Reader tokens | USD | Seconds |
|---|---|---|---:|---:|---:|---:|---:|---:|
| [R1](R1/trace-index.jsonl) | natural-routing | prior | 0 | 14/14 | 668,988 | 0 | 0.3484 | 101.5 |
| [R2](R2/trace-index.jsonl) | natural-routing | revised | 0 | 14/14 | 772,471 | 0 | 0.3989 | 139.3 |
| [R3](R3/trace-index.jsonl) | natural-routing | direct | 0 | 14/14 | 649,171 | 0 | 0.4258 | 161.8 |
| [R4](R4/trace-index.jsonl) | natural-routing | direct | 0 | 14/14 | 494,595 | 0 | 0.2706 | 86.4 |
| [R5](R5/trace-index.jsonl) | natural-routing | revised | 0 | 14/14 | 766,433 | 0 | 0.3722 | 107.3 |
| [R6](R6/trace-index.jsonl) | natural-routing | prior | 0 | 14/14 | 1,305,364 | 0 | 0.6140 | 199.0 |
| [H1](H1/trace-index.jsonl) | requested-handoff | prior | 1 | 14/14 | 1,507,496 | 428,645 | 0.8050 | 272.3 |
| [H2](H2/trace-index.jsonl) | requested-handoff | revised | 1 | 14/14 | 1,506,710 | 551,444 | 0.8567 | 347.1 |
| [H3](H3/trace-index.jsonl) | requested-handoff | revised | 1 | 14/14 | 2,800,271 | 794,432 | 1.3000 | 409.8 |
| [H4](H4/trace-index.jsonl) | requested-handoff | prior | 0 | 14/14 | 619,155 | 0 | 0.3206 | 133.5 |

## Interpretation boundaries

Natural-routing participants all used direct or ranged source reads, so those six runs measure the permitted exploration alternatives, not scout efficacy. The additional requested-handoff scenario explicitly asks for a scout and must be compared only within that scenario. H4 still skipped delegation; keep that noncompliance in the results, rather than dropping or replacing it. A cost comparison across different prompts would confound workflow and task wording.

Actual response metadata verifies `claude-sonnet-5` for implementers and `claude-haiku-4-5-20251001` for readers where dispatched. Two repetitions per arm on one task cannot establish population-level improvement. Passing behavioral checks is separate from evidence that every relevant caller was inspected before editing. Independent scoring of that distinction is recorded in the judge report.

## Reproduction and evidence

[Fixture origin](fixture-origin.json) identifies the unchanged registry package; [policy snapshots](policy-snapshots) preserve exact guidance and hooks. Run `python held-out-checks.py /path/to/candidate/checkout` against a preserved candidate package. Each run directory contains the source diff, candidate-authored executable checks, complete sanitized tool transcript, compact trace index, and independent behavior results. Apply a run's diff to the identified fixture before reproducing its result. Absolute candidate paths and model names are sanitized in judge transcripts; measured identities and raw transcript SHA256 remain in metrics. Raw originals remain under `/tmp/registry-workroom/retained/`.

## Invalidated setup attempts

All eight earlier attempts under a shared parent were excluded: two were superseded by final anchor wording; the shared-parent layout then allowed one scout to discover the held-out checker. All arms were restarted with separate parents and an identical instruction forbidding parent/sibling exploration. The H1 scout violated the scope instruction by listing its parent directory (transcript events 195/197). That output contained only its own checkout; no hidden checks or sibling arm were exposed. No retained transcript shows access to hidden evaluation material. [Invalidation metadata](invalidated-runs.json) records hashes, reasons, and known costs. Interrupted attempts lack final usage summaries, so their full cost is unavailable; retained-run cost is not represented as all-in session spending.

## Observed cost and context tradeoffs

Natural routing averaged 769,452 accumulated parent tokens for revised guidance, versus 987,176 for prior guidance and 571,883 for direct source. Mean list-price-equivalent cost was $0.3856, $0.4812, and $0.3482 respectively. Revised guidance was cheaper than prior guidance in this sample and more expensive than direct source. No scouts ran in this scenario.

With explicitly requested delegation, revised guidance averaged 2,153,490.5 parent tokens plus 672,938 reader tokens, versus 1,063,325.5 parent plus 214,322.5 reader tokens for prior guidance. Mean cost was $1.0784 versus $0.5628. One prior run skipped delegation, so this is a comparison of outcomes under the requested policies, not four successful scout handoffs. The data does **not** support consistent end-to-end token savings from the revised handoff.

Source-map fidelity also remains limited despite passing implementations. A separate adversarial review found that H2's scout said local metadata was skipped entirely, including kept regions (reader event 239); H3 said the local renderer replaced both/all metadata blocks (event 311). The unchanged local `_unmanaged_regions` helper appends metadata lines when `keeping` is true, so those summaries overstate what is removed from foreign sections. These inaccuracies are retained in the transcripts. They demonstrate why scout output needs source verification; they cannot be turned into evidence that codebase understanding is guaranteed.

The ten retained runs account for $5.7122284 list-price-equivalent usage. Invalidated attempts additionally include one completed run reporting $0.3118392; interrupted-attempt total costs are unavailable. This is an explicit accounting limit, not zero overhead.

## Blinded grading and synthesis

One fresh-context judge scored all ten sanitized outputs in one pass on the frozen scale, without model identities or arm mappings. Its [complete judgment](judgment.json) includes event anchors and uncertainty notes.

| Scenario | Prior | Revised | Direct source |
|---|---|---|---|
| Natural routing | R1: 7/10; R6: 7/10 | R2: 7/10; R5: 7/10 | R3: 8/10; R4: 7/10 |
| Requested handoff | H1: 6/10; H4: 9/10* | H2: 7/10; H3: 8/10 | Not run |

*H4 skipped explicitly requested delegation. The frozen rubric does not automatically penalize scout absence; that instruction-compliance failure is reported separately rather than retroactively changing its score.*

The judge found no natural-routing implementation had directly inspected both adapter contracts before its first edit. H1–H3 also left GitHub consumer understanding to the scout. H4 directly read relevant excerpts from both adapters, although its local excerpt omitted later provider-state assignments. Full-file reading was not required for that judgment. Only H3 demonstrated executed local-provider update/status preservation coverage beyond the shared parser/factory checks. All ten passed the independent adapter/state checks, which remain separate evidence from what candidates themselves validated.

The judge independently identified wrong-file and corrupted source quotations in H1 and overgeneralized local-renderer commentary in H2/H3. The coordinator's and separate adversarial review's source checks agree with those factual concerns; there is no unresolved grading disagreement. H3's extra local writer correction was judged relevant to the request's human-text preservation requirement, rather than gratuitous scope expansion. Its additional work also contributes to its higher cost, so that cost is not attributable solely to longer handoff instructions.

**Recommendation: keep the clearer source-understanding policy, but do not claim demonstrated token-saving or context-preservation efficacy.** This sample shows correct bounded implementations with mixed cost, incomplete direct caller inspection, and inaccurate scout summaries. The revised policy is reviewable as a safeguard; its effectiveness remains a limitation, not a passed guarantee.
