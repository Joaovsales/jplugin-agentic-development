---
title: A caller that restates its callee's output format makes the callee optional
date: 2026-09-21
problem_type: pattern
module: skill invocation chains — .agents/skills/brainstorm/SKILL.md Step 3 → /grilling
tags: [skill-chain, information-hiding, eval, triggerability, aposd]
applies_when: one skill invokes another and the caller's prose also describes what the callee's output looks like
---

## The rule

When a caller skill spells out the callee's output format, the model has
everything it needs to produce that output **without loading the callee**. The
chain then holds only by habit, and every rule that lives solely in the callee
(its opt-out, its end condition, its fact-versus-decision split) is silently
skipped on the turns that do not load it. State the *invocation and the intent*
in the caller; leave the *format and the rules* to the callee. If the caller must
show the shape, keep it to a pointer ("in `/grilling`'s round format"), not a
specification.

## This session

`brainstorm/SKILL.md:48` restates the round: "`❓` / `➡️` format: the whole
frontier at once, numbered, a recommended answer on every question", and the Key
Principle at `brainstorm/SKILL.md:170` restates it again. The `/eval` Mode A run
(`tasks/e2e-log.md:1262`) fired `jplugin:brainstorm` in 6/6 organic prompts and
`jplugin:grilling` in 5/6; the MISROUTED session ran Step 3 inline from the
brainstorm text, six `❓` questions with a `➡️` each, and never loaded the
primitive. The output looked right. The opt-out line and the empty-frontier end
condition, which live only in `grilling/SKILL.md:80-84`, were never in context.

The dispatched design review of the same diff flagged the restatement as
information leakage (reported, not applied; the format was left in the caller
so a session that fails to load the primitive still asks in rounds). That is the
trade: a caller robust to a missing callee is a caller that makes the callee
optional. Choose deliberately and measure with `/eval` Mode A rather than assume
the chain holds.

## What the static guard pins

`tests/test-skill-invocation-chain.sh:189-192` asserts the caller *names*
`/grilling`. It cannot assert the callee *loads* — only a transcript-graded probe
can (`.agents/skills/eval/scripts/grade-skill-loads.sh`).

## Related

- [../conventions/write-skill-prose-so-the-static-guards-can-read-it.md](../conventions/write-skill-prose-so-the-static-guards-can-read-it.md)
  — the guards read tokens, and a token in the caller is not a load of the callee.
- [a-skill-write-needs-a-concrete-trigger-and-a-visible-line.md](a-skill-write-needs-a-concrete-trigger-and-a-visible-line.md)
  — the other behaviour of this build that only an e2e run could see.
