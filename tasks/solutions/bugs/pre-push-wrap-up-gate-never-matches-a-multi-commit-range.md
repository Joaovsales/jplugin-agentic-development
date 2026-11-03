---
title: pre-push wrap-up gate never matches a multi-commit covered range
date: 2026-10-21
problem_type: bug
module: .agents/git-hooks/pre-push
tags: [git-hooks, pre-push, wrap-up-gate, posix-sh, case-pattern, false-positive]
symptoms: Every push carrying two or more code commits printed WRAP-UP GAP and wrote tasks/wrap-up-debt.md even when a valid `## Session Summary — <date> [a..b]` range in the committed tasks/todo.md covered all of them; the fingerprint parsed fine
root_cause: The covered list was built from `git rev-list` output, which is newline-separated, but membership was tested with `case " $_covered " in *" $_c "*)`; a `case` word is not field-split, so the newlines survived and the space-on-both-sides pattern matched nothing but the first entry
resolution: Test membership by word-splitting the covered list — `for _k in $_covered; do [ "$_k" = "$_c" ] && continue 2; done` (.agents/git-hooks/pre-push:141) — so spaces and newlines both delimit and no producer has to know the delimiter. Regression test — a range of three code commits must be silent — in tests/test-pre-push-gate.sh § Covered range of several commits
---

## Symptoms

Reported from the downstream project `Joaovsales/personal-website` on 2026-10-20:
a push of 30 commits on `build/mvp-launch` with a valid
`## Session Summary — 2026-10-20 [a81cfb6..b585166]` in the committed
`tasks/todo.md` had every code commit inside that range reported as uncovered
and a ledger entry `## build/mvp-launch 4114736..b585166` written. The
fingerprint grep returned `[a81cfb6..b585166]`; only the coverage test failed.

## Root cause

`.agents/git-hooks/pre-push` appended `$(git rev-list "$_start..$_end")` to the
covered list and tested membership with
`case " $_covered " in *" $_c "*) continue ;; esac`. Two shell facts collide:

1. `git rev-list` prints one SHA per line. A command substitution strips only
   the *trailing* newlines, so a one-commit range yields a bare SHA and a range
   of two or more keeps interior newlines.
2. The word of a `case` statement is never field-split. The pattern
   `*" $_c "*` needs a space on both sides of the SHA, and a SHA bounded by a
   newline never matches.

The existing "Covered" test used a one-commit range, so the list format was
never exercised, and the gate looked correct while covering nothing in
practice.

## Resolution

The membership test word-splits the covered list instead of pattern-matching
the whole string: `for _k in $_covered; do [ "$_k" = "$_c" ] && continue 2; done`.
An unquoted expansion splits on spaces and newlines alike, so the producer no
longer has to know the delimiter and a later append from another
newline-emitting git command cannot bring the bug back. The first draft fixed
the producer (`| tr '\n' ' '` on the rev-list output); the design review asked
for the consumer-side fix, which removes the implicit contract rather than
documenting it.

`printf '%s\n' $_covered | grep -qxF "$_c"` was rejected: under
`set -o pipefail` a `grep -q` that exits on its first match can hand the
pipeline printf's SIGPIPE status once the list outgrows the pipe buffer, which
would be the same silent false positive back, now load-dependent.

The regression test builds a fixture with three code commits under one summary
range and asserts the hook prints nothing and writes no ledger.

The same change teaches the hook that a bracket group holding a date
(`[YYYY-MM-DD]`, the heading form `/wrap-up-session` documents) is not a
fingerprint, so it is skipped instead of being named as unparseable on every
push.

## Prevention

When a list is assembled from command output and consumed by a `case` pattern
or a string comparison, write a test whose list has at least two entries: the
one-entry case is indistinguishable from a correctly delimited list. Make the
consumer whitespace-agnostic (word-split the list) rather than fixing the
delimiter at each producer.

Related: [[pre-push-force-guard-never-fires]],
[[a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos]]
