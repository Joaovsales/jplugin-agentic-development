---
title: An assertion against a whole payload passes on the wrong half
date: 2026-09-02
problem_type: process
module: tests/test-living-spec-reconciliation.sh, .agents/skills/wrap-up-session/scripts/spec-reconcile.py
tags: [testing, vacuous-assertion, mutation-probe, json-payload]
applies_when: asserting a substring against a command's full output when that output has more than one section
---

## The rule

Assert against the **section** the behavior lives in, not the whole payload. When
a command emits several sections that share vocabulary, a bare substring needle
matches whichever section is cheapest — usually the one that is true by
construction — so the assertion stays green through exactly the regression it was
written to catch.

Parse the output and scope the needle, or make the needle unique to the section.

## What happened

`spec-reconcile.py discover --json` emits two halves: `changeset` (every changed
path) and `candidates` (the specs those paths selected, each with `reasons`). Two
assertions checked that a **rename** selects a spec through its *old* path and that
a **deletion** still selects the spec documenting it:

```sh
assert_contains "$DISC" 'src/renamed_from.py' "a rename selects the spec via its OLD path"
assert_contains "$DISC" 'src/deleted.py'      "a deletion still selects the spec"
```

Both paths appear in the `changeset` half unconditionally — the change set lists
them because they changed, whether or not matching ever consulted them. The
assertions could not fail. Deleting the old-path branch from `Change.match_targets`
left the suite green.

Fixed by extracting only the candidates' `reasons` and asserting against those.

## Proof it was vacuous, and proof the fix is not

The distinction is only visible under mutation. With `match_targets` reduced to
`return (self.path,)`:

- before the fix: 0 new failures — the assertions were decoration
- after the fix: 2 new failures — they now bite

A passing assertion is not evidence until a mutation that should break it does.

## How to apply

- When output has named sections, scope the assertion to one. For JSON, parse it;
  a one-line `json.load` plus a join is cheaper than a false green.
- Write the needle so it *cannot* appear in a section that is true by
  construction. If it can, the assertion is measuring the wrong thing.
- Mutation-probe every assertion that guards a selection or filtering rule.
  Those are the ones whose inputs also appear in the output.

Related: [[baseline-must-precede-tree-edits]]
