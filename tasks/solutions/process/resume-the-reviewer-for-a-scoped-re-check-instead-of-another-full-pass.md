---
title: Resume the design reviewer for a scoped re-check of its own findings instead of another full pass
date: 2026-10-23
problem_type: process
module: /quality-gate Phase 4 (software-design-expert-review dispatch); /wrap-up-session § Quality receipt; Agent / SendMessage resume on Claude Code
tags: [quality-gate, design-review, should-fix, hold, convergence, sub-agents]
applies_when: a quality-gate Phase 4 pass leaves manual SHOULD-FIX findings the session fixes rather than approves, and the fixes need a design verdict before the receipt is minted
---

## What happened

The read-shunt baseline branch went through nine full-scope Phase 4 passes
between 2026-10-21 and 2026-10-22. Every pass reviewed the whole branch diff
again and every pass found two or three new SHOULD-FIX on code no earlier pass
had flagged — a Ceiling reviewer reading 100 files finds something each time,
so the count-derived HOLD (`> 3` unresolved SHOULD-FIX) never converged, and
iteration stopped with five recorded findings and an approve-hold decision.

On 2026-10-23 the five were fixed, and the tenth pass — again full scope,
introduced-only boundary stated — returned HOLD with four SHOULD-FIX on the
fixes. Those were applied by a Sonnet builder. Instead of an eleventh full
pass, the **same reviewer agent was resumed** (`SendMessage` to its id) with a
scoped brief: verify each of your findings on commit `<sha>`, report
`resolved` / `not resolved — why` per finding, new findings only on the lines
that commit changed, then re-issue the verdict. It returned GO in one round,
about 25 tool calls, with two cosmetic NITPICKs — against 140 k tokens and 20
tool calls for the full pass before it.

## Why it converges

- The resumed reviewer carries its own context: it knows what it flagged and
  why, so it checks resolution rather than re-deriving the file's design from
  scratch and finding new things to say.
- The brief bounds the new-finding surface to the lines the fix commit touched,
  which is also the only code the gate's "no phase after 4 edits the tree" rule
  lets this round change.
- Independence is preserved: the verdict still comes from a dispatched agent,
  not from the main context, so the receipt's `dispatch: dispatched` stays
  honest and Phase 1–3 corroboration keeps its promotion.

## The rule

After applying a Phase 4 pass's manual findings through a builder:

1. Resume the reviewer that reported them (its agent id from the dispatch
   result) rather than dispatching a fresh one; a fresh one would re-run the
   full pass and the count would move again.
2. Give it the fix commit, the per-finding list of what landed, and the two
   bounds: `resolved` / `not resolved` per finding, new findings only on the
   changed lines.
3. Apply the `gated_auto` NITPICKs it returns under the Apply Gate; record the
   advisory ones; mint the receipt on that tree.

A full pass is still the right tool for the **first** review of a diff and
after a change that reaches beyond the findings' lines. Budget rounds up front
either way: a Ceiling pass over a large diff always has something to add
(`.agents/references/finding-model.md` § *Independence Accounting*).

## Evidence

- Passes 1–9: `tasks/history.md` § `[2026-10-22] — read-shunt design findings resolved`.
- Pass 10 and the scoped re-check: `tasks/history.md` § `[2026-10-23] — read-shunt HOLD findings fixed, gate GO`; commits 31b1863, 6d2bed9, 13368f9.
