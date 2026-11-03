---
title: When a contract is declared twice on purpose, pin the two copies equal by test instead of deleting one
date: 2026-10-19
problem_type: pattern
module: tests/test-go-lanes.sh, .agents/skills/go/SKILL.md, .agents/skills/go/lanes/, tests/test-memory-maintain-doc.sh, .agents/skills/memory-maintain/SKILL.md, tests/test-solutions-schema.sh
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
Its pin extracts the live heading (`tests/test-memory-maintain-doc.sh:33`) and
asserts the citation carries it (`:38`), so renaming Step 4 fails the test
instead of leaving a dead pointer. The same file already read its history-count
command out of `.agents/hooks/session-start.sh` (`:9`, asserted at `:19`).

**A translation copies every input it rests on (2026-10-14).** Phase 2 restates
the old ">70%" threshold as Step 4's High band, and that conclusion has three
inputs from `/learn`: the band (`| High | 4–5 |`,
`.agents/skills/learn/SKILL.md:56`), the scale (five dimensions per track), and
the cross-track cap that makes "a pair on different tracks never merges" true.
On PR #287, three review rounds in a row each found one more unpinned input: the
band was a literal, then the dimension count, then the cap. Each was fixed only
after a separate review. The pins now read the band (`:34`) and count each
track's cells (`:35`, asserted at `:42`), and the cap phrase is one constant
(`tests/test-solutions-schema.sh:193`) shared by Step 4's three copies and
Phase 2 (`:205`).

- Extract with `tr -d '\r' <owner | sed -n 's/^…\(value\)…$/\1/p'` (the `tr`
  matters on a CRLF checkout) and assert the result non-empty, so a renamed
  source fails loudly instead of yielding an empty needle.
- Pin a named rule inside the section that defines it (`awk` the section out,
  `:42`), so the name and its definition move together.
- Kill one mutant on a scratch copy before trusting the pin.
- Before pinning a restatement, list every value it depends on: the number, its
  scale, and any rule the conclusion follows from. Pin all of them in one pass,
  and mutate each one, so review does not find them one round at a time.
- When the owner's value already has a guard that loops over its copies, add the
  new copy to that guard's constant instead of writing a second extractor.

## When not to use it

If the summary adds nothing a reader acts on, delete it — the pin is for the
case where both copies earn their place. And a pin only catches drift in what
the extractor sees; prose that changes meaning without changing tokens still
needs a human.

Related: [write skill prose so the static guards can read it](../conventions/write-skill-prose-so-the-static-guards-can-read-it.md) — the line-shape rules the same guards impose.

## The oracle is a file, not a literal (2026-10-19)

The diagram-skill build pinned one tool version in three homes that ship
separately — `install.sh` (tag and commit), the `/diagram` resolver
`.agents/skills/diagram/scripts/archify.sh` (tag, for the install command it
prints) and the `archify` entry of `.github/upstreams.json` (commit as
`baseline`, tag as `ref`). The first tests pinned them equal by writing the tag
and commit as literals into three test files, which made a bump a six-file edit
and let the tests report the bump itself as the defect (design review,
2026-10-19). The repair: the tests read `ref` and `baseline` from the registry
(`"$TEST_PYTHON" -c 'import json; …'` in `tests/test-upstream-drift.sh`
§ installed, `tests/test-install-sh.sh` § archify and
`tests/test-diagram-skill.sh` § resolver) and assert every other home against
it, including the README § Sources link and the notices section. A bump now
edits the three consumer files and the notices, and no test. One copy is still
the oracle; the rule is that the oracle is a file the build already owns, never
a literal the test carries.
