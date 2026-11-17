# Phase 4 — from a finding to a checked model

`state_machines.py tla` turns one finding into a TLA+ skeleton. The skeleton is a
starting point, never a verdict: it models only the variable the finding names,
and every action is a claim about the code that a reviewer must be able to open.

## What the skeleton contains

- `VARIABLES state, via` — the machine's state, and the label of the last step.
- `Init` — the finding's `entry`.
- `T1..Tn` — one action per intended transition; `via'` is the transition's `via`.
- `H1..Hn` — one action per hidden transition, preceded by its `why` as a comment;
  `via'` is `hidden <n>: <via>`, so a hidden move that shares code with an
  intended one stays distinct.
- `Done` — exit states stutter, so a correct end is not reported as a deadlock.
  Without exits there is no `Done`, and TLC will report a deadlock at any state
  with no step out — that is a finding to read, not to suppress.
- `TypeOK` and `IntendedOnly == via \notin HiddenVias`. `IntendedOnly` fails on
  the shortest path that takes a hidden transition — the bug path to show the user.

## Make it true to the code

1. Replay each action against its `via` line. Where the code's guard is richer
   than "current state is X" (a flag, a second variable), add the variable and the
   guard. Where two writers race, model each as its own action.
2. Write each rule the user agrees to as an `INVARIANT` in the `.cfg` — a rule
   about what the user sees, stores or sends, in their words. Never weaken a rule
   to make it pass.
3. Keep constants small; add a `CONSTRAINT` if a counter is unbounded.

## Check and draw

- **pstack installed** — run `/statechart` on the module. Name the `.tla`, its
  `.cfg`, and a view that labels states in the reader's words; it reports the
  shortest path to each broken rule and draws the Mermaid statechart. Refer to
  `/statechart` by name: its command line changes between releases, so copy none
  of it here.
- **The property must keep holding** — hand the machine to pstack's
  `/create-formal-verification-skill`, which generates a project-local verify
  skill with a coverage record and sync commit. Pass it the finding's name, files,
  and the hidden transitions as the bugs its check must catch.
- **No pstack** — TLC runs directly:
  `java -cp tla2tools.jar tlc2.TLC -config <Module>.cfg <Module>.tla`
  (`tla2tools.jar` from the TLA+ releases page). Say in the hand-off that the
  chart was not drawn.

## Replay before you believe it

When TLC reports a path, replay it against the real code — as a test or a live
repro, one step per action. If the path does not occur, assume the model is wrong
until shown otherwise, and correct the finding's `hidden` entry in
`findings.json`.
