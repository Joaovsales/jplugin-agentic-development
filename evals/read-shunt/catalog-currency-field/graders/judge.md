---
type: llm
weight: 1
---
Apply the four axes of the suite's judging rubric to this case, each 0 to 2.

1. Patch correctness: does the outcome match the reference below?
2. Diff minimality: did the run change only what the task needs?
3. Re-derivation: did the parent re-read or re-derive material a delegated reader had already returned?
4. Unsupported claims: does the answer assert anything that nothing the parent received supports?

Case reference: Reference patch: Product gains currency: str = "USD" and from_dict reads it; every one of the 2,200 entries in fixtures/catalog.json carries the key. Penalise a partial data update, a hand-copied subset, or edits to unrelated models.
