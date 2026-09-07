---
title: Two harnesses need two pointers — neither reads the other's project file
date: 2026-09-07
problem_type: pattern
module: AGENTS.md, .claude/project.md, .agents/skills/task-registry/scripts/registry/config.py
tags: [configuration, harness-parity, silent-fallback, claude-code, pi]
applies_when: adding a project-level declaration that a harness reads at session start
---

## The rule

`.claude/project.md` is Claude Code's project file and `AGENTS.md` is Pi's.
Neither harness reads the other. A declaration placed in one configures **one**
harness, and on the other the loader falls back to shipped defaults — silently,
because a default is a valid configuration.

Every project-level declaration is therefore two edits, and the pair needs a test
that compares them. One is not a subset of the other.

## How it showed up

Phase A of `specs/workflow-routing.md` added `docs/task-tracking.md` and declared
it in `.claude/project.md`, whose own prose then said:

> Pi reads the same line from `AGENTS.md`.

`AGENTS.md` had no such line. On Pi this repository loaded the shipped routine
chains, the shipped selectors, and the shipped claim label, with nothing
reporting a difference — and the file that would have told a reader otherwise was
the one asserting it worked.

Two things made it survive a build and a review pass: the configuration's values
were equal to the defaults, so behaviour was identical either way; and the
existing test asserted the Claude Code pointer resolved, which it did.

## The fix

Both files carry the declaration, and the test compares them rather than checking
each in isolation:

```bash
assert_file_matches "AGENTS.md" "^Task tracking instructions: " \
  "AC7: AGENTS.md carries the declaration too — Pi reads no other project file"
assert_eq "$project_pointer" "$agents_pointer" \
  "AC7: both harnesses are pointed at the SAME configuration file"
```

The equality assertion is the load-bearing one. Two independent existence checks
pass while the two files point at different targets.

## What generalises

- **A duplicated declaration needs an equality test, not two presence tests.**
  Presence checks drift apart without failing.
- Prose asserting that a second location exists is not evidence that it does.
  This one was written by the same session that omitted the file.
- The pointer cannot live in `CLAUDE.md`: `/sync` overwrites it wholesale from a
  template that cannot ship a `docs/` target, which would leave every adopter in
  the declared-but-missing state the loader refuses
  ([[a-declared-intent-with-a-broken-target-is-not-an-absent-one]]).

## Related

- [[layered-config-claude-md-template-claude-project-md-project]]
- [[a-config-equal-to-its-defaults-cannot-prove-it-was-read]] — why the omission
  produced no observable difference.
- [[the-bash-test-suite-enforces-agents-claude-byte-identical-sk]]
