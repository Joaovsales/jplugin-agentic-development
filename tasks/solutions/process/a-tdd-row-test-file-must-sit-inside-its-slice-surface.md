---
title: A TDD row's test file must sit inside its slice's Surface
date: 2026-10-16
problem_type: process
module: /slice § Build Order; .agents/skills/slice/scripts/slice.py § validate
tags: [slice, surface, build-order, plan-block, tdd]
applies_when: /slice writes a plan block whose `[ ] TDD: <test-file> § <section>` rows name a test file, and a later slice adds a section to a test file an earlier slice created
---

## A TDD row's test file must sit inside its slice's Surface

**Claim** (this session observed, 2026-10-16): the HyperFrames plan's slice 4
("Skill text and table") had Surface `.agents/skills/design-stack/SKILL.md,
.agents/skills/build/SKILL.md, README.md` while its TDD row targeted
`tests/test-design-stack-video.sh § docs`, a file slice 2 created. `slice.py
validate` checks surface overlap, cycles and `implementation_paths` membership
(`.agents/skills/slice/SKILL.md` § Propose step 1) and did not refuse it; the
mismatch surfaced only when slice 4 became ready and its agent would have had to
report a `[SURFACE]` line for the very file its row named.

**Rule**: when sizing, put every test file a slice's TDD rows name into that
slice's Surface. Two slices appending sections to one test file is allowed as
long as the later one is `blocked-by` the earlier one (ordered overlap is legal
for `validate`). On discovery at build time, fix the plan in place — widen the
Surface cell in § Build Order, re-run `validate`, re-run `ready` — rather than
letting the agent work outside its surface.

**Consequence of ignoring it**: the slice's own verification cannot be written
inside its declared surface, `slice.py check` reports the test file as
`undeclared`, and the handover's Surface line is noise.

Related: [a-slice-verify-command-misses-repo-wide-doc-guards](a-slice-verify-command-misses-repo-wide-doc-guards.md),
[slice-check-reports-sibling-slices-in-a-parallel-build](../tooling/slice-check-reports-sibling-slices-in-a-parallel-build.md).
A validator check for this is proposed as a follow-up task (session chip, 2026-10-16).
