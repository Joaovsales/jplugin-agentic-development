---
implementation_paths:
  - .agents/agents/bulk-reader.md
  - .claude/agents/bulk-reader.md
  - .claude/hooks/bulk-read-gate.py
  - .claude/settings.json
  - pi/extensions/bulk-read-gate.ts
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
  - tests/test-model-tiers.sh
  - tests/test-codex-install.sh
  - tests/test-agents.sh
  - tests/test-doc-conventions.sh
  - tasks/e2e-log.md
  - tasks/eval-results/bulk-read-context/**
---

# Spec: Bulk-Read Gate — mechanical scout-tier routing for large file reads

## Problem

Model routing decides which model a *dispatched agent* runs on. Nothing decides
what the main thread or a builder agent does when it opens a 2,000-line file: it
reads the whole file into the most expensive context in the session. Every rule
we have about bulk reading is prose (Large-Artifact Handoff covers logs only, and
only `/prd` names the scout tier for exploration). Spotify's Shunt plugin showed
the mechanical version of this rule cuts bulk-read tokens by about 90% on a Java
monorepo: a `PreToolUse` hook intercepts reads over a line threshold and routes
them to a cheap model that answers a question instead of returning the file.

This spec adds that gate to all three supported harnesses, with the cheap model
per harness: `haiku` on Claude Code, `gpt-5.6-luna` on Codex, and
`deepseek/deepseek-v4-flash` on Pi.

## Behavior

**The gate.** A pre-tool hook runs before every file read. When the read would
put more than `BULK_READ_MIN_LINES` lines (default 350) of one file into the
calling model's context, the call is denied with a reason that names the file,
its line count, the threshold, and the two allowed alternatives: dispatch
`bulk-reader` with a question, or read bounded ranges needed to understand and
edit the component. The gate never rewrites the call and never reads the file content itself; it only
counts lines.

**The bulk-reader.** A canonical persona, `.agents/agents/bulk-reader.md`, takes
a question plus one or more paths and returns a source map: facts with
`file:line` anchors, relevant symbol ranges, callers, dependencies, related tests,
coverage boundaries, and unresolved questions. It distinguishes observed facts
from unknowns; an unsearched path is not evidence that no dependency exists.
Summaries are navigation aids, not edit anchors or correctness evidence. The
reader never proposes edits or judges architecture or correctness. It reads files
in ranges no larger than the threshold, so the gate never blocks it. It is Scout tier on every harness.

**Routing.** The Scout tier gains the `bulk-reader` row. Claude Code pins
`model: haiku` in `.claude/agents/bulk-reader.md`. Codex pins
`model = "gpt-5.6-luna"` in the rendered TOML for Scout-tier agents
(`bulk-reader`, `context-document-optimizer`) and omits `model` for every other
agent, which is Ceiling semantics on Codex because an omitted setting inherits
the parent session. Pi pins `deepseek/deepseek-v4-flash` with thinking off in
`subagents.agentOverrides`. `PI_SETUP.md` § Sub-Agent Routing stays the single
source of concrete IDs and gains a Codex column.

**Skills.** `/plan`, `/build`, `/debug`, and `/sweep` each carry one line
pointing exploration and context-gathering at `bulk-reader` instead of direct
reads, referencing CLAUDE.md § Model Routing →
*Bulk-Read Handoff*. The `/build` delegation contract states that a builder
receives a bulk-reader answer as a source map, then inspects the source needed
to reason about the change, including files it will not edit. Before editing,
the implementing agent identifies the affected behavior, contracts, callers,
state and error paths, and tests, citing the inspected source and naming any
unresolved dependency. It expands reading or delegates factual exploration
until correctness-relevant unknowns are resolved; otherwise it reports the
blocker rather than edits on assumptions.

**Scope of understanding.** The threshold limits each tool read, not cumulative
context or the size of a component. Successive bounded reads may cover an entire
relevant component. Reading is organized by behavior and dependencies, not
arbitrary line windows; dispatch boundaries follow coherent responsibilities,
not file length. The hook enforces read size only. Source comprehension is a
workflow requirement evaluated through source inspection and resulting behavior,
not something the line-count hook can prove.

## Inputs

- Hook stdin (Claude Code and Codex, identical shape): JSON with `tool_name` and
  `tool_input`. Reads are `Read` (`file_path`, `offset`, `limit`), `Bash`
  (`command`), `PowerShell` (`command`), and Codex's shell tool (`command`).
- Pi: `tool_call` event with `toolName` in `read` (`path`, `offset`, `limit`)
  or `bash` (`command`).
- Environment: `BULK_READ_MIN_LINES` (positive integer, default 350),
  `BULK_READ_GATE=off` disables the gate entirely.

## Outputs

- Allow: exit 0, no stdout (silent success path).
- Deny: exit 0 with
  `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "<reason>"}}`
  on Claude Code and Codex; `{ block: true, reason }` on Pi. The reason names
  the file, its line count, the threshold, and both alternatives.
- Internal error (malformed stdin, unreadable path that exists): exit 1 with a
  one-line structured error on stderr. Loud, non-blocking, never a silent allow.

## Shell read detection

A shell command is a whole-file read when the **final pipe stage of any of its
command lists** is one of `cat <path>`, `type <path>`, `Get-Content <path>`
without `-TotalCount` or `-Tail`, `head -n N <path>`, or `sed -n 'A,Bp' <path>`,
**and** printing it would deliver more than the threshold's worth of lines from a
path that exists as a regular text file. Lines delivered, not range width, is
what counts: `sed -n '300,700p'` on a 400-line file delivers 101 lines and
`sed -n '100,$p'` delivers 301, so both are allowed; `head` with no `-n`
delivers 10. Anything piped into a further stage (`cat f | grep x`) is not a
whole-file read, but `|` is the only operator that redirects a stage's output:
`;`, `&&`, `||`, `&` and a newline start a new command list whose output still
lands in the tool result, so every list's final stage is gated, not only the
last one on the line (`cat big && echo ok`, `cat big; true`, `ls⏎cat big` all
deny). Redirections are neither separators nor paths: `2>&1` and `>&2` change
nothing, `> file`, `>> file` and `&> file` take stdout out of the tool result so
the stage is not a read (`cat big > out`, `cat >> big <<EOF` allow), `< path`
names the path being printed (`cat < big` denies), and `<<WORD` is an inline
heredoc. Arguments are split by a quote-aware tokenizer that keeps quotes on the
token, treats backslashes as literal on every host, and makes the separators
their own tokens; the Python hook and the Pi mirror carry the same grammar, so
one command yields one decision everywhere. Commands the pattern list does not
recognise are allowed.

Admission is by input shape, not tool name: `Read` is gated by `file_path`, and
any other tool whose input carries a string or argv `command` is treated as a
shell. Claude Code scopes the hook with a tool matcher; Codex registers it for
every tool and names its shell tool differently, so the shell contract lives in
the input. Pi gates by its two fixed tool names.

## Edge Cases

- File at exactly the threshold: allowed. Strictly greater denies.
- Ranged `Read` with `limit` above the threshold: denied. A range that large is
  a bulk read in disguise. `limit` exactly at the threshold is allowed, the same
  rule as a file exactly at the threshold: strictly greater denies, everywhere.
- Ranged `Read` with `limit` at or below the threshold: allowed regardless of
  file size. Lines past the end of the file are not delivered, so an `offset`
  near the end with a large `limit` is judged by what remains, not by `limit`.
- Path does not exist, is a directory, or is binary (NUL byte in the first 8 KB):
  allowed. The tool reports its own error; the gate has no opinion.
- Path exists but cannot be opened (permissions): exit 1 with stderr, not allow.
- `BULK_READ_MIN_LINES` unset or empty: default 350. Non-integer or zero: exit 1
  with stderr naming the bad value.
- Sub-agents: hooks fire inside sub-agents too. `bulk-reader`, `Explore`, and
  every other agent stay under the gate and must chunk reads; the persona says so.
- Windows paths with spaces or quotes in a shell command: the tokenizer keeps
  the quotes on the token and the gate strips them from the path; backslashes
  are literal, so `C:\\path\\file` survives on every host.
- Relative path after a `cd` in the same command (`cd src && cat big.py`): the
  gate has no shell state, so the path resolves against the hook's own cwd and
  is not found there; the read is allowed ungated. Absolute paths in compound
  commands are gated normally.
- Unexpanded shell variables and substitutions (`cat "$FILE"`, `cat $(latest)`):
  the gate does not run the shell, so the literal token is not a file and the
  read is allowed ungated. Same class of limit as the `cd` case above, and
  pinned by the same kind of test row so it stays deliberate.
- `tail -n N <path>` is not in the pattern list, so it is allowed; it is the one
  common line-bounded read the list leaves out.
- Python resolution on Claude Code: `.claude/settings.json` runs the
  `bulk-read-gate.sh` shim, which resolves `python3` then `python` the way
  `install-codex.sh` does. A hardcoded `python3` would exit non-zero on a
  python-only host, and a non-blocking hook error degrades to allow.
- Hook registered both project-level and user-level: the deny fires twice with
  the same reason. Harmless but doubles latency, so the gate registers
  **project-level only** in `.claude/settings.json`, following the Stop and
  PreCompact precedent; `install.sh` does not touch `~/.claude/settings.json`.
- Codex reads files mostly through its shell tool, so the shell patterns are
  the load-bearing half there.

## Acceptance Criteria

1. `bash tests/test-bulk-read-gate.sh` feeds the hook JSON for: whole-file
   `Read` of a 400-line fixture (deny), ranged `Read` with `limit` 50 (allow),
   ranged `Read` with `limit` 400 (deny), whole-file `Read` of a 100-line
   fixture (allow), missing path (allow), `cat big` (deny), `cat big | grep x`
   (allow), `sed -n 1,50p big` (allow), `sed -n 1,400p big` (deny),
   `head -n 400 big` (deny), `Get-Content big` (deny),
   `Get-Content big -TotalCount 20` (allow), `BULK_READ_GATE=off` with
   `cat big` (allow), `BULK_READ_MIN_LINES=500` with `cat big` (allow),
   malformed stdin (exit 1, stderr non-empty). Every deny reason contains
   `bulk-reader` and the line count.
2. `.claude/settings.json` registers `PreToolUse` for `Read`, `Bash`, and
   `PowerShell` running `.claude/hooks/bulk-read-gate.py` through the
   `bulk-read-gate.sh` interpreter shim; the test parses the JSON and asserts
   the matcher and command, and that the shim resolves `python3` then `python`.
3. `.agents/agents/bulk-reader.md` exists with colon-free single-line
   `description`, `name` matching the filename, no `model:` line; the
   `.claude/agents/` copy is identical plus `model: haiku`.
   `tests/test-model-tiers.sh` lists `bulk-reader:haiku` in `PINNED_AGENTS` and
   `tests/test-agents.sh` passes.
4. `scripts/render-codex.py` emits `model = "gpt-5.6-luna"` for `bulk-reader`
   and `context-document-optimizer` and no `model` key for any other agent,
   with the ID read by `install-codex.sh` from `PI_SETUP.md`'s tier table
   (Scout row, Codex column) rather than repeated in code;
   `bash scripts/install-codex.sh` in an isolated `CODEX_HOME` installs
   `coding-agent-workflow-bulk-read-gate.py` and registers it once under
   `PreToolUse` in `hooks.json`, idempotent on rerun.
   `tests/test-codex-install.sh` asserts all of it.
5. `pi/extensions/bulk-read-gate.ts` exists, subscribes to `tool_call`, mirrors
   the threshold, the two environment variables, the `read` range rule, and the
   shell pattern list, and returns `{ block: true, reason }`. `install.sh`
   copies it to `~/.pi/agent/extensions/` when `~/.pi/agent` exists.
   `PI_SETUP.md` adds `bulk-reader` to `agentOverrides` on
   `deepseek/deepseek-v4-flash` with thinking off. Static assertions only; a
   `TODO(shortcut):` in the test names the live Pi run as the upgrade path.
6. `CLAUDE.md` has a `bulk-reader` row in the agent table (`haiku`), a
   *Bulk-Read Handoff* subsection under Model Routing stating the threshold,
   the two alternatives, and the per-harness enforcement surface, and one
   sentence routing Codex Scout-tier IDs to `PI_SETUP.md`. No concrete provider
   ID appears in `CLAUDE.md`. `PI_SETUP.md` § Sub-Agent Routing has a Codex
   column with `gpt-5.6-luna` on Scout rows and *inherit* elsewhere. README's
   Codex Setup names the new hook in the `/hooks` review step.
7. `/plan`, `/build`, `/debug`, and `/sweep` each contain the phrase
   `Bulk-Read Handoff`; `/build`'s delegation contract says builders receive a
   bulk-reader answer as a source map and requires direct inspection of relevant
   implementations, contracts, callers, state/error paths, and tests before edits.
   Reads may expand to the entire relevant component in bounded calls; neither
   reading nor task ownership is restricted to edited lines or file length.
   `tests/test-skill-parity.sh` and `tests/test-doc-conventions.sh` are green.
8. One live measurement is recorded in `tasks/e2e-log.md`: the same question
   about one file over 350 lines in this repo, answered once by direct read and
   once through `bulk-reader`, with parent-context exposure and the wall-clock
   latency of the delegated path. Character-based token estimates are labelled
   estimates; they are not model usage or total cost. No percentage target.
9. `env -u TASK_REGISTRY_TRUSTED_CONFIG bash tests/run.sh` passes on Linux,
   with no regression in files this change did not touch. The environment unset
   isolates the known Doctor fixture leak tracked in #131; Windows failures and
   Windows CI are tracked separately in #129 and #130.
10. Repeated blinded coding evaluations use the same organic task and starting
    source per arm, with a rubric recorded before dispatch. Compare the former
    handoff, revised handoff, and a direct-source workflow where available.
    Grade implementation behavior, dependency inspection before edits, regressions,
    and unresolved assumptions from transcripts and independent checks. Record
    parent and scout token use separately, total usage, cache accounting, latency,
    model identity, repetitions, and every failed or incomplete run. Estimated
    context size must not be called measured model tokens. Promote a savings
    claim only if measured cost falls against the named baseline without losing
    required behavior or dependency coverage; otherwise report the result as
    inconclusive or a trade-off. Retrieval-only AC8 is not coding-quality evidence.
11. The gate tests demonstrate successive bounded reads spanning a component
    remain allowed; there is no cumulative read budget. Persona and mirrored
    skill tests pin source maps, coverage/unknown reporting, direct inspection,
    and responsibility-based delegation.

## Non-goals

- Delegating edits or reasoning to the cheap model. The article's two named
  limits become the persona's two prohibitions.
- Rewriting a denied call into a delegated call. The model chooses the
  alternative; the hook only closes the expensive door.
- A Sol/Terra ladder for Codex Planner and Builder tiers. Scout only.
- User-level registration of the hook on Claude Code.

## Implementation Paths

- `.agents/agents/bulk-reader.md` — canonical Scout-tier persona; `.claude/agents/bulk-reader.md` is the copy with the `haiku` pin
- `.claude/hooks/bulk-read-gate.py` — the gate, shared byte-identical by Claude Code and Codex
- `.claude/settings.json` — project-level `PreToolUse` registration
- `pi/extensions/bulk-read-gate.ts` — the Pi mirror of the gate
- `scripts/render-codex.py`, `scripts/install-codex.sh` — Scout-tier `model` in TOMLs; hook install and `hooks.json` merge
- `install.sh` — Pi extension copy step
- `CLAUDE.md`, `PI_SETUP.md`, `README.md` — routing table, Bulk-Read Handoff rule, Codex IDs, install docs
- `.agents/skills/{plan,build,debug,sweep}/SKILL.md` and `.claude/skills/` copies — one Bulk-Read Handoff line each
- `tests/test-bulk-read-gate.sh` — hook behaviour matrix; `tests/test-model-tiers.sh`, `tests/test-codex-install.sh`, `tests/test-agents.sh`, `tests/test-doc-conventions.sh` — routing and doc pins
- `tasks/e2e-log.md` — the recorded measurement

## Sources

- Spotify Engineering, "Portal by Spotify cut my Claude Code token usage by 90%" (2026-09)
- OpenAI Codex docs: hooks (`PreToolUse`, deny via `hookSpecificOutput.permissionDecision`), custom agent TOML `model` field, `gpt-5.6-luna`
- Pi docs: extensions, `pi.on("tool_call")` returning `{ block, reason }`
