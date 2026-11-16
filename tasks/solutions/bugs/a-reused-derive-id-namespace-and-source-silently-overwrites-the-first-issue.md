---
title: A reused derive-id namespace and source silently overwrites the first issue
date: 2026-11-16
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/upsert.py — derive_id; task-registry.py --derive-id/--fold-title
tags: [task-registry, upsert, derive-id, idempotence, github-issues]
symptoms: "Filing a second, distinct issue with `--derive-id` and the same namespace and `--source` as an existing one created no new number and gave no warning. Issue #417 was retitled and its body replaced mid-session (its timeline shows the rename)"
root_cause: "`derive_id(namespace, path, title='')` (upsert.py:105) mints the id from the namespace and path alone unless `--fold-title` is passed. The same inputs give the same id, and upsert is designed to update in place, so the second filing counts as an edit of the first"
resolution: "Workaround, no code change: pass `--fold-title` whenever more than one finding can be filed against the same source path, or pass a distinct explicit id. Before filing, `task-registry.py show <derived id>` reveals an existing record"
---

## What happened

On 2026-11-15/16 a coordinator filed a second issue whose `--source` was
`tests/test-plugin-manifest.sh`, the same path #417 was filed under
(`task-id: bug.tests-test-plugin-manifest-sh`). The id matched #417's, so
upsert updated #417 instead of creating a new issue. There was no warning
and no new issue number. #417's old title ("Plugin version guard fails after
merging master…") was replaced.

## Why it is silent

This is the idempotence the registry promises: running the same upsert
twice must not create two tasks (`derive_id` docstring, upsert.py:106-120).
The registry cannot tell "the same task re-filed" apart from "a different
task about the same file". `--fold-title` (task-registry.py:165-170) exists
for exactly that second case.

## Prevention

- Use `--fold-title` for any namespace that can carry more than one finding
  per path, such as bugs and sweep findings.
- Run `show` on the derived id before an `--apply` that is meant to create a
  new issue.
