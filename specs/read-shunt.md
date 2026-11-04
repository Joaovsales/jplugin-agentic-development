# Read Shunt — research brief, design and eval plan

**Date**: 2026-10-20 · **Status**: research brief (pre-spec; `/plan` turns § Design into
Behavior / Acceptance Criteria) · **Origin**: "Spotify denies smart models bulk reads —
can jplugin do that with hooks or a mod, routing reads to Haiku, without blocking the
main agent or losing its context?"

Four parallel research agents covered Spotify's own publications, hook-based read
guards in the wild, context-engineering guidance, and eval methodology. Every claim
below carries its source in § Sources; anything unverified is marked as such.

## Problem

File reads dominate a coding agent's bill and its context. Two independent
measurements put read-type tool output at 68–76% of total tokens (SWE-Pruner on
SWE-bench Verified with Sonnet 4.5; observation masking study, 84% of SWE-agent
context). Every token the parent reads also degrades its attention: accuracy falls
with input length even on trivial tasks (Chroma's context-rot study, 18 models).
jplugin today enforces nothing here: `hooks/hooks.json` registers only SessionStart,
PreCompact and Stop, and Scout-tier delegation exists only as prose in `/how`,
`/why`, `/plan` and `/build`.

## What the research established

1. **Spotify's mechanism is real and specific.** The "shunt" plugin in
   `spotify/portal-ai-plugins` (Sep 2026) uses two PreToolUse hooks: `Read` is denied
   for whole-file reads over 350 lines (`offset`/`limit` reads pass) and `Bash` is
   denied for bare `cat`/`head`/`tail`/`less`/`more` on large files (pipes and
   redirects pass). The deny message names a `bulk-reader` skill that ships the file
   plus a question to a cheap worker (Gemini 2.5 Flash via Portal) and returns cited
   bullets. A CLAUDE.md routing block was tried first and "sort of worked"; hooks
   replaced it because prose was advisory and per-project. [S1][S2]
2. **The 90% figure is per bulk read, not per bill.** Spotify measured
   33,684→5,737 tokens on a 4,014-line file and a mean of 90% across bulk reads on one
   162K-line Java monorepo. Total cost, latency per task and task success are
   unpublished. Latency was 10–30 s per delegation. [S1]
3. **Two independent replications saved nothing.** With Opus as the parent, the hook
   never fired: the model used `grep` and `sed -n` windows under the threshold
   (36.7K vs 35.5K tokens, noise). Delegated test writing cost +23% to +34% because
   the parent re-read and rewrote the draft. A second replication logged 12 blocked
   reads and zero delegations in a day, then switched the guard off. [S3][S4]
4. **The only published A/B of a read gate flips sign at small files.** claude-mem's
   File Read Gate: −38% (Sonnet) / −30% (Opus) mean cost on a 49 KB file, but
   **+20% on Opus for a 19 KB file**, because every denied read re-sends the whole
   context and Opus read ~70% of the small file anyway. They raised the floor from
   1.5 KB to 32 KB. A third project, context-guard, was archived after seeing *more*
   input tokens. [S5][S6]
5. **Bare denies cause retry loops.** The model re-issues the identical denied call
   5–10 times (claude-code #80319); auto-mode flags the remediated retry as a bypass
   (#51676); when two hooks deny only one reason reaches the model (#80919). The fix
   people converged on is to return the exact corrected call. [S7]
6. **Hooks can rewrite, not just deny.** Claude Code PreToolUse supports
   `permissionDecision: allow` + `updatedInput` (replaces the whole input, so a bare
   Read becomes `{file_path, offset, limit}`) + `additionalContext` (a system reminder
   the model reads beside the result). `agent_id`/`agent_type` are present when the
   call comes from a sub-agent. Timed-out hooks fail open; async hooks cannot block.
   Codex CLI supports deny only. [S8]
7. **A Claude Code mod can answer the read itself.** A mod's `tool.call` hook on
   `Read` sees `file_path`, `offset`, `limit` and `agentId`; it may `deny`, call
   `next({...e, limit})`, or return its own `{ result, context }` which the engine
   records as the tool's result. `$.model.complete({ model: "haiku", prompt })` runs a
   tool-less completion through the session's credentials; `$.fs.read` caps at 4 MiB;
   `$.agent.spawn` starts a sub-agent. (Read from this build's engine types, see
   `mods/factory-board` for the pattern.)
8. **Prose summaries lose the signal; excerpts keep it.** Natural-language summaries
   answered 4/45 behavioural questions vs 27/45 from source, and a frontier
   summariser did no better than a 3B one; compressed code with line anchors matched
   whole files at a third of the tokens. Compactors drop file paths and error strings
   as "low-entropy". Goal-hinted line-level pruning cut read tokens 23–38% with the
   resolve rate flat (70.6→70.2%). [S9][S10][S11]
9. **Delegation has a floor.** Anthropic's Opus 5 guidance: delegation "multiplies
   cost and time when applied to small tasks"; Vercel: if the parent can do it in
   three steps, delegation isn't paying for itself. Sub-agents cost tens of thousands
   of tokens to return 1–2K. [S12][S13][S14]
10. **Explore is no longer Haiku by default.** Current sub-agent docs say the built-in
    `Explore` runs on the main conversation's model unless a project defines its own
    `Explore` agent with `model: haiku`. jplugin's skills pass `model: "haiku"` per
    call, which still works; a project-level `Explore` persona would make it the
    default. [S15]
11. **Agent evals need pairs and repetitions.** Run-to-run SD of pass@1 on SWE-bench
    Verified is 0.7–1.8 pp and persists at temperature 0; detecting a 2 pp effect
    needs ~9 runs, 5 pp needs 1–3. Pairwise judges flip ~1/3 of verdicts when order
    is swapped. Claude models verbalise eval awareness in ~13% of transcripts and
    behave better when aware. [S16][S17][S18]

## Folklore and contested points

- "Spotify cut Claude Code costs 90%" — overstated; see finding 2.
- "Honk uses cheaper models" — never stated; Honk's context discipline is tool
  allowlists and hidden verifiers that return regex-extracted errors. [S19]
- "Spotify uses Haiku" — they used Gemini Flash through Portal.
- Whether summaries beat raw code is contested between Anthropic's practice posts and
  the measurement papers; the reconciliation is *excerpts with line numbers, not prose*.
- Whether 1M-token windows make this moot: Chroma and Anthropic say the attention
  budget, not the window, is the constraint.

## Design

The verified evidence points away from Spotify's exact shape (deny at 350 lines) and
toward four properties: a byte threshold near 32 KB, cap-and-annotate instead of
deny, a reader that returns anchored excerpts, and sub-agents exempt from the gate.
The design is layered so each layer is an eval arm.

### Tier 0 — measure first (no code)

Before building, log what the parent actually reads in real jplugin sessions: a
PostToolUse hook on `Read`/`Bash` appending `{session_id, agent_id, tool, file,
bytes, lines, offset, limit}` to `tasks/.shunt/<session_id>.jsonl` (gitignored).
One week of sessions answers whether whole-file reads above 32 KB happen often
enough to matter. Finding 3 says a parent on a strong model may already window its
reads, in which case the shunt saves nothing and the project stops here.

### Tier 1 — `read-shunt.sh`, a PreToolUse hook (portable)

Registered in `hooks/hooks.json` with matcher `Read|Bash`. Synchronous, <100 ms,
shell + `wc -c`, no LLM call, fails open on any error.

| Call | Condition | Action |
|------|-----------|--------|
| `Read` without `offset`/`limit` | file ≥ `SHUNT_BYTES` (default 32768) or ≥ `SHUNT_LINES` (default 800) | **cap-and-annotate**: `allow` + `updatedInput {file_path, offset: 1, limit: SHUNT_HEAD}` + `additionalContext` naming total lines/bytes, the loaded range, and the exact delegation call |
| `Read` of `*.lock`, `*.min.*`, `dist/**`, `node_modules/**`, `*.map` | any size | `deny` with the reason |
| `Bash` bare `cat`/`head -c`/`tail`/`less`/`more`/`sed -n '1,$p'` on a file over the threshold, not piped or redirected | every file in a chained command checked | `deny` with the corrected call (`sed -n 'a,bp'`, Grep, or the delegation call) |
| any call with `agent_id` present | — | pass through untouched (sub-agents read whole files) |
| `SHUNT_MODE=deny` | — | Spotify-style deny on the first row, kept only as an eval arm |

The `additionalContext` text is factual, not imperative (the docs warn imperatives
trip injection defences), and names the delegation verbatim, for example:
`Agent(subagent_type: "reader", model: "haiku", prompt: "<question> in <path>")`.
Every decision is appended to the Tier 0 log, which is the eval's ground truth.

Cap-and-annotate is chosen over deny because it costs no extra turn, cannot loop
(finding 5), and keeps Edit's read-before-edit precondition satisfied (finding 4's
"editing never deadlocks").

### Tier 2 — the `reader` persona and its return schema

A Scout-tier agent in `.agents/agents/reader.md` (copied to `.claude/agents/`), the
read-only sibling of `/how`'s explorer prompt. Its brief must carry a **question**
and the paths; its answer is a fixed schema, each section filled or explicitly
`none`:

```
### Answer            one or two sentences
### Excerpts          verbatim lines with file:line anchors, nothing paraphrased
### Symbol map        name → line range, for the file(s) read
### Not found         what the question asked for that is not in the files
### Open questions
```

Excerpts over prose is finding 8; the explicit-empty sections are Factory's fix for
compactors dropping paths. The full read stays restorable: the parent can re-open an
exact `offset`/`limit` window instead of re-reading the file (Manus's "restorable
compression", this repo's *Large-Artifact Handoff* rule).

Non-delegation list, from Spotify's and the field reports: editing, debugging a
specific failure, architecture decisions, security-critical code, and anything under
the threshold.

### Tier 3 — `mods/read-shunt`, in-process extraction (Claude Code only)

A mod `tool.call` hook on `Read` in the main loop (`e.agentId` absent) for files over
the threshold. It reads the file with `$.fs.read`, runs
`$.model.complete({ model: "haiku", prompt })` with the Tier 2 schema and a question,
and returns `{ result, context }` as the tool result. The parent never spends a turn
and never sees the file; the log records bytes in, tokens out, and Haiku's cost.

The open problem is the question: a `Read` carries no intent. Two options to
evaluate: (a) the hook registers `mcp__read-shunt__ask_file({file_path, question})`
and the capped `Read` points the model at it, so every delegated read is
question-directed by construction; (b) for a bare over-threshold `Read` the hook
returns a Haiku-generated **outline** (symbol map with line ranges, no bodies) and
the pointer, which is cheap, intent-free and always useful. Ship (b) as the default
reply and (a) as the follow-up tool.

### Configuration

`SHUNT_BYTES`, `SHUNT_LINES`, `SHUNT_HEAD` (default 150), `SHUNT_MODE`
(`annotate|deny|off`), `SKIP_READ_SHUNT=1` kill switch, mirroring `pre-compact.sh`.
Declared below the AGENTS.md end marker as `Read shunt: <mode> <bytes>` so a project
can turn it off.

### Decisions settled by the research

| Decision | Choice | Why |
|----------|--------|-----|
| Enforcement | hook, not CLAUDE.md prose | finding 1 |
| Default action | cap-and-annotate | findings 4, 5 |
| Threshold | bytes ≥ 32 KB, lines as fallback | finding 4; line count ≠ tokens (20–70% formatting overhead) |
| Reader output | anchored excerpts + symbol map, fixed schema | finding 8 |
| Sub-agents | exempt | the delegate must read whole files |
| Shell reads | gated, every file in a chain | finding 1, replication bypass in [S3] |
| Logging | every decision to a per-session JSONL | the eval's ground truth |

### Open questions for `/grilling`

- Does Tier 3 (mod) earn its complexity over Tier 1 + Tier 2, or is the in-process
  Haiku call just a faster version of the same thing? Only the eval can say.
- Should `Grep` with `-C` ≥ 50 or `head_limit: 0` on a large file be gated? Spotify
  did not; the eval design agent recommends it.
- Does Pi need parity (its `subagents` extension has no PreToolUse equivalent), or is
  this Claude Code and Codex (deny-only) first?
- Should `/build`'s Scout dispatch adopt the `reader` persona, or stay on `Explore`
  with `model: haiku`?

## Eval design

**Question under test**: does the read shunt reduce the parent's context and total
cost on tasks that force a large read, without hurting task outcome, and does the
parent comply rather than route around it?

The existing `/eval` skill supplies the blinding rules, Mode B (variant lift) and
transcript-over-self-report grading. It lacks every metric below, so the eval adds
one grader script and a fixture repository.

### Arms

| Arm | Harness | What it isolates |
|-----|---------|------------------|
| A | control, no shunt | baseline incidence of bulk reads and routing |
| B | Tier 1 annotate + Tier 2 reader | the recommended design |
| C | Tier 1 `SHUNT_MODE=deny` + Tier 2 | Spotify's shape; expected to loop or route around |
| D (later) | Tier 3 mod | whether in-process extraction beats delegation |

Same model, same prompts, same fixtures. Arms differ only in the plugin build the
candidate's `--plugin-dir` carries, so a candidate cannot tell which arm it is in.

### Task set

Eight organic tasks that force a large read, plus three controls where the gate must
never fire. Each has a hidden test and a reference patch.

1. A three-line bug in a 4–8K-line generated client (OpenAPI/protobuf).
2. Diagnose a failing CI run from a 20–60K-line log with one stack trace near the end.
3. Add a field to a schema whose fixtures JSON is over 256 KB (Read's own cap).
4. Refactor one function in a 3K-line module with scattered callers.
5. Explain why a test in a 2K-line suite is flaky, from the suite alone.
6. Port a config loader whose reference implementation is a 1,500-line file.
7. Find every caller of a renamed symbol across 40 files (breadth, not depth).
8. Summarise a 900-line CHANGELOG into release notes (prose, where excerpts matter less).
9–11. Controls: fix a typo in a 60-line file; add a test to a 200-line module; answer
   a question about a 25 KB file just under the threshold.

Prompts are written as a user would type them, with the no-push clause from
`references/probe-recipe.md`, and never mention size, context, sub-agents or cost.

### The fixture problem

`/eval` worktrees are cut from the remote default branch, so large fixtures cannot be
pasted into the prompt the way a failing test can. Two honest routes: a dedicated
fixture repository (`origin` pointed at a throwaway bare clone, large files generated
by a script so nothing eval-shaped is committed), or `claude plugin eval`'s own
scaffold, which hides case directories from the candidate and supports `--runs`,
with/without ablation, a `tool_used` grader (`min: 0, max: 0` for parent bulk reads),
`regex` over the trace and an `llm` judge with 2-of-3 votes. Prefer `claude plugin
eval` if its ablation can carry a hook; fall back to the fixture repository.

### Runs

N = 5 per task per arm minimum (Terminal-Bench's floor), 10 preferred. Paired design:
task × seed slot across arms; report paired per-task means with bootstrap CIs
(B = 10,000), never raw counts. With 5 runs only effects of roughly 5 pp or more on
outcome are detectable; compliance and cost deltas are expected to be far larger, and
the outcome criterion is therefore "no regression we can see", stated as such.

### Metrics and where each is recorded

Use `claude -p --output-format stream-json --verbose --forward-subagent-text`; the
on-disk JSONL is documented as internal. Enable OTel for per-call sizes
(`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOG_TOOL_DETAILS=1`).

| Metric | Source |
|--------|--------|
| Parent bulk reads (whole-file `Read` over threshold) | `assistant` frames with `parent_tool_use_id: null`, `tool_use.name == Read`, no `limit`; file size from the shunt log |
| Routing around (`cat`/`sed -n`/`head`/`tail`/`python -c open()` on a large file; `Grep` with huge `-C`) | same frames, `tool_use.name in {Bash, PowerShell, Grep}`, regex over `input` |
| Hook decisions and retries (same `tool_use.input` denied twice) | `tasks/.shunt/<session>.jsonl`; OTel `claude_code.tool_decision{source: hook}`; `permission_denials[]` on the `result` frame |
| Bytes into parent context per call; largest single result | OTel `tool_result_size_bytes` filtered to the parent |
| Tokens by model and cost | `result.modelUsage[model]` (includes sub-agents) vs `result.usage` (parent only); their difference is the sub-agent share |
| Parent end-context | last parent `assistant.message.usage`: input + cache_read + cache_creation, deduped by `message.id` |
| Compactions | `system/compact_boundary.compact_metadata{pre_tokens, post_tokens}` |
| Sub-agent spend | `system/task_started`, `task_progress.usage{total_tokens, tool_uses}` |
| Latency | `result.duration_ms`, `num_turns` |
| Re-read rate (information loss) | parent `Read`/`cat` of a path that appeared in an earlier `Agent` prompt or reader result |
| Outcome | hidden test pass@1 and pass^k over the runs |

### Grader to build

`.agents/skills/eval/scripts/grade-read-shunt.py <run-dir>`: parses one stream-json
file plus its shunt log per candidate and emits one row per run with every metric
above, then per-task paired means per arm. Sibling of `grade-skill-loads.sh`, same
exit discipline: exit 2 on an unparseable transcript, never a silent zero.

### Judge

One pass, both variants interleaved under sanitised labels, judged on a stronger tier
than the candidates, **both orders** with a win counted only when the orders agree.
Rubric, written before any run: patch correctness against the reference; diff
minimality; whether the parent re-derived what a reader had already returned;
whether the final answer makes claims unsupported by what reached the parent.
Calibrate on 20 hand-labelled transcripts; target κ ≥ 0.6 with the human grades.

### Success thresholds (arm B vs arm A)

- Compliance: ≥ 95% of runs with zero parent bulk reads and ≤ 1 routing attempt; any
  run with ≥ 3 identical denied calls is a failure.
- Outcome: paired pass-rate CI not excluding zero, and no task whose pass rate drops
  by more than one run in five.
- Parent end-context: −30% or better.
- Total cost (`modelUsage` sum): not worse than control. The observation-masking
  result suggests −50% is plausible when reads are 76% of tokens; +20% on small
  files is the documented failure mode, hence the controls.
- Re-read rate: ≤ 10% of reader-returned paths.
- Latency: +25% tolerated.
- Controls: zero gate activations. One activation is a threshold defect, not noise.

### Pitfalls to design around

- **Observer effect**: temp `HOME`, no eval-shaped names anywhere the candidate can
  look, and grep every transcript for "eval/test/benchmark" self-talk as an exclusion
  flag. The Iron Law of `/eval` holds.
- **Cached-suite contamination**: `cached-suite.sh` reuses a green run on the same
  tree; every candidate runs in a fresh worktree with the cache disabled.
- **Cost accounting**: `result.usage` excludes sub-agents; `total_cost_usd` is a
  client-side estimate and was ~10× too high for Haiku in an April 2026 bug. Report
  tokens by model beside dollars.
- **Prompt-cache splits** differ between arms; report `cache_read` and `input`
  separately.
- **Version pinning**: record `claudeVersion` from the `system/init` frame with every
  result; the hook contract and Explore's default model both changed in 2026.
- **Eval cost**: 11 tasks × 5 runs × 3 arms ≈ 165 runs plus judges, roughly $100–500
  per iteration. Budget with `--max-budget-usd`; after the first full sweep keep only
  tasks whose single-run result correlates with the full set.

### Go / no-go

Build Tier 1 + Tier 2 only if Tier 0 shows the parent doing whole-file reads over
32 KB in a meaningful share of sessions. Promote arm B only if it meets every
threshold above on the paired comparison. Arm C is kept to confirm, with this repo's
own data, that deny loops or is routed around; if it does not, the simpler shape wins.
Arm D is attempted only after B is promoted.

## Build order sketch (for `/slice`)

1. Tier 0 logging hook + gitignore + one week of real-session data (manual gate).
2. `read-shunt.sh` with `tests/test-read-shunt.sh` (cap, path deny, Bash chain, agent
   exemption, fail-open, kill switch) and the `hooks.json` registration, pinned by
   `tests/test-hooks-json.sh`.
3. `reader` persona in `.agents/agents/` + `.claude/agents/`, routed in
   `model-routing.md`; `/how` and `/build` Scout dispatch reference it.
4. Fixture generator + `grade-read-shunt.py` + rubric; `/eval` SKILL.md gains a Mode C
   row ("behavioural lift with cost") and the metrics table.
5. The eval run itself: arms A, B, C; report under `tasks/`; promote or revert.
6. (conditional) `mods/read-shunt` and arm D.

## Sources

- [S1] Spotify Engineering, "Portal by Spotify cut my Claude Code token usage by 90%",
  D. Mazmanov, 2026-09-03. https://engineering.atspotify.com/2026/9/portal-by-spotify-cut-my-claude-code-token-usage-by-90
- [S2] `spotify/portal-ai-plugins`, `plugins/shunt/README.md`.
  https://github.com/spotify/portal-ai-plugins/blob/main/plugins/shunt/README.md
- [S3] XDA Developers, J. Rice-Jones, 2026-10-03.
  https://www.xda-developers.com/claudes-token-burn-problem-borrowed-spotifys-playbook/
- [S4] A. Baker, DIY replication, 2026-09-17. https://andrewbaker.ninja/?p=11520
- [S5] `thedotmack/claude-mem` PR #4553, File Read Gate A/B.
- [S6] `ictechgy/context-guard` (archived 2026-09).
- [S7] `anthropics/claude-code` issues #80319, #51676, #80919, #20223, #22699, #49048.
- [S8] Claude Code hooks reference. https://code.claude.com/docs/en/hooks
- [S9] B. Sam-Bodden, "What Context Does a Coding Agent Actually Need to Act?",
  arXiv 2607.09691, 2026-06.
- [S10] Factory Research, "Evaluating compression", 2025-12-16.
  https://factory.com/news/evaluating-compression
- [S11] SWE-Pruner, arXiv 2601.16746, 2026-01; "The Complexity Trap", Lindenbauer et
  al., arXiv 2508.21433, NeurIPS 2025.
- [S12] Anthropic, Prompting Claude Opus 5 § Controlling subagent spawning.
- [S13] Vercel Academy, "Why delegate", updated 2026-05-20.
- [S14] Anthropic, "Effective context engineering for AI agents", 2025-09-29.
  https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- [S15] Claude Code sub-agents docs. https://code.claude.com/docs/en/sub-agents
- [S16] Bjarnason, Silva, Monperrus, "On Randomness in Agentic Evals", arXiv
  2602.07150, ICLR 2026.
- [S17] Shi et al., "Judging the Judges", IJCNLP 2025; MT-Bench, arXiv 2306.05685.
- [S18] Claude Sonnet 4.5 system card, evaluation awareness, 2025-09-30.
- [S19] Spotify Engineering, Honk parts 1–4 (2025-11 to 2026-04), esp. Part 3
  "Feedback loops". https://engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3
- [S20] Anthropic, "Demystifying evals for AI agents", 2026-01-09; Claude Code plugin
  evals. https://code.claude.com/docs/en/plugin-evals
- [S21] Chroma, "Context Rot", 2025-07-14. https://www.trychroma.com/research/context-rot
- [S22] Cognition, "Don't build multi-agents", 2025-06-12; Manus, "Context
  engineering lessons", 2025-07-18; TraceLab, arXiv 2606.30560, 2026-06.
