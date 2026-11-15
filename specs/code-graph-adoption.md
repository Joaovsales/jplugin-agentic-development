---
implementation_paths:
  - README.md
  - install.sh
  - AGENTS.md
  - hooks/hooks.json
  - .agents/graphify.pin
  - .agents/hooks/session-start.sh
  - .agents/hooks/code-graph-hint.sh
  - .agents/references/code-navigation.md
  - .agents/skills/sync/SKILL.md
  - .agents/skills/how/references/explorer-prompt.md
  - .agents/skills/debug/SKILL.md
  - .agents/skills/plan/SKILL.md
  - .agents/skills/quality-gate/SKILL.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/eval/SKILL.md
  - .agents/skills/eval/scripts/grade-code-graph.py
  - codex/hooks/code_graph_hint.py
  - scripts/install-codex.sh
  - scripts/render-codex.py
  - evals/code-graph/**
  - tasks/eval-results/code-graph/**
  - tasks/code-graph-run.md
  - tasks/solutions/**/code-graph-*.md
  - tasks/backlog.md
  - tests/test-install-sh.sh
  - tests/test-session-start.sh
  - tests/test-code-graph-hint.sh
  - tests/test-grade-code-graph.sh
  - tests/test-code-graph-suite.sh
  - tests/test-code-graph-wiring.sh
  - tests/test-codex-install.sh
---

# Spec: Code-graph adoption, gated by a measured A/B

## Summary

The harness tells agents to prefer the graphify code graph (`AGENTS.md` § Core
Principles, *Code Graph First*), but no skill calls it. The install path names
a PyPI package that does not exist, and the one hook graphify ships tells agents
to read a 124 KB report.

This program first fixes that hygiene. It then measures, in a pre-registered A/B
on localization-heavy tasks, whether graph-aware navigation beats the plain
harness, and whether a broken graph leaves the agent no worse off than having no
graph. Only a passing go rule ships the routing rule, the hooks and the skill
wiring through test, PR and merge. A failing go rule records the negative result
and leaves graphify optional.

Every path degrades to the plain `Grep`/`Glob`/`Read` harness. Agents never
install software. An orchestrator agent runs the whole program as one
persistent goal loop (§ Run Protocol).

## Behavior

### Harness coverage

| Mechanism | Claude Code | Codex | Pi | Cursor |
|---|---|---|---|---|
| Routing rule and skill steps (text) | yes | yes | yes | through `AGENTS.md` only |
| `graphify` CLI calls (shell) | yes | yes | yes | yes |
| Graph hint hook | plugin `hooks/hooks.json` | adapter, when the slice-6 probe finds PreToolUse support | none | none |
| Session status line | plugin SessionStart | existing Codex SessionStart adapter | none | none |
| Measured by the eval | yes | no | no | no |

A harness with no hook still gets the routing rule, and on that harness the
rule alone carries the behaviour. A harness that ignores the rule behaves as it
does today. `results.md` states which harness and version were measured, and
that the verdict does not cover Codex, Pi or Cursor.

### Install and update policy

- `.agents/graphify.pin` holds the single pinned version, `<PIN>`. `install.sh`,
  the session banner and `/sync` Step 7 all read it from there. `<PIN>` is the
  current PyPI release of `graphifyy` (the package name has two `y`s) on the day
  slice 1 is built, checked against the canonical repository
  `github.com/Graphify-Labs/graphify`. Look-alike domains are never a source.
- `install.sh` is run by a person. When graphify is absent, or its version
  differs from `<PIN>`, it offers `pipx install --force graphifyy==<PIN>` behind
  a y/N prompt. It prompts only when all of these hold: stdin is a TTY, `CI` is
  unset, and `pipx` is on `PATH`. Every other case prints one `NOTE` line with
  the exact command and continues. Declining is not an error.
- Agents never install or upgrade graphify. `code-navigation.md` says so, and
  no skill step runs `pip` or `pipx`. The graph itself is rebuilt
  automatically: by the git hooks on commit and checkout, and by `/build` at
  each slice handover.

### Phase A: hygiene (ships regardless of the eval)

- `README.md`, `install.sh` and `/sync` Step 7 name `graphifyy==<PIN>`,
  following the policy above.
- After `graphify claude install`, `install.sh` deletes the stock PreToolUse
  entry, the one that tells agents to read `graphify-out/GRAPH_REPORT.md`, from
  `.claude/settings.json`. It keeps the moved `## graphify` rules section, but
  rewrites the line that points at `GRAPH_REPORT.md` into a budgeted
  `timeout 20 graphify query "<question>" --budget 1500`.
- `AGENTS.md` § Code Graph (below the end marker) describes this repository as
  it is: the graph covers the Python scripts under `.agents/skills/*/scripts/`,
  is built with `graphify update .` and stays gitignored.
- The session banner's Code Graph Check prints exactly one line per broken
  state, and nothing when every state is healthy:
  - `code graph: stale`: the graph is older than HEAD, or older than a
    modified tracked code file.
  - `code graph: broken`: `graph.json` fails to parse, or
    `timeout 5 graphify --help` exits non-zero.
  - `code graph: version drift <installed> != <PIN>`, followed by the upgrade
    command.
  - The existing "installed but no graph" line.

  Graphify that is not installed stays silent, as today. Each probe is bounded
  by `timeout`, and the banner always exits 0.

### Phase B: measurement

- `evals/code-graph/` is a `claude plugin eval` suite of at least 10 cases.
  - At least 7 localization cases: a call-chain bug, all callers of a function,
    the blast radius of a signature change, a cross-module data flow, a
    stack-trace-to-root-cause, and a renamed symbol.
  - At least 3 controls where the research expects the plain harness to win: a
    typo, a YAML config edit, and a new-file scaffold.

  `fixture_gen.py` generates each fixture from a fixed seed: a multi-package
  Python and TypeScript repository of at least 150 files and 20,000 lines.
  Every case carries a deterministic `outcome` grader: the answer names the
  file, and the function where the case defines one, that holds the seeded
  defect. Case names, prompts and paths obey `/eval` § *Blinding
  non-negotiables*.
- The run compares four arms, each a plugin build on its own branch:
  - **A (off):** the merged Phase A harness, with no graph in the workspace.
  - **B (graph):** the Phase C treatment, with the scaffold running
    `graphify update .` at `<PIN>`.
  - **C (graph+LSP):** B plus Serena's symbol tools and the LSP rows of the
    routing rule.
  - **D (degraded):** B's build, with a `graphify` stub first on `PATH`. Each
    case's seed assigns the stub one of four failure modes: exit 1, hang past
    the 20-second timeout, empty output, or a corrupt `graph.json`.

  Arm C runs only when the slice-4 spike shows that the runner can provide
  Serena inside the eval workspace. The spike's result is recorded in
  `evals/code-graph/README.md`. Without Serena, the absence of arm C is
  recorded in `protocol.md`.
- `.agents/skills/eval/scripts/grade-code-graph.py` grades from transcripts,
  through the shared `read_transcript.py` parser. For each run it reports:
  - graph tool calls (`Bash` commands that invoke `graphify`) and LSP tool
    calls (`mcp__serena__*`);
  - native `Grep`, `Glob` and `Read` calls;
  - total tokens (parent plus sub-agent) and wall time;
  - the outcome from `outcome.json`.

  It prints per-case means per arm as paired rows, and one `Verdict:` line that
  applies the go rule.
- `tasks/eval-results/code-graph/protocol.md` is committed before any paid run.
  It records the arms, N, the seeds, the model id, the harness version, the
  budget and the go rule, verbatim. Changing the protocol after the first paid
  run invalidates every run made under the old version.

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

### Phase C: treatment (built before the eval, shipped only on go)

**The routing rule.** `.agents/references/code-navigation.md` holds:

- **The capability ladder.** Use the language server when its tools are
  present; else the graph, when `graphify` runs and the graph is fresh; else
  `Grep`/`Glob`/`Read`, which are always available.
- **Routing:**
  - exact strings, config and non-code files → `Grep`/`Glob`;
  - definitions, references and callers of one symbol → LSP, else
    `graphify explain` and `graphify path`;
  - "what touches this", blast radius and module boundaries →
    `graphify query --budget 1500`;
  - never read `GRAPH_REPORT.md` whole.
- **Per-call fallback.** Every `graphify` call runs under `timeout 20`. A
  non-zero exit, a timeout, unparsable output or an empty result sends that
  question to `Grep`, with no retry of the same call. A stale or broken graph
  gets at most one `timeout 120 graphify update .` per session. If that fails,
  the session stays on `Grep`.
- **Confirm negatives.** A graph answer of "no callers", "unused" or "nothing
  touches this" is confirmed with `Grep` on the symbol name before any action
  depends on it. A missing edge is not evidence of absence.
- **No installs.** An agent never installs or upgrades graphify or a language
  server. It reports the banner's command instead.

**The hint hook.** `.agents/hooks/code-graph-hint.sh` is a PreToolUse hook on
`Grep|Glob`, registered in the plugin's `hooks/hooks.json` with a 5-second
timeout. It never calls graphify; it only checks files.

- **Fresh graph:** `graphify-out/graph.json` exists, is not older than HEAD,
  and is not older than any modified tracked code file. The hook then adds one
  line of `additionalContext` that names the routing reference.
- **Otherwise,** or on any internal error, it emits nothing.
- It always exits 0 and never denies a call.

**The Codex adapter.** `codex/hooks/code_graph_hint.py` wraps the same shell
hook for Codex. `scripts/install-codex.sh` and `scripts/render-codex.py`
register it, but only when slice 6's probe shows that the installed Codex
supports a PreToolUse event with a tool matcher. Without that support, nothing
is registered, and the coverage table records Codex as text-only.

**Skill steps.** Five skills each gain one step that cites the routing
reference and names the `Grep` fallback:

- the `/how` explorer prompt, at "find the entry point / trace the flow";
- `/debug`, at localization;
- `/plan`, at pre-flight "check this repository first";
- `/quality-gate`, at the caller and blast-radius check that *Code Economy*
  requires, where it confirms negatives with `Grep`;
- `/build`. Each slice handover runs `timeout 120 graphify update .` when
  `command -v graphify` succeeds and a graph exists. A failure there writes one
  warning line into the handover and never fails the slice.

**On go:** the treatment branch becomes a PR. It passes `/quality-gate`, the
full suite and Linux CI, and is merged. The `AGENTS.md` *Code Graph First*
principle is reworded to point at the routing reference. Each downstream
project that has a graph gets the change through a `/sync` PR (D9).

**On no-go:** the treatment branch is closed unmerged, with a comment that links
the results. `tasks/solutions/` gains one document recording the negative result
and its numbers. *Code Graph First* is reworded to "optional, measured no lift
on <date>; see <results path>". Phase A stays merged.

## Inputs

- The canonical graphify repository and its PyPI release `graphifyy==<PIN>`.
- `claude plugin eval` with `--scaffold --keep-temp --max-cost-usd`, on a Linux
  host with the sandbox backend. Bash must be granted, because graph tools are
  shell commands.
- `read_transcript.py` and `arrange-plugin-eval-results.py`, unchanged.
- The installed Codex CLI, for slice 6's hook-event probe.
- The orchestrator's budget ceiling and merge authority (§ Decisions).

## Outputs

- A Phase A PR, merged.
- The suite and the grader with their tests, plus `protocol.md`.
- Raw results under `tasks/eval-results/code-graph/<date>/`: transcripts are
  gitignored; `results.md` is committed and carries the `Verdict:` line and
  the harness-coverage statement.
- Either a merged treatment PR with downstream `/sync` PRs opened, or a closed
  treatment PR and a negative-result learning document.
- `tasks/code-graph-run.md`, the orchestrator's ledger, ending in exactly one
  terminal state.

## Edge Cases

- **`<PIN>` changes the CLI.** If `query`, `explain`, `path`, `update` or
  `hook install` moved or were renamed, slice 1 records the new forms in
  `code-navigation.md`'s source notes. Every later slice uses only those forms.
- **Graphify is not installed.** The banner and the hook stay silent, the
  routing ladder starts at `Grep`, and behaviour equals arm A.
- **Graphify is installed but broken, hangs, or returns nothing.** The banner
  prints one `broken` line. The hook is unaffected, because it never calls
  graphify. Each agent call falls back to `Grep` under the per-call rule, and
  arm D measures that path.
- **The graph is stale while a build edits files.** The hook stays silent,
  because its freshness check sees modified tracked files. `/build` refreshes
  the graph at the next handover.
- **There is no `pipx`, no TTY, or the run is CI.** `install.sh` prints the
  command and continues. Nothing installs.
- **The plugin eval runner cannot run arms or keep transcripts.** The fallback
  is the Workflow-based runner that writes the same
  `<results>/<arm>/<case>/run-<n>/` layout (`/eval` § Mode C).
- **One eval run errors.** It is retried once with the same seed. A second
  error marks it `errored`, excluded and counted. When more than 10% of an
  arm's runs error, that arm is re-run whole.
- **The budget is projected to be exceeded.** The orchestrator projects the
  cost after the smoke run. If the projection or the actual spend passes the
  ceiling, the loop halts in `HALTED-NEEDS-USER` before the next paid run.
- **The result is close to a threshold.** The verdict is still the rule's
  literal output. A result within 2 points of any threshold is flagged in
  `results.md`, and no runs are added to move it across a line.
- **A concurrent session pushes to the same PR branch.** Never force-push.
  Rebase on fetch, re-run the affected tests and push again.
- **The Windows CI leg fails with pre-existing failures.** Compare against the
  base with `comm`, never by count. Only new failures block.

## Interfaces

### code-graph-hint.sh

- **Path:** `.agents/hooks/code-graph-hint.sh`
- **Hides:** where the graph lives, the freshness rule (HEAD and the working
  tree) and the routing text.
- **Interface:** a PreToolUse hook. It reads hook JSON on stdin, writes either
  one `additionalContext` line or nothing, and always exits 0.
- **Alternative considered:** restoring graphify's stock hook in
  `.claude/settings.json`. That loses on two counts. The CI sync mirror
  overwrites that file (downstream commit `6d6f1eb8`, #262, 2026-08-03). And
  the stock message triggers a 124 KB read.
- **Depth:** one call decides whether a graph exists and is fresh, and what one
  line to say. The Claude plugin and the Codex adapter share it, and callers
  never learn graphify's layout.

### grade-code-graph.py

- **Path:** `.agents/skills/eval/scripts/grade-code-graph.py`
- **Hides:** the transcript shape (through `read_transcript.py`), tool
  classification and the go-rule arithmetic.
- **Interface:**
  `grade-code-graph.py <results-dir> --control A --arm <B|C> --degraded D [--json]`
- **Alternative considered:** a flag on `grade-read-shunt.py`. That script's
  metrics and verdict belong to another spec.
- **Depth:** a results directory in; a per-run table, paired means and one
  `Verdict:` line out.

## Run Protocol (for the orchestrator)

The orchestrator is the `/build` session started by the build prompt. It runs
until `tasks/code-graph-run.md` records a terminal state.

**Ledger.** `tasks/code-graph-run.md` holds:

- the current state and each slice's status;
- every eval run id with its arm, case, seed, cost and status;
- the PR numbers, the CI run ids and the cumulative spend.

The orchestrator updates it after every state change and commits it at each
slice handover. A fresh session resumes from the ledger alone.

**Branches and PRs:**

- Slices 1–4 build on the current branch, `Joaovsales/code-graph`. After slice
  4's handover, the orchestrator runs `/quality-gate`, the full suite and
  `/wrap-up-session`, then opens PR 1. It merges PR 1 under D11 once Linux CI is
  green. Arm A is `master` after that merge.
- Slices 5, 6 and 7 build on `code-graph/treatment`, cut from `master` after
  PR 1 merges. Arms B and D use that branch's plugin build. Slice 8 commits the
  protocol and results to the same branch.
- On go, slice 9 opens PR 2 from `code-graph/treatment` and merges it under D8.
- On no-go, slice 9 opens PR 2 and then closes it unmerged, with the results
  link; its branch is kept. Slice 9 also opens PR 3 from `master` on
  `code-graph/results`, carrying the results, the learning document and the
  `AGENTS.md` wording, and merges it under D11's gate.

**States:** `PHASE-A`, `HARNESS`, `TREATMENT`, `SMOKE`, `RUNNING`, `GRADING`
and `RETRY-<rule>-<n>`.

**Terminal states:**

- `MERGED`: go; the treatment is merged and the downstream PRs are opened.
- `NO-GO-RECORDED`: the negative result is merged and the treatment closed.
- `HALTED-NEEDS-USER`.

**Loop:**

1. Read the ledger.
2. Run `slice.py ready` to find the dispatchable slices.
3. Dispatch each ready slice to a sub-agent. Disjoint slices run in parallel.
4. Monitor each long job (an eval arm, the full suite, CI) as a background
   task with a Monitor until-loop, never by polling with sleep.
5. Verify each result from evidence: transcripts, exit codes and
   `gh pr checks`. A sub-agent's claim is not evidence.
6. Write the ledger, then repeat until a terminal state.

**Resiliency:**

- **Stalled sub-agent:** no tool call for 10 minutes, or no result after
  30 minutes. Follow `.agents/skills/build/references/subagent-resilience.md`:
  stop it, then re-dispatch once with a narrower scope and the read rules
  verbatim. A second stall counts as a step failure.
- **Step failure:** retry once after running `/debug` on the evidence. A third
  failure of the same step is `HALTED-NEEDS-USER`, with the evidence path.
- **One suite at a time:** run it through `cached-suite.sh` as
  `env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh </dev/null`. Finish
  any mutation probe before the suite starts.
- **Eval arms run sequentially,** never alongside the full suite.
- **CI red:** `/debug` and fix, at most two attempts, and retry a flake once.
  A third red is `HALTED-NEEDS-USER`.
- **Large artifacts:** follow *Large-Artifact Handoff*.

**Additional halts:** the budget is exceeded; a CRITICAL security finding; a
merge conflict in `AGENTS.md`'s managed block; any change to `protocol.md`
after the first paid run.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | Synthetic fixtures are too small or regular for a graph to matter | M | H | 150+ files and 20k+ lines; mixed Python and TypeScript; results within 2 points are flagged; a no-go is recorded honestly | 4 |
| R2 | The eval runner cannot grant Bash or provide Serena on this host | M | H | The slice-4 spike decides first; Workflow-based fallback runner; arm C can be dropped | 4 |
| R3 | Agents ignore the graph tools, so the eval measures wiring | M | M | Rule 4 measures adoption separately; at most two wiring revisions | 8 |
| R4 | Eval spend overruns | L | M | Per-run `--max-cost-usd`; a projection after the smoke run; a ledger halt | 8 |
| R5 | The `<PIN>` upgrade breaks downstream projects on 0.4.x commands | L | M | Slice 1 records CLI changes; rollout only through `/sync` PRs | 1, 9 |
| R6 | A broken graphify makes agents worse than no graph | M | H | The per-call fallback, negatives confirmed with `Grep`, and rule 6 measured by arm D | 5, 8 |
| R7 | The verdict is read as covering Codex, Pi or Cursor | M | M | The coverage table and the statement in `results.md`; Codex replication goes to the backlog | 8 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| D1 | Escalate to `/system-design-planning`? | No | assumed | No schema or external contract changes. The new calls are optional invocations of a CLI that `install.sh` already wires. |
| D2 | Does Phase A depend on the eval? | No. Phase A merges on its own gate | assumed | It contains a security fix and corrections of false statements. |
| D3 | Restore graphify's stock PreToolUse hook? | No. Remove it, and ship our own hint only on go | assumed | The CI mirror erases project settings, and the stock message triggers a 124 KB read. |
| D4 | How is graphify installed? | `pipx install --force graphifyy==<PIN>`, with `<PIN>` read from `.agents/graphify.pin` | assumed | Isolated from project venvs, with one source for the version. |
| D5 | Arms | A off, B graph, C graph+LSP (when the spike allows), D degraded | user | The user asked for fallback and graceful degradation to be verified, not assumed. |
| D6 | N and model | N = 3; the session-default model, recorded by id in `protocol.md` | assumed | k = 1 noise was the published study's main caveat. |
| D7 | Eval budget | $320 total ceiling, $4 per run | assumed | About 130 runs at about $1–2, plus one retry. Overrunning halts the loop. |
| D8 | Merge authority for the treatment | On go, merge once `/quality-gate`, the full suite and Linux CI are green | user | The user authorized merging when graphify improves the harness. |
| D9 | Downstream projects | On go, open `/sync` PRs in each project that has `graphify-out/`, and merge none | assumed | Merging in other repositories is outward-facing and was not authorized. |
| D10 | Real-repository replay cases | Out of scope; synthetic seeded fixtures only | assumed | Portable and reproducible. Replay can follow a go. |
| D11 | Merge authority for Phase A and the no-go results PR | Same gate as D8 | assumed | Independent of the verdict, and it contains a security fix. |
| D12 | Harness scope | Rule and skill steps for all harnesses; hooks for Claude Code and, when supported, Codex; the eval measures Claude Code only | user | The user asked for harness agnosticism. Hooks exist only where the harness supports them. |
| D13 | Auto-install | Never by an agent. `install.sh` offers it behind y/N, only interactively | user | The user asked about automatic installs. Unattended package installs are a supply-chain and machine-state risk. |
| D14 | Degradation contract | Capability ladder, per-call `timeout 20` fallback, one bounded refresh, negatives confirmed with `Grep`, hooks fail open | user | The user asked how fallbacks and graceful degradation work. |

## Acceptance Criteria

- AC1: `grep -rn 'pip install graphify\b' README.md install.sh .agents/skills/sync/SKILL.md` returns nothing. All three files read the version from `.agents/graphify.pin` and name `graphifyy`.
- AC2: After `install.sh` runs in a fixture project with graphify present, `.claude/settings.json` holds no `GRAPH_REPORT.md` hook. The `## graphify` section in `AGENTS.md` contains `timeout 20` and `--budget`, and no instruction to read `GRAPH_REPORT.md`.
- AC3: `AGENTS.md` § Code Graph states that the graph covers `.agents/skills/*/scripts/`. With a graph built at HEAD and a clean tree, the banner prints no graph line.
- AC4: `tasks/eval-results/code-graph/protocol.md` is committed before every paid run's start time, and `git log` against the ledger's timestamps shows this. It holds the go rule verbatim from this spec.
- AC5: `tests/test-grade-code-graph.sh` feeds `grade-code-graph.py` fixture results and asserts four things: the classification of a `graphify` Bash call, an `mcp__serena__` call and a native `Grep`; the paired means; `Verdict: go` on a fixture that passes all six rules; and `Verdict: no-go` naming the failed rule on fixtures that each fail one rule. A malformed transcript exits 2.
- AC6: `tests/test-code-graph-suite.sh` asserts that the suite has at least 7 localization cases and at least 3 controls. Each fixture is at least 150 files and 20,000 lines and byte-identical across two generations. No case name, prompt or path contains an `/eval` blinding word. The arm-D stub produces each of its four failure modes deterministically from the case seed.
- AC7: `tests/test-code-graph-hint.sh` asserts the hook's behaviour. With a fresh graph, it emits exactly one `additionalContext` line naming `.agents/references/code-navigation.md`. It emits nothing with a graph older than HEAD, a graph older than a modified tracked code file, a missing graph, no graphify, or a corrupt `graph.json`. A hanging CLI stub is never executed: with otherwise-fresh files the hook may still emit its file-freshness hint, and must finish within 2 seconds. CLI health is checked by the banner and per-call fallback, not by this file-only hook. It always exits 0 and never denies. (Build clarification: detecting an uncalled CLI hang is impossible; the explicit no-CLI hook contract takes precedence.)
- AC8: `results.md` reports, for every arm, the per-case paired means, the errored-run count and the total spend. It carries the grader's verbatim `Verdict:` line and the sentence `Harness measured: Claude Code <version>; not measured: Codex, Pi, Cursor`. Each verdict input traces to a run directory.
- AC9: On go, the treatment PR is merged with a `/quality-gate` receipt, a green full suite and green Linux CI. `AGENTS.md` *Code Graph First* cites the routing reference. A downstream `/sync` PR is opened for each project that has a graph, and a Codex replication item is added to `tasks/backlog.md`.
- AC10: On no-go, the treatment PR is closed unmerged, with a comment linking `results.md`. One `tasks/solutions/` document records the verdict and its numbers, and *Code Graph First* reads as optional with the results path.
- AC11: `tasks/code-graph-run.md` ends in exactly one of `MERGED`, `NO-GO-RECORDED` or `HALTED-NEEDS-USER`. Every slice has a `> Handover:` line, and the recorded spend is at most D7's ceiling.
- AC12: `tests/test-code-graph-wiring.sh` asserts that the `/how` explorer prompt, `/debug`, `/plan` and `/quality-gate` each cite `.agents/references/code-navigation.md` and name the `Grep` fallback at the steps § Phase C names, and that `/quality-gate` confirms negatives with `Grep`. It also asserts that `/build`'s handover runs `timeout 120 graphify update .` only behind `command -v graphify` and the existence of a graph, and that a failure there is a warning, never a failed slice.
- AC13: `tests/test-install-sh.sh` asserts the install policy. With no TTY, with `CI` set, or with no `pipx`, `install.sh` prints one `NOTE` with the command and installs nothing. With a TTY and `n`, it installs nothing and exits 0. With a TTY and `y`, it runs exactly `pipx install --force graphifyy==<PIN>` against a stubbed `pipx`.
- AC14: `tests/test-session-start.sh` asserts the banner's states. A graph older than a modified tracked code file prints `code graph: stale`. A corrupt `graph.json`, and a stub `graphify` that exits 1 or hangs, each print `code graph: broken` within the probe timeout. A version that differs from the pin prints `version drift` with the upgrade command. No graphify prints nothing. The banner exits 0 in every case.
- AC15: `tests/test-code-graph-hint.sh` also asserts that `code-navigation.md` states the capability ladder, `timeout 20` on every graphify command it shows, the four fallback triggers, the one-refresh limit, confirming negatives with `Grep`, and the no-install rule.
- AC16: `tests/test-codex-install.sh` covers the Codex adapter. When the probe records PreToolUse support, `install-codex.sh` registers `code_graph_hint.py` once (idempotent on re-run), and the adapter turns the shell hook's line into Codex hook JSON. When it records no support, nothing is registered and the coverage table says text-only.

## Implementation Paths

- `.agents/graphify.pin`: the single pinned graphify version.
- `README.md`, `install.sh`, `.agents/skills/sync/SKILL.md`: the install name, the pin, the interactive offer, hook removal and the budgeted rules text (Phase A).
- `AGENTS.md`: § Code Graph below the marker (Phase A); *Code Graph First* in the managed block (outcome).
- `.agents/hooks/session-start.sh`: the banner's one-line graph states (Phase A).
- `.agents/references/code-navigation.md`: the ladder, the routing and the fallback contract (Phase C).
- `hooks/hooks.json`, `.agents/hooks/code-graph-hint.sh`: the Claude Code hint hook (Phase C).
- `codex/hooks/code_graph_hint.py`, `scripts/install-codex.sh`, `scripts/render-codex.py`: the Codex hint adapter and its registration (Phase C).
- `.agents/skills/{how/references/explorer-prompt.md,debug/SKILL.md,plan/SKILL.md,quality-gate/SKILL.md,build/SKILL.md}`: the five wiring steps (Phase C).
- `.agents/skills/eval/SKILL.md`, `.agents/skills/eval/scripts/grade-code-graph.py`: the grader and its Mode C entry (Phase B).
- `evals/code-graph/**`: the suite, the generator, the arm-D stub, graders and rubric (Phase B).
- `tasks/eval-results/code-graph/**`: the protocol, results and verdict (Phase B).
- `tasks/code-graph-run.md`: the orchestrator ledger.
- `tasks/solutions/**/code-graph-*.md`: the negative-result learning on a no-go.
- `tasks/backlog.md`: the Codex replication follow-up on a go.
- `tests/test-install-sh.sh`, `tests/test-session-start.sh`, `tests/test-code-graph-hint.sh`, `tests/test-codex-install.sh`, `tests/test-grade-code-graph.sh`, `tests/test-code-graph-suite.sh`, `tests/test-code-graph-wiring.sh`: verification for AC1–AC7 and AC12–AC16.

## Build Order

Sizing: 9 slices. Ceiling: per `slice/references/sizing.md`. Over:
- slice 1 has 6 systems, because one install path is documented in three places, plus the pin, the test and the ledger;
- slice 2 has 3 systems, because the banner, its test and the repository description move together;
- slice 4 has more than 8 files, because each of the 10+ case directories holds the runner's fixed five-file shape;
- slice 5 has 4 systems, because a hook ships with its plugin registration, its routing reference and its test;
- slice 6 has 3 systems, because a Codex adapter needs its installer and its test;
- slice 7 has 6 systems, because one routing rule is cited from five skills plus one test.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | graphify install policy | pin file, `graphifyy` name, interactive y/N offer, stock hook stripped, budgeted rules text, ledger created | `.agents/graphify.pin`, `README.md`, `install.sh`, `.agents/skills/sync/SKILL.md`, `tests/test-install-sh.sh`, `tasks/code-graph-run.md` | — | 1, 2, 13 | `bash tests/test-install-sh.sh` | 6 files · 6 systems · 3 ACs |
| 2 | graph status reporting | `AGENTS.md` § Code Graph matches the tree; the banner prints one line per broken state | `AGENTS.md`, `.agents/hooks/session-start.sh`, `tests/test-session-start.sh` | 1 | 3, 14 | `bash tests/test-session-start.sh` | 3 files · 3 systems · 2 ACs |
| 3 | code-graph grader | `grade-code-graph.py` with tool classification, paired means and the six-rule verdict | `.agents/skills/eval/SKILL.md`, `.agents/skills/eval/scripts/grade-code-graph.py`, `tests/test-grade-code-graph.sh` | — | 5 | `bash tests/test-grade-code-graph.sh` | 3 files · 2 systems · 1 AC |
| 4 | localization suite | the runner spike in the suite README, seeded fixtures, 10+ cases, the arm-D stub, graders, rubric, one smoke run | `evals/code-graph/**`, `tests/test-code-graph-suite.sh` | 1, 3 | 6 | `bash tests/test-code-graph-suite.sh` | 50+ files · 2 systems · 1 AC |
| 5 | routing rule and hint hook | `code-navigation.md` with the ladder and fallback contract; a fail-open, working-tree-aware hint registered in the plugin | `.agents/references/code-navigation.md`, `.agents/hooks/code-graph-hint.sh`, `hooks/hooks.json`, `tests/test-code-graph-hint.sh` | 2 | 7, 15 | `bash tests/test-code-graph-hint.sh` | 4 files · 4 systems · 2 ACs |
| 6 | Codex hint adapter | a probe of Codex PreToolUse support; the adapter registered only when it is supported | `codex/hooks/code_graph_hint.py`, `scripts/install-codex.sh`, `scripts/render-codex.py`, `tests/test-codex-install.sh` | 5 | 16 | `bash tests/test-codex-install.sh` | 4 files · 3 systems · 1 AC |
| 7 | skill wiring | one routing step with the `Grep` fallback in each of the `/how` explorer, `/debug`, `/plan` and `/quality-gate`; a bounded graph refresh at `/build` handover | `.agents/skills/how/references/explorer-prompt.md`, `.agents/skills/debug/SKILL.md`, `.agents/skills/plan/SKILL.md`, `.agents/skills/quality-gate/SKILL.md`, `.agents/skills/build/SKILL.md`, `tests/test-code-graph-wiring.sh` | 5 | 12 | `bash tests/test-code-graph-wiring.sh` | 6 files · 6 systems · 1 AC |
| 8 | eval run and verdict | the protocol committed first; arms A, B, C and D run at N = 3 and graded; `results.md` with the verdict and coverage statement | `tasks/eval-results/code-graph/**`, `tasks/code-graph-run.md` | 4, 6, 7 | 4, 8 | `python3 .agents/skills/eval/scripts/grade-code-graph.py tasks/eval-results/code-graph/<date> --control A --arm B --degraded D` | 3+ files · 1 system · 2 ACs |
| 9 | outcome | go: PR 2 merged, downstream `/sync` PRs opened, Codex replication backlogged; no-go: PR 2 closed and PR 3 merged; the ledger reaches a terminal state | `AGENTS.md`, `tasks/solutions/**/code-graph-*.md`, `tasks/backlog.md`, `tasks/code-graph-run.md` | 8 | 9, 10, 11 | `env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh </dev/null` | 4 files · 2 systems · 3 ACs |

Build prompt:

```
Invoke `/build` for `specs/code-graph-adoption.md`.
Plan: `## Plan: Code-graph adoption, gated by a measured A/B` in `tasks/todo.md`, 9 slices, ready set <1, 3>.
Files: README.md, install.sh, AGENTS.md, hooks/hooks.json, .agents/graphify.pin, .agents/hooks/session-start.sh, .agents/hooks/code-graph-hint.sh, .agents/references/code-navigation.md, .agents/skills/sync/SKILL.md, .agents/skills/how/references/explorer-prompt.md, .agents/skills/debug/SKILL.md, .agents/skills/plan/SKILL.md, .agents/skills/quality-gate/SKILL.md, .agents/skills/build/SKILL.md, .agents/skills/eval/SKILL.md, .agents/skills/eval/scripts/grade-code-graph.py, codex/hooks/code_graph_hint.py, scripts/install-codex.sh, scripts/render-codex.py, evals/code-graph/**, tasks/eval-results/code-graph/**, tasks/code-graph-run.md, tasks/solutions/**/code-graph-*.md, tasks/backlog.md, tests/test-install-sh.sh, tests/test-session-start.sh, tests/test-code-graph-hint.sh, tests/test-grade-code-graph.sh, tests/test-code-graph-suite.sh, tests/test-code-graph-wiring.sh, tests/test-codex-install.sh.
Instructions:
1. `/build`'s pre-flight links the feature issue: one upsert, only when `slice.py link` prints `unlinked <id>`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints: Run as the persistent loop in § Run Protocol until `tasks/code-graph-run.md` records MERGED, NO-GO-RECORDED or HALTED-NEEDS-USER; resume from that ledger in any fresh session. D2/D11: slices 1-4 merge as PR 1 before the eval; the no-go results PR merges on the same gate. D3: never restore graphify's stock GRAPH_REPORT hook. D4/D13: graphify is installed only by a person through install.sh's y/N offer from `.agents/graphify.pin`; no agent or skill runs pip or pipx. D5: arms A off, B graph, C graph+LSP only if the slice-4 spike allows, D degraded stub. D6: N = 3, session-default model recorded by id. D7: $320 total, $4 per run; halt before exceeding. D8: merge the treatment PR only on `Verdict: go` (all six rules) plus quality gate, full suite and Linux CI green. D9: open downstream `/sync` PRs, merge none. D10: synthetic seeded fixtures only. D12: the verdict covers Claude Code only; register the Codex hook only when slice 6's probe finds PreToolUse support. D14: every graph path fails open to Grep; hooks always exit 0. The go rule and `protocol.md` are frozen once the first paid run starts; never add runs to cross a threshold; never force-push.
```
