---
title: design-stack setup cannot launch bare npx on Windows
date: 2026-10-08
problem_type: bug
module: .agents/skills/design-stack/scripts/design_stack.py
tags: [design-stack, windows, subprocess, npx]
symptoms: "`design_stack.py setup` reported `SetupRequired: [WinError 2] The system cannot find the file specified` on a Windows host with Node installed"
root_cause: "`run()` hands `subprocess.run` the bare name `npx` (default of `DESIGN_STACK_NPX`) without a shell; on Windows the executable is `npx.cmd`, which CreateProcess does not resolve from a bare name"
resolution: "`run()` resolves the command with `shutil.which` before running it, falling back to the raw name so a missing tool still fails explicitly. Pre-fix workaround: `DESIGN_STACK_NPX=npx.cmd`"
---

**Status**: fixed — 2026-10-09 (PR #272)
**Regression test**: `tests/test-design-stack-install.sh` § executable resolution
