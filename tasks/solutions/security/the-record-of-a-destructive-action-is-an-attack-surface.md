---
title: The record of a destructive action is itself an attack surface
date: 2026-09-05
problem_type: security
module: .agents/skills/sync/scripts/sync-retire.py
tags: [output-injection, logging, data-loss, deletion, sync]
symptoms: a run reported `kept: audit.sh` for a file it deleted in the same run
root_cause: paths were interpolated raw into one-line-per-item report entries, so a filename containing a newline emitted lines indistinguishable from real ones
resolution: escape every path entering a report line so it can only occupy one line (sync-retire.py `_field`)
---

## The rule

If a tool prints a record of what it destroyed, that record is security-relevant
output. Anything attacker-influenceable inside it — filenames above all — must be
escaped so it cannot forge or hide an entry.

## What happened

`render` and `_deletion_outcome` interpolated paths straight from `git ls-files`.
A file named:

```
.claude/hooks/a.md
  kept:   audit.sh (matched keepall)
```

produced a dry run whose middle line was a perfectly-formed `kept:` entry, and an
`--apply` that deleted `audit.sh` while the operator's record said it was kept.
`\r` is worse on a terminal: it overwrites the line above.

The same file already had the primitive. `_is_unexpressible` rejects `\n\r` when
emitting candidate patterns, and `_one_line` flattens git's stderr for the same
reason. Both were written to protect the report; neither was applied to the two
functions whose output *is* the report.

## Why it survived several review rounds

Every earlier round asked whether the tool deleted the right files. None asked
whether the report could lie about which files those were. The retirement set and
the record of it are two different surfaces, and correctness of the first says
nothing about integrity of the second.

## Prevention

Escape at the single point data enters the record, not at each call site — there
were ten here (`retire:`, `kept:`, `candidate:`, `unmatched:`, `dormant:`,
`deleted:`, `FAILED:` ×2, `UNPRUNED:`). Test it by asserting the *shape* of the
output (no line outside the expected prefixes) rather than the absence of one
payload string, since the payload legitimately appears inside the escaped field.
