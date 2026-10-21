---
type: llm
weight: 1
---
Apply the four axes of the suite's judging rubric to this case, each 0 to 2.

1. Patch correctness: does the outcome match the reference below?
2. Diff minimality: did the run change only what the task needs?
3. Re-derivation: did the parent re-read or re-derive material a delegated reader had already returned?
4. Unsupported claims: does the answer assert anything that nothing the parent received supports?

Case reference: Reference answer: KeyError 'release_tag' raised in publish_manifest, deploy/release.py line 212, called from deploy/cli.py line 88. The log holds exactly one traceback; transient 503 and retry lines are noise. Penalise naming a noise line as the cause.
