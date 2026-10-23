---
implementation_paths:
  - .agents/skills/eval/SKILL.md
  - .agents/skills/eval/scripts/read_transcript.py
  - .agents/skills/eval/scripts/read-incidence.py
  - .agents/skills/eval/scripts/grade-read-shunt.py
  - evals/read-shunt/**
  - tests/test-read-incidence.sh
  - tests/test-read-shunt-grader.sh
  - tests/test-read-shunt-evals.sh
  - tests/test-eval-skill.sh
  - tests/fixtures/transcripts/**
  - tasks/eval-results/read-shunt/**
  - tasks/solutions/patterns/cross-harness-hook-by-input-shape-not-tool-name.md
  - tasks/solutions/process/bash-and-sub-agents-read-the-shared-checkout.md
  - tasks/solutions/architecture/subagents-for-research.md
  - specs/read-shunt.md
---

# Spec: Read-shunt baseline and eval harness

## Summary

Before any read gate ships, the repository measures how often the parent agent
pulls whole files over the shunt threshold into its own context, from the
session transcripts already on disk, and builds the eval harness that will judge
a gate when one is built. Both tools read the same transcript format through one
parser. The work supersedes PR #128, whose two gate implementations and paired
eval are kept as evidence. The research, the gate design and the eval design
this spec implements are `specs/read-shunt.md`; this spec covers its Tier 0 and
its grader, fixtures and rubric, on Claude Code only.

## Behavior

### Incidence report

`read-incidence.py` walks a transcript root (default `~/.claude/projects`) and
reads every main-loop session transcript, streaming one JSON line at a time so
an 800 MB root finishes in minutes and nothing but metadata is held in memory.
Sub-agent transcripts under each session's `subagents/` directory are read too
and reported in their own column, never mixed with the parent's.

For every `Read` tool use it records the input (`file_path`, `offset`, `limit`)
and the result metadata (`totalLines`, `numLines`, `startLine`, content length
in bytes). A read with neither `offset` nor `limit` is a *whole-file read*; one
whose `numLines` is below `totalLines` without a `limit` is a whole-file read
the tool truncated at its own cap, counted as whole-file and flagged. A read is
*large* when its content is at least `--bytes` (default 32768) or its
`totalLines` is at least `--lines` (default 800). A result that is not a text
file (image, PDF, notebook, directory, error) is excluded from every count and
tallied once as `excluded`.

For every `Bash` tool use whose command is a bare shell read of one or more
paths (`cat`, `head`, `tail`, `less`, `more`, `sed -n` with a print range),
neither piped nor redirected, it records the result length as bytes delivered.
Piped and redirected forms (`cat f | grep`, `cat f > g`) are not counted; every
file in a chained command (`cat a; cat b`) is.

The report, as a Markdown table on stdout or JSON with `--json`, gives per
session and in aggregate: reads, whole-file large reads, bytes those reads
delivered, their share of all tool-result bytes in the parent loop, shell reads
and their bytes, the largest single result, re-reads of a path already read in
the same session, the parent's final context size (input, cache-creation and
cache-read tokens of its last assistant message), compaction markers when the
transcript carries them, and sub-agent reads beside the parent's. File paths
appear as basenames unless `--paths` is passed; file contents never appear.

### Go rule

The baseline run is committed as `tasks/eval-results/read-shunt/baseline-<date>.md`
with the aggregate table and the rule applied: the gate (Tier 1 and Tier 2 of
`specs/read-shunt.md`) is built only when whole-file large reads account for at
least 10% of the parent's tool-result bytes in the median session, or at least
25% in a quarter of sessions. Below that, the report records "not worth gating"
and the brief's remaining tiers stay unbuilt.

### Eval harness

`evals/read-shunt/` is a `claude plugin eval` suite under the plugin root: eleven
cases, each a prompt written as a user would type it, a deterministic scaffold
script that generates its fixture into the case workspace from a seed, and its
graders. Eight cases force a large read (a generated client over 32 KB with a
three-line bug, a CI log over 20K lines with one stack trace near the end, a
fixtures JSON over 256 KB, a 3K-line module with scattered callers, a flaky
2K-line suite, a 1,500-line reference loader to port, a renamed symbol across 40
files, a 900-line changelog to summarise). Three are controls under the
threshold (a typo in a 60-line file, a test for a 200-line module, a question
about a file of 25 KB) where a gate must never fire. Fixtures are generated, not
committed, so nothing eval-shaped sits in a candidate's workspace, and no prompt,
case name or scaffold path contains the blinding words of `/eval` § *Blinding
non-negotiables*.

`grade-read-shunt.py` grades a run from transcripts, never from what the
candidate said. Given a results directory it emits one row per run with: parent
whole-file large reads; routing-around attempts (bare shell reads, `Grep` with
`-C` of 50 or more or `head_limit: 0` on a large file); hook decisions and
repeated identical denied inputs when a shunt log is present beside the
transcript; bytes delivered into the parent; the largest single result; the
parent's final context size; compaction count; sub-agent tokens and tool uses;
wall time from the first to the last timestamp; re-read rate (a parent read of a
path that an earlier `Agent` prompt or sub-agent result named); and the outcome
grade the runner recorded. It then prints per-task means per arm as paired rows,
so two runs of the suite (control plugin, candidate plugin) compare task by
task. Both scripts import `read_transcript.py`, the one place that knows the
JSONL shape; a Read, Bash, Agent or usage block that shape cannot read ends the
run with exit 2 and the offending line, never a silent zero.

The judge rubric is written into the suite before any run: patch correctness
against the reference, diff minimality, whether the parent re-derived what a
reader had returned, and whether the answer makes claims nothing that reached
the parent supports. `/eval` § *Mode C — behavioural lift with cost* documents
the two scripts, the metrics and the thresholds from `specs/read-shunt.md`.

### Supersession of PR #128

PR #128's three learning-store documents are ported into `tasks/solutions/`
under this tree's schema, its whole-task protocol, results, prompts and blind
grades are copied to `tasks/eval-results/read-shunt/prior-128/`, and the PR is
closed with a comment that links this spec and the brief and states why the
draft is superseded. Its branch and the `bulk-read-gate` worktree are left in
place.

## Inputs

- Session transcripts: `<root>/<project>/<session>.jsonl` and
  `<root>/<project>/<session>/subagents/agent-<id>.jsonl`, one JSON object per
  line, with `tool_use` blocks in `message.content`, `toolUseResult` beside each
  `tool_result`, `message.usage` on assistant lines, `isSidechain` and
  `agentId` markers.
- Thresholds `--bytes`, `--lines`; `--json`; `--paths`; `--root`.
- An eval results directory from `claude plugin eval --json` or from the
  Workflow-based `/eval` Mode B, plus the transcripts those runs left.
- A shunt decision log, when a later build adds the hook.

## Outputs

- The incidence report on stdout, Markdown or JSON, and the committed baseline
  under `tasks/eval-results/read-shunt/`.
- One grader row per run and paired per-task means per arm, Markdown or JSON.
- The eval suite directory and its rubric.
- A closed PR #128 with its evidence preserved in this tree.

## Edge Cases

- A transcript line that is not valid JSON is skipped and counted under
  `malformed`; a transcript with no tool use at all yields a zero row, not an
  error.
- A root with no transcripts, or a transcript whose Read block the parser cannot
  read, exits 2 with the path.
- Windows paths with backslashes and drive letters are compared after
  normalisation, so a re-read is detected whichever spelling the model used.
- A `Read` of an image, PDF or notebook has a different `toolUseResult` shape
  and is excluded, not misclassified as a zero-byte text read.
- A Bash command with `cat` inside a pipeline, a subshell or a heredoc is not a
  bare read; `sed -n '1,$p' f` is.
- Sub-agent reads never raise the parent's count, including reads a forked
  sub-agent makes with the parent's context.
- The grader reads a results directory with one arm as readily as two; with one
  arm it prints rows and no paired means.
- A scaffold that produces a fixture under the size its case promises fails the
  suite's own test, before any paid run.
- A real root repeats a tool use: an `api-request-blob` record copies the
  request's `tool_use` blocks (no `uuid`, no `isSidechain`) and a resumed
  session re-logs its assistant records verbatim. The parser reads only
  `assistant`, `user` and `system` records and absorbs a tool-use id — and
  its result — once, first record wins.
- The grader's sub-agent tokens are `0` for a run that dispatched no Agent and
  unknown (`-`) only for a dispatched Agent with neither counters nor a
  transcript, so the paired means average both columns over one denominator.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | The baseline shows the parent already windows its reads, so no gate is worth building | M | L | That is the go rule working; the brief's later tiers stay unbuilt and the harness remains for any future gate | 1 |
| R2 | `claude plugin eval`'s case schema or result layout differs from what the suite assumes | M | M | The suite is authored from `claude plugin eval init --bare` output; the grader works from transcripts, which both runners leave | 3 |
| R3 | The on-disk JSONL format is documented as internal and changes | M | M | Fixtures pin today's shape; the parser exits 2 on a block it cannot read | 1 |
| R4 | An eval-shaped name leaks into a candidate workspace and breaks blinding | L | H | Generated fixtures, project-shaped case names, a test that greps prompts and scaffolds for the blinding words | 3 |
| R5 | A full suite run costs more than expected | M | M | `--max-cost-usd` on every run; the smoke run is one control case with one run | 4 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Enforce a read gate with a hook or with CLAUDE.md prose? | hook | specs/read-shunt.md | Spotify found prose advisory and per-project |
| 2 | Default gate action when one is built | cap-and-annotate (`allow` + `updatedInput` + `additionalContext`) | specs/read-shunt.md | the only A/B flips negative on denies of small files; denies loop |
| 3 | Threshold | bytes ≥ 32768, lines ≥ 800 as fallback | specs/read-shunt.md | claude-mem's measured crossover; line count is a poor token proxy |
| 4 | Reader output | anchored excerpts and a symbol map, fixed schema | specs/read-shunt.md | prose summaries lose behavioural signal |
| 5 | Sub-agent reads | exempt from any gate, counted separately here | specs/read-shunt.md | the delegate must read whole files |
| 6 | Shell reads | gated when a gate exists; counted here, every file in a chain | specs/read-shunt.md | the replication bypass used `cat` and `sed -n` |
| 7 | Logging | every gate decision to a per-session JSONL; the parser module owns its reader (`ShuntDecision`, `read_shunt_log`) and the arranging step copies `tasks/.shunt/<session>.jsonl` beside the transcript | specs/read-shunt.md | the eval's ground truth, read in one place |
| 8 | Relation to PR #128 | supersede; port its learnings and evidence; close it with a comment; leave branch and worktree | user | 94 commits behind and conflicting, registration predates `hooks/hooks.json`, its post-read map measured net negative on a 14 KB fixture |
| 9 | First build | measurement from past transcripts plus the eval harness; no hook, no reader | user | the gate is built only if the baseline justifies it |
| 10 | Harness scope | Claude Code only | user | Codex is deny-only; Pi has no PreToolUse; both wait for the eval |
| 11 | Go rule | 10% of parent tool-result bytes in the median session, or 25% in a quarter of sessions | assumed | a gate that touches a tenth of the parent's input is the smallest effect the harness can show; the user reads the report and may move the bar |
| 12 | Where the measurement code lives | `.agents/skills/eval/scripts/`, one parser module and two CLIs | assumed | both tools measure transcripts, the eval skill's domain; one parser means one place to pin the format |
| 13 | Eval runner | `claude plugin eval`, suite under `evals/read-shunt/`; the Workflow-based `/eval` Mode B is the fallback | assumed | present on this install with ablation, runs, scaffold and a cost ceiling; the grader is runner-neutral |
| 14 | Gate `Grep` with large `-C` or `head_limit: 0`? | measured here as routing-around; the gate decision waits for the data | assumed | the brief left it open; counting costs nothing |
| 15 | `reader` persona and `/build` Scout dispatch | deferred to the gate build | assumed | nothing to dispatch to until a gate exists |
| 16 | In-process mod (brief Tier 3) | deferred; arm D only after a gate is promoted | assumed | PR #128's post-read replacement is the same shape and measured net negative on small files |

## Acceptance Criteria

- AC1: `read-incidence.py` over `tests/fixtures/transcripts/` prints a per-session and an aggregate table with reads, whole-file large reads, their bytes and share, shell reads, largest result, re-reads, final context size and sub-agent reads; `--json` prints the same as JSON.
- AC2: a ranged read is never counted as whole-file; a read with `numLines` below `totalLines` and no `limit` is counted as whole-file and flagged truncated; a non-text result is tallied under `excluded` and nowhere else; a read in a `subagents/` transcript or a sidechain line raises the sub-agent column only.
- AC3: `cat f`, `head f`, `tail f`, `sed -n '1,$p' f` and `cat a; cat b` are counted as shell reads with their result bytes; `cat f | grep x` and `cat f > g` are not.
- AC4: an empty root exits 2 naming it; a Read block the parser cannot read exits 2 naming the file and line; a malformed line is skipped and counted under `malformed`.
- AC5: the baseline over the real transcript root is committed as `tasks/eval-results/read-shunt/baseline-<date>.md` with the aggregate table and the go rule's verdict stated in one line.
- AC6: both CLIs import `read_transcript.py`; no second extraction of Read, Bash, Agent or usage blocks exists in either CLI.
- AC7: `grade-read-shunt.py` over a fixture results directory holding two arms prints one row per run with every metric in § Behavior and paired per-task means per arm; over one arm it prints rows and no means; a shunt log beside a transcript adds the hook-decision and repeated-deny columns.
- AC8: `evals/read-shunt/` holds eleven cases; each large case's scaffold generates a fixture over 32 KB from a fixed seed and each control's under; `tests/test-read-shunt-evals.sh` greps every prompt, case name and scaffold path for the blinding words and finds none, and runs every scaffold into a temp dir to check the promised sizes.
- AC9: `.agents/skills/eval/SKILL.md` carries § *Mode C — behavioural lift with cost* naming the two scripts, the metrics table and the thresholds, and its *What is measurable here* table gains the row; `tests/test-eval-skill.sh` pins the section and the scripts' presence.
- AC10: the three PR #128 learning documents exist under `tasks/solutions/` with this tree's frontmatter, `tasks/eval-results/read-shunt/prior-128/` holds its protocol, results, prompts and blind grades, and PR #128 is closed with a comment linking this spec and `specs/read-shunt.md`; `origin/worktree-bulk-read-gate` and the local worktree are untouched.
- AC11: `claude plugin eval` runs one control case with `--runs 1 --max-cost-usd 1` against this plugin, and `grade-read-shunt.py` parses the transcripts that run leaves into one row.

## Implementation Paths

- `.agents/skills/eval/scripts/read_transcript.py` — the one parser of the session JSONL shape: tool uses, results, usage, sidechain and sub-agent markers; exits 2 on drift.
- `.agents/skills/eval/scripts/read-incidence.py` — the baseline report over a transcript root.
- `.agents/skills/eval/scripts/grade-read-shunt.py` — per-run metrics and paired per-task means over an eval results directory.
- `.agents/skills/eval/SKILL.md` — Mode C documentation.
- `evals/read-shunt/**` — the eleven cases, their scaffold generators and the judge rubric.
- `tests/fixtures/transcripts/**` — hand-made transcripts pinning today's JSONL shape: whole-file large, ranged, truncated, non-text, sub-agent, bare and piped shell reads, malformed line.
- `tests/test-read-incidence.sh`, `tests/test-read-shunt-grader.sh`, `tests/test-read-shunt-evals.sh`, `tests/test-eval-skill.sh` — the contract above.
- `tasks/eval-results/read-shunt/**` — the committed baseline and PR #128's prior evidence.
- `tasks/solutions/patterns/cross-harness-hook-by-input-shape-not-tool-name.md`, `tasks/solutions/process/bash-and-sub-agents-read-the-shared-checkout.md`, `tasks/solutions/architecture/subagents-for-research.md` — the ported learnings.
- `specs/read-shunt.md` — the research brief, gate design and eval design this spec implements the first part of.

## Build Order

Sizing: 8 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: the fixture transcripts are many one-screen files that pin one format and belong with the parser that reads them; slice 5: eleven cases each need a prompt, a case file and a scaffold, and the suite is one unit of blinding.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Transcript parser | One parser reads a session JSONL's tool uses, results, usage, sidechain and sub-agent markers, classifies reads, and exits 2 on a block it cannot read. | `.agents/skills/eval/scripts/read_transcript.py`, `tests/fixtures/transcripts/**`, `tests/test-read-incidence.sh` | — | 2, 4 | `bash tests/test-read-incidence.sh` | ~10 planned files · 2 systems · 2 ACs |
| 2 | Incidence report | The baseline report over a transcript root, Markdown or JSON, with shell reads counted and paths hidden by default. | `.agents/skills/eval/scripts/read-incidence.py`, `tests/test-read-incidence.sh` | 1 | 1, 3 | `bash tests/test-read-incidence.sh` | 2 planned files · 2 systems · 2 ACs |
| 3 | Baseline report | The committed baseline over the real transcript root with the go rule's verdict in one line. | `tasks/eval-results/read-shunt/baseline-*.md` | 2 | 5 | `python3 .agents/skills/eval/scripts/read-incidence.py --root ~/.claude/projects` | 1 planned file · 1 system · 1 AC |
| 4 | Read-shunt grader | Per-run metrics and paired per-task means over an eval results directory, through the shared parser. | `.agents/skills/eval/scripts/grade-read-shunt.py`, `tests/fixtures/transcripts/**`, `tests/test-read-shunt-grader.sh` | 1, 2 | 6, 7 | `bash tests/test-read-shunt-grader.sh` | ~6 planned files · 2 systems · 2 ACs |
| 5 | Eval suite cases | Eleven cases with prompts, seeded scaffold generators, graders and the judge rubric, with a test that checks fixture sizes and blinding. | `evals/read-shunt/**`, `tests/test-read-shunt-evals.sh` | — | 8 | `bash tests/test-read-shunt-evals.sh` | ~25 planned files · 2 systems · 1 AC |
| 6 | Eval Mode C docs | `/eval` documents Mode C: the two scripts, the metrics table and the thresholds; the test pins the section and the scripts. | `.agents/skills/eval/SKILL.md`, `tests/test-eval-skill.sh` | 2, 4 | 9 | `bash tests/test-eval-skill.sh` | 2 files · 2 systems · 1 AC |
| 7 | Supersede PR 128 | PR #128's three learnings ported, its protocol, results, prompts and blind grades copied under prior-128, the PR closed with a comment; branch and worktree untouched. | `tasks/solutions/patterns/cross-harness-hook-by-input-shape-not-tool-name.md`, `tasks/solutions/process/bash-and-sub-agents-read-the-shared-checkout.md`, `tasks/solutions/architecture/subagents-for-research.md`, `tasks/eval-results/read-shunt/prior-128/**` | — | 10 | `gh pr view 128 --json state,comments` | ~8 planned files · 2 systems · 1 AC |
| 8 | Suite smoke run | One control case run through `claude plugin eval` under a cost ceiling, its transcripts graded into one row. | `tasks/eval-results/read-shunt/smoke-*.md` | 4, 5 | 11 | `claude plugin eval evals/read-shunt --case <control> --runs 1 --max-cost-usd 1 --json` | 1 planned file · 1 system · 1 AC |

Build prompt:

```
Invoke `/build` for `specs/read-shunt-baseline.md`.
Plan: `## Plan: read-shunt-baseline` in `tasks/todo.md`, 8 slices, ready set <1, 5, 7>.
Files: .agents/skills/eval/SKILL.md, .agents/skills/eval/scripts/read_transcript.py, .agents/skills/eval/scripts/read-incidence.py, .agents/skills/eval/scripts/grade-read-shunt.py, evals/read-shunt/**, tests/test-read-incidence.sh, tests/test-read-shunt-grader.sh, tests/test-read-shunt-evals.sh, tests/test-eval-skill.sh, tests/fixtures/transcripts/**, tasks/eval-results/read-shunt/**, tasks/solutions/patterns/cross-harness-hook-by-input-shape-not-tool-name.md, tasks/solutions/process/bash-and-sub-agents-read-the-shared-checkout.md, tasks/solutions/architecture/subagents-for-research.md, specs/read-shunt.md.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/read-shunt-baseline.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints:
- Claude Code only; no Codex or Pi adapter (D10).
- No hook, no reader persona, no mod in this build; the gate waits for the baseline's verdict (D9, D15, D16).
- Go rule: whole-file large reads at or above 10% of the parent's tool-result bytes in the median session, or 25% in a quarter of sessions (D11).
- Thresholds: bytes ≥ 32768, lines ≥ 800; sub-agent reads in their own column, never the parent's (D3, D5).
- Runner is `claude plugin eval`, the suite authored from `claude plugin eval init --bare`; the Workflow-based `/eval` Mode B is the fallback (D13).
- Count `Grep` with `-C` ≥ 50 or `head_limit: 0` on a large file as routing-around; gate nothing (D14).
- PR #128: close it with a comment linking both specs; port its learnings; leave `origin/worktree-bulk-read-gate` and the `bulk-read-gate` worktree untouched (D8).
- Every paid run carries `--max-cost-usd`; the smoke run is one control case, one run.
```
