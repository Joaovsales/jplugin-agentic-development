---
title: task-registry select and claim refused the repository doctor had already resolved
date: 2026-09-14
problem_type: bug
module: .agents/skills/task-registry/scripts/registry/providers/github.py
tags: [task-registry, github-provider, lazy-discovery, routines, regression-test]
symptoms: In a checkout with a GitHub remote, an authenticated gh and no docs/task-tracking.md, `doctor` reported the provider reachable while `select`, `claim` and `workflow` exited 1 with "github: no repository configured"
root_cause: GitHubProvider populated `self.repository` from `gh repo view` only inside `discover()`, and the routine commands call `known_labels()`, `list_tasks()` and `update_task()` without ever running `discover()`, so `_repo()` raised on an empty field that only the diagnostic command knew how to fill
resolution: `_repo()` now performs the `gh repo view` discovery itself on first use and caches the answer; `discover()` calls `_repo()` instead of carrying its own copy, so every read and write resolves the repository through one path
---

**Status**: fixed — 2026-09-14
**Regression test**: `tests/test-task-registry.sh` — the `Selection (#124)` assertions (select and workflow on a remote-resolved provider with no `repository =` line)

Issue #124. Observed live in the 2026-09-10 `fix` and `improve` routine runs on a
downstream project, where the routine exited without claiming anything because
`select` refused on the first `gh` call.

## Investigation

**Reproduction (Level 1).** A temp repo with `git remote add origin <github url>`,
no configuration file, and the real authenticated `gh`: `doctor` printed
`reachable: yes — gh authenticated for <owner/repo>`, then `select --routine fix`
exited 1 with the `_repo()` message verbatim.

**Discriminator (Level 1).** `show '#124'` succeeded on the same checkout. `show`
reaches the provider through `Registry.external_tasks` (`registry/detail.py:77`),
which calls `discover()` before `list_tasks()`; `select` reaches
`known_labels()` from `_upstream_verdict` (`task-registry.py:688`) with no
`discover()` in between. Same provider object, primed vs unprimed, was the only
difference — which pinned the fault to the population path rather than to
`gh label list`, auth scope, or the selector vocabulary.

**Candidate not taken.** `select_provider` (`registry/config.py:795-800`) learns
`owner/repo` from `git remote -v` and discards it into the reason string, so the
provider is constructed blind (`github.py:86`). Threading that value into the
provider would also have fixed the symptom, but it changes semantics: `gh repo view`
honours `gh repo set-default` on multi-remote checkouts, and the first `github.com`
line of `git remote -v` does not. Keeping `doctor` and the routine commands on the
same `gh repo view` lookup was the fix that did not widen behaviour.

## Fix shape

`discover()` had the lookup and `_repo()` had the refusal. The lookup moved into
`_repo()`, `discover()` now calls `_repo()` and maps its two failure classes
(`ProviderUnavailable` for a missing `gh`, `ProviderError` for a `gh repo view`
that cannot name a repository) onto the same `ProviderStatus` lines it always
reported. The refusal text now also quotes what `gh repo view` answered, so
"or run inside a repo with a GitHub remote" is a true statement of the fallback.

## Verification note

The regression assertions run through the `tests/fixtures/task-registry/gh` mock.
On Windows Git Bash with native Python that mock is unreachable — `subprocess.run`
resolves `gh` through `PATHEXT` and finds the real `gh.exe`, so the fixture's
`GH_MOCK_UNAUTH` assertions fail before the fix and after it (part of the #129
set). The fix was proved live against the real `gh` on Windows and by the Linux
suite in CI.

Related pattern: [Validate in the loader, not in one optional command](../patterns/validate-in-the-loader-not-in-one-optional-command.md)
— a step that only the diagnostic command performs protects nothing that runs
unattended; here it was identity resolution rather than validation, but the shape
is the same.
