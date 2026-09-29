---
title: An artifact keyed by commit must be read by the commit that produced it, not HEAD
date: 2026-09-29
problem_type: pattern
module: .agents/skills/wrap-up-session/scripts/publish_evidence.py, .agents/skills/verify-evidence
tags: [wrap-up, e2e-evidence, short-sha, defaults, silent-failure]
applies_when: a script finds files, log entries or receipts by a commit sha and a later step in the same flow makes a commit before it runs
---

## The rule

When a step reads an artifact stored under a commit's short-sha, pass the sha
the producer used. Do not default to `git rev-parse --short HEAD`. If any commit
lands between the producer and the reader, HEAD has moved on, the lookup finds
an empty directory, and the reader reports "nothing to do" as if that were a
real result.

## Where it bit

`publish_evidence.py` first defaulted `--sha` to HEAD. `/wrap-up-session` runs it
from § *The Pull Request*, which comes after § *Commit and push*. By then the
PNGs under `tasks/e2e-artifacts/<walkthrough-sha>/` are keyed by an older sha,
so the publisher would print `evidence: none` and every later re-sync would
empty the PR section. The fixture tests passed because nothing committed between
the walkthrough and the publish. The dispatched APOSD review caught it, not the
tests.

## The fix

`--sha` is now required (`publish_evidence.py` `main`). Wrap-up passes the
short-sha that § *E2E coverage* checked. The test commits between the walkthrough
and the publish, and asserts that a missing `--sha` is a usage error (exit 2).
Making the argument required rules out the silent HEAD guess entirely, rather
than detecting it after the fact.
