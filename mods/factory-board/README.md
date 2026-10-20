# factory-board — a Claude Code mod

A live Kanban pane of the sub-agents in the current session, grouped by the
stage of the software-factory harness they work in:

```
PLAN 1        BUILD 2                REVIEW 1             HUMAN 1              DONE 3
◐ planner ·   ◐ general-purpose ·    ◐ code-reviewer ·    ⚑ critic · slice 2   ✓ Explore · find …
  slice 4     ▶ slice 3 tests          slice 2                                 ✓ general-purpose …
              ◐ backend-developer …                                            ✗ security-reviewer …
```

- **Columns**: `PLAN` (planner, Plan, Explore, grilling), `BUILD` (everything
  else that is running), `REVIEW` (code-reviewer, critic, security-reviewer,
  software-design-expert-review, validators), `HUMAN` (an agent with an
  `AskUserQuestion` dialog open, or one that finished with `[AMBIGUITY]` lines
  in its answer), `DONE` (finished: `✓` answered, `✗` failed, aborted or killed).
- **Cards** are buttons. Press one: the main transcript scrolls to the Agent
  tool row that spawned it, and a detail box opens under the board with its
  status, duration, agent id, parent and the tail of its own transcript. Press
  it again to close the detail. `▶` marks the card whose transcript the person
  has on screen through the engine's tasks list.
- A yellow line at the top says when the **main session** is waiting for an
  answer.
- `/factory-board` opens (and focuses) the pane; it also opens by itself at
  session start where the terminal is wide enough to dock it.

## Layout

```
.claude-plugin/plugin.json   manifest (name, version, the state contract)
hooks/hooks.json             names the one hooks module
hooks/register.tsx           the hooks: agent.spawn, turn.complete, tool.call(AskUserQuestion), ui.render(Pane)
hooks/register.test.tsx      claude plugin test
types/index.d.ts             Card, Stage and the $.state contract
```

State lives in `$.state` (cards, asking, selected), so a hot reload keeps the
board; a `$.clock.every` sync folds `$.agent.list()` in every 5 s so killed or
background agents the hooks never saw still show their engine status.

## Run it

```bash
claude --plugin-dir "$(pwd)/mods/factory-board"
```

Or copy the folder into the session's `~/.claude/dev-mods/<session>/` folder
while the `plugin-authoring` skill is loaded and accept "Enable hot reloading".

```bash
claude plugin validate mods/factory-board
claude plugin test mods/factory-board
```
