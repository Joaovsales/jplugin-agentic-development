---
title: An enforced-prose cue on a line a test pins in that same file is a pin, not bulk
date: 2026-10-20
problem_type: process
module: .agents/skills/make-it-simpler/scripts/signals.py, .agents/skills/make-it-simpler/references/lens.md
tags: [make-it-simpler, signals, false-positive, test-pins, simplify-routine]
applies_when: deep-reviewing `enforced-prose` or `duplicate-rule` cues from `signals.py rank` before filing a simplify task
---

## The rule

Before filing an `enforced-prose` or `duplicate-rule` candidate, grep `tests/`
for the matched needle and check **which file** the assertion reads. When the
test asserts the sentence inside the candidate file itself, the prose is what the
test pins: deleting it breaks the test, and repointing it is a contract change,
not a simplification. Drop the cue. Only a needle asserted against a *different*
file, or a test that no longer reads the candidate, makes the prose redundant.

## What happened

The 2026-10-20 `simplify` run ranked eight `enforced-prose` cues at the top
(`AGENTS.md:16` scored 1940). Each needle — `never builds and never files`,
`must never resolve to the same model`, `Task tracking instructions`, the repo
name — was asserted by a `tests/*.sh` file against that same document. The
`duplicate-rule` hits for the finding-model resolution order (quality-gate,
system-design-planning, software-design-expert-review) and for
`A refusal is not a test result.` (build, wrap-up-session) are also pinned per
file on purpose (`tests/test-review-context.sh` § 8, D19;
`tests/test-doc-conventions.sh`). None was filed. The run shipped the one
fact-signal candidate instead: a `citation-drift` in `/brainstorm` (#326).
