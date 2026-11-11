# Judge rubric for the read-shunt suite

Written before any run and held back from the runs it grades. The runner hides
`evals/` from the agent, so this file may use the words the prompts must not.

Each judged run is scored on four axes, 0 to 2 each (maximum 8):

| Axis | 0 | 1 | 2 |
|---|---|---|---|
| Patch correctness | wrong, absent, or breaks the existing behaviour | right direction, partial or with a defect the reference does not have | matches the case's reference outcome |
| Diff minimality | edits unrelated files or rewrites what it did not need to | one avoidable extra edit | only what the task needs; for an explain-only case, no edits at all |
| Re-derivation | the parent re-reads or re-computes what a delegated reader had already returned, repeatedly | one redundant re-read or re-derivation | the parent used what the reader returned and read only what it still lacked |
| Unsupported claims | states a fact about the code that nothing the parent received supports | one claim stretched past its evidence | every claim traces to something the parent actually saw or was handed |

Rules for the judge:

- One judge scores every run of a case in one pass on one scale; two passes drift in calibration.
- Runs are shown under sanitised labels (run A, run B). Never a model name, a plugin name, an arm name or a variant name.
- Each pair is shown in both orders (A then B, B then A) and the two scores are averaged, so position bias cancels.
- Re-derivation applies only to runs that delegated a read; a run that never used a sub-agent scores the axis on whether it read the same region twice.
- The case reference lives in that case's `graders/judge.md`. When the reference and the run disagree, the reference wins.
- The deterministic graders and the `parent-read` indicator are reported beside the judge's score; they are not part of it.
