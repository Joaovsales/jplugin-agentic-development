---
title: pre-push force-push guard never fires
date: 2026-09-02
problem_type: bug
module: .agents/git-hooks/pre-push
tags: [git-hooks, dead-code, pre-push, force-push]
symptoms: A force push proceeds with no warning even when ALLOW_FORCE_PUSH is unset
root_cause: The hook scans "$@" for --force, but git invokes pre-push with only <remote-name> <remote-url>; push flags are never passed to the hook
resolution: none yet — recorded open. Detecting a force push requires inferring a non-fast-forward pair from the stdin ref list, a different mechanism deliberately left out of this change
date_source: session
---

## pre-push force-push guard never fires

Status: **open** — recorded, deliberately not fixed in this change.

`.agents/git-hooks/pre-push:13-20` scans `"$@"` for `--force` / `-f` and blocks
unless `ALLOW_FORCE_PUSH=1`. Git invokes the hook as
`pre-push <remote-name> <remote-url>` and passes no push flags at all, so the
loop has never matched and the guard has never fired.

**Root cause:** the hook was written as though it wrapped the `git push` command
line. It does not. Git's hook contract gives a pre-push hook two positional
arguments and the ref list on stdin; the user's flags are not part of it.

**Why it stayed invisible:** no test covered this hook until
`tests/test-pre-push-gate.sh` was added, and a guard that silently never
triggers looks identical to a guard that is never provoked.

**Detecting a force push at all** requires inferring it from the stdin ref
lines — a non-fast-forward local→remote pair — not from argv. That is a
different mechanism with its own blast radius, so it was left out of the wrap-up
gate change rather than bolted on.

Related: [[a-gate-that-ships-into-a-template-dir-never-reaches-existing-repos]]
