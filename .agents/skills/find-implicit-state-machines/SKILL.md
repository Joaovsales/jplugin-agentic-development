---
name: find-implicit-state-machines
description: "Find the implicit state machines in a codebase — status/mode/phase variables, boolean flags, guard chains, lock and marker files, handlers and async chains that move shared state with no declared machine — then document each one (states, transitions, entry, exits, tests, confidence), flag hidden transitions the code allows but nobody intended and machines with thin transition coverage, and write .jplugin/state-machines/findings.json. Read-only. Can bridge a found machine to a TLA+ skeleton for /statechart. Triggers on: 'find implicit state machines', 'what states can this get into', 'hidden transitions', 'unexpected state paths', 'map the state machines'."
argument-hint: "[<path>... | --verify <machine name>]"
disable-model-invocation: false
harness: universal
---

# /find-implicit-state-machines — discovery → documentation → formalization

An explicit state machine declares its states and the legal moves between them. An
implicit one emerges from functions scattered across files, each flipping a flag or
writing a status — and together they allow moves nobody designed: an order shipped
before it is paid, two handlers changing it at once. Unit and integration tests pass,
because no test drives the path nobody thought existed. This skill finds those
machines, writes each one down, and names the paths that should not be possible.

**Never modify application code.** Read, run the helper, write only
`.jplugin/state-machines/`. A fix is the user's call, in a later session.

`scripts/state_machines.py` (Python 3 standard library) does the deterministic
work: `scan` ranks files, `check` validates the findings and computes the flags,
`tla` writes the Phase 4 skeleton; paths resolve from the repository root. Without
Python, do the same ranking by hand with the patterns in `references/signals.md`.

One run completes Phases 1–3. Re-running refreshes the file: keep a machine's
`name` stable across runs so a reader can diff findings over time.

## Phase 1 — Scan

1. **Scope.** Whole repository by default; the user's paths narrow it (`--path`, repeatable).
2. **Rank.**
   ```bash
   python3 .agents/skills/find-implicit-state-machines/scripts/state_machines.py scan [--path <p>]... [--limit 40]
   ```
   It lists files through `git ls-files --cached --others --exclude-standard` (so
   `.gitignore` holds), skips vendor, generated (`@generated`, `DO NOT EDIT`),
   minified, test, fixture and non-code files, and ranks each remaining file by the
   weighted signals in `references/signals.md`. A file needs two signal kinds to
   rank. Each candidate carries its signal counts and up to five verbatim sample lines.
3. **Read in rank order.** Open the top candidates and follow each state variable to
   every writer and reader — `grep -n` the variable, the setter, the enum. A machine
   usually spans files the scan ranked low; follow it there. On a large repository
   (more than ~15 candidates), dispatch one sub-agent per cluster of related files
   (Reviewer tier, `.agents/references/model-routing.md`), each returning draft
   findings in the Phase 2 shape, and verify every cited line yourself before it
   enters the file.
4. **What counts.** A machine is one piece of state (a variable, field, column,
   file on disk, or set of flags read together) with at least two values and code
   that moves it between them. Look for: modal variables (`status`, `phase`,
   `mode`); boolean flags that only make sense in combination (`isLoading` +
   `hasError`); `if`/`else` chains or `switch`es that decide behavior by state;
   callbacks that must fire only in some states; flags that gate which functions
   are callable; parsers whose loop variables (`in_block`, `expecting`) are states;
   handlers that mutate shared state; lock and marker files; async chains whose
   ordering is the only thing keeping a state consistent.

## Phase 2 — Document

Write `.jplugin/state-machines/findings.json` (create the directory):

```json
{
  "version": 1,
  "head": "<git rev-parse --short HEAD>",
  "scope": ["."],
  "findings": [{
    "name": "Order lifecycle",
    "files": ["src/order.js:2", "src/checkout.js"],
    "states": ["pending", "paid", "shipped", "cancelled"],
    "transitions": [{"from": "pending", "to": "paid", "via": "pay() at src/order.js:4", "tested": true}],
    "entry": "pending",
    "exit": ["shipped", "cancelled"],
    "tested": "UNTESTED",
    "tests": ["tests/order.test.js"],
    "confidence": "HIGH",
    "hidden": [{"from": "pending", "to": "shipped", "via": "ship() at src/order.js:11",
                "why": "ship() never checks isPaid", "tested": false}]
  }],
  "dismissed": [{"path": "src/form.js", "reason": "one flag, one writer — not a machine"}]
}
```

- **name** — what the reader calls the thing whose state it is. Unique; stable across runs.
- **files** — every file that defines a state or makes a transition, `path` or `path:line`.
- **states** — inferred from code: literal values, enum members, flag combinations
  named in words (`loading`, not `isLoading=true,hasError=false`). A state the code
  never names but can reach (both flags true) is a state.
- **transitions** — the intended moves. `via` is the function, event or mutation
  *with* `path:line`. `tested` is true only when a test drives this exact move.
- **entry** — the initial state. **exit** — terminal states; `[]` when none.
- **tested** — `TESTED` only when some test drives an *unexpected* transition and
  asserts it is refused or handled; happy-path tests alone leave it `UNTESTED`.
  **tests** lists every test file that exercises the machine at all.
- **confidence** — `HIGH`: one state variable, named states, several writers.
  `MEDIUM`: the states are clear but spread across flags or files.
  `LOW`: the pattern is ambiguous. Report a LOW machine as LOW and say why in the
  hand-off; never promote it, and never invent states or transitions the code does
  not show. A candidate you read and rejected goes in `dismissed` with the reason.

## Phase 3 — Flag the gaps

For every machine, list in **hidden** each move the code allows that was likely
not intended: a writer with no guard on the source state, two writers racing on the
same state, a flag set on one path and never cleared on another, a callback that
fires in a state where its effect is wrong, an exit state that can be left. Cite the
line; say in `why` which guard is missing. Then run:

```bash
python3 .agents/skills/find-implicit-state-machines/scripts/state_machines.py check --write
```

`check` refuses (exit 1) a transition to an undeclared state, a file or a cited
`path:line` (in `files`, `tests` or `via`) that does not exist, a missing field, a
duplicate name, `TESTED` without a test, or stored flags gone stale — fix the
finding, never the check. `--write` stores `coverage` (tested moves over all moves,
hidden included) and `flags`: `UNTESTED`, `HIDDEN_TRANSITIONS`, `WIDE_LOW_COVERAGE`
(more than 3 states and under 50% coverage) and `LOW_CONFIDENCE`.

## Hand-off

Print `check`'s summary lines, then for each flagged machine one line per hidden
transition: `from → to via <path:line> — <why>`. Name the LOW machines and what
would raise them. End with the next move: a test that drives the hidden transition,
or Phase 4.

## Phase 4 — Bridge to formal verification (on request)

Only when the user asks to verify a found machine (`--verify "<name>"`, or "verify
the order lifecycle"):

```bash
python3 .agents/skills/find-implicit-state-machines/scripts/state_machines.py tla --name "<name>"
```

It writes `tla/<Module>.tla` and `.cfg` beside the findings: one action per
transition, hidden transitions as named actions, a stutter step for exit states, and
`IntendedOnly`, an invariant that fails on the shortest path through a hidden
transition. Then, per `references/formal-bridge.md`: add the user's rules as
invariants; check and draw it with pstack's `/statechart` when installed; for a
property that must keep holding as the code changes, hand the machine to
`/create-formal-verification-skill`. Without pstack, the hand-off names the TLC
command and says the skeleton is unchecked.

## Provenance

The question is Steve Ruiz's prompt — "Find all the implicit state machines in my
app." The Phase 4 target is Lauren Tan's `/statechart` and
`/create-formal-verification-skill` in pstack (`cursor/plugins`, revision
`bf0c7cd80abdbf7fe47b634978a7d1b4071f71a7`), referred to by name, not copied.
