---
title: Running git inside an untrusted checkout executes that repository's config
date: 2026-09-04
problem_type: security
module: .agents/skills/sync/scripts/sync-retire.py
tags: [git, command-execution, trust-boundary, untrusted-input, sync]
symptoms: A dry run that writes nothing created a sentinel file in the fixture, before any user approval and without --apply.
root_cause: git honours the inspected repository's own .git/config, and core.fsmonitor names a command git executes on ls-files. The checkout is same-uid, so safe.directory never fires.
resolution: Pin the exec-capable knobs on the command line, where -c outranks repository config, and drop system/global config from the environment.
---

## The rule

`git -C <dir> <cmd>` is not a read-only operation on `<dir>`. It is a request to
execute whatever that directory's configuration names. If `<dir>` came from
anywhere but the project itself, its config is untrusted input.

## How it showed up

`/sync` obtains a template checkout and this script inventories it. Switching the
manual-diff path from `diff -rq` to `git ls-files` introduced the sink without
introducing an obviously new capability — the diff looked like a fidelity
improvement.

Reproduced with `git config core.fsmonitor "touch …/PWNED; false"` planted in the
template. The sentinel appeared during the **Step 3 dry run**: before approval,
without `--apply`, on the code path whose entire purpose is to *preview*.

## The fix

`-c core.fsmonitor=` on the command line beats repository config, because
command-line `-c` has the highest precedence. `GIT_CONFIG_NOSYSTEM=1` and
`GIT_CONFIG_GLOBAL=/dev/null` remove the other two config layers.

Verified: `git -C tmpl ls-files` executed the payload; `git -C tmpl -c
core.fsmonitor= ls-files` did not, with identical output otherwise.

## What generalises

- A "read-only" subcommand is not safety evidence. Ask what the *config* can do.
- `safe.directory` protects against **other users'** repositories. It does nothing
  for a directory your own uid created — which is exactly what `mktemp -d` plus a
  clone produces.
- The env-var suppression is defence-in-depth *behind* the `-c` pin and is not
  independently observable once the pin is in place. A test asserting it passes
  either way; see [[../process/an-assertion-can-pass-because-a-different-guard-fired]].
