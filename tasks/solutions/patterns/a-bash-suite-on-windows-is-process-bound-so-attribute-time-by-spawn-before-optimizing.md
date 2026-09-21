---
title: A bash suite on Windows is process-bound, so attribute time by spawn before optimizing
date: 2026-09-21
problem_type: pattern
module: tests/ (bash test suite), tests/run.sh, tests/lib.sh
tags: [tests, windows, performance, xtrace, process-spawn, bash-builtins]
applies_when: a bash test file or suite is slow on Windows (Git Bash) and you are about to guess which command is to blame
---

## The rule

On Windows every process a shell script starts costs 100–500 ms — `mkdir`,
`dirname`, `cat`, a `$(...)` subshell — and a Python launcher 0.7–1.5 s. Do
not optimize the command that *looks* expensive. Trace the file with a
timestamped xtrace, sum the gaps by command word, and fix the top of that list.

## The recipe

```bash
bash -c 'exec 9>trace.txt; export BASH_XTRACEFD=9
         export PS4="+${EPOCHREALTIME} ${LINENO} "
         bash -x tests/test-slow.sh </dev/null >run.out 2>&1'
```

Each trace line is `+<epoch.micros> <line> <command>`; the gap to the next line
is the command's cost. Group by the command word and by the test line. Bash
buffers the trace fd, so read it after the run exits.

## What it showed on #136

`tests/test-sync-retirement.sh` took 1275 s alone. The issue, and the first
instinct, blamed the Microsoft Store `python3`. The trace:

| Command | Share | Calls | Per call |
|---|---|---|---|
| git | 26 % | 567 | 469 ms |
| mkdir | 25 % | 1160 | 220 ms |
| python3 | 20 % | 124 | 1703 ms (including the script's own work) |
| dirname | 11 % | 867 | 127 ms |
| `$(...)` fork for dirname | 8 % | 865 | 92 ms |
| cat | 4 % | 230 | 165 ms |

Swapping the interpreter (0.4 s launcher delta × 124) would have saved 5 %.
One helper line — `_f() { mkdir -p "$(dirname "$1")"; printf ... > "$1"; }`,
called ~900 times — was a third of the file. Per-section times were uniform
(15–100 s), so there was no pathological section either: the shape of the
helper was the whole story.

## Builtins that replace a process

| Instead of | Use | Notes |
|---|---|---|
| `mkdir -p "$(dirname "$p")"` | `[ -d "${p%/*}" ] || mkdir -p "${p%/*}"` | guard `case "$p" in */*)` for bare names |
| `$(cat a)` | `$(<a)` | identical, including trailing-newline stripping |
| `$(cat a; cat b)` | `$(cat a b)`, or `$(<a)` when `[ -s b ]` is false | `$(<a)$(<b)` is **not** identical: it strips a's trailing newlines |
| `git -C r config user.name x` ×2 | `printf '[user]\n    name = x\n    email = y\n' >> r/.git/config` | same lines git would write |
| a `while read` loop calling `sha256sum` per file | `find … -print0 \| sort -z \| xargs -0 sha256sum` | when only equality between two runs matters |
| N × `mkdir -p dir_i` | one `mkdir -p dir_1 … dir_N` | pre-create in the fixture builder |

Check exact semantics before each swap: two assertions in that file count
lines after the first, so a capture that drops one blank line changes their
meaning.

## Related

- [[windows-suite-takes-20-to-38-minutes-because-every-process-spawn-costs-over-a-second]] — the bug this was learned on
- [[a-slow-test-is-not-a-hung-test]] — time the files first; `tests/run.sh` now prints that timing itself
- [[claude-code-bash-tool-collapses-backslash-escapes]] — patching these files from the Bash tool: write backslashes via a placeholder
