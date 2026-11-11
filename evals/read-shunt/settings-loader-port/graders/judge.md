---
type: llm
weight: 1
---
Apply the four axes of the suite's judging rubric to this case, each 0 to 2.

1. Patch correctness: does the outcome match the reference below?
2. Diff minimality: did the run change only what the task needs?
3. Re-derivation: did the parent re-read or re-derive material a delegated reader had already returned?
4. Unsupported claims: does the answer assert anything that nothing the parent received supports?

Case reference: Reference behaviour: environment beats file beats default; an empty environment value counts as unset; ${NAME} and ${NAME:-fallback} interpolate against the environment then the file; each setting validates its type and range. Penalise a port that changes precedence, drops validation, or skips settings.
