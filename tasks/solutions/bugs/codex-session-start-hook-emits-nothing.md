---
title: Codex SessionStart hook emits nothing so its JSON assertion fails
date: 2026-08-17
problem_type: test-failure
module: codex/hooks/session_start.py
tags: [codex, hooks, tests, windows, encoding]
symptoms: "tests/test-codex-install.sh — 1/22 assertions FAILED: `hook: SessionStart output validates as Codex JSON`, with a JSONDecodeError at line 1 column 1 (char 0), i.e. the hook produced no stdout at all"
root_cause: "Two stacked defects in the Codex adapter, both Windows-only. (1) The shared shell hook's double-invocation guard keys on $PPID, which is 1 for any bash spawned from a native Windows process, so every adapter invocation collides on one sentinel and all but the first in a 5-minute window exit silently. (2) With the guard out of the way, `print()` encoded the banner with the platform default (cp1252), raising UnicodeEncodeError before any JSON reached stdout."
resolution: "codex/hooks/session_start.py now passes CCW_SESSION_GUARD=0 to the shell hook (Codex registers it once, so the Claude Code de-duplication guard can only suppress) and writes the JSON as explicit UTF-8 bytes to sys.stdout.buffer instead of print()."
---

## Symptoms

`bash tests/run.sh` reported `RESULT: 1/16 test files FAILED`. The failing file
was `tests/test-codex-install.sh`; every other assertion in it passed.

The assertion pipes `{"source":"startup"}` into the installed
`$CODEX_HOME/hooks/coding-agent-workflow-session-start.py` and parses the result
as JSON. The parse failed at `char 0` — the hook wrote nothing to stdout.

Linux CI passed the full suite throughout, so the red was invisible to everyone
except Windows contributors.

## Root cause

Two independent defects, stacked so that fixing either alone leaves the test red.
The second is *masked* by the first: the guard exits before the encode is
reached, which is why the failure presented as silence rather than a traceback.

**1 — the double-invocation guard collapses onto one key.**
`.agents/hooks/session-start.sh:43-65` (formerly `.claude/hooks/session-start.sh`
before the #156 surface retirement) de-duplicates the banner for Claude Code,
which registers the hook twice (globally by `install.sh` and per-project by
`.claude/settings.json`). Without `jq` or a `session_id` it falls back to
`GUARD_KEY=${GUARD_KEY:-$PPID}` (`session-start.sh:49`).

Bash spawned from a native Windows process reports `PPID=1` — verified directly:

```
$ python3 -c "import subprocess;print(subprocess.run(['bash','-c','echo PPID=\$PPID'],capture_output=True,text=True).stdout)"
PPID=1
```

So every Codex invocation writes and reads the single sentinel
`$TMPDIR/.ccw-session-start-1-startup`, and the 5-minute freshness window at
`session-start.sh:55-63` silently `exit 0`s every run after the first. Codex
registers the hook exactly once, so the guard has nothing legitimate to suppress
there — it can only ever delete the one banner that exists.

This also explains why the failure looked non-deterministic: on a machine with no
recent sentinel the first run got through, and every run for the next five
minutes did not.

**2 — `print()` encodes stdout with the platform default.**
With the guard disabled, the adapter reached its output line and raised:

```
UnicodeEncodeError: 'charmap' codec can't encode characters in position 79-118
```

The banner carries box rules, arrows and em-dashes; Python 3.13 on Windows
encodes stdout as cp1252. `ensure_ascii=False` was already set, so the JSON
string kept its non-ASCII and `print()` could not encode it.

## Resolution

Both fixed in `codex/hooks/session_start.py`:

- `subprocess.run(..., env={**os.environ, "CCW_SESSION_GUARD": "0"})` — the
  shell hook already documents that escape hatch (`session-start.sh:41`).
- `sys.stdout.buffer.write((json.dumps(...) + "\n").encode("utf-8"))` in place of
  `print()`. Chosen over setting `PYTHONIOENCODING` because it holds regardless
  of how Codex or a test invokes the adapter, rather than depending on the
  caller's environment.

The shell hook itself is unchanged: its guard is correct for the harness it was
written for.

## Verification

Each fix was mutation-probed separately against
`tests/test-codex-install.sh` — reverting either one alone reproduces
`2/23 assertions FAILED`, so neither is redundant. Full suite: 17/17 files pass
on Windows.

The test now pins both. It asserts the decoded `additionalContext` contains
non-ASCII (so a return to `print()` fails rather than passing on an
ASCII-only banner), and it invokes the adapter twice, asserting the second run
still emits (so a re-enabled guard fails deterministically instead of depending
on sentinel age).

## Related

- A second-order effect of defect 1 is *not* fixed here and remains open: on
  Windows the same `PPID=1` collapse means two Claude Code sessions started in
  different repos within five minutes share the sentinel, so the second gets no
  banner. That is a defect in the shared hook rather than the Codex adapter.
- `../process/baseline-must-precede-tree-edits.md` — the earlier session's first
  baseline run was taken while the tree was being edited and was worthless.
