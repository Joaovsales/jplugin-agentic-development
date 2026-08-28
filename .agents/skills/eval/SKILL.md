---
name: eval
description: Blinded A/B evals for skill, prompt, or workflow changes before promoting them. Use when deciding whether a new skill variant, prompt rewrite, or structural change actually improves agent behavior — and before merging any skill edit into .agents/skills/.
argument-hint: "[what changed] [vs what]"
harness: universal
---

# /eval — Blinded Skill Evaluation

## Overview

Evals test how a change affects agent behavior **before promoting it**: a new skill
variant, a structural change, a prompt tweak. The failure mode is the **observer
effect** — an agent that knows it is being evaluated behaves differently, so
candidates must run blind. "Looks smart once" is not evidence.

Adapted from poteto's [pstack](https://github.com/cursor/plugins/tree/main/pstack)
`eval` playbook, translated from Cursor to pi's sub-agent system.

## The Iron Law

```
THE CANDIDATE NEVER KNOWS IT IS BEING EVALUATED
```

## Non-negotiables for blinding

- No `eval`, `test`, `judge`, `experiment`, `rubric`, `score`, `compare`,
  `benchmark`, `candidate`, or `arena` in any directory, file, or prompt the
  candidate sees.
- The candidate prompt looks like an organic user request. State the goal, not
  the meta. "build me a small todo cli" — not "show me how you follow the
  skill chain".
- No chain-eliciting cues. Don't ask the candidate to list which skills,
  principles, or files it applied; that meta-prompt inflates citation behavior.
  Ask for design notes generally and grade chain-following from code shape,
  never self-report.
- Sanitize directory and slug names. Use project-shaped names a user might
  pick, not labels like `candidate-1` or `agent-a`.
- Don't tell the candidate other candidates exist.
- The judge can know it's judging but sees outputs by sanitized label only,
  never by model name.
- Comparing two variants: **one judge scores both sets in a single pass on one
  scale**, blind to which set each came from. Two judge runs with different
  prompts don't compare — the calibration drifts.

## Steps

1. **Frame.** State what variant is under test and what behavior counts as
   success. Write the rubric (3–6 concrete criteria) for the judge only. Hold
   it back from candidates.
2. **Set up sanitized environments.** Per-candidate managed worktree
   (`worktree: true` on the workflow/child) with the variant in place. Plant
   any context an organic task would have: a project skeleton, the skills the
   candidate would naturally read.
3. **Author one organic prompt.** What a user would type. No leakage of what
   is being measured.
4. **Spawn N parallel candidates** via `pi-subagents` (`runs.all` inside one
   workflowScript), one per variant, each in its own sanitized worktree. Same
   prompt to each. Use the build tier (`qwen3-coder-next`) unless the change
   specifically targets a different tier.
5. **Spawn one blinded judge** on a **different model family** (reasoning
   tier: `deepseek-v4-pro`). Judge sees outputs by sanitized label and the
   rubric, never a model name.
6. **Verify the chain from transcripts, not self-report.** Read each
   candidate's session transcript under `.pi/agent/sessions/` for its
   worktree. Look at which files each candidate actually opened. Citing a
   skill is not reading it, and reading it is not applying it. Grade
   chain-following from the files it really read plus the shape of the code,
   never from the candidate's own claims.
7. **Read every candidate output yourself**, end to end. Compare to the
   judge's verdict. Disagreement means the judge is biased or the rubric is
   ambiguous — fix the rubric and re-judge before trusting a result.
8. **Decide.** Promote the variant only on a clear, reproducible lift. On an
   ambiguous result, raise N (repeat count) before raising confidence.

## Reply format

variant under test · rubric · per-candidate notes · judge's verdict · your
synthesis · recommendation (promote / reject / re-run with changes).

## Anti-patterns

| Smell | Why it fails |
|-------|--------------|
| Judging variants in separate judge runs | Calibration drift; scores aren't comparable |
| Asking candidates which skills they used | Inflates citation, measures compliance theater |
| Grading from candidate self-report | Verification theater — grade from transcripts and code shape |
| Eval-aware directory names (`eval-runs/candidate-1`) | Breaks blinding the moment the candidate looks around |
| One run, one verdict | Single-run variance can exceed real skill lift; repeat before deciding |
