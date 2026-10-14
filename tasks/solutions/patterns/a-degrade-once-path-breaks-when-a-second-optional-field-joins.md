---
title: A degrade-once path breaks when a second optional field joins it
date: 2026-10-13
problem_type: pattern
module: .agents/skills/task-registry/scripts/registry/providers/github.py § _issue_json, OPTIONAL_ISSUE_FIELDS, linked_pr_exclusion_available
tags: [degradation, optional-fields, gh-cli, change-amplification, task-registry, design-review]
applies_when: adding a member to a list of optional fields, capabilities or flags whose handling was written while the list had one entry
---

`OPTIONAL_ISSUE_FIELDS` was a tuple that looked general, but everything that
handled a missing field was written for its one member:

- `_issue_json` dropped the rejected field and retried exactly once.
- The degradation note named that field and its gh version.
- `linked_pr_exclusion_available()` checked that field alone.

#146 added `stateReason` as the second member and changed none of the three.
The design review (HOLD, 2026-10-13) found the result. A gh older than both
fields rejects the first one, drops it, retries, and the retry raises on the
second. Every read then crashes, the outcome the field's own comment calls
wrong. The old test modelled only one missing field, so it stayed green.

The fix generalized each place that handles a missing field:

- `_issue_json` loops, dropping each rejected optional field in turn. The loop
  ends because every pass returns, re-raises a field already dropped, or drops
  a new one (`github.py:640`).
- The capability is false when any field it depends on is missing
  (`github.py:550`). A missing `stateReason` can then never be read as "not
  reopened".
- The test makes gh reject both fields, then only the second one
  (`tests/test-task-registry.sh:900`, `:904`).

The general rule: before adding a member to a list that was written with one
entry, find everything that reads or handles that list. Make each one handle
any member, or split the list. A test that removes only one member at a time
cannot catch this.

The same review flagged a near relative. `closing_references` decided "is this
issue in this repository" by checking whether a display label started with
`#`, which ties a routing decision to a message format. Routing now uses the
node's owner and name (`_node_repo`, `github.py:573`), and the label is built
only for the message.

Related: [../tooling/gh-closing-pr-references-carry-no-pr-state.md](../tooling/gh-closing-pr-references-carry-no-pr-state.md)
