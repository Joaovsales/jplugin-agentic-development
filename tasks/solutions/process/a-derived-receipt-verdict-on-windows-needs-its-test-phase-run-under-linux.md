---
title: A derived receipt verdict on Windows needs its test phase run under Linux
date: 2026-10-21
problem_type: process
module: .agents/skills/quality-gate/scripts/receipt.py § derive_verdict; /quality-gate phase 5
tags: [quality-receipt, windows, wsl, baseline-failures, tests, verdict]
applies_when: /quality-gate phase 5 (or wrap-up § Full suite) runs on this Windows machine and the affected or full test set includes files already in the Windows failure baseline
---

> **Correction (2026-10-21).** Since `specs/test-suite-aposd.md` D2 landed
> (#345, in the #336–#347 build), the Windows run itself exits 0: every known
> Windows-only failure is a row of `tests/expected-failures.txt`, `tests/lib.sh`
> prints `XFAIL` for it and `tests/run.sh` reports `0 failed`, so the recipe
> below is no longer needed to get a green `tests.exit` on this machine — the
> 2026-10-21 gate ran `bash tests/affected.sh --run <base>` on Windows (91 files,
> 6885 passed, 0 failed, 289 xfail, 2218 s with `TEST_JOBS=6
> TEST_FILE_TIMEOUT=10800`) and minted its receipt from that. The WSL recipe
> still serves two purposes: proving a Linux-only behaviour, and checking a new
> failure that is *not* a baseline row before adding one.
>
> Two facts about that Windows run. (1) When `tests/lib.sh`, `run.sh` or
> `affected.sh` changed, `tests/affected.sh` prints every test file
> (`tests/affected.sh:70`), so the gate's Phase 5 is the whole suite — under a
> different cache key than the wrap-up's `bash tests/run.sh`
> (`.agents/skills/build/scripts/cached-suite.sh:109-115` keys on the verbatim
> command plus `uname -s`, the Python version and `gh` presence), so Windows
> pays both runs. (2) Some rows are host-state rows, not platform rows: the
> `test-task-registry-config.sh` "Selection" group depends on the host's
> `gh auth status` (the mock `gh` is unreachable from Python on Windows, #129).
> The shipped rows were captured with `gh` logged in and the group comment says
> so; a host in the other state flips four of them to `XPASS` and three others
> to `FAIL`, the run goes red, `receipt.py write` mints `STOP`, and
> `receipt.py check` then says `stale missing` (a STOP receipt is no parent), so
> the sequence is: mint the red receipt, reconcile the rows under the gh-auth
> comment, re-run Phase 5 at full scope, mint again. Check `gh auth status`
> against that comment **before** Phase 5 and reconcile first.
>
> **Update (2026-10-22).** The gh-auth rows are gone from the baseline. A second
> Windows Phase 5 run went red in the logged-out pattern while `gh auth status`
> said logged in before and after — under a 95-minute load `gh`'s network check
> itself failed — which proves the point: a row whose outcome follows host state
> cannot be a baseline row in either direction. `tests/test-task-registry-config.sh`
> now probes whether a Python-launched `gh --version` leaves the mock's log and
> `skip`s the fifteen github selection rows when it does not (8fb5bf9); the eight
> config rows left `tests/expected-failures.txt` (289 → 281). Linux reaches the
> mock and runs them. The rule: a platform cause → a baseline row; a host-state
> cause → a runtime probe and `skip`.

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

Confirmed again on 2026-10-16 (HyperFrames build): without the wrapper the
same control assertion was the one failure in 40 affected files; with
`/var/tmp/bin/gh` on PATH and `TEST_JOBS=6` the 40 files passed in about 50 s.
Write the wrapper through a file piped into `wsl -- bash -c 'cat > …'`: a
`printf` from the Bash tool loses the `"$@"` and Git Bash expands `$PATH`
on the Windows side. See also
[cached-suite-keys-on-the-verbatim-command-so-parallelism-comes-from-the-environment](../tooling/cached-suite-keys-on-the-verbatim-command-so-parallelism-comes-from-the-environment.md).

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

Confirmed again on 2026-10-14 (#168). On Windows, 6/22 affected files failed,
104 assertions, every one also failing at the base. A WSL clone at the same tree
passed 22/22 in 76 s, against about 40 minutes on Windows. `receipt.py` stores
the `tests` object as given (`receipt.py:388`), so that session's outcome
recorded the WSL exit and kept the Windows run next to it as `host`,
`windows_exit` and `windows_note`. The receipt shows both runs and never hides
the Windows exit.
