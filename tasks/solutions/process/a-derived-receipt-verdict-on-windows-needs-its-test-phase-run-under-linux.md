---
title: A derived receipt verdict on Windows needs its test phase run under Linux
date: 2026-09-23
problem_type: process
module: .agents/skills/quality-gate/scripts/receipt.py § derive_verdict; /quality-gate phase 5
tags: [quality-receipt, windows, wsl, baseline-failures, tests, verdict]
applies_when: /quality-gate phase 5 (or wrap-up Step 6) runs on this Windows machine and the affected or full test set includes files already in the Windows failure baseline
---

`receipt.py` derives the verdict from the recorded test exit and never accepts a
verdict as input. Any non-zero `tests.exit` is `STOP`
(`.agents/skills/quality-gate/scripts/receipt.py:342`). On this Windows machine,
several test files (task-registry, routine-selectors and others: cp1252 output,
and a `gh` mock that Python never reaches) are already in the failure baseline.
Any change whose affected set touches them therefore mints a `STOP` receipt, even
when no failure is new. The 2026-09-23 session (#163) saw 104 failing assertions,
all of them baseline failures, and `STOP` as the result.

Do not fake the exit code. Record the Windows run as it was, then run the same
command under WSL Ubuntu from a clean clone checked out at the reviewed commit.
The clone's `HEAD^{tree}` equals the tree hash `receipt.py fingerprint` measured
on Windows whenever the Windows working tree is clean, so `tests.tree` still
matches the receipt. In that session, 31 affected files passed in 63 s under
WSL, where they had failed on Windows.

Invoking WSL from the Bash tool (Git Bash) has two traps:
- Set `MSYS_NO_PATHCONV=1`. Without it, Git Bash rewrites `/mnt/c/...` to
  `C:/Program Files/Git/mnt/c/...` and `wsl.exe` exits 127.
- Use the long path (`/mnt/c/Users/Joao.Souto/...`). WSL does not resolve the
  8.3 short name the scratchpad path carries (`JOAO~1.SOU`).

Put the script in a file, strip CR with `sed 's/\r$//'`, and write its log back
to a `/mnt/c` path the Windows side can read.

Related: [../bugs/test-python-shim-execd-itself-on-linux-and-hung-ci.md](../bugs/test-python-shim-execd-itself-on-linux-and-hung-ci.md)
(the same WSL reproduction recipe).
