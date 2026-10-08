---
title: A derived receipt verdict on Windows needs its test phase run under Linux
date: 2026-09-23
problem_type: process
module: .agents/skills/quality-gate/scripts/receipt.py § derive_verdict; /quality-gate phase 5
tags: [quality-receipt, windows, wsl, baseline-failures, tests, verdict]
applies_when: /quality-gate phase 5 (or wrap-up § Full suite) runs on this Windows machine and the affected or full test set includes files already in the Windows failure baseline
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

WSL Ubuntu has no `gh`, and CI does. Without one,
`tests/test-lane-catalogue.sh` "AC4 control: workflow's failure is the
provider's" fails, on master too (2026-09-28): the provider's error names the
missing binary, not `no repository configured`. Put a two-line wrapper on PATH
that execs the real Windows binary, `/mnt/c/Program Files/GitHub CLI/gh.exe`.
With it, the same clean clone ran 44/44 affected and 60/60 full.

Confirmed again on 2026-10-06 (lane-plan-handover). The Windows affected run
failed 166 assertions, all also failing on the base SHA, and minted `STOP`. A
WSL clone fetched from the local repository path at the same tree passed
37/37. Fetching from the local path needs no push, so this check never has to
publish the branch before the gate.

Related: [../bugs/test-python-shim-execd-itself-on-linux-and-hung-ci.md](../bugs/test-python-shim-execd-itself-on-linux-and-hung-ci.md)
(the same WSL reproduction recipe).

Confirmed again on 2026-10-08 (readable-visual-plans). The Windows affected run had
9/38 files failing, every one in the base baseline, and minted `STOP`. A WSL clone at
the same tree (`99744b0`) failed only lane-catalogue AC4 without `gh`, and passed
38/38 in 83 s with the `gh` wrapper. Run the WSL check *before* writing the receipt:
re-minting a receipt over an existing one was refused as audit tampering by the
auto-mode classifier, so the first `write` is the one that stands.
