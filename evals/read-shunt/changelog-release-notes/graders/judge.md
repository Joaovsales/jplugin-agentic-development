---
type: llm
weight: 1
---
Apply the four axes of the suite's judging rubric to this case, each 0 to 2.

1. Patch correctness: does the outcome match the reference below?
2. Diff minimality: did the run change only what the task needs?
3. Re-derivation: did the parent re-read or re-derive material a delegated reader had already returned?
4. Unsupported claims: does the answer assert anything that nothing the parent received supports?

Case reference: Reference: release notes grouped by theme (not by version), covering the added, changed, fixed and removed entries across 3.0 to 3.11 without inventing entries. Penalise dropped versions, invented features and a flat copy of the changelog.
