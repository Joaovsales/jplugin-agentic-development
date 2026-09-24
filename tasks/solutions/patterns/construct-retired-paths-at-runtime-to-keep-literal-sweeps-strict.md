---
title: Construct retired paths at runtime to keep literal-reference sweeps strict
date: 2026-08-13
problem_type: pattern
module: .agents/hooks/session-start.sh (formerly .claude/hooks/session-start.sh; moved in the #156 surface retirement)
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

(originally .claude/hooks/session-start.sh:110-111, now
`.agents/hooks/session-start.sh` since the #156 surface retirement, line
unverified since; `/sync` Step 6.5 uses brace
expansion the same way.) The literal-grep sweep stays allowlist-free — any
new literal reference anywhere in either skill tree fails the suite — while
the detection logic keeps working.

## Trade-off

The rejected alternative (literal paths + a sweep allowlist) is more
grep-discoverable: searching for the old filename finds the detector.
Constructed paths hide the detector from that search, so this document and a
code comment carry the pointer instead. Chose strictness because an
allowlist rots — every future exception lands in it and the sweep decays
into documentation.
