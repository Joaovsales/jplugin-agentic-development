---
title: Shape validation cannot catch a membership error
date: 2026-09-05
problem_type: pattern
module: .agents/skills/wrap-up-session/scripts/routine_branch.py
tags: [validation, error-design, serialization, typos, aposd]
applies_when: A function validates an identifier before serializing it, and a closed set of valid identifiers exists
---

## The gap

`format_routine_branch` validated its routine name against `^[a-z][a-z-]*$` and
documented the ValueError as preventing a branch that "would not parse back".

`format_routine_branch("plna", 90, "x")` passes that regex. It yields
`routine/plna/90-x`, which parses *perfectly* — so nothing errors anywhere. Wrap-up
reads the routine as "not `plan`" and opens a **ready** pull request where the
contract requires a draft. The typo is invisible until a human wonders why a
proposal was marked ready to merge.

Shape was never the invariant. **Membership** was.

## The rule

When a closed set of valid values exists, validate against the set. A regex over
the shape of an identifier accepts every typo that happens to be well-formed, and
well-formed typos are the common case — they are what typos of an identifier
*are*.

```python
def format_routine_branch(routine, issue, slug, known=CONTRACT_ROUTINES):
    if routine not in known:
        raise ValueError(...)
```

Pass the set as a defaulted parameter rather than importing it, so the module
keeps its stdlib-only property and a caller adding a value says so explicitly.

## The stronger version

Where the real contract is a round trip, assert the round trip instead of
proxying it with input checks:

```python
if parse_routine_branch(branch) != (routine, issue):
    raise ValueError(f"refusing to emit {branch!r} — it does not parse back")
```

That one check subsumed three input guards, one of which was unreachable. Check
the property you actually mean; input validation is a proxy for it, and proxies
drift.

## Corollary — not every failure deserves an exception

The same function raised on a slug that normalized to nothing. That one was
defined out of existence with a fallback: a CJK or emoji-only issue title should
not halt a routine at step 3, because the issue *number* identifies the branch and
the slug is decoration. Separate the errors that cannot be caught downstream
(raise) from the ones that are merely ugly (absorb).
