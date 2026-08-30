---
name: eval
description: "Blinded A/B evaluation of a skill, prompt, or workflow change before promoting it. Candidates run in sanitized worktrees on organic prompts and never learn they are being measured; grading comes from session transcripts, not self-report. Two runnable modes: triggerability (does the harness route to this skill at all) and variant lift (does variant A beat variant B). Use before merging a skill edit, when a skill seems never to fire, or when deciding whether a rewrite actually helped. Triggers on: 'does this skill even fire', 'A/B this prompt', 'did the rewrite improve anything', 'evaluate my skills', 'run an eval'."
argument-hint: "[what changed] [vs what]"
harness: universal
---

# /eval — Blinded Skill Evaluation

## What this does

Answers one question with evidence: **does this change alter agent behavior in
the direction claimed?**

A run spawns N candidate agents on an organic-looking prompt, each in its own
sanitized worktree, and grades what they did from their session transcripts. The
failure mode it defends against is the observer effect — an agent that knows it
is being measured behaves differently — so no candidate is ever told it is in an
eval.

Use it before merging a skill edit, when a skill seems never to fire, or when
deciding whether a rewrite actually helped.

## The Iron Law

```
THE CANDIDATE NEVER KNOWS IT IS BEING EVALUATED
```

## What is measurable here

**Two questions, and a third this harness cannot answer.** Designing a run
against the third produces a number that looks like lift and means nothing.

| Question | Mode | Status |
|----------|------|--------|
| Does the harness route to this skill from an organic prompt? | A — triggerability | runnable |
| Does variant X of a skill outperform variant Y? | B — variant lift | runnable |
| Does having the skill beat not having it? | presence/absence | **not available** |

Presence/absence is unavailable because a skill cannot be removed from a
candidate's reach: the roster is a spawn-time snapshot, and `install.sh` puts a
copy of every skill in the user's global skills directory, so deleting the repo
copy ablates nothing. Deleting the global copy would break every other project
on that machine. If presence/absence lift is genuinely required, the only honest
routes are a machine with no global install, or Mode B against a deliberately
gutted variant — both stated as such, never reported as ablation.

Say "not measurable here" and stop. A proxy that measures something else is
worse than no number, because it gets quoted.

## Blinding non-negotiables

- No `eval`, `test`, `judge`, `experiment`, `rubric`, `score`, `compare`,
  `benchmark`, `candidate`, or `arena` in any directory, worktree, file, or
  prompt the candidate sees. Name worktrees after project-shaped slugs.
- The candidate prompt is an organic user request. State the goal, not the meta.
- No chain-eliciting cues. Never ask a candidate which skills or principles it
  applied — that inflates citation and measures compliance theater. Grade from
  the transcript.
- Never tell the candidate other candidates exist.
- The judge may know it is judging, but sees outputs by sanitized label only —
  never a model name, never a variant name.
- One judge scores both variants in **one pass on one scale**. Two judge runs
  drift in calibration and their scores do not compare.
- Write the rubric (3–6 concrete criteria) **before** spawning anyone, and hold
  it back from candidates.

## Preconditions belong in the prompt, not the repo

Managed worktrees are cut from the remote default branch, so planted fixture
state never reaches a candidate. A skill gated on open `tasks/todo.md` items, a
failing test, or review comments therefore has nothing to fire on, and scores a
false "never fired".

Carry the precondition **in the prompt**: paste the failing test output, the
plan, the reviewer's comments. A real user pastes exactly that, so the prompt
stays organic and the fixture problem disappears. Never name a file the worktree
does not contain — the candidate stops and asks, and the run is lost.

## Mode A — triggerability

Measures the real router, and is the cheapest useful eval in this repo.

1. For each skill under test, write one organic prompt that its `description`
   claims to cover, with any precondition pasted inline.
2. Spawn one candidate per prompt per repetition, each in its own worktree.
   **N >= 2** — a single miss is variance, not a verdict.
3. Add a no-push clause to every prompt. Candidates can reach the real remote:
   two separate runs shipped a live PR and a live branch before this was
   guarded. For push-shaped asks, point `origin` at a throwaway bare repo.
4. Grade with `scripts/grade-skill-loads.sh` (below). Three outcomes per run:
   `FIRED`, `MISROUTED` (a different skill loaded — record which), `NONE`.
5. A misroute is a **description defect**, not a candidate failure. Fix the
   description; do not touch the prompt until the description has been read.

`references/probe-recipe.md` carries the prompt recipe and a run skeleton.

## Mode B — variant lift

Both variants are present on disk; they differ in content, so nothing has to be
removed. Use it for description rewrites and body rewrites alike.

1. Put variant A and variant B on **two branches pushed to the remote**, or two
   differently-named skills in one branch. Worktrees are cut from the remote
   default branch, so an unpushed variant never reaches a candidate.
2. Same organic prompt to both arms, N >= 2 per arm.
3. Interleave both arms' outputs into **one** judge prompt under sanitized
   labels. Judge on a stronger tier than the candidates (Ceiling judging
   Builder); cross-vendor blinding is not available in-harness.
4. Report cost beside lift. A variant that wins by 5% for 3x the tokens lost.

## Grading — transcripts, not self-report

```
.agents/skills/eval/scripts/grade-skill-loads.sh <transcript-dir> [skill]
```

The transcript directory is the workflow's own, one `agent-<id>.jsonl` per
candidate. The script counts genuine `Skill` tool-use blocks and nothing else.

A bare string match on `SKILL.md` is not evidence of a load — a candidate's own
test output prints those filenames. Citing a skill is not reading it, and
reading it is not applying it: grade *following* from the shape of the work.

Then read every candidate output end to end yourself and compare with the
judge. Disagreement means the rubric is ambiguous or the judge is biased — fix
the rubric and re-judge before trusting the result.

## Reply format

what is under test · mode · rubric · per-run grades with transcript evidence ·
judge verdict · your synthesis including every disagreement · cost · one
recommendation (promote / keep / rewrite / delete / not measurable here).

## Anti-patterns

| Smell | Why it fails |
|-------|--------------|
| Asking the candidate to delete the skill as the ablation | Not an ablation. A capable candidate checks, finds the directory tracked and referenced, and refuses — so the skill stays present and the run measures nothing. It also trips safety classifiers. |
| Reporting presence/absence lift where a global install exists | The global copy still routes. The number is noise wearing a label. |
| Naming a fixture file the worktree cannot have | The candidate stops and asks. Scored as "never fired", it is a broken fixture. |
| Grading "never fired" without satisfying the skill's own precondition | Same defect, cheaper to miss: no open task, no failing test, no review comments means nothing to fire on. |
| Telling the candidate its remote is safe to push to | It will verify. If `origin` can reach the real host, treat a push as inevitable and neuter the remote yourself. |
| Judging variants in separate judge runs | Calibration drift; the scores are not comparable. |
| Asking candidates which skills they used | Inflates citation, measures theater. |
| One run, one verdict | Single-run variance routinely exceeds real lift. |
| Comparing a full sweep against a subset chosen for having failed | Selection bias — the subset was selected on the outcome, so the difference proves nothing. |
| Eval-aware directory names | Blinding dies the moment the candidate looks around. |

## Provenance

Adapted from pstack's `eval` playbook — `skills/poteto-mode/playbooks/eval.md`
in `cursor/plugins`, revision `68836ddaf5697224520f1847d90cdb90ca8babaa`. The
blinding non-negotiables and the transcript-over-self-report grading rule are
upstream's. The two-mode scope, the precondition-in-the-prompt rule, and
`grade-skill-loads.sh` are local additions for a sub-agent harness that cannot
ablate a skill.

The upstream MIT notice is bundled as `LICENSE.pstack`; repository-level
provenance is in `THIRD_PARTY_NOTICES.md`.
