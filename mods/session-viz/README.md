# session-viz — a Claude Code mod

One docked pane, titled `Session`, that shows how a jplugin session is going.
It observes and never intervenes: no hook denies, rewrites or answers for the
engine. It supersedes `mods/factory-board/`, whose sub-agent Kanban it absorbs
into its Agents section.

```
PHASE                                   AGENT
BUILD · build                           code-reviewer · review slice 3
route feature · plan, build             requested sonnet · resolved claude-sonnet-5-5
spec specs/session-viz-mod.md           parent claude-opus-5-5 · under agent-7
                                        ✓ answer · 12s · 14 tool calls · 3 steps · 9 messages
PLAN                                    read [a.md, b.ts] · edited [c.ts] · grepped [foo in src]
session-viz-mod · slice 1/5 · rows 3/11 commands [npm test]
1/5 Shell, phase and status line · rows 3/3 · ✓ handover
2/5 Agents tree and drill-down · rows 0/3
…
AGENTS
◐ build general-purpose · slice 2 agents
  ✓ review code-reviewer · review slice 1 · 12s
GATES
receipt GO 3f9a1c2e · tests exit 0 · unresolved 0
MUST-FIX 0 · SHOULD-FIX 1 · NITPICK 2
```

- **Phase** — `PLAN`, `BUILD`, `GATE`, `WRAP-UP` or `idle` from the skill
  running now (`skill.prompt`), plus the `/go` route when a `[ROUTE]` line was
  printed and the spec the build prompt named.
- **Plan** — the active `## Plan:` block of `tasks/todo.md`: slices closed over
  total (a slice is closed once its `> Handover:` exists), rows done over total,
  one line per slice.
- **Agents** — every sub-agent as a tree indented by parent: a glyph (`◐`
  running, `✓` answered, `✗` failed or killed, `⚑` waiting on a dialog or with
  `[AMBIGUITY]` lines), the factory stage, the type, the description, the status
  or duration. Rows are buttons.
- **Gates** — the quality receipt, the last `Verdict:` line, finding counts by
  severity, every `[AMBIGUITY]` and `[SURFACE]` line, and the dispatch checks
  (off-tier, missing contract items).
- **Drill-down** — the pressed agent's brief and footprint: description, type,
  models, parent, the spawn prompt, files read, edited and grepped, commands,
  tool-call, step and message counts, outcome and duration. Pressing the row
  again closes it; pressing also scrolls the transcript to the spawning Agent
  tool row. No transcript is read or shown.

From 120 body columns the drill-down is a right column beside the four
sections; below that it is the last section. Every section shows one dim line
when it has nothing.

The status line reads `viz · <PHASE> · <skill> · slice k/N · ctx NN% · $X.XX ·
agents R/T`, every unknown field left out.

Three toasts, and no others: `session-viz: quality gate STOP (<fp8>)`,
`session-viz: <type> dispatched on <model> (<tier>); model-routing says <tier>`
and `session-viz: <type> dispatch missing contract item(s) <n, …>`. `HOLD` never
toasts.

## Layout

```
.claude-plugin/plugin.json   manifest (name, version, the state contract)
hooks/hooks.json             names the one hooks module
hooks/register.tsx           the shell: session.start, /session-viz, the Pane render composing the sections
hooks/state.ts               every $.state atom, the status-line builder and shared helpers
hooks/phase.tsx              the skill-to-phase map, the [ROUTE] parser, the recorded spec
hooks/plan.tsx               the tasks/todo.md plan-block parser and re-read triggers
hooks/agents.tsx             the sub-agent tree, footprints and drill-down
hooks/gates.tsx              findings, ambiguities, surfaces, the receipt reader, the STOP toast
hooks/dispatch.tsx           the off-tier and contract-item checks on agent.spawn
hooks/*.test.ts              claude plugin test, one file per section
types/index.d.ts             the $.state contract
```

Everything a drawing or a toast decision reads lives in `$.state`, so a hot
reload keeps the pane and repeats no toast; nothing is kept in `$.store`.

## Run it

Needs Claude Code 2.1.299 or later (`claude --version`).

```bash
claude --plugin-dir "$(pwd)/mods/session-viz"
```

Or copy the folder into the session's `~/.claude/dev-mods/<session>/` folder
while the `plugin-authoring` skill is loaded and accept "Enable hot reloading";
the repository folder stays the source of truth.

```bash
claude plugin validate mods/session-viz
claude plugin test mods/session-viz
```
