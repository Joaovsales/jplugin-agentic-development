---
title: An assertion can pass because a different guard fired
date: 2026-09-04
problem_type: process
module: tests/test-sync-retirement.sh, .agents/skills/sync/scripts/sync-retire.py
tags: [testing, mutation-probe, vacuous-assertion, defence-in-depth]
applies_when: testing a validator that sits upstream of another check which would reject the same input
---

## The rule

When two guards reject the same input, asserting only "the run failed" pins
**neither**. Mutation-probe the guard you meant to test; if the suite stays green,
the assertion is measuring its downstream neighbour.

## How it showed up

A root-shape validator was tightened to reject `.claude/../`, `.claude/./` and
`.claude/*/`. The new assertions checked exit status and that the message named
the offending root — and stayed green when the fix was reverted, because a
later check (`assert_roots_present`) refuses those roots incidentally: git
normalises its output, so no template path literally begins with `.claude/../`.

The test certified a safety property it could not observe. Reverting the
traversal fix produced a green suite with whole-repo deletion one refactor away.

## The fix

Assert on the *specific* guard's message, not on the outcome both guards share:

```
assert_contains "$RUN_OUTPUT" "is not a syncable root" \
  "the root-shape validator is what rejects it, not a downstream accident"
```

Re-probed: reverting the regex now fails 3 assertions.

## What generalises

- Defence-in-depth makes tests harder to write, not easier. Every redundant guard
  is a way for an assertion to pass for the wrong reason.
- Some properties are genuinely unobservable behind a stronger guard. When that is
  true, say so in the test rather than leaving an assertion that looks like proof —
  a comment naming what it cannot distinguish is honest; silence is not.
- Two distinct failure shapes need two distinct messages, or they cannot be
  told apart from the outside.

Sibling case, different mechanism (wrong *half* of a payload rather than wrong
*guard*): [[assertion-must-be-scoped-to-the-half-it-tests]].

## Second occurrence — 2026-09-07, `tests/test-task-registry.sh` (Cut 1)

Same rule, with the two guards in *different modules* rather than stacked in one
validator — which made the substitution harder to see.

Retiring the Jira provider narrowed two independent things:

- `registry/config.py`'s `PROVIDERS` tuple, which validates a `provider =` line
  in a project's checked-in `docs/task-tracking.md`
- `registry/providers/__init__.py`'s `PROVIDER_CLASSES` dict, which validates the
  `--provider` command-line override

Three new assertions ran `doctor --provider jira` and checked the refusal named
the surviving providers. All three passed. Then the mutation:

```sh
# put 'jira' back in config.PROVIDERS only
sed -i 's/^PROVIDERS = ("github", "local")/PROVIDERS = ("github", "jira", "local")/' config.py
# -> 0 new failures
```

Zero. The assertions pinned `PROVIDER_CLASSES`, because `--provider` never
reaches `config.PROVIDERS` at all — `build_provider` raises first. The tuple
could have been left untouched and the suite would not have noticed.

That matters beyond tidiness: **a checked-in config saying `provider = jira` is
the path a downstream project actually takes**, and it was the one with no
coverage. Fixed by adding a config-file assertion that reaches the other guard:

```sh
printf '# T\n\n```ini\n[tracker]\nprovider = jira\n```\n' > "$F_RETPROV/docs/task-tracking.md"
assert_contains "$retprov_out" "expected one of: github, local" \
  "Config: the refusal enumerates the providers that ship, and jira is not among them"
```

Re-running the same mutation now fails 2 assertions.

**The generalisation.** When a change narrows a vocabulary, count the places that
vocabulary is *enforced* before writing assertions — one per enforcement point,
not one per user-visible symptom. Two guards rejecting the same word will hide
each other, and the one your test happens to reach is decided by call order, not
by which one you meant.
