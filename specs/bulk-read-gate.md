---
implementation_paths:
  - .agents/agents/bulk-reader.md
  - .claude/agents/bulk-reader.md
  - .claude/hooks/bulk-read-gate.py
  - .claude/hooks/bulk-read-gate.sh
  - .claude/settings.json
  - pi/extensions/bulk-read-gate.ts
  - scripts/context-read.py
  - scripts/install-codex.sh
  - scripts/render-codex.py
  - install.sh
  - CLAUDE.md
  - PI_SETUP.md
  - README.md
  - .agents/skills/plan/SKILL.md
  - .agents/skills/build/SKILL.md
  - .agents/skills/debug/SKILL.md
  - .agents/skills/sweep/SKILL.md
  - .claude/skills/plan/SKILL.md
  - .claude/skills/build/SKILL.md
  - .claude/skills/debug/SKILL.md
  - .claude/skills/sweep/SKILL.md
  - tests/test-bulk-read-gate.sh
  - tests/context_read_cases.py
  - tests/pi-result-cases.mjs
  - tests/test-pi-result.sh
  - tests/test-codex-install.sh
  - tests/test-install-sh.sh
  - tests/test-settings-json.sh
  - tests/test-model-tiers.sh
  - tests/test-agents.sh
  - tests/test-doc-conventions.sh
  - tasks/e2e-log.md
  - tasks/eval-results/bulk-read-context/**
  - tasks/eval-results/bulk-read-auto/**
---

# Spec: Automatic bulk-read routing

## Problem

PR #128's PreToolUse gate denies a large read and asks the agent to dispatch
`bulk-reader`. That second step is optional in practice: retained natural
routing runs made no reader calls, and requested handoffs did not show
consistent whole-task savings. A size denial alone cannot route a model call.

The router invokes a cheap reader automatically for eligible full-file reads
and substitutes a bounded source map before the main agent receives the tool
result. It retains the direct, ranged source access needed to verify facts and
make edits. The first rollout measures complete tasks; it makes no 90% savings
claim.

## Behavior

A synchronous post-tool adapter observes the actual result of a native file
read or a simple one-file shell read. If the result is successful, textual,
over the configured delivered-content threshold, and eligible, it calls the
shared `scripts/context-read.py` CLI itself. The main agent need not notice
a denial, invoke a skill, or retry the read. The original read has already run
locally; its large output is replaced before delivery to the main model.

The first release admits native `Read`/`read` calls and a simple literal
`cat <path>` or `Get-Content <path>` command. Ranged reads and other shell
commands keep their native result. Compound commands, variable or command
substitution, multiple paths, redirected output, and non-file tool results are
outside this automatic route. They are never rewritten or executed a second
time. The old broad shell grammar is reduced to this documented surface; it
is not a security or complete context-enforcement boundary.

The shared CLI receives one canonical request: source path, file content,
a source hash, an optional explicit question, and a bounded output budget.
For automatic hook calls without an explicit question, the cheap worker makes
a neutral source map: symbols and relevant ranges, observed connections,
coverage, and unknowns. The tool does not invent the agent's reason for
reading from a path or depend on a transcript's unstable format. An explicit
question can be supplied when the agent calls the CLI for a follow-up.

The cheap worker is a separate noninteractive process using the installed
harness's existing authentication and scout-tier model (Claude Code Haiku,
Codex Luna, Pi DeepSeek Flash, as resolved by the repository's tier config).
It receives the supplied file content via stdin, runs without tools or repo
instruction discovery where the host allows, and cannot recursively trigger
the bulk-read hook. No new paid provider or credential is required by default.
The subprocess boundary uses an argv array, not shell evaluation.

A successful map names the inspected path, its content hash, line ranges for
each claim, coverage boundaries, unresolved questions, and whether the answer
is incomplete. The CLI enforces a model-facing output cap and validates the
response schema and cited ranges. It cannot prove the claims are true. The
main agent treats the map as navigation and reads exact relevant ranges,
callers, dependencies, and tests before edits or correctness conclusions.
Direct ranged reads are always available.

When the worker is missing, times out, is refused by its provider, returns an
empty/invalid/oversized answer, or cannot safely process the input, the adapter
passes through the original result and records a structured, local fallback
event. It never substitutes an empty summary. The hook's success path is
silent apart from its required protocol output. Telemetry contains no source
content, user prompt, or credential.

The existing `BULK_READ_GATE=off` bypass remains accepted during migration.
Configuration can change the delivered-content threshold, worker timeout,
input/output ceilings, and telemetry location. Invalid settings are reported
clearly and result in the original tool output. Jev, semantic task
classification, an MCP server, and a default deny policy are outside this
first release.

## Inputs

- Claude Code and Codex PostToolUse event: tool name, input, result, cwd,
  and session/call identifier where available.
- Pi `tool_result` event: tool name, input, result content, and call id.
- Explicit CLI: question and one or more readable paths for a follow-up.
- Local worker configuration and existing scout-tier model resolution.

## Outputs

- Eligible successful read: a bounded source map replaces the model-facing
  tool result through each harness's supported hook output contract.
- Ineligible read: the original tool result is unchanged.
- Routing failure: the original tool result is unchanged; a local metadata-only
  fallback record names the failure category.
- The CLI emits a validated machine-readable map or exits nonzero with an
  actionable error. No partial answer is presented as complete.

## Edge Cases

- A read at the threshold passes through; a result above it is eligible.
  Tests cover both line count and a long-line/byte-heavy file so line count
  cannot hide an unusually large result.
- A ranged read stays direct even when its source file is large. A failed,
  missing, binary, directory, or permission-denied read preserves its
  original result.
- A file changed during routing invalidates the map's hash and causes
  pass-through, preventing stale citations from being presented as current.
- A worker child and a disabled router pass through without recursively
  starting another worker.
- Concurrent calls keep results and telemetry tied to their own tool-call
  IDs. A large read and a small sibling cannot swap outputs.
- A provider response that lacks usage counters records usage as unknown,
  never zero. Logs keep no raw file content or prompt.

## Acceptance Criteria

1. One eligible large native read automatically invokes a stub worker exactly
   once and delivers its bounded map to the main model without an agent retry;
   an eligible simple shell read behaves the same way on each harness.
2. Small, ranged, unsupported, failed, and disabled reads preserve their
   original tool result and launch no worker. Threshold boundary and
   long-line cases are covered.
3. Missing worker, timeout, provider failure, invalid schema, bad citation,
   oversized input/output, and changed source each preserve the original
   result and produce a metadata-only fallback event.
4. Claude Code, Codex, and Pi adapters use their actual installed hook
   contracts; one live smoke run per harness verifies result replacement and
   one verifies fallback. Installation remains idempotent.
5. Worker invocations use the existing scout-tier models and credentials,
   disable tools/recursion, and do not add a new provider dependency.
6. The main-agent guidance preserves the PR #128 source-map contract and
   explicitly requires direct inspection of cited source before edits or
   correctness claims.
7. A paired evaluation records parent and worker input/output/cache tokens
   when available, estimated or reported cost, latency, retries, corrections,
   and answer quality. It includes broad-reading and subtle-bug cases,
   distinguishes main-context reduction from whole-task savings, and retains
   failures and unknown usage.

## Implementation Paths

- `.claude/hooks/bulk-read-gate.py`, `.claude/hooks/bulk-read-gate.sh`,
  `.claude/settings.json` — reuse the installed Python hook and shim,
  changing their event/output contract to automatic post-read replacement.
- `pi/extensions/bulk-read-gate.ts` — Pi result adapter, invoking the same
  CLI and replacing model-facing content.
- `scripts/context-read.py` — provider-neutral request validation, worker
  process, source-map validation, output bounds, and telemetry.
- `scripts/install-codex.sh`, `scripts/render-codex.py`, `install.sh` —
  keep model-tier and installer wiring; update hook registration.
- `.agents/agents/bulk-reader.md`, `.claude/agents/bulk-reader.md`,
  workflow guidance, `CLAUDE.md`, `PI_SETUP.md`, `README.md` — preserve
  the source-verification contract and explain automatic versus explicit reads.
- `tests/test-bulk-read-gate.sh` and installer tests — exercise routing,
  pass-through, failures, and idempotent cross-harness registration.
- `tasks/e2e-log.md`, `tasks/eval-results/bulk-read-context/**` — retain
  live walkthrough and whole-task evidence.
