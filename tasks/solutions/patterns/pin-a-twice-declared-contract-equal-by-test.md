---
title: When a contract is declared twice on purpose, pin the two copies equal by test instead of deleting one
date: 2026-09-16
problem_type: pattern
module: tests/test-go-lanes.sh, .agents/skills/go/SKILL.md, .agents/skills/go/lanes/, tests/test-memory-maintain-doc.sh, .agents/skills/memory-maintain/SKILL.md
tags: [static-pins, drift, information-leakage, prose-contract, skills, cross-references]
applies_when: a design review flags the same list or contract written in two places — a summary table an agent reads first and the source it summarises — and removing either copy would cost the reader the overview or the detail; or skill prose cites a heading, table row, command or threshold that another file owns
---

## The pattern

A summary row and the thing it summarises are one fact in two places, which
APOSD calls information leakage: edit one and the other drifts. The reflex fix
is to delete the summary. When the summary is what a reader uses to *choose*
(a lane table, a skills table, a routing matrix), deleting it moves the
decision cost onto every reader. Keep both and make the test suite the single
owner of their agreement:

1. Extract the tokens from both sides with the **same extractor**, so the two
   readings cannot disagree on what counts as a token.
2. Assert the two token sequences equal, in order, for every row.
3. Accept the corollary convention: the summarised side may carry no token the
   source lacks, and vice versa, or the pin goes red for a reason that is not
   drift.

## This session

`/go`'s lane table restates each playbook's skill chain in a *Chain* column
(`.agents/skills/go/SKILL.md:56-64`), and the playbooks' numbered steps are the
source (`.agents/skills/go/lanes/*.md`). The design reviewer flagged the
double declaration as a SHOULD-FIX. The build kept the column — the spec's AC1
requires it and it is how an agent picks a lane — and added the pin
(`tests/test-go-lanes.sh:121-137`): `skill_tokens` runs over the table row and
over the playbook, and `assert_eq` compares the joined sequences per lane in
both skill trees.

The corollary bit immediately: `investigate.md`'s *Reply* said a goal could be
"re-routed by a new `/go`", which put a `/go` token in the playbook that the
table row does not carry, and the pin failed. The sentence was reworded to
"goes back through the front door" — the convention is now that a playbook
never names `/go`, and the pin enforces it as a side effect.

## A pointer is a copy too (2026-10-13)

The same pin applies when one side is a single value another file owns. A pin
on a literal copy checks the copy against itself: the owner changes, the
dependent prose goes stale, and the pin still passes. `/memory-maintain` Phase 2
cites `/learn` Step 4 by heading (`.agents/skills/memory-maintain/SKILL.md:99`).
Its pin extracts the live heading (`tests/test-memory-maintain-doc.sh:29`) and
asserts the citation carries it (`:32`), so renaming Step 4 fails the test
instead of leaving a dead pointer. The same file already read its history-count
command out of `.agents/hooks/session-start.sh` (`:9`, asserted at `:19`). The
dispatched design review found the counter-example in the same block. The High
band "4 or 5 of the five dimensions" is pinned as a literal (`:36`), while its
owner is `/learn`'s `| High | 4–5 |` row (`.agents/skills/learn/SKILL.md:56`). It
was reported, not applied, on the branch stacked on #168.

- Extract with `tr -d '\r' <owner | sed -n 's/^…\(value\)…$/\1/p'` (the `tr`
  matters on a CRLF checkout) and assert the result non-empty, so a renamed
  source fails loudly instead of yielding an empty needle.
- Pin a named rule inside the section that defines it (`awk` the section out,
  `:42`), so the name and its definition move together.
- Kill one mutant on a scratch copy before trusting the pin.

## When not to use it

If the summary adds nothing a reader acts on, delete it — the pin is for the
case where both copies earn their place. And a pin only catches drift in what
the extractor sees; prose that changes meaning without changing tokens still
needs a human.

Related: [write skill prose so the static guards can read it](../conventions/write-skill-prose-so-the-static-guards-can-read-it.md) — the line-shape rules the same guards impose.
