---
title: An assertion against a whole payload passes on the wrong half
date: 2026-09-08
problem_type: process
module: tests/test-living-spec-reconciliation.sh, tests/test-routine-skills.sh, tests/test-task-registry.sh
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

## Second occurrence — 2026-09-07, `tests/test-routine-skills.sh`

Same rule, a sharper variant: the needle appeared in the **success** output as
well as the failure output, so the assertion could not fail rather than merely
matching the wrong section.

Three assertions checked that a chain naming an uninstalled skill is refused
*naming the skill* (`specs/workflow-routing.md` AC4):

```sh
assert_contains "$ghost_out" "/summon-the-kraken" "the refusal names the missing skill"
```

`$ghost_out` is the whole load report. With the validator deleted the config
loads and prints `chain plan: /plan -> /summon-the-kraken -> /wrap-up-session` —
which contains the needle. Removing the gate failed only 1 of the 3 assertions.

Fixed with a refusal-only channel, which also fails safely on an empty
extraction because `assert_contains` cannot match a non-empty needle in an empty
haystack:

```sh
refusal_of() { load_report "$1" | grep '^REFUSED:' || true; }
```

All 3 now go red when the gate is removed.

## Third occurrence — 2026-09-08, `tests/test-task-registry.sh`

The sharpest variant yet: the needle was a **section header**, and the section's
own contents contained it.

Cut 2 added a `degraded:` block to `show`'s output so a provider-degraded read
cannot read as a complete one. The assertion:

```sh
assert_contains "$gh_degraded" "degraded" "show reports the degradation"
```

The limitation rendered inside that block reads *"reads degraded to local-only"*.
So deleting the `degraded:` header — the entire feature under test — left the
needle matching the payload it was meant to introduce. Mutation-probed: 0 new
failures.

Fixed by extracting the block before asserting, and moving the needle to text
that only appears inside it:

```sh
degraded_block="$(printf '%s\n' "$gh_degraded" | sed -n '/^  degraded:$/,/^  [a-z]*:$/p')"
assert_contains "$degraded_block" "reads degraded to local-only"
```
— `tests/test-task-registry.sh:1924`

Red under the same mutation after the fix.

## The generalization, after three occurrences

Each time the needle was a word the feature **names itself with**. Section
headers, status labels, and command names are the worst possible needles for
exactly this reason: the vocabulary that identifies a feature is the vocabulary
its own payload repeats.

Rule of thumb: if the needle appears in the *name* of the thing being tested,
it will appear somewhere the test does not intend. Scope the haystack first, then
pick a needle from the section's **content**, not its label.

