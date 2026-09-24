---
title: PPID is 1 on Windows so a PPID-keyed session guard collapses to one constant
date: 2026-08-18
problem_type: bug
module: .agents/hooks/session-start.sh (formerly .claude/hooks/session-start.sh; moved in the #156 surface retirement)
tags: [windows, hooks, session-start, guard, ppid]
symptoms: "Start Claude Code in repo A, then in repo B within five minutes, and repo B's session prints NO session-start banner at all — no learning-store counts, no active tasks, no git status. Observable on disk as a single shared sentinel `$TMPDIR/.ccw-session-start-1-<source>` instead of one per session."
root_cause: "The double-invocation guard fell back to `GUARD_KEY=${GUARD_KEY:-$PPID}` whenever `jq` was absent or the payload carried no `session_id`. On Windows, bash spawned from a native Windows parent (node, python) reports `PPID=1`, so the key collapsed to the constant `1-<source>` and every session in every repo shared one sentinel. The 5-minute freshness window then made the first session suppress the next one."
resolution: "Parse `session_id` out of the hook payload with `sed` (dropping the `jq` requirement entirely, as the `source` field already did), and when it is absent fall back to a `cksum` hash of `$PWD` instead of `$PPID`. Pinned by seven assertions in tests/test-session-start.sh."
---

## Symptoms

`ls $TMPDIR/.ccw-session-start-*` showed `1-startup`, `1-compact`, `1-resume` and
`1-clear` sitting among ~280 normally-keyed sentinels, with `1-startup` being
rewritten by every live session.

Reproduce the `PPID` half directly:

```
python3 -c "import subprocess;print(subprocess.run(['bash','-c','echo PPID=\$PPID'],capture_output=True,text=True).stdout)"
# PPID=1
```

## Root cause

The guard key had to be **stable within one session** (so the two registrations
collapse) and **distinct across sessions** (so one session never inherits
another's sentinel). `$PPID` satisfied neither on Windows: it was not merely
unstable, it was a constant.

`jq` is not installed on this machine, so the `session_id` branch never ran and
the fallback was the only live path.

## Resolution

Two changes, in priority order:

1. `session_id` parsed with `sed` rather than `jq`. It is the genuinely correct
   key. Removing the `jq` branch rather than preferring it leaves one
   always-exercised path instead of a fallback that runs on every machine
   without an optional binary.
2. The no-`session_id` fallback keys on `cksum` of `$PWD`. Both registrations
   share a repo so they still collapse; repos stay distinct.

## The trap inside the fix

The first cut of that fallback wrote the `cksum` pipeline with no `|| true`,
under the file's `set -eo pipefail`. A missing `cksum` therefore propagated 127
and **killed the hook at that line** -- zero output, non-zero exit -- so the
raw-path degradation the comment promised was unreachable dead code. That is a
worse silent-banner loss than the defect being fixed, and the whole suite stayed
green because the "stays silent" assertions only inspected stdout, which a crash
also leaves empty.

Two rules came out of it:

- Under `set -eo pipefail`, every fallible substitution needs its own `|| true`,
  or the fallback below it never runs. Removing an optional-binary dependency
  (`jq`) while adding a *fatal* one (`cksum`) is a net loss.
- An assertion that a program printed nothing must also assert it **exited 0**.
  Otherwise "correctly suppressed" and "crashed before printing" are the same
  observation.

## Known limitation

Two sessions started in the **same** repo within the freshness window, with no
`session_id` in the payload, still share a key. That is strictly narrower than
the constant it replaced, and only reachable on a CLI that omits `session_id`.

## Related

- The guard was inert under test for a separate reason — see
  [[command-substitution-forks-a-subshell-so-ppid-varies-per-call]].
- Not the same defect as [[codex-session-start-hook-emits-nothing]], which was
  fixed independently on master by #66 while this branch was in flight.

  Worth knowing *why* probing that one came back negative here: setting
  `CCW_SESSION_GUARD=0` alone did not make its test pass, which looked like
  evidence the guard was unrelated to it. It was not. Two defects were stacked --
  clearing the guard let the banner through, and then `print()` encoded it with
  the platform default, so cp1252 on Windows raised `UnicodeEncodeError` and
  Codex still received nothing. The second defect masked the fix for the first.
  A negative result from fixing one of two stacked causes is not evidence that
  cause was innocent.
