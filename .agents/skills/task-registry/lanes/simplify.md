---
routine: consumer
selects: simplify
cues: simplify, make it simpler, one home per rule, too long, trim
ends: ready PR whose body quotes the before and after proof, Behavior changes and Simplified
---
# Lane: simplify

Runs when an issue carries the `simplify` label, or the goal asks to make
something simpler, give a rule one home, or trim what is too long. A
simplification is behavior-preserving and sized to one review; a significant
one is filed `design-decision` and belongs to `plan`. The scheduled entry is
`/make-it-simpler --unattended`, whose discovery files the task before the spine
selects it.

1. `/make-it-simpler <ref>` — before-proof, scope, and a spec whose § Decisions carries the safe-moves practices; a scope stop ends the run here — **non-skippable**
2. `/plan <spec>` — with the overrides `/make-it-simpler` owns: no interview unattended, no build prompt, `/build` in place
3. `/build` — the TDD rows the plan wrote, with no slice filing — **non-skippable**
4. `/quality-gate` — structural, anti-pattern, and APOSD passes, with the declared `Behavior changes:` as intent (runs inside the build's Phase 3; the row records where it ran) — **non-skippable**
5. `/wrap-up-session` — the PR body quotes the before-proof and the after-proof from the same commands, a `Behavior changes:` section (a list or `none`) and a `Simplified:` line — **non-skippable**

## Reply

The before and after proof side by side, the `Simplified:` line, the declared
behavior changes, and the PR URL — or the scope-stop line when step 1 stopped.
