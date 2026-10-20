---
title: A root container passes permission-denial tests vacuously, so run the suite unprivileged
date: 2026-10-19
problem_type: process
module: tests/run.sh, tests/affected.sh, .agents/skills/build/scripts/cached-suite.sh; /quality-gate phase 5; /wrap-up-session § Full suite
tags: [root, container, test-environment, cached-suite, quality-receipt, runuser]
applies_when: the suite or the quality gate's test phase runs in a cloud container as uid 0 (Claude Code on the web, CI images that run as root), and the baseline shows failures in tests that rely on a file being unreadable, undeletable or unprunable
---

## The claim

Three test files in this repository assert a *failure* path that only exists
when the kernel refuses an operation: an unreadable spec must not report
success (`tests/test-task-registry.sh`), a locked file must survive a deletion
sweep and be named (`tests/test-sync-retirement.sh`), a directory that cannot be
pruned must be counted (`tests/test-sync-retirement.sh`). Root bypasses
`chmod 000`, so as uid 0 every one of those operations succeeds and the
assertions fail — eleven of them in the 2026-10-19 baseline. The code under
test is correct; the environment cannot express the input.

Two more environment artefacts came with the same container: a shallow clone
(51 commits) hid the retired-skill names `install.sh` reads from history, and a
slow-reaping PID 1 made the drift checker's process-tree assertion flaky
([bugs/kill-0-counts-a-zombie-as-alive-under-a-slow-reaping-pid-1.md](../bugs/kill-0-counts-a-zombie-as-alive-under-a-slow-reaping-pid-1.md)).

## The rule

Make the environment honest instead of recording a red receipt for code that
is green:

1. `git fetch --unshallow origin` — history-reading tests need the history.
2. Run the test command as an unprivileged user through the same cache
   wrapper, so the record the next skill reuses carries the verbatim command:

   ```bash
   git config --system --add safe.directory '*'   # the repo is root-owned; the sandbox HOME never sees a user config
   chmod -R a+rwX .git/objects .git/cached-suite   # write-tree writes blobs; the cache writes its record and lock
   runuser -u nobody -- env HOME=/tmp/nobody-home PYTHONDONTWRITEBYTECODE=1 \
     .agents/skills/build/scripts/cached-suite.sh -- bash tests/affected.sh --run <base>
   ```

   Pass the proxy and CA variables through when a test is network-gated;
   this session's proxy credentials lived under `/root`, so the network case
   printed its `note` and skipped under `nobody` and ran as root.
3. The cache key is the tree plus the command, not the user, so
   `/wrap-up-session`'s root invocation of the same command prints
   `cached-suite: reused green run` once the unprivileged run was green.

## The consequence of ignoring it

`receipt.py` turns any non-zero `tests.exit` into `STOP` (its `derive_verdict`),
and wrap-up refuses to push on a STOP receipt — the build's deliverable stalls
on failures that have nothing to do with the diff. The sibling document for the
Windows machine,
[a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md](a-derived-receipt-verdict-on-windows-needs-its-test-phase-run-under-linux.md),
reaches the same conclusion from the other side: the receipt's test phase runs
where the tests' assumptions hold, and the record says where that was.
