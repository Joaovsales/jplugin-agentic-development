# Code-graph protocol draft — UNREGISTERED

This is an unregistered draft, not `protocol.md`. No paid run has started.
Do not rename or commit this as the registered protocol until the per-run budget
blocker below is resolved and the parent reviews the runner evidence.

## Registration and fixed inputs

- Harness: Claude Code 2.1.325 on Linux; verdict covers Claude Code only.
- Exact requested model ID: `claude-opus-5-5` on every run. The user's configured
  Claude alias is `opus`; the installed native default resolves to the opus55
  registry entry absent a policy override, and this workspace's retained Claude
  transcript records `claude-opus-5-5`. Read-only provenance is retained in
  `preflight-after-install-2026-11-15.json`. No model probe was run.
- Graphify pin: `graphifyy==0.9.109`, installed through the person's interactive
  `install.sh` choice; the canonical runtime guard now exits 0.
- Arm A: merged Phase A `c7360e41fc0c466764b0bb4e32df6dd35d279b5b`
  (PR #416). No graph in the scaffold.
- Arm B: the unmerged treatment build, exact source SHA recorded with each run.
- Arm D: B plus the deterministic fault stub first on PATH.
- Arm C: excluded; the slice-4 spike did not demonstrate Serena inside the
  isolated runner workspace. No inference about LSP is permitted.
- N = 3 for every case and selected arm: 90 planned slots. The paid smoke is
  slot A/invoice-rounding/run-1, not an additional sample.
- No paid run begins before official `protocol.md` is committed; retain that
  commit SHA and UTC time in the ledger. Freeze its bytes and the go rule after
  the first paid run. A protocol change then invalidates prior runs and halts.

[AMBIGUITY] The orchestrator uses Codex while the experiment measures Claude Code's session-default model | options: A) request the orchestrator's incompatible model through Claude Code B) use Claude Code's configured default resolved by exact ID | picked: B | reason: D12 scopes the measured harness to Claude Code and its local configuration and retained session support claude-opus-5-5.

## Cases and paired seeds

| Case | Kind | Seed | Repetitions per arm |
|---|---|---:|---:|
| invoice-rounding | localization | 101 | 3 |
| dispatch-callers | localization | 102 | 3 |
| currency-shape | localization | 103 | 3 |
| credit-flow | localization | 104 | 3 |
| terms-failure | localization | 105 | 3 |
| status-rename | localization | 106 | 3 |
| refund-balance | localization | 107 | 3 |
| readme-copy | control | 108 | 3 |
| profile-port | control | 109 | 3 |
| receipt-module | control | 110 | 3 |

Run arms sequentially A, B, D, one case at a time in table order and repetitions
1, 2, 3 in order. Preserve paired case/seed slots; never add runs to cross a
threshold. Fixtures are fixed synthetic Python/TypeScript projects with at least
150 files and 20,000 lines, generated outside the candidate's visible metadata.
Use organic prompts and neutral workspace/tool paths. No real-repository replay.

## Runner and budget admission — verification pending

The native plugin eval runner leaks `claude-eval-*` paths through its visible
sandbox policy. Use the spec-permitted direct CLI fallback in
`run-code-graph.py` with neutral `hr-*/round/{home/app,config,scratch,package,tools,out}`
paths. Its aggregate is derived from actual CLI output and the same fixed regex
graders, then consumed by unchanged `arrange-plugin-eval-results.py` and
`read_transcript.py`. No experiment, grader, task ledger or fixture source enters
the candidate workspace. Runtime payload copies include the complete plugin
manifest, skills, hooks, references and agents, excluding specs/tasks/evals/git.
The existing general workflow skill names remain the ordinary harness catalog.

Every prompt appends exactly: `Keep all work local; do not push or open pull requests.`
The native command fixes exact model `claude-opus-5-5`, 30 turns, output cap
4096, sequential execution and the same enabled/required Bash sandbox. Available
tools are Bash, Edit, Write, Read, Grep, Glob and Skill; no delegated or web model
calls. MCP configuration is empty. Fast mode, compaction, background tasks,
auto-memory and automatic request retries are disabled. Candidate environment is
an explicit allowlist. OAuth reaches the native process through an inherited
file descriptor, with no token value in its environment or artifacts.

A fresh localhost admission gateway guards each run, forwarding only the
admitted standard-pricing model request shape to api.anthropic.com. It reserves
before forwarding, under a concurrency lock, using UTF-8 request bytes plus
65,536 structural tokens and 256 tokens per structural node, the maximum known
Opus 4.8/5.5 cache-write price ($10/M input), output price ($25/M), a 1.1 geography
factor and a maximum of 4096 output tokens. See `admission-gateway.md` for the
explicit bound assumptions and fail-closed request/response contract. Complete,
valid usage settles at conservative permitted rates; incomplete/unknown usage
retains its full reservation. Unknown models/pricing stop further admission.
The native `--max-budget-usd 4` is a secondary stop check, never the primary cap.

- Total budget is $320, per run $4. Before each paid attempt, durably persist a
  pending $4 reservation. An unresolved reservation blocks restart and cannot
  silently pay for the same slot again.
- Persist each attempt's actual nominal cost or labeled conservative upper cost,
  protocol/source IDs, status and audit path before arranging results. A failed
  arranger resumes from retained evidence and never launches that attempt again.
- Every errored slot retries once, with the same seed; retain both attempts and
  charge both. More than 10% errored slots reruns that complete arm once; archive
  its prior inputs outside selected run directories, keeping N=3. A second arm
  failure halts. No additional samples may be added to cross a go threshold.
- The paid smoke is A/invoice-rounding/1; its cost projects the remaining fixed
  slots before more paid work. Reserve before exceeding total or projected cost.
- Manifest pins model/N/cases/seeds/sources, the native binary hash, fixture
  baseline and operational source hashes. Validate before every paid attempt.
  Official protocol bytes must match their committed hash before execution.
- Current spend remains $0. No paid execution or registered protocol exists.

## Arm preparation and fallback

All arms first generate the same source bytes, add `.gitignore` and `.ignore`
with exactly `graphify-out/`, and create an explicit fixture-local Git baseline
with fixed identity/date and hooks disabled. Graph preparation follows that
commit, ensuring freshness checks use the actual fixture repository. These two
cache exclusions match the normal installer and apply identically to A/B/D.

Set `CODE_GRAPH_ARM` explicitly. A has no graph. B/D invoke the already-installed
pinned `graphify update .` under 120 seconds (the installed global help identifies
update as code re-extraction with no LLM needed). Never install packages.
For D, place a fresh neutral tools directory first on runner PATH and set
`CODE_GRAPH_STUB_DIR`, `CODE_GRAPH_REAL_GRAPHIFY` to the exact pinned binary, and
`CODE_GRAPH_SEED` to the case seed before runner launch. Scaffold-only exports
cannot configure the parent runner. Stub modes are `seed % 4`: 0 exit 1;
1 sleep 60 seconds; 2 empty success; 3 corrupt graph JSON.
Every graph navigation call has `timeout 20` and falls open to Grep on failure,
timeout, malformed output, or empty result; permit at most one bounded refresh.
Confirm negative graph answers with Grep. Never restore the stock report hook.

## Retained evidence and grading

Use `<date>/<arm>/<case>/run-<n>/` with `transcript.jsonl`, `outcome.json`,
`metadata.json`, and delegated `subagents/agent-*.jsonl` when present. Metadata
records kind, integer seed, completed/errored status, and nonnegative cost_usd.
Ledger entries record run ID, arm, case, seed, UTC start/end, protocol commit,
plugin/source SHA, status, spend and retry linkage. Keep failed attempts outside
selected `run-*` and include their spend in the program total. Raw transcripts
remain gitignored, with retained artifact paths and hashes in tracked evidence.

Use unchanged `arrange-plugin-eval-results.py` and `read_transcript.py`. Grade
parent plus delegated tokens, actual wall time and deterministic outcome; count
genuine graph/LSP invocations, excluding availability probes. Candidate
self-report is not measurement. Run the unchanged `grade-code-graph.py` with
`--control A --arm B --degraded D`. Every verdict input must resolve to a retained
run directory. Missing evidence cannot produce go; malformed completed evidence
is an error, not a no-go result.

`results.md` reports per-case paired means for every arm, errored counts, selected
input spend and full program spend from the ledger, and the grader's verbatim
`Verdict:` line. Include `Harness measured: Claude Code 2.1.325; not measured:
Codex, Pi, Cursor` on one line. Flag any result within two points of a threshold
without adding samples. AC4 and AC8 remain unfinished until registration and
actual paid evidence exist.

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
