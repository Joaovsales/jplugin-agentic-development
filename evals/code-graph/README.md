# Code-navigation suite

Ten fixed-seed commerce cases: seven localization problems and three controls.
Each scaffold creates eight Python packages plus TypeScript modules, exceeding
150 files and 20,000 lines. Only generated project files reach the workspace;
the generator's case records and reference answers stay outside it.

| Case | Kind | Seed | Problem |
|---|---|---:|---|
| invoice-rounding | localization | 101 | Call-chain arithmetic |
| dispatch-callers | localization | 102 | Remaining incompatible caller |
| currency-shape | localization | 103 | Signature-change blast radius |
| credit-flow | localization | 104 | Cross-module value flow |
| terms-failure | localization | 105 | Traceback to root cause |
| status-rename | localization | 106 | Renamed symbol's stale use |
| refund-balance | localization | 107 | Refund arithmetic |
| readme-copy | control | 108 | Typo |
| profile-port | control | 109 | YAML configuration |
| receipt-module | control | 110 | New-file scaffold |

`fixture_gen.py <case> --out <directory> --arm A` is deterministic and requires
only Python's standard library. Cases use the runner's `case.yaml`, `prompt.md`,
`fixture.sh` and `graders/outcome.md` layout. The control cases also have a file
grader for the requested change. No LLM grader is wired.

## Runner spike — 2026-11-15

- Host: Linux; Claude Code 2.1.325. `claude plugin eval --help` exposes
  `--scaffold`, `--keep-temp`, `--allow-tools`, `--max-cost-usd`, `--model`,
  `--runs`, `--ablation none`, `--mocks` and `--allow-real-servers`.
- Sandbox: bubblewrap 0.9.0 is installed. The read-only isolation probe
  `bwrap --ro-bind / / --unshare-net -- true` completed successfully. This
  establishes a backend prerequisite, not a completed model run.
- Arm C: excluded. The host configuration names Serena, but no Serena server
  was provisioned and demonstrated inside an isolated runner workspace.
  Capability flags and a host configuration name do not prove workspace tool
  availability. Record this exclusion in the pre-registered protocol.
- Graph prerequisite: the host has graphifyy 0.4.23; `.agents/graphify.pin` is
  0.9.109. The pinned version supports `--version`, `update .` and graph
  navigation. An agent must never upgrade it; a person uses `install.sh`.
- Paid smoke: deferred until `protocol.md` is committed and Phase A PR 1 is
  merged. No model call, paid result, token count or spend is claimed here.
  The fixture contract test provides the unpaid scaffold smoke.

Before any graph-arm run, run the prerequisite check outside the paid runner:

```bash
python3 evals/code-graph/fixture_gen.py --check-runtime
```

It refuses missing, broken or wrong-version graphify without installing
anything. The exact session model ID must be recorded in the protocol and
passed to `--model`; do not substitute a convenient alias. No model ID was
provided to this spike, so no model-selection claim is made.

## Arm preparation

Run arms sequentially on separate plugin builds: A is merged Phase A, B is
the unmerged treatment, D is that same treatment with the degraded stub.
The scaffold reads `CODE_GRAPH_ARM` (A by default). Set it explicitly for
every run. A creates no graph. B and D invoke the already-installed exact
pinned graphify under a 120-second timeout; version probing is bounded by
five seconds. No scaffold installs packages or language servers.

D additionally needs a fresh, neutrally named tools directory outside the
workspace. Set `CODE_GRAPH_STUB_DIR` to that directory, put it first on the
runner's `PATH`, set `CODE_GRAPH_REAL_GRAPHIFY` to the absolute pinned binary,
and set `CODE_GRAPH_SEED` to the case's seed before starting the runner.
The scaffold copies `stubs/graphify` into that tools directory after graph
construction. The model inherits the same PATH and seed. Do not rely on a
scaffold's exported variables persisting in its parent process.

The stub chooses `seed % 4`: 0 exits 1, 1 sleeps 60 seconds (beyond the
navigation timeout), 2 exits successfully without output, 3 writes corrupt
`graphify-out/graph.json`. The corrupt mode is also planted before the model
starts. Each retry of a case uses the same seed and failure mode.

## Paid-run protocol

After the protocol commit and Phase A merge, the orchestrator runs one case
and one repetition at a time. One invocation must use `--runs 1`,
`--concurrency 1`, `--ablation none`, `--max-cost-usd 4`, `--keep-temp`,
`--scaffold`, `--allow-tools Bash Edit Write`, `--trust-plugin`, `--no-publish`
and the protocol's exact `--model` ID. Never invoke this suite before checking
the ledger's cumulative spend and the next run's $4 reservation against $320.
The paid smoke counts toward the pre-registered N=3; never add samples to
change a verdict. Project spend from it before starting the remaining runs.

Use the Workflow-based runner described by `/eval` Mode C when the plugin
runner cannot grant Bash or retain transcripts. That fallback must preserve
the same plugin arm, model, seed, limits and result layout; it is not a
different population or a waiver of the budget.

Arrange retained evidence as:

```text
<results>/<arm>/<case>/run-<n>/
  transcript.jsonl
  outcome.json
  metadata.json
  subagents/agent-*.jsonl
```

`metadata.json` records `kind` (`localization` or `control`), integer `seed`,
`status` (`completed` or `errored`) and nonnegative `cost_usd`. Record one
planned slot per repetition; retries and their costs remain in the ledger
and outside `run-*`. Preserve all spend, including failed attempts. The
grader's selected-arm spend excludes any unselected optional arm, so the
report's program total must come from the ledger. Use the unchanged
`arrange-plugin-eval-results.py` and shared transcript parser; candidate
self-report is not measurement.

No fixture or runner result is a go verdict. The grader applies all six frozen
rules to matched cases and seeds at N=3, with the spec's exact error and
two-retry limits. Results must state that Claude Code alone was measured.
