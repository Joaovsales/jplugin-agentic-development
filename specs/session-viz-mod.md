---
implementation_paths:
  - mods/session-viz/**
---

# Spec: session-viz

> Origin: conversation (2026-10-19) · Review status: **planned**
> Prior art: `mods/factory-board/` (#289) — the sub-agent Kanban this mod absorbs (D5).

## Summary

A Claude Code mod (a plugin of function hooks) that shows how a jplugin session is
going, in one docked pane: the workflow phase and the running skill, slice progress
read from `tasks/todo.md`, the sub-agent tree with each agent's brief and footprint,
and the quality gates — findings, the quality receipt, ambiguities, surface reports
and dispatch checks. It observes and never intervenes. It is a standalone mod at
`mods/session-viz/`, beside `mods/factory-board/`, whose Kanban it supersedes.

## Behavior

The pane `session-viz`, titled `Session`, opens at `session.start` where the surface
docks panes and on `/session-viz` (focused). Its body is one column of stacked
sections, in this order:

1. **Phase** — the phase (`PLAN`, `BUILD`, `GATE`, `WRAP-UP`, or `idle`), the skill
   running now, and the `/go` route (`lane`, `chain`) when one was printed.
2. **Plan** — the active `## Plan:` block of `tasks/todo.md`: feature, spec, `slice
   k/N` closed (a slice is closed once its `> Handover:` blockquote exists), rows done
   over rows total, and one line per slice (`n/N name · rows d/t · ✓ handover`).
3. **Agents** — every sub-agent of the session as a tree indented by parent, in spawn
   order, one Button row each: a glyph (`◐` running, `✓` answered, `✗` failed or
   killed, `⚑` an open `AskUserQuestion` or `[AMBIGUITY]` lines in its answer), the
   factory stage (`plan`, `build`, `review` from the agent type's name, as
   factory-board derives it), the type, the description, and its status or duration.
4. **Gates** — the quality receipt (`verdict fp8 · tests exit N · unresolved N`, or
   `no receipt yet`), the last `Verdict:` line seen, finding counts by severity,
   every `[AMBIGUITY]` line with its agent, every `[SURFACE] +path` report, and the
   dispatch issues (off-tier and missing-contract-item) the toasts announced.
5. **Drill-down** — the pressed agent's brief and footprint: description, type,
   requested and resolved model, parent model and parent agent, the spawn prompt
   (first 2000 characters, then `… +n chars`), files read, files edited, patterns
   grepped, commands run, tool-call count, step count, message count, outcome and
   duration, `[AMBIGUITY]` and `[SURFACE]` lines, finding counts. Pressing the row
   again closes it. Pressing also scrolls the transcript to the Agent tool row that
   spawned the agent. No transcript is read or shown.

From 120 body columns the drill-down is a right column beside sections 1–4; below
that it is the last section. Every section shows one dim line when it has nothing.

The status line reads `viz · <PHASE> · <skill> · slice k/N · ctx NN% · $X.XX ·
agents R/T` with every unknown field left out.

Three toasts, and no others:

- `session-viz: quality gate STOP (<fp8>)` — a receipt whose verdict is `STOP`, once
  per fingerprint, or a main-loop answer line `Receipt: STOP …` or `Verdict: … STOP`,
  once per turn. `HOLD` never toasts.
- `session-viz: <type> dispatched on <model> (<tier>); model-routing says <tier |
  inherit>` — an `agent.spawn` whose model tier disagrees with
  `.agents/references/model-routing.md` (D11).
- `session-viz: <type> dispatch missing contract item(s) <n, …>` — a reviewer spawn
  whose prompt lacks the marker of any of the seven items of
  `.agents/references/review-dispatch-contract.md` (D10).

Observe-only: every hook passes `e` to `next` unchanged and returns what `next`
resolved; no hook returns `deny`, rewrites a field, or answers for the engine. The
pane, the status line and the toasts are the only outputs.

## Inputs

Engine events (names as `on(...)` takes them, fields as `types/claude-code.d.ts`
declares them):

| Event | Fields read | Feeds |
|---|---|---|
| `session.start` | — | registers `/session-viz`, opens the pane, starts the 5 s `$.agent.list()` sync, reads `tasks/todo.md` once |
| `command.run` `{ command: 'session-viz' }` | — | opens the pane with `focus` |
| `agent.spawn` | `prompt`, `description`, `subagentType`, `model`, `parentModel`, `parentAgentId`, `tool_use_id`; result `agentId`, `model` | a tree row and its brief; the two dispatch checks |
| `turn.step` (async generator, `yield* next(e)`) | `agentId`, `index`, `messageCount`; result `answer` | step and message counts; `[ROUTE]` lines on the main loop |
| `turn.complete` | `agentId`, `reason`, `durationMs`, `answer`, `usage` | status, outcome, `[AMBIGUITY]`, `[SURFACE]`, four-axis findings, `Verdict:` and `Receipt:` lines; a receipt re-read on the main loop |
| `tool.call` | `tool`, `agentId`, and per tool `file_path` (Read, Edit, Write, MultiEdit, NotebookEdit), `pattern` and `path` (Glob, Grep), `command` (Bash); `AskUserQuestion` open or answered | footprints; `⚑` while a dialog is open; a `tasks/todo.md` re-read after an Edit or Write of it; a receipt re-read after a Bash `receipt.py write` |
| `skill.prompt` | `skill` | the running skill and the phase (D8) |
| `prompt.submit` | `text` | the spec path a build prompt names (D9) |
| `session.measure` | `context.percent`, `cost.usd` | the status line |
| `ui.render` `{ component: 'Pane', requestId: 'session-viz' }` | `surface`, `props.bodyColumns`, `props.view.agentId` | the drawing |

Engine calls: `$.agent.list()` (ids, types, descriptions, parents, statuses),
`$.fs.read` and `$.fs.stat` (`tasks/todo.md`, `.git`, the receipt files),
`$.session.repo()` (the main working tree's root), `$.ui.open`, `$.ui.status`,
`$.ui.toast`, `$.ui.scroll`, `$.ui.resolve(e)`, `$.command.register`,
`$.clock.every`, and `$.state` through `atom`, `read` and `update` from
`'claude-code'`.

Files and text conventions parsed:

- `tasks/todo.md` — `## Plan: <feature>`, `> Spec: specs/<x>.md`, `### Slice n/N —
  <name>`, `- [ ]`/`- [x]` header rows, indented `[ ] TDD:`, `[x] TDD:` and
  `[ ] Verify:` rows, `> Handover:` blockquotes. `\r` is stripped first.
- `[ROUTE] lane=<lane> | chain=<skill, …> | reason: …`
- `[AMBIGUITY] <text> | options: … | picked: <letter> | reason: …`
- `[SURFACE] +<path> | reason: <sentence>`
- `[MUST-FIX | confidence: N | autofix_class: … | owner: …]`, with an optional
  `<n>. ` prefix, as `.agents/references/finding-model.md` § *Emission format* spells
  it; severities `MUST-FIX`, `SHOULD-FIX`, `NITPICK`.
- `Receipt: <GO|HOLD|STOP> <fp8> …` and `Verdict: <glyph>? <GO|HOLD|STOP>` lines.
- The quality receipt: `<repo root>/.git/quality-receipts/branch-<branch>.json`
  (`{ fingerprint }`) then `<fingerprint>.json` (`schema`, `verdict`, `tests.exit`,
  `unresolved[]`, `design_verdict`), `<branch>` sanitized as `receipt.py` does
  (`[^A-Za-z0-9_.-]` → `-`). The branch comes from `.git/HEAD` (a file `.git` in a
  worktree is `gitdir: <path>`; HEAD is read there).

## Outputs

- The pane `session-viz` and its tree, validating on the `terminal` and `desktop`
  surfaces.
- One status line entry, replaced on every change.
- The three toasts above, and nothing on `HOLD`, `GO`, a finished agent or an
  `[AMBIGUITY]` line.
- Session state under `$.state` for the plugin `session-viz`: `phase`, `agents`,
  `asking`, `selected`, `plan`, `gates`, `measure`, `toasted` — declared in
  `types/index.d.ts` (§ Implementation Paths), nothing in `$.store`.
- `$.ui.scroll({ to: { requestId: <toolUseId> } })` on a row press.

## Edge Cases

- **Hot reload.** `register` runs again and module variables start over: every value
  a drawing or a toast decision reads is in `$.state`, the set of fingerprints and
  turns already toasted included, so a reload neither empties the pane nor repeats a
  toast.
- **An agent the hooks never saw** (spawned before the mod loaded): the sync adds it
  from `$.agent.list()` with no `toolUseId`, the prompt `(spawned before session-viz
  loaded)` and an empty footprint; its press opens the drill-down without scrolling.
- **An agent whose parent is unknown** is drawn as a root.
- **`e.skill` with a plugin prefix** (`jplugin:build`): the phase map matches the
  segment after the last `:`.
- **`[ROUTE]` printed mid-turn**: it is read off every main-loop `turn.step`
  result, not only the turn's final answer.
- **No recorded spec**: the Plan section shows the last `## Plan:` block holding an
  open `[ ]` row, else the last block, else `no plan block`.
- **`tasks/todo.md` missing or unparseable**: the Plan section reads `no plan
  block`; nothing is logged to the model and no hook fails.
- **Detached HEAD, no `.git`, or a receipt file missing or malformed**: the Gates
  section reads `no receipt yet` or `receipt unreadable`; no toast.
- **No surface** (`claude -p`, a desktop session before a page attaches): `$.ui.open`
  resolves `isPlaced: false` and the pane waits; the status line and the toasts are
  still set and do no harm.
- **Narrow pane**: below 120 body columns the drill-down is the last section; every
  row is truncated to the body width with `…`.
- **Caps**: 200 agents (the oldest finished rows leave first), 40 entries per
  footprint list (the drill-down says `+n more`), 2000 characters of spawn prompt
  drawn, 50 ambiguity and 50 surface lines kept.
- **Tool names differ per build** (a native build registers no Glob or Grep): the
  footprint compares `String(e.tool)` and reads the fields by name.
- **The `turn.step` hook** is an async generator (`async function* ($, e, next) {
  const result = yield* next(e); …; return result }`); a plain function there is a
  type error and loads nothing.
- **The CLI on PATH** may be older than the engine that runs the session (2.1.277
  here, against a 2.1.299 engine): `claude plugin validate` there refuses the
  `update($, …)` helper and has no `plugin test`. The build checks `claude --version`
  is 2.1.299 or later before the first validate and upgrades it when it is not
  (D15).
- **Load**: one person, one session, at most a few hundred agents and a
  `tasks/todo.md` of a few thousand lines; every parse is linear and runs on a
  change, never on a timer.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Slice |
|---|---|---|---|---|---|
| R1 | The function-hooks API is early access and moves between releases | M | H | The types laid in `.claude-plugin/types/` at the first load are the authority; every event field the mod reads is one those types declare today | 1 |
| R2 | A jplugin text convention changes shape and a parser goes quiet | M | M | Each convention's regex lives in one function with a test pinning the current format; a miss shows an empty section, never a failure | 2, 3, 4, 5 |
| R3 | The seven-item contract check is heuristic and toasts on a hand-written dispatch | M | L | The markers are the contract's own words (D10); the toast names the missing items so the person can judge, and the row stays under Gates | 5 |

## Decisions

| # | Question | Decision | Source | Why |
|---|---|---|---|---|
| 1 | Does v1 intervene? | Observe only: no `deny`, no rewrite, every hook passes `e` on unchanged | user | Settled in the prior session; a visualizer that can refuse a tool call is a different, riskier mod |
| 2 | Where does the mod live? | A standalone mod at `mods/session-viz/`, not a module of the jplugin plugin's `hooks/hooks.json`; during the build it is hot-reloaded by copying the folder into the session's `~/.claude/dev-mods/<session>/` folder or by `claude --plugin-dir mods/session-viz`, the repo copy being the source of truth | user | Settled as "standalone first, into jplugin later"; placing the source in the repo (the interview's refinement) lets `/slice` size its surface and the build commit it, which a folder outside the repo cannot |
| 3 | What does the per-agent drill-down show? | Brief plus footprint — description, spawn prompt, files read, edited and grepped, commands, step count, outcome — and no transcript | user | Settled in the prior session; the transcript is the engine's tasks list's job |
| 4 | Where is state kept? | Everything in `$.state`, session-scoped; nothing in `$.store` | user | Settled; nothing here is worth carrying across sessions |
| 5 | How does it relate to `mods/factory-board`? | A superset: the Agents section carries the tree plus factory-board's stage derivation, glyphs, dialog mark and press-to-scroll; factory-board is untouched now and retired when session-viz moves into jplugin | user | Two panes tracking the same agents is noise; retiring now would widen this spec's surface |
| 6 | Pane layout? | One column of stacked sections — Phase, Plan, Agents, Gates, Drill-down; from 120 body columns the drill-down is a right column | user | Everything is visible at once; tabs hide the gates while agents run |
| 7 | Toast conditions? | Strict, `HOLD` silent: STOP from a receipt (once per fingerprint) or a `Receipt:`/`Verdict:` line (once per turn); off-tier per D11; a missing contract item per D10, one toast per spawn naming the items | user | `HOLD` already waits on the person through the gate's own output; a toast would double it |
| 8 | How is the phase known? | From `skill.prompt`, by the skill name's last `:` segment: `prd`, `grill-me`, `grilling`, `brainstorm`, `plan`, `system-design-planning`, `slice`, `visual-plan` → `PLAN`; `build`, `yolo`, `auto-push`, `make-it-simpler` → `BUILD`; `quality-gate`, `software-design-expert-review`, `security-scan`, `verify-evidence` → `GATE`; `wrap-up-session` → `WRAP-UP`; any other skill is shown as running and leaves the phase | assumed | `AGENTS.md` § Workflow names these as the phases' owning skills; a `[ROUTE]` line adds the lane and chain |
| 9 | Which `## Plan:` block is active? | The one whose `> Spec:` names the spec path the most recent `prompt.submit` text named (`specs/<x>.md`, the build prompt's `Invoke \`/build\` for …` line); otherwise the last block with an open `[ ]` row; otherwise the last block | assumed | The build prompt is the one place a session states which plan it builds |
| 10 | What counts as a contract item present? | A case-insensitive marker per item, in the reviewer prompt: 1 `diff --git`, `...HEAD` or `git diff`; 2 `specs/<x>.md` or `no spec —`; 3 `tasks/todo.md`; 4 `[AMBIGUITY]` or `ambiguit`; 5 `TODO(shortcut)` or `deferrals: none`; 6 `introduced`, `pre-existing` or `boundary`; 7 both `confidence` and `autofix_class`, or `failure:`. Checked for `code-reviewer`, `critic`, `security-reviewer`, `software-design-expert-review` (last `:` segment of `subagentType`) | assumed | The contract is prose with two canonical empty forms; its own words are the only stable markers |
| 11 | What is off-tier? | Tier of a model string: contains `opus` → planner, `sonnet` → builder (Reviewer resolves to the same alias), `haiku` → scout. Pinned personas: `planner` → planner; `backend-developer`, `frontend-developer`, `frontend-design-validator`, `code-debugger`, `context-document-optimizer` → builder. Ceiling personas (`code-reviewer`, `security-reviewer`, `software-design-expert-review`) toast on any explicit `model`; `critic` toasts on an explicit model unless it is planner tier and `parentModel` is below planner. Unlisted types are never checked | assumed | Verbatim from `.agents/references/model-routing.md` § Agents and § Floors |
| 12 | How is the receipt located without `$.process.run`? | `$.session.repo().root` is the main working tree's root, so the receipts are under `<root>/.git/quality-receipts/`; the branch is read from `.git/HEAD`, following a `gitdir:` file in a worktree | assumed | `$.process` is CLI-only and this session is desktop-hosted; the files are enough |
| 13 | How is the module split? | `hooks/register.tsx` wires the shell and composes the pane from section modules — `phase.tsx`, `plan.tsx`, `agents.tsx`, `gates.tsx`, `dispatch.tsx` — each exporting its `register<Section>(on)` and `<Section>` render; `hooks/state.ts` holds every atom; slice 1 lays the section files as stubs so slices 2–5 edit disjoint files | assumed | Disjoint surfaces let the ready set dispatch in parallel; one 600-line module would serialize every slice |
| 14 | Which engine runs `validate` and `test`? | Claude Code 2.1.299 or later (2.1.303 is published); the build's pre-flight runs `claude --version` and upgrades with `npm i -g @anthropic-ai/claude-code@latest` when older | assumed | The 2.1.277 CLI on this PATH fails on the `update` import and lacks `plugin test` |
| 15 | Pane id, title, command? | `session-viz`, `Session`, `/session-viz` | assumed | One word the status line and the toasts share |
| 16 | Footprint capture? | `tool.call` with `agentId`: Read, Glob → read; Edit, Write, MultiEdit, NotebookEdit → edited; Grep → `<pattern> in <path>`; Bash → the command's first 80 characters; every call counts; `turn.step` with `agentId` → steps (`index + 1`, max) and the last `messageCount`; `turn.complete` → outcome, duration, usage | assumed | These are the four footprint kinds decision 3 names, read from the events that carry them |

## Acceptance Criteria

- AC1: `claude plugin validate mods/session-viz` and `claude plugin test mods/session-viz` pass on Claude Code 2.1.299 or later; the pane `session-viz` opens at `session.start` and on `/session-viz`; the same tree mounts on the `terminal` and `desktop` surfaces; with nothing observed each section draws its one empty line; a `tool.call` result passes through the mod's hooks unchanged.
- AC2: a `skill.prompt` for `jplugin:build` makes the Phase section read `BUILD · build`; a main-loop `turn.step` whose answer carries `[ROUTE] lane=fix | chain=debug, quality-gate | reason: a defect` sets lane `fix` and chain `debug, quality-gate`; a `prompt.submit` whose text names `specs/x.md` records that spec.
- AC3: after a `session.measure` with `context.percent` 42 and `cost.usd` 1.2345 the status line reads `viz · BUILD · build · ctx 42% · $1.23` with the agents count appended once agents exist, and no field it does not know.
- AC4: a `code-reviewer` spawned with the `parentAgentId` of a running `general-purpose` agent is drawn indented under it with `◐` and stage `review`; after its `turn.complete` with reason `answer` and `durationMs` 12000 it reads `✓ … 12s`; an agent only `$.agent.list()` reports, with status `killed`, is drawn `✗` as a root.
- AC5: `tool.call`s with `agentId` X — Read `a.md`, Edit `b.ts`, Grep `foo` in `src`, Bash `npm test` — and two `turn.step`s (`index` 0 and 1, `messageCount` 7) give X the footprint read `[a.md]`, edited `[b.ts]`, grepped `[foo in src]`, commands `[npm test]`, 4 tool calls, 2 steps, 7 messages; a 41st read entry drops the oldest and the drill-down says `+1 more`.
- AC6: pressing `agent:X` answers `{ element: 'agent:X' }`, scrolls to X's spawning `tool_use_id`, and opens the drill-down with X's description, type, requested and resolved model, parent model, parent agent, spawn prompt, footprint lists and counts, outcome and duration; pressing again closes it; `$.session.messages` is never called.
- AC7: with a `tasks/todo.md` holding two `## Plan:` blocks and a recorded spec matching the first, the Plan section reads `slice 1/4 · rows 3/7` with one line per slice and `✓ handover` on the closed one; without a recorded spec the last block holding an open `[ ]` row is shown.
- AC8: a `tool.call` Edit or Write whose `file_path` ends with `tasks/todo.md` re-reads the file after the call completes and the Plan section changes; a missing file reads `no plan block` and no hook fails.
- AC9: a reviewer's `turn.complete` answer with two `[MUST-FIX | confidence: 100 | autofix_class: gated_auto | owner: agent]` findings (one `1. `-prefixed), one `[NITPICK | …]`, one `[AMBIGUITY] …` line and one `[SURFACE] +x.py | reason: y` line gives Gates `MUST-FIX 2 · NITPICK 1`, the ambiguity listed with the agent's type, and the surface report listed.
- AC10: a `branch-<branch>.json` pointer naming a `<fingerprint>.json` whose `verdict` is `STOP` toasts `session-viz: quality gate STOP (<fp8>)` once (a second read of the same fingerprint is silent); a `HOLD` receipt toasts nothing; a main-loop answer line `Receipt: STOP <fp8> policy qg1-00000000` toasts once per turn; the Gates section reads `receipt STOP <fp8> · tests exit 1 · unresolved N`.
- AC11: `backend-developer` spawned with `model` `opus` toasts off-tier; `code-reviewer` spawned with `model` `sonnet` toasts; `critic` with `opus` under `parentModel` `claude-sonnet-5-5` is silent; `planner` with `opus` is silent; `general-purpose` with any model is silent; each toast is also a row under Gates.
- AC12: a `code-reviewer` spawned with a prompt carrying all seven markers is silent; the same prompt without `deferrals: none` and without the boundary words toasts `session-viz: code-reviewer dispatch missing contract item(s) 5, 6` once; a `general-purpose` spawn with no markers is silent.

## Implementation Paths

- `mods/session-viz/.claude-plugin/plugin.json` — manifest: `name` `session-viz`, `version` `0.1.0`, `description`, `"types": "./types/index.d.ts"`.
- `mods/session-viz/hooks/hooks.json` — `{ "modules": ["./register.tsx"] }`.
- `mods/session-viz/hooks/register.tsx` — `export const register: Register`: `session.start` (command, pane, sync timer, first `tasks/todo.md` read), `command.run`, `prompt.submit`, `session.measure`, `skill.prompt`, the `ui.render` Pane hook composing the sections and the status line builder; calls each section's `register<Section>(on)`.
- `mods/session-viz/hooks/state.ts` — every `atom({ plugin: 'session-viz', key })` and shared helpers (`fit`, `seconds`, `lastSegment`).
- `mods/session-viz/hooks/phase.tsx` — the skill-to-phase map (D8), the `[ROUTE]` parser, `PhaseSection`.
- `mods/session-viz/hooks/plan.tsx` — `parsePlan(text, spec?)` over `tasks/todo.md` (D9), the re-read triggers, `PlanSection`.
- `mods/session-viz/hooks/agents.tsx` — `agent.spawn`, `turn.step` (generator), `turn.complete`, `tool.call` footprints and `AskUserQuestion` marks, the `$.agent.list()` merge, `AgentsSection` and `DrillDown`.
- `mods/session-viz/hooks/gates.tsx` — finding, ambiguity, surface, `Verdict:` and `Receipt:` parsers; the receipt reader (D12); the STOP toast; `GatesSection`.
- `mods/session-viz/hooks/dispatch.tsx` — the tier table and off-tier rule (D11), the seven-item markers (D10), their toasts, `DispatchIssues` drawn under Gates.
- `mods/session-viz/hooks/*.test.ts` — `claude plugin test` files, one per section plus `register.test.ts` for the shell; each UI assertion loops over `['terminal', 'desktop'] as const`.
- `mods/session-viz/types/index.d.ts` — `Phase`, `AgentRow`, `Footprint`, `PlanProgress`, `SliceRow`, `Gates`, `DispatchIssue`, and `declare module 'claude-code' { interface PluginState { 'session-viz': { phase, agents, asking, selected, plan, gates, measure, toasted } } }`.
- `mods/session-viz/README.md` — what the pane shows, the layout, how to run it (`--plugin-dir`, the dev-mods copy), `validate` and `test`.

## Build Order

Sizing: 5 slices. Ceiling: per `slice/references/sizing.md`. Over: slice 1: 12 files — four of them (`agents.tsx`, `plan.tsx`, `gates.tsx`, `dispatch.tsx`) are one-export stubs the wiring imports, laid here so slices 2–5 own disjoint files and dispatch in parallel.

| # | Slice | Delivers | Surface | Blocked by | ACs | Verify | Size |
|---|-------|----------|---------|------------|-----|--------|------|
| 1 | Shell, phase and status line | The manifest, the `$.state` contract, the pane shell composing five section slots, the phase and `[ROUTE]` reader, the recorded spec and the status line | `mods/session-viz/.claude-plugin/plugin.json`, `mods/session-viz/hooks/hooks.json`, `mods/session-viz/hooks/register.tsx`, `mods/session-viz/hooks/state.ts`, `mods/session-viz/hooks/phase.tsx`, `mods/session-viz/hooks/agents.tsx`, `mods/session-viz/hooks/plan.tsx`, `mods/session-viz/hooks/gates.tsx`, `mods/session-viz/hooks/dispatch.tsx`, `mods/session-viz/hooks/register.test.ts`, `mods/session-viz/types/index.d.ts`, `mods/session-viz/README.md` | — | 1, 2, 3 | `claude plugin validate mods/session-viz && claude plugin test mods/session-viz` | 12 files · 1 system · 3 ACs |
| 2 | Agents tree and drill-down | The sub-agent tree with stage glyphs and statuses, per-agent footprints from tool calls and steps, and the press-to-open brief-plus-footprint drill-down | `mods/session-viz/hooks/agents.tsx`, `mods/session-viz/hooks/agents.test.ts` | 1 | 4, 5, 6 | `claude plugin validate mods/session-viz && claude plugin test mods/session-viz` | 2 files · 1 system · 3 ACs |
| 3 | Plan progress | The `tasks/todo.md` plan-block parser, the active-block choice and the re-read triggers behind the Plan section | `mods/session-viz/hooks/plan.tsx`, `mods/session-viz/hooks/plan.test.ts` | 1 | 7, 8 | `claude plugin validate mods/session-viz && claude plugin test mods/session-viz` | 2 files · 1 system · 2 ACs |
| 4 | Findings and receipt | Four-axis finding, ambiguity, surface and verdict parsing, the quality-receipt reader and the STOP toast behind the Gates section | `mods/session-viz/hooks/gates.tsx`, `mods/session-viz/hooks/gates.test.ts` | 1 | 9, 10 | `claude plugin validate mods/session-viz && claude plugin test mods/session-viz` | 2 files · 1 system · 2 ACs |
| 5 | Dispatch checks | The off-tier and missing-contract-item checks on every `agent.spawn`, their toasts and their rows under Gates | `mods/session-viz/hooks/dispatch.tsx`, `mods/session-viz/hooks/dispatch.test.ts` | 1 | 11, 12 | `claude plugin validate mods/session-viz && claude plugin test mods/session-viz` | 2 files · 1 system · 2 ACs |

Build prompt:

```
Invoke `/build` for `specs/session-viz-mod.md`.
Plan: `## Plan: session-viz-mod` in `tasks/todo.md`, 5 slices, ready set <1>.
Files: mods/session-viz/**.
Instructions:
1. `/build`'s pre-flight files the slices: `/slice specs/session-viz-mod.md --file --approve`. The planning session filed nothing.
2. Build the ready set, then each slice its blockers release. A slice edits only its Surface in § Build Order.
3. Follow § Decisions: every row is settled. A gap the spec leaves is an `[AMBIGUITY]` line, never a question to the user.
4. Close every slice with a `> Handover:` line; after the last one run `/wrap-up-session`.
Constraints:
- D14: run `claude --version` before the first validate; `claude plugin validate` and `claude plugin test` need Claude Code 2.1.299 or later — upgrade with `npm i -g @anthropic-ai/claude-code@latest` when older.
- D1: observe only — no hook returns `deny`, rewrites `e`, or answers for the engine.
- D4: every value a drawing or a toast decision reads lives in `$.state`; nothing in `$.store`.
- D5: `mods/factory-board/` is not edited.
- D2: hot-reload during the build from a copy in the session's `~/.claude/dev-mods/<session>/` folder (load the bundled `plugin-authoring` skill first) or with `claude --plugin-dir mods/session-viz`; the repo folder is the source of truth.
- D13: slice 1 lays `agents.tsx`, `plan.tsx`, `gates.tsx` and `dispatch.tsx` as stubs exporting `register<Section>(on)` and the section's render; slices 2–5 fill their own file only.
```
