# Bulk-read context: preregistered exploratory protocol

2026-09-12. Three workflow variants, two fresh Sonnet implementations per arm on one identical cross-file correction. Prior handoff comes from `5015f3d`; revised handoff is captured after source-ready; direct-source is an explicit workflow variant, **not** skill presence/absence ablation. Haiku is the installed scout persona model. Actual model IDs will be recorded from transcripts.

The fixture is the real `registry/` package extracted from this branch's task-registry skill: 3,443 source lines, including 404-line model and 536-line GitHub adapter. No synthetic padding. Its unrelated workflow files, histories, spec, and measurement artifacts are omitted. Ordinary project instructions share the same scope rules and differ in the handoff policy. Skills are disabled in all arms to isolate this handoff policy from unrelated globally installed workflows; this is a bounded workflow experiment, not full `/build` validation. The source and personas are committed to disposable local branches and cloned independently. No public remote is reachable through origin. Candidates receive the same natural correction request, including explicit local-only implementation authorization. Raw logs and held-out checks live outside candidate working directories.

## Frozen rubric (0–2 each; ten points)

1. Behavior: 2 for all held-out checks passing, 1 for partial correctness, 0 for no correct implementation or shared normal parsing regressions.
2. Source understanding: 2 for direct implementer inspection of parser, existing writer/bounds contract, and both local/GitHub consumers before editing; 1 for partial direct inspection or consumers seen only through scout evidence; 0 for editing without implementation/contract evidence.
3. Handoff integrity: 2 for factual anchored coverage and unresolved scope reported where applicable, or equivalent grounded direct-source exploration; 1 for lossy or incomplete but accurate evidence; 0 for wrong-file/invented evidence. Scout absence alone is not a penalty.
4. Scope/coherence: 2 for central shared fix preserving state and unrelated text without unnecessary sibling patches; 1 for working duplication or unrelated churn; 0 for divergent/broken sibling behavior.
5. Validation: 2 for runnable local checks of malformed blocks and sibling/state preservation; 1 for only parser or happy-path checks; 0 for no executable validation. Held-out checks remain invisible during implementation.

A single ceiling-tier judge will receive all six neutral-labelled outputs in one batch; no arm/model names or builder conclusions. The coordinator independently inspects transcripts and reports disagreements. Model identities are verified from actual response metadata; no identity is inferred merely from an alias.

## Independent checks

Check parser selection of innermost/latest complete pair with preceding stray or trailing incomplete markers; no complete pair means empty metadata; repeated evidence/reproduction/proposed-fix preserve commas and order; provider-neutral and both adapter conversions preserve identity, provider status and external references; writer preserves surrounding human text and remains readable; normal rendering remains valid.

## Accounting and decision

Retain full parent/subagent transcripts, diffs, exit status, elapsed wall time, actual model usage, and cost. Report parent input/output/cache reads/cache creation and scout usage separately, plus overall totals; do not sum overlapping result aggregates and individual requests. Deduplicate streaming usage by message ID if needed. Read exposure is reported separately as bytes/characters, never labelled tokenizer-measured tokens. Compare revised to both prior and direct. Two repetitions of one task are exploratory evidence only: no general codebase-context guarantee, causal population claim, or token-saving percentage beyond this sample. Runs that time out or cannot invoke the model remain visible as failures/limitations, never silently excluded.

## Isolation correction (before retained launches)

Early runs shared a parent directory. One scout escaped its checkout and read the held-out check script. All early runs were invalidated together, including otherwise uncontaminated runs, and retained runs restarted in six independent `/tmp/task-records-<name>/source` parents. Each parent contains only one checkout. Shared scope instructions explicitly prohibit parent/sibling/global/session exploration. An earlier pair was also interrupted when final anchor wording changed after launch. Invalidations and their usage overhead are retained separately; they never count toward results.

## Additional preregistered scenario: requested scout handoff

The natural-routing runs chose direct/ranged reads, so they cannot establish scout handoff quality. Before additional launches, add exactly four fresh runs: prior and revised handoff, two repetitions each, same package, same held-out checks and same rubric. Prefix the original request with: “Have bulk-reader map the affected metadata parsing flow and its consumers first, then implement the correction yourself using that handoff.” Everything else remains equal. This is explicitly requested delegation, not evidence of spontaneous routing. Compare cost and quality only between prior/revised within this scenario. The first scenario's direct-source arm is not a causal cost comparator across different prompts. No further scenarios will be added.
