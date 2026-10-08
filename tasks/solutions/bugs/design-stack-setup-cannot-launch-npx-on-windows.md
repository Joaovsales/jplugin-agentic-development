---
title: design-stack setup cannot launch bare npx on Windows
date: 2026-10-08
problem_type: bug
module: .agents/skills/design-stack/scripts/design_stack.py
tags: [design-stack, windows, subprocess, npx]
symptoms: "`design_stack.py setup` reported `SetupRequired: [WinError 2] The system cannot find the file specified` on a Windows host with Node installed"
root_cause: "`run()` hands `subprocess.run` the bare name `npx` (default of `DESIGN_STACK_NPX`) without a shell; on Windows the executable is `npx.cmd`, which CreateProcess does not resolve from a bare name"
resolution: "Open. Workaround verified 2026-10-08: `DESIGN_STACK_NPX=npx.cmd design_stack.py setup` installs release 7975901f. Fix: resolve the command with `shutil.which` before running it"
---

**Status**: open — suggested as a follow-up task from the readable-visual-plans build session (2026-10-08).
**Regression test**: none yet — belongs in `tests/test-design-stack-install.sh`.
