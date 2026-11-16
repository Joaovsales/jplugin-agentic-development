# Code-graph adoption — evaluation protocol

## Registration, scope and model

No paid generation may start until this protocol and the finalized run manifest are committed and their hashes verify. After the first paid request, this file and the go-rule bytes are frozen; statuses and evidence updates belong in the ledger, never here. A changed protocol invalidates prior runs and halts execution.

Harness: Claude Code 2.1.325, Linux. Exact requested model: `claude-opus-5-5` on every arm/attempt. This resolves the measured harness's configured session default `opus`, supported by retained local resolver/session provenance in `preflight-after-install-2026-11-15.json`. No convenient alias or alternate requested model substitutes. The known served `claude-opus-4-8` mapping is included only in conservative pricing; an unexpected served ID halts admission.

Arm C is excluded: the slice-4 spike did not demonstrate Serena inside the runner workspace. The verdict covers Claude Code only, with no inference about Codex, Pi, Cursor or LSP lift.

## Arms, immutable sources and fixtures

- A: off; merged Phase A `c7360e41fc0c466764b0bb4e32df6dd35d279b5b` (PR #416), no graph and no graphify on its neutral PATH.
- B: graph; initial treatment source `e2bf011301812c9da7f22d4799d234249d54f6ed`.
- D: degraded; the same initial treatment source, with the fixed seed-selected stub.
- Operational documentation does not change these initial runtime payloads. Record each attempt's immutable source SHA and manifest SHA. Only the predeclared wiring-revision rules below permit a new treatment source.

Fixtures are synthetic seeded Python/TypeScript commerce projects, each at least 150 files and 20,000 lines; no real-repository replay. All arms use the identical `.gitignore` and `.ignore` exclusion `graphify-out/`. Initialize and commit the generated fixture to an explicit deterministic git baseline before graph construction, so graph freshness has the same clean tracked-file baseline.

B/D build the graph using the person's installed pinned `graphifyy==0.9.109`, under `timeout 120`. No agent installs packages. Query/explain/path and code update were inspected as local graph/AST operations. Never restore the stock GRAPH_REPORT hook or read its report whole.

D builds the real graph first, then installs its stub first on PATH. `seed % 4` selects: 0 nonzero exit; 1 sleep 60 seconds; 2 empty successful output; 3 corrupt graph JSON, also planted before the candidate starts. Each retry retains the seed and assigned fault.

## Fixed sample and order

N = 3 per case per selected arm: 10 cases × A/B/D × 3 = 90 selected slots. Arms run sequentially A, then B, then D; within each arm use table order, repetitions 1, 2, 3. No full suite runs beside an arm.

| Case | Kind | Seed |
|---|---|---:|
| invoice-rounding | localization | 101 |
| dispatch-callers | localization | 102 |
| currency-shape | localization | 103 |
| credit-flow | localization | 104 |
| terms-failure | localization | 105 |
| status-rename | localization | 106 |
| refund-balance | localization | 107 |
| readme-copy | control | 108 |
| profile-port | control | 109 |
| receipt-module | control | 110 |

The paid smoke is A/invoice-rounding/run-1, the first planned slot, never an extra sample. Project remaining program cost after that smoke and before further paid requests; halt if the projection exceeds $320. Never add runs to move a threshold or resolve a close verdict.

## Identical blinded runner

The primary plugin-eval runner exposed `claude-eval` paths. Use the spec-supported direct-CLI/Workflow fallback in `run-code-graph.py`, with the same plugin arm, case, seed, model, limits and retained result contract. The candidate sees only neutral package/home/config/app/scratch/tool paths; no results, expected answers, arm labels or experiment metadata. Each attempt's own private runtime scratch is readable and writable as needed; host harness and credential stores remain denied. OAuth reaches the native client/gateway through an in-memory descriptor, never a candidate-visible credential file.

Use each case's unchanged organic prompt plus these identical sentences in every arm: `Keep all work local; do not push or open pull requests.` `Do not install or upgrade software.` The launcher also disallows pip, pipx and python-m-pip command patterns.

The requested core tool pool is Bash, Edit, Write, Read, Grep, Glob and Skill; the native SDK may add its DeferredToolPlaceholder infrastructure tool. It adds no model-launching capability. Native Bash sandboxing stays enabled and fails if unavailable; unsandboxed bypass is disabled, with the same sandbox/settings across arms. Strict empty MCP configuration excludes host servers. Agent, Task, Workflow, Monitor and other model-launching tools are unavailable. External network from candidate Bash is denied.

Native options are identical across arms: exact model, stream-json/verbose retained output, 30-turn limit, output cap 4096 tokens, SDK retries 0, fast/background/auto-memory/compaction off, nonessential traffic off and isolated user settings. `--max-budget-usd 4` is supplemental; it is not represented as a hard in-flight cap. The admission gateway supplies request-level budget enforcement.

## Budget admission and accepted assumptions

$4 maximum per attempt; $320 maximum program total, including failed attempts, retries and replacement campaigns. Before launch, durably record a pending $4 reservation in the ledger/state and verify that current accounted spend plus $4 fits the total ceiling. Unknown or failed paid costs never default to zero. A confirmed unpaid/no-forward preflight is retained separately from selected runs.

Every model request must pass `admission_gateway.py` before forwarding to canonical `api.anthropic.com`. It admits only the exact requested model, known normal modes, text/custom-tool shapes and max_tokens ≤4096; unsupported billable endpoints, server tools, documents/images, modes and betas fail closed. Redirects refuse. Authentication/body content never enter audits.

For each request, reserve `1.1 × (10 × input_bound + 25 × max_tokens) / 1000000` dollars before forwarding, where `input_bound = full UTF-8 JSON bytes + 65536 + 256 × JSON container nodes`. A lock keeps settled upper cost plus all outstanding reservations ≤$4. Retrying a request needs another reservation.

The reviewed bound is conditional on ordinary byte-level text tokenization, the admitted protocol's structural overhead fitting that allowance, ordinary max_tokens semantics, accurate reported usage and the known normal pricing contract. It is not an unconditional guarantee against provider billing faults, undisclosed charges or future pricing/tokenization changes. A billing/bound assumption breach halts before any further paid request.

Normal pricing union for requested 5.5/known mapped 4.8, per million tokens: input $5, output $25, cache-write at most $10 (1h), cache-read $0.50, with conservative geo multiplier 1.1. These catalog tiers have no long-context price uplift. Admission treats all input as the most expensive cache write; complete usage can settle at the corresponding distinct conservative rates.

Only complete JSON or correctly ordered, monotone, terminal SSE usage releases unused reservation. Partial/unknown usage holds the entire reservation; inconsistent counters/events, unknown pricing/served models or extra billed iterations hold and block. Audit retains hashes, bounds, reserved/settled/held amounts and denials, without identities, request bodies or secrets. Debit each attempt by `max(native nominal cost, gateway accounted upper cost)`; pending/held uncertainty remains charged until proven reconciled. All program projections and ceilings use that upper accounting.

## Errors, retries and permitted revisions

One errored slot retries once with the same seed, preserving both attempts and all spend. A second error marks that slot errored/excluded/countable. More than 10% errored slots in an arm requires one whole-arm rerun within budget; repeated excessive errors hit the circuit breaker and halt. Archive discarded attempts/campaigns outside selected `run-*` paths; never overwrite their evidence.

Rule-4-only wiring failure reopens slices 5–7 and reruns only B/D, at most twice. Rule-6-only fallback failure reopens slices 5/7 under the same two-retry limit. A third such failure is no-go. Retain original A evidence; permitted revisions receive immutable treatment source/manifest versions in the ledger, without changing this protocol, its rule or earlier records. Budget/verification halts take precedence over any retry.

Infrastructure failures are not measured no-go results. Missing prerequisites, unverified evidence, budget exhaustion, changed frozen bytes, critical security findings or forbidden managed-block conflicts reach HALTED-NEEDS-USER with receipts. Never force-push.

## Manifest, metrics and retained evidence

`run-manifest.json` binds the 90 slots, seeds, source SHAs, fixture source, native binary hash, operational launcher/gateway/relay hashes and protocol SHA256 before execution. Per-run receipts retain manifest/protocol commit hashes and verify current files before payment. The protocol does not embed a manifest digest; this avoids circular hashes. The initial manifest is immutable once that campaign starts; permitted revision manifests are separately versioned and audited.

Use the unchanged `arrange-plugin-eval-results.py` and shared `read_transcript.py`. Measure verdict `wall_seconds` from the retained parent transcript’s first timestamp to its last timestamp, as the unchanged grader does; native `duration_ms` is audit evidence only, not a verdict input. Measure parent plus any retained delegated tokens, genuine tool invocations and deterministic case outcomes. No candidate self-report or LLM judge substitutes. Deterministic regex graders use their fixed weights; controls additionally check the specified file targets. Availability probes do not count as graph adoption.

Selected layout: `<date>/<arm>/<case>/run-<n>/` with transcript.jsonl, outcome.json, metadata.json and any delegated transcripts. Raw transcripts remain retained and gitignored. Track safe metadata/outcomes, audit hashes and evidence pointers; each verdict input traces to its run directory. Retain failed/replaced attempts separately and include every cost in the ledger/program total.

`results.md` reports every arm's per-case paired means, errored counts, selected input costs and all-attempt program spend, and the grader's verbatim `Verdict:` line. Flag results within two points of a threshold without adding samples. Include exactly:

Harness measured: Claude Code 2.1.325; not measured: Codex, Pi, Cursor

## Outcome gates

Go requires all six rules plus quality gate, full suite and Linux CI green before merging the treatment. Open downstream `/sync` PRs for projects with graphs, merge none, and backlog Codex replication. No-go closes treatment unmerged with a results link, records the numerical learning and optional wording, and merges the separate results PR only after the same quality/full-suite/Linux-CI gate. Phase A remains merged. The ledger ends MERGED, NO-GO-RECORDED or HALTED-NEEDS-USER.

### Go rule (pre-registered)

The arm under test (B or C) passes against A when all six of these hold over
N = 3 runs per case:

1. **Correctness, localization cases:** its mean outcome is at least A's, and
   no case drops by more than one run in three.
2. **Cost, localization cases:** median total tokens are at most 0.85 × A's,
   or the mean outcome is at least A's + 10 points with median tokens at most
   1.10 × A's.
3. **Overhead, controls:** the outcome is no worse than A's, and median tokens
   are at most 1.15 × A's.
4. **Adoption:** the graph or LSP tools are called in at least 60% of its
   localization runs.
5. **Latency:** median wall time is at most 1.30 × A's.
6. **Graceful degradation:** arm D's localization outcome is at least A's, no
   case drops by more than one run in three, and D's median tokens are at most
   1.15 × A's.

A failure on rule 4 alone is a wiring defect, not a verdict. The orchestrator
re-opens slices 5, 6 and 7 with the adoption evidence, revises the treatment's
instructions, and re-runs only arms B and D, at most twice. A third rule-4
failure is a no-go.

A failure on rule 6 alone re-opens slices 5 and 7 the same way, under the same
two-retry limit, because the fallback text is part of the treatment.

When both B and C pass, C ships only if it beats B on rule 1 or rule 2.
Otherwise B ships, because it adds no MCP server.
