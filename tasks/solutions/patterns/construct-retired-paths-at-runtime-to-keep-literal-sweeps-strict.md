---
title: Construct retired paths at runtime to keep literal-reference sweeps strict
date: 2026-08-13
problem_type: pattern
module: .claude/hooks/session-start.sh
tags: [migration, grep, sweeps, detection, retired-files]
applies_when: a spec bans literal references to retired file paths (verified by grep) but live code must still detect those same paths
---

## The tension

The M3 cutover spec required two things that look mutually exclusive:

1. A sweep AC: no file outside `tasks/archive/` and `specs/` may reference
   the retired stores literally — enforced by a strict
   `grep -rlF "tasks/memory.md" ...` in tests/test-doc-conventions.sh.
2. Detection: `session-start.sh` and `/sync` must *notice* an unmigrated
   repo, i.e. check whether those very files exist.

## The pattern

Build the retired filenames at runtime instead of writing them literally:

```bash
for OLD_STORE in memory lessons bugs; do
  [ -f "tasks/${OLD_STORE}.md" ] && UNMIGRATED=1
done
```

(.claude/hooks/session-start.sh:110-111; `/sync` Step 6.5 uses brace
expansion the same way.) The literal-grep sweep stays allowlist-free — any
new literal reference anywhere in either skill tree fails the suite — while
the detection logic keeps working.

## Same pattern, another sweep

The `/wrap-up-session` § *Shortcut ledger* grep sweeps the whole repository
for `TODO(shortcut):` comment markers. A test that writes literal sample
markers (a hash comment followed by the tag) to check the pattern becomes a ledger row
itself, tagged `no-trigger`. tests/test-doc-conventions.sh:1428-1429 avoids that
in two ways. It builds the samples from `tag='TODO(shortcut):'`, and it runs
them through the pattern extracted from the skill's own line instead of a copy.
That way the test checks the regex that ships (2026-10-09).

## Trade-off

The rejected alternative (literal paths + a sweep allowlist) is more
grep-discoverable: searching for the old filename finds the detector.
Constructed paths hide the detector from that search, so this document and a
code comment carry the pointer instead. Chose strictness because an
allowlist rots — every future exception lands in it and the sweep decays
into documentation.
