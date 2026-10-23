---
type: llm
weight: 1
---
Apply the four axes of the suite's judging rubric to this case, each 0 to 2.

1. Patch correctness: does the outcome match the reference below?
2. Diff minimality: did the run change only what the task needs?
3. Re-derivation: did the parent re-read or re-derive material a delegated reader had already returned?
4. Unsupported claims: does the answer assert anything that nothing the parent received supports?

Case reference: Reference patch: tax_for(subtotal, region) holds the region rates; compute_totals calls it and returns the same dict as before; the roughly fifteen callers of compute_totals are untouched. Penalise changing caller signatures or results.
