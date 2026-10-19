---
implementation_paths:
  - mods/factory-board/**
---

# Spec: factory-board

> Origin: "prompt" (2026-10-16) · MVP · Review status: **built** 2026-10-16

## Behavior

A Claude Code mod (a plugin of function hooks, hot-reloadable) that opens a
pane showing every sub-agent of the current session as a card on a Kanban
board with the columns PLAN, BUILD, REVIEW, HUMAN and DONE — the stages of the
`/plan` → `/build` → `/quality-gate` harness plus the human escalations the
Ambiguity Protocol and `AskUserQuestion` produce. Pressing a card scrolls the
transcript to the Agent tool row that spawned the agent and opens a detail box
with the agent's status, duration, id, parent and the tail of its transcript.

## Inputs

- `agent.spawn` — one card per started agent: `agentId`, `tool_use_id`,
  `subagentType`, `description`, `parentAgentId`.
- `turn.complete` with `agentId` — status (`done` on `answer`, else `failed`),
  `durationMs`, and the count of `[AMBIGUITY]` lines in `answer`.
- `tool.call` of `AskUserQuestion` — the loop (`agentId`, or `main`) is in
  HUMAN while the dialog is open.
- `$.agent.list()` every 5 s — engine statuses (`completed`, `failed`,
  `killed`) and agents the hooks never saw (started before a reload).
- `Pane` props: `bodyColumns` sizes the columns, `view.agentId` marks the card
  whose transcript the person has on screen.

## Outputs

- A pane `factory-board` titled `Factory`, opened at `session.start` and by
  `/factory-board`.
- A toast when an agent's answer carries `[AMBIGUITY]` lines.
- A press: `selected` toggles, `$.ui.scroll({ to: { requestId: toolUseId } })`.

## Decisions

| # | Decision | Why |
|---|----------|-----|
| D1 | Stage is derived from the agent type's name (`review\|critic\|security\|validator` → REVIEW, `plan\|explore\|scout\|grill` → PLAN, else BUILD) | The harness names its personas by tier; no spawn carries a stage, and a table keyed on names is one function to edit |
| D2 | HUMAN holds both an open `AskUserQuestion` and a finished agent with `[AMBIGUITY]` lines | Both are the escalations the user asked to see; the glyph (`⚑`) and the detail box tell them apart |
| D3 | "Jump to the agent" is a transcript scroll to the spawning row plus a transcript tail in the pane | The plugin API exposes no call that switches the viewed agent; `view.agentId` is read-only, so the mod marks (`▶`) rather than switches |
| D4 | State in `$.state`, never module variables | A hot reload re-runs `register`; the board must survive it |
| D5 | Standalone mod under `mods/`, not a `modules` entry on the root `hooks/hooks.json` | The jplugin plugin ships classic command hooks; mixing a function-hooks module into it changes what every install loads |

## Edge Cases

- Narrow pane (`bodyColumns` < 80): columns stack vertically.
- An agent that finished before the mod loaded: the sync adds it with an
  empty `toolUseId`; its press opens the detail without scrolling.
- A `session.messages` deny (an agent the session cannot read): the detail
  box shows the reason instead of the tail.
- More than 100 cards: the oldest fall off.

## Acceptance Criteria

- A spawned `code-reviewer` is a card under `REVIEW 1`; after its
  `turn.complete` with one `[AMBIGUITY]` line it is under `HUMAN 1` and
  `REVIEW` reads `0`.
- Pressing the card answers `{ element: 'card:<agentId>' }`, opens the detail
  box (type, description, `1 [AMBIGUITY]`, transcript tail); pressing again
  closes it.
- While an `AskUserQuestion` call of the main loop is open the pane shows the
  `main-waiting` line; once answered it is gone.
- The same tree validates on the `terminal` and `desktop` surfaces.
- `claude plugin validate mods/factory-board` and `claude plugin test
  mods/factory-board` pass.
