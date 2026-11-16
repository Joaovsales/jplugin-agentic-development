# Code-graph adoption results — 2026-11-16

Verdict: no-go — rule 2 (cost); rule 4 (adoption); rule 6 (graceful degradation)

Harness measured: Claude Code 2.1.325; not measured: Codex, Pi, Cursor

The unchanged registered grader consumed all 90 selected slots: 10 synthetic cases × A/B/D × N=3. All selected runs completed; no replacement campaign, treatment revision or extra threshold sample was added. Arm C was excluded by the registered spike. Requested model: `claude-opus-5-5`.

## Six registered rules

| Rule | Result | Observed values and frozen threshold |
|---|---|---|
| 1 Correctness | pass | Localization outcome A/B = 100%/100%; maximum case drop 0 runs (limit 1 of 3). |
| 2 Cost | fail | Localization median tokens A/B = 79,198/97,425; B/A = 1.230145, above 0.85. Outcome lift is 0 points, below the alternate +10-point requirement; token ratio also exceeds 1.10. |
| 3 Control overhead | pass | Outcome A/B = 100%/100%; median tokens 74,813/75,206; B/A = 1.005253 ≤ 1.15. |
| 4 Adoption | fail | Graph/LSP calls in 0 of 21 B localization runs = 0%, below 60%. Availability probes do not count. |
| 5 Latency | pass | All-case median wall seconds A/B = 11.8285/11.8380; B/A = 1.000803 ≤ 1.30. |
| 6 Graceful degradation | fail | Localization outcome A/D = 100%/100%, maximum case drop 0 runs; median tokens A/D = 79,198/100,621; D/A = 1.270499, above 1.15. |

Near-threshold flags (within two percentage points): the zero-point outcome differences in rules 1, 3 and 6 sit exactly at their non-degradation floors. Other percentage/ratio tests are more than two points from their thresholds. These flags do not alter the literal verdict or add runs.

No rule-only retry applies: rules 2, 4 and 6 fail together. The treatment was never adopted in the measured localization runs, so this result does not establish graph utility when used. D also recorded zero graph/LSP invocations: its configured fault conditions measure this treatment, not an independently demonstrated query-failure fallback.

## Paired per-case means

| Arm | Case | Runs | graph_calls | lsp_calls | grep_calls | glob_calls | read_calls | total_tokens | wall_seconds | outcome |
|---|---|---|---|---|---|---|---|---|---|---|
| A | credit-flow | 3 | 0 | 0 | 1.3333333333333333 | 0 | 0 | 137688.66666666666 | 19.223333333333333 | 1.0 |
| B | credit-flow | 3 | 0 | 0 | 0.6666666666666666 | 0 | 0.3333333333333333 | 138862.66666666666 | 19.861333333333334 | 1.0 |
| D | credit-flow | 3 | 0 | 0 | 1 | 0 | 0 | 153317.66666666666 | 20.904666666666667 | 1.0 |
| A | currency-shape | 3 | 0 | 0 | 1.3333333333333333 | 0 | 0 | 59883.333333333336 | 11.443666666666667 | 1.0 |
| B | currency-shape | 3 | 0 | 0 | 1.3333333333333333 | 0 | 0 | 72826 | 11.162 | 1.0 |
| D | currency-shape | 3 | 0 | 0 | 1.6666666666666667 | 0 | 0 | 87300 | 13.103 | 1.0 |
| A | dispatch-callers | 3 | 0 | 0 | 1.6666666666666667 | 0 | 0 | 50357 | 7.193666666666667 | 1.0 |
| B | dispatch-callers | 3 | 0 | 0 | 1.3333333333333333 | 0 | 0 | 44316 | 7.224 | 1.0 |
| D | dispatch-callers | 3 | 0 | 0 | 1.6666666666666667 | 0 | 0 | 51078.666666666664 | 7.87 | 1.0 |
| A | invoice-rounding | 3 | 0 | 0 | 0 | 0 | 0 | 125668.66666666667 | 15.953 | 1.0 |
| B | invoice-rounding | 3 | 0 | 0 | 0 | 0 | 0 | 128008 | 16.127000000000002 | 1.0 |
| D | invoice-rounding | 3 | 0 | 0 | 0 | 0 | 0 | 126978 | 15.090333333333334 | 1.0 |
| A | profile-port | 3 | 0 | 0 | 1 | 0 | 1 | 74730.66666666667 | 7.9543333333333335 | 1.0 |
| B | profile-port | 3 | 0 | 0 | 0.6666666666666666 | 0 | 0.6666666666666666 | 69317 | 8.436666666666667 | 1.0 |
| D | profile-port | 3 | 0 | 0 | 0.6666666666666666 | 0 | 1 | 83190.33333333333 | 9.693 | 1.0 |
| A | readme-copy | 3 | 0 | 0 | 1 | 0 | 1 | 62317 | 7.08 | 1.0 |
| B | readme-copy | 3 | 0 | 0 | 1 | 0 | 1 | 62725.333333333336 | 7.377666666666666 | 1.0 |
| D | readme-copy | 3 | 0 | 0 | 1 | 0 | 1 | 69018.66666666667 | 7.4736666666666665 | 1.0 |
| A | receipt-module | 3 | 0 | 0 | 0 | 0 | 0 | 87401.33333333333 | 14.380333333333333 | 1.0 |
| B | receipt-module | 3 | 0 | 0 | 0 | 0 | 0 | 86383.33333333333 | 14.552 | 1.0 |
| D | receipt-module | 3 | 0 | 0 | 0 | 0 | 0 | 87646.33333333333 | 13.796666666666667 | 1.0 |
| A | refund-balance | 3 | 0 | 0 | 1 | 0 | 1.6666666666666667 | 70833 | 11.323666666666666 | 1.0 |
| B | refund-balance | 3 | 0 | 0 | 1 | 0 | 2 | 70443 | 11.470333333333333 | 1.0 |
| D | refund-balance | 3 | 0 | 0 | 1 | 0 | 2 | 87791.66666666667 | 13.215333333333334 | 1.0 |
| A | status-rename | 3 | 0 | 0 | 1.3333333333333333 | 0 | 0 | 70965.66666666667 | 11.061666666666666 | 1.0 |
| B | status-rename | 3 | 0 | 0 | 1.6666666666666667 | 0 | 0 | 63854.333333333336 | 8.847 | 1.0 |
| D | status-rename | 3 | 0 | 0 | 1.6666666666666667 | 0 | 0 | 54500.666666666664 | 7.512333333333333 | 1.0 |
| A | terms-failure | 3 | 0 | 0 | 1.6666666666666667 | 0 | 1 | 122965.33333333333 | 18.582333333333334 | 1.0 |
| B | terms-failure | 3 | 0 | 0 | 2.3333333333333335 | 0 | 0.6666666666666666 | 103586.66666666667 | 15.455666666666668 | 1.0 |
| D | terms-failure | 3 | 0 | 0 | 2 | 0 | 0.6666666666666666 | 103561.66666666667 | 15.741 | 1.0 |

The table is copied verbatim from [the unchanged grader report](grader-report.md); its full per-run table and [JSON](grader-report.json) retain every verdict input. Tokens and wall time are transcript-derived; native CLI duration is audit evidence only.

## Errors and spend

| Arm | Selected completed / errored | Paid attempts / errored attempts | Selected nominal USD | All-attempt nominal USD | Accounted upper USD |
|---|---|---|---|---|---|
| A | 30 / 0 | 31 / 1 | 4.15103060 | 4.30030260 | 7.96195015 |
| B | 30 / 0 | 30 / 0 | 4.08166880 | 4.08166880 | 6.18941620 |
| D | 30 / 0 | 30 / 0 | 4.22682300 | 4.22682300 | 6.43833025 |
| Total | 90 / 0 | 91 / 1 | 12.45952240 | 12.60879440 | 20.58969660 |

The $320 program ceiling uses the $20.58969660 conservative upper accounting, including failed attempts. Every attempt stays within its $4 ceiling; no reservation remains pending. Native nominal cost is $12.60879440; selected-input nominal cost is $12.45952240. Full-precision source values remain in the evidence index and controller state.

The excluded original attempt `A/invoice-rounding/1/0/1` errored during usage decoding: nominal $0.149272, retained accounted amount $1.660241. A reviewed, versioned operational decoder recovery preserved the frozen protocol, cohort, original attempt and all charges. Its sole same-seed retry `A/invoice-rounding/1/0/2` completed and supplies selected `A/invoice-rounding/run-1` (nominal $0.1524704; accounted $0.23920710). The lost original raw SSE prevents asserting one unique triggering shape; the recovery proves compatibility with the enumerated native counter variants. This one historical error is not a selected-run error.

## Registration and evidence

- Frozen protocol commit: `f1f4df8715029e380c8b4e382a4547152f4082df`, committed `2026-11-15T23:43:23-03:00`; first paid attempt started `2026-11-16T02:50:43.118919+00:00`. Commit bytes and verbatim spec go rule verify.
- Protocol SHA256: `eceb8b458bf7b0464d0b523de8e87eec61f621151818aa29c1b4881932798dfd`.
- Original immutable manifest SHA256: `6e27abd6299168923124f2bcbaadec6f46df56ee0856070deb39400763894c1e`.
- Active compatibility manifest SHA256: `f91ff5d287569ab8c6cb8594d6c55f01ce9c2bbeaa3c39e39f557af01150c23a`; committed at `9cb54876fce13a8390583832523e85aafdb99804` before every attempt using it.
- Arm A source: `c7360e41fc0c466764b0bb4e32df6dd35d279b5b` (merged Phase A PR #416).
- Arms B/D source: `e2bf011301812c9da7f22d4799d234249d54f6ed`; fixture source: `c7360e41fc0c466764b0bb4e32df6dd35d279b5b`.
- [Evidence index](evidence-index.json) binds each selected run directory, its grader metrics, transcript/metadata/outcome SHA256 values, raw artifact root, and all 91 paid-attempt receipt/trace/admission/aggregate hashes. It also records native/operational/grader hashes and registration timing checks.
- Raw transcripts remain retained and gitignored. Relative run paths in the index resolve under this directory; absolute raw paths are local evidence pointers. Safe selected metadata and outcomes are committed alongside the report.
- [Controller state](../execution-state.json), [job control](../job-control.json), [recovery journal](../usage-compatibility-migration-applied.jsonl) and [compatibility notes](../usage-compatibility-notes.md) retain execution and recovery provenance.

The numerical verdict is recorded; treatment/results PR handling and quality, full-suite and Linux-CI gates remain the orchestrator’s next steps. No treatment merge is asserted here.
