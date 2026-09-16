# Lane: refactor

Owned by the go front door. Runs when the goal asks to rename, extract,
inline, dedupe, or move, or says "no behaviour change".

1. Before-proof: run the tests that cover the code being changed and record the command and result; if nothing covers it, record a characterization run (the current inputs and outputs) before any edit
2. `/plan <goal>` — the spec's acceptance criteria are "the before-proof still holds" plus the structural change; this is where the human is asked before code changes
3. `/build` — the TDD rows the plan wrote
4. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran)
5. `/wrap-up-session` — the PR body quotes the before-proof and the after-proof from the same command

## Reply

Before and after proof quoted side by side, the PR URL, and any behaviour the
characterization run showed that the goal did not expect.
