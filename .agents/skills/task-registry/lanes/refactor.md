---
cues: rename, extract, inline, dedupe, move, no behaviour change
ends: PR whose body quotes the before and after proof
---
# Lane: refactor

Runs when the goal asks to rename, extract, inline, dedupe, or move, or says
"no behaviour change". It goes through `/plan` because nothing else in its
chain writes the TDD rows the build step consumes, and because that is where the
harness asks the human before code changes.

1. Before-proof: run the tests that cover the code being changed and record the command and result; if nothing covers it, record a characterization run (the current inputs and outputs) before any edit
2. `/plan <ref>` — the spec's acceptance criteria are "the before-proof still holds" plus the structural change; this is where the human is asked before code changes
3. `/build` — the TDD rows the plan wrote
4. `/quality-gate` — structural, anti-pattern, and APOSD passes (runs inside the build's Phase 3; the row records where it ran) — **non-skippable**
5. `/wrap-up-session` — the PR body quotes the before-proof and the after-proof from the same command

## Reply

Before and after proof quoted side by side, the PR URL, and any behaviour the
characterization run showed that the goal did not expect.
